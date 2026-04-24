import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'theme/si_theme.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>>? _assignedEquipment;
  bool _isLoading = true;
  bool _isPhotoLoading = false;
  final Map<String, bool> _obscureCredentials = {
    'mail': true,
    'drp': true,
    'gp': true,
    'bitrix': true,
    'ek': true,
    'otro': true,
  };

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  // ── Data layer (unchanged) ───────────────────────────────────────────────

  Future<void> _updateProfilePhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
      maxWidth: 800,
    );
    if (image == null) return;
    setState(() => _isPhotoLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final bytes = await image.readAsBytes();
      final fileExt = image.path.split('.').last;
      final fileName =
          '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final path = 'avatars/$fileName';
      await Supabase.instance.client.storage
          .from('employee_photos')
          .uploadBinary(path, bytes,
              fileOptions:
                  const FileOptions(cacheControl: '3600', upsert: false));
      final photoUrl = Supabase.instance.client.storage
          .from('employee_photos')
          .getPublicUrl(path);
      await Supabase.instance.client
          .from('profiles')
          .update({'foto_url': photoUrl}).eq('id', user.id);
      await _fetchProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Foto de perfil actualizada'),
            backgroundColor: SiColors.light.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error actualizando foto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: SiColors.light.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPhotoLoading = false);
    }
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
        if (mounted) setState(() => _profile = data);

        final equipmentData = await Supabase.instance.client
            .from('issi_inventory')
            .select()
            .eq('usuario_id', user.id);
        if (mounted) {
          setState(() {
            _assignedEquipment =
                List<Map<String, dynamic>>.from(equipmentData);
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

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: c.brand, strokeWidth: 2),
      );
    }

    final fullName = _profile?['full_name'] as String? ?? 'Usuario';
    final role = (_profile?['role'] as String? ?? 'usuario');
    final userEmail =
        Supabase.instance.client.auth.currentUser?.email ?? '';
    final initials = _profileInitials(fullName);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(SiSpace.x6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Page header
              _PageHeader(
                onChangePassword: _showChangePasswordDialog,
                onChangePhoto: _updateProfilePhoto,
                isPhotoLoading: _isPhotoLoading,
              ),
              const SizedBox(height: SiSpace.x6),

              // Content layout
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left profile card
                    SizedBox(
                      width: 280,
                      child: _ProfileCard(
                        profile: _profile,
                        fullName: fullName,
                        role: role,
                        userEmail: userEmail,
                        initials: initials,
                        isPhotoLoading: _isPhotoLoading,
                        onChangePhoto: _updateProfilePhoto,
                      ),
                    ),
                    const SizedBox(width: SiSpace.x4),
                    // Right cards
                    Expanded(
                      child: Column(
                        children: [
                          _DatosColaboradorCard(profile: _profile),
                          const SizedBox(height: SiSpace.x4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: _EquipmentCard(
                                      equipment: _assignedEquipment)),
                              const SizedBox(width: SiSpace.x4),
                              Expanded(
                                  child: _CredentialsCard(
                                      profile: _profile,
                                      obscure: _obscureCredentials,
                                      onToggle: (k) => setState(() =>
                                          _obscureCredentials[k] =
                                              !(_obscureCredentials[k] ??
                                                  true)))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    _ProfileCard(
                      profile: _profile,
                      fullName: fullName,
                      role: role,
                      userEmail: userEmail,
                      initials: initials,
                      isPhotoLoading: _isPhotoLoading,
                      onChangePhoto: _updateProfilePhoto,
                    ),
                    const SizedBox(height: SiSpace.x4),
                    _DatosColaboradorCard(profile: _profile),
                    const SizedBox(height: SiSpace.x4),
                    _EquipmentCard(equipment: _assignedEquipment),
                    const SizedBox(height: SiSpace.x4),
                    _CredentialsCard(
                      profile: _profile,
                      obscure: _obscureCredentials,
                      onToggle: (k) => setState(() =>
                          _obscureCredentials[k] =
                              !(_obscureCredentials[k] ?? true)),
                    ),
                  ],
                ),
              const SizedBox(height: SiSpace.x8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Change password dialog (logic unchanged) ─────────────────────────────

  void _showChangePasswordDialog() {
    final currentPwCtrl = TextEditingController();
    final newPwCtrl = TextEditingController();
    final confirmPwCtrl = TextEditingController();
    bool isLoading = false;
    bool obscureNew = true;
    bool obscureConfirm = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final c = SiColors.of(context);
          return Container(
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(SiRadius.xl)),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: SiSpace.x6,
                right: SiSpace.x6,
                top: SiSpace.x6,
                bottom: MediaQuery.of(context).viewInsets.bottom + SiSpace.x10,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancelar',
                            style: TextStyle(color: c.ink3, fontSize: 14)),
                      ),
                      Text('Cambiar contraseña',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: c.ink)),
                      TextButton(
                        onPressed: isLoading
                            ? null
                            : () async {
                                if (currentPwCtrl.text.isEmpty ||
                                    newPwCtrl.text.isEmpty ||
                                    confirmPwCtrl.text.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Completa todos los campos')),
                                  );
                                  return;
                                }
                                if (newPwCtrl.text.length < 8) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Mínimo 8 caracteres')),
                                  );
                                  return;
                                }
                                if (newPwCtrl.text != confirmPwCtrl.text) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Las contraseñas no coinciden')),
                                  );
                                  return;
                                }
                                setDialogState(() => isLoading = true);
                                try {
                                  final user = Supabase
                                      .instance.client.auth.currentUser;
                                  if (user == null || user.email == null) {
                                    throw Exception('Usuario no encontrado');
                                  }
                                  await Supabase.instance.client.auth
                                      .signInWithPassword(
                                    email: user.email!,
                                    password: currentPwCtrl.text,
                                  );
                                  await Supabase.instance.client.auth
                                      .updateUser(UserAttributes(
                                          password: newPwCtrl.text));
                                  if (mounted) {
                                    setDialogState(() => isLoading = false);
                                    Navigator.of(dialogContext).pop();
                                    Future.delayed(
                                        const Duration(milliseconds: 300),
                                        () {
                                      if (mounted) {
                                        showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text(
                                                'Contraseña actualizada'),
                                            content: const Text(
                                                'Tu contraseña fue cambiada. Debes iniciar sesión nuevamente.'),
                                            actions: [
                                              TextButton(
                                                onPressed: () async {
                                                  await Supabase.instance.client
                                                      .auth
                                                      .signOut();
                                                  if (ctx.mounted)
                                                    Navigator.pop(ctx);
                                                },
                                                child: const Text('Aceptar'),
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
                                      const SnackBar(
                                        content: Text(
                                            'Contraseña actual incorrecta'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    setDialogState(() => isLoading = false);
                                  }
                                }
                              },
                        child: isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : Text('Guardar',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: c.brand)),
                      ),
                    ],
                  ),
                  const SizedBox(height: SiSpace.x5),
                  TextField(
                    controller: currentPwCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Contraseña actual',
                        prefixIcon: Icon(Icons.lock_outline, size: 16)),
                  ),
                  const SizedBox(height: SiSpace.x4),
                  TextField(
                    controller: newPwCtrl,
                    obscureText: obscureNew,
                    decoration: InputDecoration(
                      labelText: 'Nueva contraseña',
                      prefixIcon: const Icon(Icons.lock, size: 16),
                      suffixIcon: IconButton(
                        icon: Icon(
                            obscureNew
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 16),
                        onPressed: () =>
                            setDialogState(() => obscureNew = !obscureNew),
                      ),
                    ),
                  ),
                  const SizedBox(height: SiSpace.x4),
                  TextField(
                    controller: confirmPwCtrl,
                    obscureText: obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Confirmar nueva contraseña',
                      prefixIcon: const Icon(Icons.lock_outline, size: 16),
                      suffixIcon: IconButton(
                        icon: Icon(
                            obscureConfirm
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 16),
                        onPressed: () => setDialogState(
                            () => obscureConfirm = !obscureConfirm),
                      ),
                    ),
                  ),
                  const SizedBox(height: SiSpace.x2),
                  Text('Mínimo 8 caracteres',
                      style: TextStyle(fontSize: 12, color: c.ink3)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Page header ──────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  final VoidCallback onChangePassword;
  final VoidCallback onChangePhoto;
  final bool isPhotoLoading;

  const _PageHeader({
    required this.onChangePassword,
    required this.onChangePhoto,
    required this.isPhotoLoading,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mi Perfil',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                    letterSpacing: -0.3)),
            Text(
                'Resumen de tu información, equipo asignado y accesos a sistemas.',
                style: TextStyle(fontSize: 13, color: c.ink2)),
          ],
        ),
        const Spacer(),
        _ActionButton(
          icon: Icons.lock_outline,
          label: 'Cambiar contraseña',
          onPressed: onChangePassword,
        ),
        const SizedBox(width: SiSpace.x2),
        _ActionButton(
          icon: Icons.logout,
          label: 'Cerrar sesión',
          danger: true,
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
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool danger;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final fgColor = danger ? c.danger : c.ink2;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: fgColor),
      label: Text(label,
          style: TextStyle(fontSize: 12, color: fgColor)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
            color: danger ? c.danger.withOpacity(0.4) : c.line, width: 1),
        padding:
            const EdgeInsets.symmetric(horizontal: SiSpace.x3, vertical: 6),
        minimumSize: Size.zero,
        shape: const RoundedRectangleBorder(borderRadius: SiRadius.rMd),
      ),
    );
  }
}

