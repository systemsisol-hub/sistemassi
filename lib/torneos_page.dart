import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/torneos.dart';
import 'theme/si_theme.dart';

/// Torneos: la SiSol Mario Kart Cup. Ver supabase/migrations/20261006200000_torneos.sql.
///
/// Quien no se ha inscrito ve primero la tarjeta de inscripcion (como en el HTML original); ya
/// inscrito, entra a Liga, Ranking, Kart Garage y su perfil. Los puntos viven en la base y se
/// calculan de los resultados, asi que todos ven lo mismo y se actualiza solo (Realtime).
class TorneosPage extends StatefulWidget {
  final Map<String, dynamic> permissions;

  const TorneosPage({super.key, required this.permissions});

  @override
  State<TorneosPage> createState() => _TorneosPageState();
}

class _TorneosPageState extends State<TorneosPage> {
  final _db = Supabase.instance.client;

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _torneo;
  Map<String, Jugador> _jugadores = {};
  Map<String, String> _grupoDe = {};
  List<Carrera> _carreras = [];
  List<FilaTabla> _tabla = [];
  String _miNombre = '';

  RealtimeChannel? _canal;
  Timer? _recarga;

  String get _yo => _db.auth.currentUser?.id ?? '';
  bool get _esOrganizador => widget.permissions['show_torneos_admin'] == true;
  Jugador? get _miJugador => _jugadores[_yo];

  @override
  void initState() {
    super.initState();
    _fetchData();
    _escuchar();
  }

  @override
  void dispose() {
    _recarga?.cancel();
    if (_canal != null) _db.removeChannel(_canal!);
    super.dispose();
  }

