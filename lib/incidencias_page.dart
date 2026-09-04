import 'dart:typed_data';
import 'dart:ui';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/incidencias_pdf_service.dart';
import 'services/file_saver_util.dart';
import 'services/trash_service.dart';
import 'incidencias_por_periodo.dart';
import 'services/quincena.dart';
import 'theme/si_theme.dart';
import 'widgets/calendario_incidencias.dart';
import 'widgets/grafica_vacaciones_mes.dart';


class IncidenciasPage extends StatefulWidget {
  const IncidenciasPage({super.key});

  @override
  State<IncidenciasPage> createState() => _IncidenciasPageState();
}

class _IncidenciasPageState extends State<IncidenciasPage> {
  List<Map<String, dynamic>> _incidencias = [];
  List<Map<String, dynamic>> _allIncidencias =
      []; // all PENDIENTE for admin view

  /// Todas las incidencias, de todos, para el resumen por mes que sólo ven los administradores.
  ///
  /// Se traen sólo las cuatro columnas que la cuenta necesita, no la fila entera: son ~700
  /// registros desde 2015 y el resto de los campos no se usa aquí.
  ///
  /// El RLS es el que protege esto de verdad: la política `is_admin()` deja ver todas, y un usuario
  /// normal sólo ve las suyas. El `if` de la pantalla oculta la tabla; el que la cierra es la base.
  List<Map<String, dynamic>> _paraResumen = [];
  Quincena? _quincena;
  bool _exportandoResumen = false;
  bool _isLoading = true;
  bool _antiguedadExpanded = false; // manual expand state for mobile card
  String? _userRole;
  String? _userFullName;
  DateTime? _fechaIngreso;
  DateTime? _fechaReingreso;
  Map<String, dynamic>? _selectedUserProfile; // To store the full profile for PDF generation