// ── Profile card (left) ──────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final String fullName;
  final String role;
  final String userEmail;
  final String initials;
  final bool isPhotoLoading;
  final VoidCallback onChangePhoto;

  const _ProfileCard({
    required this.profile,
    required this.fullName,
    required this.role,
    required this.userEmail,
    required this.initials,
    required this.isPhotoLoading,
    required this.onChangePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final hasPhoto = (profile?['foto_url'] as String?)?.isNotEmpty == true;

    return _SiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + name
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                        color: c.brandTint, shape: BoxShape.circle),
                    clipBehavior: Clip.antiAlias,
                    child: hasPhoto
                        ? Image.network(profile!['foto_url'],
                            fit: BoxFit.cover)
                        : Center(
                            child: Text(initials,
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: c.brand,
                                    height: 1))),
                  ),
                  if (isPhotoLoading)
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black26),
                        child: const Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white)),
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: isPhotoLoading ? null : onChangePhoto,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                            color: c.brand,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: c.panel, width: 2)),
                        child: const Icon(Icons.camera_alt,
                            size: 10, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: SiSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fullName,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.ink),
                        overflow: TextOverflow.ellipsis),
                    Text(
                        profile?['cargo'] as String? ??
                            role,
                        style: TextStyle(
                            fontSize: 12, color: c.ink2),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: SiSpace.x3),

          // Status chips
          Wrap(
            spacing: SiSpace.x1,
            children: [
              _StatusChip(label: role.toUpperCase(), kind: 'brand'),
              const _StatusChip(label: 'Activo', kind: 'success'),
            ],
          ),

          const SizedBox(height: SiSpace.x4),
          Divider(color: c.line2, height: 1),
          const SizedBox(height: SiSpace.x4),

          // Contact info
          _ContactRow(
              icon: Icons.mail_outline,
              label: 'Correo',
              value: userEmail,
              mono: true,
              c: c),
          const SizedBox(height: SiSpace.x3),
          _ContactRow(
              icon: Icons.phone_android,
              label: 'Celular',
              value: profile?['celular'] as String? ?? '---',
              mono: true,
              c: c),
          const SizedBox(height: SiSpace.x3),
          _ContactRow(
              icon: Icons.location_on_outlined,
              label: 'Ubicación',
              value: profile?['ubicacion'] as String? ?? '---',
              c: c),

          if (profile?['numero_empleado'] != null) ...[
            const SizedBox(height: SiSpace.x4),
            Divider(color: c.line2, height: 1),
            const SizedBox(height: SiSpace.x4),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('N° Empleado',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: c.ink3,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(
                          'EMP-${profile!['numero_empleado']}',
                          style: SiType.mono(size: 12, color: c.ink)),
                    ],
                  ),
                ),
                if (profile?['curp'] != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CURP',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: c.ink3,
                                letterSpacing: 0.5)),
                        const SizedBox(height: 2),
                        Text(
                            (profile!['curp'] as String)
                                .substring(0, 10),
                            style:
                                SiType.mono(size: 12, color: c.ink)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool mono;
  final SiColors c;

  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.c,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: c.ink3),
        const SizedBox(width: SiSpace.x2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: c.ink3,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3)),
              mono
                  ? Text(value,
                      style: SiType.mono(size: 12, color: c.ink))
                  : Text(value,
                      style: TextStyle(fontSize: 12, color: c.ink)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Datos del colaborador card ───────────────────────────────────────────────

class _DatosColaboradorCard extends StatelessWidget {
  final Map<String, dynamic>? profile;
  const _DatosColaboradorCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    if (profile?['nombre'] == null) {
      return _SiCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(SiSpace.x6),
            child: Text('Sin datos de colaborador vinculados',
                style: TextStyle(
                    fontSize: 13,
                    color: c.ink3,
                    fontStyle: FontStyle.italic)),
          ),
        ),
      );
    }

    final rows = [
      (Icons.business_outlined, 'Empresa', profile?['empresa']),
      (Icons.account_tree_outlined, 'Área', profile?['area']),
      (Icons.person_outline, 'Director', profile?['director']),
      (Icons.manage_accounts_outlined, 'Gerente regional',
          profile?['gerente_regional']),
      (Icons.person_pin_outlined, 'Jefe inmediato',
          profile?['jefe_inmediato']),
      (Icons.groups_outlined, 'Líder', profile?['lider']),
      (Icons.phone_outlined, 'Teléfono', profile?['telefono']),
    ];

    return _SiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
              icon: Icons.badge_outlined,
              title: 'Datos del colaborador',
              c: c),
          const SizedBox(height: SiSpace.x3),
          ...rows
              .where((r) => r.$3 != null && r.$3.toString().isNotEmpty)
              .map((r) => _InfoRow(icon: r.$1, label: r.$2, value: r.$3!, c: c)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final SiColors c;

  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 13, color: c.ink4),
          const SizedBox(width: SiSpace.x2),
          SizedBox(
            width: 140,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: c.ink3)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    color: c.ink,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ── Equipment card ───────────────────────────────────────────────────────────

