import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/checador.dart';
import 'services/checador_resumen.dart';
import 'services/quincena.dart';
import 'theme/si_theme.dart';
import 'widgets/dona_painter.dart';
import 'widgets/ficha_asistencia.dart';

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

/// La hora de la checada en el lugar donde se hizo, no en el reloj de quien mira. Ver
/// `desfaseHorasDe`.
DateTime? _horaLocal(Map<String, dynamic> ch) => horaLocalDeFila(ch);

String _horaDe(Map<String, dynamic>? ch) {
  final d = ch == null ? null : _horaLocal(ch);
  return d == null ? '—' : DateFormat('HH:mm').format(d);
}

Color _colorSemaforo(SiColors c, Semaforo s) => switch (s) {
      Semaforo.verde => c.success,
      Semaforo.amarillo => c.warn,
      Semaforo.rojo => c.danger,
    };

/// La diferencia contra el horario, del color del semáforo: «- 36m» en verde, «+ 5m» en amarillo,
/// «+ 8h 12m» en rojo. Nada si esa checada no tiene hora en el horario. Pedido del 29/09/2026, en
/// lugar del punto de color.
Widget _diferencia(SiColors c, Map<String, dynamic> ch, List<dynamic>? reglas,
    {double tamano = 11.5}) {
  final hora = _horaLocal(ch);
  final tipo = ch['tipo']?.toString() ?? '';
  final d = hora == null ? null : diferenciaContraHorario(tipo, hora, reglas);
  if (d == null) return const SizedBox.shrink();
  final color = _colorSemaforo(c, d.color);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(diferenciaCorta(d.minutos),
        style: TextStyle(fontSize: tamano, fontWeight: FontWeight.w700, color: color)),
  );
}

