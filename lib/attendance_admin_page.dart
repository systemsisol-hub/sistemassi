import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'schedules_page.dart';

class AttendanceAdminPage extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;
  final String? initialSearchQuery;
  const AttendanceAdminPage(
      {super.key,
      required this.role,
      required this.permissions,
      this.initialSearchQuery});

  @override
  State<AttendanceAdminPage> createState() => _AttendanceAdminPageState();
}

class _AttendanceAdminPageState extends State<AttendanceAdminPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allRecords = [];
  final _supabase = Supabase.instance.client;
  String _searchQuery = '';
  final GlobalKey<SchedulesPageState> _schedulesKey =
      GlobalKey<SchedulesPageState>();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // Obtener todos los registros uniendo con perfiles para ver nombres y horarios
      final data = await _supabase
          .from('attendance')
          .select(
              '*, profiles:colaborador_id(full_name, work_start_time, work_end_time, schedules(name, rules))')
          .order('date', ascending: false);

      if (mounted) {
        setState(() {
          _allRecords = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar datos administrativos: $e');
      if (mounted) setState(() => _isLoading = false);
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const SizedBox.shrink(),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        toolbarHeight: 0, // Ocultamos el appbar vacío para ganar espacio
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 800) {
            // Diseño Escritorio: Tres tarjetas iguales
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Card 1: Horarios
                Expanded(
                  child: SchedulesPage(
                    key: _schedulesKey,
                    title: 'HORARIOS',
                    hideAddButton: false,
                    hideSearch: true,
                  ),
                ),
                const SizedBox(width: 24),
                // Card 2: Registros de Asistencia
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildList(theme),
                ),
                const SizedBox(width: 24),
                // Card 3: Tarjeta Vacía
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Center(
                      child: Icon(Icons.add_chart_outlined, color: Colors.grey[200], size: 48),
                    ),
                  ),
                ),
              ],
            );
          } else {
            // Diseño Móvil: Secciones retráctiles (Existente)
            return SingleChildScrollView(
              child: Column(
                children: [
                  ExpansionTile(
                    initiallyExpanded: false,
                    iconColor: theme.colorScheme.primary,
                    collapsedIconColor: Colors.grey,
                    title: Text('Horarios',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: theme.colorScheme.primary)),
                    children: [
                      const SchedulesPage(),
                    ],
                  ),
                  const Divider(height: 1),
                  ExpansionTile(
                    initiallyExpanded: false,
                    iconColor: theme.colorScheme.primary,
                    collapsedIconColor: Colors.grey,
                    title: Text('Registros',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: theme.colorScheme.primary)),
                    children: [
                      _isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(child: CircularProgressIndicator()))
                          : _buildList(theme),
                    ],
                  ),
                ],
              ),
            );
  }
        },
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final filteredRecords = _allRecords.where((rec) {
      final name = (rec['profiles']?['full_name'] ?? '').toString().toLowerCase();
      final date = (rec['date'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) || date.contains(_searchQuery.toLowerCase());
    }).toList();

    return SizedBox(
      width: double.infinity,
      child: PaginatedDataTable(
        header: Row(
          children: [
            Text(
              'ASISTENCIA',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 1,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: SizedBox(
                height: 38,
                child: TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'Buscar empleado o fecha...',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: theme.colorScheme.primary)),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        dataRowMaxHeight: 60,
        dataRowMinHeight: 60,
        columnSpacing: 20,
        horizontalMargin: 24,
        columns: [
          DataColumn(label: Text('EMPLEADO', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1))),
          DataColumn(label: Text('FECHA', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1))),
          DataColumn(label: Text('HORA', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1))),
          const DataColumn(label: SizedBox()), // Acciones
        ],
        source: _AttendanceDataSource(
          records: filteredRecords,
          theme: theme,
          onOpenMap: (lat, lng) => _openMap(lat, lng),
          onViewPhotos: (rec) => _showPhotosDialog(rec),
        ),
        rowsPerPage: filteredRecords.isEmpty ? 1 : (filteredRecords.length > 10 ? 10 : filteredRecords.length),
        showCheckboxColumn: false,
      ),
    );
  }

  void _showPhotosDialog(Map<String, dynamic> rec) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Evidencia Fotográfica - ${rec['profiles']?['full_name'] ?? 'Usuario'}'),
        content: _buildPhotoSection(rec['photo_url'], rec['photo_out_url']),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR')),
        ],
      ),
    );
  }

  Widget _buildPhotoSection(String? entryUrl, String? exitUrl) {
    if (entryUrl == null && exitUrl == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Evidencia Fotográfica:',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey)),
        const SizedBox(height: 12),
        Wrap(
          // Wrap es mejor que Row+Expanded para evitar el estiramiento en pantallas grandes
          spacing: 20,
          runSpacing: 16,
          children: [
            if (entryUrl != null) _buildImageCard('Entrada', entryUrl),
            if (exitUrl != null) _buildImageCard('Salida', exitUrl),
          ],
        ),
      ],
    );
  }

  Widget _buildImageCard(String label, String url) {
    return SizedBox(
      width: 180, // Tamaño fijo controlado para evitar "exageración"
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              url,
              height: 180,
              width: 180,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 180,
                width: 180,
                color: Colors.grey[100],
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildAdminInfoRow(
      String label, String? timeStr, num? lat, num? lng, ThemeData theme,
      {bool isOut = false}) {
    final hasTime = timeStr != null;
    final time = hasTime ? DateTime.parse(timeStr).toLocal() : null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    hasTime ? DateFormat('HH:mm').format(time!) : '--:--',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (lat != null && lng != null && lat != 0)
          TextButton.icon(
            onPressed: () => _openMap(lat, lng),
            icon: Icon(Icons.map,
                size: 16,
                color: isOut ? Colors.orange : theme.colorScheme.primary),
            label: Text('VER MAPA',
                style: TextStyle(
                    color: isOut ? Colors.orange : theme.colorScheme.primary)),
          )
        else
          const Text('Sin GPS',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }



}

class _AttendanceDataSource extends DataTableSource {
  final List<Map<String, dynamic>> records;
  final ThemeData theme;
  final Function(num?, num?) onOpenMap;
  final Function(Map<String, dynamic>) onViewPhotos;

  _AttendanceDataSource({
    required this.records,
    required this.theme,
    required this.onOpenMap,
    required this.onViewPhotos,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= records.length) return null;
    final rec = records[index];
    final name = rec['profiles']?['full_name'] ?? 'Usuario Desconocido';
    final dateStr = rec['date'] ?? '';
    final recordDate = DateTime.tryParse(dateStr) ?? DateTime.now();
    final checkInStr = rec['check_in'];
    final checkOutStr = rec['check_out'];

    final schedData = rec['profiles']?['schedules'];
    final Map<String, dynamic>? sched =
        (schedData is List && schedData.isNotEmpty)
            ? schedData[0] as Map<String, dynamic>
            : (schedData is Map<String, dynamic> ? schedData : null);

    final List<dynamic> rules =
        (sched != null && sched['rules'] != null) ? sched['rules'] : [];

    String statusText = 'PENDIENTE';
    Color statusColor = Colors.grey;

    final dayIndex = recordDate.weekday % 7;
    final entryRule = rules.firstWhere(
      (r) => r['day'] == dayIndex && r['type'] == 'ENTRADA',
      orElse: () => null,
    );

    if (checkInStr != null) {
      final checkInLocal = DateTime.parse(checkInStr).toLocal();
      if (entryRule != null) {
        final workStartStr = entryRule['time'] ?? '09:00:00';
        final tolerance = entryRule['tol'] ?? 10;
        final parts = workStartStr.split(':');
        final workStart = DateTime(recordDate.year, recordDate.month, recordDate.day, int.parse(parts[0]), int.parse(parts[1]));
        if (checkInLocal.isAfter(workStart.add(Duration(minutes: tolerance)))) {
          statusText = 'RETARDO';
          statusColor = Colors.orange;
        } else {
          statusText = 'A TIEMPO';
          statusColor = Colors.green;
        }
      } else {
        statusText = 'REGISTRADO';
        statusColor = theme.colorScheme.primary;
      }
    } else {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // Wait, there's a typo in my thought: recordDate.isBefore(today).
      if (recordDate.isBefore(today)) {
        statusText = 'FALTA';
        statusColor = Colors.red;
      }
    }

    final nameParts = name.split(' ');
    final shortName = nameParts.length >= 2 ? '${nameParts[0]} ${nameParts[1]}' : name;

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(shortName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            Text(statusText, style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ],
        )),
        DataCell(Text(DateFormat('dd/MM/yy').format(recordDate), style: const TextStyle(fontSize: 12))),
        DataCell(Row(
          children: [
            const Icon(Icons.login, size: 13, color: Color(0xFFB1CB34)),
            const SizedBox(width: 4),
            Text(checkInStr != null ? DateFormat('HH:mm').format(DateTime.parse(checkInStr).toLocal()) : '--:--', 
                 style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            const Icon(Icons.logout, size: 13, color: Colors.orange),
            const SizedBox(width: 4),
            Text(checkOutStr != null ? DateFormat('HH:mm').format(DateTime.parse(checkOutStr).toLocal()) : '--:--',
                 style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        )),
        DataCell(Align(
          alignment: Alignment.centerRight,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: Colors.grey),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'map_in') onOpenMap(rec['lat'], rec['lng']);
              if (val == 'map_out') onOpenMap(rec['lat_out'], rec['lng_out']);
              if (val == 'photos') onViewPhotos(rec);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'photos', child: ListTile(leading: Icon(Icons.photo_library_outlined), title: Text('Ver Fotos'), dense: true)),
              if (rec['lat'] != null) const PopupMenuItem(value: 'map_in', child: ListTile(leading: Icon(Icons.location_on_outlined, color: Colors.blue), title: Text('Mapa Entrada'), dense: true)),
              if (rec['lat_out'] != null) const PopupMenuItem(value: 'map_out', child: ListTile(leading: Icon(Icons.location_on_outlined, color: Colors.orange), title: Text('Mapa Salida'), dense: true)),
            ],
          ),
        )),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => records.length;
  @override
  int get selectedRowCount => 0;
}