  /// Cualquier cambio en carreras o torneos vuelve a cargar todo. Se juntan los avisos de medio
  /// segundo: capturar un resultado toca la carrera y a sus 4 jugadores, y serian 5 recargas.
  void _escuchar() {
    void alCambiar(PostgresChangePayload _) {
      _recarga?.cancel();
      _recarga = Timer(const Duration(milliseconds: 500), () {
        if (mounted) _fetchData(silencioso: true);
      });
    }

    _canal = _db.channel('torneos')
      ..onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: 'torneo_carreras', callback: alCambiar)
      ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'torneo_carrera_jugadores',
          callback: alCambiar)
      ..onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: 'torneos', callback: alCambiar)
      ..subscribe();
  }

  Future<void> _fetchData({bool silencioso = false}) async {
    if (!silencioso) setState(() => _isLoading = true);
    try {
      // El torneo en curso; si todos terminaron, el ultimo.
      final torneos = await _db
          .from('torneos')
          .select()
          .order('created_at', ascending: false)
          .limit(10);
      final lista = List<Map<String, dynamic>>.from(torneos);
      final torneo = lista.firstWhere((t) => t['fase'] != 'terminado',
          orElse: () => lista.isEmpty ? <String, dynamic>{} : lista.first);
      final torneoId = torneo['id'] as String?;

      final jugadoresF = _db
          .from('torneo_jugadores')
          .select('user_id, apodo, avatar, profiles(full_name)')
          .order('apodo', ascending: true);
      final perfilF = _db.from('profiles').select('full_name').eq('id', _yo).maybeSingle();
      final carrerasF = _db
          .from('torneo_carreras')
          .select('*, torneo_carrera_jugadores(user_id, posicion, puntos)')
          .or(torneoId == null ? 'torneo_id.is.null' : 'torneo_id.eq.$torneoId,torneo_id.is.null')
          .order('created_at', ascending: true);
      final gruposF = torneoId == null
          ? Future.value(<Map<String, dynamic>>[])
          : _db.from('torneo_grupos').select('user_id, grupo').eq('torneo_id', torneoId);
      final tablaF = torneoId == null
          ? Future.value(<Map<String, dynamic>>[])
          : _db.from('torneo_tabla').select().eq('torneo_id', torneoId);

      final jugadores = await jugadoresF;
      final perfil = await perfilF;
      final carreras = await carrerasF;
      final grupos = await gruposF;
      final tabla = await tablaF;

      if (!mounted) return;
      setState(() {
        _torneo = torneoId == null ? null : torneo;
        _jugadores = {
          for (final j in jugadores.map(Jugador.fromMap)) j.userId: j,
        };
        _grupoDe = {
          for (final g in grupos) g['user_id'] as String: g['grupo'] as String,
        };
        _carreras = carreras.map(Carrera.fromMap).toList();
        _tabla = tabla.map(FilaTabla.fromMap).toList();
        _miNombre = perfil?['full_name'] as String? ?? '';
        _error = null;
      });
    } catch (e) {
      debugPrint('Error cargando torneos: $e');
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Acciones ──────────────────────────────────────────────────────────────────────────────────

  String _mensaje(Object e) => e is PostgrestException ? e.message : '$e';

  /// Corre una funcion de la base y avisa como salio. Recarga al terminar sin esperar a Realtime.
  Future<bool> _rpc(String fn, Map<String, dynamic> params, {String? ok}) async {
    try {
      await _db.rpc(fn, params: params);
      if (ok != null) _avisar(ok);
      await _fetchData(silencioso: true);
      return true;
    } catch (e) {
      debugPrint('Error en $fn: $e');
      _avisar(_mensaje(e), error: true);
      return false;
    }
  }

  void _avisar(String texto, {bool error = false}) {
    if (!mounted) return;
    final c = SiColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), backgroundColor: error ? c.danger : null),
    );
  }

  Future<void> _armarLiga() async {
    final yaArmada = _carreras.any((c) => !c.esLibre);
    final n = _jugadores.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(yaArmada ? '¿Volver a sortear la Liga?' : '¿Armar la Liga?'),
        content: Text(yaArmada
            ? 'Se borran los grupos, el calendario y TODOS los resultados de la Liga, y se sortea de '
                'nuevo con los $n inscritos. Kart Garage no se toca.'
            : 'Se sortean los grupos con los $n inscritos y se arma el calendario completo. A cada '
                'jugador le llega un aviso con su grupo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yaArmada ? 'Sortear de nuevo' : 'Armar Liga'),
          ),
        ],
      ),
    );
    if (ok != true || _torneo == null) return;
    await _rpc('torneo_generar_liga', {'p_torneo': _torneo!['id']}, ok: 'Liga armada.');
  }

  Future<void> _nuevoTorneo() async {
    final ctrl = TextEditingController(text: 'SiSol Mario Kart Cup');
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo torneo'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Crear')),
        ],
      ),
    );
    ctrl.dispose();
    if (nombre == null || nombre.isEmpty) return;
    await _rpc('torneo_crear', {'p_nombre': nombre}, ok: 'Torneo creado.');
  }

  Future<void> _capturar(Carrera c) async {
    final orden = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _CapturaDialog(
        carrera: c,
        jugadores: _jugadores,
        puntos: c.esLibre
            ? puntosGarage
            : List<int>.from((_torneo?['puntos'] as List?) ?? const [10, 7, 5, 3]),
        directo: _esOrganizador,
      ),
    );
    if (orden == null) return;
    await _rpc('torneo_capturar', {'p_carrera': c.id, 'p_orden': orden},
        ok: _esOrganizador ? 'Resultado guardado.' : 'Resultado capturado. Otro jugador tiene que confirmarlo.');
  }

  Future<void> _confirmar(Carrera c, bool acepta) async {
    await _rpc('torneo_confirmar', {'p_carrera': c.id, 'p_acepta': acepta},
        ok: acepta ? 'Resultado confirmado.' : 'Resultado rechazado. Vuelvan a capturarlo.');
  }

  Future<void> _programar(Carrera c) async {
    final base = c.fechaHora ?? DateTime.now();
    final dia = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (dia == null || !mounted) return;
    final hora = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (hora == null) return;
    final fecha = DateTime(dia.year, dia.month, dia.day, hora.hour, hora.minute);
    await _rpc('torneo_programar', {'p_carrera': c.id, 'p_fecha': fecha.toUtc().toIso8601String()},
        ok: 'Horario guardado.');
  }

  Future<void> _crearCarreraLibre() async {
    final datos = await showDialog<_NuevaCarrera>(
      context: context,
      builder: (ctx) => _NuevaCarreraDialog(
        jugadores: _jugadores.values.where((j) => j.userId != _yo).toList(),
      ),
    );
    if (datos == null) return;
    await _rpc(
      'garage_crear',
      {
        'p_fecha': datos.fecha?.toUtc().toIso8601String(),
        'p_abierta': datos.abierta,
        'p_cupo': datos.cupo,
        'p_invitados': datos.invitados,
      },
      ok: 'Carrera creada.',
    );
  }

  Future<void> _cancelarLibre(Carrera c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar la carrera?'),
        content: const Text('A los demás jugadores les llega un aviso.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancelar carrera')),
        ],
      ),
    );
    if (ok == true) await _rpc('garage_cancelar', {'p_carrera': c.id}, ok: 'Carrera cancelada.');
  }

  // ── Build ─────────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: c.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No se pudieron cargar los torneos.', style: TextStyle(color: c.ink2)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _fetchData,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_miJugador == null) {
      return Scaffold(
        backgroundColor: c.bg,
        body: _Inscripcion(
          inscritos: _jugadores.length,
          nombreSugerido: _miNombre,
          apodosOcupados: _jugadores.values.map((j) => j.apodo.toLowerCase()).toSet(),
          onInscribir: (apodo, avatar) => _rpc(
            'torneo_registrarme',
            {'p_apodo': apodo, 'p_avatar': avatar},
            ok: '¡Listo! Ya estás inscrito.',
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: c.bg,
        body: Column(
          children: [
            _buildTabBar(c),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _conRecarga(_buildLiga(c)),
                  _conRecarga(_buildRanking(c)),
                  _conRecarga(_buildGarage(c)),
                  _conRecarga(_buildPerfil(c)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mismo cromo que las pestañas de IA y Asistencia. Emojis en lugar de iconos nuevos: un glifo
  /// de Material que la app no usaba sale en blanco a quien tenga la fuente vieja en caché.
  Widget _buildTabBar(SiColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: c.brand,
          unselectedLabelColor: c.ink3,
          indicatorColor: c.brand,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: const [
            Tab(height: 42, text: '🏆  Liga'),
            Tab(height: 42, text: '📊  Ranking'),
            Tab(height: 42, text: '🔥  Kart Garage'),
            Tab(height: 42, text: '🏎️  Mi perfil'),
          ],
        ),
      ),
    );
  }

  Widget _conRecarga(Widget child) {
    return RefreshIndicator(
      onRefresh: () => _fetchData(silencioso: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: child,
          ),
        ),
      ),
    );
  }

  bool get _esAncho => MediaQuery.of(context).size.width >= 900;

  // ── Liga ──────────────────────────────────────────────────────────────────────────────────────

  Widget _buildLiga(SiColors c) {
    final t = _torneo;
    if (t == null) {
      return Column(
        children: [
          _Vacio(texto: 'Todavía no hay un torneo.'),
          if (_esOrganizador) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _nuevoTorneo,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Crear torneo'),
            ),
          ],
        ],
      );
    }

    final fase = t['fase'] as String;
    final liga = _carreras.where((x) => !x.esLibre).toList();
    final grupos = liga.where((x) => x.tipo == 'grupo').toList()
      ..sort((a, b) => (a.numero ?? 0).compareTo(b.numero ?? 0));
    final finales = liga.where((x) => x.tipo == 'final').toList()
      ..sort((a, b) => (a.numero ?? 0).compareTo(b.numero ?? 0));
    final mias = liga.where((x) => x.pendiente && x.corre(_yo)).toList()
      ..sort((a, b) => (a.numero ?? 0).compareTo(b.numero ?? 0));
    final hechas = grupos.where((x) => x.completada).length;
    final tablas = tablasDeGrupos(_tabla);
    final campeon = t['campeon'] == null ? null : _jugadores[t['campeon']];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Hero(
          titulo: t['nombre'] as String,
          fase: fase,
          inscritos: _jugadores.length,
          campeon: campeon,
        ),
        if (_esOrganizador) ...[
          const SizedBox(height: 16),
          _Tarjeta(
            titulo: 'Organizador',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (fase != 'terminado')
                  FilledButton.icon(
                    onPressed: _armarLiga,
                    icon: const Icon(Icons.bolt, size: 16),
                    label: Text(liga.isEmpty ? 'Armar Liga' : 'Volver a sortear'),
                  ),
                if (fase == 'terminado')
                  FilledButton.icon(
                    onPressed: _nuevoTorneo,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Nuevo torneo'),
                  ),
                Text(
                  'Pones horarios desde cada carrera y lo que capturas cuenta sin confirmación.',
                  style: TextStyle(fontSize: 12, color: c.ink3),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (fase == 'inscripcion')
          _Nota(
            texto: 'Inscripciones abiertas: ${_jugadoresTexto(_jugadores.length)}. La Liga se arma cuando el '
                'organizador sortea los grupos (de 4 a 8, carreras de 4). Pasan a finales los 2 '
                'mejores de cada grupo.',
          )
        else if (fase == 'grupos')
          _Nota(
            texto: 'Fase de grupos: $hechas de ${grupos.length} carreras completadas. Al confirmarse la '
                'última, los 2 mejores de cada grupo pasan solos a finales.',
          )
        else if (fase == 'finales')
          const _Nota(
            texto: 'Finales: carreras de hasta 4. Pasan los 2 mejores de cada carrera hasta la Gran Final.',
          ),
        if (mias.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Seccion(titulo: 'Mis carreras pendientes'),
          _rejilla([for (final x in mias) _tarjetaCarrera(x, liga)]),
        ],
        if (finales.isNotEmpty) ...[
          const SizedBox(height: 20),
          _Seccion(titulo: '🏁 Finales'),
          _rejilla([for (final x in finales) _tarjetaCarrera(x, liga)]),
        ],
        if (tablas.isNotEmpty) ...[
          const SizedBox(height: 20),
          _Seccion(titulo: 'Grupos'),
          _rejilla([
            for (final e in tablas.entries)
              _TablaGrupo(
                grupo: e.key,
                filas: e.value,
                jugadores: _jugadores,
                yo: _yo,
                marcarClasificados: fase == 'grupos' || fase == 'finales' || fase == 'terminado',
              ),
          ]),
        ],
        if (grupos.isNotEmpty) ...[
          const SizedBox(height: 20),
          _Seccion(titulo: 'Calendario de grupos'),
          _rejilla([for (final x in grupos) _tarjetaCarrera(x, liga)]),
        ],
      ],
    );
  }

  /// Dos columnas en escritorio, una en el telefono.
  Widget _rejilla(List<Widget> hijos) {
    if (!_esAncho) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final h in hijos) Padding(padding: const EdgeInsets.only(bottom: 12), child: h),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, cons) {
        final ancho = (cons.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final h in hijos) SizedBox(width: ancho, child: h)],
        );
      },
    );
  }

  Widget _tarjetaCarrera(Carrera x, List<Carrera> todas) {
    final enRonda = x.tipo == 'final'
        ? todas.where((o) => o.tipo == 'final' && o.ronda == x.ronda).length
        : 1;
    final soyParticipante = x.corre(_yo);
    final soyCreador = x.creadaPor == _yo;
    final acciones = <Widget>[];

    if (x.estado == 'programada' && (soyParticipante || _esOrganizador) && x.participantes.length >= 2) {
      acciones.add(FilledButton(onPressed: () => _capturar(x), child: const Text('Capturar resultado')));
    }
    if (x.estado == 'por_confirmar') {
      if (_esOrganizador || (soyParticipante && x.capturadaPor != _yo)) {
        acciones
          ..add(FilledButton.icon(
            onPressed: () => _confirmar(x, true),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Confirmar'),
          ))
          ..add(OutlinedButton(onPressed: () => _confirmar(x, false), child: const Text('Rechazar')));
      }
    }
    if (x.esLibre && x.estado == 'programada') {
      if (!soyParticipante && x.abierta && x.participantes.length < x.cupo) {
        acciones.add(FilledButton(
          onPressed: () => _rpc('garage_unirme', {'p_carrera': x.id}, ok: 'Te uniste a la carrera.'),
          child: const Text('Unirme'),
        ));
      }
      if (soyParticipante && !soyCreador) {
        acciones.add(OutlinedButton(
          onPressed: () => _rpc('garage_salir', {'p_carrera': x.id}, ok: 'Saliste de la carrera.'),
          child: const Text('Salirme'),
        ));
      }
    }
    final puedeProgramar = _esOrganizador || (x.esLibre && soyCreador);
    if (x.pendiente && puedeProgramar) {
      acciones.add(OutlinedButton.icon(
        onPressed: () => _programar(x),
        icon: const Icon(Icons.schedule, size: 16),
        label: const Text('Horario'),
      ));
    }
    if (x.esLibre && x.pendiente && (soyCreador || _esOrganizador)) {
      acciones.add(TextButton(onPressed: () => _cancelarLibre(x), child: const Text('Cancelar')));
    }
    if (x.completada && _esOrganizador && !x.esLibre) {
      acciones.add(TextButton(onPressed: () => _capturar(x), child: const Text('Corregir')));
    }

    String? nota;
    if (x.estado == 'por_confirmar' && x.capturadaPor == _yo) {
      nota = 'Esperando que otro jugador confirme.';
    } else if (x.estado == 'por_confirmar') {
      final quien = _jugadores[x.capturadaPor]?.apodo;
      nota = 'Capturado por ${quien ?? 'un jugador'}. Falta que otro lo confirme.';
    }

    return _CarreraCard(
      titulo: nombreCarrera(x, carrerasEnRonda: enRonda),
      carrera: x,
      jugadores: _jugadores,
      yo: _yo,
      nota: nota,
      acciones: acciones,
    );
  }

  // ── Ranking ───────────────────────────────────────────────────────────────────────────────────

  Widget _buildRanking(SiColors c) {
    // Liga: lo de la fase de grupos, que es donde todos corren lo mismo. Las finales se ven en Liga.
    final liga = <String, ({int puntos, int carreras, int victorias, double? media})>{};
    for (final f in _tabla.where((f) => f.tipo == 'grupo')) {
      liga[f.userId] = (puntos: f.puntos, carreras: f.carreras, victorias: f.victorias, media: f.posicionMedia);
    }
    final filasLiga = liga.entries.toList()
      ..sort((a, b) => compararFilas(
            FilaTabla(userId: a.key, tipo: 'grupo', grupo: '', ronda: 1, puntos: a.value.puntos,
                carreras: a.value.carreras, carrerasTotal: 0, victorias: a.value.victorias,
                posicionMedia: a.value.media),
            FilaTabla(userId: b.key, tipo: 'grupo', grupo: '', ronda: 1, puntos: b.value.puntos,
                carreras: b.value.carreras, carrerasTotal: 0, victorias: b.value.victorias,
                posicionMedia: b.value.media),
          ));
    final garage = rankingGarage(_carreras);

    final tablaLiga = _TablaRanking(
      titulo: '🏆 Liga · fase de grupos',
      vacio: 'La Liga todavía no empieza.',
      yo: _yo,
      jugadores: _jugadores,
      filas: [
        for (final e in filasLiga)
          (userId: e.key, puntos: e.value.puntos, carreras: e.value.carreras, victorias: e.value.victorias,
              extra: _grupoDe[e.key]),
      ],
    );
    final tablaGarage = _TablaRanking(
      titulo: '🔥 Kart Garage',
      vacio: 'Nadie ha corrido carreras libres todavía.',
      yo: _yo,
      jugadores: _jugadores,
      filas: [
        for (final g in garage)
          (userId: g.userId, puntos: g.puntos, carreras: g.carreras, victorias: g.victorias, extra: null),
      ],
    );

    if (!_esAncho) {
      return Column(children: [tablaLiga, const SizedBox(height: 16), tablaGarage]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: tablaLiga),
        const SizedBox(width: 16),
        Expanded(child: tablaGarage),
      ],
    );
  }

  // ── Kart Garage ───────────────────────────────────────────────────────────────────────────────

  Widget _buildGarage(SiColors c) {
    final libres = _carreras.where((x) => x.esLibre && !x.cancelada).toList();
    final proximas = libres.where((x) => x.pendiente).toList()
      ..sort((a, b) => (a.fechaHora ?? a.createdAt ?? DateTime(2100))
          .compareTo(b.fechaHora ?? b.createdAt ?? DateTime(2100)));
    final historial = libres.where((x) => x.completada).toList()
      ..sort((a, b) => (b.fechaHora ?? b.createdAt ?? DateTime(0))
          .compareTo(a.fechaHora ?? a.createdAt ?? DateTime(0)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Nota(
          texto: 'Kart Garage: carreras libres de 2 a 8 jugadores. No cuentan para la Liga; tienen su '
              'propio ranking (10, 7, 5, 3, 2, 1 puntos por lugar). Ábrela a todos o reta a quien quieras.',
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _crearCarreraLibre,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Crear carrera libre'),
          ),
        ),
        const SizedBox(height: 20),
        _Seccion(titulo: 'Próximas'),
        if (proximas.isEmpty)
          const _Vacio(texto: 'No hay carreras libres pendientes.')
        else
          _rejilla([for (final x in proximas) _tarjetaCarrera(x, libres)]),
        const SizedBox(height: 20),
        _Seccion(titulo: 'Historial'),
        if (historial.isEmpty)
          const _Vacio(texto: 'Todavía no se ha corrido ninguna.')
        else
          _rejilla([for (final x in historial.take(20)) _tarjetaCarrera(x, libres)]),
      ],
    );
  }

  // ── Mi perfil ─────────────────────────────────────────────────────────────────────────────────

  Widget _buildPerfil(SiColors c) {
    final yo = _miJugador!;
    final misFilas = _tabla.where((f) => f.userId == _yo).toList();
    final ligaPts = misFilas.where((f) => f.tipo == 'grupo').fold<int>(0, (s, f) => s + f.puntos);
    final ligaCarreras = misFilas.fold<int>(0, (s, f) => s + f.carreras);
    final ligaVictorias = misFilas.fold<int>(0, (s, f) => s + f.victorias);
    final garage = rankingGarage(_carreras).where((g) => g.userId == _yo).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Tarjeta(
          child: Row(
            children: [
              _Avatar(emoji: yo.avatar, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(yo.apodo, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.ink)),
                    Text(yo.nombre, style: TextStyle(fontSize: 12, color: c.ink3)),
                    if (_grupoDe[_yo] != null)
                      Text('Grupo ${_grupoDe[_yo]}', style: TextStyle(fontSize: 12, color: c.brand)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Dato(etiqueta: 'PUNTOS LIGA', valor: '$ligaPts'),
            _Dato(etiqueta: 'CARRERAS LIGA', valor: '$ligaCarreras'),
            _Dato(etiqueta: 'VICTORIAS LIGA', valor: '$ligaVictorias'),
            _Dato(etiqueta: 'KART SCORE', valor: '${garage?.puntos ?? 0}'),
            _Dato(etiqueta: 'CARRERAS LIBRES', valor: '${garage?.carreras ?? 0}'),
            _Dato(etiqueta: 'VICTORIAS LIBRES', valor: '${garage?.victorias ?? 0}'),
          ],
        ),
        const SizedBox(height: 16),
        _Tarjeta(
          titulo: 'Editar apodo y avatar',
          child: _FormJugador(
            apodoInicial: yo.apodo,
            avatarInicial: yo.avatar,
            textoBoton: 'Guardar',
            apodosOcupados: _jugadores.values
                .where((j) => j.userId != _yo)
                .map((j) => j.apodo.toLowerCase())
                .toSet(),
            onGuardar: (apodo, avatar) => _rpc(
              'torneo_registrarme',
              {'p_apodo': apodo, 'p_avatar': avatar},
              ok: 'Perfil guardado.',
            ),
          ),
        ),
      ],
    );
  }
}

