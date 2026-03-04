import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/notification_service.dart';
import 'widgets/page_header.dart';

class IncidenciasPage extends StatefulWidget {
  const IncidenciasPage({super.key});

  @override
  State<IncidenciasPage> createState() => _IncidenciasPageState();
}

class _IncidenciasPageState extends State<IncidenciasPage> {
  List<Map<String, dynamic>> _incidencias = [];
  List<Map<String, dynamic>> _allIncidencias = []; // all PENDIENTE for admin view
  bool _isLoading = true;
  bool _antiguedadExpanded = false; // manual expand state for mobile card
  String? _userRole;
  String? _userFullName;
  DateTime? _fechaIngreso;
  DateTime? _fechaReingreso;

  List<Map<String, dynamic>> _adminUserList = [];
  String? _selectedUserId;

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
          .select('role, nombre, paterno, materno, fecha_ingreso, fecha_reingreso')
          .eq('id', user.id)
          .maybeSingle();

      if (profile != null) {
        final fullName = (profile['nombre'] != null)
            ? '${profile['nombre']} ${profile['paterno']} ${profile['materno'] ?? ''}'.trim()
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
          .select('id, nombre, paterno, materno, role, fecha_ingreso, fecha_reingreso')
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
    
    final selectedProfile = _adminUserList.firstWhere((p) => p['id'] == newUserId, orElse: () => {});
    if (selectedProfile.isEmpty) return;

    setState(() {
      _selectedUserId = newUserId;
      _userFullName = (selectedProfile['nombre'] != null)
          ? '${selectedProfile['nombre']} ${selectedProfile['paterno']} ${selectedProfile['materno'] ?? ''}'.trim()
          : 'Usuario';
      _fechaIngreso = selectedProfile['fecha_ingreso'] != null
          ? DateTime.tryParse(selectedProfile['fecha_ingreso'])
          : null;
      _fechaReingreso = selectedProfile['fecha_reingreso'] != null
          ? DateTime.tryParse(selectedProfile['fecha_reingreso'])
          : null;
      _isLoading = true; // Show loading while fetching their incidencias
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
    if (days < 0) { months--; }
    if (months < 0) { years--; months += 12; }
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
    if (now.month < base.month || (now.month == base.month && now.day < base.day)) years--;
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
        border: Border.all(color: Colors.grey[300]!),
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
            decoration: BoxDecoration(color: Colors.grey[200]),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text('Antigüedad', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text('Días', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          ),
          // Data rows
          for (var i = 0; i < rows.length; i++)
            TableRow(
              decoration: BoxDecoration(
                color: i == highlightIdx
                    ? theme.colorScheme.secondary.withOpacity(0.18)
                    : (i.isEven ? Colors.white : Colors.grey[50]),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    rows[i][0],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == highlightIdx ? FontWeight.bold : FontWeight.normal,
                      color: i == highlightIdx ? theme.colorScheme.secondary : null,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    rows[i][1],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == highlightIdx ? FontWeight.bold : FontWeight.normal,
                      color: i == highlightIdx ? theme.colorScheme.secondary : null,
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
              Icon(Icons.workspace_premium_outlined, color: theme.colorScheme.secondary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(_calcAntiguedad(),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.secondary)),
                    Text('Desde: $dateStr', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              if (!isDesktop)
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(Icons.expand_more, color: theme.colorScheme.secondary.withOpacity(0.6)),
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
      margin: !isDesktop ? const EdgeInsets.fromLTRB(16, 12, 16, 4) : EdgeInsets.zero,
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
    final label = _fechaReingreso != null ? 'Antigüedad (Reingreso)' : 'Antigüedad';
    final dateStr = '${base.day.toString().padLeft(2, '0')}/${base.month.toString().padLeft(2, '0')}/${base.year}';

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
    final label = _fechaReingreso != null ? 'Antigüedad (Reingreso)' : 'Antigüedad';
    final dateStr = '${base.day.toString().padLeft(2, '0')}/${base.month.toString().padLeft(2, '0')}/${base.year}';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAntiguedadCardContent(theme: theme, label: label, dateStr: dateStr, isDesktop: true),
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
    if (base == null) return const SizedBox.shrink(); // Fallback UI already handled in Antiguedad logic

    final now = DateTime.now();
    final theme = Theme.of(context);
    final completedYears = _calcYears();

    // Map to accumulate requested days per period
    final String targetUserId = _selectedUserId ?? '';
    String normalizePeriod(String? p) => (p ?? '').replaceAll(RegExp(r'\D'), '');
    
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

    // Build rows: from year 1 to completedYears + 1 (one future period)
    final tableRows = <Map<String, dynamic>>[];
    for (int y = 1; y <= completedYears + 1; y++) {
      // Anniversary date for this year of service
      final anniversary = DateTime(base.year + y, base.month, base.day);
      final periodStart = anniversary.year - 1;
      final periodLabel = '$periodStart - ${anniversary.year}';
      final normLabel = normalizePeriod(periodLabel);

      // Days: old law if periodStart < 2023, new law otherwise
      final int days = periodStart >= 2023
          ? _getDaysByYears(y)
          : (6 + (y - 1) * 2).clamp(0, 14);

      final isCurrent = y == completedYears;       // last completed year
      final isUpcoming = anniversary.isAfter(now); // anniversary not yet passed
      final daysRequested = usedDaysMap[normLabel] ?? 0;

      tableRows.add({
        'periodo': periodLabel,
        'days': days,
        'requested': daysRequested,
        'isCurrent': isCurrent,
        'isUpcoming': isUpcoming,
      });
    }

    if (tableRows.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          Container(
            color: Colors.grey[100],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.calendar_month_outlined, size: 18, color: theme.colorScheme.secondary),
                const SizedBox(width: 8),
                Text('Historial de Vacaciones',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.secondary)),
              ],
            ),
          ),
          // Header row
          Container(
            color: Colors.grey[200],
            child: Row(children: [
              Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Período', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              )),
              SizedBox(width: 60, child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text('Ley', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center),
              )),
              SizedBox(width: 70, child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text('Pedidos', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center),
              )),
            ]),
          ),
          // Data rows
          ...tableRows.asMap().entries.map((entry) {
            final i = entry.key;
            final row = entry.value;
            final isCurrent = row['isCurrent'] as bool;
            final isUpcoming = row['isUpcoming'] as bool;

            Color bgColor;
            if (isCurrent) {
              bgColor = theme.colorScheme.secondary.withOpacity(0.15);
            } else if (isUpcoming) {
              bgColor = Colors.orange.withOpacity(0.07);
            } else {
              bgColor = i.isEven ? Colors.white : Colors.grey[50]!;
            }

            return Container(
              color: bgColor,
              child: Row(children: [
                Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    row['periodo'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? theme.colorScheme.secondary : (isUpcoming ? Colors.orange[700] : null),
                    ),
                  ),
                )),
                SizedBox(width: 60, child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(
                    '${row['days']}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? theme.colorScheme.secondary : (isUpcoming ? Colors.orange[700] : null),
                    ),
                  ),
                )),
                SizedBox(width: 70, child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(
                    '${row['requested']}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? theme.colorScheme.secondary : (isUpcoming ? Colors.orange[700] : null),
                    ),
                  ),
                )),
              ]),
            );
          }),
        ],
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
          .eq('usuario_id', _selectedUserId ?? Supabase.instance.client.auth.currentUser!.id)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _incidencias = List<Map<String, dynamic>>.from(response)
            ..sort((a, b) {
              const order = {'PENDIENTE': 0, 'APROBADA': 1, 'CANCELADA': 2};
              final aOrder = order[a['status']] ?? 99;
              final bOrder = order[b['status']] ?? 99;
              if (aOrder != bOrder) return aOrder.compareTo(bOrder);
              return (b['created_at'] as String).compareTo(a['created_at'] as String);
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
        const SnackBar(content: Text('Solo se pueden editar incidencias en estado PENDIENTE')),
      );
      return;
    }

    // Verificar antigüedad mínima de 1 año (solo para crear, no para editar, y no para admin)
    if (!isEditing && _userRole != 'admin') {
      final base = _fechaReingreso ?? _fechaIngreso;
      if (base != null) {
        final now = DateTime.now();
        final years = now.year - base.year - ((now.month < base.month || (now.month == base.month && now.day < base.day)) ? 1 : 0);
        if (years < 1) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.info_outline, color: Colors.orange, size: 36),
              title: const Text('Antigüedad insuficiente', textAlign: TextAlign.center),
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

    final periodController = TextEditingController(text: incidencia?['periodo'] ?? '2025 – 2026');
    final diasController = TextEditingController(text: incidencia?['dias']?.toString() ?? '');
    DateTime fechaInicio = incidencia != null ? DateTime.parse(incidencia['fecha_inicio']) : DateTime.now();
    DateTime fechaFin = incidencia != null ? DateTime.parse(incidencia['fecha_fin']) : DateTime.now().add(const Duration(days: 1));
    DateTime fechaRegreso = incidencia != null ? DateTime.parse(incidencia['fecha_regreso']) : DateTime.now().add(const Duration(days: 2));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 20, left: 20, right: 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEditing ? 'Editar Incidencia' : 'Nueva Incidencia',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF344092)),
                    ),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 16),
                _buildFieldLabel('Nombre (Automático)'),
                Text(isEditing ? (incidencia['nombre_usuario'] ?? '...') : (_userFullName ?? '...'), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildFieldLabel('Periodo'),
                DropdownButtonFormField<String>(
                  value: periodController.text,
                  items: ['2020 – 2021', '2021 – 2022', '2022 – 2023', '2024 – 2025', '2025 – 2026']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (val) => periodController.text = val!,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                _buildFieldLabel('Días'),
                TextField(
                  controller: diasController,
                  keyboardType: TextInputType.number,
                  maxLength: 2,
                  decoration: const InputDecoration(border: OutlineInputBorder(), counterText: ""),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildDatePicker('Fecha Inicio', fechaInicio, (d) => setModalState(() => fechaInicio = d)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDatePicker('Fecha Final', fechaFin, (d) => setModalState(() => fechaFin = d)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDatePicker('Fecha Regreso', fechaRegreso, (d) => setModalState(() => fechaRegreso = d)),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (diasController.text.isEmpty) return;
                      
                      final data = {
                        if (!isEditing) 'nombre_usuario': _userFullName,
                        'periodo': periodController.text,
                        'dias': int.parse(diasController.text),
                        'fecha_inicio': fechaInicio.toIso8601String(),
                        'fecha_fin': fechaFin.toIso8601String(),
                        'fecha_regreso': fechaRegreso.toIso8601String(),
                        if (!isEditing) 'usuario_id': _selectedUserId ?? Supabase.instance.client.auth.currentUser!.id,
                      };

                      try {
                        if (isEditing) {
                          await Supabase.instance.client.from('incidencias').update(data).eq('id', incidencia['id']);
                        } else {
                          await Supabase.instance.client.from('incidencias').insert(data);
                          // Notificar a administradores (global)
                          await NotificationService.send(
                            title: 'Nueva Incidencia',
                            message: '$_userFullName ha creado una nueva petición.',
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
                    child: Text(isEditing ? 'GUARDAR CAMBIOS' : 'CREAR PETICIÓN'),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
  );

  Widget _buildDatePicker(String label, DateTime current, Function(DateTime) onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(label),
        InkWell(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: current,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (d != null) onPick(d);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${current.day}/${current.month}/${current.year}'),
                const Icon(Icons.calendar_today, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileList(ThemeData theme) {
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
            side: BorderSide(color: Colors.grey[200]!),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            title: Text(
              inc['nombre_usuario'] ?? 'Usuario',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('Días: ${inc['dias']} | Creado: ${_formatDate(inc['created_at'])}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                if (_userRole == 'admin')
                  PopupMenuButton<String>(
                    onSelected: (val) async {
                      if (val == 'EDIT') {
                        _showIncidenciaForm(incidencia: inc);
                      } else {
                        await Supabase.instance.client.from('incidencias').update({'status': val}).eq('id', inc['id']);
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
                      const PopupMenuItem(value: 'EDIT', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar'), dense: true)),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'APROBADA', child: Text('Aprobar')),
                      const PopupMenuItem(value: 'CANCELADA', child: Text('Cancelar')),
                      const PopupMenuItem(value: 'PENDIENTE', child: Text('Pendiente')),
                    ],
                  )
                else if (inc['status'] == 'PENDIENTE')
                  IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _showIncidenciaForm(incidencia: inc)),
              ],
            ),
          ),
        );
      },
    );
  }


  /// Admin-only: shows all PENDIENTE records from all users.
  Widget _buildPendingTable(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.pending_actions, color: Colors.orange[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  'Solicitudes Pendientes (${_allIncidencias.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_allIncidencias.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('Sin solicitudes pendientes', style: TextStyle(color: Colors.grey)),
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
                headingRowColor: WidgetStateProperty.all(Colors.orange.withOpacity(0.07)),
                columnSpacing: 20,
                horizontalMargin: 16,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 48,
                columns: const [
                  DataColumn(label: Text('Nombre', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Periodo', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Días', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Fecha Inicio', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Fecha Final', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Fecha Regreso', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Estatus', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _allIncidencias.map((inc) {
                  final profile = inc['profiles'] as Map<String, dynamic>? ?? {};
                  final nombre = '${profile['nombre'] ?? ''} ${profile['paterno'] ?? ''}'.trim();
                  return DataRow(cells: [
                    DataCell(Text(nombre.isEmpty ? inc['usuario_id']?.toString().substring(0, 8) ?? '---' : nombre)),
                    DataCell(Text(inc['periodo']?.toString() ?? '---')),
                    DataCell(Text(inc['dias']?.toString() ?? '---')),
                    DataCell(Text(inc['fecha_inicio'] != null ? _formatDate(inc['fecha_inicio']) : '---')),
                    DataCell(Text(inc['fecha_fin'] != null ? _formatDate(inc['fecha_fin']) : '---')),
                    DataCell(Text(inc['fecha_regreso'] != null ? _formatDate(inc['fecha_regreso']) : '---')),
                    DataCell(
                      PopupMenuButton<String>(
                        tooltip: 'Cambiar estatus',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.orange.withOpacity(0.4), width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('PENDIENTE',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange[800])),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down, size: 14, color: Colors.orange[800]),
                            ],
                          ),
                        ),
                        onSelected: (val) async {
                          await Supabase.instance.client
                              .from('incidencias')
                              .update({'status': val})
                              .eq('id', inc['id']);
                          await NotificationService.send(
                            title: 'Tu incidencia fue $val',
                            message: 'El estado de tu petición ha cambiado a $val.',
                            userId: inc['usuario_id'],
                            type: 'incidencia_status',
                          );
                          _fetchIncidencias();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'APROBADA', child: Text('APROBADA')),
                          PopupMenuItem(value: 'RECHAZADA', child: Text('RECHAZADA')),
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

  Widget _buildDesktopTable(ThemeData theme) {


    return SizedBox(
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Historial de Solicitudes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ElevatedButton.icon(
                    onPressed: () => _showIncidenciaForm(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.secondary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(120, 48),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('NUEVO'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Theme(
              data: theme.copyWith(cardColor: Colors.transparent),
              child: PaginatedDataTable(
                columns: const [
                  DataColumn(label: Text('Funcionario', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Detalle', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Estatus', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                source: _IncidenciasDataSource(
                  items: _incidencias,
                  theme: theme,
                  isAdmin: _userRole == 'admin',
                  formatDate: _formatDate,
                  getStatusColor: _getStatusColor,
                  onEdit: (item) => _showIncidenciaForm(incidencia: item),
                  onStatusChange: (item, val) async {
                    await Supabase.instance.client.from('incidencias').update({'status': val}).eq('id', item['id']);
                    await NotificationService.send(
                      title: 'Tu incidencia fue $val',
                      message: 'El estado de tu petición ha cambiado a $val.',
                      userId: item['usuario_id'],
                      type: 'incidencia_status',
                    );
                    _fetchIncidencias();
                  },
                ),
                rowsPerPage: _incidencias.isEmpty ? 1 : (_incidencias.length > 10 ? 10 : _incidencias.length),
                showCheckboxColumn: false,
                horizontalMargin: 16,
                columnSpacing: 16,
                dataRowMinHeight: 48,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktopWidth = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      floatingActionButton: !isDesktopWidth
          ? FloatingActionButton.extended(
              onPressed: () => _showIncidenciaForm(),
              backgroundColor: theme.colorScheme.secondary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('NUEVO'),
            )
          : null,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth <= 800;
                final hasSelector = _userRole == 'admin' && _adminUserList.isNotEmpty;

                Widget? selectorWidget = hasSelector
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedUserId,
                          isDense: true,
                          icon: Icon(Icons.keyboard_arrow_down, color: theme.colorScheme.secondary),
                          items: _adminUserList.map((user) {
                            final name = '${user['nombre']} ${user['paterno']} ${user['materno'] ?? ''}'.trim();
                            return DropdownMenuItem(
                              value: user['id'] as String,
                              child: Text(name.isEmpty ? 'Usuario' : name, style: const TextStyle(fontSize: 14)),
                            );
                          }).toList(),
                          onChanged: _onUserSelected,
                        ),
                      ),
                    )
                  : null;

                return PageHeader(
                  title: 'Incidencias y Peticiones',
                  // On desktop: selector is inline (trailing)
                  // On mobile: selector goes below the title (bottom) to avoid compressing it
                  trailing: (!isMobile && selectorWidget != null) ? selectorWidget : null,
                  bottom: (isMobile && selectorWidget != null)
                    ? [SizedBox(width: double.infinity, child: selectorWidget)]
                    : null,
                );
              },
            ),
          ),
          // Main content (Responsive layout)
          SliverToBoxAdapter(
            child: Builder(
              builder: (context) {
                final isDesktop = MediaQuery.of(context).size.width > 800;

                if (isDesktop) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Admin-only pending table at top
                        if (_userRole == 'admin') ...[
                          _buildPendingTable(theme),
                          const SizedBox(height: 24),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildAntiguedadDesktop(),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: _buildHistorialVacaciones(),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 5,
                              child: _isLoading
                                  ? const Center(child: CircularProgressIndicator())
                                  : _buildDesktopTable(theme),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: Column(
                      children: [
                        // Admin-only pending table at top on mobile too
                        if (_userRole == 'admin')
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: _buildPendingTable(theme),
                          ),
                        _buildAntiguedadMobile(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildHistorialVacaciones(),
                        ),
                        if (_isLoading)
                          const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())
                        else if (_incidencias.isEmpty)
                          const Padding(padding: EdgeInsets.all(40), child: Text('Sin incidencias registradas'))
                        else
                          _buildMobileList(theme),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)), // FAB clearance
        ],
      ),
    );
  }

  IconData _getStatusIconData(String status) {
    switch (status) {
      case 'APROBADA': return Icons.check_circle_outline;
      case 'CANCELADA': return Icons.cancel_outlined;
      default: return Icons.pending_outlined;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'APROBADA': return Colors.green;
      case 'CANCELADA': return Colors.red;
      default: return Colors.orange;
    }
  }

  Widget _getStatusIcon(String status) {
    return Icon(_getStatusIconData(status), color: _getStatusColor(status));
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
  final String Function(String) formatDate;
  final Color Function(String) getStatusColor;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>, String) onStatusChange;

  _IncidenciasDataSource({
    required this.items,
    required this.theme,
    required this.isAdmin,
    required this.formatDate,
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
          Text(inc['nombre_usuario'] ?? 'Usuario', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        DataCell(
          Text('Días: ${inc['dias']} (${inc['periodo'] ?? ''}) | Creado: ${formatDate(inc['created_at'])}'),
        ),
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
              const SizedBox(width: 8),
              if (isAdmin)
                PopupMenuButton<String>(
                  onSelected: (val) {
                    if (val == 'EDIT') {
                      onEdit(inc);
                    } else {
                      onStatusChange(inc, val);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'EDIT', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar'), dense: true)),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'APROBADA', child: Text('Aprobar')),
                    const PopupMenuItem(value: 'CANCELADA', child: Text('Cancelar')),
                    const PopupMenuItem(value: 'PENDIENTE', child: Text('Pendiente')),
                  ],
                )
              else if (inc['status'] == 'PENDIENTE')
                IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => onEdit(inc)),
            ],
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
