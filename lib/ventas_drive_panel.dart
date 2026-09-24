import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/ventas_datos.dart';
import 'theme/si_theme.dart';
import 'ventas_comun.dart';

/// Lo que Sisol leyó del Drive comercial: los brochures, listas de precios y ubicación de cada
/// desarrollo, y un botón para ponerlo al día.
///
/// Pedido del usuario el 24/09/2026, después de que Sisol le contestara a un cliente con un dato
/// que no estaba en ningún lado: «el mismo sistema que ocupa SOL para que lea todo el Drive». Lo
/// llena la función `ventas-drive-sync`; esta pantalla sólo la dispara y muestra lo que hay. Cada
/// PDF se abre con el texto TAL CUAL lo tiene Sisol, para poder revisar lo que le va a decir a un
/// cliente.
class VentasDrivePanel extends StatefulWidget {
  final bool puedeActualizar;
  const VentasDrivePanel({super.key, required this.puedeActualizar});

  @override
  State<VentasDrivePanel> createState() => _VentasDrivePanelState();
}

class _VentasDrivePanelState extends State<VentasDrivePanel> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _archivos = [];
  Map<String, dynamic>? _ultima;
  bool _cargando = true;
  bool _actualizando = false;
  Timer? _sondeo;

  static const _pendientes = {'PENDIENTE', 'LEYENDO'};
  static const _categorias = {'BROCHURE': 'Brochure', 'PRECIOS': 'Precios', 'UBICACION': 'Ubicación'};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _sondeo?.cancel();
    super.dispose();
  }

  int get _porLeer => _archivos.where((a) => _pendientes.contains(a['estado'])).length;

  Future<void> _cargar() async {
    try {
      // Sin el texto: son decenas de KB por documento y sólo hace falta al abrir uno.
      final arch = await _supabase
          .from('ventas_drive_archivos')
          .select('id, carpeta, categoria, ruta, nombre, enlace, modificado, estado, error, paginas, '
              'pagina_siguiente, leido_en, ventas_desarrollos(nombre)')
          .order('carpeta', ascending: true)
          .order('categoria', ascending: true)
          .order('nombre', ascending: true);
      final sinc = await _supabase
          .from('ventas_drive_sincronizaciones')
          .select()
          .order('iniciada_en', ascending: false)
          .limit(1);
      if (!mounted) return;
      setState(() {
        _archivos = [for (final a in arch as List) Map<String, dynamic>.from(a)];
        _ultima = (sinc as List).isEmpty ? null : Map<String, dynamic>.from(sinc.first);
      });
      _vigilar();
    } catch (e) {
      debugPrint('Error al cargar el Drive de Sisol: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Mientras haya PDF por leer, la lectura sigue en el servidor sin esta pantalla. Esto sólo
  /// refresca para ver cómo avanza.
  void _vigilar() {
    _sondeo?.cancel();
    if (_porLeer > 0) {
      _sondeo = Timer(const Duration(seconds: 5), () {
        if (mounted) _cargar();
      });
    }
  }

  Future<void> _pedir(String accion) async {
    setState(() => _actualizando = true);
    try {
      final r = await _supabase.functions.invoke('ventas-drive-sync', body: {'accion': accion});
      final d = (r.data as Map?)?.cast<String, dynamic>() ?? {};
      if (d['error'] != null) throw d['error'];
      if (!mounted) return;
      final sin = List<String>.from(d['sin_catalogo'] ?? const []);
      avisoVentas(
        context,
        accion == 'sincronizar'
            ? 'Drive revisado: ${d['nuevos'] ?? 0} nuevos, ${d['cambiados'] ?? 0} cambiados, '
                '${d['quitados'] ?? 0} quitados. Los PDF se leen en segundo plano.'
                '${sin.isEmpty ? '' : ' Sin desarrollo en el catálogo: ${sin.join(', ')}.'}'
            : 'Se reanudó la lectura.',
      );
    } on FunctionException catch (e) {
      if (mounted) avisoVentas(context, 'No se pudo actualizar: ${(e.details as Map?)?['error'] ?? e}', error: true);
    } catch (e) {
      if (mounted) avisoVentas(context, 'No se pudo actualizar: $e', error: true);
    } finally {
      if (mounted) setState(() => _actualizando = false);
      await _cargar();
    }
  }

  Future<void> _abrirTexto(Map<String, dynamic> a) async {
    String texto;
    try {
      final r = await _supabase.from('ventas_drive_archivos').select('texto').eq('id', a['id']).single();
      texto = '${r['texto'] ?? ''}';
    } catch (e) {
      texto = 'No se pudo cargar: $e';
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${a['nombre']}', style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 720,
          height: 520,
          child: SingleChildScrollView(child: SelectableText(texto.isEmpty ? '(sin texto)' : texto)),
        ),
        actions: [
          TextButton(onPressed: () => abrirUrl('${a['enlace']}'), child: const Text('Abrir en el Drive')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  /// «BONANZA COTO 4 - ÁGATA» cae en «Bonanza Prisma» del catálogo: se dice, para que se vea a qué
  /// desarrollo le atribuye Sisol ese texto. Sin desarrollo, se avisa.
  String _ligadoA(String carpeta, Map<String, dynamic> a) {
    final n = (a['ventas_desarrollos'] as Map?)?['nombre']?.toString();
    if (carpeta == 'SI SOL') return ' · general';
    if (n == null) return ' · sin desarrollo en el catálogo';
    return sinAcentos(n).toLowerCase() == sinAcentos(carpeta).toLowerCase() ? '' : ' · $n';
  }

  Color _colorEstado(SiColors c, String e) => switch (e) {
        'LEIDO' => c.success,
        'ERROR' => c.danger,
        'PENDIENTE' || 'LEYENDO' => c.warn,
        _ => c.ink3,
      };

  String _textoEstado(Map<String, dynamic> a) => switch ('${a['estado']}') {
        'LEIDO' => 'Leído · ${a['paginas'] ?? '?'} p.',
        'LEYENDO' => 'Leyendo · p. ${a['pagina_siguiente'] ?? '?'}',
        'PENDIENTE' => 'Por leer',
        'SIN_TEXTO' => 'Sin texto (imagen)',
        'NO_SE_LEE' => 'No es PDF',
        'ERROR' => 'Error',
        final otro => otro,
      };

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final leidos = _archivos.where((a) => a['estado'] == 'LEIDO').length;
    final errores = _archivos.where((a) => a['estado'] == 'ERROR').length;
    final u = _ultima;

    final porCarpeta = <String, List<Map<String, dynamic>>>{};
    for (final a in _archivos) {
      (porCarpeta['${a['carpeta']}'] ??= []).add(a);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: SiSpace.x5),
      padding: const EdgeInsets.all(SiSpace.x5),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rLg,
        border: Border.all(color: c.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('Drive comercial', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          if (widget.puedeActualizar) ...[
            if (_porLeer > 0 && !_actualizando)
              TextButton(onPressed: () => _pedir('leer'), child: const Text('Reanudar lectura')),
            FilledButton.icon(
              onPressed: _actualizando ? null : () => _pedir('sincronizar'),
              icon: _actualizando
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 16),
              label: const Text('Actualizar desde el Drive'),
            ),
          ],
        ]),
        Text(
          'Sisol lee solo los brochures, listas de precios y ubicación de cada desarrollo. Cuentas, formatos '
          'de bancos, Infonavit, fideicomisos y cartas oferta no se abren. Actualiza cuando suban algo nuevo.',
          style: TextStyle(fontSize: 12.5, color: c.ink3),
        ),
        const SizedBox(height: SiSpace.x3),
        if (_cargando)
          const LinearProgressIndicator()
        else ...[
          Wrap(spacing: SiSpace.x3, runSpacing: SiSpace.x2, children: [
            etiquetaVentas(c, '$leidos leídos', c.success),
            if (_porLeer > 0) etiquetaVentas(c, '$_porLeer por leer', c.warn),
            if (errores > 0) etiquetaVentas(c, '$errores con error', c.danger),
            if (u != null)
              Text(
                u['error'] != null
                    ? 'La última actualización falló (${fechaCorta(u['iniciada_en'])}): ${u['error']}'
                    : 'Última actualización: ${fechaCorta(u['terminada_en'] ?? u['iniciada_en'])}',
                style: TextStyle(fontSize: 12, color: u['error'] != null ? c.danger : c.ink3),
              )
            else
              Text('Todavía no se ha leído el Drive: Sisol usa la copia fija de agosto.',
                  style: TextStyle(fontSize: 12, color: c.warn)),
          ]),
          if (u != null && (u['sin_catalogo'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: SiSpace.x2),
            Text(
              'Carpetas sin desarrollo en el catálogo (se leen, pero el chat no muestra su tarjeta): '
              '${(u['sin_catalogo'] as List).join(', ')}',
              style: TextStyle(fontSize: 12, color: c.warn),
            ),
          ],
          const SizedBox(height: SiSpace.x3),
          for (final e in porCarpeta.entries)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(e.key, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${e.value.where((a) => a['estado'] == 'LEIDO').length} de ${e.value.length} leídos'
                  '${_ligadoA(e.key, e.value.first)}',
                  style: TextStyle(fontSize: 11.5, color: c.ink3),
                ),
                children: [
                  for (final a in e.value)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: SiSpace.x3),
                      leading: etiquetaVentas(c, _categorias['${a['categoria']}'] ?? '${a['categoria']}', c.brand),
                      title: Text('${a['nombre']}', style: const TextStyle(fontSize: 12.5)),
                      subtitle: a['error'] != null
                          ? Text('${a['error']}', style: TextStyle(fontSize: 11.5, color: c.danger))
                          : null,
                      trailing: etiquetaVentas(c, _textoEstado(a), _colorEstado(c, '${a['estado']}')),
                      onTap: a['estado'] == 'LEIDO' ? () => _abrirTexto(a) : () => abrirUrl('${a['enlace']}'),
                    ),
                ],
              ),
            ),
        ],
      ]),
    );
  }
}
