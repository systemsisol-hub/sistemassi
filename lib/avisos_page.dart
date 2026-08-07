import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'avisos_store.dart';
import 'theme/si_theme.dart';
import 'widgets/banner_avisos.dart';
import 'widgets/dialogo_aviso.dart';
import 'widgets/lista_avisos.dart';

/// Gestión de avisos: los redacta, programa y apaga quien tenga el permiso `show_avisos`.
///
/// La página lee `avisos` directo, no `avisos_para_mi`: hace falta ver también los apagados y los
/// programados para el futuro, que son justo los que se van a editar. Quién puede hacerlo lo decide
/// RLS, no esta pantalla.
class AvisosPage extends StatefulWidget {
  const AvisosPage({super.key});

  @override
  State<AvisosPage> createState() => _AvisosPageState();
}

class _AvisosPageState extends State<AvisosPage> {
  final _supabase = Supabase.instance.client;

  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _avisos = [];
  Map<String, int> _vistos = {};

  /// Valores que existen de verdad en los perfiles activos, para el formulario de destinatarios.
  List<String> _ubicaciones = [];
  List<String> _areas = [];
  List<String> _empresas = [];

  String _filtro = 'todos';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final avisos = await _supabase
          .from('avisos')
          .select()
          .order('creado_en', ascending: false);
      _avisos = List<Map<String, dynamic>>.from(avisos);

      final conteo = await _supabase.from('avisos_conteo_vistos').select();
      _vistos = {
        for (final f in List<Map<String, dynamic>>.from(conteo))
          f['aviso_id'].toString(): (f['vistos'] as num?)?.toInt() ?? 0
      };

      // Sólo de perfiles ACTIVO: de los 2 488 registros apenas 90 lo están, y ofrecer las
      // ubicaciones de gente dada de baja llenaría el desplegable de destinos que no alcanzan a nadie.
      final perfiles = await _supabase
          .from('profiles')
          .select('ubicacion, area, empresa')
          .eq('status_sys', 'ACTIVO');
      final filas = List<Map<String, dynamic>>.from(perfiles);
      _ubicaciones = _valoresDe(filas, 'ubicacion');
      _areas = _valoresDe(filas, 'area');
      _empresas = _valoresDe(filas, 'empresa');

