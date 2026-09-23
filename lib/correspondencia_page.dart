import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/correspondencia.dart';
import 'theme/si_theme.dart';

/// Correspondencia: redactar un correo y mandarlo a compañeros —o a cualquier dirección— desde la
/// cuenta del sistema, y ver lo enviado.
///
/// La pantalla NO manda nada por sí misma: llama a la función `correspondencia`, que es la única que
/// tiene los datos del servidor de correo y la que decide si el mensaje sale. Lo que se valida aquí
/// es sólo para avisar pronto; ver `services/correspondencia.dart`.
///
/// El historial se lee directo de la tabla `correspondencia`: cada quien ve lo suyo y un
/// administrador todo, y eso lo decide RLS, no esta pantalla.
class CorrespondenciaPage extends StatefulWidget {
  final String role;
  const CorrespondenciaPage({super.key, required this.role});

  @override
  State<CorrespondenciaPage> createState() => _CorrespondenciaPageState();
}

typedef _Colaborador = ({String nombre, String correo});

class _CorrespondenciaPageState extends State<CorrespondenciaPage> {
  final _supabase = Supabase.instance.client;
  final _asuntoCtrl = TextEditingController();
  final _cuerpoCtrl = TextEditingController();

  /// El campo de destinatarios lo crea el `Autocomplete`; se guarda para poder vaciarlo al elegir.
  TextEditingController? _campoDest;

  final List<String> _destinatarios = [];
  List<_Colaborador> _colaboradores = [];
  List<Map<String, dynamic>> _enviados = [];

  bool _cargandoEnviados = true;
  bool _enviando = false;
  String? _avisoDest;

  /// Sólo para administradores: si el envío está configurado en el servidor.
  Map<String, dynamic>? _config;

  bool get _esAdmin => widget.role == 'admin';

  @override
  void initState() {
    super.initState();
    _cargarColaboradores();
    _cargarEnviados();
    if (_esAdmin) _cargarConfig();
  }

