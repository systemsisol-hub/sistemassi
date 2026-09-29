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

/// La hora de la checada en el lugar donde se hizo, no en el reloj de quien mira. Ver
/// `desfaseHorasDe`.
DateTime? _horaLocal(Map<String, dynamic> ch) {
  final d = DateTime.tryParse(ch['registrada_en']?.toString() ?? '');
  if (d == null) return null;
  return horaLocalDeChecada(d, ch['latitud'] as num?, ch['longitud'] as num?);
}

String _horaDe(Map<String, dynamic>? ch) {
  final d = ch == null ? null : _horaLocal(ch);
  return d == null ? '—' : DateFormat('HH:mm').format(d);
}

/// El color de una checada contra el horario. Sólo la entrada y el fin de jornada tienen hora en
/// los horarios; la comida no lleva color.
Semaforo? _semaforoDe(Map<String, dynamic> ch, List<dynamic>? reglas) {
  final d = _horaLocal(ch);
  final dia = DateTime.tryParse(ch['fecha']?.toString() ?? '');
  if (d == null || dia == null) return null;
  final r = reglasDelDia(reglas, dia);
  final m = d.hour * 60 + d.minute;
  if (ch['tipo'] == 'ENTRADA' && r.entrada != null) return semaforoEntrada(m, r.entrada!);
  if (ch['tipo'] == 'SALIDA' && r.salida != null) return semaforoSalida(m, r.salida!);
  return null;
}

Color _colorSemaforo(SiColors c, Semaforo s) => switch (s) {
      Semaforo.verde => c.success,
      Semaforo.amarillo => c.warn,
      Semaforo.rojo => c.danger,
    };

