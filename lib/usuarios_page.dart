import 'dart:async';
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
  final String? pendingEditUserId;
  const AdminDashboard({super.key, this.pendingEditUserId});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  static const _pageSize = 10;
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  bool _hasMore = false;
  int _page = 0;
  int? _totalCount;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _filterStatusSys;
  bool?   _filterAcceso;
  bool _isAdmin = false;
  Timer? _searchDebounce;

  // Ordenamiento de la tabla
  String? _sortField;
  bool _sortAsc = true;

  // Estadísticas del Dashboard
  Map<String, int> _statusSysCounts = {};
  Map<String, int> _statusRhCounts = {};
  int _authAccountCount = 0;
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _checkAdminRole();
    _fetchStats();
    _fetchUsers();
    // Caso: se navegó desde otra pestaña (widget nuevo → initState)
    if (widget.pendingEditUserId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showUserForm(user: {'id': widget.pendingEditUserId}));
    }
  }

  @override
  void didUpdateWidget(AdminDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Caso: ya estaba en este tab y cambió el pendingEditUserId
    if (widget.pendingEditUserId != null &&
        widget.pendingEditUserId != oldWidget.pendingEditUserId) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showUserForm(user: {'id': widget.pendingEditUserId}));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _checkAdminRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();
        if (profile != null && mounted) {
          setState(() => _isAdmin = profile['role'] == 'admin');
        } else {
          setState(() => _isAdmin = (user.userMetadata?['role'] ?? '') == 'admin');
        }
      }
    } catch (e) {
      debugPrint('Error checking admin role: $e');
    }
  }

  Future<void> _fetchStats() async {
    try {
      final List<Map<String, dynamic>> allData = [];
      int offset = 0;
      const int limit = 1000;

      // Obtener todos los registros paginados porque Supabase tiene un límite de 1000 por request
      while (true) {
        final data = await Supabase.instance.client
            .from('profiles')
            .select('status_sys, status_rh, has_auth_account')
            .range(offset, offset + limit - 1);
            
        allData.addAll(List<Map<String, dynamic>>.from(data));
        if (data.length < limit) break;
        offset += limit;
      }
      
      final sysCounts = <String, int>{};
      final rhCounts = <String, int>{};
      int authCount = 0;

      for (var row in allData) {
        final sys = row['status_sys'] as String? ?? 'NO APLICA';
        final rh = row['status_rh'] as String? ?? 'BAJA';
        final hasAuth = row['has_auth_account'] == true;

        sysCounts[sys] = (sysCounts[sys] ?? 0) + 1;
        rhCounts[rh] = (rhCounts[rh] ?? 0) + 1;
        
        if (hasAuth) {
          authCount++;
        }
      }

      if (mounted) {
        setState(() {
          _statusSysCounts = sysCounts;
          _statusRhCounts = rhCounts;
          _authAccountCount = authCount;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching stats: $e');
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    try {
      final from = _page * _pageSize;
      final q = _searchQuery.trim();

      // Divide la búsqueda en palabras para soportar "nombre apellido"
      // Cada palabra debe aparecer en al menos uno de los campos (AND entre palabras)
      final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

      var dataQuery = Supabase.instance.client
          .from('profiles')
          .select('id, nombre, paterno, materno, email, numero_empleado, role, is_blocked, status_sys, status_rh, permissions, full_name, has_auth_account, mail_user, mail_pass');
      var countQuery =
          Supabase.instance.client.from('profiles').count(CountOption.exact);

      if (_filterStatusSys != null) {
        dataQuery  = dataQuery.eq('status_sys', _filterStatusSys!);
        countQuery = countQuery.eq('status_sys', _filterStatusSys!);
      }
      if (_filterAcceso != null) {
        dataQuery  = dataQuery.eq('has_auth_account', _filterAcceso!);
        countQuery = countQuery.eq('has_auth_account', _filterAcceso!);
      }

      if (words.isNotEmpty) {
        for (final word in words) {
          final f = 'nombre.ilike.%$word%,paterno.ilike.%$word%,materno.ilike.%$word%,email.ilike.%$word%,numero_empleado.ilike.%$word%,full_name.ilike.%$word%,mail_user.ilike.%$word%';
          dataQuery = dataQuery.or(f);
          countQuery = countQuery.or(f);
        }
      }

      final dataFuture = dataQuery
          .order('numero_empleado', ascending: false, nullsFirst: false)
          .range(from, from + _pageSize);
      final countFuture = countQuery;

      final data = await dataFuture;
      final total = await countFuture;

      final rows = List<Map<String, dynamic>>.from(data);
      final hasMore = rows.length > _pageSize;

      if (mounted) {
        setState(() {
          _users = hasMore ? rows.sublist(0, _pageSize) : rows;
          _hasMore = hasMore;
          _totalCount = total;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar usuarios: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al cargar usuarios: $e'),
          backgroundColor: SiColors.of(context).danger,
        ));
      }
    }
  }

  Future<void> _refreshUsers() {
    _page = 0;
    _fetchStats();
    return _fetchUsers();
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    setState(() => _searchQuery = v);
    if (v.isEmpty) {
      _page = 0;
      _fetchUsers();
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _page = 0;
      _fetchUsers();
    });
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
          .rpc('delete_user_admin', params: {'user_id_param': id});
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

  void _showAccessDialog(Map<String, dynamic> user) {
    showFullWidthModal(
      context: context,
      builder: (ctx) => _AccessSheet(
        user: user,
        onSaved: () {
          _fetchUsers();
          _fetchStats();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Acceso actualizado')),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final items = _users;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDashboardSummary(c),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshUsers,
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

  Widget _buildDashboardSummary(SiColors c) {
    if (_isLoadingStats) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    Widget statCard(String title, List<Widget> children) {
      return Container(
        width: 260,
        margin: const EdgeInsets.only(right: SiSpace.x4),
        padding: const EdgeInsets.all(SiSpace.x4),
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: SiRadius.rLg,
          border: Border.all(color: c.line),
          boxShadow: SiShadows.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.brand, letterSpacing: 0.5)),
            const SizedBox(height: SiSpace.x3),
            ...children,
          ],
        ),
      );
    }

    Widget rowStat(String label, int value, Color color) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: c.ink3, fontWeight: FontWeight.w500)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: SiRadius.rPill),
              child: Text(value.toString(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.line, width: 1)),
      ),
      padding: const EdgeInsets.all(SiSpace.x6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            statCard('ESTATUS DE SISTEMA', [
              rowStat('ACTIVO',   _statusSysCounts['ACTIVO']   ?? 0, c.success),
              rowStat('BAJA',     _statusSysCounts['BAJA']     ?? 0, c.danger),
              rowStat('CAMBIO',   _statusSysCounts['CAMBIO']   ?? 0, c.warn),
              rowStat('NO APLICA',_statusSysCounts['NO APLICA']?? 0, c.ink3),
            ]),
            statCard('ESTATUS DE RH', [
              rowStat('ACTIVO', _statusRhCounts['ACTIVO'] ?? 0, c.success),
              rowStat('BAJA', _statusRhCounts['BAJA'] ?? 0, c.danger),
              rowStat('REINGRESO / CAMBIO', (_statusRhCounts['REINGRESO'] ?? 0) + (_statusRhCounts['CAMBIO'] ?? 0), c.warn),
            ]),
            statCard('AUTENTICACIÓN', [
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: c.brandTint, borderRadius: SiRadius.rMd),
                    child: Icon(Icons.shield_outlined, size: 28, color: c.brand),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CUENTAS ACTIVAS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c.ink4, letterSpacing: 0.5)),
                      Text(_authAccountCount.toString(), style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: c.ink, height: 1.1)),
                    ],
                  ),
                ],
              ),
            ]),
          ],
        ),
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
          horizontal: SiSpace.x4, vertical: SiSpace.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
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
                            _searchDebounce?.cancel();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  isDense: true,
                ),
                onChanged: _onSearchChanged,
              ),
            ),
          ),
          const SizedBox(width: SiSpace.x3),
          _buildFilterDropdown<String?>(
            c,
            label: 'STATUS SYS',
            value: _filterStatusSys,
            isActive: _filterStatusSys != null,
            items: [
              DropdownMenuItem(value: null, child: Text('Todos', style: TextStyle(color: c.ink3))),
              ...['ACTIVO', 'BAJA', 'CAMBIO', 'ELIMINAR', 'NO APLICA']
                  .map((s) => DropdownMenuItem(value: s, child: Text(s))),
            ],
            onChanged: (val) {
              setState(() { _filterStatusSys = val; _page = 0; });
              _fetchUsers();
            },
          ),
          const SizedBox(width: SiSpace.x3),
          _buildFilterDropdown<bool?>(
            c,
            label: 'ACCESO',
            value: _filterAcceso,
            isActive: _filterAcceso != null,
            items: [
              DropdownMenuItem(value: null, child: Text('Todos', style: TextStyle(color: c.ink3))),
              DropdownMenuItem(value: true, child: Text('Con acceso')),
              DropdownMenuItem(value: false, child: Text('Sin acceso')),
            ],
            onChanged: (val) {
              setState(() { _filterAcceso = val; _page = 0; });
              _fetchUsers();
            },
          ),
          const SizedBox(width: SiSpace.x3),
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
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SiSpace.x6),
            child: Center(
              child: Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    _buildToolbar(c),
                    if (items.isEmpty)
                      SizedBox(height: 300, child: _buildEmpty(c))
                    else ...[
                      // Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: SiSpace.x5, vertical: SiSpace.x3),
                        decoration: BoxDecoration(
                            border: Border(
                                bottom:
                                    BorderSide(color: c.line, width: 1))),
                        child: Row(
                          children: [
                            _colHeader(c, 'USUARIO', flex: 4, sortKey: 'paterno'),
                            _colHeader(c, 'NO. EMP.', flex: 2, sortKey: 'numero_empleado'),
                            _colHeader(c, 'ROL', flex: 2, sortKey: 'role'),
                            _colHeader(c, 'STATUS SYS', flex: 2, sortKey: 'status_sys'),
                            _colHeader(c, 'STATUS RH', flex: 2, sortKey: 'status_rh'),
                            _colHeader(c, 'ACCESO', flex: 2, sortKey: 'has_auth_account'),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                      // Rows
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        ..._sortedItems(items).asMap().entries.map((e) {
                            final i = e.key;
                            final u = e.value;
                            final role = u['role'] ?? 'usuario';
                            final isBlocked = u['is_blocked'] ?? false;
                            final nombre =
                                '${u['nombre'] ?? ''} ${u['paterno'] ?? ''} ${u['materno'] ?? ''}'
                                    .trim();
                            final parts = nombre
                                .split(' ')
                                .where((s) => s.isNotEmpty)
                                .toList();
                            final initials = parts.length > 1
                                ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
                                : (parts.isNotEmpty
                                    ? parts[0][0].toUpperCase()
                                    : '?');

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: SiSpace.x5,
                                  vertical: SiSpace.x2 + 2),
                              decoration: BoxDecoration(
                                color: i.isOdd ? c.bg : c.panel,
                                border: Border(
                                    bottom: BorderSide(
                                        color: c.line2, width: 0.5)),
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
                                                color: role == 'admin'
                                                    ? c.brand
                                                    : c.ink3,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                      const SizedBox(width: SiSpace.x3),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              nombre.isEmpty
                                                  ? 'Sin nombre'
                                                  : nombre,
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                  color: isBlocked ? c.danger : c.ink,
                                                  decoration: null),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(u['email'] ?? '',
                                                style: TextStyle(
                                                    color: c.ink4,
                                                    fontSize: 11),
                                                overflow: TextOverflow.ellipsis),
                                            if ((u['mail_user'] as String?)?.isNotEmpty == true)
                                              Text(u['mail_user'],
                                                  style: TextStyle(
                                                      color: c.brand.withOpacity(0.75),
                                                      fontSize: 10),
                                                  overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                    ]),
                                  ),
                                  // No. emp
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                        u['numero_empleado'] ?? '----',
                                        style: TextStyle(
                                            fontSize: 13, color: c.ink2)),
                                  ),
                                  // Rol
                                  Expanded(
                                    flex: 2,
                                    child: _RoleBadge(role: role, c: c),
                                  ),
                                  // Status Sys
                                  Expanded(
                                    flex: 2,
                                    child: _StatusBadge(
                                        isBlocked: isBlocked,
                                        statusSys: u['status_sys'],
                                        c: c),
                                  ),
                                  // Status RH
                                  Expanded(
                                    flex: 2,
                                    child: _StatusRhBadge(
                                        statusRh: u['status_rh'],
                                        c: c),
                                  ),
                                  // Acceso
                                  Expanded(
                                    flex: 2,
                                    child: _AuthBadge(
                                        hasAuth: u['has_auth_account'] == true,
                                        c: c),
                                  ),
                                  // Acciones
                                  SizedBox(
                                    width: 48,
                                    child: _isAdmin
                                        ? PopupMenuButton<String>(
                                            icon: Icon(Icons.more_horiz,
                                                size: 18, color: c.ink4),
                                            onSelected: (v) {
                                              if (v == 'edit') _showUserForm(user: u);
                                              else if (v == 'access') _showAccessDialog(u);
                                              else _deleteUser(u['id']);
                                            },
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
                                                value: 'access',
                                                child: Row(children: [
                                                  Icon(Icons.shield_outlined,
                                                      size: 16, color: c.brand),
                                                  const SizedBox(width: 12),
                                                  Text('Acceso',
                                                      style: TextStyle(color: c.brand)),
                                                ]),
                                              ),
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Row(children: [
                                                  Icon(Icons.delete_outline,
                                                      size: 16,
                                                      color: c.danger),
                                                  const SizedBox(width: 12),
                                                  Text('Eliminar',
                                                      style: TextStyle(
                                                          color: c.danger)),
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
                    _buildPaginator(c),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onSort(String field) {
    setState(() {
      if (_sortField == field) {
        _sortAsc = !_sortAsc;
      } else {
        _sortField = field;
        _sortAsc = true;
      }
    });
  }

  List<Map<String, dynamic>> _sortedItems(List<Map<String, dynamic>> items) {
    if (_sortField == null) return items;
    final sorted = [...items];
    sorted.sort((a, b) {
      dynamic va = a[_sortField];
      dynamic vb = b[_sortField];
      // Numérico para numero_empleado
      if (_sortField == 'numero_empleado') {
        va = int.tryParse(va?.toString() ?? '') ?? 0;
        vb = int.tryParse(vb?.toString() ?? '') ?? 0;
        return _sortAsc ? (va as int).compareTo(vb) : (vb as int).compareTo(va);
      }
      // Booleano: true (activo) primero en ascendente
      if (_sortField == 'has_auth_account') {
        final ia = (va == true) ? 1 : 0;
        final ib = (vb == true) ? 1 : 0;
        return _sortAsc ? ib.compareTo(ia) : ia.compareTo(ib);
      }
      // Texto para el resto
      final sa = (va ?? '').toString().toLowerCase();
      final sb = (vb ?? '').toString().toLowerCase();
      return _sortAsc ? sa.compareTo(sb) : sb.compareTo(sa);
    });
    return sorted;
  }

  Widget _buildFilterDropdown<T>(
    SiColors c, {
    required String label,
    required T value,
    required bool isActive,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: isActive ? c.brand : c.ink4,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isActive ? c.brandTint : c.bg,
            borderRadius: SiRadius.rMd,
            border: Border.all(color: isActive ? c.brand : c.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              hint: Text('Todos', style: TextStyle(fontSize: 12, color: c.ink3)),
              style: TextStyle(fontSize: 12, color: c.ink),
              icon: Icon(Icons.arrow_drop_down, size: 16, color: c.ink3),
              isDense: true,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _colHeader(SiColors c, String label, {int flex = 1, String? sortKey}) {
    final isActive = _sortField == sortKey;
    return Expanded(
      flex: flex,
      child: sortKey == null
          ? Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c.ink4,
                  letterSpacing: 0.8))
          : InkWell(
              onTap: () => _onSort(sortKey),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isActive ? c.brand : c.ink4,
                            letterSpacing: 0.8)),
                    const SizedBox(width: 3),
                    Icon(
                      isActive
                          ? (_sortAsc
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded)
                          : Icons.unfold_more_rounded,
                      size: 13,
                      color: isActive ? c.brand : c.ink4,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMobileList(SiColors c, List<Map<String, dynamic>> items) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(SiSpace.x4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            _buildToolbar(c),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              SizedBox(height: 300, child: _buildEmpty(c))
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
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
                color: isBlocked ? c.danger : c.ink,
                decoration: null,
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
                    onSelected: (v) {
                      if (v == 'edit') _showUserForm(user: u);
                      else if (v == 'access') _showAccessDialog(u);
                      else _deleteUser(u['id']);
                    },
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
                        value: 'access',
                        child: Row(children: [
                          Icon(Icons.shield_outlined, size: 16, color: c.brand),
                          const SizedBox(width: 12),
                          Text('Acceso',
                              style: TextStyle(color: c.brand)),
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
            ),
            _buildPaginator(c),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginator(SiColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SiSpace.x6, vertical: SiSpace.x3),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(top: BorderSide(color: c.line, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.chevron_left,
                color: _page > 0 ? c.ink2 : c.line),
            onPressed: _page > 0
                ? () {
                    setState(() => _page--);
                    _fetchUsers();
                  }
                : null,
          ),
          const SizedBox(width: SiSpace.x2),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Página ${_page + 1}${_totalCount != null ? ' de ${((_totalCount! + _pageSize - 1) ~/ _pageSize)}' : ''}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: c.ink3),
              ),
              if (_totalCount != null)
                Text(
                  '$_totalCount usuarios',
                  style: TextStyle(fontSize: 11, color: c.ink4),
                ),
            ],
          ),
          const SizedBox(width: SiSpace.x2),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.chevron_right,
                color: _hasMore ? c.ink2 : c.line),
            onPressed: _hasMore
                ? () {
                    setState(() => _page++);
                    _fetchUsers();
                  }
                : null,
          ),
        ],
      ),
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

class _StatusRhBadge extends StatelessWidget {
  final String? statusRh;
  final SiColors c;
  const _StatusRhBadge({required this.statusRh, required this.c});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    switch (statusRh) {
      case 'ACTIVO':
        bg = c.successTint; fg = c.success;
      case 'BAJA':
        bg = c.dangerTint;  fg = c.danger;
      case 'REINGRESO':
      case 'CAMBIO':
      case 'PENDIENTE':
        bg = c.warnTint;    fg = c.warn;
      default:
        bg = c.hover;       fg = c.ink4;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: SiRadius.rPill),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 5, height: 5,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(statusRh ?? '---',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
      ]),
    );
  }
}

