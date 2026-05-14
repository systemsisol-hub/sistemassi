import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

class PasswordsPage extends StatefulWidget {
  const PasswordsPage({super.key});

  @override
  State<PasswordsPage> createState() => _PasswordsPageState();
}

class _PasswordsPageState extends State<PasswordsPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _myPasswords = [];
  List<Map<String, dynamic>> _sharedPasswords = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late TabController _tabController;
  final Map<String, bool> _visibilityMap = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchPasswords();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchPasswords() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final myData = await Supabase.instance.client
          .from('passwords')
          .select()
          .eq('owner_id', userId)
          .order('name');

      final sharedRaw = await Supabase.instance.client
          .from('password_shares')
          .select('*, passwords(*)')
          .eq('shared_with_id', userId);

      if (mounted) {
        setState(() {
          _myPasswords = List<Map<String, dynamic>>.from(myData);
          _sharedPasswords = sharedRaw
              .where((s) => s['passwords'] != null)
              .map<Map<String, dynamic>>((s) {
                final pw = Map<String, dynamic>.from(s['passwords'] as Map);
                pw['_share_info'] = s;
                return pw;
              })
              .toList()
            ..sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching passwords: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al cargar contraseñas: $e'),
              backgroundColor: SiColors.of(context).danger),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredMine {
    if (_searchQuery.isEmpty) return _myPasswords;
    final q = _searchQuery.toLowerCase();
    return _myPasswords
        .where((p) =>
            (p['name'] ?? '').toString().toLowerCase().contains(q) ||
            (p['url'] ?? '').toString().toLowerCase().contains(q) ||
            (p['username'] ?? '').toString().toLowerCase().contains(q) ||
            (p['description'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  List<Map<String, dynamic>> get _filteredShared {
    if (_searchQuery.isEmpty) return _sharedPasswords;
    final q = _searchQuery.toLowerCase();
    return _sharedPasswords
        .where((p) =>
            (p['name'] ?? '').toString().toLowerCase().contains(q) ||
            (p['url'] ?? '').toString().toLowerCase().contains(q) ||
            (p['username'] ?? '').toString().toLowerCase().contains(q) ||
            (p['description'] ?? '').toString().toLowerCase().contains(q))
        .toList();
  }

  void _toggleVisibility(String id) =>
      setState(() => _visibilityMap[id] = !(_visibilityMap[id] ?? false));

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$label copiado'),
            duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _deletePassword(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar contraseña'),
        content: const Text('¿Deseas eliminar esta entrada permanentemente?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(foregroundColor: SiColors.of(context).danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Supabase.instance.client.from('passwords').delete().eq('id', id);
      _fetchPasswords();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Contraseña eliminada')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: SiColors.of(context).danger));
      }
    }
  }

  void _showPasswordForm({Map<String, dynamic>? item}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PasswordFormSheet(
        item: item,
        onSave: (data) async {
          if (item != null) {
            await Supabase.instance.client
                .from('passwords')
                .update(data)
                .eq('id', item['id']);
          } else {
            await Supabase.instance.client.from('passwords').insert(data);
          }
          if (mounted) {
            _fetchPasswords();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(item != null
                    ? 'Contraseña actualizada'
                    : 'Contraseña guardada')));
          }
        },
      ),
    );
  }

  void _showShareDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => _ShareDialog(
        item: item,
        currentUserId: Supabase.instance.client.auth.currentUser!.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    if (_isLoading) {
      return Scaffold(
        backgroundColor: c.bg,
        body:
            Center(child: CircularProgressIndicator(color: c.brand, strokeWidth: 2)),
      );
    }
    final myItems = _filteredMine;
    final sharedItems = _filteredShared;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          _buildToolbar(c, myItems.length, sharedItems.length),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGrid(c, myItems, isShared: false),
                _buildGrid(c, sharedItems, isShared: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(SiColors c, int mineCount, int sharedCount) {
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: SiSpace.x6, vertical: SiSpace.x3),
      child: Row(
        children: [
          // Segment tabs
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              return Container(
                height: 36,
                decoration:
                    BoxDecoration(color: c.hover, borderRadius: SiRadius.rMd),
                padding: const EdgeInsets.all(3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SegTab(
                      label: 'Mis contraseñas',
                      count: mineCount,
                      isActive: _tabController.index == 0,
                      c: c,
                      onTap: () => _tabController.animateTo(0),
                    ),
                    _SegTab(
                      label: 'Compartidas',
                      count: sharedCount,
                      isActive: _tabController.index == 1,
                      c: c,
                      onTap: () => _tabController.animateTo(1),
                    ),
                  ],
                ),
              );
            },
          ),
          const Spacer(),
          // Search
          Container(
            width: 260,
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
                hintText: 'Buscar contraseña...',
                hintStyle: TextStyle(fontSize: 13, color: c.ink4),
                prefixIcon: Icon(Icons.search, size: 16, color: c.ink3),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 14, color: c.ink3),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          const SizedBox(width: SiSpace.x3),
          ElevatedButton.icon(
            onPressed: () => _showPasswordForm(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Nueva',
                style: TextStyle(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.brand,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape:
                  const RoundedRectangleBorder(borderRadius: SiRadius.rMd),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(SiColors c, List<Map<String, dynamic>> items,
      {required bool isShared}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 56, color: c.line),
            const SizedBox(height: SiSpace.x4),
            Text(
              isShared
                  ? 'No hay contraseñas compartidas contigo'
                  : _searchQuery.isNotEmpty
                      ? 'Sin resultados para "$_searchQuery"'
                      : 'No hay contraseñas guardadas',
              style: TextStyle(color: c.ink3, fontSize: 15),
            ),
            if (!isShared && _searchQuery.isEmpty) ...[
              const SizedBox(height: SiSpace.x2),
              Text('Presiona "Nueva" para agregar una',
                  style: TextStyle(color: c.ink4, fontSize: 13)),
            ],
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(SiSpace.x6),
      child: Center(
        child: Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: SiRadius.rLg,
            side: BorderSide(color: c.line),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 480,
              mainAxisExtent: 214,
              crossAxisSpacing: 1,
              mainAxisSpacing: 1,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return Container(
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border(
                    right: BorderSide(color: c.line2, width: 0.5),
                    bottom: BorderSide(color: c.line2, width: 0.5),
                  ),
                ),
                child: _PasswordTile(
                  item: item,
                  isShared: isShared,
                  visible: _visibilityMap[item['id']] ?? false,
                  onToggleVisibility: () =>
                      _toggleVisibility(item['id'] as String),
                  onCopy: _copyToClipboard,
                  onEdit: isShared ? null : () => _showPasswordForm(item: item),
                  onDelete: isShared
                      ? null
                      : () => _deletePassword(item['id'] as String),
                  onShare: isShared ? null : () => _showShareDialog(item),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Segment tab button ────────────────────────────────────────────────────────

class _SegTab extends StatelessWidget {
  final String label;
  final int count;
  final bool isActive;
  final SiColors c;
  final VoidCallback onTap;

  const _SegTab({
    required this.label,
    required this.count,
    required this.isActive,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: SiMotion.fast,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive ? c.panel : Colors.transparent,
          borderRadius: SiRadius.rSm,
          boxShadow: isActive ? SiShadows.md : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? c.ink : c.ink3,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration:
                  BoxDecoration(color: c.hover, borderRadius: SiRadius.rPill),
              child: Text(
                '$count',
                style: TextStyle(
                    fontSize: 11,
                    color: c.ink3,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Password card tile ────────────────────────────────────────────────────────

class _PasswordTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isShared;
  final bool visible;
  final VoidCallback onToggleVisibility;
  final Future<void> Function(String, String) onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onShare;

  const _PasswordTile({
    required this.item,
    required this.isShared,
    required this.visible,
    required this.onToggleVisibility,
    required this.onCopy,
    this.onEdit,
    this.onDelete,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final name = (item['name'] ?? 'Sin nombre') as String;
    final url = (item['url'] ?? '') as String;
    final username = (item['username'] ?? '') as String;
    final password = (item['password'] ?? '') as String;
    final description = (item['description'] ?? '') as String;
    final initials =
        name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.all(SiSpace.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isShared ? c.warnTint : c.brandTint,
                  borderRadius: SiRadius.rMd,
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    color: isShared ? c.warn : c.brand,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: SiSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (url.isNotEmpty)
                      Text(
                        url,
                        style: TextStyle(fontSize: 11, color: c.brand),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              _ActionsMenu(
                  c: c, onShare: onShare, onEdit: onEdit, onDelete: onDelete),
            ],
          ),

          const SizedBox(height: SiSpace.x4),

          // Username
          if (username.isNotEmpty) ...[
            _CredRow(
              icon: Icons.person_outline,
              label: username,
              copyValue: username,
              copyLabel: 'Usuario',
              mono: true,
              c: c,
              onCopy: onCopy,
            ),
            const SizedBox(height: SiSpace.x2),
          ],

          // Password
          _CredRow(
            icon: Icons.lock_outline,
            label: visible ? password : '••••••••',
            copyValue: password,
            copyLabel: 'Contraseña',
            mono: visible,
            c: c,
            onCopy: onCopy,
            trailing: IconButton(
              icon: Icon(
                visible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 13,
                color: c.ink4,
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              onPressed: onToggleVisibility,
              tooltip: visible ? 'Ocultar' : 'Mostrar',
            ),
          ),

          const Spacer(),

          // Footer
          Row(
            children: [
              if (description.isNotEmpty)
                Expanded(
                  child: Text(
                    description,
                    style: TextStyle(fontSize: 11, color: c.ink4),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              if (isShared)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: c.warnTint, borderRadius: SiRadius.rPill),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.group_outlined, size: 11, color: c.warn),
                      const SizedBox(width: 4),
                      Text('Compartida',
                          style: TextStyle(
                              fontSize: 11,
                              color: c.warn,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Credential row ────────────────────────────────────────────────────────────

class _CredRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String copyValue;
  final String copyLabel;
  final bool mono;
  final SiColors c;
  final Future<void> Function(String, String) onCopy;
  final Widget? trailing;

  const _CredRow({
    required this.icon,
    required this.label,
    required this.copyValue,
    required this.copyLabel,
    required this.mono,
    required this.c,
    required this.onCopy,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: SiSpace.x3),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: SiRadius.rSm,
        border: Border.all(color: c.line2),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: c.ink4),
          const SizedBox(width: SiSpace.x2),
          Expanded(
            child: Text(
              label,
              style: mono
                  ? SiType.mono(size: 12, color: c.ink2)
                  : TextStyle(
                      fontSize: 14, letterSpacing: 1.5, color: c.ink3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
          IconButton(
            icon: Icon(Icons.copy_outlined, size: 13, color: c.ink4),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            tooltip: 'Copiar $copyLabel',
            onPressed: () => onCopy(copyValue, copyLabel),
          ),
        ],
      ),
    );
  }
}

// ── Actions popup menu ────────────────────────────────────────────────────────

class _ActionsMenu extends StatelessWidget {
  final SiColors c;
  final VoidCallback? onShare;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ActionsMenu({
    required this.c,
    this.onShare,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (onShare == null && onEdit == null && onDelete == null) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 18, color: c.ink4),
      onSelected: (v) {
        if (v == 'share') onShare?.call();
        if (v == 'edit') onEdit?.call();
        if (v == 'delete') onDelete?.call();
      },
      itemBuilder: (_) => [
        if (onShare != null)
          PopupMenuItem(
            value: 'share',
            child: Row(children: [
              Icon(Icons.people_alt_outlined, size: 16, color: c.ink2),
              const SizedBox(width: 12),
              const Text('Compartir'),
            ]),
          ),
        if (onEdit != null)
          PopupMenuItem(
            value: 'edit',
            child: Row(children: [
              Icon(Icons.edit_outlined, size: 16, color: c.ink2),
              const SizedBox(width: 12),
              const Text('Editar'),
            ]),
          ),
        if (onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              Icon(Icons.delete_outline, size: 16, color: c.danger),
              const SizedBox(width: 12),
              Text('Eliminar', style: TextStyle(color: c.danger)),
            ]),
          ),
      ],
    );
  }
}

// ── Password form sheet ───────────────────────────────────────────────────────

class _PasswordFormSheet extends StatefulWidget {
  final Map<String, dynamic>? item;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _PasswordFormSheet({required this.onSave, this.item});

  @override
  State<_PasswordFormSheet> createState() => _PasswordFormSheetState();
}

class _PasswordFormSheetState extends State<_PasswordFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _descCtrl;
  bool _saving = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _nameCtrl = TextEditingController(text: i?['name']);
    _urlCtrl = TextEditingController(text: i?['url']);
    _userCtrl = TextEditingController(text: i?['username']);
    _passCtrl = TextEditingController(text: i?['password']);
    _descCtrl = TextEditingController(text: i?['description']);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Nombre y contraseña son obligatorios')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave({
        'name': _nameCtrl.text.trim(),
        'url': _urlCtrl.text.trim(),
        'username': _userCtrl.text.trim(),
        'password': _passCtrl.text,
        'description': _descCtrl.text.trim(),
        'owner_id': Supabase.instance.client.auth.currentUser?.id,
        'updated_at': DateTime.now().toIso8601String(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: SiColors.of(context).danger));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final isEditing = widget.item != null;

    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: SiSpace.x6,
          right: SiSpace.x6,
          top: SiSpace.x4,
          bottom: MediaQuery.of(context).viewInsets.bottom + SiSpace.x10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: SiSpace.x4),
                decoration: BoxDecoration(
                    color: c.line, borderRadius: SiRadius.rPill),
              ),
            ),
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancelar',
                      style: TextStyle(color: c.ink3, fontSize: 15)),
                ),
                Text(
                  isEditing ? 'Editar contraseña' : 'Nueva contraseña',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: c.ink),
                ),
                TextButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: c.brand))
                      : Text('Guardar',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: c.brand)),
                ),
              ],
            ),
            const SizedBox(height: SiSpace.x6),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre *',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: SiSpace.x4),
            TextField(
              controller: _urlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL',
                prefixIcon: Icon(Icons.link_outlined),
                hintText: 'https://...',
              ),
            ),
            const SizedBox(height: SiSpace.x4),
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: 'Usuario',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: SiSpace.x4),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Contraseña *',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: SiSpace.x4),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                prefixIcon: Icon(Icons.notes_outlined),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Share dialog ──────────────────────────────────────────────────────────────