class _EquipmentCard extends StatelessWidget {
  final List<Map<String, dynamic>>? equipment;
  const _EquipmentCard({required this.equipment});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return _SiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
              icon: Icons.inventory_2_outlined,
              title: 'Equipo asignado',
              c: c,
              trailing: equipment != null && equipment!.isNotEmpty
                  ? _StatusChip(
                      label: '${equipment!.length} activos',
                      kind: 'default')
                  : null),
          const SizedBox(height: SiSpace.x2),
          if (equipment == null || equipment!.isEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: SiSpace.x4),
              child: Center(
                child: Text('Sin equipo asignado',
                    style: TextStyle(
                        fontSize: 13,
                        color: c.ink3,
                        fontStyle: FontStyle.italic)),
              ),
            )
          else
            ...equipment!
                .map((item) => _EquipmentRow(item: item, c: c)),
        ],
      ),
    );
  }
}

class _EquipmentRow extends StatefulWidget {
  final Map<String, dynamic> item;
  final SiColors c;
  const _EquipmentRow({required this.item, required this.c});

  @override
  State<_EquipmentRow> createState() => _EquipmentRowState();
}

class _EquipmentRowState extends State<_EquipmentRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final c = widget.c;
    final tipo = item['tipo'] as String?;
    final condicion = item['condicion'] as String?;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: SiMotion.fast,
        padding: const EdgeInsets.symmetric(
            vertical: SiSpace.x2, horizontal: SiSpace.x2),
        decoration: BoxDecoration(
          color: _hovered ? c.hover : Colors.transparent,
          borderRadius: SiRadius.rMd,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.brandTint,
                borderRadius: SiRadius.rMd,
              ),
              child: Icon(_iconForType(tipo), size: 15, color: c.brand),
            ),
            const SizedBox(width: SiSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${item['marca'] ?? ''} ${item['modelo'] ?? ''}'
                          .trim(),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: c.ink)),
                  if (item['n_s'] != null)
                    Text('S/N: ${item['n_s']}',
                        style: SiType.mono(size: 11, color: c.ink3)),
                ],
              ),
            ),
            if (condicion != null)
              _StatusChip(
                  label: condicion.toUpperCase(),
                  kind: _kindForCondition(condicion)),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String? tipo) {
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

  String _kindForCondition(String c) {
    switch (c.toLowerCase()) {
      case 'nuevo': return 'success';
      case 'usado': return 'warn';
      case 'dañado': return 'danger';
      default: return 'default';
    }
  }
}

