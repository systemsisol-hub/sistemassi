import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

Future<T?> showFullWidthModal<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
}) {
  final screenWidth = MediaQuery.of(context).size.width;
  final isDesktop = screenWidth > 800;
  if (isDesktop) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: SiMotion.normal,
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: SizedBox(width: screenWidth, child: builder(ctx)),
        ),
      ),
    );
  } else {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: builder,
    );
  }
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredCache = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminRole();
    _fetchUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkAdminRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        setState(() => _isAdmin = (user.userMetadata?['role'] ?? '') == 'admin');
      }
    } catch (e) {
      debugPrint('Error checking admin role: $e');
    }
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    try {
      List<Map<String, dynamic>> all = [];
      int offset = 0;
      const limit = 1000;
      while (true) {
        final data = await Supabase.instance.client
            .from('profiles')
            .select('id, nombre, paterno, materno, email, numero_empleado, role, is_blocked, status_sys, permissions')
            .range(offset, offset + limit - 1);
        all.addAll(List<Map<String, dynamic>>.from(data));
        if (data.length < limit) break;
        offset += limit;
      }
      if (mounted) {
        setState(() {
          _users = all;
          _recomputeFiltered();
        });
      }
    } catch (e) {
      debugPrint('Error al cargar usuarios: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al cargar usuarios: $e'),
          backgroundColor: SiColors.of(context).danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteUser(String id) async {
    final c = SiColors.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: c.danger, size: 22),
          const SizedBox(width: SiSpace.x3),
          const Text('Eliminar usuario'),
        ]),
        content: const Text(
            '¿Deseas eliminar este perfil? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Supabase.instance.client
          .rpc('delete_user_admin', params: {'user_id': id});
      _fetchUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuario eliminado correctamente')),
        );
      }
    } catch (e) {
      debugPrint('Error al eliminar: $e');
    }
  }

  void _showUserForm({Map<String, dynamic>? user}) async {
    Map<String, dynamic>? fullUser = user;
    if (user != null) {
      try {
        final data = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', user['id'])
            .single();
        fullUser = Map<String, dynamic>.from(data);
      } catch (e) {
        debugPrint('Error loading user details: $e');
      }
    }
    if (!mounted) return;
    showFullWidthModal(
      context: context,
      builder: (ctx) => _UserFormSheet(
        user: fullUser,
        onSaved: () {
          _fetchUsers();
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Operación exitosa')));
          }
        },
      ),
    );
  }

  void _recomputeFiltered() {
    final result = _searchQuery.isEmpty
        ? List<Map<String, dynamic>>.from(_users)
        : _users.where((u) {
            final q = _searchQuery.toLowerCase();
            return (u['nombre'] ?? '').toString().toLowerCase().contains(q) ||
                (u['paterno'] ?? '').toString().toLowerCase().contains(q) ||
                (u['email'] ?? '').toString().toLowerCase().contains(q) ||
                (u['numero_empleado'] ?? '').toString().toLowerCase().contains(q);
          }).toList();
    result.sort((a, b) {
      final ac = (a['status_sys'] == 'CAMBIO') ? 0 : 1;
      final bc = (b['status_sys'] == 'CAMBIO') ? 0 : 1;
      if (ac != bc) return ac.compareTo(bc);
      final an = int.tryParse(a['numero_empleado']?.toString() ?? '') ?? 0;
      final bn = int.tryParse(b['numero_empleado']?.toString() ?? '') ?? 0;
      return bn.compareTo(an);
    });
    _filteredCache = result;
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final items = _filteredCache;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          _buildToolbar(c),
          Expanded(
            child: _isLoading
                ? Center(
                    child: Image.asset('assets/sisol_loader.gif',
                        width: 150,
                        errorBuilder: (_, __, ___) => CircularProgressIndicator(
                            color: c.brand, strokeWidth: 2)),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchUsers,
                    child: LayoutBuilder(
                      builder: (context, constraints) =>
                          constraints.maxWidth > 800
                              ? _buildDesktopTable(c, items)
                              : _buildMobileList(c, items),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(SiColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: SiSpace.x6, vertical: SiSpace.x3),
      child: Row(
        children: [
          Container(
            width: 280,
            height: 36,
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: SiRadius.rMd,
              border: Border.all(color: c.line),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, correo, ID...',
                hintStyle: TextStyle(fontSize: 13, color: c.ink4),
                prefixIcon: Icon(Icons.search, size: 16, color: c.ink3),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 14, color: c.ink3),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _recomputeFiltered();
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                isDense: true,
              ),
              onChanged: (v) => setState(() {
                _searchQuery = v;
                _recomputeFiltered();
              }),
            ),
          ),
          const Spacer(),
          if (_isAdmin)
            ElevatedButton.icon(
              onPressed: () => _showUserForm(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Usuario',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: const RoundedRectangleBorder(
                    borderRadius: SiRadius.rMd),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopTable(SiColors c, List<Map<String, dynamic>> items) {
    if (items.isEmpty) return _buildEmpty(c);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(SiSpace.x6),
      child: Center(
        child: Card(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: SiSpace.x5, vertical: SiSpace.x3),
                decoration: BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: c.line, width: 1))),
                child: Row(
                  children: [
                    _colHeader(c, 'USUARIO', flex: 4),
                    _colHeader(c, 'NO. EMP.', flex: 2),
                    _colHeader(c, 'ROL', flex: 2),
                    _colHeader(c, 'ESTADO', flex: 2),
                    _colHeader(c, 'PERMISOS', flex: 3),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              // Rows
              ...items.asMap().entries.map((e) {
                final i = e.key;
                final u = e.value;
                final role = u['role'] ?? 'usuario';
                final isBlocked = u['is_blocked'] ?? false;
                final nombre =
                    '${u['nombre'] ?? ''} ${u['paterno'] ?? ''}'.trim();
                final parts = nombre
                    .split(' ')
                    .where((s) => s.isNotEmpty)
                    .toList();
                final initials = parts.length > 1
                    ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
                    : (parts.isNotEmpty ? parts[0][0].toUpperCase() : '?');

                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SiSpace.x5, vertical: SiSpace.x2 + 2),
                  decoration: BoxDecoration(
                    color: i.isOdd ? c.bg : c.panel,
                    border: Border(
                        bottom: BorderSide(color: c.line2, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      // Usuario
                      Expanded(
                        flex: 4,
                        child: Row(children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: role == 'admin'
                                ? c.brandTint
                                : c.hover,
                            child: Text(initials,
                                style: TextStyle(
                                    color: role == 'admin' ? c.brand : c.ink3,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: SiSpace.x3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nombre.isEmpty ? 'Sin nombre' : nombre,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: c.ink,
                                      decoration: isBlocked
                                          ? TextDecoration.lineThrough
                                          : null),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(u['email'] ?? '',
                                    style:
                                        TextStyle(color: c.ink4, fontSize: 11),
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ]),
                      ),
                      // No. emp
                      Expanded(
                        flex: 2,
                        child: Text(u['numero_empleado'] ?? '----',
                            style: TextStyle(fontSize: 13, color: c.ink2)),
                      ),
                      // Rol
                      Expanded(
                        flex: 2,
                        child: _RoleBadge(role: role, c: c),
                      ),
                      // Estado
                      Expanded(
                        flex: 2,
                        child: _StatusBadge(
                            isBlocked: isBlocked,
                            statusSys: u['status_sys'],
                            c: c),
                      ),
                      // Permisos
                      Expanded(
                        flex: 3,
                        child: _PermIcons(
                            permissions: u['permissions'], c: c),
                      ),
                      // Acciones
                      SizedBox(
                        width: 48,
                        child: _isAdmin
                            ? PopupMenuButton<String>(
                                icon: Icon(Icons.more_horiz,
                                    size: 18, color: c.ink4),
                                onSelected: (v) => v == 'edit'
                                    ? _showUserForm(user: u)
                                    : _deleteUser(u['id']),
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Row(children: [
                                      Icon(Icons.edit_outlined,
                                          size: 16, color: c.ink2),
                                      const SizedBox(width: 12),
                                      const Text('Editar'),
                                    ]),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(children: [
                                      Icon(Icons.delete_outline,
                                          size: 16, color: c.danger),
                                      const SizedBox(width: 12),
                                      Text('Eliminar',
                                          style:
                                              TextStyle(color: c.danger)),
                                    ]),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colHeader(SiColors c, String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: c.ink4,
              letterSpacing: 0.8)),
    );
  }

  Widget _buildMobileList(SiColors c, List<Map<String, dynamic>> items) {
    if (items.isEmpty) return _buildEmpty(c);
    return ListView.separated(
      padding: const EdgeInsets.all(SiSpace.x4),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: SiSpace.x3),
      itemBuilder: (context, i) {
        final u = items[i];
        final role = u['role'] ?? 'usuario';
        final isBlocked = u['is_blocked'] ?? false;
        final nombre =
            '${u['numero_empleado'] ?? '----'} | ${u['nombre'] ?? ''} ${u['paterno'] ?? ''} ${u['materno'] ?? ''}'
                .trim();

        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
                horizontal: SiSpace.x5, vertical: SiSpace.x2),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: role == 'admin' ? c.brandTint : c.hover,
                borderRadius: SiRadius.rMd,
              ),
              alignment: Alignment.center,
              child: Icon(
                role == 'admin'
                    ? Icons.admin_panel_settings_outlined
                    : Icons.person_outline,
                color: role == 'admin' ? c.brand : c.ink3,
                size: 20,
              ),
            ),
            title: Text(
              nombre,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: c.ink,
                decoration: isBlocked ? TextDecoration.lineThrough : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(u['email'] ?? 'Sin correo',
                        style: TextStyle(fontSize: 12, color: c.ink3),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if ((u['email'] ?? '').toString().isNotEmpty)
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: u['email'].toString()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Correo copiado'),
                              duration: Duration(seconds: 1)),
                        );
                      },
                      child: Icon(Icons.copy_outlined,
                          size: 13, color: c.ink4),
                    ),
                ]),
                const SizedBox(height: SiSpace.x1),
                Row(children: [
                  _RoleBadge(role: role, c: c),
                  const SizedBox(width: SiSpace.x2),
                  _PermIcons(permissions: u['permissions'], c: c),
                ]),
              ],
            ),
            trailing: _isAdmin
                ? PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, size: 18, color: c.ink4),
                    onSelected: (v) => v == 'edit'
                        ? _showUserForm(user: u)
                        : _deleteUser(u['id']),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_outlined, size: 16, color: c.ink2),
                          const SizedBox(width: 12),
                          const Text('Editar'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline,
                              size: 16, color: c.danger),
                          const SizedBox(width: 12),
                          Text('Eliminar',
                              style: TextStyle(color: c.danger)),
                        ]),
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildEmpty(SiColors c) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search_outlined, size: 56, color: c.line),
          const SizedBox(height: SiSpace.x4),
          Text(
            _searchQuery.isNotEmpty
                ? 'Sin resultados para "$_searchQuery"'
                : 'No hay usuarios registrados',
            style: TextStyle(color: c.ink3, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// ── Small badge widgets ───────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  final String role;
  final SiColors c;
  const _RoleBadge({required this.role, required this.c});

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isAdmin ? c.brandTint : c.hover,
        borderRadius: SiRadius.rPill,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
                color: isAdmin ? c.brand : c.ink3, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(role,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isAdmin ? c.brand : c.ink3)),
      ]),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isBlocked;
  final String? statusSys;
  final SiColors c;
  const _StatusBadge(
      {required this.isBlocked, required this.statusSys, required this.c});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;
    if (isBlocked) {
      bg = c.dangerTint;
      fg = c.danger;
      label = 'Bloqueado';
    } else if (statusSys == 'ACTIVO') {
      bg = c.successTint;
      fg = c.success;
      label = 'Activo';
    } else if (statusSys == 'BAJA') {
      bg = c.dangerTint;
      fg = c.danger;
      label = 'Baja';
    } else {
      bg = c.warnTint;
      fg = c.warn;
      label = statusSys ?? '---';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: SiRadius.rPill),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 5,
            height: 5,
            decoration:
                BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
      ]),
    );
  }
}

