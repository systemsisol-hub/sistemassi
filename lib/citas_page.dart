import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme/si_theme.dart';
import 'widgets/boton_flotante.dart';

/// Citas (08/10/2026): un profesional (p. ej. la nutrióloga) publica sus horarios y los usuarios
/// apartan uno.
///
/// Todo pasa por funciones de la base (`citas_listar`, `citas_publicar`, `citas_apartar`,
/// `citas_cancelar`; migración 20261008100000): la tabla no se lee directo para que los demás solo
/// vean «Ocupado», sin quién. Los correos (.ics) los manda la función `calendario-invitar`.
///
/// Reglas del usuario: una cita a la vez por servicio; se cancela hasta 2 horas antes; pueden
/// apartar todos; al apartar solo una nota opcional.
class CitasPage extends StatefulWidget {
  final bool puedePublicar;
  const CitasPage({super.key, required this.puedePublicar});

  @override
  State<CitasPage> createState() => _CitasPageState();
}

class _CitasPageState extends State<CitasPage> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late final TabController _tabs =
      TabController(length: widget.puedePublicar ? 2 : 1, vsync: this);

  List<Map<String, dynamic>> _espacios = [];
  bool _cargando = true;
  String? _filtro; // «servicio · proveedor»

  static const _anticipacionCancelar = Duration(hours: 2);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final hoy = DateTime.now();
      final desde = DateTime(hoy.year, hoy.month, hoy.day);
      final r = await _supabase.rpc('citas_listar', params: {
        'p_desde': desde.toUtc().toIso8601String(),
        'p_hasta': desde.add(const Duration(days: 90)).toUtc().toIso8601String(),
      });
      if (mounted) setState(() => _espacios = List<Map<String, dynamic>>.from(r as List));
    } catch (e) {
      debugPrint('Citas: $e');
      _avisar('No se pudieron cargar las citas: $e', error: true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _avisar(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? SiColors.of(context).danger : null,
    ));
  }

  String _mensajeDe(Object e) {
    if (e is PostgrestException) return e.message;
    return e.toString();
  }

  DateTime _inicio(Map<String, dynamic> e) => DateTime.parse(e['inicio']).toLocal();
  DateTime _fin(Map<String, dynamic> e) => DateTime.parse(e['fin']).toLocal();
  String _clave(Map<String, dynamic> e) => '${e['servicio']} · ${e['proveedor_nombre']}';

  /// Correo con la invitación (o la cancelación). Si falla, la cita igual queda: solo se avisa.
  Future<String?> _correo(String? eventoId, String accion) async {
    if (eventoId == null) return null;
    try {
      await _supabase.functions.invoke('calendario-invitar',
          body: {'event_id': eventoId, 'accion': accion, 'alcance': 'evento'});
      return null;
    } catch (e) {
      return 'no se pudo mandar el correo';
    }
  }

  // ── Apartar ──────────────────────────────────────────────────────────────────

  Future<void> _apartar(Map<String, dynamic> e) async {
    final nota = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = SiColors.of(ctx);
        final inicio = _inicio(e);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
                color: c.panel,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _encabezadoHoja(ctx, c, 'Apartar cita', 'Apartar', () => Navigator.pop(ctx, true)),
              Divider(height: 1, color: c.line),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e['servicio'] ?? '',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.ink)),
                  Text('con ${e['proveedor_nombre']}', style: TextStyle(color: c.ink3)),
                  const SizedBox(height: 12),
                  _dato(c, Icons.event, _fechaLarga(inicio)),
                  _dato(c, Icons.schedule,
                      '${DateFormat('HH:mm').format(inicio)} – ${DateFormat('HH:mm').format(_fin(e))}'),
                  if ((e['lugar'] as String?)?.isNotEmpty == true)
                    _dato(c, Icons.place_outlined, e['lugar']),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nota,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Nota (opcional)',
                      hintText: 'Por ejemplo: primera consulta',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Podrás cancelarla desde aquí hasta 2 horas antes.',
                      style: TextStyle(fontSize: 12, color: c.ink3)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
    if (ok != true) return;
    try {
      final eventoId = await _supabase.rpc('citas_apartar',
          params: {'p_id': e['id'], 'p_nota': nota.text.trim()}) as String?;
      final fallo = await _correo(eventoId, 'enviar');
      _avisar(fallo == null
          ? 'Cita confirmada. Te llegó la confirmación por correo.'
          : 'Cita confirmada, pero $fallo.');
    } catch (err) {
      _avisar(_mensajeDe(err), error: true);
    }
    _cargar();
  }

  Future<void> _cancelarMia(Map<String, dynamic> e) async {
    if (_inicio(e).difference(DateTime.now()) < _anticipacionCancelar) {
      _avisar('Ya no se puede cancelar desde aquí: faltan menos de 2 horas. Avisa directamente.',
          error: true);
      return;
    }
    final si = await _confirmar('Cancelar cita',
        '¿Cancelar tu cita de ${e['servicio']} del ${_fechaLarga(_inicio(e))} a las '
        '${DateFormat('HH:mm').format(_inicio(e))}? El horario quedará libre para otra persona.');
    if (!si) return;
    try {
      // Primero el correo: después de cancelar ya no hay evento.
      await _correo(e['evento_id'] as String?, 'cancelar');
      await _supabase.rpc('citas_cancelar', params: {'p_id': e['id']});
      _avisar('Cita cancelada.');
    } catch (err) {
      _avisar(_mensajeDe(err), error: true);
    }
    _cargar();
  }

  // ── Mis horarios (profesional) ───────────────────────────────────────────────

  Future<void> _quitarHorario(Map<String, dynamic> e) async {
    final apartado = e['estado'] == 'apartado';
    final si = await _confirmar(
        apartado ? 'Cancelar cita' : 'Quitar horario',
        apartado
            ? 'Este horario lo apartó ${e['apartado_por_nombre'] ?? 'alguien'}. Se le avisará que '
                'se canceló, por correo y en el sistema.'
            : '¿Quitar el horario del ${_fechaLarga(_inicio(e))} a las '
                '${DateFormat('HH:mm').format(_inicio(e))}?');
    if (!si) return;
    try {
      if (apartado) await _correo(e['evento_id'] as String?, 'cancelar');
      await _supabase.rpc('citas_cancelar', params: {'p_id': e['id']});
      _avisar(apartado ? 'Cita cancelada y horario quitado.' : 'Horario quitado.');
    } catch (err) {
      _avisar(_mensajeDe(err), error: true);
    }
    _cargar();
  }

  Future<void> _publicar() async {
    final ultimo = _espacios.where((e) => e['soy_proveedor'] == true).toList();
    final creados = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormPublicar(
        servicio: ultimo.isEmpty ? '' : (ultimo.last['servicio'] ?? ''),
        lugar: ultimo.isEmpty ? '' : (ultimo.last['lugar'] ?? ''),
      ),
    );
    if (creados != null) {
      _avisar(creados == 0
          ? 'No se agregó ningún horario (ya existían o ya pasaron).'
          : 'Se publicaron $creados horarios.');
      _cargar();
    }
  }

  // ── Vista ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final enMisHorarios = widget.puedePublicar && _tabs.index == 1;
    return Scaffold(
      backgroundColor: c.bg,
      floatingActionButton: widget.puedePublicar && enMisHorarios && esPantallaTelefono(context)
          ? BotonFlotanteNuevo(onPressed: _publicar, tooltip: 'Publicar horarios')
          : null,
      body: Column(children: [
        if (widget.puedePublicar)
          Material(
            color: c.panel,
            child: TabBar(
              controller: _tabs,
              labelColor: c.brand,
              unselectedLabelColor: c.ink3,
              indicatorColor: c.brand,
              tabs: const [
                Tab(icon: Icon(Icons.event_available_outlined), text: 'Apartar cita'),
                Tab(icon: Icon(Icons.edit_calendar_outlined), text: 'Mis horarios'),
              ],
            ),
          ),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: enMisHorarios ? _vistaMisHorarios(c) : _vistaApartar(c),
                ),
        ),
      ]),
    );
  }

  Widget _vistaApartar(SiColors c) {
    final ahora = DateTime.now();
    final mias = _espacios
        .where((e) => e['es_mia'] == true && _fin(e).isAfter(ahora))
        .toList();
    final futuros = _espacios
        .where((e) => e['soy_proveedor'] != true && _inicio(e).isAfter(ahora))
        .toList();
    final claves = {for (final e in futuros) _clave(e)}.toList()..sort();
    final visibles =
        futuros.where((e) => _filtro == null || _clave(e) == _filtro).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (mias.isNotEmpty) ...[
          _titulo(c, 'Mis citas'),
          for (final e in mias) _tarjetaMia(c, e),
          const SizedBox(height: 16),
        ],
        _titulo(c, 'Horarios disponibles'),
        if (claves.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                  label: const Text('Todos'),
                  selected: _filtro == null,
                  onSelected: (_) => setState(() => _filtro = null)),
              for (final k in claves)
                ChoiceChip(
                    label: Text(k),
                    selected: _filtro == k,
                    onSelected: (_) => setState(() => _filtro = k)),
            ]),
          ),
        if (visibles.isEmpty)
          _vacio(c, 'Por ahora no hay horarios publicados.')
        else
          ..._porDia(visibles).entries.map((dia) => _bloqueDia(c, dia.key, dia.value)),
      ],
    );
  }

  Widget _vistaMisHorarios(SiColors c) {
    final ahora = DateTime.now();
    final mios = _espacios
        .where((e) => e['soy_proveedor'] == true && _fin(e).isAfter(ahora))
        .toList();
    final apartados = mios.where((e) => e['estado'] == 'apartado').length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, kEspacioBotonFlotante),
      children: [
        Row(children: [
          Expanded(
            child: Text(
                mios.isEmpty
                    ? 'No tienes horarios publicados.'
                    : '${mios.length} horarios · $apartados apartados',
                style: TextStyle(color: c.ink3)),
          ),
          if (!esPantallaTelefono(context))
            FilledButton.icon(
              onPressed: _publicar,
              icon: const Icon(Icons.add),
              label: const Text('Publicar horarios'),
            ),
        ]),
        const SizedBox(height: 12),
        for (final dia in _porDia(mios).entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(_fechaLarga(dia.key),
                style: TextStyle(fontWeight: FontWeight.bold, color: c.ink2)),
          ),
          for (final e in dia.value)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.line)),
              child: ListTile(
                leading: Icon(
                    e['estado'] == 'apartado' ? Icons.person : Icons.event_available_outlined,
                    color: e['estado'] == 'apartado' ? c.brand : c.success),
                title: Text(
                    '${DateFormat('HH:mm').format(_inicio(e))} – '
                    '${DateFormat('HH:mm').format(_fin(e))} · ${e['servicio']}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(e['estado'] == 'apartado'
                    ? [
                        'Apartado por ${e['apartado_por_nombre'] ?? '—'}',
                        if ((e['nota'] as String?)?.isNotEmpty == true) '«${e['nota']}»',
                      ].join(' · ')
                    : 'Libre'),
                trailing: IconButton(
                  tooltip: e['estado'] == 'apartado' ? 'Cancelar cita' : 'Quitar horario',
                  icon: Icon(Icons.close, color: c.danger),
                  onPressed: () => _quitarHorario(e),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _tarjetaMia(SiColors c, Map<String, dynamic> e) {
    final inicio = _inicio(e);
    final sePuede = inicio.difference(DateTime.now()) >= _anticipacionCancelar;
    return Card(
      elevation: 0,
      color: c.brandTint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(Icons.event_available, color: c.brand, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['servicio']} con ${e['proveedor_nombre']}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: c.ink)),
              Text('${_fechaLarga(inicio)} · ${DateFormat('HH:mm').format(inicio)}',
                  style: TextStyle(color: c.ink2)),
              if ((e['lugar'] as String?)?.isNotEmpty == true)
                Text(e['lugar'], style: TextStyle(color: c.ink3, fontSize: 12)),
              if (!sePuede)
                Text('Ya no se puede cancelar desde aquí (faltan menos de 2 h).',
                    style: TextStyle(color: c.ink3, fontSize: 11)),
            ]),
          ),
          if (sePuede)
            TextButton(onPressed: () => _cancelarMia(e), child: const Text('Cancelar')),
        ]),
      ),
    );
  }

  Widget _bloqueDia(SiColors c, DateTime dia, List<Map<String, dynamic>> lista) {
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final e in lista) {
      grupos.putIfAbsent(_clave(e), () => []).add(e);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_fechaLarga(dia), style: TextStyle(fontWeight: FontWeight.bold, color: c.ink2)),
        for (final g in grupos.entries) ...[
          if (grupos.length > 1 || _filtro == null)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(g.key, style: TextStyle(fontSize: 12, color: c.ink3)),
            ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in g.value)
              e['estado'] == 'libre'
                  ? ActionChip(
                      avatar: Icon(Icons.schedule, size: 16, color: c.brand),
                      label: Text(DateFormat('HH:mm').format(_inicio(e))),
                      onPressed: () => _apartar(e),
                    )
                  : Chip(
                      label: Text('${DateFormat('HH:mm').format(_inicio(e))} Ocupado',
                          style: TextStyle(
                              color: c.ink4, decoration: TextDecoration.lineThrough)),
                      backgroundColor: c.hover,
                    ),
          ]),
        ],
      ]),
    );
  }

  // ── Piezas ───────────────────────────────────────────────────────────────────

  Map<DateTime, List<Map<String, dynamic>>> _porDia(List<Map<String, dynamic>> lista) {
    final m = <DateTime, List<Map<String, dynamic>>>{};
    for (final e in lista) {
      final i = _inicio(e);
      m.putIfAbsent(DateTime(i.year, i.month, i.day), () => []).add(e);
    }
    return m;
  }

  String _fechaLarga(DateTime d) {
    final t = DateFormat("EEEE d 'de' MMMM", 'es_MX').format(d);
    return t[0].toUpperCase() + t.substring(1);
  }

  Widget _titulo(SiColors c, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: c.ink3)),
      );

  Widget _vacio(SiColors c, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(children: [
            Icon(Icons.event_busy_outlined, size: 44, color: c.line2),
            const SizedBox(height: 8),
            Text(t, style: TextStyle(color: c.ink3)),
          ]),
        ),
      );

  Widget _dato(SiColors c, IconData i, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(i, size: 16, color: c.ink3),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: TextStyle(color: c.ink2))),
        ]),
      );

  Future<bool> _confirmar(String titulo, String texto) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Sí', style: TextStyle(color: SiColors.of(ctx).danger))),
        ],
      ),
    );
    return r == true;
  }
}

