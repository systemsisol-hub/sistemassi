import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/notification_service.dart';

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
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: screenWidth,
              child: builder(dialogContext),
            ),
          ),
        );
      },
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
  List<Map<String, dynamic>> _collaborators = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminRole();
    _fetchUsers();
    _fetchCollaborators();
  }

  Widget _buildGlassPill({required Widget child, EdgeInsetsGeometry? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildControls(ThemeData theme) {
    return _buildGlassPill(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1, indent: 8, endIndent: 8),
          GestureDetector(
            onTap: () => _showUserForm(),
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.add, size: 22, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkAdminRole() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final role = user.userMetadata?['role'] ?? 'usuario';
        setState(() => _isAdmin = role == 'admin');
      }
    } catch (e) {
      debugPrint('Error checking admin role: $e');
    }
  }

  Future<void> _fetchCollaborators() async {
    try {
      List<Map<String, dynamic>> allData = [];
      int offset = 0;
      const int limit = 1000;

      while (true) {
        final data = await Supabase.instance.client
            .from('profiles')
            .select('id, nombre, paterno, materno, numero_empleado, status_sys')
            .not('nombre', 'is', null)
            .order('nombre')
            .range(offset, offset + limit - 1);

        allData.addAll(List<Map<String, dynamic>>.from(data));

        if (data.length < limit) break;
        offset += limit;
      }

      if (mounted) {
        setState(() => _collaborators = allData);
      }
    } catch (e) {
      debugPrint('Error fetching collaborators: $e');
    }
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    try {
      List<Map<String, dynamic>> allData = [];
      int offset = 0;
      const int limit = 1000;

      while (true) {
        final data = await Supabase.instance.client
            .from('profiles')
            .select('*')
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);

        allData.addAll(List<Map<String, dynamic>>.from(data));

        if (data.length < limit) break;
        offset += limit;
      }

      if (mounted) {
        allData.sort((a, b) {
          final aIsCambio = (a['status_sys'] == 'CAMBIO') ? 0 : 1;
          final bIsCambio = (b['status_sys'] == 'CAMBIO') ? 0 : 1;
          if (aIsCambio != bIsCambio) return aIsCambio.compareTo(bIsCambio);
          final aNum =
              int.tryParse(a['numero_empleado']?.toString() ?? '') ?? -1;
          final bNum =
              int.tryParse(b['numero_empleado']?.toString() ?? '') ?? -1;
          return bNum.compareTo(aNum);
        });
        setState(() => _users = allData);
      }
    } catch (e) {
      debugPrint('Error al cargar usuarios: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar usuarios: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteUser(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Eliminar Usuario'),
          ],
        ),
        content: const Text(
          '¿Estás seguro de que deseas eliminar este perfil? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await Supabase.instance.client.rpc('delete_user_admin', params: {'user_id': id});
        _fetchUsers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Usuario y perfil eliminados correctamente'),
                backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        debugPrint('Error al eliminar: $e');
      }
    }
  }

  void _showUserForm({Map<String, dynamic>? user}) {
    final isEditing = user != null;
    // isGrantingAccess = profile exists (isEditing) but has NO auth account yet.
    // We use has_auth_account (set by the handle_new_user trigger) as the reliable signal.
    final isGrantingAccess = isEditing && (user['has_auth_account'] != true);
    final theme = Theme.of(context);
    final nombreController = TextEditingController(text: user?['nombre']);
    final paternoController = TextEditingController(text: user?['paterno']);
    final maternoController = TextEditingController(text: user?['materno']);
    final employeeNumberController = TextEditingController(text: user?['numero_empleado']);
    final emailController = TextEditingController(text: user?['email']);
    final passwordController = TextEditingController();
    String role = user?['role'] ?? 'usuario';
    String? statusSys = user?['status_sys'] ?? 'ACTIVO';
    bool isBlocked = user?['is_blocked'] ?? false;
    final permissions = Map<String, bool>.from(user?['permissions'] ??
        {
          'show_calendar': false,
          'show_users': false,
          'show_issi': false,
          'show_cssi': false,
          'show_incidencias': false,
          'show_logs': false,
          'show_external_contacts': false,
          'show_asistencia': false,
          'show_powerbi': false,
        });

    // Credential Controllers
    final mailUser = TextEditingController(text: user?['mail_user']);
    final mailPass = TextEditingController(text: user?['mail_pass']);
    final drpUser = TextEditingController(text: user?['drp_user']);
    final drpPass = TextEditingController(text: user?['drp_pass']);
    final gpUser = TextEditingController(text: user?['gp_user']);
    final gpPass = TextEditingController(text: user?['gp_pass']);
    final bitrixUser = TextEditingController(text: user?['bitrix_user']);
    final bitrixPass = TextEditingController(text: user?['bitrix_pass']);
    final ekUser = TextEditingController(text: user?['ek_user']);
    final ekPass = TextEditingController(text: user?['ek_pass']);
    final otroUser = TextEditingController(text: user?['otro_user']);
    final otroPass = TextEditingController(text: user?['otro_pass']);

    final Map<String, bool> obscureStatus = {
      'mail': true,
      'drp': true,
      'gp': true,
      'bitrix': true,
      'ek': true,
      'otro': true,
    };

    showFullWidthModal(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDesktop = MediaQuery.of(context).size.width > 800;

          final Widget generalSection = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('CONTROL',
                  style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: statusSys,
                decoration: const InputDecoration(
                  labelText: 'System Sys',
                  prefixIcon: Icon(Icons.settings_suggest_outlined),
                  filled: true,
                ),
                items: ['ACTIVO', 'BAJA', 'CAMBIO', 'ELIMINAR', 'NO APLICA']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (val) => setDialogState(() => statusSys = val),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                    labelText: 'Correo Electrónico',
                    prefixIcon: Icon(Icons.email)),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                    labelText: 'Contraseña (Dejar vacío para no cambiar)',
                    prefixIcon: Icon(Icons.lock)),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(
                    labelText: 'Rol del Sistema',
                    prefixIcon: Icon(Icons.admin_panel_settings)),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'usuario', child: Text('Usuario')),
                  DropdownMenuItem(
                      value: 'admin', child: Text('Administrador')),
                ],
                onChanged: (val) => setDialogState(() => role = val!),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: const Text('Cuenta', style: TextStyle(fontSize: 14)),
                subtitle: Text(isBlocked ? 'BLOQUEADA' : 'ACTIVA'),
                leading: Icon(isBlocked ? Icons.block : Icons.check_circle,
                    color: isBlocked ? Colors.red : Colors.green),
                trailing: Transform.scale(
                  scale: 0.7,
                  child: Switch(
                    value: !isBlocked,
                    onChanged: (val) => setDialogState(() => isBlocked = !val),
                  ),
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          );

          final Widget permissionsSection = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ACCESOS (VISIBILIDAD)',
                  style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary)),
              const SizedBox(height: 16),
              _buildPermissionSwitch('Calendario', 'show_calendar',
                  Icons.calendar_month, permissions, setDialogState),
              _buildPermissionSwitch('Gestión de Usuarios', 'show_users',
                  Icons.group, permissions, setDialogState),
              _buildPermissionSwitch('Inventario ISSI', 'show_issi',
                  Icons.inventory_2, permissions, setDialogState),
              _buildPermissionSwitch('Colaboradores CSSI', 'show_cssi',
                  Icons.badge, permissions, setDialogState),
              _buildPermissionSwitch('Incidencias', 'show_incidencias',
                  Icons.description, permissions, setDialogState),
              _buildPermissionSwitch('Logs del Sistema', 'show_logs',
                  Icons.assignment, permissions, setDialogState),
              _buildPermissionSwitch(
                  'Contactos Externos',
                  'show_external_contacts',
                  Icons.contact_phone,
                  permissions,
                  setDialogState),
              _buildPermissionSwitch('Asistencia', 'show_asistencia',
                  Icons.fingerprint, permissions, setDialogState),
              _buildPermissionSwitch('Power BI', 'show_powerbi',
                  Icons.bar_chart, permissions, setDialogState),
            ],
          );

          final Widget credentialsSection = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('CREDENCIALES DE SISTEMAS',
                  style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary)),
              const SizedBox(height: 16),
              _buildCredentialRow('Mail', mailUser, mailPass, 'mail',
                  obscureStatus, setDialogState),
              _buildCredentialRow('DRP', drpUser, drpPass, 'drp', obscureStatus,
                  setDialogState),
              _buildCredentialRow(
                  'GP', gpUser, gpPass, 'gp', obscureStatus, setDialogState),
              _buildCredentialRow('BITRIX', bitrixUser, bitrixPass, 'bitrix',
                  obscureStatus, setDialogState),
              _buildCredentialRow('ENKONTROL', ekUser, ekPass, 'ek',
                  obscureStatus, setDialogState),
              _buildCredentialRow('OTRO', otroUser, otroPass, 'otro',
                  obscureStatus, setDialogState),
            ],
          );

          return Container(
            width: isDesktop ? MediaQuery.of(context).size.width : double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ),
                      Text(
                        isGrantingAccess
                            ? 'Conceder Acceso'
                            : (isEditing
                                ? 'Editar ${user['nombre'] ?? ''}'
                                : 'Crear Nuevo Usuario'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (emailController.text.trim().isEmpty || (!isEditing && passwordController.text.trim().isEmpty)) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email y contraseña son obligatorios')));
                            return;
                          }
                          try {
                            if (isEditing && !isGrantingAccess) {
                              await Supabase.instance.client.rpc('update_user_admin', params: {
                                'user_id_param': user['id'],
                                'new_email': emailController.text.trim(),
                                'new_full_name': '${nombreController.text} ${paternoController.text}'.trim(),
                                'new_role': role,
                                'new_status_sys': statusSys,
                                'is_blocked_param': isBlocked,
                                'new_permissions': permissions,
                                'new_password': passwordController.text.trim().isEmpty ? null : passwordController.text.trim(),
                              });
                              await Supabase.instance.client.from('profiles').update({
                                'mail_user': mailUser.text.trim(), 'mail_pass': mailPass.text.trim(),
                                'drp_user': drpUser.text.trim(), 'drp_pass': drpPass.text.trim(),
                                'gp_user': gpUser.text.trim(), 'gp_pass': gpPass.text.trim(),
                                'bitrix_user': bitrixUser.text.trim(), 'bitrix_pass': bitrixPass.text.trim(),
                                'ek_user': ekUser.text.trim(), 'ek_pass': ekPass.text.trim(),
                                'otro_user': otroUser.text.trim(), 'otro_pass': otroPass.text.trim(),
                              }).eq('id', user['id']);
                            } else {
                              final res = await Supabase.instance.client.rpc('create_user_admin', params: {
                                'email': emailController.text.trim(),
                                'password': passwordController.text.trim(),
                                'full_name': '${nombreController.text} ${paternoController.text}'.trim(),
                                'user_role': role,
                                if (isGrantingAccess) 'user_id_param': user['id'],
                              });
                              
                              if (res != null) {
                                final newId = isGrantingAccess ? user['id'] : res;
                                await Supabase.instance.client.from('profiles').update({
                                  'nombre': nombreController.text.trim(),
                                  'paterno': paternoController.text.trim(),
                                  'materno': maternoController.text.trim(),
                                  'email': emailController.text.trim(),
                                  'numero_empleado': employeeNumberController.text.trim(),
                                  'status_sys': 'ACTIVO',
                                  'permissions': permissions,
                                  'role': role,
                                  'mail_user': mailUser.text.trim(), 'mail_pass': mailPass.text.trim(),
                                }).eq('id', newId);
                              }
                            }
                            
                            if (mounted) {
                              Navigator.pop(context);
                              _fetchUsers();
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Operación exitosa'), backgroundColor: theme.colorScheme.secondary));
                            }
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                          }
                        },
                        child: Text(isEditing ? 'Guardar' : 'Crear', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(left: 24, right: 24, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
                    child: isDesktop
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: generalSection),
                              const SizedBox(width: 32),
                              Expanded(child: permissionsSection),
                              const SizedBox(width: 32),
                              Expanded(child: credentialsSection),
                            ],
                          )
                        : Column(
                            children: [
                              generalSection, const SizedBox(height: 24), const Divider(),
                              const SizedBox(height: 24), permissionsSection, const SizedBox(height: 24), const Divider(),
                              const SizedBox(height: 24), credentialsSection,
                            ],
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPermissionSwitch(String title, String key, IconData icon,
      Map<String, bool> permissions, StateSetter setDialogState) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      leading: Icon(icon, size: 20),
      trailing: Transform.scale(
        scale: 0.7,
        child: Switch(
          value: permissions[key] ?? false,
          onChanged: (val) => setDialogState(() => permissions[key] = val),
        ),
      ),
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildCredentialRow(String label, TextEditingController uCtrl, TextEditingController pCtrl, String key, Map<String, bool> obscureMap, StateSetter setDialogState) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: TextField(controller: uCtrl, decoration: InputDecoration(labelText: '$label Usuario', isDense: true))),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: pCtrl,
                obscureText: obscureMap[key] ?? true,
                decoration: InputDecoration(
                  labelText: 'Pass', isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon((obscureMap[key] ?? true) ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                    onPressed: () => setDialogState(() => obscureMap[key] = !(obscureMap[key] ?? true)),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  List<Map<String, dynamic>> get _filteredUsers {
    List<Map<String, dynamic>> result = _searchQuery.isEmpty ? List.from(_users) : _users.where((user) {
      final q = _searchQuery.toLowerCase();
      return (user['nombre'] ?? '').toString().toLowerCase().contains(q) ||
             (user['paterno'] ?? '').toString().toLowerCase().contains(q) ||
             (user['email'] ?? '').toString().toLowerCase().contains(q) ||
             (user['numero_empleado'] ?? '').toString().toLowerCase().contains(q);
    }).toList();

    result.sort((a, b) {
      final numAStr = a['numero_empleado']?.toString() ?? '';
      final numBStr = b['numero_empleado']?.toString() ?? '';
      final numA = int.tryParse(numAStr) ?? 0;
      final numB = int.tryParse(numBStr) ?? 0;
      return numB.compareTo(numA);
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final users = _filteredUsers;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 800) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildControls(theme),
                    ],
                  ),
                );
              },
            ),
          ),
          _isLoading
              ? SliverFillRemaining(
                  child: Center(
                    child: Image.asset(
                      'assets/sisol_loader.gif',
                      width: 150,
                      errorBuilder: (context, error, stackTrace) =>
                          const CircularProgressIndicator(),
                      frameBuilder:
                          (context, child, frame, wasSynchronouslyLoaded) =>
                              frame == null
                                  ? const CircularProgressIndicator()
                                  : child,
                    ),
                  ),
                )
              : users.isEmpty
                  ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_search,
                                size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'Sin resultados para "$_searchQuery"'
                                  : 'No hay usuarios registrados',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SliverFillRemaining(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isDesktop = constraints.maxWidth > 800;
                          return RefreshIndicator(
                            onRefresh: _fetchUsers,
                            child: isDesktop
                                ? _buildDesktopLayout(theme, users)
                                : _buildMobileLayout(theme, users),
                          );
                        },
                      ),
                    ),
        ],
      ),
    );
  }

  Widget _buildMiniIcon(IconData icon, bool active) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Icon(
        icon,
        size: 14,
        color: active ? const Color(0xFF344092) : Colors.grey.withOpacity(0.3),
      ),
    );
  }

  Widget _buildMobileLayout(ThemeData theme, List<Map<String, dynamic>> users) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final user = users[index];
        final String role = user['role'] ?? 'usuario';

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey[200]!),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: role == 'admin'
                  ? theme.colorScheme.tertiary.withOpacity(0.1)
                  : theme.colorScheme.secondary.withOpacity(0.1),
              child: Icon(
                role == 'admin'
                    ? Icons.admin_panel_settings
                    : Icons.person_outline,
                color: role == 'admin'
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.secondary,
              ),
            ),
            title: Text(
              '${user['numero_empleado'] ?? '----'} | ${user['nombre'] ?? ''} ${user['paterno'] ?? ''} ${user['materno'] ?? ''}'
                  .trim(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                decoration: (user['is_blocked'] ?? false)
                    ? TextDecoration.lineThrough
                    : null,
                color: (user['is_blocked'] ?? false) ? Colors.grey : null,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(user['email'] ?? 'Sin correo',
                            style: const TextStyle(fontSize: 12)),
                      ),
                      if (user['email'] != null &&
                          user['email'].toString().isNotEmpty)
                        InkWell(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: user['email'].toString()));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Correo copiado al portapapeles'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          child: const Icon(Icons.copy,
                              size: 14, color: Colors.grey),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: role == 'admin'
                              ? theme.colorScheme.tertiary.withOpacity(0.1)
                              : theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          role.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: role == 'admin'
                                ? theme.colorScheme.tertiary
                                : theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      if (user['is_blocked'] ?? false) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'BLOQUEADO',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.red),
                          ),
                        ),
                      ],
                      const SizedBox(width: 12),
                      if (user['permissions'] != null) ...[
                        _buildMiniIcon(Icons.group,
                            user['permissions']['show_users'] == true),
                        _buildMiniIcon(Icons.inventory_2,
                            user['permissions']['show_issi'] == true),
                        _buildMiniIcon(Icons.badge,
                            user['permissions']['show_cssi'] == true),
                        _buildMiniIcon(Icons.description,
                            user['permissions']['show_incidencias'] == true),
                        _buildMiniIcon(Icons.assignment,
                            user['permissions']['show_logs'] == true),
                        _buildMiniIcon(Icons.fingerprint,
                            user['permissions']['show_asistencia'] == true),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            trailing: _isAdmin ? PopupMenuButton<String>(
              onSelected: (v) => v == 'edit' ? _showUserForm(user: user) : _deleteUser(user['id']),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Editar'), dense: true)),
                const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Eliminar', style: TextStyle(color: Colors.red)), dense: true)),
              ],
            ) : null,
          ),
        );
      },
    );
  }

  Widget _buildDesktopLayout(ThemeData theme, List<Map<String, dynamic>> users) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey[200]!)),
        child: PaginatedDataTable(
          dataRowMaxHeight: 64,
          dataRowMinHeight: 64,
          header: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, correo, ID...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: theme.colorScheme.primary)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          actions: [
            if (_isAdmin)
              OutlinedButton.icon(
                onPressed: () => _showUserForm(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar Usuario'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  side: BorderSide(color: theme.colorScheme.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
          ],
          columns: [
            DataColumn(label: Text('USUARIO', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1))),
            DataColumn(label: Text('ID', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1))),
            DataColumn(label: Text('ROL', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1))),
            DataColumn(label: Text('ESTADO', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1))),
            const DataColumn(label: SizedBox()), // Acciones
          ],
          source: _UserDataSource(users: users, theme: theme, isAdmin: _isAdmin, onEdit: (u) => _showUserForm(user: u), onDelete: (id) => _deleteUser(id)),
          rowsPerPage: users.isEmpty ? 1 : (users.length > 10 ? 10 : users.length),
          showCheckboxColumn: false,
        ),
      ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                Icon(icon, color: color, size: 24),
              ],
            ),
            const SizedBox(height: 12),
            Text(value,
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String? status) {
    final s = status ?? '---';
    final color = s == 'ACTIVO' ? Colors.green : (s == 'BAJA' ? Colors.red : Colors.orange);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withOpacity(0.4))),
      child: Text(s, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

class _UserDataSource extends DataTableSource {
  final List<Map<String, dynamic>> users;
  final ThemeData theme;
  final bool isAdmin;
  final Function(Map<String, dynamic>) onEdit;
  final Function(String) onDelete;

  _UserDataSource({required this.users, required this.theme, required this.isAdmin, required this.onEdit, required this.onDelete});

  @override
  DataRow? getRow(int index) {
    if (index >= users.length) return null;
    final user = users[index];
    final role = user['role'] ?? 'usuario';
    final nombre = '${user['nombre'] ?? ''} ${user['paterno'] ?? ''}'.trim();
    final parts = nombre.split(' ').where((e) => e.isNotEmpty).toList();
    final initials = parts.length > 1 ? '${parts[0][0]}${parts[1][0]}'.toUpperCase() : (parts.isNotEmpty ? parts[0][0].toUpperCase() : '?');

    // Role styling
    Color roleColor = Colors.grey;
    if (role == 'admin') roleColor = theme.colorScheme.primary;
    if (role == 'director') roleColor = Colors.orange;
    if (role == 'manager') roleColor = Colors.purple;

    // Status styling
    final isBlocked = user['is_blocked'] ?? false;
    final status = isBlocked ? 'Inactivo' : (user['status_sys'] == 'ACTIVO' ? 'Activo' : (user['status_sys'] ?? '---'));
    Color statusColor = status == 'Activo' ? Colors.green : (status == 'Inactivo' ? Colors.grey : Colors.orange);

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: roleColor.withOpacity(0.15),
                child: Text(initials, style: TextStyle(color: roleColor, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(nombre.isEmpty ? 'Sin Nombre' : nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(user['email'] ?? '', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
        DataCell(Text(user['numero_empleado'] ?? '----', style: const TextStyle(fontSize: 13, color: Colors.black87))),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: roleColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(role.toString().toLowerCase(), style: const TextStyle(fontSize: 12, color: Colors.black87)),
              ],
            ),
          )
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(status, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
              ],
            ),
          )
        ),
        DataCell(
          Align(
            alignment: Alignment.centerRight,
            child: isAdmin ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: Colors.grey),
              onSelected: (v) => v == 'edit' ? onEdit(user) : onDelete(user['id']),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                const PopupMenuItem(value: 'delete', child: Text('Eliminar', style: TextStyle(color: Colors.red))),
              ],
            ) : const SizedBox(),
          )
        ),
      ],
    );
  }

  @override bool get isRowCountApproximate => false;
  @override int get rowCount => users.length;
  @override int get selectedRowCount => 0;
}
