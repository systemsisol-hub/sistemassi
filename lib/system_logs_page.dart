import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'widgets/page_header.dart';

class SystemLogsPage extends StatefulWidget {
  const SystemLogsPage({super.key});

  @override
  State<SystemLogsPage> createState() => _SystemLogsPageState();
}

class _SystemLogsPageState extends State<SystemLogsPage> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  DateTime? _startDate;
  DateTime? _endDate;
  Map<DateTime, int> _dailyLogins = {};

  @override
  void initState() {
    super.initState();
    _fetchLogs();
    _fetchChartData();
  }

  Future<void> _fetchChartData() async {
    try {
      final now = DateTime.now();
      final oneWeekAgo = DateTime(now.year, now.month, now.day - 6);
      
      final data = await Supabase.instance.client
          .from('system_logs')
          .select('created_at')
          .eq('action_type', 'INICIO DE SESIÓN')
          .gte('created_at', oneWeekAgo.toIso8601String())
          .order('created_at', ascending: true);

      final Map<DateTime, int> counts = {};
      // Initialize days
      for (int i = 0; i < 7; i++) {
        final date = DateTime(oneWeekAgo.year, oneWeekAgo.month, oneWeekAgo.day + i);
        counts[date] = 0;
      }

      for (final row in data) {
        final date = DateTime.parse(row['created_at']).toLocal();
        final dayDate = DateTime(date.year, date.month, date.day);
        if (counts.containsKey(dayDate)) {
          counts[dayDate] = (counts[dayDate] ?? 0) + 1;
        }
      }

      if (mounted) {
        setState(() {
          _dailyLogins = counts;
        });
      }
    } catch (e) {
      debugPrint('Error fetching chart data: $e');
    }
  }

  Future<void> _fetchLogs() async {
    setState(() => _isLoading = true);
    try {
      var query = Supabase.instance.client
          .from('system_logs')
          .select('*, profiles:actor_id(nombre, paterno, email)');

      if (_startDate != null) {
        query = query.gte('created_at', _startDate!.toIso8601String());
      }
      if (_endDate != null) {
        // Add 23:59:59 to include the whole end day if using only dates
        final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        query = query.lte('created_at', end.toIso8601String());
      }

      final data = await query.order('created_at', ascending: false).limit(100);

      
      setState(() {
        _logs = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching logs: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Column(
      children: [
        PageHeader(
          title: 'Logs del Sistema',
          trailing: _isLoading 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
            : const Icon(Icons.show_chart, color: Colors.white),
          bottom: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildDateSelector(
                    label: _startDate == null ? 'Desde' : _formatDateOnly(_startDate!),
                    icon: Icons.calendar_today,
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _startDate ?? DateTime.now(),
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) {
                        setState(() => _startDate = d);
                        _fetchLogs();
                      }
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward, size: 16, color: Colors.white70),
                  ),
                  _buildDateSelector(
                    label: _endDate == null ? 'Hasta' : _formatDateOnly(_endDate!),
                    icon: Icons.event,
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _endDate ?? DateTime.now(),
                        firstDate: _startDate ?? DateTime(2024),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) {
                        setState(() => _endDate = d);
                        _fetchLogs();
                      }
                    },
                  ),
                  if (_startDate != null || _endDate != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _startDate = null;
                            _endDate = null;
                          });
                          _fetchLogs();
                        },
                        icon: const Icon(Icons.clear_all, size: 18, color: Colors.white),
                        label: const Text('Limpiar', style: TextStyle(color: Colors.white)),
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        _buildChartCard(theme),
        Expanded(
          child: _isLoading 
            ? Center(
                child: Image.asset(
                  'assets/sisol_loader.gif',
                  width: 150,
                  errorBuilder: (context, error, stackTrace) => const CircularProgressIndicator(),
                  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                      frame == null ? const CircularProgressIndicator() : child,
                ),
              )
            : _logs.isEmpty 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text('No hay logs registrados aún', style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : isDesktop
                ? _buildDesktopTable(theme)
                : _buildMobileList(theme),
        ),
      ],
    );
  }
  Widget _buildChartCard(ThemeData theme) {
    if (_dailyLogins.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey[200]!),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [theme.colorScheme.primary, theme.colorScheme.primary.withOpacity(0.85)],
            ),
          ),
          child: _buildChartSection(theme),
        ),
      ),
    );
  }

  Widget _buildChartSection(ThemeData theme) {
    if (_dailyLogins.isEmpty) return const SizedBox.shrink();

    final maxLogins = _dailyLogins.values.isEmpty ? 0 : _dailyLogins.values.reduce((a, b) => a > b ? a : b);
    final totalLogins = _dailyLogins.values.fold(0, (sum, val) => sum + val);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.assessment_outlined, size: 18, color: Colors.white70),
            const SizedBox(width: 8),
            Text(
              'Inicios de Sesión (Última Semana)',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Total: $totalLogins',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: _dailyLogins.entries.map((entry) {
              final dayName = _getDayName(entry.key);
              final count = entry.value;
              final heightFactor = maxLogins == 0 ? 0.0 : count / maxLogins;
              
              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      count.toString(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: count > 0 ? Colors.white : Colors.white24,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 80 * heightFactor + 4, // Min height of 4
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: count > 0 
                            ? [Colors.white, Colors.white.withOpacity(0.7)]
                            : [Colors.white24, Colors.white12],
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        boxShadow: count > 0 ? [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ] : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dayName,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                        fontWeight: entry.key.day == DateTime.now().day ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _getDayName(DateTime date) {
    const days = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
    return days[date.weekday % 7];
  }

  Icon _getIconForAction(String action, ThemeData theme) {
    switch (action) {
      case 'CREACIÓN':
        return Icon(Icons.person_add_alt_1, color: theme.colorScheme.secondary);
      case 'ELIMINACIÓN':
        return const Icon(Icons.person_remove_alt_1, color: Colors.redAccent);
      case 'REGISTRO':
        return Icon(Icons.app_registration, color: theme.colorScheme.primary);
      case 'INICIO DE SESIÓN':
        return const Icon(Icons.login_rounded, color: Colors.green);
      case 'CIERRE DE SESIÓN':
        return const Icon(Icons.logout_rounded, color: Colors.orange);
      default:
        return const Icon(Icons.history, color: Colors.blueGrey);
    }
  }

  String _formatTime(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} $hour:$minute';
  }

  String _formatDateOnly(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Widget _buildDateSelector({required String label, required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF344092)),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  String _getProfileName(Map<String, dynamic> log) {
    final profile = log['profiles'];
    if (profile == null) return '---';
    final nombre = '${profile['nombre'] ?? ''} ${profile['paterno'] ?? ''}'.trim();
    return nombre.isEmpty ? '---' : nombre;
  }

  String _getProfileEmail(Map<String, dynamic> log) {
    final profile = log['profiles'];
    if (profile == null) return '---';
    return profile['email'] ?? '---';
  }

  Widget _buildMobileList(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _fetchLogs,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _logs.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          final log = _logs[index];
          final action = log['action_type'] ?? 'ACCIÓN';
          final target = log['target_info'] ?? '---';
          final date = DateTime.parse(log['created_at']).toLocal();
          
          return ListTile(
            leading: _getIconForAction(action, theme),
            title: Text(
              action,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            subtitle: Text(
              target,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Text(
              _formatTime(date),
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesktopTable(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: double.infinity,
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Row(
                  children: [
                    const Text('Registros de Actividad', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('${_logs.length} registros', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                  ],
                ),
              ),
              const Divider(height: 1),
              Theme(
                data: theme.copyWith(cardColor: Colors.transparent),
                child: PaginatedDataTable(
                  columns: const [
                    DataColumn(label: Text('Nombre', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Acción', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Detalle', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Fecha', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  source: _LogsDataSource(
                    items: _logs,
                    theme: theme,
                    formatTime: _formatTime,
                    getStatusColor: _getStatusColor,
                    getIconForAction: _getIconForAction,
                    getProfileName: _getProfileName,
                    getProfileEmail: _getProfileEmail,
                  ),
                  rowsPerPage: _logs.isEmpty ? 1 : (_logs.length > 10 ? 10 : _logs.length),
                  showCheckboxColumn: false,
                  horizontalMargin: 16,
                  columnSpacing: 16,
                  dataRowMinHeight: 48,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'APROBADA': return Colors.green;
      case 'CANCELADA': return Colors.red;
      default: return Colors.orange;
    }
  }
}

class _LogsDataSource extends DataTableSource {
  final List<Map<String, dynamic>> items;
  final ThemeData theme;
  final String Function(DateTime) formatTime;
  final Color Function(String) getStatusColor;
  final Icon Function(String, ThemeData) getIconForAction;
  final String Function(Map<String, dynamic>) getProfileName;
  final String Function(Map<String, dynamic>) getProfileEmail;

  _LogsDataSource({
    required this.items,
    required this.theme,
    required this.formatTime,
    required this.getStatusColor,
    required this.getIconForAction,
    required this.getProfileName,
    required this.getProfileEmail,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= items.length) return null;
    final log = items[index];
    final action = log['action_type'] ?? 'ACCIÓN';
    final target = log['target_info'] ?? '---';
    final date = DateTime.parse(log['created_at']).toLocal();
    final nombre = getProfileName(log);
    final email = getProfileEmail(log);

    Color actionColor;
    switch (action) {
      case 'INICIO DE SESIÓN': actionColor = Colors.green; break;
      case 'CIERRE DE SESIÓN': actionColor = Colors.orange; break;
      case 'CREACIÓN': actionColor = theme.colorScheme.secondary; break;
      case 'ELIMINACIÓN': actionColor = Colors.redAccent; break;
      case 'REGISTRO': actionColor = theme.colorScheme.primary; break;
      default: actionColor = Colors.blueGrey;
    }

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(Text(nombre, style: const TextStyle(fontWeight: FontWeight.w500))),
        DataCell(Text(email, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: actionColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              action,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: actionColor),
            ),
          ),
        ),
        DataCell(Text(target, style: const TextStyle(fontSize: 12))),
        DataCell(Text(formatTime(date), style: TextStyle(fontSize: 12, color: Colors.grey[500]))),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => items.length;

  @override
  int get selectedRowCount => 0;
}
