import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class SchedulesPage extends StatefulWidget {
  final bool hideAddButton;
  const SchedulesPage({super.key, this.hideAddButton = false});

  @override
  State<SchedulesPage> createState() => SchedulesPageState();
}

class SchedulesPageState extends State<SchedulesPage> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _schedules = [];

  // Form State
  final _nameController = TextEditingController();
  final _zoneController = TextEditingController();
  List<Map<String, dynamic>> _currentRules = [];

  // Rules Quick-Define state
  final Set<int> _selectedDays = {};
  TimeOfDay _tempIn = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _tempOut = const TimeOfDay(hour: 18, minute: 0);
  int _tempTolerance = 10;

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

  void _removeRule(int index) {
    setState(() {
      _currentRules.removeAt(index);
    });
  }

  Future<void> _saveSchedule() async {
    // Generación Automática: si el usuario ha marcado días, generamos las reglas antes de guardar
    if (_selectedDays.isNotEmpty) {
      _currentRules = []; // Limpiamos para evitar duplicidad si reintenta
      for (int day in _selectedDays) {
        _currentRules.add({
          'day': day, 
          'type': 'ENTRADA',
          'time': '${_tempIn.hour.toString().padLeft(2, '0')}:${_tempIn.minute.toString().padLeft(2, '0')}:00',
          'tol': _tempTolerance,
        });
        _currentRules.add({
          'day': day, 
          'type': 'SALIDA',
          'time': '${_tempOut.hour.toString().padLeft(2, '0')}:${_tempOut.minute.toString().padLeft(2, '0')}:00',
          'tol': 0,
        });
      }
    }

    if (_nameController.text.trim().isEmpty || _currentRules.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor ingresa un nombre y selecciona al menos un día.')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _supabase.from('schedules').insert({
        'name': _nameController.text.trim(),
        'zone': _zoneController.text.trim(),
        'rules': _currentRules,
      });

      _nameController.clear();
      _zoneController.clear();
      setState(() {
        _currentRules = [];
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Horario'),
        content: const Text('¿Estás seguro de eliminar este horario maestro?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
    _currentRules.clear();
    _selectedDays.clear();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
                        child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                      ),
                      const Text(
                        'Nuevo Horario',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () {
                          if (_nameController.text.trim().isEmpty || (_currentRules.isEmpty && _selectedDays.isEmpty)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Por favor ingresa un nombre y selecciona al menos un día.')),
                            );
                            return;
                          }
                          _saveSchedule();
                          Navigator.pop(context);
                        },
                        child: const Text('Añadir', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildFormLogic(theme, setModalState),
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildFormLogic(ThemeData theme, StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Identificación
        _buildIconInput(
          controller: _nameController,
          label: 'Título del horario',
          hint: 'Ej. Corporativo, Nocturno...',
          icon: Icons.title,
        ),
        const SizedBox(height: 16),
        _buildIconInput(
          controller: _zoneController,
          label: 'Zona / Ubicación',
          hint: 'Añadir ubicación',
          icon: Icons.location_on_outlined,
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 24),
        
        // Quick Define
        _buildQuickDefineRow(theme, setModalState),
        
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildIconInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Row(
      children: [
        const SizedBox(width: 8), // Más espacio a la izquierda antes del icono
        Icon(icon, color: Colors.grey[400], size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[300]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickDefineRow(ThemeData theme, StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTimeSelectionItem(
          label: 'Comienza',
          time: _tempIn,
          icon: Icons.access_time_outlined,
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: _tempIn);
            if (t != null) setModalState(() => _tempIn = t);
          },
        ),
        const SizedBox(height: 16),
        _buildTimeSelectionItem(
          label: 'Termina',
          time: _tempOut,
          icon: Icons.access_time_outlined,
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: _tempOut);
            if (t != null) setModalState(() => _tempOut = t);
          },
        ),
        const SizedBox(height: 16),
        // Tolerancia con mismo estilo
        Row(
          children: [
            Icon(Icons.timer_outlined, color: Colors.grey[400], size: 22),
            const SizedBox(width: 16),
            const Text('Tolerancia', style: TextStyle(fontSize: 16)),
            const Spacer(),
            DropdownButton<int>(
              value: _tempTolerance,
              underline: const SizedBox(),
              items: [0, 5, 10, 15, 20, 30].map((t) => DropdownMenuItem(value: t, child: Text('$t min'))).toList(),
              onChanged: (v) => setModalState(() => _tempTolerance = v!),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 24),
        const Text('Días de la semana', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
        const SizedBox(height: 8),
        ...List.generate(7, (i) {
          final active = _selectedDays.contains(i);
          return Transform.scale(
            scale: 0.85,
            alignment: Alignment.centerLeft,
            child: SwitchListTile(
              title: Text(_daysOfWeek[i], style: const TextStyle(fontSize: 17)), // Un poquito más grande el texto compensando la escala
              value: active,
              activeColor: theme.colorScheme.primary,
              onChanged: (val) {
                setModalState(() {
                  if (val) _selectedDays.add(i);
                  else _selectedDays.remove(i);
                });
              },
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          );
        }),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTimeSelectionItem({
    required String label,
    required TimeOfDay time,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey[400], size: 22),
        const SizedBox(width: 16),
        Text(label, style: const TextStyle(fontSize: 16)),
        const Spacer(),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }



  Widget _buildScheduleList(ThemeData theme) {
    if (_schedules.isEmpty) {
      if (_isLoading) return const Center(child: CircularProgressIndicator());
      return const Center(child: Text('No hay horarios registrados.'));
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _schedules.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final sched = _schedules[index];
        final List<dynamic> rules = sched['rules'] ?? [];
        
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(side: BorderSide.none),
            collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
              child: Icon(Icons.calendar_today_rounded, color: theme.colorScheme.primary, size: 20),
            ),
            title: Text(
              sched['name'], 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(
              'Zona: ${sched['zone'] ?? 'N/A'}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: () => _deleteSchedule(sched['id']),
            ),
            children: [
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: rules.map((r) {
                    final dayLabel = _daysOfWeek[r['day']];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              dayLabel, 
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Icon(Icons.access_time, size: 14, color: Colors.grey[400]),
                                const SizedBox(width: 8),
                                Text(
                                  '${r['type'] == 'ENTRADA' ? 'Entr' : 'Sali'}: ${r['time'].toString().substring(0, 5)}',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                                if (r['type'] == 'ENTRADA')
                                  Text(' (+${r['tol']}m)', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.hideAddButton)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: InkWell(
              onTap: showScheduleForm,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.colorScheme.primary, theme.colorScheme.primary.withOpacity(0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Nuevo Horario',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        _isLoading 
          ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: _buildScheduleList(theme),
              ),
      ],
    );
  }
}
