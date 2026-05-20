import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'widgets/global_search.dart';
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
import 'tablas_page.dart';
import 'passwords_page.dart';
import 'theme/si_theme.dart';

class _OpenSearchIntent extends Intent {
  const _OpenSearchIntent();
}

// Visual-only nav group definitions — order here is render order.
final _navGroups = <(String, List<String>)>[
  ('GENERAL',        ['Mi Perfil', 'Social', 'Contraseñas', 'Contactos', 'Firmas', 'Calendario']),
  ('OPERACIÓN',      ['Incidencias', 'Inventario', 'Colaborador', 'Asistencia']),
  ('ANÁLISIS',       ['BI', 'Logs', 'Tablas']),
  ('ADMINISTRACIÓN', ['Usuarios']),
];

class MainNavigation extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;
  final ValueNotifier<ThemeMode> themeNotifier;
  const MainNavigation({
    super.key,
    required this.role,
    required this.permissions,
    required this.themeNotifier,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  String? _selectedEventId;
  String? _fotoUrl;

  @override
  void initState() {
    super.initState();
    _fetchFotoUrl();
  }

  Future<void> _fetchFotoUrl() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('foto_url')
          .eq('id', userId)
          .single();
      if (mounted) setState(() => _fotoUrl = data['foto_url'] as String?);
    } catch (_) {}
  }

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

    if (widget.permissions['show_passwords'] == true) {
      pages.add({
        'title': 'Contraseñas',
        'icon': Icons.vpn_key_outlined,
        'activeIcon': Icons.vpn_key,
        'widget': const PasswordsPage(),
      });
    }

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
    if (widget.permissions['show_tablas'] == true) {
      pages.add({
        'title': 'Tablas',
        'icon': Icons.table_chart_outlined,
        'activeIcon': Icons.table_chart,
        'widget': const TablasPage(),
      });
    }

    return pages;
  }

  void _onNavigateToCalendar(
      String? eventId, List<Map<String, dynamic>> pages) {
    final idx = pages.indexWhere((p) => p['title'] == 'Calendario');
    if (idx != -1) {
      setState(() {
        _selectedIndex = idx;
        _selectedEventId = eventId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _availablePages;
    if (_selectedIndex >= pages.length) _selectedIndex = 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;
        return isDesktop
            ? _DesktopShell(
                pages: pages,
                selectedIndex: _selectedIndex,
                role: widget.role,
                permissions: widget.permissions,
                themeNotifier: widget.themeNotifier,
                fotoUrl: _fotoUrl,
                onSelect: (i) => setState(() {
                  _selectedIndex = i;
                  _selectedEventId = null;
                }),
                onNavigateToCalendar: (id) =>
                    _onNavigateToCalendar(id, pages),
              )
            : _MobileShell(
                pages: pages,
                selectedIndex: _selectedIndex,
                role: widget.role,
                permissions: widget.permissions,
                themeNotifier: widget.themeNotifier,
                fotoUrl: _fotoUrl,
                onSelect: (i) => setState(() {
                  _selectedIndex = i;
                  _selectedEventId = null;
                }),
                onNavigateToCalendar: (id) =>
                    _onNavigateToCalendar(id, pages),
              );
      },
    );
  }
}

// ── Desktop shell ────────────────────────────────────────────────────────────

class _DesktopShell extends StatefulWidget {
  final List<Map<String, dynamic>> pages;
  final int selectedIndex;
  final String role;
  final Map<String, dynamic> permissions;
  final ValueNotifier<ThemeMode> themeNotifier;
  final String? fotoUrl;
  final ValueChanged<int> onSelect;
  final ValueChanged<String?> onNavigateToCalendar;

  const _DesktopShell({
    required this.pages,
    required this.selectedIndex,
    required this.role,
    required this.permissions,
    required this.themeNotifier,
    this.fotoUrl,
    required this.onSelect,
    required this.onNavigateToCalendar,
  });

  @override
  State<_DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<_DesktopShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _railCtrl;
  late final Animation<double> _railAnim;

  @override
  void initState() {
    super.initState();
    _railCtrl = AnimationController(
        vsync: this, duration: SiMotion.railExpand);
    _railAnim =
        CurvedAnimation(parent: _railCtrl, curve: SiMotion.easeOut);
  }