// ── Credentials card ─────────────────────────────────────────────────────────

class _CredentialsCard extends StatelessWidget {
  final Map<String, dynamic>? profile;
  final Map<String, bool> obscure;
  final ValueChanged<String> onToggle;

  const _CredentialsCard({
    required this.profile,
    required this.obscure,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final systems = [
      ('MAIL', 'mail_user', 'mail_pass'),
      ('DRP', 'drp_user', 'drp_pass'),
      ('GP', 'gp_user', 'gp_pass'),
      ('BITRIX', 'bitrix_user', 'bitrix_pass'),
      ('ENK', 'ek_user', 'ek_pass'),
      ('OTRO', 'otro_user', 'otro_pass'),
    ];

    final activeRows = systems.where((s) {
      final user = profile?[s.$2] as String?;
      final pass = profile?[s.$3] as String?;
      return (user != null && user.isNotEmpty) ||
          (pass != null && pass.isNotEmpty);
    }).toList();

    return _SiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
              icon: Icons.key_outlined,
              title: 'Credenciales de sistemas',
              c: c,
              trailing:
                  const _StatusChip(label: 'Cifradas', kind: 'brand')),
          const SizedBox(height: SiSpace.x2),
          if (activeRows.isEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: SiSpace.x4),
              child: Center(
                child: Text('Sin credenciales registradas',
                    style: TextStyle(
                        fontSize: 13,
                        color: c.ink3,
                        fontStyle: FontStyle.italic)),
              ),
            )
          else
            ...activeRows.map((s) {
              final key = s.$1.toLowerCase();
              final user = profile?[s.$2] as String? ?? '—';
              final pass = profile?[s.$3] as String? ?? '—';
              final isHidden = obscure[key] ?? true;

              return _CredRow(
                system: s.$1,
                username: user,
                password: pass,
                isHidden: isHidden,
                onToggle: () => onToggle(key),
                c: c,
              );
            }),
        ],
      ),
    );
  }
}

