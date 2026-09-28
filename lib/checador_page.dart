import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/checador.dart';
import 'theme/si_theme.dart';

/// El checador propio del sistema. Pedido del usuario el 28/09/2026.
///
/// Dos piezas:
///
/// * [ChecadorPropio] — la pestaña de todos: checar con foto en vivo, hora del servidor y GPS, y
///   ver las propias checadas.
/// * [ChecadorRegistros] — la de administradores: las checadas de todos por día, con su foto y su
///   ubicación.
///
/// Es independiente de appchecar —«lo dejaremos de usar»—: lee y escribe sólo `checadas` y el
/// bucket `checador-fotos`. Las reglas —qué se puede checar y en qué orden— las pone la base en
/// `checada_antes_de_guardar`; la pantalla sólo ofrece lo que la base aceptaría.

const _bucket = 'checador-fotos';

final _supabase = Supabase.instance.client;

/// URLs firmadas de las fotos, por ruta. Una hora de vida, y se reusan mientras duran.
final Map<String, (String, DateTime)> _urlsFotos = {};

Future<String?> _urlFoto(String ruta) async {
  final guardada = _urlsFotos[ruta];
  if (guardada != null && guardada.$2.isAfter(DateTime.now())) return guardada.$1;
  try {
    final url = await _supabase.storage.from(_bucket).createSignedUrl(ruta, 3600);
    _urlsFotos[ruta] = (url, DateTime.now().add(const Duration(minutes: 55)));
    return url;
  } catch (e) {
    debugPrint('checador: no se pudo firmar la foto: $e');
    return null;
  }
}

String _hora(dynamic iso) {
  final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  return d == null ? '—' : DateFormat('HH:mm').format(d);
}

String _fechaLarga(DateTime d) {
  final t = DateFormat("EEEE d 'de' MMMM", 'es_MX').format(d);
  return t[0].toUpperCase() + t.substring(1);
}

String _hoyISO() => DateFormat('yyyy-MM-dd').format(DateTime.now());

// ─────────────────────────────────────────────────────────────────────────────
// La pestaña de todos
// ─────────────────────────────────────────────────────────────────────────────

class ChecadorPropio extends StatefulWidget {
  const ChecadorPropio({super.key});

  @override
  State<ChecadorPropio> createState() => _ChecadorPropioState();
}

class _ChecadorPropioState extends State<ChecadorPropio> {
  bool _cargando = true;
  String? _error;

