import 'package:flutter/material.dart';

import 'theme/si_theme.dart';
import 'ventas_config_page.dart';
import 'ventas_conversaciones_page.dart';
import 'ventas_desarrollos_page.dart';
import 'ventas_leads_page.dart';

/// Agente Sisol: todo lo del chat público de sisol.com.mx en una sola página, con pestañas.
///
/// Eran cuatro entradas del menú (Leads, Conversaciones, Desarrollos, Agente Sisol). El usuario
/// pidió el 24/09/2026 dejarlas en una: son caras del mismo agente, igual que las pestañas de SOL.
/// El orden es el suyo: Leads primero porque es lo que se revisa a diario; Configuración al final.
class VentasPage extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;
  const VentasPage({super.key, required this.role, required this.permissions});

  @override
  State<VentasPage> createState() => _VentasPageState();
}

class _VentasPageState extends State<VentasPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          _barra(c),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              // Las pestañas son listas y tablas que se leen hacia abajo: deslizar de lado para cambiar
              // de pestaña haría saltar de una a otra al intentar desplazar una tabla ancha.
              physics: const NeverScrollableScrollPhysics(),
              children: [
                VentasLeadsPage(role: widget.role, permissions: widget.permissions),
                VentasConversacionesPage(role: widget.role, permissions: widget.permissions),
                VentasDesarrollosPage(role: widget.role, permissions: widget.permissions),
                VentasConfigPage(role: widget.role, permissions: widget.permissions),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Mismo cromo que la barra de SOL (`sol_page.dart`) y con iconos que la app ya usa: uno nuevo
  /// sale en blanco para quien tenga la fuente de iconos en caché.
  Widget _barra(SiColors c) {
    Tab pestana(IconData icono, String texto) => Tab(
          height: 42,
          icon: Icon(icono, size: 16),
          iconMargin: EdgeInsets.zero,
          text: texto,
        );
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: c.brand,
          unselectedLabelColor: c.ink3,
          indicatorColor: c.brand,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: [
            pestana(Icons.person_add_alt_1, 'Leads'),
            pestana(Icons.chat_outlined, 'Conversaciones'),
            pestana(Icons.business, 'Desarrollos'),
            pestana(Icons.settings_outlined, 'Configuración'),
          ],
        ),
      ),
    );
  }
}