      if (mounted) setState(() => _cargando = false);
    } catch (e) {
      debugPrint('avisos: $e');
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  static List<String> _valoresDe(
      List<Map<String, dynamic>> filas, String campo) {
    final valores = <String>{};
    for (final f in filas) {
      final v = (f[campo] ?? '').toString().trim();
      if (v.isNotEmpty) valores.add(v);
    }
    final lista = valores.toList()..sort();
    return lista;
  }

  List<Map<String, dynamic>> get _filtrados => _conFiltro(_filtro);

  /// Los avisos que pasan un filtro dado.
  ///
  /// Recibe el filtro por parámetro en lugar de leer `_filtro`, para que la barra pueda contar cada
  /// pestaña sin tocar el estado: la versión anterior asignaba `_filtro`, contaba y lo restauraba
  /// —mutar estado dentro de `build` funciona por accidente y se rompe en cuanto algo notifique.
  List<Map<String, dynamic>> _conFiltro(String filtro) {
    final ahora = DateTime.now();
    return _avisos.where((a) {
      switch (filtro) {
        case 'vigentes':
          return a['activo'] == true && _estaVigente(a, ahora);
        case 'programados':
          final desde = DateTime.tryParse((a['desde'] ?? '').toString());
          return a['activo'] == true && desde != null && desde.isAfter(ahora);
        case 'vencidos':
          final hasta = DateTime.tryParse((a['hasta'] ?? '').toString());
          return hasta != null && hasta.isBefore(ahora);
        case 'apagados':
          return a['activo'] != true;
        default:
          return true;
      }
    }).toList();
  }

  static bool _estaVigente(Map<String, dynamic> a, DateTime ahora) {
    final desde = DateTime.tryParse((a['desde'] ?? '').toString());
    final hasta = DateTime.tryParse((a['hasta'] ?? '').toString());
    if (desde != null && desde.isAfter(ahora)) return false;
    if (hasta != null && hasta.isBefore(ahora)) return false;
    return true;
  }

  Future<void> _alternarActivo(Map<String, dynamic> a) async {
    final nuevo = a['activo'] != true;
    try {
      await _supabase.from('avisos').update({
        'activo': nuevo,
        'actualizado_en': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', a['id']);
      await _cargar();
    } catch (e) {
      _avisar('No se pudo cambiar el estado: $e', esError: true);
    }
  }

  Future<void> _borrar(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar el aviso?'),
        content: Text(
            '«${a['titulo']}» se elimina junto con el registro de quién lo vio. '
            'Si sólo quieres que deje de aparecer, apágalo en lugar de borrarlo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supabase.from('avisos').delete().eq('id', a['id']);
      await _cargar();
    } catch (e) {
      _avisar('No se pudo borrar: $e', esError: true);
    }
  }

  void _avisar(String texto, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: esError ? Colors.red : null,
    ));
  }

  Future<void> _abrirFormulario([Map<String, dynamic>? aviso]) async {
    final guardado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FormularioAviso(
        aviso: aviso,
        ubicaciones: _ubicaciones,
        areas: _areas,
        empresas: _empresas,
      ),
    );
    if (guardado == true) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    return Scaffold(
      backgroundColor: c.bg,
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: c.brand))
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(SiSpace.x6),
                  child: Text('No se pudieron leer los avisos: $_error',
                      style: TextStyle(fontSize: 13, color: c.danger)),
                )
              : Column(
                  children: [
                    _barra(c),
                    Expanded(child: _lista(c)),
                  ],
                ),
    );
  }

  Widget _barra(SiColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          SiSpace.x5, SiSpace.x3, SiSpace.x5, SiSpace.x3),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Icon(Icons.campaign_outlined, size: 18, color: c.brand),
          const SizedBox(width: SiSpace.x2),
          Text('Avisos',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(width: SiSpace.x5),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (valor, etiqueta) in const [
                  ('todos', 'Todos'),
                  ('vigentes', 'Vigentes'),
                  ('programados', 'Programados'),
                  ('vencidos', 'Vencidos'),
                  ('apagados', 'Apagados'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: SiSpace.x2),
                    child: _chip(c, valor, etiqueta, _conFiltro(valor).length),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: SiSpace.x3),
          FilledButton.icon(
            onPressed: () => _abrirFormulario(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nuevo aviso'),
          ),
        ],
      ),
    );
  }

  Widget _chip(SiColors c, String valor, String etiqueta, int n) {
    final activo = _filtro == valor;
    return InkWell(
      onTap: () => setState(() => _filtro = valor),
      borderRadius: SiRadius.rPill,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: activo ? c.brand : c.panel,
          borderRadius: SiRadius.rPill,
          border: Border.all(color: activo ? c.brand : c.line),
        ),
        child: Text('$etiqueta ($n)',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: activo ? Colors.white : c.ink2)),
      ),
    );
  }

  Widget _lista(SiColors c) {
    final filas = _filtrados;
    if (filas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SiSpace.x10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.campaign_outlined, size: 36, color: c.ink4),
              const SizedBox(height: SiSpace.x3),
              Text(
                  _avisos.isEmpty
                      ? 'Todavía no hay avisos. El botón «Nuevo aviso» crea el primero.'
                      : 'Ningún aviso coincide con el filtro',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: c.ink3)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(SiSpace.x5),
      itemCount: filas.length,
      separatorBuilder: (_, __) => const SizedBox(height: SiSpace.x3),
      itemBuilder: (_, i) => _tarjeta(c, filas[i]),
    );
  }

  Widget _tarjeta(SiColors c, Map<String, dynamic> a) {
    final aviso = Aviso.desde(a);
    final (color, fondo, icono) = colorDeNivel(c, aviso.nivel);
    final apagado = a['activo'] != true;
    final vistos = _vistos[aviso.id] ?? 0;

    return Opacity(
      // Un aviso apagado se atenúa en lugar de esconderse: sigue estando y se puede volver a prender.
      opacity: apagado ? 0.55 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: SiRadius.rMd,
          border: Border.all(color: c.line),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: fondo,
              padding: const EdgeInsets.symmetric(
                  horizontal: SiSpace.x4, vertical: SiSpace.x2),
              child: Row(
                children: [
                  Icon(icono, size: 16, color: color),
                  const SizedBox(width: SiSpace.x2),
                  Expanded(
                    child: Text(aviso.titulo,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: c.ink)),
                  ),
                  for (final (activa, etiqueta) in [
                    (aviso.enModal, 'Emergente'),
                    (aviso.enBanner, 'Banner'),
                    (aviso.enSocial, 'Social'),
                  ])
                    if (activa)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.panel,
                            borderRadius: SiRadius.rPill,
                            border: Border.all(color: c.line),
                          ),
                          child: Text(etiqueta,
                              style: TextStyle(fontSize: 10, color: c.ink2)),
                        ),
                      ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(SiSpace.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(aviso.cuerpo,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, height: 1.4, color: c.ink2)),
                  const SizedBox(height: SiSpace.x3),
                  Wrap(
                    spacing: SiSpace.x2,
                    runSpacing: SiSpace.x2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _dato(c, Icons.event_outlined, _vigencia(a)),
                      _dato(c, Icons.groups_outlined, _destino(a)),
                      _dato(c, Icons.visibility_outlined,
                          '$vistos ${vistos == 1 ? 'acuse' : 'acuses'}'),
                      if (aviso.insistir)
                        _dato(c, Icons.repeat, 'Insiste cada sesión'),
                      if (apagado) _dato(c, Icons.pause_circle_outline, 'Apagado'),
                    ],
                  ),
                  const SizedBox(height: SiSpace.x3),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => _vistaPrevia(aviso),
                        icon: const Icon(Icons.visibility_outlined, size: 16),
                        label: const Text('Vista previa'),
                      ),
                      TextButton.icon(
                        onPressed: () => _abrirFormulario(a),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Editar'),
                      ),
                      TextButton.icon(
                        onPressed: () => _alternarActivo(a),
                        icon: Icon(
                            apagado
                                ? Icons.play_arrow_outlined
                                : Icons.pause_outlined,
                            size: 16),
                        label: Text(apagado ? 'Prender' : 'Apagar'),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => _borrar(a),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: c.danger,
                        tooltip: 'Borrar',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dato(SiColors c, IconData icono, String texto) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: SiRadius.rPill,
          border: Border.all(color: c.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icono, size: 12, color: c.ink3),
          const SizedBox(width: 5),
          Text(texto, style: TextStyle(fontSize: 11, color: c.ink2)),
        ]),
      );

  String _vigencia(Map<String, dynamic> a) {
    final desde = DateTime.tryParse((a['desde'] ?? '').toString());
    final hasta = DateTime.tryParse((a['hasta'] ?? '').toString());
    final f = DateFormat('d MMM y', 'es_MX');
    if (desde == null) return 'Sin fecha';
    if (hasta == null) return 'Desde ${f.format(desde.toLocal())}, sin caducidad';
    return '${f.format(desde.toLocal())} – ${f.format(hasta.toLocal())}';
  }

  String _destino(Map<String, dynamic> a) {
    if (a['para_todos'] == true) return 'Todos';
    final partes = <String>[];
    void agregar(String campo, String etiqueta) {
      final v = (a[campo] as List?)?.cast<String>() ?? const [];
      if (v.isEmpty) return;
      partes.add(v.length == 1 ? v.first : '${v.length} $etiqueta');
    }

    agregar('ubicaciones', 'ubicaciones');
    agregar('areas', 'áreas');
    agregar('empresas', 'empresas');
    agregar('roles', 'roles');
    return partes.isEmpty ? 'Sin destino' : partes.join(' · ');
  }

  /// Muestra el aviso como lo verá la gente, en los canales que tenga prendidos.
  ///
  /// Sin esto habría que prender un aviso de verdad para saber cómo queda, y un aviso de prueba
  /// visible para toda la empresa es exactamente lo que no se quiere.
  void _vistaPrevia(Aviso aviso) {
    final c = SiColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: c.panel,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SiSpace.x5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Icon(Icons.visibility_outlined, size: 18, color: c.brand),
                  const SizedBox(width: SiSpace.x2),
                  Text('Vista previa',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.ink)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ]),
                const SizedBox(height: SiSpace.x4),
                if (aviso.enBanner) ...[
                  _rotulo(c, 'Banner bajo la barra'),
                  BannerAvisos(avisos: [aviso], alDescartar: (_) {}),
                  const SizedBox(height: SiSpace.x5),
                ],
                if (aviso.enSocial) ...[
                  _rotulo(c, 'Muro social'),
                  ListaAvisos(avisos: [aviso]),
                  const SizedBox(height: SiSpace.x5),
                ],
                if (aviso.enModal) ...[
                  _rotulo(c, 'Ventana emergente'),
                  OutlinedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => DialogoAviso(aviso: aviso),
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Ver la ventana'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rotulo(SiColors c, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(texto.toUpperCase(),
            style: SiType.mono(size: 9.5, color: c.ink3, letterSpacing: 0.8)),
      );
}