String _jugadoresTexto(int n) => n == 1 ? '1 jugador inscrito' : '$n jugadores inscritos';

// ── Inscripcion ─────────────────────────────────────────────────────────────────────────────────

class _Inscripcion extends StatelessWidget {
  final int inscritos;
  final String nombreSugerido;
  final Set<String> apodosOcupados;
  final Future<bool> Function(String apodo, String avatar) onInscribir;

  const _Inscripcion({
    required this.inscritos,
    required this.nombreSugerido,
    required this.apodosOcupados,
    required this.onInscribir,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    // Sugerencia: el primer nombre, como el HTML mostraba a los jugadores.
    final sugerido = nombreSugerido.trim().isEmpty
        ? ''
        : nombreSugerido.trim().split(RegExp(r'\s+')).first;
    final apodo = sugerido.isEmpty
        ? ''
        : sugerido[0].toUpperCase() + sugerido.substring(1).toLowerCase();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: SiRadius.rXl,
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    gradient: const LinearGradient(colors: [Color(0xFF344092), Color(0xFF64C6F2)]),
                  ),
                  child: const Text('🏎️', style: TextStyle(fontSize: 28)),
                ),
                const SizedBox(height: 16),
                Text('SISOL · OFFICE CUP',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2, color: c.brand)),
                const SizedBox(height: 4),
                Text('Mario Kart Cup', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500, color: c.ink)),
                const SizedBox(height: 8),
                Text(
                  'Inscríbete con un apodo y un avatar. Tus puntos se guardan en sistemassi y todos ven '
                  'el mismo ranking. Ya hay ${_jugadoresTexto(inscritos)}.',
                  style: TextStyle(fontSize: 13, color: c.ink2, height: 1.5),
                ),
                const SizedBox(height: 20),
                _FormJugador(
                  apodoInicial: apodo,
                  avatarInicial: avataresTorneo.first,
                  textoBoton: 'Inscribirme',
                  apodosOcupados: apodosOcupados,
                  onGuardar: onInscribir,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormJugador extends StatefulWidget {
  final String apodoInicial;
  final String avatarInicial;
  final String textoBoton;
  final Set<String> apodosOcupados;
  final Future<bool> Function(String apodo, String avatar) onGuardar;

  const _FormJugador({
    required this.apodoInicial,
    required this.avatarInicial,
    required this.textoBoton,
    required this.apodosOcupados,
    required this.onGuardar,
  });

  @override
  State<_FormJugador> createState() => _FormJugadorState();
}

class _FormJugadorState extends State<_FormJugador> {
  late final _apodo = TextEditingController(text: widget.apodoInicial);
  late String _avatar = widget.avatarInicial;
  bool _guardando = false;

  @override
  void dispose() {
    _apodo.dispose();
    super.dispose();
  }

  String? get _problema {
    final a = _apodo.text.trim();
    if (a.length < 2) return 'Al menos 2 letras.';
    if (a.length > 24) return 'Máximo 24 letras.';
    if (widget.apodosOcupados.contains(a.toLowerCase())) return 'Ese apodo ya lo tiene otro jugador.';
    return null;
  }

  Future<void> _guardar() async {
    if (_problema != null) return;
    setState(() => _guardando = true);
    try {
      await widget.onGuardar(_apodo.text.trim(), _avatar);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _apodo,
          maxLength: 24,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Apodo',
            errorText: _apodo.text.isEmpty ? null : _problema,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text('Avatar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.ink3)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in avataresTorneo)
              InkWell(
                onTap: () => setState(() => _avatar = a),
                borderRadius: SiRadius.rMd,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _avatar == a ? c.brandTint : c.hover,
                    borderRadius: SiRadius.rMd,
                    border: Border.all(color: _avatar == a ? c.brand : Colors.transparent, width: 2),
                  ),
                  child: Text(a, style: const TextStyle(fontSize: 22)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _guardando || _problema != null ? null : _guardar,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          child: _guardando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.textoBoton),
        ),
      ],
    );
  }
}