/// El horario de cada quien: `profiles.schedule_id` → `schedules`.
Future<Map<String, Map<String, dynamic>>> _horarios() async {
  final r = await _supabase.from('schedules').select('id, name, rules');
  return {for (final h in (r as List).cast<Map<String, dynamic>>()) h['id'] as String: h};
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

  /// Su horario. Null si no tiene uno asignado.
  String? _nombreHorario;
  List<dynamic>? _reglas;

  /// Refresca el contador. Cada 20 segundos basta: cuenta en minutos.
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _cargar();
    _reloj = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    // Silencioso después de checar: con el indicador de carga la cámara se desmontaría y el
    // navegador volvería a encenderla —y en algunos, a pedir el permiso—.
    if (!silencioso) setState(() { _cargando = true; _error = null; });
    try {
      final desde = DateFormat('yyyy-MM-dd')
          .format(DateTime.now().subtract(const Duration(days: 13)));
      final r = await _supabase
          .from('checadas')
          .select('id, tipo, registrada_en, fecha, latitud, longitud, precision_m, foto, '
              'hora_local, origen, direccion')
          .eq('profile_id', uid)
          .gte('fecha', desde)
          .order('registrada_en', ascending: false);
      final perfil = await _supabase
          .from('profiles').select('schedule_id').eq('id', uid).maybeSingle();
      final idHorario = perfil?['schedule_id'] as String?;
      Map<String, dynamic>? horario;
      if (idHorario != null) {
        horario = await _supabase
            .from('schedules').select('name, rules').eq('id', idHorario).maybeSingle();
      }
      if (!mounted) return;
      setState(() {
        _checadas = (r as List).cast<Map<String, dynamic>>();
        _nombreHorario = horario?['name'] as String?;
        _reglas = horario?['rules'] as List<dynamic>?;
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

  /// Lo llama la cámara cuando la checada ya quedó guardada.
  Future<void> _alChecar(String tipo) async {
    await _cargar(silencioso: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${nombreDeChecada[tipo]} registrada a las '
            '${_horaDe(_deHoy[tipo])}.'),
      ));
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

    final reglasHoy = reglasDelDia(_reglas, DateTime.now());
    final contador = contadorDelDia(
      ahora: DateTime.now(),
      entrada: reglasHoy.entrada,
      salida: reglasHoy.salida,
      yaEntro: hoy.containsKey('ENTRADA'),
      yaSalio: hoy.containsKey('SALIDA'),
    );
    final colorContador = contador.color == null ? c.ink3 : _colorSemaforo(c, contador.color!);

    final tarjetaHoy = _tarjeta(
      c,
      titulo: 'Hoy · ${_fechaLarga(DateTime.now())}',
      children: [
        // El contador: cuánto falta para la entrada o la salida, o cuánto se lleva de retardo, con
        // el color del semáforo. Pedido del 28/09/2026.
        Container(
          padding: const EdgeInsets.all(SiSpace.x3),
          decoration: BoxDecoration(
            color: colorContador.withValues(alpha: 0.08),
            border: Border.all(color: colorContador.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.timer_outlined, size: 20, color: colorContador),
              const SizedBox(width: SiSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_nombreHorario == null ? 'No tienes horario asignado.' : contador.texto,
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600, color: colorContador)),
                    const SizedBox(height: 2),
                    Text(
                      _nombreHorario == null
                          ? 'Pídele a Recursos Humanos que te asigne uno para ver tu semáforo.'
                          : 'Tu horario: $_nombreHorario'
                              '${reglasHoy.entrada == null ? '' : ' · hoy ${reglasHoy.entrada!.hora}'}'
                              '${reglasHoy.salida == null ? '' : '–${reglasHoy.salida!.hora}'}',
                      style: TextStyle(fontSize: 11.5, color: c.ink3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SiSpace.x2),
        for (final t in tiposDeChecada) _filaHoy(c, t, hoy[t]),
        if (posibles.isEmpty) ...[
          const SizedBox(height: SiSpace.x3),
          Text('Tu jornada de hoy está completa.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.ink3)),
        ],
      ],
    );

    // La cámara se abre sola al entrar —pedido del 28/09/2026, antes era una ventana que se abría
    // con el botón— y sólo mientras haya algo que checar: con la jornada completa no tiene caso
    // tenerla encendida.
    final camara = posibles.isEmpty
        ? null
        : _CamaraChecador(posibles: posibles, alChecar: _alChecar);

    return RefreshIndicator(
      onRefresh: () => _cargar(silencioso: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(SiSpace.x6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(builder: (_, caja) {
                  if (camara == null) return tarjetaHoy;
                  if (caja.maxWidth >= 860) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: camara),
                        const SizedBox(width: SiSpace.x4),
                        Expanded(flex: 2, child: tarjetaHoy),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [camara, const SizedBox(height: SiSpace.x4), tarjetaHoy],
                  );
                }),
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
            if (ch != null) ...[
              _diferencia(c, ch, _reglas),
              const SizedBox(width: SiSpace.x2),
            ],
            Text(ch == null ? '—' : _horaDe(ch),
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_horaDe(deEse[t]),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: c.brand,
                              fontFeatures: const [FontFeature.tabularFigures()])),
                          _diferencia(c, deEse[t]!, _reglas, tamano: 10),
                        ],
                      ),
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
                future: ch['foto'] == null ? Future.value(null) : _urlFoto(ch['foto'].toString()),
                builder: (_, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const SizedBox(
                        height: 240, child: Center(child: CircularProgressIndicator()));
                  }
                  if (snap.data == null) {
                    return SizedBox(
                        height: 120,
                        child: Center(
                            child: Text(
                                ch['foto'] == null
                                    ? 'La foto todavía se está copiando de appchecar.'
                                    : 'No se pudo cargar la foto.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: ch['foto'] == null ? c.ink3 : c.danger))));
                  }
                  return Image.network(snap.data!, fit: BoxFit.cover);
                },
              ),
            ),
            const SizedBox(height: SiSpace.x3),
            Text(
              '${_fechaLarga(DateTime.parse(ch['fecha'].toString()))} · ${_horaDe(ch)}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
            ),
            const SizedBox(height: SiSpace.x1),
            // Las de appchecar no traen coordenadas: traen la dirección que registró su aplicación.
            Text(
              lat == null || lng == null
                  ? (ch['direccion']?.toString() ?? 'Sin ubicación')
                  : '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)} · '
                      '${precisionEnPalabras(ch['precision_m'] as num?)}',
              style: TextStyle(fontSize: 12.5, color: c.ink3),
            ),
            if (ch['origen'] == 'APPCHECAR')
              Text('Registrada con appchecar.',
                  style: TextStyle(fontSize: 11.5, color: c.ink4)),
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

/// La cámara y el GPS, dentro de la página.
///
/// Se encienden solos al entrar y se apagan al salir de la pestaña —el `dispose`— y, en el
/// teléfono, al mandar la aplicación al fondo: una cámara encendida sin que nadie la vea es una
/// cámara que alguien puede estar usando.
class _CamaraChecador extends StatefulWidget {
  /// Lo que se puede checar ahora. Uno por botón.
  final List<String> posibles;
  final Future<void> Function(String tipo) alChecar;

  const _CamaraChecador({required this.posibles, required this.alChecar});

  @override
  State<_CamaraChecador> createState() => _CamaraChecadorState();
}

class _CamaraChecadorState extends State<_CamaraChecador> with WidgetsBindingObserver {
  CameraController? _camara;
  String? _errorCamara;

  /// La foto recién tomada, esperando confirmación, y para qué checada es.
  Uint8List? _foto;
  String? _tipo;

  Position? _posicion;
  String? _errorUbicacion;
  bool _buscandoUbicacion = true;

  bool _guardando = false;
  String? _errorGuardar;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Las dos a la vez: el GPS tarda unos segundos, y así está listo cuando se pulsa el botón.
    _abrirCamara();
    _ubicar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camara?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.inactive || estado == AppLifecycleState.paused) {
      final cam = _camara;
      if (cam != null) {
        setState(() => _camara = null);
        cam.dispose();
      }
    } else if (estado == AppLifecycleState.resumed && _camara == null && _errorCamara == null) {
      _abrirCamara();
    }
  }

  /// La cámara EN VIVO, nunca un selector de archivos: una foto guardada no demuestra que la
  /// persona estaba ahí a esa hora. En el teléfono se prefiere la frontal.
  Future<void> _abrirCamara() async {
    try {
      final camaras = await availableCameras();
      if (camaras.isEmpty) {
        if (mounted) setState(() => _errorCamara = 'No se encontró ninguna cámara en este equipo.');
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
      setState(() { _camara = ctrl; _errorCamara = null; });
    } on CameraException catch (e) {
      debugPrint('checador: cámara: ${e.code} ${e.description}');
      if (mounted) {
        setState(() => _errorCamara = e.code.toLowerCase().contains('denied')
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

  Future<void> _tomarFoto(String tipo) async {
    final cam = _camara;
    if (cam == null) return;
    try {
      final x = await cam.takePicture();
      final bytes = await x.readAsBytes();
      if (mounted) setState(() { _foto = bytes; _tipo = tipo; _errorGuardar = null; });
    } catch (e) {
      if (mounted) setState(() => _errorGuardar = 'No se pudo tomar la foto: $e');
    }
  }

  Future<void> _guardar() async {
    final uid = _supabase.auth.currentUser?.id;
    final foto = _foto;
    final tipo = _tipo;
    final pos = _posicion;
    if (uid == null || foto == null || tipo == null || pos == null) return;
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
        'tipo': tipo,
        'latitud': pos.latitude,
        'longitud': pos.longitude,
        'precision_m': pos.accuracy,
        'foto': ruta,
        'dispositivo': kIsWeb ? 'web' : defaultTargetPlatform.name,
      });
      if (!mounted) return;
      setState(() { _guardando = false; _foto = null; _tipo = null; });
      await widget.alChecar(tipo);
    } on PostgrestException catch (e) {
      // El disparador explica en palabras lo que no se puede: «Primero hay que checar la entrada».
      if (mounted) {
        setState(() {
          _guardando = false;
          _errorGuardar = e.code == '23505'
              ? 'Ya habías checado «${nombreDeChecada[tipo]}» hoy.'
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

    Widget vista;
    if (_foto != null) {
      vista = Image.memory(_foto!, fit: BoxFit.cover);
    } else if (_errorCamara != null) {
      vista = Padding(
        padding: const EdgeInsets.all(SiSpace.x4),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorCamara!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade200, fontSize: 13)),
              const SizedBox(height: SiSpace.x2),
              TextButton(
                onPressed: () {
                  setState(() => _errorCamara = null);
                  _abrirCamara();
                },
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    } else if (_camara == null) {
      vista = const Center(child: CircularProgressIndicator());
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // En iOS, CameraPreview ya invierte la proporcion cuando el telefono esta vertical; envolverlo
      // en otro AspectRatio con la proporcion del sensor (horizontal) lo estiraba a lo ancho.
      vista = Center(child: CameraPreview(_camara!));
    } else {
      vista = Center(
        child: AspectRatio(
          aspectRatio: _camara!.value.aspectRatio,
          child: CameraPreview(_camara!),
        ),
      );
    }

    final nombre = _tipo == null ? '' : nombreDeChecada[_tipo]!.toLowerCase();

    return _tarjeta(
      c,
      titulo: _foto == null ? 'Checar' : '¿Así queda tu checada de $nombre?',
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(color: Colors.black, height: 320, child: vista),
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
                    : (_errorUbicacion ?? (_buscandoUbicacion ? 'Buscando tu ubicación…' : '')),
                style: TextStyle(
                    fontSize: 12.5, color: _errorUbicacion != null ? c.danger : c.ink2),
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
        const SizedBox(height: SiSpace.x3),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: SiSpace.x3,
          runSpacing: SiSpace.x3,
          children: _foto == null
              ? [
                  // Un botón por cada checada posible: pulsarlo toma la foto de ESA checada.
                  for (var i = 0; i < widget.posibles.length; i++)
                    i == 0
                        ? FilledButton.icon(
                            onPressed: _camara == null
                                ? null
                                : () => _tomarFoto(widget.posibles[i]),
                            icon: const Icon(Icons.photo_camera, size: 18),
                            label: Text(
                                'Checar ${nombreDeChecada[widget.posibles[i]]!.toLowerCase()}'),
                          )
                        : OutlinedButton.icon(
                            onPressed: _camara == null
                                ? null
                                : () => _tomarFoto(widget.posibles[i]),
                            icon: const Icon(Icons.photo_camera, size: 18),
                            label: Text(
                                'Checar ${nombreDeChecada[widget.posibles[i]]!.toLowerCase()}'),
                          ),
                ]
              : [
                  TextButton(
                    onPressed: _guardando
                        ? null
                        : () => setState(() { _foto = null; _tipo = null; }),
                    child: const Text('Repetir foto'),
                  ),
                  FilledButton(
                    onPressed: _guardando || _posicion == null ? null : _guardar,
                    child: _guardando
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Confirmar $nombre'),
                  ),
                ],
        ),
        const SizedBox(height: SiSpace.x2),
        Text('La hora la pone el servidor al guardar.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: c.ink4)),
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

/// Registros, con la forma de «Detalle por empleado» del Panel pero sin Zona, sobre el checador
/// propio y con los umbrales de Configuración. Pedido del 29/09/2026. La cuenta está en
/// `services/checador_resumen.dart`, que es la que se prueba.
class _ChecadorRegistrosState extends State<ChecadorRegistros> {
  bool _cargando = true;
  String? _error;
  String _busqueda = '';
  String _filtroEstatus = 'todos';
  String _filtroZona = 'todas';

  /// La columna por la que se ordena la tabla (su índice en los títulos) y en qué sentido. Sin
  /// columna, el orden es el alfabético de siempre.
  int? _ordenColumna;
  bool _ordenDescendente = true;

  /// Un clic en un título ordena por esa columna; otro clic en el mismo, al revés. Los números
  /// empiezan de mayor a menor y los textos de la A a la Z.
  void _ordenarPor(int columna) => setState(() {
        if (_ordenColumna == columna) {
          _ordenDescendente = !_ordenDescendente;
        } else {
          _ordenColumna = columna;
          _ordenDescendente = columna >= 2;
        }
      });

  /// El valor de cada columna para ordenar. En ESTATUS, de mayor a menor pone primero a los
  /// críticos; quien no tiene puntualidad («—») queda al final en % PUNT. de mayor a menor.
  Comparable<Object> _valorParaOrden(ResumenChecador r, int columna) {
    switch (columna) {
      case 0:
        return _nombre(r.profileId).toLowerCase();
      case 1:
        return _zonaDe(r.profileId).toLowerCase();
      case 2:
        return r.puntualidad ?? -1.0;
      case 3:
        return r.retardos;
      case 4:
        return r.faltas;
      case 5:
        return r.justificados;
      case 6:
        return r.diasDescuento(_retardosPorDescuento);
      default:
        return const {'critico': 3, 'atencion': 2, 'puntual': 1}[_estatus(r)] ?? 0;
    }
  }

  // Los umbrales de la pestaña Configuración (`checador_umbrales`), los mismos del Panel.
  double _criticoMax = 70;
  double _atencionMax = 90;
  int _retardosPorDescuento = 3;

  /// El primer día con checadas del sistema: antes de él no hay faltas que contar.
  DateTime? _inicio;

  late Quincena _periodo = Quincena.deIso(_hoyISO())!;

  Map<String, Map<String, dynamic>> _perfiles = {};
  Map<String, Map<String, dynamic>> _horariosPorId = {};
  List<Map<String, dynamic>> _checadas = [];
  Map<String, List<SolicitudVacaciones>> _vacaciones = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final umbrales = await _supabase
          .from('checador_umbrales')
          .select('critico_max, atencion_max, retardos_por_descuento')
          .maybeSingle();
      if (umbrales != null) {
        _criticoMax = (umbrales['critico_max'] as num).toDouble();
        _atencionMax = (umbrales['atencion_max'] as num).toDouble();
        _retardosPorDescuento =
            ((umbrales['retardos_por_descuento'] as num?)?.toInt() ?? 3).clamp(1, 100);
      }

      final primera = await _supabase
          .from('checadas').select('fecha').order('fecha', ascending: true).limit(1);
      final lista = (primera as List);
      _inicio = lista.isEmpty ? null : DateTime.tryParse(lista.first['fecha'].toString());

      final checadas = await _supabase
          .from('checadas')
          .select('id, profile_id, tipo, registrada_en, fecha, latitud, longitud, precision_m, '
              'foto, dispositivo, hora_local, origen, direccion')
          .gte('fecha', _periodo.desdeIso)
          .lte('fecha', _periodo.hastaIso)
          .order('registrada_en', ascending: true);
      _checadas = (checadas as List).cast<Map<String, dynamic>>();

      // Los ACTIVOS —para saber quién debía checar— y quien checó aunque ya no lo esté.
      const campos = 'id, nombre, paterno, materno, numero_empleado, schedule_id, ubicacion, '
          'fecha_ingreso, fecha_reingreso';
      final activos = await _supabase.from('profiles').select(campos).eq('status_sys', 'ACTIVO');
      final perfiles = <String, Map<String, dynamic>>{
        for (final x in (activos as List).cast<Map<String, dynamic>>()) x['id'] as String: x,
      };
      final faltan = _checadas
          .map((x) => x['profile_id'] as String)
          .where((id) => !perfiles.containsKey(id))
          .toSet()
          .toList();
      if (faltan.isNotEmpty) {
        final otros = await _supabase.from('profiles').select(campos).inFilter('id', faltan);
        for (final x in (otros as List).cast<Map<String, dynamic>>()) {
          perfiles[x['id'] as String] = x;
        }
      }
      _perfiles = perfiles;
      _horariosPorId = await _horarios();

      // Las vacaciones que tocan el periodo. Las APROBADAS justifican un día sin entrada; las
      // pendientes sólo se marcan en el calendario de la ficha. Las canceladas no se traen.
      final inc = await _supabase
          .from('incidencias')
          .select('usuario_id, fecha_inicio, fecha_fin, status')
          .inFilter('status', ['APROBADA', 'PENDIENTE'])
          .eq('tipo', 'VACACIONES')
          .lte('fecha_inicio', _periodo.hastaIso)
          .gte('fecha_fin', _periodo.desdeIso);
      final vac = <String, List<SolicitudVacaciones>>{};
      for (final x in (inc as List).cast<Map<String, dynamic>>()) {
        final id = x['usuario_id']?.toString();
        if (id == null) continue;
        vac.putIfAbsent(id, () => []).add((
          x['fecha_inicio'].toString().substring(0, 10),
          x['fecha_fin'].toString().substring(0, 10),
          x['status'].toString(),
        ));
      }
      _vacaciones = vac;

      if (mounted) setState(() => _cargando = false);
    } catch (e) {
      debugPrint('checador: registros: $e');
      if (mounted) setState(() { _cargando = false; _error = '$e'; });
    }
  }

  Map<String, dynamic>? _horarioDe(String id) {
    final h = _perfiles[id]?['schedule_id'] as String?;
    return h == null ? null : _horariosPorId[h];
  }

  String _nombre(String id) {
    final p = _perfiles[id];
    if (p == null) return 'Sin ficha';
    return [p['nombre'], p['paterno'], p['materno']]
        .where((x) => x != null && x.toString().trim().isNotEmpty)
        .join(' ');
  }

  /// Las quincenas desde que existe el checador hasta hoy, la más reciente primero.
  List<Quincena> get _quincenas {
    final hoy = Quincena.deIso(_hoyISO())!;
    final desde = _inicio == null ? hoy : Quincena.deIso(DateFormat('yyyy-MM-dd').format(_inicio!))!;
    final lista = <Quincena>[];
    var q = hoy;
    for (var i = 0; i < 48; i++) {
      lista.add(q);
      if (q.clave.compareTo(desde.clave) <= 0) break;
      final anterior = DateTime.parse(q.desdeIso).subtract(const Duration(days: 1));
      q = Quincena.deIso(DateFormat('yyyy-MM-dd').format(anterior))!;
    }
    return lista;
  }

  List<ResumenChecador> get _resumenes {
    final porPersona = <String, List<Map<String, dynamic>>>{};
    for (final ch in _checadas) {
      porPersona.putIfAbsent(ch['profile_id'] as String, () => []).add(ch);
    }
    final ids = <String>{
      ...porPersona.keys,
      for (final id in _perfiles.keys)
        if (_horarioDe(id) != null) id,
    };
    final inicio = _inicio ?? DateTime.now();
    // Y para cada quien, no antes de su ingreso —o reingreso—: con la historia de appchecar desde
    // julio, a quien entró en agosto se le habrían contado faltas de cuando todavía no trabajaba aquí.
    DateTime inicioDe(String id) {
      final p = _perfiles[id];
      final ingreso = DateTime.tryParse(
          (p?['fecha_reingreso'] ?? p?['fecha_ingreso'])?.toString() ?? '');
      return ingreso != null && ingreso.isAfter(inicio) ? ingreso : inicio;
    }
    return [
      for (final id in ids)
        resumirPersona(
          profileId: id,
          checadas: porPersona[id] ?? const [],
          reglas: _horarioDe(id)?['rules'] as List<dynamic>?,
          desde: DateTime.parse(_periodo.desdeIso),
          hasta: DateTime.parse(_periodo.hastaIso),
          inicio: inicioDe(id),
          vacaciones: _vacaciones[id] ?? const [],
          ahora: DateTime.now(),
        ),
    ]..sort((a, b) => _nombre(a.profileId).toLowerCase().compareTo(_nombre(b.profileId).toLowerCase()));
  }

  String _estatus(ResumenChecador r) =>
      estatusDePuntualidad(r.puntualidad, _criticoMax, _atencionMax);

  Future<void> _mostrarFicha(ResumenChecador r) async {
    // Las fotos van en un bucket privado: se firman todas las del periodo en una sola llamada.
    final rutas = <String>{
      for (final d in r.dias) ...[
        if (d['foto_entrada'] != null) d['foto_entrada'] as String,
        if (d['foto_salida'] != null) d['foto_salida'] as String,
      ],
    }.toList();
    final urls = <String, String>{};
    if (rutas.isNotEmpty) {
      try {
        final firmadas = await _supabase.storage.from(_bucket).createSignedUrls(rutas, 3600);
        for (final f in firmadas) {
          urls[f.path] = f.signedUrl;
        }
      } catch (e) {
        debugPrint('checador: no se firmaron las fotos: $e');
      }
    }
    final dias = [
      for (final d in r.dias)
        {
          ...d,
          'foto_entrada': urls[d['foto_entrada']],
          'foto_salida': urls[d['foto_salida']],
        },
    ];
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => FichaAsistencia(
        nombre: _nombre(r.profileId),
        numero: _perfiles[r.profileId]?['numero_empleado']?.toString() ?? '',
        zona: '',
        horario: _horarioDe(r.profileId)?['name']?.toString() ?? 'Sin horario asignado',
        estatus: _estatus(r),
        puntualidad: r.puntualidad,
        asistio: r.asistio,
        esperados: r.esperados,
        retardos: r.retardos,
        faltas: r.faltas,
        incompletas: r.incompletas,
        justificados: r.justificados,
        minutosTarde: r.minutosTarde,
        diasDescuento: r.diasDescuento(_retardosPorDescuento),
        reglaDescuento: 'Cada $_retardosPorDescuento retardos son 1 día, '
            'y cada falta sin justificar es 1 día.',
        dias: dias,
      ),
    );
  }

  // Los anchos mínimos, los de «Detalle por empleado» del Panel. El sobrante se reparte entre TODAS
  // las columnas y no sólo entre el nombre, la zona y la barra como allá: en 3/4 de una pantalla
  // ancha sobran unos 700px, y dados sólo a esas tres dejaban un hueco entre el nombre y la zona y
  // los números pegados a la barra (29/09/2026).
  // RETARDOS, JUSTIF. y DÍAS DESC. llevan 12px más que allá por la flecha de orden del título.
  static const _anchos = [184.0, 96.0, 90.0, 76.0, 56.0, 68.0, 84.0, 82.0];
  static const _reparto = [2, 1, 2, 1, 1, 1, 1, 1];

  static List<double> _anchosEn(double disponible) {
    final minimo = _anchos.reduce((a, b) => a + b);
    if (!disponible.isFinite || disponible <= minimo) return _anchos;
    final sobra = disponible - minimo;
    final pesos = _reparto.reduce((a, b) => a + b);
    return [for (var i = 0; i < _anchos.length; i++) _anchos[i] + sobra * _reparto[i] / pesos];
  }

  static const _etiquetaEstatus = {
    'critico': 'Crítico',
    'atencion': 'Atención',
    'puntual': 'Puntual',
    'sin datos': 'Sin datos',
  };

  Color _colorEstatus(SiColors c, String e) => switch (e) {
        'critico' => c.danger,
        'atencion' => c.warn,
        'puntual' => c.success,
        _ => c.ink3,
      };

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text('No se pudieron leer las checadas: $_error', style: TextStyle(color: c.danger)),
      );
    }

    final todos = _resumenes;
    final cuenta = <String, int>{};
    for (final r in todos) {
      final e = _estatus(r);
      cuenta[e] = (cuenta[e] ?? 0) + 1;
    }
    // Las zonas de quienes salen en el periodo, para el desplegable.
    final zonas = {for (final r in todos) _zonaDe(r.profileId)}.toList()..sort();
    final q = _busqueda.trim().toLowerCase();
    final filas = todos.where((r) {
      if (_filtroEstatus != 'todos' && _estatus(r) != _filtroEstatus) return false;
      if (_filtroZona != 'todas' && _zonaDe(r.profileId) != _filtroZona) return false;
      if (q.isEmpty) return true;
      return _nombre(r.profileId).toLowerCase().contains(q) ||
          (_perfiles[r.profileId]?['numero_empleado']?.toString() ?? '').contains(q) ||
          _zonaDe(r.profileId).toLowerCase().contains(q);
    }).toList();
    final columna = _ordenColumna;
    if (columna != null) {
      // Empates por nombre, para que el orden no brinque entre recargas.
      filas.sort((a, b) {
        final va = _valorParaOrden(a, columna);
        final vb = _valorParaOrden(b, columna);
        final cmp = _ordenDescendente ? vb.compareTo(va) : va.compareTo(vb);
        return cmp != 0
            ? cmp
            : _nombre(a.profileId).toLowerCase().compareTo(_nombre(b.profileId).toLowerCase());
      });
    }

    Widget chip(String valor, String etiqueta, int n, Color color) {
      final activo = _filtroEstatus == valor;
      return InkWell(
        onTap: () => setState(() => _filtroEstatus = valor),
        borderRadius: SiRadius.rPill,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: activo ? color : c.panel,
            borderRadius: SiRadius.rPill,
            border: Border.all(color: activo ? color : c.line),
          ),
          child: Text('$etiqueta ($n)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: activo ? FontWeight.w600 : FontWeight.normal,
                  color: activo ? Colors.white : c.ink2)),
        ),
      );
    }

    const relleno = EdgeInsets.symmetric(horizontal: 12, vertical: 10);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(SiSpace.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
      _kpis(c, todos),
      const SizedBox(height: SiSpace.x4),
      // La tabla en 3/4 del ancho y, en el cuarto que sobra, la puntualidad por zona y el semáforo.
      // Pedido del 29/09/2026. Por debajo de 1100 px no caben las dos columnas y se apilan.
      LayoutBuilder(builder: (context, caja) {
      final detalle = Container(
        padding: const EdgeInsets.all(SiSpace.x4),
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: SiRadius.rMd,
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.people_outline, size: 16, color: c.brand),
              const SizedBox(width: SiSpace.x2),
              Text('Detalle por empleado',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
              const Spacer(),
              IconButton(tooltip: 'Actualizar', onPressed: _cargar, icon: const Icon(Icons.refresh)),
            ]),
            const SizedBox(height: SiSpace.x3),
            Row(children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _busqueda = v),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, número o zona…',
                    hintStyle: TextStyle(fontSize: 13, color: c.ink4),
                    prefixIcon: Icon(Icons.search, size: 17, color: c.ink3),
                    prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 0),
                    isDense: true,
                    contentPadding: relleno,
                    border: OutlineInputBorder(borderRadius: SiRadius.rMd),
                  ),
                ),
              ),
              // Con una sola zona el filtro no filtra nada; sólo estorbaría.
              if (zonas.length > 1) ...[
                const SizedBox(width: SiSpace.x3),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('zona-$_filtroZona-${zonas.length}'),
                    initialValue: zonas.contains(_filtroZona) ? _filtroZona : 'todas',
                    isExpanded: true,
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: c.ink),
                    icon: Icon(Icons.expand_more, size: 18, color: c.ink3),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: relleno,
                      prefixIcon: Icon(Icons.place_outlined, size: 15, color: c.ink3),
                      prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 0),
                      border: OutlineInputBorder(borderRadius: SiRadius.rMd),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'todas',
                        child: Text('Todas las zonas',
                            style: TextStyle(fontSize: 13, color: c.ink2)),
                      ),
                      for (final z in zonas)
                        DropdownMenuItem(
                          value: z,
                          child: Text(z,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: c.ink2)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _filtroZona = v ?? 'todas'),
                  ),
                ),
              ],
              const SizedBox(width: SiSpace.x3),
              SizedBox(
                width: 215,
                child: DropdownButtonFormField<String>(
                  initialValue: _periodo.clave,
                  isExpanded: true,
                  isDense: true,
                  style: TextStyle(fontSize: 13, color: c.ink),
                  icon: Icon(Icons.expand_more, size: 18, color: c.ink3),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: relleno,
                    prefixIcon: Icon(Icons.date_range_outlined, size: 15, color: c.ink3),
                    prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 0),
                    border: OutlineInputBorder(borderRadius: SiRadius.rMd),
                  ),
                  items: [
                    for (final qn in _quincenas)
                      DropdownMenuItem(
                        value: qn.clave,
                        child: Text(qn.etiqueta,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: c.ink2)),
                      ),
                  ],
                  onChanged: (v) {
                    final elegida = _quincenas.firstWhere((qn) => qn.clave == v);
                    setState(() => _periodo = elegida);
                    _cargar();
                  },
                ),
              ),
            ]),
            const SizedBox(height: SiSpace.x3),
            Wrap(
              spacing: SiSpace.x2,
              runSpacing: SiSpace.x2,
              children: [
                chip('todos', 'Todos', todos.length, c.brand),
                chip('critico', 'Críticos', cuenta['critico'] ?? 0, c.danger),
                chip('atencion', 'Atención', cuenta['atencion'] ?? 0, c.warn),
                chip('puntual', 'Puntuales', cuenta['puntual'] ?? 0, c.success),
              ],
            ),
            const SizedBox(height: SiSpace.x2),
            Text(
              'Puntualidad: crítico por debajo de ${_criticoMax.toStringAsFixed(0)}%, atención hasta '
              '${_atencionMax.toStringAsFixed(0)}%. Cada $_retardosPorDescuento retardos, 1 día a '
              'descontar. Se ajusta en Configuración.',
              style: TextStyle(fontSize: 11.5, color: c.ink4),
            ),
            const SizedBox(height: SiSpace.x3),
            if (filas.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: SiSpace.x6),
                child: Center(
                  child: Text(
                      todos.isEmpty
                          ? 'Nadie tiene checadas ni horario en este periodo.'
                          : 'Nadie coincide con el filtro',
                      style: TextStyle(fontSize: 12.5, color: c.ink3)),
                ),
              )
            else
              LayoutBuilder(builder: (context, box) {
                final anchos = _anchosEn(box.maxWidth);
                const titulos = [
                  'EMPLEADO', 'ZONA', '% PUNT.', 'RETARDOS', 'FALTAS', 'JUSTIF.', 'DÍAS DESC.',
                  'ESTATUS'
                ];
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: anchos.reduce((a, b) => a + b),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: SiSpace.x2),
                          child: Row(children: [
                            for (var i = 0; i < titulos.length; i++)
                              SizedBox(
                                width: anchos[i],
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: InkWell(
                                    onTap: () => _ordenarPor(i),
                                    borderRadius: SiRadius.rSm,
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Flexible(
                                        child: Text(titulos[i],
                                            style: SiType.mono(
                                                size: 9.5,
                                                color: _ordenColumna == i ? c.brand : c.ink3,
                                                letterSpacing: 0.8)),
                                      ),
                                      Icon(
                                          _ordenColumna != i
                                              ? Icons.unfold_more
                                              : _ordenDescendente
                                                  ? Icons.arrow_downward
                                                  : Icons.arrow_upward,
                                          size: 11,
                                          color: _ordenColumna == i ? c.brand : c.ink4),
                                    ]),
                                  ),
                                ),
                              ),
                          ]),
                        ),
                        Divider(height: 1, color: c.line),
                        for (final r in filas) _fila(c, r, anchos),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      );
      final lado = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tarjetaZonas(c, todos),
          const SizedBox(height: SiSpace.x4),
          _tarjetaSemaforo(c, todos),
        ],
      );
      if (caja.maxWidth < 1100) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [detalle, const SizedBox(height: SiSpace.x4), lado],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: detalle),
          const SizedBox(width: SiSpace.x4),
          Expanded(flex: 1, child: lado),
        ],
      );
      }),
        ],
      ),
    );
  }

  Widget _tarjetaLado(SiColors c, IconData icono, String titulo, Widget cuerpo) => Container(
        padding: const EdgeInsets.all(SiSpace.x4),
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: SiRadius.rMd,
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icono, size: 16, color: c.brand),
              const SizedBox(width: SiSpace.x2),
              Expanded(
                child: Text(titulo,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
              ),
            ]),
            const SizedBox(height: SiSpace.x4),
            cuerpo,
          ],
        ),
      );

  Widget _sinDatos(SiColors c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: SiSpace.x5),
        child: Center(
          child: Text('Sin datos en el periodo', style: TextStyle(fontSize: 12.5, color: c.ink3)),
        ),
      );

  String _zonaDe(String profileId) =>
      _nombreZona(_perfiles[profileId]?['ubicacion']?.toString());

  /// «BONANZA_PRISMA» → «Bonanza Prisma». La zona es la ubicación del perfil.
  static String _nombreZona(String? u) {
    final t = (u ?? '').replaceAll('_', ' ').trim().toLowerCase();
    if (t.isEmpty) return 'Sin zona';
    return t
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }

  /// Puntualidad por zona, como la del Panel: PONDERADA por entradas —a tiempo entre evaluadas de la
  /// zona—, no el promedio de las personas. La zona sale de la ubicación de cada perfil; appchecar
  /// la traía en su reporte y aquí no hay reporte.
  Widget _tarjetaZonas(SiColors c, List<ResumenChecador> todos) {
    final aTiempo = <String, int>{};
    final total = <String, int>{};
    for (final r in todos) {
      if (r.evaluadas == 0) continue;
      final z = _nombreZona(_perfiles[r.profileId]?['ubicacion']?.toString());
      total[z] = (total[z] ?? 0) + r.evaluadas;
      aTiempo[z] = (aTiempo[z] ?? 0) + r.evaluadas - r.retardos;
    }
    final zonas = total.entries
        .map((t) => (t.key, (aTiempo[t.key] ?? 0) / t.value * 100, t.value))
        .toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    return _tarjetaLado(
      c,
      Icons.bar_chart_outlined,
      'Puntualidad por zona',
      zonas.isEmpty
          ? _sinDatos(c)
          : Column(children: [
              for (final z in zonas) ...[
                _barraZona(c, z.$1, z.$2, z.$3),
                const SizedBox(height: SiSpace.x3),
              ],
            ]),
    );
  }

  Widget _barraZona(SiColors c, String zona, double pct, int entradas) {
    final color = _colorEstatus(c, estatusDePuntualidad(pct, _criticoMax, _atencionMax));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(zona,
                overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: c.ink)),
          ),
          Text('${pct.toStringAsFixed(1)}%',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 6),
          Text('($entradas)', style: TextStyle(fontSize: 11, color: c.ink4)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: c.line,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  /// El semáforo de seguimiento: cuántas personas van en crítico, atención y puntual, con los
  /// cortes de Configuración. Quien no tiene días evaluados no entra.
  Widget _tarjetaSemaforo(SiColors c, List<ResumenChecador> todos) {
    final s = {'critico': 0, 'atencion': 0, 'puntual': 0};
    for (final r in todos) {
      final e = _estatus(r);
      if (s.containsKey(e)) s[e] = s[e]! + 1;
    }
    final total = s.values.fold<int>(0, (a, b) => a + b);

    Widget leyenda(String etiqueta, int n, Color color, String rango) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(etiqueta, style: TextStyle(fontSize: 12.5, color: c.ink)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(rango,
                  overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.ink4)),
            ),
            Text('$n', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          ]),
        );

    return _tarjetaLado(
      c,
      Icons.donut_large_outlined,
      'Semáforo de seguimiento',
      total == 0
          ? _sinDatos(c)
          : Column(children: [
              SizedBox(
                height: 150,
                child: CustomPaint(
                  painter: DonaPainter(
                    valores: [
                      (s['critico']!, c.danger),
                      (s['atencion']!, c.warn),
                      (s['puntual']!, c.success),
                    ],
                    fondo: c.line,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$total',
                            style: TextStyle(
                                fontSize: 26, fontWeight: FontWeight.w700, color: c.ink)),
                        Text('personas', style: TextStyle(fontSize: 11, color: c.ink3)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SiSpace.x3),
              leyenda('Crítico', s['critico']!, c.danger,
                  'menos de ${_criticoMax.toStringAsFixed(0)}%'),
              leyenda('Atención', s['atencion']!, c.warn,
                  'hasta ${_atencionMax.toStringAsFixed(0)}%'),
              leyenda('Puntual', s['puntual']!, c.success,
                  'más de ${_atencionMax.toStringAsFixed(0)}%'),
            ]),
    );
  }


  /// Las tarjetas de arriba, las mismas del Panel —puntualidad, retardos, faltas, justificados, días
  /// a descontar, días evaluados y empleados— con los datos del checador propio y del periodo
  /// elegido. Pedido del 29/09/2026.
  ///
  /// La puntualidad es la del conjunto, PONDERADA por días —a tiempo entre evaluadas de todos—, no el
  /// promedio de los porcentajes: una persona con un solo día evaluado no debe pesar como una con
  /// quince. Es la misma cuenta del Panel.
  Widget _kpis(SiColors c, List<ResumenChecador> todos) {
    final evaluadas = todos.fold<int>(0, (a, r) => a + r.evaluadas);
    final retardos = todos.fold<int>(0, (a, r) => a + r.retardos);
    final faltas = todos.fold<int>(0, (a, r) => a + r.faltas);
    final justificados = todos.fold<int>(0, (a, r) => a + r.justificados);
    // Por persona y luego sumado, igual que la columna de la tabla: dividir el total de retardos
    // daría más días de los que son.
    final descuento = todos.fold<int>(0, (a, r) => a + r.diasDescuento(_retardosPorDescuento));
    final pct = evaluadas == 0 ? null : (evaluadas - retardos) / evaluadas * 100;
    final colorPct = pct == null
        ? c.ink3
        : _colorEstatus(c, estatusDePuntualidad(pct, _criticoMax, _atencionMax));

    Widget tarjeta(String titulo, String valor, String pie, Color color) => Container(
          width: 150,
          padding: const EdgeInsets.all(SiSpace.x3),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: SiRadius.rMd,
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo.toUpperCase(),
                  style: SiType.mono(size: 9.5, color: c.ink3, letterSpacing: 0.8)),
              const SizedBox(height: 6),
              Text(valor,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 4),
              Text(pie, style: TextStyle(fontSize: 11, color: c.ink3)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_periodo.etiqueta,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.brand)),
        const SizedBox(height: SiSpace.x3),
        Wrap(
          spacing: SiSpace.x3,
          runSpacing: SiSpace.x3,
          children: [
            tarjeta('Puntualidad', pct == null ? '—' : '${pct.toStringAsFixed(1)}%',
                'del periodo', colorPct),
            tarjeta('Retardos', '$retardos', 'llegadas tarde', c.warn),
            tarjeta('Faltas', '$faltas', 'sin justificar', c.danger),
            tarjeta('Justificados', '$justificados', 'días de vacaciones', c.ink2),
            tarjeta('Días a descontar', '$descuento', 'para nómina',
                descuento > 0 ? c.danger : c.success),
            tarjeta('Días evaluados', '$evaluadas', 'con checada', c.ink2),
            tarjeta('Empleados', '${todos.length}', 'en el periodo', c.ink2),
          ],
        ),
      ],
    );
  }

  Widget _fila(SiColors c, ResumenChecador r, List<double> anchos) {
    final estatus = _estatus(r);
    final color = _colorEstatus(c, estatus);
    final pct = r.puntualidad;
    final descuento = r.diasDescuento(_retardosPorDescuento);
    final numero = _perfiles[r.profileId]?['numero_empleado']?.toString() ?? '';
    final horario = _horarioDe(r.profileId)?['name']?.toString() ?? 'Sin horario asignado';

    Widget celda(int i, Widget hijo) => SizedBox(width: anchos[i], child: hijo);
    Widget numeroEn(int n, Color col) => Text('$n',
        style: TextStyle(
            fontSize: 12.5,
            fontWeight: n > 0 ? FontWeight.w600 : FontWeight.normal,
            color: col,
            fontFeatures: const [FontFeature.tabularFigures()]));

    return InkWell(
      onTap: () => _mostrarFicha(r),
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line2))),
        padding: const EdgeInsets.symmetric(vertical: SiSpace.x2),
        child: Row(
          children: [
            celda(
              0,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_nombre(r.profileId),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: c.brand,
                          decoration: TextDecoration.underline,
                          decorationColor: c.brand.withValues(alpha: 0.3))),
                  Text([if (numero.isNotEmpty) '#$numero', horario].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: c.ink3)),
                ],
              ),
            ),
            celda(
              1,
              Text(_zonaDe(r.profileId),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.ink2)),
            ),
            celda(
              2,
              Row(children: [
                SizedBox(
                  width: 42,
                  child: Text(pct == null ? '—' : '${pct.toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: ((pct ?? 0) / 100).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: c.line,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
                const SizedBox(width: SiSpace.x6),
              ]),
            ),
            celda(3, numeroEn(r.retardos, r.retardos > 0 ? c.warn : c.ink3)),
            celda(4, numeroEn(r.faltas, r.faltas > 0 ? c.danger : c.ink3)),
            celda(5, numeroEn(r.justificados, c.ink3)),
            celda(
              6,
              Tooltip(
                message: descuento == 0
                    ? 'Sin días a descontar'
                    : '${r.retardos} retardos ÷ $_retardosPorDescuento = '
                        '${r.retardos ~/ _retardosPorDescuento} · faltas: ${r.faltas}',
                child: numeroEn(descuento, descuento > 0 ? c.danger : c.ink3),
              ),
            ),
            celda(
              7,
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: SiRadius.rPill,
                  ),
                  child: Text(_etiquetaEstatus[estatus] ?? estatus,
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