// ── Formulario ───────────────────────────────────────────────────────────────

class _FormularioAviso extends StatefulWidget {
  const _FormularioAviso({
    required this.aviso,
    required this.ubicaciones,
    required this.areas,
    required this.empresas,
  });

  final Map<String, dynamic>? aviso;
  final List<String> ubicaciones;
  final List<String> areas;
  final List<String> empresas;

  @override
  State<_FormularioAviso> createState() => _FormularioAvisoState();
}

class _FormularioAvisoState extends State<_FormularioAviso> {
  final _titulo = TextEditingController();
  final _cuerpo = TextEditingController();

  NivelAviso _nivel = NivelAviso.info;
  bool _enModal = false;
  bool _enBanner = true;
  bool _enSocial = false;
  bool _insistir = false;
  bool _paraTodos = true;
  final Set<String> _ubicaciones = {};
  final Set<String> _areas = {};
  final Set<String> _empresas = {};
  DateTime _desde = DateTime.now();
  DateTime? _hasta;

  bool _guardando = false;
  int? _alcance;

  @override
  void initState() {
    super.initState();
    final a = widget.aviso;
    if (a != null) {
      _titulo.text = (a['titulo'] ?? '').toString();
      _cuerpo.text = (a['cuerpo'] ?? '').toString();
      _nivel = Aviso.desde(a).nivel;
      _enModal = a['en_modal'] == true;
      _enBanner = a['en_banner'] == true;
      _enSocial = a['en_social'] == true;
      _insistir = a['insistir'] == true;
      _paraTodos = a['para_todos'] == true;
      _ubicaciones.addAll(((a['ubicaciones'] as List?) ?? []).cast<String>());
      _areas.addAll(((a['areas'] as List?) ?? []).cast<String>());
      _empresas.addAll(((a['empresas'] as List?) ?? []).cast<String>());
      _desde = DateTime.tryParse((a['desde'] ?? '').toString())?.toLocal() ??
          DateTime.now();
      _hasta = DateTime.tryParse((a['hasta'] ?? '').toString())?.toLocal();
    }
    _calcularAlcance();
  }

