import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>>? _assignedEquipment;
  bool _isLoading = true;
  final Map<String, bool> _obscureCredentials = {
    'drp': true, 'gp': true, 'bitrix': true, 'ek': true, 'otro': true,
  };

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && user.id.isNotEmpty) {
        final data = await Supabase.instance.client
            .from('profiles')
            .select('*')
            .eq('id', user.id)
            .maybeSingle();
        
        if (mounted) {
          setState(() {
            _profile = data;
          });
        }

        // Fetch assigned equipment
        final equipmentData = await Supabase.instance.client
            .from('issi_inventory')
            .select()
            .eq('usuario_id', user.id);
        
        if (mounted) {
          setState(() {
            _assignedEquipment = List<Map<String, dynamic>>.from(equipmentData);
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error cargando perfil: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 800;

    final generalInfoCard = Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.badge_outlined, color: Colors.blueGrey, size: 28),
                SizedBox(width: 12),
                Text(
                  'Datos del Colaborador',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_profile?['nombre'] != null) ...[
              _buildInfoRow(Icons.numbers, 'Número de empleado', _profile?['numero_empleado'] ?? '---'),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.fingerprint, 'CURP', _profile?['curp'] ?? '---'),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.business, 'Empresa', _profile?['empresa'] ?? '---'),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.account_tree_outlined, 'Área', _profile?['area'] ?? '---'),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.location_on_outlined, 'Ubicación', _profile?['ubicacion'] ?? '---'),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.person, 'Director', _profile?['director'] ?? '---'),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.manage_accounts, 'Gerente regional', _profile?['gerente_regional'] ?? '---'),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.person_pin, 'Jefe inmediato', _profile?['jefe_inmediato'] ?? '---'),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.groups, 'Líder', _profile?['lider'] ?? '---'),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.phone_outlined, 'Teléfono', _profile?['telefono'] ?? '---'),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.phone_android, 'Teléfono celular', _profile?['celular'] ?? '---'),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.email, 'Correo', Supabase.instance.client.auth.currentUser?.email ?? '---'),
            ] else ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Sin datos de colaborador vinculados',
                    style: TextStyle(color: Colors.blueGrey, fontStyle: FontStyle.italic),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final equipmentCard = Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: Colors.blueGrey, size: 28),
                SizedBox(width: 12),
                Text(
                  'Equipo Asignado',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_assignedEquipment == null || _assignedEquipment!.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Sin equipo asignado registrado',
                    style: TextStyle(color: Colors.blueGrey, fontStyle: FontStyle.italic),
                  ),
                ),
              )
            else
              ..._assignedEquipment!.map((item) => _buildEquipmentItem(item, theme)),
          ],
        ),
      ),
    );

    final credentialsCard = Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.key_outlined, color: Colors.blueGrey, size: 28),
                SizedBox(width: 12),
                Text(
                  'Credenciales de Sistemas',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSystemAccessRow('DRP', _profile?['drp_user'], _profile?['drp_pass'], 'drp'),
            _buildSystemAccessRow('GP', _profile?['gp_user'], _profile?['gp_pass'], 'gp'),
            _buildSystemAccessRow('BITRIX', _profile?['bitrix_user'], _profile?['bitrix_pass'], 'bitrix'),
            _buildSystemAccessRow('ENKONTROL', _profile?['ek_user'], _profile?['ek_pass'], 'ek'),
            _buildSystemAccessRow('OTRO', _profile?['otro_user'], _profile?['otro_pass'], 'otro'),
          ],
        ),
      ),
    );

    final actionButtons = Column(
      children: [
        OutlinedButton.icon(
          onPressed: () => _showChangePasswordDialog(),
          icon: const Icon(Icons.lock_outline),
          label: const Text('CAMBIAR CONTRASEÑA'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            try {
              final user = Supabase.instance.client.auth.currentUser;
              await Supabase.instance.client.rpc('log_event', params: {
                'action_type_param': 'CIERRE DE SESIÓN',
                'target_info_param': 'Usuario: ${user?.email ?? '---'}',
              });
            } catch (e) {
              debugPrint('Error logging logout: $e');
            }
            await Supabase.instance.client.auth.signOut();
          },
          icon: const Icon(Icons.logout_rounded),
          label: const Text('CERRAR SESIÓN'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.redAccent,
            side: const BorderSide(color: Colors.redAccent),
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );

    return _isLoading
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
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(32),
                              bottomRight: Radius.circular(32),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 50,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: CircleAvatar(
                              radius: 60,
                              backgroundColor: theme.colorScheme.secondary.withOpacity(0.2),
                              backgroundImage: (_profile?['foto_url'] != null && _profile?['foto_url'].toString().isNotEmpty == true)
                                  ? NetworkImage(_profile!['foto_url'])
                                  : null,
                              child: (_profile?['foto_url'] == null || _profile?['foto_url'].toString().isEmpty == true)
                                  ? Icon(Icons.person, size: 60, color: theme.colorScheme.secondary)
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 70),
                    Text(
                      _profile?['full_name'] ?? 'Usuario',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'ROL: ${(_profile?['role'] ?? 'Dato no disponible').toUpperCase()}',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: isDesktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: Column(
                                    children: [
                                      generalInfoCard,
                                      const SizedBox(height: 24),
                                      actionButtons,
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  flex: 1,
                                  child: Column(
                                    children: [
                                      equipmentCard,
                                      const SizedBox(height: 24),
                                      credentialsCard,
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                generalInfoCard,
                                const SizedBox(height: 24),
                                equipmentCard,
                                const SizedBox(height: 24),
                                credentialsCard,
                                const SizedBox(height: 24),
                                actionButtons,
                              ],
                            ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          );
  }

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;
    bool obscureNewPassword = true;
    bool obscureConfirmPassword = true;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Cambiar Contraseña',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: currentPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña Actual',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: newPasswordController,
                    decoration: InputDecoration(
                      labelText: 'Nueva Contraseña',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(obscureNewPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setDialogState(() => obscureNewPassword = !obscureNewPassword),
                      ),
                    ),
                    obscureText: obscureNewPassword,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmPasswordController,
                    decoration: InputDecoration(
                      labelText: 'Confirmar Nueva Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setDialogState(() => obscureConfirmPassword = !obscureConfirmPassword),
                      ),
                    ),
                    obscureText: obscureConfirmPassword,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mínimo 8 caracteres',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isLoading ? null : () => Navigator.pop(context),
                          child: const Text('CANCELAR'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isLoading
                              ? null
                              : () async {
                                  if (currentPasswordController.text.isEmpty ||
                                      newPasswordController.text.isEmpty ||
                                      confirmPasswordController.text.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Completa todos los campos')),
                                    );
                                    return;
                                  }

                                  if (newPasswordController.text.length < 8) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('La nueva contraseña debe tener al menos 8 caracteres')),
                                    );
                                    return;
                                  }

                                  if (newPasswordController.text != confirmPasswordController.text) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Las contraseñas no coinciden')),
                                    );
                                    return;
                                  }

                                  setDialogState(() => isLoading = true);

                                  try {
                                    final user = Supabase.instance.client.auth.currentUser;
                                    if (user == null || user.email == null) {
                                      throw Exception('No se pudo obtener el usuario');
                                    }

                                    await Supabase.instance.client.auth.signInWithPassword(
                                      email: user.email!,
                                      password: currentPasswordController.text,
                                    );

                                    await Supabase.instance.client.auth.updateUser(
                                      UserAttributes(password: newPasswordController.text),
                                    );

                                    if (mounted) {
                                      setDialogState(() => isLoading = false);
                                      Navigator.of(dialogContext).pop();
                                      
                                      Future.delayed(const Duration(milliseconds: 300), () {
                                        if (mounted) {
                                          showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (successContext) => AlertDialog(
                                              title: const Text('Contraseña Actualizada'),
                                              content: const Text('Tu contraseña ha sido cambiada correctamente. Debes iniciar sesión nuevamente con tu nueva contraseña.'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () async {
                                                    await Supabase.instance.client.auth.signOut();
                                                    if (successContext.mounted) Navigator.pop(successContext);
                                                  },
                                                  child: const Text('ACEPTAR'),
                                                ),
                                              ],
                                            ),
                                          );
                                        }
                                      });
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: La contraseña actual es incorrecta'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                      setDialogState(() => isLoading = false);
                                    }
                                  }
                                },
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('GUARDAR'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[400]),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: Colors.grey)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildSystemAccessRow(String label, String? user, String? pass, String key) {
    final hasData = (user != null && user.isNotEmpty) || (pass != null && pass.isNotEmpty);
    if (!hasData) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[100]!),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    const Text('Usuario:', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    const SizedBox(width: 8),
                    Text(user ?? '---', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    const Text('Contraseña:', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    const SizedBox(width: 8),
                    Text(
                      (_obscureCredentials[key] ?? true) ? '••••••••' : (pass ?? '---'),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        (_obscureCredentials[key] ?? true) ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 18,
                        color: Colors.blueGrey,
                      ),
                      onPressed: () => setState(() => _obscureCredentials[key] = !(_obscureCredentials[key] ?? true)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEquipmentItem(Map<String, dynamic> item, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getIconForType(item['tipo']),
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                item['tipo']?.toString().toUpperCase() ?? 'EQUIPO',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _getColorForCondition(item['condicion']).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item['condicion']?.toString().toUpperCase() ?? 'USADO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _getColorForCondition(item['condicion']),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${item['marca'] ?? ''} ${item['modelo'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          if (item['n_s'] != null && item['n_s'].toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'S/N: ${item['n_s']}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
          if (item['ubicacion'] != null && item['ubicacion'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  item['ubicacion'],
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  IconData _getIconForType(String? tipo) {
    switch (tipo?.toLowerCase()) {
      case 'laptop': return Icons.laptop;
      case 'pc': return Icons.computer;
      case 'impresora': return Icons.print;
      case 'celular': return Icons.smartphone;
      case 'telefono': return Icons.phone;
      case 'monitor': return Icons.monitor;
      default: return Icons.devices;
    }
  }

  Color _getColorForCondition(String? condicion) {
    switch (condicion?.toLowerCase()) {
      case 'nuevo': return Colors.green;
      case 'usado': return Colors.orange;
      case 'dañado': return Colors.red;
      case 'sin reparacion': return Colors.black;
      default: return Colors.blueGrey;
    }
  }
}