class _AuthBadge extends StatelessWidget {
  final bool hasAuth;
  final SiColors c;
  const _AuthBadge({required this.hasAuth, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: hasAuth ? c.successTint : c.hover,
        borderRadius: SiRadius.rPill,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          hasAuth ? Icons.shield_outlined : Icons.no_accounts_outlined,
          size: 12,
          color: hasAuth ? c.success : c.ink4,
        ),
        const SizedBox(width: 4),
        Text(
          hasAuth ? 'Activo' : 'Sin acceso',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: hasAuth ? c.success : c.ink4,
          ),
        ),
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
      _PermIcon(Icons.smart_toy_outlined, perms['show_ai'] == true),
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
  late String? _statusRh;
  late bool _isBlocked;
  late Map<String, bool> _permissions;
  final Map<String, bool> _obscure = {
    'mail': true, 'drp': true, 'gp': true,
    'bitrix': true, 'ek': true, 'otro': true,
  };
  bool _saving = false;

  bool get _isEditing => widget.user != null;

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
    _statusRh = u?['status_rh'] ?? 'ACTIVO';
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
      'show_ai': false,
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
    if (!_isEditing &&
        (_emailCtrl.text.trim().isEmpty || _passCtrl.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email y contraseña son obligatorios')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEditing) {
        // Si tiene cuenta de auth, sincronizamos rol/status/permisos en auth.users
        if (widget.user!['has_auth_account'] == true) {
          await Supabase.instance.client.rpc('update_user_admin', params: {
            'user_id_param': widget.user!['id'],
            'new_email': widget.user!['email'] ?? '',
            'new_full_name': widget.user!['full_name'] ?? '',
            'new_role': _role,
            'new_status_sys': _statusSys,
            'is_blocked_param': _isBlocked,
            'new_permissions': _permissions,
            'new_password': null,
          });
        }
        // Actualizamos el perfil directamente
        await Supabase.instance.client.from('profiles').update({
          'role': _role,
          'status_sys': _statusSys,
          'status_rh': _statusRh,
          'is_blocked': _isBlocked,
          'permissions': _permissions,
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
        // Nuevo usuario desde botón +: crea cuenta auth + perfil
        final res = await Supabase.instance.client
            .rpc('create_user_admin', params: {
          'email': _emailCtrl.text.trim(),
          'password': _passCtrl.text.trim(),
          'full_name': '',
          'user_role': _role,
        });
        if (res != null) {
          await Supabase.instance.client.from('profiles').update({
            'status_sys': _statusSys,
            'status_rh': _statusRh,
            'permissions': _permissions,
            'role': _role,
            'mail_user': _mailUser.text.trim(),
            'mail_pass': _mailPass.text.trim(),
          }).eq('id', res);
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

    final title = _isEditing
        ? 'Editar ${widget.user!['nombre'] ?? ''}'
        : 'Nuevo usuario';

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isEditing) ...[
                    _buildUserInfoCard(c),
                    const SizedBox(height: SiSpace.x6),
                    Divider(color: c.line),
                    const SizedBox(height: SiSpace.x6),
                  ],
                  if (isDesktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildGeneralSection(c)),
                        const SizedBox(width: SiSpace.x8),
                        Expanded(child: _buildPermissionsSection(c)),
                        const SizedBox(width: SiSpace.x8),
                        Expanded(child: _buildCredentialsSection(c)),
                      ],
                    )
                  else
                    Column(children: [
                      _buildGeneralSection(c),
                      const SizedBox(height: SiSpace.x6),
                      Divider(color: c.line),
                      const SizedBox(height: SiSpace.x6),
                      _buildPermissionsSection(c),
                      const SizedBox(height: SiSpace.x6),
                      Divider(color: c.line),
                      const SizedBox(height: SiSpace.x6),
                      _buildCredentialsSection(c),
                      const SizedBox(height: SiSpace.x6),
                    ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── User info card (read-only, shown only in edit mode) ──────────────────────

  Widget _buildUserInfoCard(SiColors c) {
    final u = widget.user!;
    final nombre = '${u['nombre'] ?? ''} ${u['paterno'] ?? ''} ${u['materno'] ?? ''}'
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    final avatarUrl = u['foto_url'] as String?;
    final parts    = nombre.split(' ').where((s) => s.isNotEmpty).toList();
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : parts.isNotEmpty ? parts[0][0].toUpperCase() : '?';

    final items = <(IconData, String)>[
      if ((u['numero_empleado'] ?? '').toString().isNotEmpty)
        (Icons.badge_outlined,       u['numero_empleado'].toString()),
      if ((u['tipo_empresa'] ?? '').toString().isNotEmpty)
        (Icons.business_outlined,    u['tipo_empresa'].toString()),
      if ((u['puesto'] ?? '').toString().isNotEmpty)
        (Icons.work_outline_rounded, u['puesto'].toString()),
      if ((u['ubicacion'] ?? '').toString().isNotEmpty)
        (Icons.location_on_outlined, u['ubicacion'].toString()),
    ];

    return Container(
      padding: const EdgeInsets.all(SiSpace.x4),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: SiRadius.rLg,
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 30,
            backgroundColor: c.brandTint,
            backgroundImage:
                avatarUrl != null && avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : null,
            child: avatarUrl == null || avatarUrl.isEmpty
                ? Text(initials,
                    style: TextStyle(
                        color: c.brand,
                        fontWeight: FontWeight.w700,
                        fontSize: 17))
                : null,
          ),
          const SizedBox(width: SiSpace.x4),
          // Datos
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoChip(
                  c,
                  Icons.person_outline,
                  nombre.isEmpty ? 'Sin nombre' : nombre,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  iconColor: c.ink3,
                  textColor: c.ink,
                ),
                if ((u['email'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _infoChip(
                      c,
                      Icons.alternate_email,
                      u['email'].toString(),
                      fontSize: 12,
                      iconColor: c.ink4,
                      textColor: c.ink4,
                    ),
                  ),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: SiSpace.x2),
                  Wrap(
                    spacing: SiSpace.x4,
                    runSpacing: SiSpace.x1,
                    children: items
                        .map((t) => _infoChip(c, t.$1, t.$2))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(
    SiColors c,
    IconData icon,
    String text, {
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.w400,
    Color? iconColor,
    Color? textColor,
  }) {
    final iColor = iconColor ?? c.ink4;
    final tColor = textColor ?? c.ink3;
    return Tooltip(
      message: 'Copiar',
      child: InkWell(
        borderRadius: SiRadius.rSm,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Copiado: $text'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: iColor),
              const SizedBox(width: 4),
              Text(text,
                  style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: fontWeight,
                      color: tColor)),
            ],
          ),
        ),
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
        // Status Sys
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
        // Status RH
        DropdownButtonFormField<String>(
          value: _statusRh,
          decoration: const InputDecoration(
              labelText: 'Status RH',
              prefixIcon: Icon(Icons.person_outlined)),
          items: ['ACTIVO', 'BAJA', 'REINGRESO', 'CAMBIO', 'PENDIENTE']
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) => setState(() => _statusRh = v),
        ),
        const SizedBox(height: SiSpace.x4),
        // Email y contraseña solo al crear un usuario nuevo (botón +)
        if (!_isEditing) ...[
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
            decoration: const InputDecoration(
                labelText: 'Contraseña *',
                prefixIcon: Icon(Icons.lock_outlined)),
          ),
          const SizedBox(height: SiSpace.x4),
        ],
        // Rol
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
        // Bloqueado toggle
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
        _permSwitch(c, 'Tablas', 'show_tablas', Icons.table_chart_outlined),
        _permSwitch(c, 'Asistente IA', 'show_ai', Icons.smart_toy_outlined),
      ],
    );
  }

  Widget _permSwitch(
      SiColors c, String label, String key, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Transform.scale(
            scale: 0.72,
            alignment: Alignment.centerLeft,
            child: Switch(
              value: _permissions[key] ?? false,
              onChanged: (v) => setState(() => _permissions[key] = v),
              activeColor: c.brand,
            ),
          ),
          Icon(icon, size: 16, color: c.ink3),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13, color: c.ink)),
          ),
        ],
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

