import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/ventas_datos.dart';
import 'theme/si_theme.dart';
import 'ventas_comun.dart';
import 'ventas_drive_panel.dart';

/// Cómo se comporta Sisol: su personalidad, los mensajes fijos, los límites y el interruptor que
/// apaga el chat público.
///
/// Los valores viven en `ventas_config` (clave → valor). Una clave sin fila usa el predeterminado,
/// que está en el CÓDIGO del Worker y se pide a `/api/ventas/config-meta`: así el texto de
/// «Restaurar» es siempre el que de verdad corre, y no una copia que se quede atrás.
class VentasConfigPage extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;
  const VentasConfigPage({super.key, required this.role, required this.permissions});

  @override
  State<VentasConfigPage> createState() => _VentasConfigPageState();
}

/// Las tarjetas y qué claves lleva cada una. Una clave que el Worker devuelva y no esté aquí se
/// pinta en «Otros», para que ninguna se quede sin poder editarse (le pasó a
/// `recordatorio_datos_incompletos` en el panel anterior).
const _grupos = <(String, String, List<String>)>[
  ('Personalidad del agente', 'Las instrucciones de Sisol, sin la base de conocimiento.', ['prompt_personalidad']),
  (
    'Mensajes del sistema',
    'Los recordatorios se pegan al último mensaje del cliente; el cliente no los ve.',
    ['mensaje_fin', 'mensaje_solo_ventas', 'recordatorio', 'recordatorio_datos_incompletos', 'recordatorio_lead', 'recordatorio_post_lead'],
  ),
  ('Límites de la conversación', 'Topes para que una plática no se alargue sin fin ni gaste de más.', ['max_mensajes_cliente', 'max_chars_mensaje', 'max_tokens']),
];