class _ShareDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final String currentUserId;

  const _ShareDialog({required this.item, required this.currentUserId});

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  List<Map<String, dynamic>> _users = [];
  Set<String> _selected = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final shares = await Supabase.instance.client
          .from('password_shares')
          .select('shared_with_id')
          .eq('password_id', widget.item['id']);

      final users = await Supabase.instance.client
          .from('profiles')
          .select()
          .neq('id', widget.currentUserId)
          .filter('permissions->>show_passwords', 'eq', 'true');

      if (mounted) {
        setState(() {
          _users = List<Map<String, dynamic>>.from(users);
          _selected = Set<String>.from(
              shares.map<String>((s) => s['shared_with_id'] as String));
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al cargar usuarios: $e')));
      }
    }
  }

  String _displayName(Map<String, dynamic> u) {
    final candidates = [
      u['full_name'],
      u['nombre'],
      u['name'],
      u['correo'],
      u['email'],
    ];
    for (final v in candidates) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return (u['id'] as String).substring(0, 8);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final c = SiColors.of(context);
    try {
      final prevShares = await Supabase.instance.client
          .from('password_shares')
          .select('shared_with_id')
          .eq('password_id', widget.item['id']);

      final prev = Set<String>.from(
          prevShares.map<String>((s) => s['shared_with_id'] as String));
      final toRemove = prev.difference(_selected);
      final toAdd = _selected.difference(prev);

      for (final uid in toRemove) {
        await Supabase.instance.client
            .from('password_shares')
            .delete()
            .eq('password_id', widget.item['id'])
            .eq('shared_with_id', uid);
      }

      if (toAdd.isNotEmpty) {
        await Supabase.instance.client.from('password_shares').insert(
          toAdd
              .map((uid) => {
                    'password_id': widget.item['id'],
                    'shared_with_id': uid,
                    'shared_by_id': widget.currentUserId,
                  })
              .toList(),
        );
      }

      nav.pop();
      messenger.showSnackBar(
          const SnackBar(content: Text('Compartido actualizado')));
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: c.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.people_alt_outlined, size: 20, color: c.brand),
          const SizedBox(width: SiSpace.x2),
          const Text('Compartir contraseña'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: SiSpace.x8),
                child: Center(child: CircularProgressIndicator()),
              )
            : _users.isEmpty
                ? Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: SiSpace.x4),
                    child: Text('No hay otros usuarios disponibles.',
                        style: TextStyle(color: c.ink3)),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Compartir "${widget.item['name']}" con:',
                        style: TextStyle(fontSize: 13, color: c.ink3),
                      ),
                      const SizedBox(height: SiSpace.x3),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: _users.map((u) {
                              final id = u['id'] as String;
                              return CheckboxListTile(
                                value: _selected.contains(id),
                                onChanged: _saving
                                    ? null
                                    : (v) => setState(() {
                                          if (v == true) {
                                            _selected.add(id);
                                          } else {
                                            _selected.remove(id);
                                          }
                                        }),
                                title: Text(_displayName(u),
                                    style: TextStyle(
                                        fontSize: 14, color: c.ink)),
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                activeColor: c.brand,
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        if (!_loading && _users.isNotEmpty)
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Guardar'),
          ),
      ],
    );
  }
}