Widget _encabezadoHoja(
    BuildContext ctx, SiColors c, String titulo, String accion, VoidCallback? alAceptar) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: Text('Cancelar', style: TextStyle(fontSize: 16, color: c.ink3)),
      ),
      Text(titulo, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.ink)),
      TextButton(
        onPressed: alAceptar,
        child: Text(accion,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c.brand)),
      ),
    ]),
  );
}

/// Publicar horarios: días, horas, duración; arma los espacios y los manda a `citas_publicar`.
class _FormPublicar extends StatefulWidget {
  final String servicio;
  final String lugar;
  const _FormPublicar({required this.servicio, required this.lugar});

  @override
  State<_FormPublicar> createState() => _FormPublicarState();
}

class _FormPublicarState extends State<_FormPublicar> {
  late final _servicio = TextEditingController(text: widget.servicio);
  late final _lugar = TextEditingController(text: widget.lugar);
  DateTime _desde = DateTime.now();
  DateTime _hasta = DateTime.now();
  TimeOfDay _horaIni = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _horaFin = const TimeOfDay(hour: 14, minute: 0);
  int _duracion = 30;
  final Set<int> _dias = {1, 2, 3, 4, 5}; // lunes a viernes
  bool _guardando = false;

  static const _nombresDias = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  void dispose() {
    _servicio.dispose();
    _lugar.dispose();
    super.dispose();
  }

