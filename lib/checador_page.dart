import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'schedules_page.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'attendance_admin_page.dart';
import 'checador_camera_native.dart'
    if (dart.library.html) 'checador_web_impl.dart' as camera_impl;
import 'checador_camera_preview_native.dart'
    if (dart.library.html) 'checador_camera_preview_stub.dart'
    as camera_preview;

class ChecadorPage extends StatefulWidget {
  final bool isAdmin;
  final String role;
  final Map<String, dynamic> permissions;
  const ChecadorPage({
    super.key,
    this.isAdmin = false,
    this.role = 'user',
    this.permissions = const {},
  });

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
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 800;
          return SingleChildScrollView(
            padding: EdgeInsets.all(isDesktop ? 32 : 20),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isDesktop ? 1200 : 600),
                child: Column(
                  children: [
                    if (_errorString != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade100),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red),
                            const SizedBox(width: 12),
                            Expanded(child: Text(_errorString!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500))),
                          ],
                        ),
                      ),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Columna Izquierda: Checador Unificado
                        Expanded(
                          flex: 6,
                          child: _buildUnifiedChecadorCard(theme, isCheckedIn, isCheckedOut),
                        ),
                        if (isDesktop) ...[
                          const SizedBox(width: 32),
                          // Columna Derecha: Historial en Tarjeta
                          Expanded(
                            flex: 4,
                            child: _buildHistoryCard(theme),
                          ),
                        ],
                      ],
                    ),
                    if (!isDesktop) ...[
                      const SizedBox(height: 32),
                      _buildHistoryCard(theme),
                    ],
                    if (widget.isAdmin) ...[
                      const SizedBox(height: 48),
                      const Divider(),
                      const SizedBox(height: 32),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'PANEL DE ADMINISTRACIÓN',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Usamos AttendanceAdminPage que ya tiene todo el layout de admin
                      SizedBox(
                        height: 800,
                        child: AttendanceAdminPage(
                          role: widget.role,
                          permissions: widget.permissions,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUnifiedChecadorCard(ThemeData theme, bool isIn, bool isOut) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            // Fecha
            Text(
              _formatDateForUser(_currentTime).toUpperCase(),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            // Hora
            Text(
              DateFormat('HH:mm:ss').format(_currentTime),
              style: TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.bold,
                letterSpacing: -2,
                color: theme.colorScheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 32),
            // Imagen (Cámara)
            Container(
              height: 360,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_cameraReady)
                    kIsWeb
                        ? HtmlElementView(viewType: _cameraController.viewId)
                        : camera_preview.NativeCameraPreview(
                            controller: _cameraController.controller)
                  else
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam_off_rounded, size: 64, color: Colors.white.withOpacity(0.2)),
                        const SizedBox(height: 16),
                        Text('Iniciando cámara...', style: TextStyle(color: Colors.white.withOpacity(0.4))),
                      ],
                    ),
                  // Status Badge
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isIn ? (isOut ? Colors.grey : const Color(0xFFB1CB34)) : theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                      ),
                      child: Row(
                        children: [
                          Icon(isIn ? (isOut ? Icons.check_circle : Icons.work) : Icons.work_outline, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            isIn ? (isOut ? 'JORNADA TERMINADA' : 'EN TURNO') : 'FUERA DE TURNO',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            // Botón Único Unificado
            _buildUnifiedActionButton(isIn, isOut, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedActionButton(bool isIn, bool isOut, ThemeData theme) {
    if (isOut) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFB1CB34).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFB1CB34), width: 2),
        ),
        child: const Center(
          child: Column(
            children: [
              Icon(Icons.verified, color: Color(0xFFB1CB34), size: 32),
              SizedBox(height: 8),
              Text(
                'HAS COMPLETADO TU JORNADA',
                style: TextStyle(color: Color(0xFFB1CB34), fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1),
              ),
            ],
          ),
        ),
      );
    }

    if (_isProcessing) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final bool isEntry = !isIn;
    final color = isEntry ? const Color(0xFFB1CB34) : Colors.orange;
    final label = isEntry ? 'REGISTRAR ENTRADA' : 'REGISTRAR SALIDA';
    final icon = isEntry ? Icons.login_rounded : Icons.logout_rounded;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _handleCheck(isEntry: isEntry),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 26),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 8,
          shadowColor: color.withOpacity(0.4),
        ),
        icon: Icon(icon, size: 32),
        label: Text(
          label,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
      ),
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

  Widget _buildHistoryCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              children: [
                Icon(Icons.history, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'HISTORIAL RECIENTE',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Altura fija para mostrar aprox 5 registros (cada registro mide ~90px)
          SizedBox(
            height: 500,
            child: _buildHistoryList(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(ThemeData theme) {
    if (_history.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No hay registros previos', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _history.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _history[index];
        final date = DateTime.parse(item['date']);
        return Card(
          elevation: 0,
          color: Colors.grey[50]!,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey[100]!),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('dd').format(date),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  DateFormat('MMM').format(date).toUpperCase(),
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.primary),
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
                const Text(
                  'Registro capturado (GPS activo 📍)',
                  style: TextStyle(fontSize: 12),
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
