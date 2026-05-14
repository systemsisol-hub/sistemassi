import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'widgets/page_header.dart';
import 'calendar_event_form_dialog.dart';
import 'theme/si_theme.dart';

class SocialPage extends StatefulWidget {
  const SocialPage({super.key});

  @override
  State<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends State<SocialPage> {
  List<Map<String, dynamic>> _allBirthdays = [];
  List<Map<String, dynamic>> _weeklyEvents = [];
  bool _isLoading = true;
  bool _isLoadingEvents = false;
  int _selectedMonth = DateTime.now().month;

  final List<String> _months = [
    'ENERO', 'FEBRERO', 'MARZO', 'ABRIL', 'MAYO', 'JUNIO',
    'JULIO', 'AGOSTO', 'SEPTIEMBRE', 'OCTUBRE', 'NOVIEMBRE', 'DICIEMBRE'
  ];

  @override
  void initState() {
    super.initState();
    _fetchBirthdays();
    _fetchWeeklyEvents();
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
          SnackBar(content: Text('Error al cargar cumpleaños: $e'), backgroundColor: SiColors.of(context).danger),
        );
      }
    }
  }

  Future<void> _fetchWeeklyEvents() async {
    setState(() => _isLoadingEvents = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final now = DateTime.now();
      // Compute exact Monday 00:00:00 and Sunday 23:59:59 in LOCAL time
      final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1), 0, 0, 0);
      final sunday = DateTime(now.year, now.month, now.day - (now.weekday - 1) + 6, 23, 59, 59);

      // Get event IDs where user is an invitee
      final invitations = await Supabase.instance.client
          .from('event_invitations')
          .select('event_id')
          .eq('user_id', userId);
      final invitedIds = invitations
          .map((i) => i['event_id'].toString())
          .toList();

      // Build OR filter: own events, public events, or invited events
      String orFilter = 'creator_id.eq.$userId,is_public.eq.true';
      if (invitedIds.isNotEmpty) {
        orFilter += ',id.in.(${invitedIds.join(',')})';
      }

      final response = await Supabase.instance.client
          .from('events')
          .select('id, title, start_time, end_time, location, is_public, priority')
          .gte('start_time', monday.toUtc().toIso8601String())
          .lte('start_time', sunday.toUtc().toIso8601String())
          .or(orFilter)
          .order('start_time', ascending: true);

      if (mounted) {
        setState(() {
          _weeklyEvents = List<Map<String, dynamic>>.from(response);
          _isLoadingEvents = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching weekly events: $e');
      if (mounted) setState(() => _isLoadingEvents = false);
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
    final c = SiColors.of(context);
    final theme = Theme.of(context);
    final upcoming = _filteredBirthdays;
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: c.bg,
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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: isDesktop 
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column: Birthdays
                          Expanded(
                            flex: 1,
                            child: _buildBirthdaySection(upcoming, theme),
                          ),
                          const SizedBox(width: 24),
                          // Middle Column (Weekly Events)
                          Expanded(
                            flex: 1,
                            child: _buildWeeklyEventsSection(),
                          ),
                          const SizedBox(width: 24),
                          // Right Column (Future Section)
                          Expanded(
                            flex: 1,
                            child: _buildPlaceholderSection('Próximamente', Icons.upcoming_outlined),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _buildBirthdaySection(upcoming, theme),
                          const SizedBox(height: 24),
                          _buildWeeklyEventsSection(),
                        ],
                      ),
                ),
              ),
            ),
    );
  }


  Widget _buildWeeklyEventsSection() {
    final c = SiColors.of(context);
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final sunday = DateTime(now.year, now.month, now.day - (now.weekday - 1) + 6);
    final dateRange = '${DateFormat('dd MMM', 'es_MX').format(monday)} – ${DateFormat('dd MMM', 'es_MX').format(sunday)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFB1CB34), Color(0xFF8FAA20)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB1CB34).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Eventos esta semana 📅',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                dateRange,
                style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            border: Border.all(color: c.line2),
          ),
          child: _isLoadingEvents
              ? Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Image.asset(
                      'assets/sisol_loader.gif',
                      width: 80,
                      errorBuilder: (ctx, e, s) => const CircularProgressIndicator(),
                      frameBuilder: (ctx, child, frame, _) =>
                          frame == null ? const CircularProgressIndicator() : child,
                    ),
                  ),
                )
              : _weeklyEvents.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.event_available_outlined, size: 40, color: c.line),
                            const SizedBox(height: 12),
                            Text(
                              'Sin eventos esta semana',
                              style: TextStyle(color: c.ink3, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: List.generate(_weeklyEvents.length, (index) {
                        final ev = _weeklyEvents[index];
                        final start = DateTime.parse(ev['start_time']).toLocal();
                        final isToday = start.day == now.day && start.month == now.month && start.year == now.year;
                        final isPublic = ev['is_public'] == true;
                        final priority = ev['priority'] as String? ?? 'Normal';
                        final isHigh = priority == 'Alta';

                        Color bgColor;
                        Color iconColor;
                        IconData iconData;

                        if (isHigh) {
                          bgColor = c.dangerTint;
                          iconColor = c.danger;
                          iconData = Icons.priority_high;
                        } else if (isPublic) {
                          bgColor = c.successTint;
                          iconColor = c.success;
                          iconData = Icons.groups;
                        } else {
                          bgColor = c.brandTint;
                          iconColor = c.brand;
                          iconData = Icons.person;
                        }

                        return Column(
                          children: [
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  iconData,
                                  size: 20,
                                  color: iconColor,
                                ),
                              ),
                              title: Text(
                                ev['title'] ?? 'Sin título',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              subtitle: Text(
                                DateFormat('EEE dd MMM, HH:mm', 'es_MX').format(start),
                                style: TextStyle(fontSize: 11, color: isToday ? c.warn : c.ink3),
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (isHigh)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: c.dangerTint,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: c.danger),
                                      ),
                                      child: Text('ALTA', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: c.danger)),
                                    ),
                                  if (isToday)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: c.warnTint,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: c.warn),
                                      ),
                                      child: Text('HOY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: c.warn)),
                                    ),
                                ],
                              ),
                              onTap: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) => EventFormDialog(eventId: ev['id'].toString()),
                                );
                              },
                            ),
                            if (index < _weeklyEvents.length - 1)
                              Divider(height: 1, indent: 64, endIndent: 12, color: c.line2),
                          ],
                        );
                      }),
                    ),
        ),
      ],
    );
  }

  Widget _buildBirthdaySection(List<Map<String, dynamic>> upcoming, ThemeData theme) {
    final c = SiColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Birthday Section Header with Gradient
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF344092), Color(0xFF515DBB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF344092).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Cumpleaños 🎂',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedMonth,
                    dropdownColor: const Color(0xFF344092),
                    icon: const Icon(Icons.calendar_month, color: Colors.white, size: 16),
                    items: List.generate(12, (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text(
                        _months[index],
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
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
        ),
        
        // Content Area
        Container(
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
            border: Border.all(color: c.line2),
          ),
          child: upcoming.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: _buildEmptyState(),
                )
              : _buildBirthdayList(upcoming, theme),
        ),
      ],
    );
  }

  Widget _buildBirthdayList(List<Map<String, dynamic>> items, ThemeData theme) {
    final c = SiColors.of(context);
    return Column(
      children: List.generate(items.length, (index) {
        final item = items[index];
        final date = DateTime.parse(item['fecha_nacimiento']);
        final isToday = date.day == DateTime.now().day && date.month == DateTime.now().month;

        return Column(
          children: [
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: Stack(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                    backgroundImage: item['foto_url'] != null ? NetworkImage(item['foto_url']) : null,
                    child: item['foto_url'] == null 
                      ? Icon(Icons.person, color: theme.colorScheme.primary, size: 20)
                      : null,
                  ),
                  if (isToday)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(color: c.panel, shape: BoxShape.circle),
                        child: const Text('👑', style: TextStyle(fontSize: 10)),
                      ),
                    ),
                ],
              ),
              title: Text(
                '${item['nombre']} ${item['paterno']}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              subtitle: Text(
                item['ubicacion'] ?? 'SIN UBICACIÓN',
                style: TextStyle(color: c.ink3, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 16, 
                      fontWeight: FontWeight.bold, 
                      color: isToday ? c.warn : theme.colorScheme.primary
                    ),
                  ),
                  if (isToday)
                    Text(
                      'HOY',
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: c.warn),
                    ),
                ],
              ),
              onTap: () {},
            ),
            if (index < items.length - 1)
              Divider(height: 1, indent: 64, endIndent: 12, color: c.line2),
          ],
        );
      }),
    );
  }

  Widget _buildEmptyState() {
    final c = SiColors.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cake_outlined, size: 48, color: c.line),
          const SizedBox(height: 12),
          Text(
            'No hay cumpleaños en ${_months[_selectedMonth - 1]}',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.ink3, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderSection(String title, IconData icon) {
    final c = SiColors.of(context);
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.line2),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: c.line2),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: c.line, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