  /// Las propias de los últimos 14 días, de la más reciente a la más vieja.
  List<Map<String, dynamic>> _checadas = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    setState(() { _cargando = true; _error = null; });
    try {
      final desde = DateFormat('yyyy-MM-dd')
          .format(DateTime.now().subtract(const Duration(days: 13)));
      final r = await _supabase
          .from('checadas')
          .select('id, tipo, registrada_en, fecha, latitud, longitud, precision_m, foto')
          .eq('profile_id', uid)
          .gte('fecha', desde)
          .order('registrada_en', ascending: false);
      if (!mounted) return;
      setState(() {
        _checadas = (r as List).cast<Map<String, dynamic>>();
        _cargando = false;
      });
    } catch (e) {
      debugPrint('checador: no se pudieron leer las checadas: $e');
      if (mounted) setState(() { _cargando = false; _error = '$e'; });
    }
  }

  /// Las de HOY por tipo. «Hoy» es el día que puso la base, en hora del centro de México.
  Map<String, Map<String, dynamic>> get _deHoy {
    final hoy = _hoyISO();
    return {
      for (final c in _checadas)
        if (c['fecha'] == hoy) c['tipo'] as String: c,
    };
  }

  Future<void> _checar(String tipo) async {
    final hecho = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CapturaChecada(tipo: tipo),
    );
    if (hecho == true) {
      await _cargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${nombreDeChecada[tipo]} registrada a las '
              '${_hora(_deHoy[tipo]?['registrada_en'])}.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    if (_cargando) return Center(child: CircularProgressIndicator(color: c.brand));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SiSpace.x6),
          child: Text('No se pudieron leer tus checadas: $_error',
              textAlign: TextAlign.center, style: TextStyle(color: c.danger)),
        ),
      );
    }

    final hoy = _deHoy;
    final posibles = checadasPosibles(hoy.keys.toSet());

    // Los días anteriores, agrupados.
    final porDia = <String, Map<String, Map<String, dynamic>>>{};
    for (final ch in _checadas) {
      if (ch['fecha'] == _hoyISO()) continue;
      porDia.putIfAbsent(ch['fecha'] as String, () => {})[ch['tipo'] as String] = ch;
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(SiSpace.x6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tarjeta(
                  c,
                  titulo: 'Hoy · ${_fechaLarga(DateTime.now())}',
                  children: [
                    for (final t in tiposDeChecada) _filaHoy(c, t, hoy[t]),
                    const SizedBox(height: SiSpace.x4),
                    if (posibles.isEmpty)
                      Text('Tu jornada de hoy está completa.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: c.ink3))
                    else
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: SiSpace.x3,
                        runSpacing: SiSpace.x3,
                        children: [
                          for (var i = 0; i < posibles.length; i++)
                            i == 0
                                ? FilledButton.icon(
                                    onPressed: () => _checar(posibles[i]),
                                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                                    label: Text('Checar ${nombreDeChecada[posibles[i]]!.toLowerCase()}'),
                                  )
                                : OutlinedButton.icon(
                                    onPressed: () => _checar(posibles[i]),
                                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                                    label: Text('Checar ${nombreDeChecada[posibles[i]]!.toLowerCase()}'),
                                  ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: SiSpace.x4),
                _tarjeta(
                  c,
                  titulo: 'Tus checadas de los últimos 14 días',
                  children: [
                    if (porDia.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: SiSpace.x3),
                        child: Text('Todavía no hay checadas anteriores.',
                            style: TextStyle(fontSize: 13, color: c.ink3)),
                      )
                    else
                      for (final e in porDia.entries) _filaDia(c, e.key, e.value),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filaHoy(SiColors c, String tipo, Map<String, dynamic>? ch) {
    return InkWell(
      onTap: ch == null ? null : () => mostrarChecada(context, ch, nombreDeChecada[tipo]!),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SiSpace.x2),
        child: Row(
          children: [
            Icon(ch == null ? Icons.radio_button_unchecked : Icons.check_circle,
                size: 18, color: ch == null ? c.ink4 : c.success),
            const SizedBox(width: SiSpace.x3),
            Expanded(
              child: Text(nombreDeChecada[tipo]!,
                  style: TextStyle(fontSize: 14, color: ch == null ? c.ink3 : c.ink)),
            ),
            Text(ch == null ? '—' : _hora(ch['registrada_en']),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ch == null ? c.ink4 : c.ink,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            if (ch != null) ...[
              const SizedBox(width: SiSpace.x2),
              Icon(Icons.chevron_right, size: 18, color: c.ink4),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filaDia(SiColors c, String fecha, Map<String, Map<String, dynamic>> deEse) {
    final d = DateTime.parse(fecha);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SiSpace.x2),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(_fechaLarga(d),
                style: TextStyle(fontSize: 12.5, color: c.ink2),
                overflow: TextOverflow.ellipsis),
          ),
          for (final t in tiposDeChecada)
            Expanded(
              child: deEse[t] == null
                  ? Text('—', textAlign: TextAlign.center, style: TextStyle(color: c.ink4))
                  : InkWell(
                      onTap: () => mostrarChecada(context, deEse[t]!, nombreDeChecada[t]!),
                      child: Text(_hora(deEse[t]!['registrada_en']),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: c.brand,
                              fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
            ),
        ],
      ),
    );
  }
}

Widget _tarjeta(SiColors c, {required String titulo, required List<Widget> children}) {
  return Container(
    padding: const EdgeInsets.all(SiSpace.x4),
    decoration: BoxDecoration(
      color: c.panel,
      border: Border.all(color: c.line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(titulo,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: SiSpace.x3),
        ...children,
      ],
    ),
  );
}

/// El detalle de una checada: la foto, la hora, la ubicación y el enlace al mapa.
Future<void> mostrarChecada(BuildContext context, Map<String, dynamic> ch, String titulo,
    {String? deQuien}) async {
  final c = SiColors.of(context);
  final lat = ch['latitud'] as num?;
  final lng = ch['longitud'] as num?;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(deQuien == null ? titulo : '$titulo · $deQuien',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: FutureBuilder<String?>(
                future: _urlFoto(ch['foto'].toString()),
                builder: (_, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const SizedBox(
                        height: 240, child: Center(child: CircularProgressIndicator()));
                  }
                  if (snap.data == null) {
                    return SizedBox(
                        height: 120,
                        child: Center(
                            child: Text('No se pudo cargar la foto.',
                                style: TextStyle(color: c.danger))));
                  }
                  return Image.network(snap.data!, fit: BoxFit.cover);
                },
              ),
            ),
            const SizedBox(height: SiSpace.x3),
            Text(
              '${_fechaLarga(DateTime.parse(ch['fecha'].toString()))} · ${_hora(ch['registrada_en'])}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
            ),
            const SizedBox(height: SiSpace.x1),
            Text(
              lat == null || lng == null
                  ? 'Sin ubicación'
                  : '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)} · '
                      '${precisionEnPalabras(ch['precision_m'] as num?)}',
              style: TextStyle(fontSize: 12.5, color: c.ink3),
            ),
          ],
        ),
      ),
      actions: [
        if (lat != null && lng != null)
          TextButton.icon(
            onPressed: () => launchUrl(Uri.parse(enlaceAlMapa(lat, lng)),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Ver en el mapa'),
          ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Checar: la cámara en vivo y el GPS
// ─────────────────────────────────────────────────────────────────────────────

class _CapturaChecada extends StatefulWidget {
  final String tipo;
  const _CapturaChecada({required this.tipo});

  @override
  State<_CapturaChecada> createState() => _CapturaChecadaState();
}

class _CapturaChecadaState extends State<_CapturaChecada> {
  CameraController? _camara;
  String? _errorCamara;
  Uint8List? _foto;

  Position? _posicion;
  String? _errorUbicacion;
  bool _buscandoUbicacion = true;

  bool _guardando = false;
  String? _errorGuardar;

  @override
  void initState() {
    super.initState();
    // Las dos a la vez: el GPS tarda unos segundos, y así está listo cuando la foto ya se tomó.
    _abrirCamara();
    _ubicar();
  }

  @override
  void dispose() {
    _camara?.dispose();
    super.dispose();
  }

  /// La cámara EN VIVO, nunca un selector de archivos: una foto guardada no demuestra que la
  /// persona estaba ahí a esa hora. En el teléfono se prefiere la frontal.
  Future<void> _abrirCamara() async {
    try {
      final camaras = await availableCameras();
      if (camaras.isEmpty) {
        setState(() => _errorCamara = 'No se encontró ninguna cámara en este equipo.');
        return;
      }
      final frontal = camaras.firstWhere(
        (x) => x.lensDirection == CameraLensDirection.front,
        orElse: () => camaras.first,
      );
      final ctrl = CameraController(frontal, ResolutionPreset.medium, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() => _camara = ctrl);
    } on CameraException catch (e) {
      debugPrint('checador: cámara: ${e.code} ${e.description}');
      if (mounted) {
        setState(() => _errorCamara = e.code.contains('Denied') || e.code.contains('denied')
            ? 'No diste permiso de usar la cámara. Actívalo en la configuración del navegador '
                'o del teléfono y vuelve a intentarlo.'
            : 'No se pudo abrir la cámara: ${e.description ?? e.code}');
      }
    } catch (e) {
      debugPrint('checador: cámara: $e');
      if (mounted) setState(() => _errorCamara = 'No se pudo abrir la cámara: $e');
    }
  }

  Future<void> _ubicar() async {
    setState(() { _buscandoUbicacion = true; _errorUbicacion = null; });
    try {
      if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
        throw 'La ubicación del teléfono está apagada. Enciéndela y vuelve a intentarlo.';
      }
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
        throw 'No diste permiso de ver tu ubicación. Sin ella no se puede checar: actívalo en la '
            'configuración del navegador o del teléfono.';
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      if (mounted) setState(() { _posicion = p; _buscandoUbicacion = false; });
    } catch (e) {
      debugPrint('checador: ubicación: $e');
      if (mounted) {
        setState(() {
          _buscandoUbicacion = false;
          _errorUbicacion = e is String ? e : 'No se pudo obtener tu ubicación: $e';
        });
      }
    }
  }

  Future<void> _tomarFoto() async {
    final cam = _camara;
    if (cam == null) return;
    try {
      final x = await cam.takePicture();
      final bytes = await x.readAsBytes();
      if (mounted) setState(() => _foto = bytes);
    } catch (e) {
      if (mounted) setState(() => _errorCamara = 'No se pudo tomar la foto: $e');
    }
  }

  Future<void> _guardar() async {
    final uid = _supabase.auth.currentUser?.id;
    final foto = _foto;
    final pos = _posicion;
    if (uid == null || foto == null || pos == null) return;
    setState(() { _guardando = true; _errorGuardar = null; });
    try {
      final lista = prepararFotoChecada(foto);
      if (lista == null) throw 'La foto no se pudo leer. Tómala otra vez.';
      final ruta = rutaFotoChecada(uid, DateTime.now());
      await _supabase.storage.from(_bucket).uploadBinary(
            ruta,
            lista,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      // La hora y el día NO van aquí: los pone la base con su reloj.
      await _supabase.from('checadas').insert({
        'tipo': widget.tipo,
        'latitud': pos.latitude,
        'longitud': pos.longitude,
        'precision_m': pos.accuracy,
        'foto': ruta,
        'dispositivo': kIsWeb ? 'web' : defaultTargetPlatform.name,
      });
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      // El disparador explica en palabras lo que no se puede: «Primero hay que checar la entrada».
      final ya = e.code == '23505';
      if (mounted) {
        setState(() {
          _guardando = false;
          _errorGuardar = ya
              ? 'Ya habías checado «${nombreDeChecada[widget.tipo]}» hoy.'
              : e.message;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _guardando = false; _errorGuardar = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final nombre = nombreDeChecada[widget.tipo]!;

    Widget vista;
    if (_foto != null) {
      vista = Image.memory(_foto!, fit: BoxFit.cover);
    } else if (_errorCamara != null) {
      vista = Padding(
        padding: const EdgeInsets.all(SiSpace.x4),
        child: Center(
          child: Text(_errorCamara!,
              textAlign: TextAlign.center, style: TextStyle(color: c.danger, fontSize: 13)),
        ),
      );
    } else if (_camara == null) {
      vista = const Center(child: CircularProgressIndicator());
    } else {
      vista = CameraPreview(_camara!);
    }

    return AlertDialog(
      title: Text('Checar ${nombre.toLowerCase()}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: Colors.black,
                height: 300,
                child: vista,
              ),
            ),
            const SizedBox(height: SiSpace.x3),
            Row(
              children: [
                Icon(
                  _posicion != null
                      ? Icons.location_on
                      : (_errorUbicacion != null ? Icons.location_off : Icons.my_location),
                  size: 16,
                  color: _posicion != null
                      ? c.success
                      : (_errorUbicacion != null ? c.danger : c.ink3),
                ),
                const SizedBox(width: SiSpace.x2),
                Expanded(
                  child: Text(
                    _posicion != null
                        ? 'Ubicación lista (${precisionEnPalabras(_posicion!.accuracy)})'
                        : (_errorUbicacion ??
                            (_buscandoUbicacion ? 'Buscando tu ubicación…' : '')),
                    style: TextStyle(
                        fontSize: 12.5,
                        color: _errorUbicacion != null ? c.danger : c.ink2),
                  ),
                ),
                if (_errorUbicacion != null)
                  TextButton(onPressed: _ubicar, child: const Text('Reintentar')),
              ],
            ),
            if (_errorGuardar != null) ...[
              const SizedBox(height: SiSpace.x2),
              Text(_errorGuardar!, style: TextStyle(fontSize: 12.5, color: c.danger)),
            ],
            const SizedBox(height: SiSpace.x1),
            Text('La hora la pone el servidor al guardar.',
                style: TextStyle(fontSize: 11.5, color: c.ink4)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        if (_foto == null)
          FilledButton.icon(
            onPressed: _camara == null ? null : _tomarFoto,
            icon: const Icon(Icons.photo_camera, size: 18),
            label: const Text('Tomar foto'),
          )
        else ...[
          TextButton(
            onPressed: _guardando ? null : () => setState(() => _foto = null),
            child: const Text('Repetir foto'),
          ),
          FilledButton(
            onPressed: _guardando || _posicion == null ? null : _guardar,
            child: _guardando
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Checar ${nombre.toLowerCase()}'),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Los registros de todos (administradores)
// ─────────────────────────────────────────────────────────────────────────────

class ChecadorRegistros extends StatefulWidget {
  const ChecadorRegistros({super.key});

  @override
  State<ChecadorRegistros> createState() => _ChecadorRegistrosState();
}

class _ChecadorRegistrosState extends State<ChecadorRegistros> {
  DateTime _dia = DateTime.now();
  bool _cargando = true;
  String? _error;
  String _busqueda = '';

  /// Por persona: sus checadas del día por tipo.
  Map<String, Map<String, Map<String, dynamic>>> _porPersona = {};
  Map<String, Map<String, dynamic>> _perfiles = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final r = await _supabase
          .from('checadas')
          .select('id, profile_id, tipo, registrada_en, fecha, latitud, longitud, precision_m, '
              'foto, dispositivo')
          .eq('fecha', DateFormat('yyyy-MM-dd').format(_dia))
          .order('registrada_en', ascending: true);
      final filas = (r as List).cast<Map<String, dynamic>>();
      final porPersona = <String, Map<String, Map<String, dynamic>>>{};
      for (final f in filas) {
        porPersona.putIfAbsent(f['profile_id'] as String, () => {})[f['tipo'] as String] = f;
      }
      var perfiles = <String, Map<String, dynamic>>{};
      if (porPersona.isNotEmpty) {
        final p = await _supabase
            .from('profiles')
            .select('id, nombre, paterno, materno, numero_empleado')
            .inFilter('id', porPersona.keys.toList());
        perfiles = {
          for (final x in (p as List).cast<Map<String, dynamic>>()) x['id'] as String: x,
        };
      }
      if (!mounted) return;
      setState(() {
        _porPersona = porPersona;
        _perfiles = perfiles;
        _cargando = false;
      });
    } catch (e) {
      debugPrint('checador: registros: $e');
      if (mounted) setState(() { _cargando = false; _error = '$e'; });
    }
  }

  String _nombre(String id) {
    final p = _perfiles[id];
    if (p == null) return 'Sin ficha';
    return [p['nombre'], p['paterno'], p['materno']]
        .where((x) => x != null && x.toString().trim().isNotEmpty)
        .join(' ');
  }

  Future<void> _elegirDia() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dia,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime.now(),
      locale: const Locale('es', 'MX'),
    );
    if (d != null) {
      setState(() => _dia = d);
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final q = _busqueda.trim().toLowerCase();
    final ids = _porPersona.keys
        .where((id) => q.isEmpty || _nombre(id).toLowerCase().contains(q)
            || (_perfiles[id]?['numero_empleado']?.toString() ?? '').contains(q))
        .toList()
      ..sort((a, b) => _nombre(a).compareTo(_nombre(b)));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(SiSpace.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: SiSpace.x3,
            runSpacing: SiSpace.x3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _elegirDia,
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(_fechaLarga(_dia)),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Buscar por nombre o número',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _busqueda = v),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
              ),
              if (!_cargando)
                Text('${_porPersona.length} personas checaron este día',
                    style: TextStyle(fontSize: 12.5, color: c.ink3)),
            ],
          ),
          const SizedBox(height: SiSpace.x4),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.all(SiSpace.x8),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Text('No se pudieron leer las checadas: $_error', style: TextStyle(color: c.danger))
          else if (ids.isEmpty)
            Padding(
              padding: const EdgeInsets.all(SiSpace.x8),
              child: Center(
                child: Text(
                    _porPersona.isEmpty
                        ? 'Nadie ha checado con el sistema este día.'
                        : 'Nadie coincide con la búsqueda.',
                    style: TextStyle(color: c.ink3)),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: c.panel,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(c.hover),
                  columns: [
                    const DataColumn(label: Text('Colaborador')),
                    for (final t in tiposDeChecada) DataColumn(label: Text(nombreDeChecada[t]!)),
                  ],
                  rows: [
                    for (final id in ids)
                      DataRow(cells: [
                        DataCell(Text(_nombre(id))),
                        for (final t in tiposDeChecada)
                          DataCell(
                            _porPersona[id]![t] == null
                                ? Text('—', style: TextStyle(color: c.ink4))
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(_hora(_porPersona[id]![t]!['registrada_en']),
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: c.brand,
                                              fontFeatures: const [FontFeature.tabularFigures()])),
                                      const SizedBox(width: 4),
                                      Icon(Icons.photo_camera_outlined, size: 14, color: c.ink4),
                                    ],
                                  ),
                            onTap: _porPersona[id]![t] == null
                                ? null
                                : () => mostrarChecada(
                                    context, _porPersona[id]![t]!, nombreDeChecada[t]!,
                                    deQuien: _nombre(id)),
                          ),
                      ]),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