// ── Piezas ──────────────────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  final String titulo;
  final String fase;
  final int inscritos;
  final Jugador? campeon;

  const _Hero({required this.titulo, required this.fase, required this.inscritos, this.campeon});

  @override
  Widget build(BuildContext context) {
    const pasos = [('inscripcion', '1 · Inscripción'), ('grupos', '2 · Grupos'), ('finales', '3 · Finales'), ('terminado', '🏆 Campeón')];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(colors: [Color(0xFF344092), Color(0xFF4B58A4)]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CAMPEONATO OFICIAL',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2, color: Color(0xFFD8F5FF))),
          const SizedBox(height: 6),
          Text(titulo, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 4),
          Text('${_jugadoresTexto(inscritos)} · ${etiquetaFase(fase)}',
              style: const TextStyle(fontSize: 13, color: Color(0xFFEDF0FF))),
          if (campeon != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFB1CB34),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('🏆 Campeón: ${campeon!.avatar} ${campeon!.apodo}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1B2600))),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in pasos)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: p.$1 == fase ? const Color(0xFF64C6F2) : Colors.white.withValues(alpha: 0.15),
                    borderRadius: SiRadius.rPill,
                  ),
                  child: Text(p.$2,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: p.$1 == fase ? const Color(0xFF12314B) : Colors.white,
                      )),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CarreraCard extends StatelessWidget {
  final String titulo;
  final Carrera carrera;
  final Map<String, Jugador> jugadores;
  final String yo;
  final String? nota;
  final List<Widget> acciones;

  const _CarreraCard({
    required this.titulo,
    required this.carrera,
    required this.jugadores,
    required this.yo,
    required this.acciones,
    this.nota,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final x = carrera;
    final (fondo, tinta) = switch (x.estado) {
      'completada' => (c.successTint, c.success),
      'por_confirmar' => (c.warnTint, c.warn),
      'cancelada' => (c.dangerTint, c.danger),
      _ => (c.brandTint, c.brand),
    };
    final conResultado = x.participantes.any((p) => p.posicion != null);
    final fecha = x.fechaHora == null
        ? 'Horario por definir'
        : DateFormat("EEE d 'de' MMM · HH:mm", 'es').format(x.fechaHora!);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rLg,
        border: Border.all(color: x.corre(yo) && x.pendiente ? c.brand : c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(titulo, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: fondo, borderRadius: SiRadius.rPill),
                child: Text(etiquetaEstado(x.estado).toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: tinta)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            x.esLibre
                ? '$fecha · ${x.abierta ? 'Abierta' : 'Por invitación'} · ${x.participantes.length}/${x.cupo}'
                : fecha,
            style: TextStyle(fontSize: 12, color: c.ink3),
          ),
          const SizedBox(height: 10),
          for (final p in conResultado ? x.enOrden : x.participantes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(p.posicion == null ? '·' : '${p.posicion}.º',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.ink3)),
                  ),
                  Text(jugadores[p.userId]?.avatar ?? '🏎️', style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      jugadores[p.userId]?.apodo ?? '?',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: c.ink,
                        fontWeight: p.userId == yo ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (p.puntos != null)
                    Text('+${p.puntos}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.success)),
                ],
              ),
            ),
          if (nota != null) ...[
            const SizedBox(height: 8),
            Text(nota!, style: TextStyle(fontSize: 12, color: c.warn)),
          ],
          if (acciones.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: acciones),
          ],
        ],
      ),
    );
  }
}