class _CredRow extends StatefulWidget {
  final String system;
  final String username;
  final String password;
  final bool isHidden;
  final VoidCallback onToggle;
  final SiColors c;

  const _CredRow({
    required this.system,
    required this.username,
    required this.password,
    required this.isHidden,
    required this.onToggle,
    required this.c,
  });

  @override
  State<_CredRow> createState() => _CredRowState();
}

class _CredRowState extends State<_CredRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: SiMotion.fast,
        padding: const EdgeInsets.symmetric(
            vertical: 7, horizontal: SiSpace.x2),
        decoration: BoxDecoration(
          color: _hovered ? c.hover : Colors.transparent,
          borderRadius: SiRadius.rMd,
        ),
        child: Row(
          children: [
            // System badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: c.brandTint,
                borderRadius: SiRadius.rSm,
              ),
              child: Text(widget.system,
                  style: SiType.mono(
                      size: 10,
                      weight: FontWeight.w500,
                      color: c.brand)),
            ),
            const SizedBox(width: SiSpace.x3),
            // Username
            Expanded(
              child: Text(widget.username,
                  style: TextStyle(fontSize: 12, color: c.ink2),
                  overflow: TextOverflow.ellipsis),
            ),
            // Password
            Text(
              widget.isHidden ? '••••••••••' : widget.password,
              style: SiType.mono(
                  size: 12,
                  color: widget.isHidden ? c.ink4 : c.ink),
            ),
            const SizedBox(width: SiSpace.x1),
            InkWell(
              onTap: widget.onToggle,
              borderRadius: SiRadius.rSm,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  widget.isHidden
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 14,
                  color: c.ink3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared UI primitives ─────────────────────────────────────────────────────

class _SiCard extends StatelessWidget {
  final Widget child;
  const _SiCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SiSpace.x4),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rLg,
        border: Border.all(color: c.line, width: 1),
      ),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final SiColors c;
  final Widget? trailing;

  const _CardHeader(
      {required this.icon,
      required this.title,
      required this.c,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: c.ink3),
        const SizedBox(width: SiSpace.x2),
        Text(title,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.ink)),
        if (trailing != null) ...[
          const Spacer(),
          trailing!,
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final String kind;
  const _StatusChip({required this.label, required this.kind});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final (bg, fg) = switch (kind) {
      'success' => (c.successTint, c.success),
      'warn' => (c.warnTint, c.warn),
      'danger' => (c.dangerTint, c.danger),
      'brand' => (c.brandTint, c.brand),
      _ => (c.hover, c.ink2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: SiRadius.rPill,
        border: Border.all(color: fg.withOpacity(0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 5,
              height: 5,
              decoration:
                  BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: fg)),
        ],
      ),
    );
  }
}

String _profileInitials(String name) {
  final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return name.isNotEmpty ? name[0].toUpperCase() : '?';
}