/// La diferencia contra el horario, del color del semáforo: «36 min antes» en verde, «12 min
/// tarde» en amarillo. Nada si esa checada no tiene hora en el horario. Pedido del 29/09/2026, en
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
    child: Text(diferenciaEnPalabras(tipo, d.minutos),
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
          .select('id, tipo, registrada_en, fecha, latitud, longitud, precision_m, foto')
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
              '${_fechaLarga(DateTime.parse(ch['fecha'].toString()))} · ${_horaDe(ch)}',
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

class _ChecadorRegistrosState extends State<ChecadorRegistros> {
  DateTime _dia = DateTime.now();
  bool _cargando = true;
  String? _error;
  String _busqueda = '';

  /// Por persona: sus checadas del día por tipo.
  Map<String, Map<String, Map<String, dynamic>>> _porPersona = {};
  Map<String, Map<String, dynamic>> _perfiles = {};
  Map<String, Map<String, dynamic>> _horariosPorId = {};

  /// El filtro de los contadores: 'verde', 'amarillo', 'rojo', 'sin' o null para todos.
  String? _filtro;

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
      // Los ACTIVOS, para saber quién debía checar y no lo hizo; y quien checó aunque ya no lo esté.
      const campos = 'id, nombre, paterno, materno, numero_empleado, schedule_id';
      final activos = await _supabase.from('profiles').select(campos).eq('status_sys', 'ACTIVO');
      final perfiles = <String, Map<String, dynamic>>{
        for (final x in (activos as List).cast<Map<String, dynamic>>()) x['id'] as String: x,
      };
      final faltan = porPersona.keys.where((id) => !perfiles.containsKey(id)).toList();
      if (faltan.isNotEmpty) {
        final otros = await _supabase.from('profiles').select(campos).inFilter('id', faltan);
        for (final x in (otros as List).cast<Map<String, dynamic>>()) {
          perfiles[x['id'] as String] = x;
        }
      }
      final horarios = await _horarios();
      if (!mounted) return;
      setState(() {
        _porPersona = porPersona;
        _perfiles = perfiles;
        _horariosPorId = horarios;
        _cargando = false;
      });
    } catch (e) {
      debugPrint('checador: registros: $e');
      if (mounted) setState(() { _cargando = false; _error = '$e'; });
    }
  }

  Map<String, dynamic>? _horarioDe(String id) {
    final h = _perfiles[id]?['schedule_id'] as String?;
    return h == null ? null : _horariosPorId[h];
  }

  /// Cómo va la ENTRADA de una persona ese día: su color, 'sin' si debía checar y no lo hizo,
  /// 'aun' si todavía está a tiempo de hacerlo, o null si no tiene horario ese día.
  String? _estadoEntrada(String id) {
    final reglas = _horarioDe(id)?['rules'] as List<dynamic>?;
    final entrada = reglasDelDia(reglas, _dia).entrada;
    final ch = _porPersona[id]?['ENTRADA'];
    if (ch != null) return _semaforoDe(ch, reglas)?.name;
    if (entrada == null) return null;
    final hoy = DateUtils.isSameDay(_dia, DateTime.now());
    final ahora = DateTime.now();
    if (hoy && ahora.hour * 60 + ahora.minute <= entrada.minutos + entrada.tolerancia) return 'aun';
    return 'sin';
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

    // Quien checó, y quien debía checar ese día según su horario aunque no lo haya hecho.
    final todos = <String>{
      ..._porPersona.keys,
      for (final id in _perfiles.keys)
        if (reglasDelDia(_horarioDe(id)?['rules'] as List<dynamic>?, _dia).entrada != null) id,
    };
    final estados = {for (final id in todos) id: _estadoEntrada(id)};
    final cuenta = <String, int>{};
    for (final e in estados.values) {
      if (e != null) cuenta[e] = (cuenta[e] ?? 0) + 1;
    }

    final ids = todos
        .where((id) => _filtro == null || estados[id] == _filtro)
        .where((id) => q.isEmpty || _nombre(id).toLowerCase().contains(q)
            || (_perfiles[id]?['numero_empleado']?.toString() ?? '').contains(q))
        .toList()
      ..sort((a, b) => _nombre(a).compareTo(_nombre(b)));

    Widget contador(String clave, String etiqueta, Color color) {
      final activo = _filtro == clave;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _filtro = activo ? null : clave),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: SiSpace.x3, vertical: SiSpace.x2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: activo ? 0.18 : 0.08),
            border: Border.all(color: color.withValues(alpha: activo ? 0.9 : 0.35)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${cuenta[clave] ?? 0}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(width: SiSpace.x2),
              Text(etiqueta, style: TextStyle(fontSize: 12.5, color: c.ink2)),
            ],
          ),
        ),
      );
    }

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
          const SizedBox(height: SiSpace.x3),
          // El conteo del día por color de la ENTRADA. Tocar uno filtra la tabla.
          if (!_cargando && _error == null)
            Wrap(
              spacing: SiSpace.x2,
              runSpacing: SiSpace.x2,
              children: [
                contador('verde', 'a tiempo', c.success),
                contador('amarillo', 'en tolerancia', c.warn),
                contador('rojo', 'con retardo', c.danger),
                contador('sin', 'sin checar', c.ink3),
                if ((cuenta['aun'] ?? 0) > 0) contador('aun', 'aún a tiempo', c.ink4),
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
                    todos.isEmpty
                        ? 'Nadie ha checado con el sistema este día.'
                        : 'Nadie coincide con el filtro o la búsqueda.',
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
                        DataCell(Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_nombre(id)),
                            Text(_horarioDe(id)?['name']?.toString() ?? 'Sin horario asignado',
                                style: TextStyle(fontSize: 11, color: c.ink4)),
                          ],
                        )),
                        for (final t in tiposDeChecada)
                          DataCell(
                            _porPersona[id]?[t] == null
                                ? Text(
                                    t == 'ENTRADA' && estados[id] == 'sin'
                                        ? 'Sin checar'
                                        : (t == 'ENTRADA' && estados[id] == 'aun' ? 'Aún no' : '—'),
                                    style: TextStyle(
                                        color: t == 'ENTRADA' && estados[id] == 'sin'
                                            ? c.danger
                                            : c.ink4,
                                        fontWeight: t == 'ENTRADA' && estados[id] == 'sin'
                                            ? FontWeight.w600
                                            : null))
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(_horaDe(_porPersona[id]![t]),
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: c.brand,
                                              fontFeatures: const [FontFeature.tabularFigures()])),
                                      const SizedBox(width: 6),
                                      _diferencia(c, _porPersona[id]![t]!,
                                          _horarioDe(id)?['rules'] as List<dynamic>?),
                                      const SizedBox(width: 4),
                                      Icon(Icons.photo_camera_outlined, size: 14, color: c.ink4),
                                    ],
                                  ),
                            onTap: _porPersona[id]?[t] == null
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
