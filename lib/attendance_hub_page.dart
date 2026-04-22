import 'package:flutter/material.dart';
import 'checador_page.dart';
import 'attendance_admin_page.dart';

class AttendanceHubPage extends StatelessWidget {
  final String role;
  final Map<String, dynamic> permissions;

  const AttendanceHubPage(
      {super.key, required this.role, required this.permissions});

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = role == 'admin';

    // Construir lista dinámica de pestañas
    final List<Map<String, dynamic>> tabs = [
      {
        'title': 'Checador',
        'icon': Icons.timer_outlined,
        'widget': const ChecadorPage(),
      }
    ];

    if (isAdmin) {
      tabs.add({
        'title': 'Configuración',
        'icon': Icons.rule_outlined,
        'widget': AttendanceAdminPage(role: role, permissions: permissions),
      });
    }

    if (tabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Asistencia')),
        body: const Center(
            child: Text('No tienes permisos para ver estos módulos.')),
      );
    }

    final theme = Theme.of(context);

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            color: theme.appBarTheme.backgroundColor ?? theme.primaryColor,
            child: SafeArea(
              child: TabBar(
                isScrollable: tabs.length > 2,
                indicatorColor: Colors.white,
                indicatorWeight: 4,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white.withOpacity(0.6),
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                tabs: tabs
                    .map((t) => Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(t['icon'] as IconData, size: 20),
                              const SizedBox(width: 8),
                              Text(t['title'] as String),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: tabs.map((t) => t['widget'] as Widget).toList(),
        ),
      ),
    );
  }
}