class _TablaGrupo extends StatelessWidget {
  final String grupo;
  final List<FilaTabla> filas;
  final Map<String, Jugador> jugadores;
  final String yo;
  final bool marcarClasificados;

  const _TablaGrupo({
    required this.grupo,
    required this.filas,
    required this.jugadores,
    required this.yo,
    required this.marcarClasificados,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final hechas = filas.isEmpty ? 0 : filas.map((f) => f.carreras).reduce((a, b) => a + b);
    final total = filas.isEmpty ? 0 : filas.map((f) => f.carrerasTotal).reduce((a, b) => a + b);
    TextStyle cab = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.ink3);

    return _Tarjeta(
      titulo: 'Grupo $grupo',
      trailing: Text(total == 0 ? '' : '${(hechas / 4).round()}/${(total / 4).round()} carreras',
          style: TextStyle(fontSize: 11, color: c.ink3)),
      child: Column(
        children: [
          Row(children: [
            SizedBox(width: 24, child: Text('#', style: cab)),
            Expanded(child: Text('JUGADOR', style: cab)),
            SizedBox(width: 40, child: Text('PJ', style: cab, textAlign: TextAlign.right)),
            SizedBox(width: 32, child: Text('V', style: cab, textAlign: TextAlign.right)),
            SizedBox(width: 44, child: Text('PTS', style: cab, textAlign: TextAlign.right)),
          ]),
          const SizedBox(height: 4),
          for (var i = 0; i < filas.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line2))),
              child: Row(children: [
                SizedBox(
                  width: 24,
                  child: Text('${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: marcarClasificados && i < 2 ? c.success : c.ink3,
                      )),
                ),
                Text(jugadores[filas[i].userId]?.avatar ?? '🏎️', style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    jugadores[filas[i].userId]?.apodo ?? '?',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.ink,
                      fontWeight: filas[i].userId == yo ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text('${filas[i].carreras}/${filas[i].carrerasTotal}',
                      textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: c.ink2)),
                ),
                SizedBox(
                  width: 32,
                  child: Text('${filas[i].victorias}',
                      textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: c.ink2)),
                ),
                SizedBox(
                  width: 44,
                  child: Text('${filas[i].puntos}',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
                ),
              ]),
            ),
          if (marcarClasificados) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Los 2 primeros pasan a finales.', style: TextStyle(fontSize: 11, color: c.success)),
            ),
          ],
        ],
      ),
    );
  }
}

