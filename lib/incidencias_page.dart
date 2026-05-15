import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_service.dart';
import '../services/incidencias_pdf_service.dart';
import 'theme/si_theme.dart';


class IncidenciasPage extends StatefulWidget {
  const IncidenciasPage({super.key});

  @override
  State<IncidenciasPage> createState() => _IncidenciasPageState();
}

class _IncidenciasPageState extends State<IncidenciasPage> {
  List<Map<String, dynamic>> _incidencias = [];
  List<Map<String, dynamic>> _allIncidencias =
      []; // all PENDIENTE for admin view
  bool _isLoading = true;
  bool _antiguedadExpanded = false; // manual expand state for mobile card
  String? _userRole;
  String? _userFullName;
  DateTime? _fechaIngreso;
  DateTime? _fechaReingreso;
  Map<String, dynamic>? _selectedUserProfile; // To store the full profile for PDF generation


  List<Map<String, dynamic>> _adminUserList = [];
  String? _selectedUserId;

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

  Widget _buildControls(SiColors c) {
    return _buildGlassPill(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_userRole == 'admin' && _adminUserList.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              decoration: BoxDecoration(
                color: c.hover,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedUserId,
                  isDense: true,
                  icon: Icon(Icons.keyboard_arrow_down,
                      color: c.ink, size: 20),
                  items: _adminUserList.map((user) {
                    final name =
                        '${user['nombre']} ${user['paterno']} ${user['materno'] ?? ''}'
                            .trim();
                    return DropdownMenuItem(
                      value: user['id'] as String,
                      child: Text(name.isEmpty ? 'Usuario' : name,
                          style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: _onUserSelected,
                ),
              ),
            ),
            const VerticalDivider(
                width: 1, thickness: 1, indent: 8, endIndent: 8),
          ],
          GestureDetector(
            onTap: () => _showIncidenciaForm(),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(Icons.add, size: 22, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // Fetch role and name
      final profile = await Supabase.instance.client
          .from('profiles')
          .select(
              '*, role, nombre, paterno, materno, fecha_ingreso, fecha_reingreso, area, ubicacion, puesto, jefe_inmediato, foto_url, numero_empleado')
          .eq('id', user.id)
          .maybeSingle();

      if (profile != null) {
        final fullName = (profile['nombre'] != null)
            ? '${profile['nombre']} ${profile['paterno']} ${profile['materno'] ?? ''}'
                .trim()
            : user.email ?? 'Usuario';

        if (mounted) {
          setState(() {
            _userRole = profile['role'];
            _userFullName = fullName;
            _fechaIngreso = profile['fecha_ingreso'] != null
                ? DateTime.tryParse(profile['fecha_ingreso'])
                : null;
            _fechaReingreso = profile['fecha_reingreso'] != null
                ? DateTime.tryParse(profile['fecha_reingreso'])
                : null;
            _selectedUserId = user.id;
            _selectedUserProfile = profile;
          });

          if (_userRole == 'admin') {
            await _fetchAdminUserList();
          }
        }
      }
      _fetchIncidencias();
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    }
  }

  Future<void> _fetchAdminUserList() async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select(
              '*, id, nombre, paterno, materno, role, fecha_ingreso, fecha_reingreso, area, ubicacion, puesto, jefe_inmediato, foto_url, numero_empleado')
          .eq('status_sys', 'ACTIVO')
          .order('nombre', ascending: true);

      if (mounted) {
        setState(() {
          _adminUserList = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching user list: $e');
    }
  }

  void _onUserSelected(String? newUserId) {
    if (newUserId == null || newUserId == _selectedUserId) return;

    final selectedProfile = _adminUserList
        .firstWhere((p) => p['id'] == newUserId, orElse: () => {});
    if (selectedProfile.isEmpty) return;

    setState(() {
      _selectedUserId = newUserId;
      _userFullName = (selectedProfile['nombre'] != null)
          ? '${selectedProfile['nombre']} ${selectedProfile['paterno']} ${selectedProfile['materno'] ?? ''}'
              .trim()
          : 'Usuario';
      _fechaIngreso = selectedProfile['fecha_ingreso'] != null
          ? DateTime.tryParse(selectedProfile['fecha_ingreso'])
          : null;
      _fechaReingreso = selectedProfile['fecha_reingreso'] != null
          ? DateTime.tryParse(selectedProfile['fecha_reingreso'])
          : null;
      _isLoading = true; // Show loading while fetching their incidencias
      _selectedUserProfile = selectedProfile;
    });

    _fetchIncidencias();
  }

  /// Calcula la antigüedad a partir de la fecha efectiva (reingreso si existe, sino ingreso)
  String _calcAntiguedad() {
    final base = _fechaReingreso ?? _fechaIngreso;
    if (base == null) return 'Sin fecha registrada';
    final now = DateTime.now();
    int years = now.year - base.year;
    int months = now.month - base.month;
    int days = now.day - base.day;
    if (days < 0) {
      months--;
    }
    if (months < 0) {
      years--;
      months += 12;
    }
    final parts = <String>[];
    if (years > 0) parts.add('$years año${years > 1 ? 's' : ''}');
    if (months > 0) parts.add('$months mes${months > 1 ? 'es' : ''}');
    if (parts.isEmpty) parts.add('Menos de un mes');
    return parts.join(' y ');
  }

  /// Años completos de antigüedad
  int _calcYears() {
    final base = _fechaReingreso ?? _fechaIngreso;
    if (base == null) return 0;
    final now = DateTime.now();
    int years = now.year - base.year;
    if (now.month < base.month ||
        (now.month == base.month && now.day < base.day)) years--;
    return years < 0 ? 0 : years;
  }


  /// Devuelve el índice (0-based) de la fila de la tabla que corresponde a los años del usuario
  int _getRowIndex(int years) {
    if (years <= 0) return -1;
    if (years == 1) return 0;
    if (years == 2) return 1;
    if (years == 3) return 2;
    if (years == 4) return 3;
    if (years == 5) return 4;
    if (years <= 10) return 5;
    if (years <= 15) return 6;
    if (years <= 20) return 7;
    if (years <= 25) return 8;
    if (years <= 30) return 9;
    return 10; // 31-35+
  }

  Widget _buildLeyesVacacionesTable() {
    final theme = Theme.of(context);
    final c = SiColors.of(context);
    const rows = [
      ['1 año', '12'],
      ['2 años', '14'],
      ['3 años', '16'],
      ['4 años', '18'],
      ['5 años', '20'],
      ['6 a 10 años', '22'],
      ['11 a 15 años', '24'],
      ['16 a 20 años', '26'],
      ['21 a 25 años', '28'],
      ['26 a 30 años', '30'],
      ['31 a 35 años', '32'],
    ];

    final years = _calcYears();
    final highlightIdx = _getRowIndex(years);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(1),
        },
        children: [
          // Header
          TableRow(
            decoration: BoxDecoration(color: c.hover),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text('Antigüedad',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text('Días',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          // Data rows
          for (var i = 0; i < rows.length; i++)
            TableRow(
              decoration: BoxDecoration(
                color: i == highlightIdx
                    ? theme.colorScheme.secondary.withOpacity(0.18)
                    : (i.isEven ? c.panel : c.bg),
              ),
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    rows[i][0],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == highlightIdx
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: i == highlightIdx
                          ? theme.colorScheme.secondary
                          : null,
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    rows[i][1],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == highlightIdx
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: i == highlightIdx
                          ? theme.colorScheme.secondary
                          : null,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Tarjeta de antigüedad (Contenido interno)
  Widget _buildAntiguedadCardContent({
    required ThemeData theme,
    required String label,
    required String dateStr,
    bool isDesktop = false,
    bool expanded = false,
    Widget? table,
  }) {
    final c = SiColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.secondary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_outlined,
                  color: theme.colorScheme.secondary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style:
                            TextStyle(fontSize: 11, color: c.ink3)),
                    Text(_calcAntiguedad(),
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.secondary)),
                    Text('Desde: $dateStr',
                        style:
                            TextStyle(fontSize: 11, color: c.ink3)),
                  ],
                ),
              ),
              if (!isDesktop)
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(Icons.expand_more,
                      color: theme.colorScheme.secondary.withOpacity(0.6)),
                ),
            ],
          ),
          if (!isDesktop && expanded && table != null) ...[
            const SizedBox(height: 8),
            table,
          ],
        ],
      ),
    );
  }

  Widget _buildMissingDateFallback({bool isDesktop = false}) {
    return Container(
      margin: !isDesktop
          ? const EdgeInsets.fromLTRB(16, 12, 16, 4)
          : EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Fecha de ingreso no registrada. Contacta a un administrador para configurar tu perfil.',
              style: TextStyle(fontSize: 13, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  /// Antigüedad para Móvil (Hamburguesa/ExpansionTile)
  Widget _buildAntiguedadMobile() {
    final base = _fechaReingreso ?? _fechaIngreso;
    if (base == null) return _buildMissingDateFallback(isDesktop: false);
    final theme = Theme.of(context);
    final label =
        _fechaReingreso != null ? 'Antigüedad (Reingreso)' : 'Antigüedad';
    final dateStr =
        '${base.day.toString().padLeft(2, '0')}/${base.month.toString().padLeft(2, '0')}/${base.year}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: GestureDetector(
        onTap: () => setState(() => _antiguedadExpanded = !_antiguedadExpanded),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: SizedBox(
            width: double.infinity,
            child: _buildAntiguedadCardContent(
              theme: theme,
              label: label,
              dateStr: dateStr,
              isDesktop: false,
              expanded: _antiguedadExpanded,
              table: _buildLeyesVacacionesTable(),
            ),
          ),
        ),
      ),
    );
  }

  /// Antigüedad para Escritorio (Inline)
  Widget _buildAntiguedadDesktop() {
    final base = _fechaReingreso ?? _fechaIngreso;
    if (base == null) return _buildMissingDateFallback(isDesktop: true);
    final theme = Theme.of(context);
    final label =
        _fechaReingreso != null ? 'Antigüedad (Reingreso)' : 'Antigüedad';
    final dateStr =
        '${base.day.toString().padLeft(2, '0')}/${base.month.toString().padLeft(2, '0')}/${base.year}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAntiguedadCardContent(
            theme: theme, label: label, dateStr: dateStr, isDesktop: true),
        const SizedBox(height: 12),
        _buildLeyesVacacionesTable(),
      ],
    );
  }

  /// Días de vacaciones según nueva ley 2023 y años de servicio
  int _getDaysByYears(int years) {
    if (years == 1) return 12;
    if (years == 2) return 14;
    if (years == 3) return 16;
    if (years == 4) return 18;
    if (years == 5) return 20;
    if (years <= 10) return 22;
    if (years <= 15) return 24;
    if (years <= 20) return 26;
    if (years <= 25) return 28;
    if (years <= 30) return 30;
    return 32;
  }

  /// Tabla de historial de vacaciones por periodo
  Widget _buildHistorialVacaciones() {
    final base = _fechaReingreso ?? _fechaIngreso;
    if (base == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final theme = Theme.of(context);
    final c = SiColors.of(context);
    final completedYears = _calcYears();

    final String targetUserId = _selectedUserId ?? '';
    String normalizePeriod(String? p) =>
        (p ?? '').replaceAll(RegExp(r'\D'), '');

    final usedDaysMap = <String, int>{};
    for (final inc in _incidencias) {
      if (inc['usuario_id'] == targetUserId && inc['status'] == 'APROBADA') {
        final normP = normalizePeriod(inc['periodo'] as String?);
        final dias = inc['dias'] as int? ?? 0;
        if (normP.isNotEmpty) {
          usedDaysMap[normP] = (usedDaysMap[normP] ?? 0) + dias;
        }
      }
    }

    // Fórmula: (días_ley / 365) × (fecha_actual − inicio_periodo + 1)
    // periodEnd = anniversary date (when year y completes)
    // periodStart = one year before = DateTime(base.year + y - 1, ...)
    double _calcProporcionalDouble(
        int days, DateTime periodStart, DateTime periodEnd) {
      if (periodStart.isAfter(now)) {
        // Future period: show full entitlement
        return days.toDouble();
      } else if (periodEnd.isBefore(now) || periodEnd.isAtSameMomentAs(now)) {
        // Past completed period: full entitlement
        return days.toDouble();
      } else {
        // Current in-progress: (fecha_actual - inicio_periodo + 1)
        final elapsed = now.difference(periodStart).inDays + 1;
        return (days / 365) * elapsed;
      }
    }

    final tableRows = <Map<String, dynamic>>[];
    for (int y = 1; y <= completedYears + 1; y++) {
      final periodEnd =
          DateTime(base.year + y, base.month, base.day); // anniversary end
      final periodStart = DateTime(
          base.year + y - 1, base.month, base.day); // anniversary start
      final periodLabel = '${periodStart.year} - ${periodEnd.year}';
      final normLabel = normalizePeriod(periodLabel);

      final int days;
      if (periodStart.year >= 2023) {
        days = _getDaysByYears(y);
      } else {
        // Ley anterior: depende de la fecha de ingreso del colaborador
        final cutoff = DateTime(2017, 5, 2);
        if (base.isBefore(cutoff)) {
          // Ingreso antes de 2017-05-02: empieza en 6, máximo 14
          days = (6 + (y - 1) * 2).clamp(0, 14);
        } else {
          // Ingreso en o después de 2017-05-02: empieza en 8, máximo 16
          days = (8 + (y - 1) * 2).clamp(0, 16);
        }
      }

      final isCurrent = y == completedYears;
      final isUpcoming = periodEnd.isAfter(now) && periodStart.isAfter(now);
      final daysRequested = usedDaysMap[normLabel] ?? 0;
      final proporcional =
          _calcProporcionalDouble(days, periodStart, periodEnd);
      final saldo = proporcional - daysRequested;

      tableRows.add({
        'periodo': periodLabel,
        'days': days,
        'proporcional': proporcional,
        'requested': daysRequested,
        'saldo': saldo,
        'isCurrent': isCurrent,
        'isUpcoming': isUpcoming,
      });
    }

    if (tableRows.isEmpty) return const SizedBox.shrink();

    // Grand totals
    final totalProp =
        tableRows.fold<double>(0, (s, r) => s + (r['proporcional'] as double));
    final totalReq =
        tableRows.fold<int>(0, (s, r) => s + (r['requested'] as int));
    final totalSaldo =
        tableRows.fold<double>(0, (s, r) => s + (r['saldo'] as double));

    // Column widths
    const double wProp = 95;
    const double wPedidos = 95;
    const double wSaldo = 100;
    const double wLey = 60;

    Widget _cell(String text,
        {Color? color,
        FontWeight? weight,
        TextAlign align = TextAlign.center,
        double? width}) {
      final w = Text(text,
          textAlign: align,
          style: TextStyle(fontSize: 12, fontWeight: weight, color: color));
      return width != null
          ? SizedBox(
              width: width,
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: w))
          : Expanded(
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: w));
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title (Fixed)
          Container(
            color: c.hover,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.calendar_month_outlined,
                    size: 18, color: theme.colorScheme.secondary),
                const SizedBox(width: 8),
                Text('Historial de Vacaciones',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: theme.colorScheme.secondary)),
              ],
            ),
          ),
          // Scrollable Table Content
          LayoutBuilder(
            builder: (context, tableConstraints) {
              final double tableWidth = tableConstraints.maxWidth > 520
                  ? tableConstraints.maxWidth
                  : 520;

              return Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2), // Periodo gets more space
                        1: FixedColumnWidth(wLey),
                        2: FixedColumnWidth(wProp),
                        3: FixedColumnWidth(wPedidos),
                        4: FixedColumnWidth(wSaldo),
                      },
                      children: [
                        // Header row
                        TableRow(
                          decoration: BoxDecoration(color: c.hover),
                          children: [
                            _cellTable('Período',
                                weight: FontWeight.bold, align: TextAlign.left),
                            _cellTable('Dias', weight: FontWeight.bold),
                            _cellTable('Proporcional', weight: FontWeight.bold),
                            _cellTable('Solicitados', weight: FontWeight.bold),
                            _cellTable('Actual', weight: FontWeight.bold),
                          ],
                        ),
                        // Data rows
                        ...tableRows.asMap().entries.map((entry) {
                          final i = entry.key;
                          final row = entry.value;
                          final isCurrent = row['isCurrent'] as bool;
                          final isUpcoming = row['isUpcoming'] as bool;

                          final Color? textColor = isCurrent
                              ? theme.colorScheme.secondary
                              : (isUpcoming ? Colors.orange[700] : null);
                          final double saldo = row['saldo'] as double;
                          final double proporcional =
                              row['proporcional'] as double;
                          final FontWeight? weight =
                              isCurrent ? FontWeight.bold : null;
                          final Color saldoColor = saldo < 0
                              ? Colors.red
                              : (saldo == 0 ? Colors.grey : Colors.green[700]!);

                          Color bgColor;
                          if (isCurrent)
                            bgColor =
                                theme.colorScheme.secondary.withOpacity(0.15);
                          else if (isUpcoming)
                            bgColor = Colors.orange.withOpacity(0.07);
                          else
                            bgColor = i.isEven ? c.panel : c.bg;

                          return TableRow(
                            decoration: BoxDecoration(color: bgColor),
                            children: [
                              _cellTable(row['periodo'] as String,
                                  color: textColor,
                                  weight: weight,
                                  align: TextAlign.left),
                              _cellTable('${row['days']}',
                                  color: textColor, weight: weight),
                              _cellTable('${proporcional.toInt()}',
                                  color: textColor, weight: weight),
                              _cellTable(
                                  row['requested'] > 0
                                      ? '${row['requested']}'
                                      : '',
                                  color: textColor,
                                  weight: weight),
                              _cellTable(
                                  proporcional == 0 && row['requested'] == 0
                                      ? ''
                                      : '${saldo.toInt()}',
                                  color: saldoColor,
                                  weight: FontWeight.bold),
                            ],
                          );
                        }),
                        // Grand Total row
                        TableRow(
                          decoration: BoxDecoration(color: c.hover),
                          children: [
                            _cellTable('Saldo Actual Total',
                                weight: FontWeight.bold, align: TextAlign.left),
                            _cellTable(''),
                            _cellTable(''),
                            _cellTable(''),
                            _cellTable('${totalSaldo.toInt()} días.',
                                weight: FontWeight.bold,
                                color: totalSaldo < 0
                                    ? Colors.red
                                    : Colors.green[700]),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Helper for Table cells
  Widget _cellTable(String text,
      {Color? color,
      FontWeight? weight,
      TextAlign align = TextAlign.center}) {
    final c = SiColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          color: color ?? c.ink,
          fontWeight: weight,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _fetchIncidencias() async {
    setState(() => _isLoading = true);
    try {
      // Fetch incidencias for the selected (or current) user
      final response = await Supabase.instance.client
          .from('incidencias')
          .select()
          .eq('usuario_id',
              _selectedUserId ?? Supabase.instance.client.auth.currentUser!.id)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _incidencias = List<Map<String, dynamic>>.from(response)
            ..sort((a, b) {
              const order = {'PENDIENTE': 0, 'APROBADA': 1, 'CANCELADA': 2};
              final aOrder = order[a['status']] ?? 99;
              final bOrder = order[b['status']] ?? 99;
              if (aOrder != bOrder) return aOrder.compareTo(bOrder);
              return (b['created_at'] as String)
                  .compareTo(a['created_at'] as String);
            });
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching incidencias: $e');
      if (mounted) setState(() => _isLoading = false);
    }

    // Separately fetch ALL pending incidencias for admin view (independent query)
    if (_userRole == 'admin') {
      try {
        final pendingResp = await Supabase.instance.client
            .from('incidencias')
            .select()
            .eq('status', 'PENDIENTE')
            .order('created_at', ascending: false);

        final pending = List<Map<String, dynamic>>.from(pendingResp);

        // Enrich with profile names from the already-loaded _adminUserList
        for (final inc in pending) {
          final uid = inc['usuario_id'] as String?;
          final profile = _adminUserList.firstWhere(
            (u) => u['id'] == uid,
            orElse: () => {},
          );
          inc['profiles'] = profile.isNotEmpty ? profile : null;
        }

        if (mounted) setState(() => _allIncidencias = pending);
      } catch (e) {
        debugPrint('Error fetching pending incidencias: $e');
      }
    }
  }

  void _showIncidenciaForm({Map<String, dynamic>? incidencia}) {
    final isEditing = incidencia != null;
    final status = incidencia?['status'] ?? 'PENDIENTE';

    // Si no es admin y el estatus no es PENDIENTE, no se puede editar
    if (isEditing && _userRole != 'admin' && status != 'PENDIENTE') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Solo se pueden editar incidencias en estado PENDIENTE')),
      );
      return;
    }

    // Verificar antigüedad mínima de 1 año (solo para crear, no para editar, y no para admin)
    if (!isEditing && _userRole != 'admin') {
      final base = _fechaReingreso ?? _fechaIngreso;
      if (base != null) {
        final now = DateTime.now();
        final years = now.year -
            base.year -
            ((now.month < base.month ||
                    (now.month == base.month && now.day < base.day))
                ? 1
                : 0);
        if (years < 1) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.info_outline,
                  color: Colors.orange, size: 36),
              title: const Text('Antigüedad insuficiente',
                  textAlign: TextAlign.center),
              content: const Text(
                'Recuerda que partiendo de tu fecha de ingreso o reingreso, debes de cumplir el año de servicios para poder ser válidas tus vacaciones.',
                textAlign: TextAlign.center,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
          return;
        }
      }
    }

    final periodController =
        TextEditingController(text: incidencia?['periodo'] ?? '2025 – 2026');
    final diasController =
        TextEditingController(text: incidencia?['dias']?.toString() ?? '');
    DateTime fechaInicio = incidencia != null
        ? DateTime.parse(incidencia['fecha_inicio'])
        : DateTime.now();
    DateTime fechaFin = incidencia != null
        ? DateTime.parse(incidencia['fecha_fin'])
        : DateTime.now().add(const Duration(days: 1));
    DateTime fechaRegreso = incidencia != null
        ? DateTime.parse(incidencia['fecha_regreso'])
        : DateTime.now().add(const Duration(days: 2));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final c = SiColors.of(context);
          return Container(
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 40,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancelar',
                          style: TextStyle(fontSize: 16, color: c.ink3)),
                    ),
                    Text(
                      isEditing ? 'Editar Incidencia' : 'Nueva Incidencia',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: c.ink),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (diasController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Completa todos los campos')),
                          );
                          return;
                        }

                        final data = {
                          if (!isEditing) 'nombre_usuario': _userFullName,
                          'periodo': periodController.text,
                          'dias': int.parse(diasController.text),
                          'fecha_inicio': fechaInicio.toIso8601String(),
                          'fecha_fin': fechaFin.toIso8601String(),
                          'fecha_regreso': fechaRegreso.toIso8601String(),
                          if (!isEditing)
                            'usuario_id': _selectedUserId ??
                                Supabase.instance.client.auth.currentUser!.id,
                        };

                        try {
                          if (isEditing) {
                            await Supabase.instance.client
                                .from('incidencias')
                                .update(data)
                                .eq('id', incidencia['id']);
                          } else {
                            await Supabase.instance.client
                                .from('incidencias')
                                .insert(data);
                            await NotificationService.send(
                              title: 'Nueva Incidencia',
                              message:
                                  '$_userFullName ha creado una nueva petición.',
                              type: 'new_incidencia',
                            );
                          }
                          if (mounted) {
                            Navigator.pop(context);
                            _fetchIncidencias();
                          }
                        } catch (e) {
                          debugPrint('Error saving incidencia: $e');
                        }
                      },
                      child: Text(
                        'Guardar',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: c.brand),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  isEditing
                      ? (incidencia['nombre_usuario'] ?? '...')
                      : (_userFullName ?? '...'),
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16, color: c.ink),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  value: periodController.text,
                  items: ['2024 – 2025', '2025 – 2026']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (val) => periodController.text = val!,
                  decoration: const InputDecoration(
                    labelText: 'Periodo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: diasController,
                  keyboardType: TextInputType.number,
                  maxLength: 2,
                  decoration: const InputDecoration(
                    labelText: 'Días',
                    border: OutlineInputBorder(),
                    counterText: "",
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildDatePicker('Fecha Inicio', fechaInicio,
                          (d) => setModalState(() => fechaInicio = d)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDatePicker('Fecha Final', fechaFin,
                          (d) => setModalState(() => fechaFin = d)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDatePicker('Fecha Regreso', fechaRegreso,
                    (d) => setModalState(() => fechaRegreso = d)),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
        },
      ),
    );
  }

  Widget _buildDatePicker(
      String label, DateTime current, Function(DateTime) onPick) {
    return TextField(
      readOnly: true,
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: current,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (d != null) onPick(d);
      },
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.calendar_today, size: 18),
      ),
      controller: TextEditingController(
        text:
            '${current.day.toString().padLeft(2, '0')}/${current.month.toString().padLeft(2, '0')}/${current.year}',
      ),
    );
  }

  Widget _buildMobileList(ThemeData theme) {
    final c = SiColors.of(context);
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: _incidencias.length,
      itemBuilder: (context, index) {
        final inc = _incidencias[index];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: c.line),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            title: Text(
              inc['periodo'] ?? '---',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
                'Días: ${inc['dias']} | Creado: ${_formatDate(inc['created_at'])}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor(inc['status']).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    inc['status'],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(inc['status']),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (val) async {
                    if (val == 'PDF') {
                      if (_selectedUserProfile != null) {
                        IncidenciasPdfService.generateVacationRequest(
                            _selectedUserProfile!, inc);
                      }
                    } else if (val == 'EDIT') {
                      _showIncidenciaForm(incidencia: inc);
                    } else if (_userRole == 'admin') {
                      await Supabase.instance.client
                          .from('incidencias')
                          .update({'status': val}).eq('id', inc['id']);
                      await NotificationService.send(
                        title: 'Tu incidencia fue $val',
                        message: 'El estado de tu petición ha cambiado a $val.',
                        userId: inc['usuario_id'],
                        type: 'incidencia_status',
                      );
                      _fetchIncidencias();
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                        value: 'PDF',
                        child: ListTile(
                            leading: Icon(Icons.picture_as_pdf_outlined),
                            title: Text('Descargar PDF'),
                            dense: true)),
                    if (_userRole == 'admin' || inc['status'] == 'PENDIENTE')
                      const PopupMenuItem(
                          value: 'EDIT',
                          child: ListTile(
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Editar'),
                              dense: true)),
                    if (_userRole == 'admin') ...[
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                          value: 'APROBADA', child: Text('Aprobar')),
                      const PopupMenuItem(
                          value: 'CANCELADA', child: Text('Cancelar')),
                      const PopupMenuItem(
                          value: 'PENDIENTE', child: Text('Pendiente')),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _buildPendingTable(SiColors c) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: SiRadius.rLg,
        side: BorderSide(color: Colors.orange.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: Colors.orange.withOpacity(0.05),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.pending_actions_rounded,
                    color: Colors.orange[700], size: 22),
                const SizedBox(width: 12),
                Text(
                  'Solicitudes Pendientes',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.orange[900]),
                ),
                const Spacer(),
                if (_allIncidencias.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange[700],
                      borderRadius: SiRadius.rPill,
                    ),
                    child: Text('${_allIncidencias.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_allIncidencias.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text('Sin solicitudes pendientes',
                    style: TextStyle(color: c.ink3)),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                          Colors.orange.withOpacity(0.07)),
                      columnSpacing: 20,
                      horizontalMargin: 16,
                      dataRowMinHeight: 40,
                      dataRowMaxHeight: 48,
                      columns: const [
                        DataColumn(
                            label: Text('Nombre',
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(
                            label: Text('Periodo',
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(
                            label: Text('Días',
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(
                            label: Text('Fecha Inicio',
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(
                            label: Text('Fecha Final',
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(
                            label: Text('Fecha Regreso',
                                style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(
                            label: Text('Estatus',
                                style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: _allIncidencias.map((inc) {
                        final profile =
                            inc['profiles'] as Map<String, dynamic>? ?? {};
                        final nombre =
                            '${profile['nombre'] ?? ''} ${profile['paterno'] ?? ''}'
                                .trim();
                        return DataRow(cells: [
                          DataCell(Text(nombre.isEmpty
                              ? inc['usuario_id']?.toString().substring(0, 8) ??
                                  '---'
                              : nombre)),
                          DataCell(Text(inc['periodo']?.toString() ?? '---')),
                          DataCell(Text(inc['dias']?.toString() ?? '---')),
                          DataCell(Text(inc['fecha_inicio'] != null
                              ? _formatDate(inc['fecha_inicio'])
                              : '---')),
                          DataCell(Text(inc['fecha_fin'] != null
                              ? _formatDate(inc['fecha_fin'])
                              : '---')),
                          DataCell(Text(inc['fecha_regreso'] != null
                              ? _formatDate(inc['fecha_regreso'])
                              : '---')),
                          DataCell(
                           PopupMenuButton<String>(
                              tooltip: 'Cambiar estatus',
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: Colors.orange.withOpacity(0.4),
                                      width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('PENDIENTE',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange[800])),
                                    const SizedBox(width: 4),
                                    Icon(Icons.arrow_drop_down,
                                        size: 14, color: Colors.orange[800]),
                                  ],
                                ),
                              ),
                              onSelected: (val) async {
                                if (val == 'PDF') {
                                  final uProfile = inc['profiles'] as Map<String, dynamic>? ?? {};
                                  if (uProfile.isNotEmpty) {
                                    IncidenciasPdfService.generateVacationRequest(uProfile, inc);
                                  }
                                  return;
                                }
                                await Supabase.instance.client
                                    .from('incidencias')
                                    .update({'status': val}).eq(
                                        'id', inc['id']);
                                await NotificationService.send(
                                  title: 'Tu incidencia fue $val',
                                  message:
                                      'El estado de tu petición ha cambiado a $val.',
                                  userId: inc['usuario_id'],
                                  type: 'incidencia_status',
                                );
                                _fetchIncidencias();
                              },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'PDF',
                                      child: ListTile(
                                          leading: Icon(Icons.picture_as_pdf_outlined),
                                          title: Text('Descargar PDF'),
                                          dense: true)),
                                  PopupMenuItem(
                                      value: 'APROBADA', child: Text('APROBADA')),
                                  PopupMenuItem(
                                      value: 'RECHAZADA',
                                      child: Text('RECHAZADA')),
                                ],
                            ),
                          ),
                        ]);
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopTable(SiColors c) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: SiRadius.rLg,
        side: BorderSide(color: c.line),
      ),
      child: Theme(
        data: theme.copyWith(cardColor: Colors.transparent),
        child: PaginatedDataTable(
          header: Row(
            children: [
              if (_userRole == 'admin' && _adminUserList.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: SizedBox(
                    height: 38,
                    child: _buildTableUserSelector(c),
                  ),
                ),
            ],
          ),
          actions: [
            SizedBox(
              height: 38,
              child: _buildTableAddButton(c),
            ),
          ],
          dataRowMaxHeight: 54,
          dataRowMinHeight: 54,
          columnSpacing: 20,
          horizontalMargin: 16,
          columns: [
            DataColumn(
                label: SizedBox(
                    width: screenWidth * 0.12,
                    child: Text('PERIODO',
                        style: TextStyle(
                            color: c.ink3,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 1)))),
            DataColumn(
                label: SizedBox(
                    width: screenWidth * 0.03,
                    child: Text('DÍAS',
                        style: TextStyle(
                            color: c.ink3,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 1)))),
            DataColumn(
                label: SizedBox(
                    width: screenWidth * 0.07,
                    child: Text('CREADO',
                        style: TextStyle(
                            color: c.ink3,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 1)))),
            DataColumn(
                label: SizedBox(
                    width: screenWidth * 0.07,
                    child: Text('FECHA INICIO',
                        style: TextStyle(
                            color: c.ink3,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 1)))),
            DataColumn(
                label: SizedBox(
                    width: screenWidth * 0.07,
                    child: Text('FECHA FIN',
                        style: TextStyle(
                            color: c.ink3,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 1)))),
            DataColumn(
                label: SizedBox(
                    width: screenWidth * 0.07,
                    child: Text('ESTATUS',
                        style: TextStyle(
                            color: c.ink3,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 1)))),
            DataColumn(
                label: SizedBox(
                    width: screenWidth * 0.04,
                    child: const SizedBox())), // Acciones
          ],
          source: _IncidenciasDataSource(
            items: _incidencias,
            theme: theme,
            isAdmin: _userRole == 'admin',
            userProfile: _selectedUserProfile,
            formatDate: _formatDate,
            siColors: c,
            getStatusColor: _getStatusColor,
            onEdit: (inc) => _showIncidenciaForm(incidencia: inc),
            onStatusChange: (inc, status) async {
              if (status == 'PDF') {
                if (_selectedUserProfile != null) {
                  IncidenciasPdfService.generateVacationRequest(
                      _selectedUserProfile!, inc);
                }
              } else {
                await Supabase.instance.client
                    .from('incidencias')
                    .update({'status': status}).eq('id', inc['id']);
                await NotificationService.send(
                  title: 'Tu incidencia fue $status',
                  message: 'El estado de tu petición ha cambiado a $status.',
                  userId: inc['usuario_id'],
                  type: 'incidencia_status',
                );
                _fetchIncidencias();
              }
            },
          ),
          rowsPerPage: _incidencias.isEmpty
              ? 1
              : (_incidencias.length > 5 ? 5 : _incidencias.length),
          showCheckboxColumn: false,
        ),
      ),
    );
  }

  Widget _buildTableUserSelector(SiColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedUserId,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: c.ink3, size: 20),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          style: TextStyle(fontSize: 13, color: c.ink),
          items: _adminUserList.map((user) {
            final name = '${user['nombre'] ?? ''} ${user['paterno'] ?? ''}'.trim();
            return DropdownMenuItem(
              value: user['id'] as String,
              child: Text(name.isEmpty ? 'Seleccionar Usuario' : name, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: _onUserSelected,
        ),
      ),
    );
  }

  Widget _buildTableAddButton(SiColors c) {
    final theme = Theme.of(context);
    return ElevatedButton.icon(
      onPressed: () => _showIncidenciaForm(),
      icon: const Icon(Icons.add, size: 16),
      label: const Text('Nuevo', style: TextStyle(fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    return Scaffold(
      backgroundColor: c.bg,
      body: _isLoading
          ? Center(
              child: Image.asset(
                'assets/sisol_loader.gif',
                width: 150,
                errorBuilder: (context, error, stackTrace) =>
                    const CircularProgressIndicator(),
              ),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: SiSpace.x6, vertical: SiSpace.x4),
              child: Column(
                children: [
                  // Admin Pending Section
                  if (_userRole == 'admin') ...[
                    _buildPendingTable(c),
                    SizedBox(height: SiSpace.x6),
                  ],

                  // Main Content Grid
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isDesktop = constraints.maxWidth > 1100;
                      if (isDesktop) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Main Table (50% width)
                            Expanded(
                              flex: 2,
                              child: _buildDesktopTable(c),
                            ),
                            SizedBox(width: SiSpace.x6),
                            // Historial (25% width)
                            Expanded(
                              flex: 1,
                              child: _buildHistorialVacaciones(),
                            ),
                            SizedBox(width: SiSpace.x6),
                            // Antigüedad (25% width)
                            Expanded(
                              flex: 1,
                              child: _buildAntiguedadDesktop(),
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            _buildAntiguedadMobile(),
                            SizedBox(height: SiSpace.x4),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: _buildHistorialVacaciones(),
                            ),
                            SizedBox(height: SiSpace.x6),
                            _incidencias.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.all(40),
                                    child:
                                        Text('No hay solicitudes registradas'),
                                  )
                                : _buildMobileList(Theme.of(context)),
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 80),
                ],
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

  String _formatDate(String iso) {

    final d = DateTime.parse(iso);
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _IncidenciasDataSource extends DataTableSource {
  final List<Map<String, dynamic>> items;
  final ThemeData theme;
  final bool isAdmin;
  final Map<String, dynamic>? userProfile;
  final String Function(String) formatDate;
  final SiColors siColors;

  final Color Function(String) getStatusColor;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>, String) onStatusChange;

  _IncidenciasDataSource({
    required this.items,
    required this.theme,
    required this.isAdmin,
    this.userProfile,
    required this.formatDate,
    required this.siColors,
    required this.getStatusColor,
    required this.onEdit,
    required this.onStatusChange,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= items.length) return null;
    final inc = items[index];

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(
          Text(inc['periodo'] ?? '---',
              style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        DataCell(Text('${inc['dias'] ?? '-'}')),
        DataCell(Text(formatDate(inc['created_at']))),
        DataCell(Text(inc['fecha_inicio'] != null
            ? formatDate(inc['fecha_inicio'])
            : '-')),
        DataCell(Text(
            inc['fecha_fin'] != null ? formatDate(inc['fecha_fin']) : '-')),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: getStatusColor(inc['status']).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  inc['status'],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: getStatusColor(inc['status']),
                  ),
                ),
              ),
            ],
          ),
        ),
        DataCell(
          Align(
            alignment: Alignment.centerRight,
            child: PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz, color: siColors.ink3),
            tooltip: 'Acciones',
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 4,
            onSelected: (val) {
              if (val == 'EDIT') {
                onEdit(inc);
              } else {
                onStatusChange(inc, val);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'PDF',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf_outlined,
                        size: 18, color: Colors.red[700]),
                    const SizedBox(width: 12),
                    const Text('Descargar PDF', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              if (isAdmin || inc['status'] == 'PENDIENTE')
                PopupMenuItem(
                  value: 'EDIT',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined,
                          size: 18, color: Colors.blue[700]),
                      const SizedBox(width: 12),
                      const Text('Editar', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              if (isAdmin) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'APROBADA',
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 18, color: Colors.green),
                      const SizedBox(width: 12),
                      const Text('Aprobar', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'CANCELADA',
                  child: Row(
                    children: [
                      const Icon(Icons.cancel_outlined,
                          size: 18, color: Colors.red),
                      const SizedBox(width: 12),
                      const Text('Cancelar', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