// ── Access sheet ─────────────────────────────────────────────────────────────

class _AccessSheet extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onSaved;
  const _AccessSheet({required this.user, required this.onSaved});

  @override
  State<_AccessSheet> createState() => _AccessSheetState();
}

class _AccessSheetState extends State<_AccessSheet> {
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passCtrl;
  final TextEditingController _newPassCtrl = TextEditingController();
  bool _saving = false;
  bool _hasAuth = false;
  bool _obscureNew = true;

  @override
  void initState() {
    super.initState();
    _hasAuth = widget.user['has_auth_account'] == true;
    _emailCtrl = TextEditingController(
      text: widget.user['mail_user'] ?? widget.user['email'] ?? '',
    );
    _passCtrl = TextEditingController(
      text: widget.user['mail_pass'] ?? '',
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _grantAccess() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Correo y contraseña son requeridos')),
      );
      return;
    }
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('create_user_admin', params: {
        'email': _emailCtrl.text.trim(),
        'password': _passCtrl.text.trim(),
        'full_name': widget.user['full_name'] ?? '',
        'user_role': widget.user['role'] ?? 'usuario',
        'user_id_param': widget.user['id'],
      });
      await Supabase.instance.client.from('profiles').update({
        'has_auth_account': true,
        'mail_user': _emailCtrl.text.trim(),
      }).eq('id', widget.user['id']);
      if (mounted) {
        navigator.pop();
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

  Future<void> _changePassword() async {
    final pw = _newPassCtrl.text.trim();
    if (pw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa la nueva contraseña')),
      );
      return;
    }
    if (pw.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La contraseña debe tener al menos 6 caracteres')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('update_user_password', params: {
        'user_id_param': widget.user['id'],
        'new_password': pw,
      });
      _newPassCtrl.clear();
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contraseña actualizada correctamente')),
        );
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

  Future<void> _revokeAccess() async {
    final c = SiColors.of(context);
    // Capturar navigator antes de cualquier operación async para evitar
    // usar un contexto stale que pueda popear la pantalla incorrecta
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: c.danger, size: 22),
          const SizedBox(width: 8),
          const Text('Revocar acceso'),
        ]),
        content: const Text(
            '¿Deseas revocar el acceso de inicio de sesión? El perfil del colaborador se conservará.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text('Revocar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      // Solo elimina la cuenta auth; el perfil se conserva
      await Supabase.instance.client.rpc('revoke_user_access',
          params: {'user_id_param': widget.user['id']});
      await Supabase.instance.client.from('profiles').update({
        'has_auth_account': false,
      }).eq('id', widget.user['id']);
      if (mounted) {
        navigator.pop();
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al revocar: $e'),
          backgroundColor: SiColors.of(context).danger,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final nombre = widget.user['full_name'] ??
        '${widget.user['nombre'] ?? ''} ${widget.user['paterno'] ?? ''}'.trim();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
              border: Border(bottom: BorderSide(color: c.line, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancelar',
                      style: TextStyle(fontSize: 15, color: c.ink3)),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.shield_outlined, size: 18, color: c.brand),
                  const SizedBox(width: 8),
                  Text('Acceso al sistema',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: c.ink)),
                ]),
                if (_saving)
                  const SizedBox(
                    width: 60,
                    child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                else
                  const SizedBox(width: 60),
              ],
            ),
          ),
          // Body
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: SiSpace.x6,
                right: SiSpace.x6,
                top: SiSpace.x5,
                bottom: MediaQuery.of(context).viewInsets.bottom + SiSpace.x6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Estado actual
                  Container(
                    padding: const EdgeInsets.all(SiSpace.x4),
                    decoration: BoxDecoration(
                      color: _hasAuth ? c.successTint : c.warnTint,
                      borderRadius: SiRadius.rMd,
                      border: Border.all(
                          color: _hasAuth ? c.success : c.warn,
                          width: 1),
                    ),
                    child: Row(children: [
                      Icon(
                        _hasAuth
                            ? Icons.verified_user_outlined
                            : Icons.person_off_outlined,
                        color: _hasAuth ? c.success : c.warn,
                        size: 24,
                      ),
                      const SizedBox(width: SiSpace.x3),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(nombre,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: c.ink)),
                              Text(
                                _hasAuth
                                    ? 'Cuenta de acceso activa'
                                    : 'Sin cuenta de acceso al sistema',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: _hasAuth ? c.success : c.warn),
                              ),
                            ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: SiSpace.x5),
                  if (!_hasAuth) ...[
                    Text('CREAR ACCESO',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: c.brand,
                            letterSpacing: 0.8)),
                    const SizedBox(height: SiSpace.x4),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo de acceso *',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: SiSpace.x4),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña *',
                        prefixIcon: Icon(Icons.lock_outlined),
                      ),
                    ),
                    const SizedBox(height: SiSpace.x5),
                    FilledButton.icon(
                      onPressed: _saving ? null : _grantAccess,
                      icon: const Icon(Icons.shield_outlined, size: 18),
                      label: const Text('Crear acceso',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: c.brand,
                        minimumSize: const Size(double.infinity, 48),
                        shape: const RoundedRectangleBorder(
                            borderRadius: SiRadius.rMd),
                      ),
                    ),
                  ] else ...[
                    // ── Cambiar contraseña ──────────────────────────────────
                    Text('CAMBIAR CONTRASEÑA',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: c.brand,
                            letterSpacing: 0.8)),
                    const SizedBox(height: SiSpace.x4),
                    TextField(
                      controller: _newPassCtrl,
                      obscureText: _obscureNew,
                      decoration: InputDecoration(
                        labelText: 'Nueva contraseña',
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureNew
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                    ),
                    const SizedBox(height: SiSpace.x4),
                    FilledButton.icon(
                      onPressed: _saving ? null : _changePassword,
                      icon: const Icon(Icons.lock_reset_outlined, size: 18),
                      label: const Text('Actualizar contraseña',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: c.brand,
                        minimumSize: const Size(double.infinity, 48),
                        shape: const RoundedRectangleBorder(
                            borderRadius: SiRadius.rMd),
                      ),
                    ),
                    const SizedBox(height: SiSpace.x5),
                    Divider(color: c.line),
                    const SizedBox(height: SiSpace.x4),
                    // ── Revocar acceso ──────────────────────────────────────
                    Text('REVOCAR ACCESO',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: c.danger,
                            letterSpacing: 0.8)),
                    const SizedBox(height: SiSpace.x3),
                    Text(
                      'Elimina la cuenta de inicio de sesión. El perfil del colaborador se conservará.',
                      style: TextStyle(fontSize: 13, color: c.ink3),
                    ),
                    const SizedBox(height: SiSpace.x4),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _revokeAccess,
                      icon: Icon(Icons.no_accounts_outlined,
                          size: 18, color: c.danger),
                      label: Text('Revocar acceso',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, color: c.danger)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: c.danger),
                        minimumSize: const Size(double.infinity, 48),
                        shape: const RoundedRectangleBorder(
                            borderRadius: SiRadius.rMd),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