  List<(DateTime, DateTime)> get _espacios {
    final r = <(DateTime, DateTime)>[];
    final ahora = DateTime.now();
    var d = DateTime(_desde.year, _desde.month, _desde.day);
    final ultimo = DateTime(_hasta.year, _hasta.month, _hasta.day);
    while (!d.isAfter(ultimo)) {
      if (_dias.contains(d.weekday)) {
        var t = DateTime(d.year, d.month, d.day, _horaIni.hour, _horaIni.minute);
        final tope = DateTime(d.year, d.month, d.day, _horaFin.hour, _horaFin.minute);
        while (!t.add(Duration(minutes: _duracion)).isAfter(tope)) {
          final fin = t.add(Duration(minutes: _duracion));
          if (t.isAfter(ahora)) r.add((t, fin));
          t = fin;
        }
      }
      d = d.add(const Duration(days: 1));
    }
    return r;
  }

  Future<void> _guardar() async {
    final espacios = _espacios;
    if (_servicio.text.trim().isEmpty) {
      _aviso('Escribe el servicio (por ejemplo: Nutrición).');
      return;
    }
    if (espacios.isEmpty) {
      _aviso('Con esas fechas y horas no sale ningún horario futuro.');
      return;
    }
    if (espacios.length > 500) {
      _aviso('Son ${espacios.length} horarios; publica máximo 500 de una vez.');
      return;
    }
    setState(() => _guardando = true);
    try {
      final n = await Supabase.instance.client.rpc('citas_publicar', params: {
        'p_servicio': _servicio.text.trim(),
        'p_lugar': _lugar.text.trim(),
        'p_espacios': [
          for (final (i, f) in espacios)
            {'inicio': i.toUtc().toIso8601String(), 'fin': f.toUtc().toIso8601String()}
        ],
      });
      if (mounted) Navigator.pop(context, n as int);
    } catch (e) {
      setState(() => _guardando = false);
      _aviso(e is PostgrestException ? e.message : '$e');
    }
  }