  @override
  void dispose() {
    _railCtrl.dispose();
    super.dispose();
  }

  List<Widget> _buildGroupedItems(bool labelVisible, double labelOpacity,
      {bool onDark = true}) {
    final items = <Widget>[];
    bool firstNonEmpty = true;

    for (final (label, titles) in _navGroups) {
      // Collect pages that belong to this group (preserving flat index)
      final groupEntries = <(int, Map<String, dynamic>)>[];
      for (var i = 0; i < widget.pages.length; i++) {
        if (titles.contains(widget.pages[i]['title'])) {
          groupEntries.add((i, widget.pages[i]));
        }
      }
      if (groupEntries.isEmpty) continue;

      if (labelVisible) {
        items.add(_SectionHeader(
            label: label, visible: true, opacity: labelOpacity, onDark: onDark));
      } else if (!firstNonEmpty) {
        items.add(_SectionHeader(
            label: label, visible: false, opacity: 0, onDark: onDark));
      }
      firstNonEmpty = false;

      for (final (i, page) in groupEntries) {
        final isActive = widget.selectedIndex == i;
        items.add(_RailItem(
          icon: isActive ? page['activeIcon'] : page['icon'],
          label: page['title'],
          isActive: isActive,
          showLabel: labelVisible,
          labelOpacity: labelOpacity,
          onTap: () => widget.onSelect(i),
          onDark: onDark,
        ));
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userEmail =
        Supabase.instance.client.auth.currentUser?.email ?? '';
    final initials = _initials(userEmail);
    final currentPage = widget.pages[widget.selectedIndex];

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _OpenSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _OpenSearchIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _OpenSearchIntent: CallbackAction<_OpenSearchIntent>(
            onInvoke: (_) {
              showGlobalSearch(
                context: context,
                role: widget.role,
                permissions: widget.permissions,
                pages: widget.pages,
                onSelectPage: widget.onSelect,
              );
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: _buildScaffold(context, c, isDark, initials, userEmail, currentPage),
        ),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context, SiColors c, bool isDark,
      String initials, String userEmail, Map<String, dynamic> currentPage) {
    return Scaffold(
      backgroundColor: c.bg,
      body: Row(
        children: [
          // ── Sidebar ──────────────────────────────────────────
          MouseRegion(
            onEnter: (_) => _railCtrl.forward(),
            onExit: (_) => _railCtrl.reverse(),
            child: AnimatedBuilder(
              animation: _railAnim,
              builder: (context, _) {
                final w = SiLayout.railCollapsed +
                    (SiLayout.railExpanded - SiLayout.railCollapsed) *
                        _railAnim.value;
                final labelVisible = _railAnim.value > 0.4;
                final labelOpacity =
                    ((_railAnim.value - 0.4) / 0.6).clamp(0.0, 1.0);

                return Container(
                  width: w,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? c.panel : c.brand,
                    border: Border(
                      right: BorderSide(
                        color: isDark
                            ? c.line
                            : Colors.white.withValues(alpha: 0.08),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Brand row
                      SizedBox(
                        height: SiLayout.headerHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: SiSpace.x3),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: AnimatedSwitcher(
                              duration: SiMotion.normal,
                              child: labelVisible
                                  ? ColorFiltered(
                                      key: const ValueKey('full'),
                                      colorFilter: isDark
                                          ? const ColorFilter.mode(
                                              Colors.transparent,
                                              BlendMode.dst)
                                          : const ColorFilter.mode(
                                              Colors.white,
                                              BlendMode.srcIn),
                                      child: Image.asset(
                                        'assets/logo.png',
                                        height: 28,
                                        fit: BoxFit.contain,
                                        alignment: Alignment.centerLeft,
                                      ),
                                    )
                                  : Container(
                                      key: const ValueKey('ico'),
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.15),
                                        borderRadius: SiRadius.rSm,
                                      ),
                                      padding: const EdgeInsets.all(4),
                                      child: ColorFiltered(
                                        colorFilter: const ColorFilter.mode(
                                          Colors.white,
                                          BlendMode.srcIn,
                                        ),
                                        child: Image.asset(
                                          'assets/logo_ico.png',
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                          height: 1,
                          color: isDark
                              ? c.line
                              : Colors.white.withValues(alpha: 0.08)),

                      // Nav items (grouped)
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                              vertical: SiSpace.x2,
                              horizontal: SiSpace.x1),
                          children: _buildGroupedItems(
                              labelVisible, labelOpacity,
                              onDark: !isDark),
                        ),
                      ),

                      // User footer
                      Container(
                          height: 1,
                          color: isDark
                              ? c.line
                              : Colors.white.withValues(alpha: 0.10)),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: SiSpace.x2,
                            vertical: SiSpace.x2),
                        child: Row(
                          children: [
                            _Avatar(
                                initials: initials,
                                size: 28,
                                c: c,
                                onDark: !isDark,
                                fotoUrl: widget.fotoUrl),
                            if (labelVisible) ...[
                              const SizedBox(width: SiSpace.x2),
                              Expanded(
                                child: Opacity(
                                  opacity: labelOpacity,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(userEmail,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? c.ink2
                                                  : Colors.white,
                                              fontWeight:
                                                  FontWeight.w500)),
                                      Text(widget.role.toUpperCase(),
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? c.ink4
                                                  : Colors.white.withValues(
                                                      alpha: 0.55),
                                              letterSpacing: 0.5)),
                                    ],
                                  ),
                                ),
                              ),
                              Opacity(
                                opacity: labelOpacity,
                                child: InkWell(
                                  onTap: () async {
                                    try {
                                      final user = Supabase.instance
                                          .client.auth.currentUser;
                                      await Supabase.instance.client
                                          .rpc('log_event', params: {
                                        'action_type_param':
                                            'CIERRE DE SESIÓN',
                                        'target_info_param':
                                            'Usuario: ${user?.email ?? '---'}',
                                      });
                                    } catch (_) {}
                                    await Supabase.instance.client.auth
                                        .signOut();
                                  },
                                  borderRadius: SiRadius.rSm,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.all(SiSpace.x1),
                                    child: Icon(Icons.logout,
                                        size: 16,
                                        color: isDark
                                            ? c.ink3
                                            : Colors.white.withValues(
                                                alpha: 0.70)),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── Main content ──────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                _Header(
                  pageTitle: currentPage['title'],
                  role: widget.role,
                  permissions: widget.permissions,
                  themeNotifier: widget.themeNotifier,
                  pages: widget.pages,
                  onSelectPage: widget.onSelect,
                  onNavigateToCalendar: widget.onNavigateToCalendar,
                  onSelectHome: () => widget.onSelect(0),
                ),
                Expanded(child: currentPage['widget']),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mobile shell ─────────────────────────────────────────────────────────────

class _MobileShell extends StatelessWidget {
  final List<Map<String, dynamic>> pages;
  final int selectedIndex;
  final String role;
  final Map<String, dynamic> permissions;
  final ValueNotifier<ThemeMode> themeNotifier;
  final String? fotoUrl;
  final ValueChanged<int> onSelect;
  final ValueChanged<String?> onNavigateToCalendar;

  const _MobileShell({
    required this.pages,
    required this.selectedIndex,
    required this.role,
    required this.permissions,
    required this.themeNotifier,
    this.fotoUrl,
    required this.onSelect,
    required this.onNavigateToCalendar,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final currentPage = pages[selectedIndex];

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(currentPage['title']),
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, mode, _) => IconButton(
              icon: Icon(
                mode == ThemeMode.dark
                    ? Icons.wb_sunny_outlined
                    : Icons.dark_mode_outlined,
                size: 20,
              ),
              tooltip: mode == ThemeMode.dark ? 'Modo claro' : 'Modo oscuro',
              onPressed: () => themeNotifier.value =
                  mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
            ),
          ),
          NotificationBell(
            role: role,
            permissions: permissions,
            currentUserId:
                Supabase.instance.client.auth.currentUser?.id ?? '',
            onNavigateToCalendar: onNavigateToCalendar,
          ),
        ],
      ),
      drawer: _buildDrawer(context, c, fotoUrl),
      body: currentPage['widget'],
    );
  }

  Widget _buildDrawer(BuildContext context, SiColors c, String? fotoUrl) {
    final userEmail =
        Supabase.instance.client.auth.currentUser?.email ?? '';
    final initials = _initials(userEmail);

    return Drawer(
      backgroundColor: c.panel,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                  SiSpace.x4, SiSpace.x5, SiSpace.x4, SiSpace.x4),
              child: Image.asset(
                'assets/logo.png',
                height: 28,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
              ),
            ),
            Divider(color: c.line, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                    vertical: SiSpace.x2, horizontal: SiSpace.x2),
                children: _buildGroupedDrawerItems(context, c),
              ),
            ),
            Divider(color: c.line, height: 1),
            ListTile(
              leading: _Avatar(initials: initials, size: 28, c: c, fotoUrl: fotoUrl),
              title: Text(userEmail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.ink)),
              subtitle: Text(role.toUpperCase(),
                  style: TextStyle(fontSize: 10, color: c.ink3)),
              trailing: IconButton(
                icon: Icon(Icons.logout, size: 18, color: c.ink3),
                onPressed: () async {
                  Navigator.pop(context);
                  await Supabase.instance.client.auth.signOut();
                },
              ),
            ),
            const SizedBox(height: SiSpace.x2),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroupedDrawerItems(BuildContext context, SiColors c) {
    final items = <Widget>[];
    for (final (label, titles) in _navGroups) {
      final groupEntries = <(int, Map<String, dynamic>)>[];
      for (var i = 0; i < pages.length; i++) {
        if (titles.contains(pages[i]['title'])) {
          groupEntries.add((i, pages[i]));
        }
      }
      if (groupEntries.isEmpty) continue;

      items.add(_SectionHeader(
          label: label, visible: true, opacity: 1.0, onDark: false));

      for (final (i, page) in groupEntries) {
        final isActive = selectedIndex == i;
        items.add(_RailItem(
          icon: isActive ? page['activeIcon'] : page['icon'],
          label: page['title'],
          isActive: isActive,
          showLabel: true,
          labelOpacity: 1.0,
          onTap: () {
            onSelect(i);
            Navigator.pop(context);
          },
          onDark: false,
        ));
      }
      items.add(const SizedBox(height: SiSpace.x2));
    }
    return items;
  }
}

// ── Header bar ───────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String pageTitle;
  final String role;
  final Map<String, dynamic> permissions;
  final ValueNotifier<ThemeMode> themeNotifier;
  final List<Map<String, dynamic>> pages;
  final ValueChanged<int> onSelectPage;
  final ValueChanged<String?> onNavigateToCalendar;
  final VoidCallback onSelectHome;

  const _Header({
    required this.pageTitle,
    required this.role,
    required this.permissions,
    required this.themeNotifier,
    required this.pages,
    required this.onSelectPage,
    required this.onNavigateToCalendar,
    required this.onSelectHome,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    return Container(
      height: SiLayout.headerHeight,
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line, width: 1)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 20),
          // Breadcrumb
          GestureDetector(
            onTap: onSelectHome,
            child: Text('Sistemassi',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: c.ink3)),
          ),
          Text(' / ',
              style: TextStyle(fontSize: 13, color: c.ink4)),
          Text(pageTitle,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.ink)),
          const SizedBox(width: 16),
          // Search bar — absorbs remaining space, centered
          Expanded(
            child: Center(
              child: _SearchBar(
                role: role,
                permissions: permissions,
                pages: pages,
                onSelectPage: onSelectPage,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, mode, _) {
              final isDark = mode == ThemeMode.dark;
              return IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: isDark ? 'Modo claro' : 'Modo oscuro',
                icon: Icon(
                  isDark ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
                  size: 18,
                  color: c.ink3,
                ),
                onPressed: () => themeNotifier.value =
                    isDark ? ThemeMode.light : ThemeMode.dark,
              );
            },
          ),
          NotificationBell(
            role: role,
            permissions: permissions,
            currentUserId:
                Supabase.instance.client.auth.currentUser?.id ?? '',
            onNavigateToCalendar: onNavigateToCalendar,
          ),
          const SizedBox(width: SiSpace.x3),
        ],
      ),
    );
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final String role;
  final Map<String, dynamic> permissions;
  final List<Map<String, dynamic>> pages;
  final ValueChanged<int> onSelectPage;