  @override
  void dispose() {
    _titulo.dispose();
    _cuerpo.dispose();
    super.dispose();
  }

  /// A cuánta gente activa alcanza la segmentación actual.
  ///
  /// Se cuenta contra `profiles` con los mismos cruces que la función de la base —dimensiones con AND,
  /// valores con OR— para que el número no prometa algo distinto de lo que hará el aviso. Sin este
  /// dato es fácil publicar un aviso que no le llega a nadie y no enterarse.
  Future<void> _calcularAlcance() async {
    try {
      var q = Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('status_sys', 'ACTIVO');
      if (!_paraTodos) {
        if (_ubicaciones.isNotEmpty) {
          q = q.inFilter('ubicacion', _ubicaciones.toList());
        }
        if (_areas.isNotEmpty) q = q.inFilter('area', _areas.toList());
        if (_empresas.isNotEmpty) q = q.inFilter('empresa', _empresas.toList());
      }
      final filas = await q;
      if (mounted) {
        setState(() => _alcance = List<Map<String, dynamic>>.from(filas).length);
      }
    } catch (_) {
      if (mounted) setState(() => _alcance = null);
    }
  }

  bool get _hayDestino =>
      _paraTodos ||
      _ubicaciones.isNotEmpty ||
      _areas.isNotEmpty ||
      _empresas.isNotEmpty;

