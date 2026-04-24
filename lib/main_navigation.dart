import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_dashboard.dart';
import 'usuarios_page.dart';
import 'system_logs_page.dart';
import 'issi_page.dart';
import 'cssi_page.dart';
import 'incidencias_page.dart';
import 'social_page.dart';
import 'external_contacts_page.dart';
import 'widgets/notification_bell.dart';
import 'calendar_page.dart';
import 'attendance_hub_page.dart';
import 'bi_page.dart';
import 'signature_generator_page.dart';

class MainNavigation extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;
  const MainNavigation(
      {super.key, required this.role, required this.permissions});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  String? _selectedEventId;

  List<Map<String, dynamic>> get _availablePages {
    final pages = <Map<String, dynamic>>[];

    pages.add({
      'title': 'Mi Perfil',
      'icon': Icons.person_outline,
      'activeIcon': Icons.person,
      'widget': const UserDashboard(),
    });

    pages.add({
      'title': 'Social',
      'icon': Icons.diversity_3_outlined,
      'activeIcon': Icons.diversity_3,
      'widget': const SocialPage(),
    });

    pages.add({
      'title': 'Firmas',
      'icon': Icons.draw_outlined,
      'activeIcon': Icons.draw,
      'widget': const SignatureGeneratorPage(),
    });

    if (widget.permissions['show_calendar'] == true) {
      pages.add({
        'title': 'Calendario',
        'icon': Icons.calendar_month_outlined,
        'activeIcon': Icons.calendar_month,
        'widget': CalendarPage(initialEventId: _selectedEventId),
      });
    }

    if (widget.permissions['show_incidencias'] == true) {
      pages.add({
        'title': 'Incidencias',
        'icon': Icons.description_outlined,
        'activeIcon': Icons.description,
        'widget': const IncidenciasPage(),
      });
    }

    if (widget.permissions['show_users'] == true) {
      pages.add({
        'title': 'Usuarios',
        'icon': Icons.group_outlined,
        'activeIcon': Icons.group,
        'widget': const AdminDashboard(),
      });
    }

    if (widget.permissions['show_issi'] == true) {
      pages.add({
        'title': 'Inventario',
        'icon': Icons.inventory_2_outlined,
        'activeIcon': Icons.inventory_2,
        'widget': const IssiPage(),
      });
    }

    if (widget.permissions['show_cssi'] == true) {
      pages.add({
        'title': 'Colaborador',
        'icon': Icons.badge_outlined,
        'activeIcon': Icons.badge,
        'widget': CssiPage(role: widget.role),
      });
    }

    if (widget.permissions['show_logs'] == true) {
      pages.add({
        'title': 'Logs',
        'icon': Icons.assignment_outlined,
        'activeIcon': Icons.assignment,
        'widget': const SystemLogsPage(),
      });
    }

    if (widget.permissions['show_external_contacts'] == true) {
      pages.add({
        'title': 'Contactos',
        'icon': Icons.contact_phone_outlined,
        'activeIcon': Icons.contact_phone,
        'widget': const ExternalContactsPage(),
      });
    }

    if (widget.permissions['show_asistencia'] == true) {
      pages.add({
        'title': 'Asistencia',
        'icon': Icons.fingerprint,
        'activeIcon': Icons.fingerprint,
        'widget': AttendanceHubPage(
            role: widget.role, permissions: widget.permissions),
      });
    }

    if (widget.permissions['show_powerbi'] == true) {
      pages.add({
        'title': 'BI',
        'icon': Icons.bar_chart_outlined,
        'activeIcon': Icons.bar_chart,
        'widget': BiPage(role: widget.role, permissions: widget.permissions),
      });
    }

    return pages;
  }

  void _onNavigateToCalendar(String? eventId, List<Map<String, dynamic>> pages) {
    final calendarIndex = pages.indexWhere((p) => p['title'] == 'Calendario');
    if (calendarIndex != -1) {
      setState(() {
        _selectedIndex = calendarIndex;
        _selectedEventId = eventId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = _availablePages;

    if (_selectedIndex >= pages.length) {
      _selectedIndex = 0;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;
        return isDesktop
            ? _buildDesktopLayout(theme, pages)
            : _buildMobileLayout(theme, pages);
      },
    );
  }

  // ─── DESKTOP: NavigationRail lateral ─────────────────────────────────────

  Widget _buildDesktopLayout(
      ThemeData theme, List<Map<String, dynamic>> pages) {
    return Scaffold(
      appBar: AppBar(
        title: Text(pages[_selectedIndex]['title']),
        actions: [
          NotificationBell(
            role: widget.role,
            permissions: widget.permissions,
            currentUserId:
                Supabase.instance.client.auth.currentUser?.id ?? '',
            onNavigateToCalendar: (eventId) =>
                _onNavigateToCalendar(eventId, pages),
          ),
        ],
      ),
      body: Row(
        children: [
          // ── NavigationRail azul ──────────────────────────────────────────
          NavigationRail(
            backgroundColor: const Color(0xFF344092),
            selectedIndex: _selectedIndex,
            minWidth: 76,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
                _selectedEventId = null;
              });
            },
            labelType: NavigationRailLabelType.all,
            indicatorColor: Colors.white,
            selectedIconTheme:
                const IconThemeData(color: Color(0xFF344092), size: 22),
            unselectedIconTheme:
                const IconThemeData(color: Colors.white70, size: 22),
            selectedLabelTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
            unselectedLabelTextStyle: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
            leading: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              child: Image.asset(
                'assets/logo.png',
                height: 38,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.apps,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            trailing: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Divider(color: Colors.white.withOpacity(0.15), height: 1),
                  const SizedBox(height: 8),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white70, size: 22),
                    tooltip: 'Cerrar sesión',
                    onPressed: () async {
                      try {
                        final user = Supabase.instance.client.auth.currentUser;
                        await Supabase.instance.client.rpc('log_event', params: {
                          'action_type_param': 'CIERRE DE SESIÓN',
                          'target_info_param': 'Usuario: ${user?.email ?? '---'}',
                        });
                      } catch (_) {}
                      await Supabase.instance.client.auth.signOut();
                    },
                  ),
                ],
              ),
            ),
            destinations: pages
                .map(
                  (p) => NavigationRailDestination(
                    icon: Icon(p['icon']),
                    selectedIcon: Icon(p['activeIcon']),
                    label: Text(p['title']),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                )
                .toList(),
          ),
          // Línea divisoria sutil
          const VerticalDivider(thickness: 1, width: 1),
          // ── Contenido principal ──────────────────────────────────────────
          Expanded(
            child: pages[_selectedIndex]['widget'],
          ),
        ],
      ),
    );
  }

  // ─── MÓVIL: Drawer (sidebar) ─────────────────────────────────────────────

  Widget _buildMobileLayout(
      ThemeData theme, List<Map<String, dynamic>> pages) {
    return Scaffold(
      appBar: AppBar(
        title: Text(pages[_selectedIndex]['title']),
        // El ícono de hamburguesa se agrega automáticamente al haber un Drawer
        actions: [
          NotificationBell(
            role: widget.role,
            permissions: widget.permissions,
            currentUserId:
                Supabase.instance.client.auth.currentUser?.id ?? '',
            onNavigateToCalendar: (eventId) =>
                _onNavigateToCalendar(eventId, pages),
          ),
        ],
      ),
      drawer: _buildDrawer(theme, pages),
      body: pages[_selectedIndex]['widget'],
    );
  }

  Widget _buildDrawer(ThemeData theme, List<Map<String, dynamic>> pages) {
    return Drawer(
      backgroundColor: const Color(0xFF344092),
      child: SafeArea(
        child: Column(
          children: [
            // ── Cabecera del drawer ───────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.apps, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'App Sisol',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.role.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
            const SizedBox(height: 8),
            // ── Ítems de navegación ───────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: pages.length,
                itemBuilder: (context, index) {
                  final page = pages[index];
                  final isSelected = _selectedIndex == index;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: ListTile(
                      selected: isSelected,
                      selectedTileColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(
                        isSelected ? page['activeIcon'] : page['icon'],
                        color: isSelected
                            ? const Color(0xFF344092)
                            : Colors.white70,
                        size: 22,
                      ),
                      title: Text(
                        page['title'],
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF344092)
                              : Colors.white,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedIndex = index;
                          _selectedEventId = null;
                        });
                        Navigator.pop(context); // cierra el drawer
                      },
                    ),
                  );
                },
              ),
            ),
            // ── Pie del drawer: cerrar sesión ─────────────────────────────
            Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading:
                  const Icon(Icons.logout, color: Colors.white70, size: 22),
              title: const Text(
                'Cerrar sesión',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              onTap: () async {
                Navigator.pop(context);
                await Supabase.instance.client.auth.signOut();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