  const _SearchBar({
    required this.role,
    required this.permissions,
    required this.pages,
    required this.onSelectPage,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final shortcut = isMac ? '⌘K' : 'Ctrl K';
    final isAdmin = role == 'admin';

    void openSearch() {
      if (!isAdmin) return;
      showGlobalSearch(
        context: context,
        role: role,
        permissions: permissions,
        pages: pages,
        onSelectPage: onSelectPage,
      );
    }

    return MouseRegion(
      cursor:
          isAdmin ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: openSearch,
        child: Container(
          height: 32,
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: c.hover,
            border: Border.all(color: c.line, width: 1),
            borderRadius: SiRadius.rMd,
          ),
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(Icons.search,
                  size: 14,
                  color: isAdmin ? c.ink3 : c.ink4),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isAdmin
                      ? 'Buscar colaborador, activo, incidencia...'
                      : 'Búsqueda disponible para administradores',
                  style: TextStyle(fontSize: 13, color: c.ink4),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 2),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: c.panel,
                    border: Border.all(color: c.line, width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(shortcut,
                      style: SiType.mono(size: 10, color: c.ink3)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final bool visible;
  final double opacity;
  final bool onDark;

  const _SectionHeader({
    required this.label,
    required this.visible,
    required this.opacity,
    this.onDark = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return Container(
        height: 1,
        margin: const EdgeInsets.symmetric(
            vertical: SiSpace.x2, horizontal: SiSpace.x2),
        color: onDark
            ? Colors.white.withValues(alpha: 0.08)
            : SiColors.of(context).line,
      );
    }
    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 8, 6),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: SiType.fontFamily,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 10.5 * 0.08,
            color: onDark
                ? Colors.white.withValues(alpha: 0.45)
                : SiColors.of(context).ink3,
            height: 1,
          ),
        ),
      ),
    );
  }
}