  @override
  void dispose() {
    _asuntoCtrl.dispose();
    _cuerpoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarColaboradores() async {
    try {
      // `mail_pass` NO se pide, a propósito: esta pantalla no la necesita.
      final filas = await _supabase
          .from('profiles')
          .select('nombre, paterno, materno, mail_user, email')
          .eq('status_sys', 'ACTIVO')
          .order('nombre', ascending: true);
      final lista = <_Colaborador>[];
      for (final f in filas) {
        final correo = correoDe(f);
        if (correo == null) continue;
        final nombre = [f['nombre'], f['paterno'], f['materno']]
            .map((x) => (x ?? '').toString().trim())
            .where((x) => x.isNotEmpty)
            .join(' ');
        lista.add((nombre: nombre.isEmpty ? correo : nombre, correo: correo));
      }
      if (mounted) setState(() => _colaboradores = lista);
    } catch (e) {
      debugPrint('Correspondencia: no se cargaron los colaboradores: $e');
    }
  }

  Future<void> _cargarEnviados() async {
    setState(() => _cargandoEnviados = true);
    try {
      final filas = await _supabase
          .from('correspondencia')
          .select('id, remitente_id, remitente_nombre, asunto, destinatarios, estado, error, '
              'creado_en')
          .order('creado_en', ascending: false)
          .limit(50);
      if (mounted) setState(() => _enviados = List<Map<String, dynamic>>.from(filas));
    } catch (e) {
      debugPrint('Correspondencia: no se cargó el historial: $e');
    } finally {
      if (mounted) setState(() => _cargandoEnviados = false);
    }
  }

  Future<void> _cargarConfig() async {
    try {
      final r = await _supabase.functions
          .invoke('correspondencia', body: {'configuracion': true});
      if (mounted) setState(() => _config = Map<String, dynamic>.from(r.data as Map));
    } catch (e) {
      // Si la función todavía no está desplegada, se dice igual que si no estuviera configurada.
      if (mounted) {
        setState(() => _config = {'configurado': false, 'error': _mensajeDe(e)});
      }
    }
  }

  /// El texto que se le enseña a la persona, no el volcado técnico del error.
  ///
  /// La función contesta `{error: "..."}` con un motivo escrito para leerse —«Llegaste al límite de
  /// 20 mensajes por hora»—, y eso es lo que hay que mostrar, no `FunctionException(status: 429...)`.
  String _mensajeDe(Object e) {
    if (e is FunctionException) {
      final d = e.details;
      if (d is Map && d['error'] != null) {
        final rechazados = (d['rechazados'] as List?)?.join(', ');
        return rechazados == null || rechazados.isEmpty
            ? d['error'].toString()
            : '${d['error']} ($rechazados)';
      }
      return 'El servidor respondió con el error ${e.status}.';
    }
    return e.toString();
  }

  void _agregarTexto(String texto) {
    final r = separarCorreos(texto, yaElegidos: _destinatarios);
    setState(() {
      _destinatarios.addAll(r.validos);
      _avisoDest = r.rechazados.isEmpty
          ? null
          : (r.rechazados.length == 1
              ? '«${r.rechazados.first}» no es una dirección válida.'
              : 'No son direcciones válidas: ${r.rechazados.join(', ')}.');
    });
    // Se deja en el campo sólo lo que no se pudo añadir, para que se pueda corregir.
    _campoDest?.text = r.rechazados.join(', ');
  }

  void _agregarColaborador(_Colaborador c) {
    setState(() {
      if (!_destinatarios.contains(c.correo)) _destinatarios.add(c.correo);
      _avisoDest = null;
    });
    _campoDest?.clear();
  }

  String _nombreDeCorreo(String correo) {
    for (final c in _colaboradores) {
      if (c.correo == correo) return c.nombre;
    }
    return correo;
  }

  Future<void> _enviar() async {
    // Lo que quede escrito en el campo cuenta: quien teclea una dirección y pulsa «Enviar» sin darle
    // Enter espera que vaya incluida.
    final pendiente = _campoDest?.text.trim() ?? '';
    if (pendiente.isNotEmpty) {
      _agregarTexto(pendiente);
      if (_avisoDest != null) return;
    }

    final falta = queFalta(
      asunto: _asuntoCtrl.text,
      cuerpo: _cuerpoCtrl.text,
      destinatarios: _destinatarios.length,
    );
    if (falta != null) {
      _aviso(falta, error: true);
      return;
    }

    // Se confirma porque no se puede deshacer: un correo que salió, salió.
    final n = _destinatarios.length;
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar correo'),
        content: Text(n == 1
            ? '¿Enviar «${_asuntoCtrl.text.trim()}» a ${_nombreDeCorreo(_destinatarios.first)}?'
            : '¿Enviar «${_asuntoCtrl.text.trim()}» a $n destinatarios?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (seguro != true || !mounted) return;

    setState(() => _enviando = true);
    try {
      final r = await _supabase.functions.invoke('correspondencia', body: {
        'asunto': _asuntoCtrl.text.trim(),
        'cuerpo': _cuerpoCtrl.text.trim(),
        'destinatarios': _destinatarios,
      });
      final datos = Map<String, dynamic>.from(r.data as Map);
      final noAceptados = (datos['no_aceptados'] as List?)?.cast<String>() ?? const [];
      if (!mounted) return;
      if (noAceptados.isEmpty) {
        _aviso(n == 1 ? 'Correo enviado.' : 'Correo enviado a $n destinatarios.');
        setState(() {
          _destinatarios.clear();
          _asuntoCtrl.clear();
          _cuerpoCtrl.clear();
        });
      } else {
        // Salió, pero no a todos: se dice a quién no, y se deja el borrador para reintentar.
        _aviso('El servidor no aceptó: ${noAceptados.join(', ')}.', error: true);
      }
    } catch (e) {
      // Si falla, el borrador se queda intacto para poder reintentar sin volver a escribirlo.
      if (mounted) _aviso('No se pudo enviar: ${_mensajeDe(e)}', error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
      _cargarEnviados();
    }
  }

  void _aviso(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? Colors.red[700] : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: LayoutBuilder(builder: (context, constraints) {
        final ancho = constraints.maxWidth > 1100;
        final redactar = _tarjetaRedactar(c);
        final enviados = _tarjetaEnviados(c);
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: SiSpace.x6, vertical: SiSpace.x4),
          child: ancho
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: redactar),
                    SizedBox(width: SiSpace.x6),
                    Expanded(flex: 2, child: enviados),
                  ],
                )
              : Column(children: [redactar, SizedBox(height: SiSpace.x6), enviados]),
        );
      }),
    );
  }

  Widget _tarjeta(SiColors c, {required String titulo, required IconData icono,
      Widget? accion, required Widget cuerpo}) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: SiRadius.rLg, side: BorderSide(color: c.line)),
      child: Padding(
        padding: EdgeInsets.all(SiSpace.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icono, size: 20, color: c.brand),
              SizedBox(width: SiSpace.x2),
              Expanded(
                child: Text(titulo,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              if (accion != null) accion,
            ]),
            SizedBox(height: SiSpace.x4),
            cuerpo,
          ],
        ),
      ),
    );
  }

  Widget _tarjetaRedactar(SiColors c) {
    return _tarjeta(
      c,
      titulo: 'Nuevo correo',
      icono: Icons.edit_outlined,
      cuerpo: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_esAdmin) _avisoConfiguracion(c),
          _campoDestinatarios(c),
          SizedBox(height: SiSpace.x4),
          TextField(
            controller: _asuntoCtrl,
            maxLength: maxAsunto,
            decoration: const InputDecoration(
              labelText: 'Asunto',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: SiSpace.x2),
          TextField(
            controller: _cuerpoCtrl,
            minLines: 8,
            maxLines: 16,
            maxLength: maxCuerpo,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Mensaje',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: SiSpace.x2),
          Text(
            'Sale desde la cuenta del sistema con tu nombre. Las respuestas te llegan a tu correo.',
            style: TextStyle(fontSize: 12, color: c.ink3),
          ),
          SizedBox(height: SiSpace.x4),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _enviando ? null : _enviar,
              icon: _enviando
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send, size: 18),
              label: Text(_enviando ? 'Enviando…' : 'Enviar'),
            ),
          ),
        ],
      ),
    );
  }

  /// Sólo administradores: avisa si el servidor de correo no está listo, antes de que alguien
  /// escriba un mensaje entero y descubra al enviar que no puede salir.
  Widget _avisoConfiguracion(SiColors c) {
    final cfg = _config;
    if (cfg == null) return const SizedBox.shrink();
    final configurado = cfg['configurado'] == true;
    final puertoOk = cfg['puerto_ok'] != false;
    if (configurado && puertoOk) return const SizedBox.shrink();

    final texto = cfg['error'] != null
        ? 'No se pudo consultar la configuración del correo: ${cfg['error']}'
        : !configurado
            ? 'El envío todavía no está configurado. Faltan los datos del servidor SMTP en los '
                'secretos de la función «correspondencia».'
            : (cfg['motivo_puerto'] ?? 'El puerto configurado no se puede usar.').toString();
    return Container(
      margin: EdgeInsets.only(bottom: SiSpace.x4),
      padding: EdgeInsets.all(SiSpace.x3),
      decoration: BoxDecoration(
        color: c.warnTint,
        borderRadius: SiRadius.rMd,
        border: Border.all(color: c.warn.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, color: c.warn, size: 20),
        SizedBox(width: SiSpace.x2),
        Expanded(child: Text(texto, style: TextStyle(fontSize: 13, color: c.ink))),
      ]),
    );
  }

  Widget _campoDestinatarios(SiColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_destinatarios.isNotEmpty) ...[
          Wrap(
            spacing: SiSpace.x2,
            runSpacing: SiSpace.x2,
            children: [
              for (final d in _destinatarios)
                InputChip(
                  label: Text(_nombreDeCorreo(d)),
                  tooltip: d,
                  onDeleted: () => setState(() => _destinatarios.remove(d)),
                ),
            ],
          ),
          SizedBox(height: SiSpace.x2),
        ],
        Autocomplete<_Colaborador>(
          displayStringForOption: (o) => o.correo,
          optionsBuilder: (valor) {
            final q = valor.text.trim().toLowerCase();
            if (q.length < 2) return const Iterable<_Colaborador>.empty();
            return _colaboradores
                .where((o) => !_destinatarios.contains(o.correo))
                .where((o) => o.nombre.toLowerCase().contains(q) || o.correo.contains(q))
                .take(8);
          },
          onSelected: _agregarColaborador,
          optionsViewBuilder: (context, onSelected, opciones) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: SiRadius.rMd,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280, maxWidth: 480),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final o in opciones)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline, size: 18),
                        title: Text(o.nombre),
                        subtitle: Text(o.correo),
                        onTap: () => onSelected(o),
                      ),
                  ],
                ),
              ),
            ),
          ),
          fieldViewBuilder: (context, ctrl, foco, alEnviar) {
            _campoDest = ctrl;
            return TextField(
              controller: ctrl,
              focusNode: foco,
              decoration: InputDecoration(
                labelText: 'Para',
                hintText: 'Busca un compañero o escribe un correo y pulsa Enter',
                border: const OutlineInputBorder(),
                errorText: _avisoDest,
                helperText: '${_destinatarios.length} de $maxDestinatarios destinatarios',
              ),
              onSubmitted: (t) {
                // Si lo escrito ya es un correo completo, gana lo escrito. Si no, Enter elige la
                // sugerencia resaltada. Al revés, teclear «ana@cliente.com» y pulsar Enter añadiría
                // a la compañera Ana, que sale sugerida porque su nombre también empieza por «ana».
                final escrito = t.trim().toLowerCase();
                if (esCorreo(escrito) || escrito.contains(RegExp(r'[\s,;]'))) {
                  _agregarTexto(t);
                } else {
                  alEnviar();
                  if (ctrl.text.trim().isNotEmpty) _agregarTexto(ctrl.text);
                }
                foco.requestFocus();
              },
            );
          },
        ),
      ],
    );
  }

  Widget _tarjetaEnviados(SiColors c) {
    final miId = _supabase.auth.currentUser?.id;
    return _tarjeta(
      c,
      titulo: _esAdmin ? 'Enviados (todos)' : 'Mis enviados',
      icono: Icons.outbox_outlined,
      accion: IconButton(
        tooltip: 'Actualizar',
        icon: const Icon(Icons.refresh, size: 20),
        onPressed: _cargandoEnviados ? null : _cargarEnviados,
      ),
      cuerpo: _cargandoEnviados
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          : _enviados.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                      child: Text('Todavía no hay correos enviados.',
                          style: TextStyle(color: c.ink3))),
                )
              : Column(
                  children: [
                    for (final m in _enviados) _filaEnviado(c, m, esMio: m['remitente_id'] == miId),
                  ],
                ),
    );
  }

  Widget _filaEnviado(SiColors c, Map<String, dynamic> m, {required bool esMio}) {
    final estado = (m['estado'] ?? '').toString();
    final (color, fondo) = switch (estado) {
      'ENVIADO' => (c.success, c.successTint),
      'FALLIDO' => (c.danger, c.dangerTint),
      _ => (c.warn, c.warnTint),
    };
    final dest = (m['destinatarios'] as List?)?.cast<String>() ?? const [];
    final fecha = DateTime.tryParse((m['creado_en'] ?? '').toString())?.toLocal();
    final detalle = [
      dest.length == 1 ? _nombreDeCorreo(dest.first) : '${dest.length} destinatarios',
      if (fecha != null) DateFormat('dd/MM/yyyy HH:mm').format(fecha),
      // Un administrador ve los de todos: se dice de quién es cada uno.
      if (!esMio) 'de ${m['remitente_nombre'] ?? '—'}',
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      padding: EdgeInsets.symmetric(vertical: SiSpace.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((m['asunto'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(detalle, style: TextStyle(fontSize: 12, color: c.ink3)),
                if (estado == 'FALLIDO' && m['error'] != null) ...[
                  const SizedBox(height: 4),
                  Text(m['error'].toString(),
                      style: TextStyle(fontSize: 12, color: c.danger)),
                ],
              ],
            ),
          ),
          SizedBox(width: SiSpace.x2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: fondo, borderRadius: SiRadius.rPill),
            child: Text(estado,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
          ),
        ],
      ),
    );
  }
}
