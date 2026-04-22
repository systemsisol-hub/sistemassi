import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'checador_camera_native.dart'
    if (dart.library.html) 'checador_web_impl.dart' as camera_impl;
import 'checador_camera_preview_native.dart'
    if (dart.library.html) 'checador_camera_preview_stub.dart'
    as camera_preview;

class ChecadorPage extends StatefulWidget {
  const ChecadorPage({super.key});

  @override
  State<ChecadorPage> createState() => _ChecadorPageState();
}

class _ChecadorPageState extends State<ChecadorPage> {
  bool _isLoading = true;
  bool _isProcessing = false;
  Map<String, dynamic>? _todayRecord;
  String? _errorString;
  List<Map<String, dynamic>> _history = [];
  bool _autoTriggered = false;
  final _supabase = Supabase.instance.client;
  Timer? _clockTimer;
  DateTime _currentTime = DateTime.now();
  late camera_impl.NativeCameraController _cameraController;
  bool _cameraReady = false;

  @override
  void initState() {
    super.initState();
    _cameraController = camera_impl.NativeCameraController();
    _fetchData();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _currentTime = DateTime.now());
    });
    _initCamera();
  }

  Future<void> _initCamera() async {
    await _cameraController.initCamera();
    if (mounted) setState(() => _cameraReady = _cameraController.isReady);
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);

      // Obtener registro de hoy
      final todayData = await _supabase
          .from('attendance')
          .select()
          .eq('colaborador_id', userId)
          .eq('date', todayStr)
          .maybeSingle();

      // Obtener historial reciente
      final historyData = await _supabase
          .from('attendance')
          .select()
          .eq('colaborador_id', userId)
          .order('date', ascending: false)
          .limit(10);

      if (mounted) {
        setState(() {
          _todayRecord = todayData;
          _history = List<Map<String, dynamic>>.from(historyData);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar datos del checador: $e');
      if (mounted) {
        setState(() {
          _errorString = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleCheck({required bool isEntry}) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Feedback inmediato
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Iniciando checado: Solicitando GPS y Cámara...'),
          duration: Duration(seconds: 2)),
    );

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw 'Usuario no autenticado';

      // 1. Verificar permisos y obtener ubicación
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Los servicios de ubicación están desactivados.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Los permisos de ubicación fueron denegados.';
        }
      }

      // 1. Iniciar captura de ubicación en segundo plano (para ganar tiempo)
      final locationFuture = Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      ).catchError((e) {
        debugPrint('Error obteniendo ubicación: $e');
        return Position(
            latitude: 0.0,
            longitude: 0.0,
            timestamp: DateTime.now(),
            accuracy: 0.0,
            altitude: 0.0,
            heading: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
            altitudeAccuracy: 0.0,
            headingAccuracy: 0.0);
      });

      // 2. Capturar foto de la cámara
      debugPrint('Capturando foto...');
      Uint8List bytes;

      if (_cameraReady) {
        final captured = await _cameraController.captureFrame();
        if (captured != null) {
          bytes = captured;
        } else {
          throw 'No se pudo capturar imagen de la cámara';
        }
      } else {
        // Fallback a image_picker si la cámara no está disponible
        final ImagePicker picker = ImagePicker();
        final XFile? photo = await picker
            .pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.front,
          imageQuality: 70,
        )
            .catchError((e) {
          throw 'Error al abrir cámara: $e';
        });
        if (photo == null) {
          setState(() => _isProcessing = false);
          return;
        }
        bytes = await photo.readAsBytes();
      }

      // 3. Esperar a que la ubicación esté lista
      final Position position = await locationFuture;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final type = isEntry ? 'entry' : 'exit';
      final fileName =
          'attendance/$userId/${DateFormat('yyyy-MM-dd').format(DateTime.now())}_$type\_$timestamp.jpg';

      await _supabase.storage.from('asistencia_registros').uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(
                cacheControl: '3600', upsert: false, contentType: 'image/jpeg'),
          );

      final photoUrl =
          _supabase.storage.from('asistencia_registros').getPublicUrl(fileName);

      // 4. Guardar en base de datos
      if (isEntry) {
        // Registrar Entrada
        await _supabase.from('attendance').insert({
          'colaborador_id': userId,
          'check_in': DateTime.now().toUtc().toIso8601String(),
          'lat': position.latitude,
          'lng': position.longitude,
          'accuracy': position.accuracy,
          'photo_url': photoUrl,
          'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        });
      } else {
        // Registrar Salida
        await _supabase.from('attendance').update({
          'check_out': DateTime.now().toUtc().toIso8601String(),
          'lat_out': position.latitude,
          'lng_out': position.longitude,
          'photo_out_url': photoUrl,
        }).eq('id', _todayRecord!['id']);
      }

      // 5. Finalizar
      await _fetchData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEntry
                ? 'Entrada registrada con éxito'
                : 'Salida registrada con éxito'),
            backgroundColor: const Color(0xFFB1CB34),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorString = 'Error en el proceso: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _openMap(num? lat, num? lng) async {
    if (lat == null || lng == null || (lat == 0 && lng == 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicación no disponible')),
      );
      return;
    }
    final Uri url =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el mapa')),
      );
    }
  }

  String _formatDateForUser(DateTime date) {
    final dayName = DateFormat('EEEE', 'es').format(date);
    final dayNumber = DateFormat('d', 'es').format(date);
    final monthName = DateFormat('MMMM', 'es').format(date);
    final year = DateFormat('yyyy', 'es').format(date);

    // Capitalizar mes
    final capitalizedMonth = monthName.isNotEmpty
        ? '${monthName[0].toUpperCase()}${monthName.substring(1)}'
        : monthName;

    return "$dayName, $dayNumber $capitalizedMonth $year";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCheckedIn = _todayRecord != null;
    final isCheckedOut = isCheckedIn && _todayRecord!['check_out'] != null;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // Desktop 3-column layout
            return SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Col 1: Camera
                  Expanded(
                    flex: 4,
                    child: _buildStatusCard(theme, isCheckedIn, isCheckedOut),
                  ),
                  const SizedBox(width: 32),
                  // Col 2: Clock & Actions
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        _buildClockSection(theme),
                        const SizedBox(height: 32),
                        _buildActionButtons(isCheckedIn, isCheckedOut),
                      ],
                    ),
                  ),
                  const SizedBox(width: 32),
                  // Col 3: History
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Historial Reciente',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        _buildHistoryList(theme),
                      ],
                    ),
                  ),
                ],
              ),
            );
          } else {
            // Mobile / Tablet single column layout
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusCard(theme, isCheckedIn, isCheckedOut),
                  if (_errorString != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      '$_errorString',
                      style: const TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 32),
                  _buildActionButtons(isCheckedIn, isCheckedOut),
                  const SizedBox(height: 32),
                  _buildClockSection(theme),
                  const SizedBox(height: 32),
                  const Text(
                    'Historial Reciente',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildHistoryList(theme),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildClockSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withOpacity(0.08),
            theme.colorScheme.primary.withOpacity(0.02)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          Text(
            DateFormat('HH:mm:ss').format(_currentTime),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              color: theme.colorScheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatDateForUser(_currentTime),
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isCheckedIn, bool isCheckedOut) {
    if (isCheckedOut) {
      return const Card(
        color: Color(0xFFB1CB34),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 32),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Jornada completada por hoy',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isProcessing) return const Center(child: CircularProgressIndicator());

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isCheckedIn ? null : () => _handleCheck(isEntry: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB1CB34),
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.login, size: 24),
            label: const Text(
              'ENTRADA',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: (isCheckedIn && !isCheckedOut)
                ? () => _handleCheck(isEntry: false)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.logout, size: 24),
            label: const Text(
              'SALIDA',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(ThemeData theme, bool isIn, bool isOut) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Camera preview box
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.3), width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Live camera preview
              if (_cameraReady)
                kIsWeb
                    ? HtmlElementView(viewType: _cameraController.viewId)
                    : camera_preview.NativeCameraPreview(
                        controller: _cameraController.controller)
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.videocam_rounded,
                        size: 64, color: Colors.white.withOpacity(0.25)),
                    const SizedBox(height: 12),
                    Text(
                      'Iniciando cámara...',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.4), fontSize: 13),
                    ),
                  ],
                ),
              // Status overlay badge
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isIn
                        ? (isOut ? Colors.grey : const Color(0xFFB1CB34))
                        : theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isIn
                            ? (isOut ? Icons.event_available : Icons.timer)
                            : Icons.timer_outlined,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isIn
                            ? (isOut
                                ? '\u00a1Hasta ma\u00f1ana!'
                                : 'En el trabajo')
                            : 'Fuera del trabajo',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeInfo(String label, String? time) {
    if (time == null) return const SizedBox.shrink();
    final dateTime = DateTime.parse(time).toLocal();
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(height: 4),
        Text(
          DateFormat('HH:mm').format(dateTime),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildHistoryList(ThemeData theme) {
    if (_history.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No hay registros previos',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _history.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _history[index];
        final date = DateTime.parse(item['date']);
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey[100]!),
          ),
          child: ListTile(
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('dd').format(date),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  DateFormat('MMM').format(date).toUpperCase(),
                  style:
                      TextStyle(fontSize: 10, color: theme.colorScheme.primary),
                ),
              ],
            ),
            title: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.login, size: 14, color: Color(0xFFB1CB34)),
                    const SizedBox(width: 4),
                    Text(
                      item['check_in'] != null
                          ? DateFormat('HH:mm').format(
                              DateTime.parse(item['check_in']).toLocal())
                          : '--:--',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (item['check_out'] != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.logout, size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('HH:mm').format(
                            DateTime.parse(item['check_out']).toLocal()),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  item['validated'] == true
                      ? 'Validado ✅'
                      : 'Pendiente (GPS capturado 📍)',
                  style: const TextStyle(fontSize: 12),
                ),
                if (item['lat'] != null && item['lng'] != null) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _openMap(item['lat'], item['lng']),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on,
                            size: 12, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Ver ubicación Entrada',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (item['lat_out'] != null && item['lng_out'] != null) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _openMap(item['lat_out'], item['lng_out']),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on, size: 12, color: Colors.orange),
                        const SizedBox(width: 4),
                        Text(
                          'Ver ubicación Salida',
                          style: TextStyle(
                            color: Colors.orange[700],
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