// ── Rail nav item ─────────────────────────────────────────────────────────────

class _RailItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool showLabel;
  final double labelOpacity;
  final VoidCallback onTap;
  final bool onDark;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.showLabel,
    required this.labelOpacity,
    required this.onTap,
    this.onDark = false,
  });

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    final Color bg;
    final Color iconColor;
    final Color textColor;

    if (widget.onDark) {
      bg = widget.isActive
          ? Colors.white.withValues(alpha: 0.14)
          : _hovered
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent;
      iconColor = widget.isActive
          ? Colors.white
          : Colors.white.withValues(alpha: 0.65);
      textColor = widget.isActive
          ? Colors.white
          : Colors.white.withValues(alpha: 0.75);
    } else {
      bg = widget.isActive
          ? c.brandTint
          : _hovered
              ? c.hover
              : Colors.transparent;
      iconColor = widget.isActive ? c.brand : c.ink3;
      textColor = widget.isActive ? c.brand : c.ink2;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: SiMotion.fast,
          curve: SiMotion.easeOut,
          height: 36,
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: SiRadius.rMd,
            border: widget.isActive
                ? Border(
                    left: BorderSide(
                      color: widget.onDark ? Colors.white : c.brand,
                      width: 2,
                    ),
                  )
                : null,
          ),
          padding: EdgeInsets.only(
            left: widget.isActive ? SiSpace.x2 : SiSpace.x3,
            right: SiSpace.x2,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 17, color: iconColor),
              if (widget.showLabel) ...[
                const SizedBox(width: SiSpace.x2),
                Opacity(
                  opacity: widget.labelOpacity,
                  child: Text(
                    widget.label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: widget.isActive
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: textColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String initials;
  final double size;
  final SiColors c;
  final bool onDark;
  final String? fotoUrl;

  const _Avatar({
    required this.initials,
    required this.size,
    required this.c,
    this.onDark = false,
    this.fotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = fotoUrl != null && fotoUrl!.isNotEmpty;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: hasPhoto
            ? Image.network(
                fotoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Container(
        color: onDark
            ? Colors.white.withValues(alpha: 0.18)
            : c.brandTint,
        alignment: Alignment.center,
        child: Text(initials,
            style: TextStyle(
                fontSize: size * 0.4,
                fontWeight: FontWeight.w600,
                color: onDark ? Colors.white : c.brand,
                height: 1)),
      );
}

String _initials(String email) {
  final parts = email.split('@').first.split('.');
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return email.isNotEmpty ? email[0].toUpperCase() : '?';
}