class _TablaRanking extends StatelessWidget {
  final String titulo;
  final String vacio;
  final String yo;
  final Map<String, Jugador> jugadores;
  final List<({String userId, int puntos, int carreras, int victorias, String? extra})> filas;

  const _TablaRanking({
    required this.titulo,
    required this.vacio,
    required this.yo,
    required this.jugadores,
    required this.filas,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final cab = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.ink3);
    return _Tarjeta(
      titulo: titulo,
      child: filas.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(vacio, style: TextStyle(fontSize: 13, color: c.ink3)),
            )
          : Column(
              children: [
                Row(children: [
                  SizedBox(width: 28, child: Text('#', style: cab)),
                  Expanded(child: Text('JUGADOR', style: cab)),
                  SizedBox(width: 40, child: Text('CARR.', style: cab, textAlign: TextAlign.right)),
                  SizedBox(width: 32, child: Text('V', style: cab, textAlign: TextAlign.right)),
                  SizedBox(width: 48, child: Text('PTS', style: cab, textAlign: TextAlign.right)),
                ]),
                const SizedBox(height: 4),
                for (var i = 0; i < filas.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: filas[i].userId == yo ? c.brandTint : null,
                      border: Border(top: BorderSide(color: c.line2)),
                    ),
                    child: Row(children: [
                      SizedBox(
                        width: 24,
                        child: Text(i < 3 ? ['🥇', '🥈', '🥉'][i] : '${i + 1}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.ink3)),
                      ),
                      Text(jugadores[filas[i].userId]?.avatar ?? '🏎️', style: const TextStyle(fontSize: 15)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(jugadores[filas[i].userId]?.apodo ?? '?',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink)),
                            Text(
                              [
                                jugadores[filas[i].userId]?.nombre ?? '',
                                if (filas[i].extra != null) 'Grupo ${filas[i].extra}',
                              ].where((s) => s.isNotEmpty).join(' · '),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: c.ink3),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text('${filas[i].carreras}',
                            textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: c.ink2)),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text('${filas[i].victorias}',
                            textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: c.ink2)),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text('${filas[i].puntos}',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
                      ),
                    ]),
                  ),
              ],
            ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final String? titulo;
  final Widget? trailing;
  final Widget child;