class _PermIcons extends StatelessWidget {
  final dynamic permissions;
  final SiColors c;
  const _PermIcons({required this.permissions, required this.c});

  @override
  Widget build(BuildContext context) {
    if (permissions == null || permissions is! Map) return const SizedBox.shrink();
    final perms = permissions as Map;
    final icons = <_PermIcon>[
      _PermIcon(Icons.group_outlined, perms['show_users'] == true),
      _PermIcon(Icons.inventory_2_outlined, perms['show_issi'] == true),
      _PermIcon(Icons.badge_outlined, perms['show_cssi'] == true),
      _PermIcon(Icons.description_outlined, perms['show_incidencias'] == true),
      _PermIcon(Icons.assignment_outlined, perms['show_logs'] == true),
      _PermIcon(Icons.fingerprint, perms['show_asistencia'] == true),
      _PermIcon(Icons.bar_chart_outlined, perms['show_powerbi'] == true),
      _PermIcon(Icons.vpn_key_outlined, perms['show_passwords'] == true),
    ];
    return Wrap(
      spacing: 3,
      children: icons
          .map((pi) => Icon(pi.icon,
              size: 13,
              color: pi.active ? c.brand : c.line))
          .toList(),
    );
  }
}

class _PermIcon {
  final IconData icon;
  final bool active;
  const _PermIcon(this.icon, this.active);
}

