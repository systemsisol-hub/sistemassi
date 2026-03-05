import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import 'widgets/page_header.dart';

class SocialPage extends StatefulWidget {
  const SocialPage({super.key});

  @override
  State<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends State<SocialPage> {
  List<Map<String, dynamic>> _allBirthdays = [];
  bool _isLoading = true;
  int _selectedMonth = DateTime.now().month;

  final List<String> _months = [
    'ENERO', 'FEBRERO', 'MARZO', 'ABRIL', 'MAYO', 'JUNIO',
    'JULIO', 'AGOSTO', 'SEPTIEMBRE', 'OCTUBRE', 'NOVIEMBRE', 'DICIEMBRE'
  ];

  @override
  void initState() {
    super.initState();
    _fetchBirthdays();
  }

  Future<void> _fetchBirthdays() async {
    setState(() => _isLoading = true);
    try {
      // Obtenemos todos los colaboradores que tengan fecha de nacimiento
      final data = await Supabase.instance.client
          .from('profiles')
          .select('nombre, paterno, materno, fecha_nacimiento, foto_url, ubicacion')
          .not('fecha_nacimiento', 'is', null)
          .neq('status_rh', 'BAJA')
          .eq('status_sys', 'ACTIVO')
          .order('nombre');

      if (mounted) {
        setState(() {
          _allBirthdays = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching birthdays: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar cumpleaños: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredBirthdays {
    return _allBirthdays.where((item) {
      final fechaStr = item['fecha_nacimiento'] as String?;
      if (fechaStr == null || fechaStr.isEmpty) return false;
      try {
        final date = DateTime.parse(fechaStr);
        return date.month == _selectedMonth;
      } catch (_) {
        return false;
      }
    }).toList()
      ..sort((a, b) {
        final dateA = DateTime.parse(a['fecha_nacimiento']);
        final dateB = DateTime.parse(b['fecha_nacimiento']);
        return dateA.day.compareTo(dateB.day);
      });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upcoming = _filteredBirthdays;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? Center(
              child: Image.asset(
                'assets/sisol_loader.gif',
                width: 150,
                errorBuilder: (context, error, stackTrace) => const CircularProgressIndicator(),
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                    frame == null ? const CircularProgressIndicator() : child,
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Birthday Section Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Cumpleaños 🎂',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF344092)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: _selectedMonth,
                                  dropdownColor: Colors.white,
                                  icon: const Icon(Icons.calendar_month, color: Color(0xFF344092), size: 20),
                                  items: List.generate(12, (index) => DropdownMenuItem(
                                    value: index + 1,
                                    child: Text(
                                      _months[index],
                                      style: const TextStyle(color: Color(0xFF344092), fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  )),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedMonth = val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Celebrando a nuestros colaboradores en ${_months[_selectedMonth - 1]}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                        const SizedBox(height: 24),
                        
                        // Birthday List or Empty State
                        upcoming.isEmpty
                            ? _buildEmptyState()
                            : _buildBirthdayList(upcoming, theme),
                            
                        // Space for future sections
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBirthdayList(List<Map<String, dynamic>> items, ThemeData theme) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Column(
        children: List.generate(items.length, (index) {
              final item = items[index];
              final date = DateTime.parse(item['fecha_nacimiento']);
              final isToday = date.day == DateTime.now().day && date.month == DateTime.now().month;

              return Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                          backgroundImage: item['foto_url'] != null ? NetworkImage(item['foto_url']) : null,
                          child: item['foto_url'] == null 
                            ? Icon(Icons.person, color: theme.colorScheme.primary, size: 30)
                            : null,
                        ),
                        if (isToday)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: const Text('👑', style: TextStyle(fontSize: 14)),
                            ),
                          ),
                      ],
                    ),
                    title: Text(
                      '${item['nombre']} ${item['paterno']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    subtitle: Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item['ubicacion'] ?? 'SIN UBICACIÓN',
                            style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 24, 
                            fontWeight: FontWeight.bold, 
                            color: isToday ? Colors.orange : theme.colorScheme.primary
                          ),
                        ),
                        if (isToday)
                          const Text(
                            'HOY',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
                          ),
                      ],
                    ),
                    onTap: () {}, // Efecto visual al tocar
                  ),
                  if (index < items.length - 1)
                    Divider(height: 1, indent: 84, endIndent: 16, color: Colors.grey[200]),
                ],
              );
            }),
          ),
        );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cake_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No hay cumpleaños en ${_months[_selectedMonth - 1].toLowerCase()}',
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
        ],
      ),
    );
  }
}