  const _Tarjeta({this.titulo, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rXl,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (titulo != null) ...[
            Row(children: [
              Expanded(
                child: Text(titulo!, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  final String titulo;

  const _Seccion({required this.titulo});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(titulo, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
    );
  }
}

class _Nota extends StatelessWidget {
  final String texto;

  const _Nota({required this.texto});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.brandTint,
        borderRadius: SiRadius.rMd,
      ),
      child: Text(texto, style: TextStyle(fontSize: 13, color: c.brandInk, height: 1.5)),
    );
  }
}

class _Vacio extends StatelessWidget {
  final String texto;

  const _Vacio({required this.texto});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: SiRadius.rLg,
        border: Border.all(color: c.line),
      ),
      child: Text(texto, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.ink3)),
    );
  }
}

class _Dato extends StatelessWidget {
  final String etiqueta;
  final String valor;

  const _Dato({required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rLg,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: c.ink3)),
          const SizedBox(height: 6),
          Text(valor, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.ink)),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String emoji;
  final double size;

  const _Avatar({required this.emoji, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.brandTint, shape: BoxShape.circle),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

// ── Dialogos ────────────────────────────────────────────────────────────────────────────────────

/// Un desplegable por lugar, como en el HTML. Devuelve los ids del 1.º al último.
class _CapturaDialog extends StatefulWidget {
  final Carrera carrera;
  final Map<String, Jugador> jugadores;
  final List<int> puntos;
  final bool directo;

  const _CapturaDialog({
    required this.carrera,
    required this.jugadores,
    required this.puntos,
    required this.directo,
  });

  @override
  State<_CapturaDialog> createState() => _CapturaDialogState();
}

class _CapturaDialogState extends State<_CapturaDialog> {
  late final List<String?> _lugares;

  @override
  void initState() {
    super.initState();
    final n = widget.carrera.participantes.length;
    _lugares = List<String?>.filled(n, null);
    // Si ya habia un resultado (corregir), se parte de el.
    for (final p in widget.carrera.participantes) {
      final pos = p.posicion;
      if (pos != null && pos >= 1 && pos <= n) _lugares[pos - 1] = p.userId;
    }
  }

  bool get _completo => !_lugares.contains(null) && _lugares.toSet().length == _lugares.length;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final ids = widget.carrera.participantes.map((p) => p.userId).toList();
    return AlertDialog(
      title: const Text('Resultado de la carrera'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.directo
                    ? 'Como organizador, el resultado cuenta en cuanto lo guardas.'
                    : 'Otro jugador de la carrera tiene que confirmarlo para que cuente.',
                style: TextStyle(fontSize: 12, color: c.ink3),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _lugares.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DropdownButtonFormField<String>(
                    initialValue: _lugares[i],
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: '${i + 1}.º lugar  (+${i < widget.puntos.length ? widget.puntos[i] : 0})',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final id in ids)
                        DropdownMenuItem(
                          value: id,
                          child: Text(
                            '${widget.jugadores[id]?.avatar ?? ''} ${widget.jugadores[id]?.apodo ?? '?'}',
                            style: TextStyle(
                              color: _lugares.contains(id) && _lugares[i] != id ? c.ink4 : c.ink,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      // Elegir a alguien que ya estaba en otro lugar lo mueve aqui.
                      final antes = _lugares.indexOf(v);
                      if (antes != -1 && antes != i) _lugares[antes] = null;
                      _lugares[i] = v;
                    }),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _completo ? () => Navigator.pop(context, _lugares.cast<String>()) : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _NuevaCarrera {
  final DateTime? fecha;
  final bool abierta;
  final int cupo;
  final List<String> invitados;

  const _NuevaCarrera({this.fecha, required this.abierta, required this.cupo, required this.invitados});
}

class _NuevaCarreraDialog extends StatefulWidget {
  final List<Jugador> jugadores;

  const _NuevaCarreraDialog({required this.jugadores});

  @override
  State<_NuevaCarreraDialog> createState() => _NuevaCarreraDialogState();
}

class _NuevaCarreraDialogState extends State<_NuevaCarreraDialog> {
  DateTime? _fecha;
  bool _abierta = true;
  int _cupo = 4;
  final Set<String> _invitados = {};
  String _filtro = '';

  String? get _problema {
    if (!_abierta && _invitados.isEmpty) return 'Invita al menos a un jugador.';
    if (_invitados.length + 1 > _cupo) return 'Invitaste a más de los que caben.';
    return null;
  }

  Future<void> _elegirFecha() async {
    final base = _fecha ?? DateTime.now();
    final dia = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (dia == null || !mounted) return;
    final hora = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (hora == null) return;
    setState(() => _fecha = DateTime(dia.year, dia.month, dia.day, hora.hour, hora.minute));
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final visibles = widget.jugadores
        .where((j) =>
            _filtro.isEmpty ||
            j.apodo.toLowerCase().contains(_filtro) ||
            j.nombre.toLowerCase().contains(_filtro))
        .toList();

    return AlertDialog(
      title: const Text('Carrera libre'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _elegirFecha,
                icon: const Icon(Icons.schedule, size: 16),
                label: Text(_fecha == null
                    ? 'Fecha y hora (opcional)'
                    : DateFormat("EEE d 'de' MMM · HH:mm", 'es').format(_fecha!)),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('🔓 Abierta')),
                  ButtonSegment(value: false, label: Text('🔒 Por invitación')),
                ],
                selected: {_abierta},
                onSelectionChanged: (s) => setState(() => _abierta = s.first),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _cupo,
                decoration: const InputDecoration(labelText: 'Cupo', border: OutlineInputBorder(), isDense: true),
                items: [for (var i = 2; i <= 8; i++) DropdownMenuItem(value: i, child: Text('$i jugadores'))],
                onChanged: (v) => setState(() => _cupo = v ?? 4),
              ),
              const SizedBox(height: 12),
              Text(_abierta ? 'Invitados (opcional)' : 'Invitados',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.ink3)),
              const SizedBox(height: 6),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar jugador',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _filtro = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final j in visibles)
                        FilterChip(
                          label: Text('${j.avatar} ${j.apodo}'),
                          selected: _invitados.contains(j.userId),
                          onSelected: (s) => setState(() {
                            s ? _invitados.add(j.userId) : _invitados.remove(j.userId);
                          }),
                        ),
                      if (visibles.isEmpty)
                        Text(
                          widget.jugadores.isEmpty
                              ? 'Todavía no hay nadie más inscrito.'
                              : 'Nadie más inscrito con ese nombre.',
                          style: TextStyle(fontSize: 12, color: c.ink3),
                        ),
                    ],
                  ),
                ),
              ),
              if (_problema != null) ...[
                const SizedBox(height: 8),
                Text(_problema!, style: TextStyle(fontSize: 12, color: c.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _problema != null
              ? null
              : () => Navigator.pop(
                    context,
                    _NuevaCarrera(fecha: _fecha, abierta: _abierta, cupo: _cupo, invitados: _invitados.toList()),
                  ),
          child: const Text('Crear'),
        ),
      ],
    );
  }
}
