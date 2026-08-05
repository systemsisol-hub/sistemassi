import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

/// Administración de horarios. Es lo único que quedó de la página de Asistencia: el checador y
/// su panel administrativo se retiraron.
///
/// Antes se dibujaba sin Scaffold porque vivía incrustada en ese panel. Ahora es una página
/// completa, con los parámetros del modo incrustado retirados.
class SchedulesPage extends StatefulWidget {
  const SchedulesPage({super.key});

  @override
  State<SchedulesPage> createState() => _SchedulesPageState();
}

class _SchedulesPageState extends State<SchedulesPage> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _schedules = [];
  String _searchQuery = '';

  /// Tolerancia fija para la entrada, en minutos. Antes era configurable por horario; se
  /// unificó para que el criterio de retardo sea el mismo en toda la empresa.
  static const _toleranciaMin = 15;

  static const _entradaPorDefecto = TimeOfDay(hour: 8, minute: 0);
  static const _salidaPorDefecto = TimeOfDay(hour: 18, minute: 0);

  // Form State
  final _nameController = TextEditingController();
  final _zoneController = TextEditingController();

  /// Horario por día, cada uno independiente. Un día presente en el mapa está activo; su
  /// ausencia significa que no se trabaja ese día.
  final Map<int, TimeOfDay> _entradaPorDia = {};
  final Map<int, TimeOfDay> _salidaPorDia = {};

  final List<String> _daysOfWeek = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];

  @override
  void initState() {
    super.initState();
    _fetchSchedules();
  }

  Future<void> _fetchSchedules() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supabase.from('schedules').select().order('name');
      setState(() {
        _schedules = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching schedules: $e');
      setState(() => _isLoading = false);
    }
  }


  /// "HH:mm:00", el formato que espera la columna rules.
  static String _hhmmss(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  /// Dos reglas por día activo: ENTRADA con tolerancia y SALIDA sin ella. Cada día lleva su
  /// propia hora, así que un horario puede tener jornadas distintas entre semana y sábado.
  List<Map<String, dynamic>> _construirReglas() {
    final dias = _entradaPorDia.keys.toList()..sort();
    return [
      for (final day in dias) ...[
        {
          'day': day,
          'type': 'ENTRADA',
          'time': _hhmmss(_entradaPorDia[day]!),
          'tol': _toleranciaMin,
        },
        {
          'day': day,
          'type': 'SALIDA',
          'time': _hhmmss(_salidaPorDia[day] ?? _salidaPorDefecto),
          'tol': 0,
        },
      ],
    ];
  }

  Future<void> _saveSchedule() async {
    final reglas = _construirReglas();

    if (_nameController.text.trim().isEmpty || reglas.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor ingresa un nombre y activa al menos un día.')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _supabase.from('schedules').insert({
        'name': _nameController.text.trim(),
        'zone': _zoneController.text.trim(),
        'rules': reglas,
      });

      _nameController.clear();
      _zoneController.clear();
      setState(() {
        _entradaPorDia.clear();
        _salidaPorDia.clear();
        _isLoading = false;
      });
      _fetchSchedules();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Horario maestro creado con éxito ✅')),
        );
      }
    } catch (e) {
      debugPrint('Error saving schedule: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    }
  }

  Future<void> _deleteSchedule(String id) async {
    final c = SiColors.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Horario'),
        content: const Text('¿Estás seguro de eliminar este horario maestro?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text('ELIMINAR')
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _supabase.from('schedules').delete().eq('id', id);
        _fetchSchedules();
      } catch (e) {
        debugPrint('Error deleting schedule: $e');
      }
    }
  }

  void showScheduleForm() {
    _nameController.clear();
    _zoneController.clear();
    _entradaPorDia.clear();
    _salidaPorDia.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          final c = SiColors.of(context);
          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              children: [
                // Header (Top Bar)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancelar', style: TextStyle(color: c.ink3)),
                      ),
                      const Text(
                        'Nuevo Horario',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () {
                          if (_nameController.text.trim().isEmpty ||
                              _entradaPorDia.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Por favor ingresa un nombre y activa al menos un día.')),
                            );
                            return;
                          }
                          _saveSchedule();
                          Navigator.pop(context);
                        },
                        child: Text('Añadir', style: TextStyle(fontWeight: FontWeight.bold, color: c.brand)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildFormLogic(theme, setModalState, c),
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildFormLogic(ThemeData theme, StateSetter setModalState, SiColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Identificación
        _buildIconInput(
          controller: _nameController,
          label: 'Título del horario',
          hint: 'Ej. Corporativo, Nocturno...',
          icon: Icons.title,
          c: c,
        ),
        const SizedBox(height: 16),
        _buildIconInput(
          controller: _zoneController,
          label: 'Zona / Ubicación',
          hint: 'Añadir ubicación',
          icon: Icons.location_on_outlined,
          c: c,
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 24),

        // Quick Define
        _buildQuickDefineRow(theme, setModalState, c),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildIconInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required SiColors c,
  }) {
    return Row(
      children: [
        const SizedBox(width: 8), // Más espacio a la izquierda antes del icono
        Icon(icon, color: c.ink4, size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              hintStyle: TextStyle(color: c.line),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.line2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.line2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickDefineRow(ThemeData theme, StateSetter setModalState, SiColors c) {
    final activos = _entradaPorDia.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.timer_outlined, color: c.ink4, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Tolerancia de $_toleranciaMin minutos en la entrada, igual para todos los días.',
                style: TextStyle(fontSize: 12, color: c.ink3, height: 1.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 20),
        Row(
          children: [
            Text('Días y horario',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13, color: c.ink2)),
            const Spacer(),
            // Con jornadas iguales toda la semana, capturar 7 días por separado sería tedioso;
            // esto copia el primer día activo a los demás y luego se puede ajustar el que
            // difiera, como el sábado.
            if (activos.length > 1)
              TextButton(
                onPressed: () => setModalState(() {
                  final entrada = _entradaPorDia[activos.first]!;
                  final salida = _salidaPorDia[activos.first] ?? _salidaPorDefecto;
                  for (final d in activos) {
                    _entradaPorDia[d] = entrada;
                    _salidaPorDia[d] = salida;
                  }
                }),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text('Igualar al ${_daysOfWeek[activos.first].toLowerCase()}',
                    style: TextStyle(fontSize: 11, color: c.brand)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        ...List.generate(7, (i) => _buildDiaFila(i, setModalState, c)),
        const SizedBox(height: 8),
        if (activos.isEmpty)
          Text('Activa al menos un día para definir su horario.',
              style: TextStyle(fontSize: 12, color: c.warn)),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Un día: interruptor y, si está activo, sus horas de entrada y salida.
  Widget _buildDiaFila(int dia, StateSetter setModalState, SiColors c) {
    final activo = _entradaPorDia.containsKey(dia);
    final entrada = _entradaPorDia[dia];
    final salida = _salidaPorDia[dia];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: activo ? c.brandTint : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: activo ? c.brand.withValues(alpha: 0.25) : c.line),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Switch(
              value: activo,
              onChanged: (val) => setModalState(() {
                if (val) {
                  // Se hereda del último día ya configurado: crear una semana completa no
                  // debería exigir capturar la misma hora siete veces.
                  final previos = _entradaPorDia.keys.toList()..sort();
                  final ref = previos.isEmpty ? null : previos.last;
                  _entradaPorDia[dia] =
                      ref == null ? _entradaPorDefecto : _entradaPorDia[ref]!;
                  _salidaPorDia[dia] = ref == null
                      ? _salidaPorDefecto
                      : (_salidaPorDia[ref] ?? _salidaPorDefecto);
                } else {
                  _entradaPorDia.remove(dia);
                  _salidaPorDia.remove(dia);
                }
              }),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _daysOfWeek[dia],
              style: TextStyle(
                fontSize: 15,
                fontWeight: activo ? FontWeight.w600 : FontWeight.normal,
                color: activo ? c.ink : c.ink3,
              ),
            ),
          ),
          if (activo) ...[
            _chipHora(
              hora: entrada!,
              c: c,
              tooltip: 'Entrada',
              onTap: () async {
                final t =
                    await showTimePicker(context: context, initialTime: entrada);
                if (t != null) setModalState(() => _entradaPorDia[dia] = t);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('→', style: TextStyle(color: c.ink4, fontSize: 13)),
            ),
            _chipHora(
              hora: salida ?? _salidaPorDefecto,
              c: c,
              tooltip: 'Salida',
              onTap: () async {
                final t = await showTimePicker(
                    context: context, initialTime: salida ?? _salidaPorDefecto);
                if (t != null) setModalState(() => _salidaPorDia[dia] = t);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipHora({
    required TimeOfDay hora,
    required SiColors c,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.line),
          ),
          child: Text(
            '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}',
            style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13, color: c.ink),
          ),
        ),
      ),
    );
  }




  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = SiColors.of(context);

    final filteredSchedules = _schedules.where((s) {
      final name = (s['name'] ?? '').toString().toLowerCase();
      final zone = (s['zone'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) ||
          zone.contains(_searchQuery.toLowerCase());
    }).toList();

    // Mismo andamio que el resto de las páginas: fondo de la app, barra de herramientas y
    // contenido desplazable.
    return Scaffold(
      backgroundColor: c.bg,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: c.brand))
          : Column(
              children: [
                _buildToolbar(c, theme),
                Expanded(
                  child: filteredSchedules.isEmpty
                      ? _buildVacio(c)
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(SiSpace.x6),
                          child: Center(
                            child: Card(
                              child: PaginatedDataTable(
                                columns: [
                                  DataColumn(
                                      label: Text('NOMBRE',
                                          style: TextStyle(
                                              color: c.ink3,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              letterSpacing: 1))),
                                  const DataColumn(label: SizedBox()), // Acciones
                                ],
                                source: _SchedulesDataSource(
                                  schedules: filteredSchedules,
                                  theme: theme,
                                  siColors: c,
                                  daysOfWeek: _daysOfWeek,
                                  onDelete: (id) => _deleteSchedule(id),
                                  onViewRules: (s) => _showRulesDialog(s),
                                ),
                                rowsPerPage: filteredSchedules.length > 10
                                    ? 10
                                    : filteredSchedules.length,
                                showCheckboxColumn: false,
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildToolbar(SiColors c, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SiSpace.x6, vertical: SiSpace.x4),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: SizedBox(
              height: 38,
              child: TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Buscar horario...',
                  hintStyle: TextStyle(color: c.ink4, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.line)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.line)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: c.brand)),
                  filled: true,
                  fillColor: c.bg,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: showScheduleForm,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('NUEVO',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.brand,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: const RoundedRectangleBorder(borderRadius: SiRadius.rMd),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVacio(SiColors c) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchQuery.isEmpty ? Icons.schedule_outlined : Icons.search_off,
            size: 56,
            color: c.line,
          ),
          const SizedBox(height: SiSpace.x4),
          Text(
            _searchQuery.isEmpty
                ? 'No hay horarios creados'
                : 'Sin resultados para "$_searchQuery"',
            style: TextStyle(color: c.ink3, fontSize: 15),
          ),
        ],
      ),
    );
  }

  void _showRulesDialog(Map<String, dynamic> sched) {
    final List<dynamic> rules = sched['rules'] ?? [];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reglas de Horario: ${sched['name']}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: rules.map((r) {
              final dayLabel = _daysOfWeek[r['day']];
              return ListTile(
                title: Text(dayLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${r['type']}: ${r['time'].toString().substring(0, 5)} ${r['type'] == 'ENTRADA' ? '(Tol: ${r['tol']}m)' : ''}'),
                dense: true,
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR')),
        ],
      ),
    );
  }
}

class _SchedulesDataSource extends DataTableSource {
  final List<Map<String, dynamic>> schedules;
  final ThemeData theme;
  final SiColors siColors;
  final List<String> daysOfWeek;
  final Function(String) onDelete;
  final Function(Map<String, dynamic>) onViewRules;

  _SchedulesDataSource({
    required this.schedules,
    required this.theme,
    required this.siColors,
    required this.daysOfWeek,
    required this.onDelete,
    required this.onViewRules,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= schedules.length) return null;
    final sched = schedules[index];

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(Text(sched['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Align(
          alignment: Alignment.centerRight,
          child: PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: siColors.ink3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'rules') onViewRules(sched);
              if (val == 'delete') onDelete(sched['id']);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'rules', child: ListTile(leading: Icon(Icons.rule_outlined), title: Text('Ver Reglas'), dense: true)),
              PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: siColors.danger), title: Text('Eliminar', style: TextStyle(color: siColors.danger)), dense: true)),
            ],
          ),
        )),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;
  @override
  int get rowCount => schedules.length;
  @override
  int get selectedRowCount => 0;
}