  bool get _hayCanal => _enModal || _enBanner || _enSocial;

  String? get _problema {
    if (_titulo.text.trim().isEmpty) return 'Falta el título.';
    if (_cuerpo.text.trim().isEmpty) return 'Falta el texto del aviso.';
    if (!_hayCanal) return 'Elige al menos un lugar donde mostrarlo.';
    if (!_hayDestino) return 'Elige a quién va dirigido.';
    if (_hasta != null && !_hasta!.isAfter(_desde)) {
      return 'La fecha de fin tiene que ser posterior a la de inicio.';
    }
    return null;
  }

  Future<void> _guardar() async {
    final problema = _problema;
    if (problema != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(problema)));
      return;
    }
    setState(() => _guardando = true);
    try {
      final datos = {
        'titulo': _titulo.text.trim(),
        'cuerpo': _cuerpo.text.trim(),
        'nivel': switch (_nivel) {
          NivelAviso.critico => 'CRITICO',
          NivelAviso.advertencia => 'ADVERTENCIA',
          NivelAviso.info => 'INFO',
        },
        'en_modal': _enModal,
        'en_banner': _enBanner,
        'en_social': _enSocial,
        'insistir': _insistir,
        'para_todos': _paraTodos,
        // Dirigido a todos, las listas se limpian: dejarlas guardadas haría que al reactivar
        // «dirigido» reaparecieran destinos viejos que nadie volvió a revisar.
        'ubicaciones': _paraTodos ? [] : _ubicaciones.toList(),
        'areas': _paraTodos ? [] : _areas.toList(),
        'empresas': _paraTodos ? [] : _empresas.toList(),
        'desde': _desde.toUtc().toIso8601String(),
        'hasta': _hasta?.toUtc().toIso8601String(),
      };

      final cliente = Supabase.instance.client;
      if (widget.aviso == null) {
        datos['creado_por'] = cliente.auth.currentUser?.id;
        await cliente.from('avisos').insert(datos);
      } else {
        datos['actualizado_en'] = DateTime.now().toUtc().toIso8601String();
        await cliente.from('avisos').update(datos).eq('id', widget.aviso!['id']);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo guardar: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _elegirFecha({required bool esDesde}) async {
    final inicial = esDesde ? _desde : (_hasta ?? _desde);
    final elegida = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 3),
    );
    if (elegida == null) return;
    setState(() {
      if (esDesde) {
        _desde = elegida;
      } else {
        // Fin del día: elegir el 12 de agosto debe incluir el 12 completo, no cortarlo a medianoche.
        _hasta = DateTime(elegida.year, elegida.month, elegida.day, 23, 59, 59);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    return Dialog(
      backgroundColor: c.panel,
      insetPadding: const EdgeInsets.all(SiSpace.x6),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(SiSpace.x5),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(children: [
                Icon(Icons.campaign_outlined, size: 18, color: c.brand),
                const SizedBox(width: SiSpace.x2),
                Text(widget.aviso == null ? 'Nuevo aviso' : 'Editar aviso',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink)),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(SiSpace.x5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _titulo,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Título',
                        border: OutlineInputBorder(borderRadius: SiRadius.rMd),
                      ),
                    ),
                    const SizedBox(height: SiSpace.x4),
                    TextField(
                      controller: _cuerpo,
                      onChanged: (_) => setState(() {}),
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Texto del aviso',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(borderRadius: SiRadius.rMd),
                      ),
                    ),
                    const SizedBox(height: SiSpace.x5),
                    _rotulo(c, 'Nivel'),
                    Row(
                      children: [
                        for (final n in NivelAviso.values)
                          Padding(
                            padding: const EdgeInsets.only(right: SiSpace.x2),
                            child: _pastillaNivel(c, n),
                          ),
                      ],
                    ),
                    const SizedBox(height: SiSpace.x5),
                    _rotulo(c, 'Dónde se muestra'),
                    _casilla(c, 'Ventana emergente', _enModal,
                        (v) => setState(() => _enModal = v),
                        ayuda: 'Se abre encima de todo al entrar al sistema'),
                    if (_enModal)
                      Padding(
                        padding: const EdgeInsets.only(left: SiSpace.x6),
                        child: _casilla(c, 'Insistir en cada sesión', _insistir,
                            (v) => setState(() => _insistir = v),
                            ayuda:
                                'Vuelve a aparecer aunque ya lo hayan cerrado'),
                      ),
                    _casilla(c, 'Banner bajo la barra', _enBanner,
                        (v) => setState(() => _enBanner = v),
                        ayuda: 'Una franja de color, se puede descartar'),
                    _casilla(c, 'Muro social', _enSocial,
                        (v) => setState(() => _enSocial = v),
                        ayuda: 'Queda como consulta en la página Social'),
                    const SizedBox(height: SiSpace.x5),
                    _rotulo(c, 'Vigencia'),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _elegirFecha(esDesde: true),
                          icon: const Icon(Icons.event_outlined, size: 16),
                          label: Text('Desde ${_fecha(_desde)}'),
                        ),
                      ),
                      const SizedBox(width: SiSpace.x2),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _elegirFecha(esDesde: false),
                          icon: const Icon(Icons.event_busy_outlined, size: 16),
                          label: Text(_hasta == null
                              ? 'Sin caducidad'
                              : 'Hasta ${_fecha(_hasta!)}'),
                        ),
                      ),
                      if (_hasta != null)
                        IconButton(
                          onPressed: () => setState(() => _hasta = null),
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: 'Quitar la fecha de fin',
                        ),
                    ]),
                    const SizedBox(height: SiSpace.x5),
                    _rotulo(c, 'Destinatarios'),
                    Row(children: [
                      _opcionDestino(c, 'Todos', true),
                      const SizedBox(width: SiSpace.x2),
                      _opcionDestino(c, 'Dirigido a', false),
                    ]),
                    if (!_paraTodos) ...[
                      const SizedBox(height: SiSpace.x2),
                      _selector(c, 'Ubicaciones', widget.ubicaciones, _ubicaciones),
                      _selector(c, 'Áreas', widget.areas, _areas),
                      _selector(c, 'Empresas', widget.empresas, _empresas),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                            'Se cruzan: elegir una ubicación y un área alcanza a quien cumple las dos.',
                            style: TextStyle(fontSize: 11, color: c.ink4)),
                      ),
                    ],
                    const SizedBox(height: SiSpace.x3),
                    Row(children: [
                      Icon(Icons.groups_outlined, size: 14, color: c.ink3),
                      const SizedBox(width: 6),
                      Text(
                        _alcance == null
                            ? 'Alcance sin calcular'
                            : 'Alcanza a $_alcance ${_alcance == 1 ? 'persona' : 'personas'} activas',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _alcance == 0 ? c.danger : c.ink2),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(SiSpace.x4),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  if (_problema != null)
                    Expanded(
                      child: Text(_problema!,
                          style: TextStyle(fontSize: 11.5, color: c.warn)),
                    )
                  else
                    const Spacer(),
                  TextButton(
                    onPressed: _guardando
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: SiSpace.x2),
                  FilledButton(
                    onPressed:
                        _guardando || _problema != null ? null : _guardar,
                    child: Text(_guardando ? 'Guardando…' : 'Guardar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rotulo(SiColors c, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(texto.toUpperCase(),
            style: SiType.mono(size: 9.5, color: c.ink3, letterSpacing: 0.8)),
      );

  /// Todos / Dirigido a. Se usan pastillas y no RadioListTile porque su API de grupo quedó
  /// deprecada, y porque así el formulario tiene un solo lenguaje visual con el selector de nivel.
  Widget _opcionDestino(SiColors c, String etiqueta, bool valor) {
    final activo = _paraTodos == valor;
    return InkWell(
      onTap: () {
        setState(() => _paraTodos = valor);
        _calcularAlcance();
      },
      borderRadius: SiRadius.rPill,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: activo ? c.brandTint : c.panel,
          borderRadius: SiRadius.rPill,
          border: Border.all(
              color: activo ? c.brand : c.line, width: activo ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(activo ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 14, color: activo ? c.brand : c.ink3),
          const SizedBox(width: 6),
          Text(etiqueta,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: activo ? FontWeight.w700 : FontWeight.w400,
                  color: activo ? c.ink : c.ink2)),
        ]),
      ),
    );
  }

  Widget _pastillaNivel(SiColors c, NivelAviso n) {
    final (color, fondo, icono) = colorDeNivel(c, n);
    final activo = _nivel == n;
    return InkWell(
      onTap: () => setState(() => _nivel = n),
      borderRadius: SiRadius.rPill,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: activo ? fondo : c.panel,
          borderRadius: SiRadius.rPill,
          border: Border.all(color: activo ? color : c.line, width: activo ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icono, size: 14, color: activo ? color : c.ink3),
          const SizedBox(width: 6),
          Text(etiquetaDeNivel(n),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: activo ? FontWeight.w700 : FontWeight.w400,
                  color: activo ? c.ink : c.ink2)),
        ]),
      ),
    );
  }

  Widget _casilla(SiColors c, String etiqueta, bool valor,
          void Function(bool) alCambiar, {String? ayuda}) =>
      CheckboxListTile(
        value: valor,
        onChanged: (v) => alCambiar(v == true),
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(etiqueta, style: const TextStyle(fontSize: 13)),
        subtitle: ayuda == null
            ? null
            : Text(ayuda, style: TextStyle(fontSize: 11, color: c.ink4)),
      );

  /// Selector de varios valores. Un desplegable no sirve: hay 74 ubicaciones y se pueden elegir
  /// varias, así que se listan como pastillas que se prenden y apagan.
  Widget _selector(
      SiColors c, String titulo, List<String> opciones, Set<String> elegidos) {
    if (opciones.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: SiSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$titulo (${elegidos.length} de ${opciones.length})',
              style: TextStyle(fontSize: 11.5, color: c.ink3)),
          const SizedBox(height: 4),
          // Tope de alto: con 74 ubicaciones la lista completa empujaría el resto del formulario
          // fuera de la pantalla.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 116),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final o in opciones)
                    InkWell(
                      onTap: () {
                        setState(() {
                          elegidos.contains(o)
                              ? elegidos.remove(o)
                              : elegidos.add(o);
                        });
                        _calcularAlcance();
                      },
                      borderRadius: SiRadius.rPill,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: elegidos.contains(o) ? c.brand : c.panel,
                          borderRadius: SiRadius.rPill,
                          border: Border.all(
                              color: elegidos.contains(o) ? c.brand : c.line),
                        ),
                        child: Text(o,
                            style: TextStyle(
                                fontSize: 11.5,
                                color: elegidos.contains(o)
                                    ? Colors.white
                                    : c.ink2)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fecha(DateTime d) {
    try {
      return DateFormat('d MMM y', 'es_MX').format(d);
    } catch (_) {
      return '${d.day}/${d.month}/${d.year}';
    }
  }
}