  List<Map<String, dynamic>> _adminUserList = [];
  String? _selectedUserId;
  _IncidenciasDataSource? _dataSource;

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
            SizedBox(
              width: 220,
              child: _buildUserAutocomplete(c, maxWidth: 280),
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

  @override
  void dispose() {
    _dataSource?.dispose();
    super.dispose();
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
      _fetchIncidencias(showLoader: true);
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

    _fetchIncidencias(showLoader: true);
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
          ? const EdgeInsets.only(top: 12, bottom: 4)
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
      padding: const EdgeInsets.only(top: 12, bottom: 4),
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

  /// Returns all vacation periods for the current user.
  /// When [onlyWithDays] is true (default), only periods with días
  /// disponibles > 0 are included. Each entry has:
  ///   { 'label': '2025 - 2026', 'disponible': 13, 'days': 24 }
  List<Map<String, dynamic>> _getAvailablePeriods({bool onlyWithDays = true}) {
    final base = _fechaReingreso ?? _fechaIngreso;
    if (base == null) return [];

    final now = DateTime.now();
    final completedYears = _calcYears();
    final targetId = _selectedUserId ??
        Supabase.instance.client.auth.currentUser?.id ??
        '';

    String norm(String? p) => (p ?? '').replaceAll(RegExp(r'\D'), '');

    // Días usados por período: SÓLO las APROBADAS.
    //
    // Decidido el 18/08/2026, y es lo contrario de lo que estaba: antes se contaban también las
    // PENDIENTES, porque una solicitud pendiente reservaba los días. Ver el comentario largo en
    // `_buildHistorialTable`, que explica la consecuencia de este cambio.
    final used = <String, int>{};
    for (final inc in _incidencias) {
      if (inc['usuario_id'] == targetId && inc['status'] == 'APROBADA') {
        final k = norm(inc['periodo'] as String?);
        if (k.isNotEmpty) {
          used[k] = (used[k] ?? 0) + (inc['dias'] as int? ?? 0);
        }
      }
    }

    double calcProp(int days, DateTime start, DateTime end) {
      if (start.isAfter(now)) return days.toDouble();
      if (end.isBefore(now) || end.isAtSameMomentAs(now)) return days.toDouble();
      final elapsed = now.difference(start).inDays + 1;
      return (days / 365) * elapsed;
    }

    final list = <Map<String, dynamic>>[];
    for (int y = 1; y <= completedYears + 1; y++) {
      final end   = DateTime(base.year + y,     base.month, base.day);
      final start = DateTime(base.year + y - 1, base.month, base.day);
      final label = '${start.year} - ${end.year}';

      final int days;
      if (start.year >= 2023) {
        days = _getDaysByYears(y);
      } else {
        final cutoff = DateTime(2017, 5, 2);
        days = base.isBefore(cutoff)
            ? (6 + (y - 1) * 2).clamp(0, 14)
            : (8 + (y - 1) * 2).clamp(0, 16);
      }

      final requested = used[norm(label)] ?? 0;
      final prop      = calcProp(days, start, end);
      final disp      = (prop - requested).floor();

      if (!onlyWithDays || disp > 0) {
        list.add({'label': label, 'disponible': disp, 'days': days});
      }
    }
    return list;
  }


  /// Tabla de historial de vacaciones por periodo
  Widget _buildHistorialVacaciones() {
    final base = _fechaReingreso ?? _fechaIngreso;
    if (base == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final theme = Theme.of(context);
    final c = SiColors.of(context);
    final completedYears = _calcYears();

    // Antes esto era `_selectedUserId ?? ''`, y con eso la tabla mentía.
    //
    // Cuando alguien ve SU PROPIA página no hay usuario seleccionado, así que `targetUserId` quedaba
    // en cadena vacía, ninguna incidencia coincidía con la comparación de abajo, y `usedDaysMap`
    // salía vacío: la columna «Solicitados» mostraba 0 y «Disponible» los días de ley completos.
    // Medido con un caso real —ingreso 2014, 108 días ya tomados—: la tabla decía **182 días
    // disponibles** donde había **74**. El formulario de solicitud sí los restaba, así que las dos
    // partes de la misma página se contradecían.
    //
    // `_fetchIncidencias` ya trae sólo las de la persona correcta, así que basta con resolver el id
    // igual que hace `_getAvailablePeriods`.
    final String targetUserId = _selectedUserId ??
        Supabase.instance.client.auth.currentUser?.id ??
        '';
    String normalizePeriod(String? p) =>
        (p ?? '').replaceAll(RegExp(r'\D'), '');

    final usedDaysMap = <String, int>{};
    for (final inc in _incidencias) {
      // Cuenta SÓLO las APROBADAS.
      //
      // ─── Las dos decisiones, y por qué está escrito aquí ────────────────────
      //
      // En junio se decidió contar también las PENDIENTES, porque una solicitud pendiente reserva los
      // días. El 18/08/2026 se decidió lo contrario: sólo cuentan los días ya autorizados.
      //
      // La consecuencia, para que nadie la descubra por sorpresa: mientras una solicitud espera
      // autorización, sus días siguen apareciendo como disponibles. Alguien con 5 días y una solicitud
      // pendiente de 5 puede pedir otros 5, y las dos pueden aprobarse. El control de eso pasa a ser
      // de quien autoriza, no del cálculo.
      //
      // Lo que NO cambia es que los TRES sitios cuentan igual —esta tabla, `_getAvailablePeriods` que
      // alimenta el formulario, y `calcular_vacaciones` que usa Soli—. Cuando no coincidían, la tabla
      // mostraba más días disponibles de los que el formulario dejaba pedir; ése es el fallo que hay
      // que evitar al cambiar esta regla, y por eso se cambian los tres a la vez.
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

    // Column widths — keep totals small so all fit without scrolling
    const double wPeriodo = 120;   // Período fijo (suficiente p/"2025 - 2026")
    const double wDias = 70;       // Días/Prop fusionado
    const double wPedidos = 88;    // Solicitados
    const double wDisp = 88;       // Disponible
    // Total fijo: 120+70+88+88 = 366 → cabe en el panel lateral (~360px)

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
          // Los 366px de columnas eran para el panel lateral de ~360, y la tarjeta ahora mide un
          // tercio de la página: entre 390 y 600px según la pantalla. Las columnas se reparten ese
          // ancho en la misma proporción, porque con anchos fijos la tabla se quedaba en 366 y
          // dejaba el resto de la tarjeta en blanco.
          LayoutBuilder(
            builder: (context, tableConstraints) {
              const double minW = wPeriodo + wDias + wPedidos + wDisp; // 366
              final double tableWidth = tableConstraints.maxWidth > minW
                  ? tableConstraints.maxWidth
                  : minW;
              final double factor = tableWidth / minW;

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                      width: tableWidth,
                      child: Table(
                      columnWidths: {
                        0: FixedColumnWidth(wPeriodo * factor),
                        1: FixedColumnWidth(wDias * factor),
                        2: FixedColumnWidth(wPedidos * factor),
                        3: FixedColumnWidth(wDisp * factor),
                      },
                      children: [
                        // Header row
                        TableRow(
                          decoration: BoxDecoration(color: c.hover),
                          children: [
                            _cellTable('Período',
                                weight: FontWeight.bold, align: TextAlign.left),
                            _cellTable('Días', weight: FontWeight.bold),
                            _cellTable('Solicitados', weight: FontWeight.bold),
                            _cellTable('Disponible', weight: FontWeight.bold),
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

                          final int propInt = proporcional.toInt();
                          final int daysInt = row['days'] as int;
                          final String diasText = propInt == daysInt
                              ? '$propInt'
                              : '$propInt de $daysInt';

                          return TableRow(
                            decoration: BoxDecoration(color: bgColor),
                            children: [
                              _cellTable(row['periodo'] as String,
                                  color: textColor,
                                  weight: weight,
                                  align: TextAlign.left),
                              _cellTable(diasText,
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
                            _cellTable('Total disponible',
                                weight: FontWeight.bold, align: TextAlign.left),
                            _cellTable(''),
                            _cellTable('$totalReq',
                                weight: FontWeight.bold),
                            _cellTable('${totalSaldo.toInt()} días',
                                weight: FontWeight.bold,
                                color: totalSaldo < 0
                                    ? Colors.red
                                    : Colors.green[700]),
                          ],
                        ),
                      ],
                    ),   // Table
                  ),    // SizedBox
                );      // SingleChildScrollView
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

  /// Si esta incidencia se puede eliminar.
  ///
  /// ─── Las dos condiciones, y por qué ──────────────────────────────────────
  ///
  /// **Sólo PENDIENTE o CANCELADA.** Una APROBADA es el registro de días que la persona YA tomó, y es
  /// además lo que `calcular_vacaciones` descuenta del saldo: borrarla le devolvería días que sí
  /// disfrutó. Una PENDIENTE también reserva días —decisión tomada—, pero ahí borrarla es justo lo que
  /// se quiere: libera lo que nunca se usó.
  ///
  /// **Sólo administradores**, y no por comodidad: lo dice RLS. Las políticas de `incidencias` conceden
  /// el borrado con `is_admin()`, y en `trash` sólo un administrador puede insertar. Un usuario normal
  /// que quiera deshacerse de su solicitud tiene el camino correcto ya puesto: cancelarla, que su
  /// política sí le permite mientras esté PENDIENTE.
  bool _sePuedeEliminar(Map<String, dynamic> inc) =>
      _userRole == 'admin' &&
      (inc['status'] == 'PENDIENTE' || inc['status'] == 'CANCELADA');

  /// Manda la incidencia a la papelera: se guarda entera y se puede restaurar.
  ///
  /// Mismo patrón que Colaboradores, Inventario y Contactos: `trash` conserva la fila completa en
  /// `data` y `TrashService.restore` la reinserta en su tabla. No es un borrado con marca en la propia
  /// tabla, así que la fila desaparece de `incidencias` y **el saldo de vacaciones se recalcula solo**
  /// —`calcular_vacaciones` suma sobre lo que hay—, sin tener que tocar nada más.
  Future<void> _eliminarIncidencia(Map<String, dynamic> inc) async {
    if (!_sePuedeEliminar(inc)) return;

    final quien = (inc['nombre_usuario'] ?? '').toString().trim();
    final dias = inc['dias'];
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar a la papelera'),
        // Se dicen los días y el periodo: es lo que permite darse cuenta de que es la incidencia
        // equivocada ANTES de borrarla, no después.
        content: Text(
          '¿Enviar a la papelera la incidencia de '
          '${quien.isEmpty ? 'este colaborador' : quien}'
          '${dias == null ? '' : ' de $dias día${dias == 1 ? '' : 's'}'}'
          '${inc['periodo'] == null ? '' : ', periodo ${inc['periodo']}'}?\n\n'
          'Se puede restaurar desde la Papelera. Los días vuelven a estar disponibles.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ENVIAR A LA PAPELERA'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    try {
      // Primero la copia, después el borrado. Al revés, un fallo al guardar en la papelera dejaría la
      // incidencia perdida sin forma de recuperarla.
      await TrashService.moveToTrash(
        originTable: 'incidencias',
        originId: inc['id'].toString(),
        data: Map<String, dynamic>.from(inc),
        label: 'Incidencia'
            '${quien.isEmpty ? '' : ' de $quien'}'
            '${inc['periodo'] == null ? '' : ' (${inc['periodo']})'}',
      );
      await Supabase.instance.client
          .from('incidencias')
          .delete()
          .eq('id', inc['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incidencia enviada a la papelera')));
      _fetchIncidencias();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo eliminar: $e'),
          backgroundColor: Colors.red));
    }
  }

  Future<void> _fetchIncidencias({bool showLoader = false}) async {
    if (showLoader) setState(() => _isLoading = true);
    try {
      // Fetch incidencias for the selected (or current) user
      final response = await Supabase.instance.client
          .from('incidencias')
          .select()
          .eq('usuario_id',
              _selectedUserId ?? Supabase.instance.client.auth.currentUser!.id)
          .order('created_at', ascending: false);

      if (mounted) {
        final sorted = List<Map<String, dynamic>>.from(response)
          ..sort((a, b) {
            const order = {'PENDIENTE': 0, 'APROBADA': 1, 'CANCELADA': 2};
            final aOrder = order[a['status']] ?? 99;
            final bOrder = order[b['status']] ?? 99;
            if (aOrder != bOrder) return aOrder.compareTo(bOrder);
            return (b['created_at'] as String)
                .compareTo(a['created_at'] as String);
          });
        setState(() {
          _incidencias = sorted;
          _isLoading = false;
          // Reutiliza el DataSource existente para que PaginatedDataTable
          // detecte el cambio vía notifyListeners()
          if (_dataSource != null) {
            _dataSource!.updateItems(sorted);
          }
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

      // Y lo mínimo para el resumen por mes.
      try {
        final resumenResp = await Supabase.instance.client
            .from('incidencias')
            .select('created_at,status,nombre_usuario,dias,'
                'fecha_inicio,fecha_fin,fecha_regreso,usuario_id')
            .eq('status', 'APROBADA')
            .order('created_at', ascending: false);
        final filas = List<Map<String, dynamic>>.from(resumenResp);
        if (mounted) {
          setState(() {
            _paraResumen = filas;
            // Se abre en la quincena MÁS RECIENTE CON DATOS, no en la del reloj: el día 2 de un
            // mes la quincena en curso casi no tiene registros y la tabla se vería vacía sin razón
            // aparente. Es el mismo criterio del panel de Asistencia.
            final qs = quincenasConDatos(filas);
            _quincena ??= qs.isNotEmpty ? qs.first : null;
          });
        }
      } catch (e) {
        debugPrint('Error fetching resumen por mes: $e');
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

    // Períodos disponibles (filtra solo los que tienen días cuando es alta nueva)
    final availablePeriods = _getAvailablePeriods(onlyWithDays: !isEditing);
    String norm(String? p) => (p ?? '').replaceAll(RegExp(r'\D'), '');

    // Valor inicial del período: para edición usa el guardado, para alta el
    // primer período con días disponibles.
    String initPeriod = '';
    if (isEditing) {
      final raw = incidencia?['periodo'] as String? ?? '';
      // Busca coincidencia por dígitos (cubre diferencias de guión/em-dash)
      final match = availablePeriods.cast<Map<String, dynamic>?>().firstWhere(
        (p) => norm(p!['label']) == norm(raw),
        orElse: () => null,
      );
      initPeriod = match != null ? match['label'] as String : raw;
    } else {
      initPeriod = availablePeriods.isNotEmpty
          ? availablePeriods.first['label'] as String
          : '';
    }

    final periodController = TextEditingController(text: initPeriod);
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
                            // El aviso ya NO se manda desde aqui.
                            //
                            // Lo hace un disparador de la base -`notificar_incidencia_nueva`- que
                            // avisa al JEFE DIRECTO de quien pide y a Desarrollo Humano. Dejarlo aqui
                            // mandaria las dos cosas a la vez: el dirigido y el antiguo a los cinco
                            // administradores.
                            //
                            // Y el antiguo tenia dos problemas: iba a TODOS los admins sin importar de
                            // quien fuera la solicitud, y solo salia por este camino. Una peticion
                            // creada por WhatsApp no avisaba a nadie, que es lo que se reporto.
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
                if (availablePeriods.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.orange.shade50,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.orange.shade700, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Sin períodos con días disponibles.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: periodController.text.isEmpty
                        ? null
                        : periodController.text,
                    items: availablePeriods.map((p) {
                      final label = p['label'] as String;
                      final disp  = p['disponible'] as int;
                      return DropdownMenuItem<String>(
                        value: label,
                        child: Row(
                          children: [
                            Expanded(child: Text(label)),
                            const SizedBox(width: 8),
                            Text(
                              '$disp días',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: disp <= 5
                                      ? Colors.orange[700]
                                      : Colors.green[700]),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) periodController.text = val;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Período',
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
      padding: const EdgeInsets.only(bottom: 16),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: _incidencias.length,
      itemBuilder: (context, index) {
        final inc = _incidencias[index];
        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
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
                    } else if (val == 'DELETE') {
                      await _eliminarIncidencia(inc);
                    } else if (_userRole == 'admin') {
                      await Supabase.instance.client
                          .from('incidencias')
                          .update({'status': val}).eq('id', inc['id']);
                      // El aviso lo manda un disparador de la base -`notificar_cambio_de_estatus`- que avisa a
                      // quien pidio las vacaciones y a Desarrollo Humano, por campana y por WhatsApp.
                      //
                      // Estaba escrito TRES veces, una por cada menu de esta pagina, y aun asi faltaba en el cuarto
                      // camino: aprobar por WhatsApp pasa por `actualizar_incidencia` de Soli, que no notificaba. Es
                      // justo lo que se reporto -Marco aprobo por WhatsApp y no le llego a nadie-. En la base esta
                      // una vez y cubre los cuatro.
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
                      if (_sePuedeEliminar(inc)) ...[
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                            value: 'DELETE',
                            child: ListTile(
                                leading: Icon(Icons.delete_outline,
                                    color: Colors.red),
                                title: Text('Eliminar',
                                    style: TextStyle(color: Colors.red)),
                                dense: true)),
                      ],
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
                        final nombre =
                            inc['nombre_usuario']?.toString().trim() ?? '---';
                        return DataRow(cells: [
                          DataCell(Text(nombre.isEmpty ? '---' : nombre)),
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
                                // Optimistic update: remover el item de la lista
                                // inmediatamente para que la tabla refleje el
                                // cambio sin esperar el re-fetch.
                                final incId = inc['id'];
                                setState(() {
                                  _allIncidencias.removeWhere(
                                      (item) => item['id'] == incId);
                                });
                                try {
                                  await Supabase.instance.client
                                      .from('incidencias')
                                      .update({'status': val}).eq('id', incId);
                                  // El aviso lo manda un disparador de la base -`notificar_cambio_de_estatus`- que avisa a
                                  // quien pidio las vacaciones y a Desarrollo Humano, por campana y por WhatsApp.
                                  //
                                  // Estaba escrito TRES veces, una por cada menu de esta pagina, y aun asi faltaba en el cuarto
                                  // camino: aprobar por WhatsApp pasa por `actualizar_incidencia` de Soli, que no notificaba. Es
                                  // justo lo que se reporto -Marco aprobo por WhatsApp y no le llego a nadie-. En la base esta
                                  // una vez y cubre los cuatro.
                                } finally {
                                  // Siempre refrescar aunque NotificationService falle
                                  _fetchIncidencias();
                                }
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

  /// Los registros por mes. **Sólo administradores.**
  ///
  /// Va debajo de las solicitudes pendientes porque responde la pregunta de al lado: las pendientes
  /// dicen qué hay que atender hoy, y esta dice cómo viene el año. En los datos se ve un patrón que
  /// no se nota mirando registros de uno en uno —diciembre de 2025 tuvo 45 solicitudes y el resto de
  /// los meses ronda las 15—.
  ///
  /// La cuenta NO se hace aquí: vive en `incidencias_por_mes.dart`, con pruebas. Los días los
  /// consumen APROBADA y PENDIENTE y no las canceladas, que es la misma regla que ya usa el saldo de
  /// esta página; no es una regla nueva.
  /// Los registros de incidencias de una quincena. **Sólo administradores.**
  ///
  /// Va debajo de las solicitudes pendientes porque responde la pregunta de al lado: las pendientes
  /// dicen qué hay que atender hoy, y esta dice qué pasó en el periodo que se está cerrando.
  ///
  /// Una incidencia cae en la quincena donde EMPIEZA, aunque termine en otra —hay casos reales, del
  /// 28 de agosto al 2 de septiembre—. El por qué está en `incidencias_por_periodo.dart`, con sus
  /// pruebas; aquí sólo se dice en la pantalla para que nadie tenga que deducirlo.
  Widget _buildResumenMensual(SiColors c) {
    final quincenas = quincenasConDatos(_paraResumen);
    final q = _quincena;
    final registros = q == null
        ? const <Map<String, dynamic>>[]
        : registrosDe(_paraResumen, q);
    final totales = totalesDe(registros);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: SiRadius.rLg,
        side: BorderSide(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: c.hover,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.calendar_month_outlined, color: c.ink3, size: 22),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Registros por quincena',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: c.ink)),
                      Text(
                          'Sólo APROBADAS, del 1 al 15 y del 16 al último día del mes. Una '
                          'incidencia entra en la quincena donde EMPIEZA, aunque termine en otra.',
                          style: TextStyle(fontSize: 11.5, color: c.ink3)),
                    ],
                  ),
                ),
                if (quincenas.length > 1)
                  DropdownButton<String>(
                    value: q?.clave,
                    underline: const SizedBox.shrink(),
                    items: quincenas
                        .map((x) => DropdownMenuItem(
                            value: x.clave,
                            child: Text(x.etiqueta,
                                style: const TextStyle(
                                    fontSize: 13.5, fontWeight: FontWeight.w600))))
                        .toList(),
                    onChanged: (v) => setState(() => _quincena =
                        v == null ? null : quincenas.firstWhere((x) => x.clave == v)),
                  ),
                if (q != null)
                  OutlinedButton.icon(
                    onPressed: _exportandoResumen
                        ? null
                        : () => _exportarResumen(q, registros, totales),
                    icon: _exportandoResumen
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('Excel'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (q == null)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text('Sin incidencias registradas',
                    style: TextStyle(color: c.ink3)),
              ),
            )
          else if (registros.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text('Sin registros del ${q.etiqueta}',
                    style: TextStyle(color: c.ink3)),
              ),
            )
          else ...[
            // Ocupa el ancho de la tarjeta, y rueda sólo si de verdad no cabe.
            //
            // `SingleChildScrollView` a secas ajusta la tabla a su CONTENIDO, así que en una
            // pantalla ancha quedaba encogida a la izquierda con la tarjeta vacía a la derecha. El
            // `minWidth` la estira hasta el ancho disponible sin quitarle el desplazamiento
            // horizontal, que en un teléfono sigue haciendo falta.
            LayoutBuilder(
              builder: (context, cajas) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: cajas.maxWidth),
                  child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 38,
                dataRowMaxHeight: 44,
                columnSpacing: 22,
                headingTextStyle: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: c.ink3),
                dataTextStyle: TextStyle(fontSize: 12.5, color: c.ink),
                columns: const [
                  DataColumn(label: Text('ELABORACIÓN')),
                  DataColumn(label: Text('ESTATUS')),
                  DataColumn(label: Text('COLABORADOR')),
                  DataColumn(label: Text('DÍAS'), numeric: true),
                  DataColumn(label: Text('INICIO')),
                  DataColumn(label: Text('FIN')),
                  DataColumn(label: Text('REGRESO')),
                ],
                    rows: [for (final r in registros) _renglonRegistro(c, r)],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            // El pie con lo que suma la quincena.
            //
            // Ya no lleva el desglose por estatus: con la tabla filtrada a aprobadas, «8 registros,
            // 8 aprobadas» diría dos veces lo mismo.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Wrap(
                spacing: 20,
                runSpacing: 6,
                children: [
                  _pie(c, '${totales.registros}', 'registros aprobados'),
                  _pie(c, '${totales.dias}', 'días'),
                  _pie(c, '${totales.personas}', 'personas'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pie(SiColors c, String numero, String etiqueta, {String? ayuda, Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(numero,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: color ?? c.ink)),
        const SizedBox(width: 5),
        Text(ayuda == null ? etiqueta : '$etiqueta ($ayuda)',
            style: TextStyle(fontSize: 11.5, color: c.ink3)),
      ],
    );
  }

  DataRow _renglonRegistro(SiColors c, Map<String, dynamic> r) {
    final estatus = (r['status'] ?? '').toString().toUpperCase();
    final cancelada = estatus == 'CANCELADA';
    return DataRow(cells: [
      DataCell(Text(fechaCorta(r['created_at']))),
      DataCell(_etiquetaEstatus(c, estatus)),
      DataCell(ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Text((r['nombre_usuario'] ?? '—').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                // Una cancelada se apaga: sigue siendo un registro, pero no consume dias.
                color: cancelada ? c.ink3 : c.ink)),
      )),
      DataCell(Text('${r['dias'] ?? '—'}',
          style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()]))),
      DataCell(Text(fechaCorta(r['fecha_inicio']))),
      DataCell(Text(fechaCorta(r['fecha_fin']))),
      DataCell(Text(fechaCorta(r['fecha_regreso']))),
    ]);
  }

  Widget _etiquetaEstatus(SiColors c, String estatus) {
    final color = switch (estatus) {
      'APROBADA' => c.success,
      'PENDIENTE' => Colors.orange[800]!,
      'CANCELADA' => c.danger,
      _ => c.ink3,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: SiRadius.rSm,
      ),
      child: Text(estatus.isEmpty ? '—' : estatus,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  /// Exporta los MISMOS registros que se están viendo, sin volver a filtrar.
  ///
  /// Recibe la lista y los totales ya calculados en lugar de recalcularlos: si los recalculara
  /// aquí, el archivo podría no coincidir con la tabla que el usuario tiene delante —y esa es la
  /// clase de discrepancia que nadie encuentra hasta que alguien compara dos hojas en una junta—.
  Future<void> _exportarResumen(
      Quincena q, List<Map<String, dynamic>> registros, TotalesQuincena t) async {
    setState(() => _exportandoResumen = true);
    try {
      final excel = xl.Excel.createExcel();
      final hoja = excel['Incidencias'];
      excel.delete('Sheet1');

      final estiloEncabezado = xl.CellStyle(
        bold: true,
        backgroundColorHex: xl.ExcelColor.fromHexString('#344092'),
        fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
      );

      const encabezados = [
        'Elaboracion', 'Estatus', 'Colaborador', 'Dias',
        'Fecha inicio', 'Fecha fin', 'Fecha regreso',
      ];
      for (var i = 0; i < encabezados.length; i++) {
        final celda = hoja.cell(
            xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        celda.value = xl.TextCellValue(encabezados[i]);
        celda.cellStyle = estiloEncabezado;
      }

      for (var r = 0; r < registros.length; r++) {
        final inc = registros[r];
        // Las fechas van en ISO y no en dd/mm/aaaa: asi Excel las ordena y las filtra como fechas
        // en cualquier configuracion regional, que es para lo que se exporta esta hoja.
        final valores = <xl.CellValue>[
          xl.TextCellValue(_iso10(inc['created_at'])),
          xl.TextCellValue((inc['status'] ?? '').toString()),
          xl.TextCellValue((inc['nombre_usuario'] ?? '').toString()),
          xl.IntCellValue(int.tryParse('${inc['dias'] ?? 0}') ?? 0),
          xl.TextCellValue(_iso10(inc['fecha_inicio'])),
          xl.TextCellValue(_iso10(inc['fecha_fin'])),
          xl.TextCellValue(_iso10(inc['fecha_regreso'])),
        ];
        for (var col = 0; col < valores.length; col++) {
          hoja
              .cell(xl.CellIndex.indexByColumnRow(
                  columnIndex: col, rowIndex: r + 1))
              .value = valores[col];
        }
      }

      final filaTotal = registros.length + 1;
      final estiloTotal = xl.CellStyle(bold: true);
      final totales = <xl.CellValue>[
        xl.TextCellValue('TOTAL'),
        xl.TextCellValue('${t.registros} registros'),
        xl.TextCellValue('${t.personas} personas'),
        xl.IntCellValue(t.dias),
        xl.TextCellValue(q.desdeIso),
        xl.TextCellValue(q.hastaIso),
        xl.TextCellValue(''),
      ];
      for (var col = 0; col < totales.length; col++) {
        final celda = hoja.cell(
            xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: filaTotal));
        celda.value = totales[col];
        celda.cellStyle = estiloTotal;
      }

      // Las reglas, escritas en la hoja. Un archivo que sale de la aplicacion acaba en un correo
      // sin nadie que lo explique.
      final nota = filaTotal + 2;
      final notas = [
        'Quincena: ${q.etiqueta} (${q.desdeIso} al ${q.hastaIso}).',
        'Solo incidencias APROBADAS.',
        'Una incidencia entra por su FECHA DE INICIO, aunque termine en otra quincena.',
      ];
      for (var i = 0; i < notas.length; i++) {
        hoja
            .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: nota + i))
            .value = xl.TextCellValue(notas[i]);
      }

      final bytes = excel.encode()!;
      await FileSaverUtil.saveAndShare(
        Uint8List.fromList(bytes),
        'incidencias_${q.clave}.xlsx',
      );
    } catch (e) {
      debugPrint('Error exportando el resumen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportandoResumen = false);
    }
  }

  /// Los primeros diez caracteres de una fecha, que en ISO son `AAAA-MM-DD`.
  String _iso10(dynamic v) {
    final t = (v ?? '').toString();
    return t.length >= 10 ? t.substring(0, 10) : '';
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
                SizedBox(
                  width: 320,
                  child: _buildTableUserSelector(c),
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
          columnSpacing: 12,
          horizontalMargin: 12,
          columns: [
            DataColumn(
                label: Text('PERIODO',
                    style: TextStyle(
                        color: c.ink3,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1))),
            DataColumn(
                label: Text('DÍAS',
                    style: TextStyle(
                        color: c.ink3,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1))),
            DataColumn(
                label: Text('CREADO',
                    style: TextStyle(
                        color: c.ink3,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1))),
            DataColumn(
                label: Text('INICIO → FIN',
                    style: TextStyle(
                        color: c.ink3,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1))),
            DataColumn(
                label: Text('REGRESO',
                    style: TextStyle(
                        color: c.ink3,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1))),
            DataColumn(
                label: Text('ESTATUS',
                    style: TextStyle(
                        color: c.ink3,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1))),
            DataColumn(
                label: const SizedBox(width: 40)), // Acciones
          ],
          source: () {
            _dataSource ??= _IncidenciasDataSource(
              items: _incidencias,
              theme: theme,
              isAdmin: _userRole == 'admin',
              userProfile: _selectedUserProfile,
              formatDate: _formatDate,
              siColors: c,
              getStatusColor: _getStatusColor,
              onEdit: (inc) => _showIncidenciaForm(incidencia: inc),
              onDelete: _eliminarIncidencia,
              sePuedeEliminar: _sePuedeEliminar,
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
                  // El aviso lo manda un disparador de la base -`notificar_cambio_de_estatus`- que avisa a
                  // quien pidio las vacaciones y a Desarrollo Humano, por campana y por WhatsApp.
                  //
                  // Estaba escrito TRES veces, una por cada menu de esta pagina, y aun asi faltaba en el cuarto
                  // camino: aprobar por WhatsApp pasa por `actualizar_incidencia` de Soli, que no notificaba. Es
                  // justo lo que se reporto -Marco aprobo por WhatsApp y no le llego a nadie-. En la base esta
                  // una vez y cubre los cuatro.
                  _fetchIncidencias();
                }
              },
            );
            return _dataSource!;
          }(),
          rowsPerPage: _incidencias.isEmpty
              ? 1
              : (_incidencias.length > 5 ? 5 : _incidencias.length),
          showCheckboxColumn: false,
        ),
      ),
    );
  }

  /// Widget de autocomplete compartido para móvil y escritorio
  Widget _buildUserAutocomplete(SiColors c, {double maxWidth = 300}) {
    String _fullName(Map<String, dynamic> u) =>
        '${u['nombre'] ?? ''} ${u['paterno'] ?? ''} ${u['materno'] ?? ''}'
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

    final selectedUser = _adminUserList.isEmpty
        ? null
        : _adminUserList.firstWhere(
            (u) => u['id'] == _selectedUserId,
            orElse: () => _adminUserList.first,
          );
    final initialText = selectedUser != null ? _fullName(selectedUser) : '';

    return Autocomplete<Map<String, dynamic>>(
      key: ValueKey(_selectedUserId),
      initialValue: TextEditingValue(text: initialText),
      optionsBuilder: (textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) return _adminUserList;
        return _adminUserList.where(
          (u) => _fullName(u).toLowerCase().contains(q),
        );
      },
      displayStringForOption: _fullName,
      onSelected: (user) => _onUserSelected(user['id'] as String),
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return SizedBox(
          height: 38,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            style: TextStyle(fontSize: 13, color: c.ink),
            decoration: InputDecoration(
              hintText: 'Buscar colaborador…',
              hintStyle: TextStyle(fontSize: 13, color: c.ink3),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: c.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: c.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: c.brand, width: 1.5),
              ),
              prefixIcon: Icon(Icons.search_rounded, size: 16, color: c.ink3),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, val, __) => val.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close_rounded,
                            size: 14, color: c.ink3),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          controller.clear();
                          focusNode.requestFocus();
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            color: c.panel,
            shadowColor: Colors.black26,
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxHeight: 260, maxWidth: maxWidth),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final user = options.elementAt(index);
                    final name = _fullName(user);
                    final isSelected = user['id'] == _selectedUserId;
                    return InkWell(
                      onTap: () => onSelected(user),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        color: isSelected
                            ? c.brand.withOpacity(0.08)
                            : Colors.transparent,
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 13,
                            color: isSelected ? c.brand : c.ink,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableUserSelector(SiColors c) {
    return _buildUserAutocomplete(c, maxWidth: 320);
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
                    _buildResumenMensual(c),
                    SizedBox(height: SiSpace.x6),
                  ],

                  // Main Content Grid
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isDesktop = constraints.maxWidth > 1100;
                      if (isDesktop) {
                        // Arriba, mitad y mitad: la tabla de registros y el calendario. Abajo, la
                        // fila partida en tres: antigüedad se lleva un tercio y el historial de
                        // vacaciones los otros dos, que es el que tiene tabla y necesita el ancho.
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Sin solicitudes el calendario no se pinta, así que la tabla se queda
                            // con todo el ancho en vez de apretarse contra media página vacía.
                            if (_incidencias.isEmpty)
                              _buildDesktopTable(c)
                            else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _buildDesktopTable(c)),
                                  SizedBox(width: SiSpace.x6),
                                  Expanded(child: _buildIncidenciasCalendar()),
                                ],
                              ),
                            SizedBox(height: SiSpace.x6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildAntiguedadDesktop()),
                                SizedBox(width: SiSpace.x6),
                                Expanded(child: _buildHistorialVacaciones()),
                                SizedBox(width: SiSpace.x6),
                                Expanded(
                                  child: GraficaVacacionesPorMes(
                                      incidencias: _incidencias),
                                ),
                              ],
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            _buildAntiguedadMobile(),
                            SizedBox(height: SiSpace.x4),
                            _buildIncidenciasCalendar(),
                            if (_incidencias.isNotEmpty)
                              SizedBox(height: SiSpace.x4),
                            _buildHistorialVacaciones(),
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


  Widget _buildIncidenciasCalendar() {
    if (_incidencias.isEmpty) return const SizedBox.shrink();
    return CalendarioIncidencias(
      incidencias: _incidencias,
      colorDeEstatus: _getStatusColor,
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
  List<Map<String, dynamic>> items;
  final ThemeData theme;
  final bool isAdmin;
  final Map<String, dynamic>? userProfile;
  final String Function(String) formatDate;
  final SiColors siColors;

  final Color Function(String) getStatusColor;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>, String) onStatusChange;
  /// Manda la incidencia a la papelera. Va como callback y no resuelto aqui porque el dialogo de
  /// confirmacion y el refresco son de la pagina, no de la tabla.
  final Function(Map<String, dynamic>) onDelete;
  /// Si esta fila se puede eliminar. Lo decide la pagina -`_sePuedeEliminar`- para que la regla viva
  /// en UN sitio: la tabla no tiene por que saber que una APROBADA no se toca.
  final bool Function(Map<String, dynamic>) sePuedeEliminar;

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
    required this.onDelete,
    required this.sePuedeEliminar,
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
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ),
        DataCell(Text('${inc['dias'] ?? '-'}',
            style: const TextStyle(fontSize: 13))),
        DataCell(Text(formatDate(inc['created_at']),
            style: const TextStyle(fontSize: 13))),
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                inc['fecha_inicio'] != null ? formatDate(inc['fecha_inicio']) : '-',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              Text(
                inc['fecha_fin'] != null ? formatDate(inc['fecha_fin']) : '-',
                style: TextStyle(fontSize: 11, color: siColors.ink3),
              ),
            ],
          ),
        ),
        DataCell(Text(
          inc['fecha_regreso'] != null ? formatDate(inc['fecha_regreso']) : '-',
          style: const TextStyle(fontSize: 13),
        )),
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
          SizedBox(
            width: 40,
            child: PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz, color: siColors.ink3, size: 20),
              tooltip: 'Acciones',
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              onSelected: (val) {
                if (val == 'EDIT') {
                  onEdit(inc);
                } else if (val == 'DELETE') {
                  onDelete(inc);
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
                // Separado del resto y detrás de una línea: «Cancelar» y «Eliminar» están a un pixel
                // el uno del otro y hacen cosas muy distintas.
                if (sePuedeEliminar(inc)) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'DELETE',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            size: 18, color: Colors.red[700]),
                        const SizedBox(width: 12),
                        Text('Enviar a la papelera',
                            style: TextStyle(
                                fontSize: 13, color: Colors.red[700])),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    ],
    );
  }

  /// Actualiza los datos y notifica a PaginatedDataTable para que se redibuje.
  void updateItems(List<Map<String, dynamic>> newItems) {
    items = newItems;
    notifyListeners();
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => items.length;

  @override
  int get selectedRowCount => 0;
}