// ── User form sheet ───────────────────────────────────────────────────────────

class _UserFormSheet extends StatefulWidget {
  final Map<String, dynamic>? user;
  final VoidCallback onSaved;

  const _UserFormSheet({
    required this.onSaved,
    this.user,
  });

  @override
  State<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends State<_UserFormSheet> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _paternoCtrl;
  late final TextEditingController _maternoCtrl;
  late final TextEditingController _empNumCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _mailUser;
  late final TextEditingController _mailPass;
  late final TextEditingController _drpUser;
  late final TextEditingController _drpPass;
  late final TextEditingController _gpUser;
  late final TextEditingController _gpPass;
  late final TextEditingController _bitrixUser;
  late final TextEditingController _bitrixPass;
  late final TextEditingController _ekUser;
  late final TextEditingController _ekPass;
  late final TextEditingController _otroUser;
  late final TextEditingController _otroPass;

  late String _role;
  late String? _statusSys;
  late bool _isBlocked;
  late Map<String, bool> _permissions;
  final Map<String, bool> _obscure = {
    'mail': true, 'drp': true, 'gp': true,
    'bitrix': true, 'ek': true, 'otro': true,
  };
  bool _saving = false;

  bool get _isEditing => widget.user != null;
  bool get _isGrantingAccess =>
      _isEditing && (widget.user!['has_auth_account'] != true);

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _nombreCtrl = TextEditingController(text: u?['nombre']);
    _paternoCtrl = TextEditingController(text: u?['paterno']);
    _maternoCtrl = TextEditingController(text: u?['materno']);
    _empNumCtrl = TextEditingController(text: u?['numero_empleado']);
    _emailCtrl = TextEditingController(text: u?['email']);
    _passCtrl = TextEditingController();
    _mailUser = TextEditingController(text: u?['mail_user']);
    _mailPass = TextEditingController(text: u?['mail_pass']);
    _drpUser = TextEditingController(text: u?['drp_user']);
    _drpPass = TextEditingController(text: u?['drp_pass']);
    _gpUser = TextEditingController(text: u?['gp_user']);
    _gpPass = TextEditingController(text: u?['gp_pass']);
    _bitrixUser = TextEditingController(text: u?['bitrix_user']);
    _bitrixPass = TextEditingController(text: u?['bitrix_pass']);
    _ekUser = TextEditingController(text: u?['ek_user']);
    _ekPass = TextEditingController(text: u?['ek_pass']);
    _otroUser = TextEditingController(text: u?['otro_user']);
    _otroPass = TextEditingController(text: u?['otro_pass']);
    _role = u?['role'] ?? 'usuario';
    _statusSys = u?['status_sys'] ?? 'ACTIVO';
    _isBlocked = u?['is_blocked'] ?? false;
    _permissions = Map<String, bool>.from(u?['permissions'] ?? {
      'show_calendar': false,
      'show_users': false,
      'show_issi': false,
      'show_cssi': false,
      'show_incidencias': false,
      'show_logs': false,
      'show_external_contacts': false,
      'show_asistencia': false,
      'show_powerbi': false,
      'show_passwords': false,
    });
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _paternoCtrl.dispose();
    _maternoCtrl.dispose();
    _empNumCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _mailUser.dispose();
    _mailPass.dispose();
    _drpUser.dispose();
    _drpPass.dispose();
    _gpUser.dispose();
    _gpPass.dispose();
    _bitrixUser.dispose();
    _bitrixPass.dispose();
    _ekUser.dispose();
    _ekPass.dispose();
    _otroUser.dispose();
    _otroPass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_emailCtrl.text.trim().isEmpty ||
        (!_isEditing && _passCtrl.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Email y contraseña son obligatorios')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEditing && !_isGrantingAccess) {
        await Supabase.instance.client.rpc('update_user_admin', params: {
          'user_id_param': widget.user!['id'],
          'new_email': _emailCtrl.text.trim(),
          'new_full_name':
              '${_nombreCtrl.text} ${_paternoCtrl.text}'.trim(),
          'new_role': _role,
          'new_status_sys': _statusSys,
          'is_blocked_param': _isBlocked,
          'new_permissions': _permissions,
          'new_password': _passCtrl.text.trim().isEmpty
              ? null
              : _passCtrl.text.trim(),
        });
        await Supabase.instance.client.from('profiles').update({
          'mail_user': _mailUser.text.trim(),
          'mail_pass': _mailPass.text.trim(),
          'drp_user': _drpUser.text.trim(),
          'drp_pass': _drpPass.text.trim(),
          'gp_user': _gpUser.text.trim(),
          'gp_pass': _gpPass.text.trim(),
          'bitrix_user': _bitrixUser.text.trim(),
          'bitrix_pass': _bitrixPass.text.trim(),
          'ek_user': _ekUser.text.trim(),
          'ek_pass': _ekPass.text.trim(),
          'otro_user': _otroUser.text.trim(),
          'otro_pass': _otroPass.text.trim(),
        }).eq('id', widget.user!['id']);
      } else {
        final res = await Supabase.instance.client
            .rpc('create_user_admin', params: {
          'email': _emailCtrl.text.trim(),
          'password': _passCtrl.text.trim(),
          'full_name':
              '${_nombreCtrl.text} ${_paternoCtrl.text}'.trim(),
          'user_role': _role,
          if (_isGrantingAccess)
            'user_id_param': widget.user!['id'],
        });
        if (res != null) {
          final newId = _isGrantingAccess ? widget.user!['id'] : res;
          await Supabase.instance.client.from('profiles').update({
            'nombre': _nombreCtrl.text.trim(),
            'paterno': _paternoCtrl.text.trim(),
            'materno': _maternoCtrl.text.trim(),
            'email': _emailCtrl.text.trim(),
            'numero_empleado': _empNumCtrl.text.trim(),
            'status_sys': 'ACTIVO',
            'permissions': _permissions,
            'role': _role,
            'mail_user': _mailUser.text.trim(),
            'mail_pass': _mailPass.text.trim(),
          }).eq('id', newId);
        }
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: SiColors.of(context).danger,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 800;

    final title = _isGrantingAccess
        ? 'Conceder acceso'
        : (_isEditing
            ? 'Editar ${widget.user!['nombre'] ?? ''}'
            : 'Nuevo usuario');

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(
                vertical: SiSpace.x3, horizontal: SiSpace.x4),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border:
                  Border(bottom: BorderSide(color: c.line, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancelar',
                      style: TextStyle(fontSize: 15, color: c.ink3)),
                ),
                Text(title,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.ink)),
                TextButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: c.brand))
                      : Text(_isEditing ? 'Guardar' : 'Crear',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: c.brand)),
                ),
              ],
            ),
          ),
          // Body
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: SiSpace.x6,
                right: SiSpace.x6,
                top: SiSpace.x4,
                bottom:
                    MediaQuery.of(context).viewInsets.bottom + SiSpace.x6,
              ),
              child: isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildGeneralSection(c)),
                        const SizedBox(width: SiSpace.x8),
                        Expanded(child: _buildPermissionsSection(c)),
                        const SizedBox(width: SiSpace.x8),
                        Expanded(child: _buildCredentialsSection(c)),
                      ],
                    )
                  : Column(children: [
                      _buildGeneralSection(c),
                      const SizedBox(height: SiSpace.x6),
                      Divider(color: c.line),
                      const SizedBox(height: SiSpace.x6),
                      _buildPermissionsSection(c),
                      const SizedBox(height: SiSpace.x6),
                      Divider(color: c.line),
                      const SizedBox(height: SiSpace.x6),
                      _buildCredentialsSection(c),
                    ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(SiColors c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SiSpace.x4),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: c.brand,
              letterSpacing: 0.8)),
    );
  }

  Widget _buildGeneralSection(SiColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(c, 'CONTROL'),
        DropdownButtonFormField<String>(
          value: _statusSys,
          decoration: const InputDecoration(
              labelText: 'Status Sys',
              prefixIcon: Icon(Icons.settings_suggest_outlined)),
          items: ['ACTIVO', 'BAJA', 'CAMBIO', 'ELIMINAR', 'NO APLICA']
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) => setState(() => _statusSys = v),
        ),
        const SizedBox(height: SiSpace.x4),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
              labelText: 'Correo electrónico *',
              prefixIcon: Icon(Icons.email_outlined)),
        ),
        const SizedBox(height: SiSpace.x4),
        TextField(
          controller: _passCtrl,
          obscureText: true,
          decoration: InputDecoration(
              labelText: _isEditing
                  ? 'Contraseña (dejar vacío para no cambiar)'
                  : 'Contraseña *',
              prefixIcon: const Icon(Icons.lock_outlined)),
        ),
        const SizedBox(height: SiSpace.x4),
        DropdownButtonFormField<String>(
          value: _role,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Rol',
              prefixIcon: Icon(Icons.admin_panel_settings_outlined)),
          items: const [
            DropdownMenuItem(value: 'usuario', child: Text('Usuario')),
            DropdownMenuItem(value: 'admin', child: Text('Administrador')),
          ],
          onChanged: (v) => setState(() => _role = v!),
        ),
        const SizedBox(height: SiSpace.x4),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: SiSpace.x3, vertical: SiSpace.x2),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: SiRadius.rMd,
            border: Border.all(color: c.line),
          ),
          child: Row(children: [
            Icon(
              _isBlocked ? Icons.block_outlined : Icons.check_circle_outline,
              color: _isBlocked ? c.danger : c.success,
              size: 18,
            ),
            const SizedBox(width: SiSpace.x3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Cuenta',
                    style: TextStyle(fontSize: 13, color: c.ink)),
                Text(_isBlocked ? 'Bloqueada' : 'Activa',
                    style: TextStyle(
                        fontSize: 11,
                        color: _isBlocked ? c.danger : c.success)),
              ]),
            ),
            Switch(
              value: !_isBlocked,
              onChanged: (v) => setState(() => _isBlocked = !v),
              activeColor: c.brand,
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildPermissionsSection(SiColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(c, 'ACCESOS (VISIBILIDAD)'),
        _permSwitch(c, 'Calendario', 'show_calendar', Icons.calendar_month_outlined),
        _permSwitch(c, 'Gestión de usuarios', 'show_users', Icons.group_outlined),
        _permSwitch(c, 'Inventario ISSI', 'show_issi', Icons.inventory_2_outlined),
        _permSwitch(c, 'Colaboradores CSSI', 'show_cssi', Icons.badge_outlined),
        _permSwitch(c, 'Incidencias', 'show_incidencias', Icons.description_outlined),
        _permSwitch(c, 'Logs del sistema', 'show_logs', Icons.assignment_outlined),
        _permSwitch(c, 'Contactos externos', 'show_external_contacts', Icons.contact_phone_outlined),
        _permSwitch(c, 'Asistencia', 'show_asistencia', Icons.fingerprint),
        _permSwitch(c, 'Power BI', 'show_powerbi', Icons.bar_chart_outlined),
        _permSwitch(c, 'Contraseñas', 'show_passwords', Icons.vpn_key_outlined),
      ],
    );
  }

  Widget _permSwitch(
      SiColors c, String label, String key, IconData icon) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 18, color: c.ink3),
      title: Text(label, style: TextStyle(fontSize: 13, color: c.ink)),
      trailing: Switch(
        value: _permissions[key] ?? false,
        onChanged: (v) => setState(() => _permissions[key] = v),
        activeColor: c.brand,
      ),
    );
  }

  Widget _buildCredentialsSection(SiColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(c, 'CREDENCIALES DE SISTEMAS'),
        _credRow(c, 'Mail', _mailUser, _mailPass, 'mail'),
        _credRow(c, 'DRP', _drpUser, _drpPass, 'drp'),
        _credRow(c, 'GP', _gpUser, _gpPass, 'gp'),
        _credRow(c, 'Bitrix', _bitrixUser, _bitrixPass, 'bitrix'),
        _credRow(c, 'Enkontrol', _ekUser, _ekPass, 'ek'),
        _credRow(c, 'Otro', _otroUser, _otroPass, 'otro'),
      ],
    );
  }

  Widget _credRow(SiColors c, String label,
      TextEditingController uCtrl, TextEditingController pCtrl, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SiSpace.x3),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: uCtrl,
            decoration: InputDecoration(
                labelText: '$label usuario', isDense: true),
          ),
        ),
        const SizedBox(width: SiSpace.x2),
        Expanded(
          child: TextField(
            controller: pCtrl,
            obscureText: _obscure[key] ?? true,
            decoration: InputDecoration(
              labelText: 'Pass',
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(
                  (_obscure[key] ?? true)
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 16,
                  color: c.ink4,
                ),
                onPressed: () =>
                    setState(() => _obscure[key] = !(_obscure[key] ?? true)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
