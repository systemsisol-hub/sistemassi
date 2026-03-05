import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_dashboard.dart';
import 'admin_dashboard.dart';
import 'system_logs_page.dart';
import 'issi_page.dart';
import 'cssi_page.dart';
import 'incidencias_page.dart';
import 'social_page.dart';
import 'external_contacts_page.dart';
import 'widgets/notification_bell.dart';

class MainNavigation extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;
  const MainNavigation({super.key, required this.role, required this.permissions});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  List<Map<String, dynamic>> get _availablePages {
    final pages = <Map<String, dynamic>>[];
    
    // Perfil siempre disponible
    pages.add({
      'title': 'Mi Perfil',
      'icon': Icons.person_outline,
      'activeIcon': Icons.person,
      'widget': const UserDashboard(),
    });

    // Social siempre disponible
    pages.add({
      'title': 'Social',
      'icon': Icons.diversity_3_outlined,
      'activeIcon': Icons.diversity_3,
      'widget': const SocialPage(),
    });

    // Incidencias disponible según permisos
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
        'title': 'ISSI',
        'icon': Icons.inventory_2_outlined,
        'activeIcon': Icons.inventory_2,
        'widget': const IssiPage(),
      });
    }

    if (widget.permissions['show_cssi'] == true) {
      pages.add({
        'title': 'CSSI',
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

    return pages;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = _availablePages;
    
    // Safety check for index out of bounds if permissions change
    if (_selectedIndex >= pages.length) {
      _selectedIndex = 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(pages[_selectedIndex]['title']),
        actions: [
          NotificationBell(
            role: widget.role,
            permissions: widget.permissions,
            currentUserId: Supabase.instance.client.auth.currentUser?.id ?? '',
          ),
        ],
      ),
      body: pages[_selectedIndex]['widget'],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: pages.map((p) => BottomNavigationBarItem(
          icon: Icon(p['icon']),
          activeIcon: Icon(p['activeIcon']),
          label: p['title'],
        )).toList(),
      ),
    );
  }
}