  void _aviso(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _elegirFecha(bool desde) async {
    final d = await showDatePicker(
      context: context,
      initialDate: desde ? _desde : _hasta,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null) return;
    setState(() {
      if (desde) {
        _desde = d;
        if (_hasta.isBefore(d)) _hasta = d;
      } else {
        _hasta = d.isBefore(_desde) ? _desde : d;
      }
    });
  }

  Future<void> _elegirHora(bool ini) async {
    final t = await showTimePicker(context: context, initialTime: ini ? _horaIni : _horaFin);
    if (t != null) setState(() => ini ? _horaIni = t : _horaFin = t);
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final f = DateFormat('EEE d MMM', 'es_MX');
    final n = _espacios.length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
            color: c.panel, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        constraints: BoxConstraints(
            maxWidth: 620, maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _encabezadoHoja(context, c, 'Publicar horarios', 'Publicar', _guardando ? null : _guardar),
          Divider(height: 1, color: c.line),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _servicio,
                  decoration: const InputDecoration(
                      labelText: 'Servicio *',
                      hintText: 'Nutrición',
                      prefixIcon: Icon(Icons.medical_services_outlined)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _lugar,
                  decoration: const InputDecoration(
                      labelText: 'Lugar o liga de la reunión',
                      prefixIcon: Icon(Icons.place_outlined)),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _elegirFecha(true),
                      icon: const Icon(Icons.event),
                      label: Text('Del ${f.format(_desde)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _elegirFecha(false),
                      icon: const Icon(Icons.event),
                      label: Text('al ${f.format(_hasta)}'),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Text('Días', style: TextStyle(color: c.ink3, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: [
                  for (var i = 1; i <= 7; i++)
                    FilterChip(
                      label: Text(_nombresDias[i - 1]),
                      selected: _dias.contains(i),
                      onSelected: (v) =>
                          setState(() => v ? _dias.add(i) : _dias.remove(i)),
                    ),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _elegirHora(true),
                      icon: const Icon(Icons.schedule),
                      label: Text('De ${_horaIni.format(context)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _elegirHora(false),
                      icon: const Icon(Icons.schedule),
                      label: Text('a ${_horaFin.format(context)}'),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  value: _duracion,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Duración de cada cita', prefixIcon: Icon(Icons.timelapse)),
                  items: [15, 20, 30, 45, 60, 90]
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m minutos')))
                      .toList(),
                  onChanged: (v) => setState(() => _duracion = v!),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: c.brandTint, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                      n == 0
                          ? 'Con estos datos no sale ningún horario.'
                          : 'Se publicarán $n horarios de $_duracion minutos.',
                      style: TextStyle(color: c.brand, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