class _VentasConfigPageState extends State<VentasConfigPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _meta = [];
  Map<String, dynamic> _agente = {};
  Map<String, Map<String, dynamic>> _guardado = {};
  final _campos = <String, TextEditingController>{};
  bool _cargando = true;
  String? _error;
  bool? _chatActivo;
  String? _guardandoGrupo;

  bool get _puedeEditar => puedeEditarVentas(widget.role, widget.permissions);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final t in _campos.values) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final filas = await _supabase.from('ventas_config').select('clave, valor, actualizado_en');
      final guardado = {for (final f in filas as List) '${f['clave']}': Map<String, dynamic>.from(f)};
      if (!mounted) return;
      setState(() {
        _guardado = guardado;
        _chatActivo = guardado['chat_detenido']?['valor'] != '1';
      });
      final r = await SisolApi.configMeta();
      final meta = r.config;
      if (!mounted) return;
      setState(() {
        _meta = meta;
        _agente = r.agente;
        for (final m in meta) {
          final clave = '${m['clave']}';
          (_campos[clave] ??= TextEditingController()).text =
              '${guardado[clave]?['valor'] ?? m['predeterminado'] ?? ''}';
        }
      });
    } catch (e) {
      debugPrint('Error cargando configuración de Sisol: $e');
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cambiarChat(bool activo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(activo ? 'Reactivar el chat' : 'Detener el chat'),
        content: Text(activo
            ? 'Sisol vuelve a contestar en sisol.com.mx.'
            : 'Los visitantes de sisol.com.mx verán «El chat no está disponible en este momento» '
                'hasta que lo reactives. Úsalo si ves abuso o respuestas equivocadas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(activo ? 'Reactivar' : 'Detener')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supabase.from('ventas_config').upsert({'clave': 'chat_detenido', 'valor': activo ? '0' : '1'});
      if (!mounted) return;
      setState(() => _chatActivo = activo);
      avisoVentas(context, activo ? 'Chat reactivado.' : 'Chat detenido.');
    } catch (e) {
      if (mounted) avisoVentas(context, 'No se pudo cambiar: $e', error: true);
    }
  }

  Map<String, dynamic>? _metaDe(String clave) => _meta.where((m) => m['clave'] == clave).firstOrNull;

  Future<void> _guardar(String grupo, List<String> claves) async {
    final filas = <Map<String, dynamic>>[];
    for (final k in claves) {
      final m = _metaDe(k);
      final v = _campos[k]?.text.trim() ?? '';
      if (m == null) continue;
      if (v.isEmpty) {
        avisoVentas(context, '«${m['label']}» no puede quedar vacío.', error: true);
        return;
      }
      if (m['tipo'] == 'numero' && (int.tryParse(v) ?? 0) <= 0) {
        avisoVentas(context, '«${m['label']}» tiene que ser un número mayor que cero.', error: true);
        return;
      }
      // Igual al predeterminado y sin fila: no se escribe, para que siga el del código si cambia.
      if (v == '${m['predeterminado']}' && !_guardado.containsKey(k)) continue;
      filas.add({'clave': k, 'valor': v});
    }
    setState(() => _guardandoGrupo = grupo);
    try {
      if (filas.isNotEmpty) await _supabase.from('ventas_config').upsert(filas);
      if (mounted) avisoVentas(context, 'Guardado. Sisol lo usa desde el siguiente mensaje.');
      await _cargar();
    } catch (e) {
      if (mounted) avisoVentas(context, 'No se pudo guardar: $e', error: true);
    } finally {
      if (mounted) setState(() => _guardandoGrupo = null);
    }
  }

  Future<void> _restaurar(String grupo, List<String> claves) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Restaurar «$grupo»'),
        content: const Text('Se borran los textos personalizados de esta tarjeta y vuelven los del código.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supabase.from('ventas_config').delete().inFilter('clave', claves);
      await _cargar();
    } catch (e) {
      if (mounted) avisoVentas(context, 'No se pudo restaurar: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    if (_cargando && _meta.isEmpty) return const Center(child: CircularProgressIndicator());

    final enGrupos = _grupos.expand((g) => g.$3).toSet();
    final otros = [for (final m in _meta) if (!enGrupos.contains(m['clave'])) '${m['clave']}'];

    return Scaffold(
      backgroundColor: c.bg,
      body: ListView(
        padding: const EdgeInsets.all(SiSpace.x5),
        children: [
          _interruptor(c),
          const SizedBox(height: SiSpace.x5),
          if (_agente.isNotEmpty) ...[
            _resumen(c),
            const SizedBox(height: SiSpace.x5),
          ],
          // Arriba de los textos: es lo que Sisol sabe de los desarrollos, y lo que más se actualiza.
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: SiSpace.x5),
              padding: const EdgeInsets.all(SiSpace.x4),
              decoration: BoxDecoration(color: c.dangerTint, borderRadius: SiRadius.rLg),
              child: Row(children: [
                Expanded(
                  child: Text('No se pudo leer la configuración de Sisol: $_error',
                      style: TextStyle(color: c.danger)),
                ),
                TextButton(onPressed: _cargar, child: const Text('Reintentar')),
              ]),
            ),
          // Dos columnas: a todo lo ancho, los cuadros de texto quedaban de una sola línea larguísima
          // (pedido del usuario el 24/09/2026). Se reparten para que las dos midan parecido: el Drive
          // y la personalidad a la izquierda, los mensajes —seis cuadros— y los límites a la derecha.
          LayoutBuilder(builder: (_, caja) {
            final izquierda = <Widget>[
              VentasDrivePanel(puedeActualizar: _puedeEditar),
              _tarjeta(c, _grupos[0].$1, _grupos[0].$2, _grupos[0].$3),
            ];
            final derecha = <Widget>[
              for (final g in _grupos.skip(1)) _tarjeta(c, g.$1, g.$2, g.$3),
              if (otros.isNotEmpty) _tarjeta(c, 'Otros', '', otros),
            ];
            if (caja.maxWidth < 900) return Column(children: [...izquierda, ...derecha]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(children: izquierda)),
              const SizedBox(width: SiSpace.x4),
              Expanded(child: Column(children: derecha)),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _interruptor(SiColors c) {
    final activo = _chatActivo ?? true;
    return Container(
      padding: const EdgeInsets.all(SiSpace.x4),
      decoration: BoxDecoration(
        color: activo ? c.successTint : c.dangerTint,
        borderRadius: SiRadius.rLg,
      ),
      child: Row(children: [
        Icon(activo ? Icons.check_circle_outline : Icons.pause_circle_outline, color: activo ? c.success : c.danger),
        const SizedBox(width: SiSpace.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(activo ? 'El chat está activo en sisol.com.mx' : 'El chat está DETENIDO',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(activo ? 'Sisol contesta a los visitantes.' : 'Los visitantes ven un aviso de «no disponible».',
                style: TextStyle(fontSize: 12.5, color: c.ink2)),
          ]),
        ),
        if (_puedeEditar)
          FilledButton.tonal(
            onPressed: _chatActivo == null ? null : () => _cambiarChat(!activo),
            child: Text(activo ? 'Detener chat' : 'Reactivar chat'),
          ),
      ]),
    );
  }

  /// Cómo está armado Sisol, en tarjetas como las de SOL. Todo sale del Worker —de las mismas
  /// constantes y cargas que usa el chat—, así que lo que se lee aquí es lo que de verdad corre.
  Widget _resumen(SiColors c) {
    final a = _agente;
    final wa = (a['whatsapp'] as Map?) ?? const {};
    final datos = (a['datos'] as Map?) ?? const {};
    final herramientas = (a['herramientas'] as List?) ?? const [];
    final protecciones = (a['protecciones'] as List?) ?? const [];
    final tarjetas = <Widget>[
      _tarjetaInfo(c, 'El modelo', [
        _fila(c, 'Modelo', '${a['modelo'] ?? '—'}'),
        _fila(c, 'Respaldo', '${a['modelo_respaldo'] ?? '—'}'),
        _fila(c, 'Proveedor', '${a['proveedor'] ?? '—'}'),
        _fila(c, 'Recuerda', 'los últimos ${a['historial'] ?? '?'} mensajes de la plática'),
        _fila(c, 'Aviso al asesor',
            wa['configurado'] == true ? 'WhatsApp al ${wa['asesor']} (${wa['servidor']})' : 'FALTA configurar OpenWA',
            alerta: wa['configurado'] != true),
        _nota(c, 'El modelo y el aviso se cambian en el código del Worker (workers/ventas); '
            'los textos y límites, abajo.'),
      ]),
      _tarjetaInfo(c, 'Qué sabe hacer', [
        for (final h in herramientas) _fila(c, '${h['nombre']}', '${h['que_hace']}'),
      ]),
      _tarjetaInfo(c, 'Lo que tiene cargado', [
        _fila(c, 'Desarrollos activos', '${datos['desarrollos_activos'] ?? 0}'),
        _fila(c, 'Unidades en inventario', '${datos['unidades'] ?? 0} (${datos['unidades_disponibles'] ?? 0} disponibles)'),
        _fila(c, 'Documentos del Drive', '${datos['documentos_drive'] ?? 0}'),
        _fila(c, 'Información adicional', '${datos['conocimiento_adicional'] ?? 0} fragmentos'),
      ]),
      _tarjetaInfo(c, 'Protecciones', [
        for (final p in protecciones) _nota(c, '• $p'),
      ]),
      _tarjetaInfo(c, 'Hasta dónde llega', [
        _nota(c, '${a['ambito'] ?? ''}'),
      ]),
    ];
    // Tres columnas en pantalla ancha, dos en mediana y una en el teléfono; cada columna crece hacia
    // abajo con lo suyo, igual que la Configuración de SOL.
    return LayoutBuilder(builder: (_, caja) {
      final columnas = caja.maxWidth >= 1100 ? 3 : (caja.maxWidth >= 720 ? 2 : 1);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var k = 0; k < columnas; k++) ...[
            if (k > 0) const SizedBox(width: SiSpace.x4),
            Expanded(
              child: Column(children: [
                for (var i = k; i < tarjetas.length; i += columnas) ...[
                  tarjetas[i],
                  const SizedBox(height: SiSpace.x4),
                ],
              ]),
            ),
          ],
        ],
      );
    });
  }

  Widget _tarjetaInfo(SiColors c, String titulo, List<Widget> hijos) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SiSpace.x4),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: SiRadius.rMd,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.ink3, letterSpacing: .5)),
        const SizedBox(height: SiSpace.x2),
        ...hijos,
      ]),
    );
  }

  Widget _nota(SiColors c, String texto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(texto, style: TextStyle(fontSize: 12.5, color: c.ink3, height: 1.45)),
      );

  Widget _fila(SiColors c, String etiqueta, String valor, {bool alerta = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 150, child: Text(etiqueta, style: TextStyle(fontSize: 12.5, color: c.ink3))),
        Expanded(
          child: SelectableText(valor,
              style: TextStyle(
                  fontSize: 12.5,
                  color: alerta ? c.danger : c.ink,
                  fontWeight: alerta ? FontWeight.w600 : FontWeight.w400)),
        ),
      ]),
    );
  }

  Widget _tarjeta(SiColors c, String titulo, String ayuda, List<String> claves) {
    final presentes = [for (final k in claves) if (_metaDe(k) != null) k];
    if (presentes.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: SiSpace.x5),
      padding: const EdgeInsets.all(SiSpace.x5),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rLg,
        border: Border.all(color: c.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        if (ayuda.isNotEmpty) Text(ayuda, style: TextStyle(fontSize: 12.5, color: c.ink3)),
        const SizedBox(height: SiSpace.x4),
        for (final k in presentes) _campo(c, k),
        if (_puedeEditar)
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => _restaurar(titulo, presentes), child: const Text('Restaurar predeterminados')),
            const SizedBox(width: SiSpace.x2),
            FilledButton(
              onPressed: _guardandoGrupo == titulo ? null : () => _guardar(titulo, presentes),
              child: const Text('Guardar cambios'),
            ),
          ]),
      ]),
    );
  }

  Widget _campo(SiColors c, String clave) {
    final m = _metaDe(clave)!;
    final g = _guardado[clave];
    final esNumero = m['tipo'] == 'numero';
    return Padding(
      padding: const EdgeInsets.only(bottom: SiSpace.x4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${m['label']}', style: const TextStyle(fontWeight: FontWeight.w600))),
          etiquetaVentas(
            c,
            g == null ? 'Predeterminado' : 'Personalizado · ${fechaCorta(g['actualizado_en'])}',
            g == null ? c.ink3 : c.brand,
          ),
        ]),
        Text('${m['descripcion']}', style: TextStyle(fontSize: 12, color: c.ink3)),
        const SizedBox(height: SiSpace.x2),
        SizedBox(
          width: esNumero ? 180 : null,
          child: TextField(
            controller: _campos[clave],
            readOnly: !_puedeEditar,
            keyboardType: esNumero ? TextInputType.number : TextInputType.multiline,
            minLines: esNumero ? 1 : (clave == 'prompt_personalidad' ? 14 : 3),
            maxLines: esNumero ? 1 : (clave == 'prompt_personalidad' ? 30 : 8),
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(border: OutlineInputBorder(borderRadius: SiRadius.rMd), isDense: true),
          ),
        ),
      ]),
    );
  }
}
