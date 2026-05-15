import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

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
  Map<String, Map<String, dynamic>> _emailProfiles = {};
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<Map<String, dynamic>> get _filteredLogs {
    var result = List<Map<String, dynamic>>.from(_logs);
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((log) {
        final action = (log['action_type'] ?? '').toString().toLowerCase();
        final target = (log['target_info'] ?? '').toString().toLowerCase();
        final name = _getProfileName(log).toLowerCase();
        final email = _getProfileEmail(log).toLowerCase();
        
        return action.contains(query) || target.contains(query) || name.contains(query) || email.contains(query);
      }).toList();
    }
    return result;
  }

  Widget _buildGlassPill({required Widget child, EdgeInsetsGeometry? padding}) {
    final c = SiColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c.panel.withOpacity(0.85),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: c.line.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }

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
        final date =
            DateTime(oneWeekAgo.year, oneWeekAgo.month, oneWeekAgo.day + i);
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
      var query = Supabase.instance.client.from('system_logs').select();

      if (_startDate != null) {
        query = query.gte('created_at', _startDate!.toIso8601String());
      }
      if (_endDate != null) {
        // Add 23:59:59 to include the whole end day if using only dates
        final end = DateTime(
            _endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        query = query.lte('created_at', end.toIso8601String());
      }

      final data = await query.order('created_at', ascending: false).limit(100);

      setState(() {
        _logs = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });

      // Extract unique emails from target_info and fetch profiles
      final emails = <String>{};
      for (final log in _logs) {
        final target = (log['target_info'] ?? '') as String;
        final email = _extractEmail(target);
        if (email.isNotEmpty) emails.add(email);
      }
      if (emails.isNotEmpty) {
        try {
          final profiles = await Supabase.instance.client
              .from('profiles')
              .select('nombre, paterno, email')
              .inFilter('email', emails.toList());
          final map = <String, Map<String, dynamic>>{};
          for (final p in profiles) {
            final e = p['email'] as String?;
            if (e != null) map[e.toLowerCase()] = Map<String, dynamic>.from(p);
          }
          if (mounted) setState(() => _emailProfiles = map);
        } catch (e) {
          debugPrint('Error fetching profiles for logs: $e');
        }
      }
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
    final c = SiColors.of(context);

    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Column(
      children: [
        if (!isDesktop)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildGlassPill(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDateSelector(
                        label: _startDate == null
                            ? 'Desde'
                            : _formatDateOnly(_startDate!),
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
                        child: Icon(Icons.arrow_forward,
                            size: 14, color: Colors.grey),
                      ),
                      _buildDateSelector(
                        label: _endDate == null
                            ? 'Hasta'
                            : _formatDateOnly(_endDate!),
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
                          child: IconButton(
                            onPressed: () {
                              setState(() {
                                _startDate = null;
                                _endDate = null;
                              });
                              _fetchLogs();
                            },
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: 'Limpiar filtros',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        _buildChartCard(theme),
        Expanded(
          child: _isLoading
              ? Center(
                  child: Image.asset(
                    'assets/sisol_loader.gif',
                    width: 150,
                    errorBuilder: (context, error, stackTrace) =>
                        const CircularProgressIndicator(),
                    frameBuilder: (context, child, frame,
                            wasSynchronouslyLoaded) =>
                        frame == null
                            ? const CircularProgressIndicator()
                            : child,
                  ),
                )
              : _filteredLogs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_toggle_off,
                              size: 64, color: c.line2),
                          const SizedBox(height: 16),
                          Text('No hay logs registrados aún',
                              style: TextStyle(color: c.ink3)),
                        ],
                      ),
                    )
                  : isDesktop
                      ? _buildDesktopTable(theme, _filteredLogs)
                      : _buildMobileList(theme),
        ),
      ],
    );
  }

  Widget _buildChartCard(ThemeData theme) {
    if (_dailyLogins.isEmpty) return const SizedBox.shrink();
    final c = SiColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.line),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primary.withOpacity(0.85)
              ],
            ),
          ),
          child: _buildChartSection(theme),
        ),
      ),
    );
  }

  Widget _buildChartSection(ThemeData theme) {
    if (_dailyLogins.isEmpty) return const SizedBox.shrink();

    final maxLogins = _dailyLogins.values.isEmpty
        ? 0
        : _dailyLogins.values.reduce((a, b) => a > b ? a : b);
    final totalLogins = _dailyLogins.values.fold(0, (sum, val) => sum + val);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.assessment_outlined,
                size: 18, color: Colors.white70),
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
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6)),
                        boxShadow: count > 0
                            ? [
                                BoxShadow(
                                  color: theme.colorScheme.primary
                                      .withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dayName,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                        fontWeight: entry.key.day == DateTime.now().day
                            ? FontWeight.bold
                            : FontWeight.normal,
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

  Widget _buildDateSelector(
      {required String label,
      required IconData icon,
      required VoidCallback onTap}) {
    final c = SiColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c.brand),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.ink)),
          ],
        ),
      ),
    );
  }

  String _extractEmail(String targetInfo) {
    // target_info format: "Usuario: email@domain.com"
    if (targetInfo.startsWith('Usuario: ')) {
      return targetInfo.substring(9).trim().toLowerCase();
    }
    return '';
  }

  String _getProfileName(Map<String, dynamic> log) {
    final email = _extractEmail((log['target_info'] ?? '') as String);
    if (email.isEmpty) return '---';
    final profile = _emailProfiles[email];
    if (profile == null) return '---';
    final nombre =
        '${profile['nombre'] ?? ''} ${profile['paterno'] ?? ''}'.trim();
    return nombre.isEmpty ? '---' : nombre;
  }

  String _getProfileEmail(Map<String, dynamic> log) {
    final email = _extractEmail((log['target_info'] ?? '') as String);
    return email.isEmpty ? '---' : email;
  }

  Widget _buildMobileList(ThemeData theme) {
    final c = SiColors.of(context);
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
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: c.ink),
            ),
            subtitle: Text(
              target,
              style: TextStyle(fontSize: 12, color: c.ink2),
            ),
            trailing: Text(
              _formatTime(date),
              style: TextStyle(fontSize: 11, color: c.ink3),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesktopTable(ThemeData theme, List<Map<String, dynamic>> filteredLogs) {
    final c = SiColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: double.infinity,
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: c.line),
          ),
          child: PaginatedDataTable(
            dataRowMaxHeight: 54,
            dataRowMinHeight: 54,
            columnSpacing: 40,
            horizontalMargin: 24,
            header: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 350),
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Buscar en logs...',
                        hintStyle: TextStyle(color: c.ink3, fontSize: 13),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.line)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.line)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.brand)),
                        filled: true,
                        fillColor: c.panel,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      ),
                      style: TextStyle(fontSize: 13, color: c.ink),
                      onChanged: (value) => setState(() => _searchQuery = value),
                    ),
                  ),
                ),
                _buildDateSelector(
                  label: _startDate == null ? 'Desde' : _formatDateOnly(_startDate!),
                  icon: Icons.calendar_today,
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: _startDate ?? DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime.now());
                    if (d != null) { setState(() => _startDate = d); _fetchLogs(); }
                  },
                ),
                _buildDateSelector(
                  label: _endDate == null ? 'Hasta' : _formatDateOnly(_endDate!),
                  icon: Icons.event,
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: _endDate ?? DateTime.now(), firstDate: _startDate ?? DateTime(2024), lastDate: DateTime.now());
                    if (d != null) { setState(() => _endDate = d); _fetchLogs(); }
                  },
                ),
                if (_startDate != null || _endDate != null)
                  SizedBox(
                    height: 38,
                    child: IconButton(
                      onPressed: () { setState(() { _startDate = null; _endDate = null; }); _fetchLogs(); },
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'Limpiar filtros',
                    ),
                  ),
              ],
            ),
            columns: [
              DataColumn(label: SizedBox(width: screenWidth * 0.1, child: Text('FECHA', style: TextStyle(color: c.ink3, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
              DataColumn(label: SizedBox(width: screenWidth * 0.25, child: Text('USUARIO', style: TextStyle(color: c.ink3, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
              DataColumn(label: SizedBox(width: screenWidth * 0.15, child: Text('ACCIÓN', style: TextStyle(color: c.ink3, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
              DataColumn(label: SizedBox(width: screenWidth * 0.25, child: Text('DETALLE', style: TextStyle(color: c.ink3, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
            ],
            source: _LogsDataSource(
              items: filteredLogs,
              theme: theme,
              siColors: c,
              formatTime: _formatTime,
              getProfileName: _getProfileName,
              getProfileEmail: _getProfileEmail,
              screenWidth: screenWidth,
            ),
            rowsPerPage: filteredLogs.isEmpty ? 1 : (filteredLogs.length > 10 ? 10 : filteredLogs.length),
            showCheckboxColumn: false,
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'APROBADA':
        return Colors.green;
      case 'CANCELADA':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }
}

class _LogsDataSource extends DataTableSource {
  final List<Map<String, dynamic>> items;
  final ThemeData theme;
  final SiColors siColors;
  final String Function(DateTime) formatTime;
  final String Function(Map<String, dynamic>) getProfileName;
  final String Function(Map<String, dynamic>) getProfileEmail;
  final double screenWidth;

  _LogsDataSource({
    required this.items,
    required this.theme,
    required this.siColors,
    required this.formatTime,
    required this.getProfileName,
    required this.getProfileEmail,
    required this.screenWidth,
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

    final parts = nombre.split(' ').where((e) => e.isNotEmpty).toList();
    final initials = parts.length > 1 ? '${parts[0][0]}${parts[1][0]}'.toUpperCase() : (parts.isNotEmpty ? parts[0][0].toUpperCase() : '?');

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
        DataCell(SizedBox(width: screenWidth * 0.1, child: Text(formatTime(date), style: TextStyle(fontSize: 12, color: siColors.ink3)))),
        DataCell(
          SizedBox(
            width: screenWidth * 0.25,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: siColors.brand.withOpacity(0.15),
                  child: Text(initials, style: TextStyle(color: siColors.brand, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(nombre.isEmpty ? 'Sin Nombre' : nombre, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: siColors.ink), overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(email, style: TextStyle(color: siColors.ink3, fontSize: 11), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: screenWidth * 0.15,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: actionColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: actionColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: actionColor, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(action, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: actionColor)),
                  ],
                ),
              ),
            ),
          ),
        ),
        DataCell(SizedBox(width: screenWidth * 0.25, child: Text(target, style: TextStyle(fontSize: 12, color: siColors.ink2), overflow: TextOverflow.ellipsis, maxLines: 2))),
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
