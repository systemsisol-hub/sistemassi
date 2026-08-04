import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';
import 'bi_web_iframe_stub.dart' if (dart.library.html) 'bi_web_iframe_web.dart';

class BiPage extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;

  const BiPage({super.key, required this.role, required this.permissions});

  @override
  State<BiPage> createState() => _BiPageState();
}

class _BiPageState extends State<BiPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _links = [];
  List<Map<String, dynamic>> _grupos = [];
  bool _isLoading = true;
  bool get _isAdmin => widget.role == 'admin';
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      final hasPowerBi = widget.permissions['show_powerbi'] == true;

      if (hasPowerBi && userId != null) {
        final assignedRaw = await _supabase
            .from('powerbi_link_users')
            .select(
                'link_id, powerbi_links(id, title, url, descripcion, is_active, created_by, grupo_id, pbi_workspace_id, pbi_dataset_id, ai_context, bi_grupos(name))')
            .eq('user_id', userId);

        final assigned = (assignedRaw as List)
            .where((e) =>
                e['powerbi_links'] != null &&
                e['powerbi_links']['is_active'] == true)
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e['powerbi_links'] as Map))
            .toList();

        final createdRaw = await _supabase
            .from('powerbi_links')
            .select(
                'id, title, url, descripcion, is_active, created_by, grupo_id, pbi_workspace_id, pbi_dataset_id, ai_context, bi_grupos(name)')
            .eq('created_by', userId)
            .eq('is_active', true);

        final created = (createdRaw as List)
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();

        final unique = <String, Map<String, dynamic>>{};
        for (final l in [...assigned, ...created]) {
          unique[l['id'].toString()] = l;
        }
        _links = unique.values.toList();
      } else {
        _links = [];
      }

      final gruposRaw = await _supabase
          .from('bi_grupos')
          .select('id, name')
          .order('name');
      _grupos = (gruposRaw as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error fetching BI data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: SiColors.of(context).danger,
        ));
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _links;
    final q = _searchQuery.toLowerCase();
    return _links.where((l) {
      final grupoName =
          (l['bi_grupos'] as Map?)?['name']?.toString().toLowerCase() ?? '';
      return (l['title'] ?? '').toString().toLowerCase().contains(q) ||
          (l['descripcion'] ?? '').toString().toLowerCase().contains(q) ||
          grupoName.contains(q);
    }).toList();
  }

  void _showGruposManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GruposManagerSheet(
        grupos: List.from(_grupos),
        supabase: _supabase,
        onChanged: _fetchData,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getUsers() async {
    final data = await _supabase
        .from('profiles')
        .select('id, nombre, paterno, materno, email, status_sys, permissions')
        .eq('status_sys', 'ACTIVO')
        .order('nombre');
    return (data as List)
        .where((u) {
          final p = u['permissions'];
          return p is Map && p['show_powerbi'] == true;
        })
        .map((u) => Map<String, dynamic>.from(u))
        .toList();
  }

  Future<List<String>> _getLinkUserIds(String linkId) async {
    final data = await _supabase
        .from('powerbi_link_users')
        .select('user_id')
        .eq('link_id', linkId);
    return (data as List).map((e) => e['user_id'].toString()).toList();
  }

  Future<void> _toggleUserAccess(
      String linkId, String userId, bool add) async {
    try {
      if (add) {
        final existing = await _supabase
            .from('powerbi_link_users')
            .select('id')
            .eq('link_id', linkId)
            .eq('user_id', userId)
            .maybeSingle();
        if (existing == null) {
          await _supabase.from('powerbi_link_users').insert({
            'link_id': linkId,
            'user_id': userId,
          });
        }
      } else {
        await _supabase
            .from('powerbi_link_users')
            .delete()
            .eq('link_id', linkId)
            .eq('user_id', userId);
      }
    } catch (e) {
      debugPrint('Error toggling user access: $e');
    }
  }

  void _openLink(Map<String, dynamic> link) {
    final url = link['url'] as String?;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este reporte no tiene URL configurada')),
      );
      return;
    }
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: Colors.black54,
      transitionDuration: SiMotion.normal,
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: _LinkViewer(
              url: url,
              title: link['title'] ?? 'Reporte',
              linkId: link['id']?.toString(),
              // Sin dataset configurado el asistente no puede leer cifras; el panel lo
              // dice en lugar de fingir que puede.
              hasDataset: link['pbi_dataset_id'] != null &&
                  link['pbi_workspace_id'] != null,
              onClose: () => Navigator.pop(ctx),
            ),
          ),
        ),
      ),
    );
  }

  void _showLinkForm({Map<String, dynamic>? link}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LinkFormSheet(
        link: link,
        isAdmin: _isAdmin,
        grupos: _grupos,
        getUsers: _getUsers,
        getLinkUserIds: _getLinkUserIds,
        toggleUserAccess: _toggleUserAccess,
        onGrupoCreated: (g) => setState(() => _grupos.add(g)),
        onSave: (data) async {
          if (link != null) {
            await _supabase
                .from('powerbi_links')
                .update(data)
                .eq('id', link['id']);
          } else {
            await _supabase.from('powerbi_links').insert(data);
          }
          if (mounted) {
            _fetchData();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text(link != null ? 'Enlace actualizado' : 'Enlace creado'),
            ));
          }
        },
      ),
    );
  }

  Future<void> _deleteLink(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mover a papelera'),
        content: const Text('El enlace se moverá a la papelera. Puedes restaurarlo desde ahí.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: SiColors.of(context).danger),
            child: const Text('Mover a papelera'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _supabase
          .from('powerbi_links')
          .update({'is_active': false})
          .eq('id', id);
      _fetchData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Enlace movido a papelera'),
            action: SnackBarAction(
              label: 'Deshacer',
              onPressed: () async {
                await _supabase
                    .from('powerbi_links')
                    .update({'is_active': true})
                    .eq('id', id);
                _fetchData();
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: SiColors.of(context).danger,
        ));
      }
    }
  }

  void _showPapelera() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PapeleraSheet(
        supabase: _supabase,
        onChanged: _fetchData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(
          child: Image.asset(
            'assets/sisol_loader.gif',
            width: 150,
            errorBuilder: (_, __, ___) =>
                CircularProgressIndicator(color: c.brand, strokeWidth: 2),
          ),
        ),
      );
    }

    final items = _filtered;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          _buildToolbar(c),
          Expanded(child: _buildContent(c, items)),
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
                hintText: 'Buscar reporte...',
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
          const Spacer(),
          if (_isAdmin) ...[
            IconButton(
              onPressed: _showPapelera,
              icon: Icon(Icons.delete_outline, size: 20, color: c.ink3),
              tooltip: 'Papelera',
            ),
            const SizedBox(width: SiSpace.x1),
            OutlinedButton.icon(
              onPressed: _showGruposManager,
              icon: const Icon(Icons.folder_outlined, size: 16),
              label: const Text('Grupos',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.brand,
                side: BorderSide(color: c.brand),
                elevation: 0,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: const RoundedRectangleBorder(
                    borderRadius: SiRadius.rMd),
              ),
            ),
            const SizedBox(width: SiSpace.x2),
            ElevatedButton.icon(
              onPressed: () => _showLinkForm(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nuevo',
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
        ],
      ),
    );
  }

  Widget _buildContent(SiColors c, List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchQuery.isEmpty ? Icons.bar_chart_outlined : Icons.search_off,
              size: 56,
              color: c.line,
            ),
            const SizedBox(height: SiSpace.x4),
            Text(
              _searchQuery.isEmpty
                  ? (_isAdmin
                      ? 'No hay enlaces creados'
                      : 'No tienes acceso a ningún reporte')
                  : 'Sin resultados para "$_searchQuery"',
              style: TextStyle(color: c.ink3, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth > 800
          ? _buildTable(c, items)
          : _buildList(c, items),
    );
  }

  Widget _buildTable(SiColors c, List<Map<String, dynamic>> items) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(SiSpace.x6),
      child: Center(
        child: Card(
          child: _BiTable(
            links: items,
            isAdmin: _isAdmin,
            c: c,
            onTap: _openLink,
            onEdit: _isAdmin ? (l) => _showLinkForm(link: l) : null,
            onDelete: _isAdmin ? (id) => _deleteLink(id) : null,
            grupos: _grupos,
          ),
        ),
      ),
    );
  }

  Widget _buildList(SiColors c, List<Map<String, dynamic>> items) {
    return ListView.separated(
      padding: const EdgeInsets.all(SiSpace.x4),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: SiSpace.x3),
      itemBuilder: (context, i) {
        final link = items[i];
        final desc = link['descripcion']?.toString() ?? '';
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
                horizontal: SiSpace.x5, vertical: SiSpace.x2),
            leading: Container(
              width: 40,
              height: 40,
              decoration:
                  BoxDecoration(color: c.brandTint, borderRadius: SiRadius.rMd),
              alignment: Alignment.center,
              child:
                  Icon(Icons.assessment_outlined, color: c.brand, size: 20),
            ),
            title: Text(
              link['title'] ?? 'Sin título',
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14, color: c.ink),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((link['bi_grupos'] as Map?)?['name'] != null)
                  Container(
                    margin: const EdgeInsets.only(top: 2, bottom: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: c.brandTint,
                      borderRadius: SiRadius.rPill,
                    ),
                    child: Text(
                      (link['bi_grupos'] as Map)['name'].toString(),
                      style: TextStyle(fontSize: 10, color: c.brand, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (desc.isNotEmpty)
                  Text(desc,
                      style: TextStyle(fontSize: 12, color: c.ink3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
            trailing: _isAdmin
                ? PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, size: 18, color: c.ink4),
                    onSelected: (v) {
                      if (v == 'edit') _showLinkForm(link: link);
                      if (v == 'delete') _deleteLink(link['id']);
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
                : Icon(Icons.arrow_forward_ios, size: 14, color: c.ink4),
            onTap: () => _openLink(link),
          ),
        );
      },
    );
  }
}

// ── Table ─────────────────────────────────────────────────────────────────────

class _BiTable extends StatelessWidget {
  final List<Map<String, dynamic>> links;
  final List<Map<String, dynamic>> grupos;
  final bool isAdmin;
  final SiColors c;
  final void Function(Map<String, dynamic>) onTap;
  final void Function(Map<String, dynamic>)? onEdit;
  final void Function(String)? onDelete;

  const _BiTable({
    required this.links,
    required this.isAdmin,
    required this.c,
    required this.onTap,
    required this.grupos,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Sort by grupo name (null/sin grupo last), then by title
    final sorted = List.of(links)
      ..sort((a, b) {
        final ga = (a['bi_grupos'] as Map?)?['name']?.toString() ?? '';
        final gb = (b['bi_grupos'] as Map?)?['name']?.toString() ?? '';
        if (ga != gb) {
          if (ga.isEmpty) return 1;
          if (gb.isEmpty) return -1;
          return ga.compareTo(gb);
        }
        return (a['title'] ?? '').toString().compareTo((b['title'] ?? '').toString());
      });

    String? lastGrupo;
    int rowIdx = 0;
    final rows = <Widget>[];
    for (final link in sorted) {
      final grupoName = (link['bi_grupos'] as Map?)?['name']?.toString();
      if (grupoName != lastGrupo) {
        lastGrupo = grupoName;
        rows.add(_groupHeader(grupoName));
        rowIdx = 0;
      }
      rows.add(_linkRow(link, rowIdx));
      rowIdx++;
    }

    return Column(
      children: [
        // Table header
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: SiSpace.x5, vertical: SiSpace.x3),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('TÍTULO',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.ink4,
                        letterSpacing: 0.8)),
              ),
              Expanded(
                flex: 5,
                child: Text('DESCRIPCIÓN',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.ink4,
                        letterSpacing: 0.8)),
              ),
              if (isAdmin) const SizedBox(width: 48),
            ],
          ),
        ),
        ...rows,
      ],
    );
  }

  Widget _groupHeader(String? name) {
    return Container(
      padding: const EdgeInsets.fromLTRB(SiSpace.x5, SiSpace.x2, SiSpace.x5, SiSpace.x2),
      decoration: BoxDecoration(
        color: c.brandTint,
        border: Border(bottom: BorderSide(color: c.line2, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 14, color: c.brand),
          const SizedBox(width: 6),
          Text(
            name ?? 'Sin grupo',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c.brand,
                letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _linkRow(Map<String, dynamic> link, int i) {
    final desc = link['descripcion']?.toString() ?? '';
    return InkWell(
      onTap: () => onTap(link),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: SiSpace.x5, vertical: SiSpace.x3 + 2),
        decoration: BoxDecoration(
          color: i.isOdd ? c.bg : c.panel,
          border: Border(bottom: BorderSide(color: c.line2, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                        color: c.brandTint, borderRadius: SiRadius.rSm),
                    alignment: Alignment.center,
                    child: Icon(Icons.assessment_outlined,
                        size: 14, color: c.brand),
                  ),
                  const SizedBox(width: SiSpace.x3),
                  Expanded(
                    child: Text(
                      (link['title'] ?? 'Sin título').toString().toUpperCase(),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 5,
              child: Text(
                desc.isEmpty ? '—' : desc,
                style: TextStyle(fontSize: 13, color: c.ink3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isAdmin)
              SizedBox(
                width: 48,
                child: PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz, size: 18, color: c.ink4),
                  onSelected: (v) {
                    if (v == 'edit') onEdit?.call(link);
                    if (v == 'delete') onDelete?.call(link['id']);
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
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline, size: 16, color: c.danger),
                        const SizedBox(width: 12),
                        Text('Eliminar', style: TextStyle(color: c.danger)),
                      ]),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Link form sheet ───────────────────────────────────────────────────────────

class _LinkFormSheet extends StatefulWidget {
  final Map<String, dynamic>? link;
  final bool isAdmin;
  final List<Map<String, dynamic>> grupos;
  final Future<List<Map<String, dynamic>>> Function() getUsers;
  final Future<List<String>> Function(String) getLinkUserIds;
  final Future<void> Function(String, String, bool) toggleUserAccess;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final void Function(Map<String, dynamic>)? onGrupoCreated;

  const _LinkFormSheet({
    required this.onSave,
    required this.isAdmin,
    required this.grupos,
    required this.getUsers,
    required this.getLinkUserIds,
    required this.toggleUserAccess,
    this.link,
    this.onGrupoCreated,
  });

  @override
  State<_LinkFormSheet> createState() => _LinkFormSheetState();
}

class _LinkFormSheetState extends State<_LinkFormSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _wsCtrl;
  late final TextEditingController _dsCtrl;
  late final TextEditingController _aiCtxCtrl;
  late List<Map<String, dynamic>> _grupos;
  String? _selectedGrupoId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final l = widget.link;
    _titleCtrl = TextEditingController(text: l?['title']);
    _urlCtrl = TextEditingController(text: l?['url']);
    _descCtrl = TextEditingController(text: l?['descripcion']);
    _wsCtrl = TextEditingController(text: l?['pbi_workspace_id']);
    _dsCtrl = TextEditingController(text: l?['pbi_dataset_id']);
    _aiCtxCtrl = TextEditingController(text: l?['ai_context']);
    _grupos = List.from(widget.grupos);
    _selectedGrupoId = l?['grupo_id'] as String?;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    _descCtrl.dispose();
    _wsCtrl.dispose();
    _dsCtrl.dispose();
    _aiCtxCtrl.dispose();
    super.dispose();
  }

  /// Los dos identificadores son UUID. Validarlos aquí evita guardar un valor que la base
  /// rechazaría con un error opaco de Postgres.
  static final _uuidRe = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  String? _validarUuid(String raw, String campo) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    if (!_uuidRe.hasMatch(v)) return '$campo no es un UUID válido.';
    return null;
  }

  Future<void> _createGrupo(BuildContext ctx) async {
    final c = SiColors.of(ctx);
    final ctrl = TextEditingController();
    final newName = await showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Nuevo grupo'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre del grupo',
            prefixIcon: Icon(Icons.folder_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text('Cancelar', style: TextStyle(color: c.ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
            child: Text('Crear', style: TextStyle(color: c.brand)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newName == null || newName.isEmpty) return;
    try {
      final result = await Supabase.instance.client
          .from('bi_grupos')
          .insert({'name': newName})
          .select('id, name')
          .single();
      final g = Map<String, dynamic>.from(result);
      setState(() {
        _grupos.add(g);
        _selectedGrupoId = g['id'] as String;
      });
      widget.onGrupoCreated?.call(g);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al crear grupo: $e')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El título es obligatorio')),
      );
      return;
    }

    final errorUuid = _validarUuid(_wsCtrl.text, 'El ID del workspace') ??
        _validarUuid(_dsCtrl.text, 'El ID del dataset');
    if (errorUuid != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorUuid),
        backgroundColor: SiColors.of(context).danger,
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      String? limpio(TextEditingController ctrl) =>
          ctrl.text.trim().isEmpty ? null : ctrl.text.trim();

      await widget.onSave({
        'title': _titleCtrl.text.trim().toUpperCase(),
        'url':
            _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
        'descripcion': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'grupo_id': _selectedGrupoId,
        'pbi_workspace_id': limpio(_wsCtrl),
        'pbi_dataset_id': limpio(_dsCtrl),
        'ai_context': limpio(_aiCtxCtrl),
        'is_active': true,
        'created_by': Supabase.instance.client.auth.currentUser?.id,
      });
      if (mounted) Navigator.pop(context);
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
    final isEditing = widget.link != null;

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
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: SiSpace.x4),
                decoration: BoxDecoration(
                    color: c.line, borderRadius: SiRadius.rPill),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancelar',
                      style: TextStyle(color: c.ink3, fontSize: 15)),
                ),
                Text(
                  isEditing ? 'Editar enlace' : 'Nuevo enlace',
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
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Título *',
                prefixIcon: Icon(Icons.title_outlined),
              ),
            ),
            const SizedBox(height: SiSpace.x4),
            DropdownButtonFormField<String>(
              value: _selectedGrupoId,
              decoration: const InputDecoration(
                labelText: 'Grupo',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              items: [
                ..._grupos.map((g) => DropdownMenuItem(
                      value: g['id'] as String,
                      child: Text(g['name'] as String? ?? ''),
                    )),
                const DropdownMenuItem(
                  value: '__new__',
                  child: Row(
                    children: [
                      Icon(Icons.add, size: 16),
                      SizedBox(width: 6),
                      Text('Crear nuevo grupo...'),
                    ],
                  ),
                ),
              ],
              onChanged: (val) {
                if (val == '__new__') {
                  _createGrupo(context);
                } else {
                  setState(() => _selectedGrupoId = val);
                }
              },
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
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                prefixIcon: Icon(Icons.notes_outlined),
                alignLabelWithHint: true,
              ),
            ),
            if (widget.isAdmin) ...[
              const SizedBox(height: SiSpace.x6),
              Divider(color: c.line),
              const SizedBox(height: SiSpace.x4),
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: c.brand),
                  const SizedBox(width: SiSpace.x2),
                  Text('Asistente IA',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.ink)),
                ],
              ),
              const SizedBox(height: SiSpace.x2),
              Text(
                'Con el workspace y el dataset de Power BI, el asistente puede analizar '
                'las cifras del reporte. Sin ellos sólo explica el panel.',
                style: TextStyle(fontSize: 12, color: c.ink3, height: 1.4),
              ),
              const SizedBox(height: SiSpace.x4),
              TextField(
                controller: _wsCtrl,
                decoration: const InputDecoration(
                  labelText: 'ID del workspace',
                  prefixIcon: Icon(Icons.workspaces_outline),
                  hintText: '9d6868a1-526c-4aaf-9da9-0647e6cccef7',
                ),
              ),
              const SizedBox(height: SiSpace.x4),
              TextField(
                controller: _dsCtrl,
                decoration: const InputDecoration(
                  labelText: 'ID del dataset',
                  prefixIcon: Icon(Icons.dataset_outlined),
                  helperText: 'Se obtiene de GET /groups/{workspace}/reports, '
                      'no del nombre del reporte.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: SiSpace.x4),
              TextField(
                controller: _aiCtxCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Contexto para el asistente',
                  prefixIcon: Icon(Icons.psychology_outlined),
                  alignLabelWithHint: true,
                  helperText: 'Qué mide el reporte y cómo se calculan sus KPIs.',
                  helperMaxLines: 2,
                ),
              ),
            ],
            if (isEditing && widget.isAdmin) ...[
              const SizedBox(height: SiSpace.x6),
              Divider(color: c.line),
              const SizedBox(height: SiSpace.x4),
              Text('Asignar a usuarios',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.ink)),
              const SizedBox(height: SiSpace.x3),
              SizedBox(
                height: 320,
                child: _UserAssignList(
                  linkId: widget.link!['id'].toString(),
                  getUsers: widget.getUsers,
                  getLinkUserIds: widget.getLinkUserIds,
                  toggleUserAccess: widget.toggleUserAccess,
                  c: c,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── User assign list ──────────────────────────────────────────────────────────

class _UserAssignList extends StatefulWidget {
  final String linkId;
  final Future<List<Map<String, dynamic>>> Function() getUsers;
  final Future<List<String>> Function(String) getLinkUserIds;
  final Future<void> Function(String, String, bool) toggleUserAccess;
  final SiColors c;

  const _UserAssignList({
    required this.linkId,
    required this.getUsers,
    required this.getLinkUserIds,
    required this.toggleUserAccess,
    required this.c,
  });

  @override
  State<_UserAssignList> createState() => _UserAssignListState();
}

class _UserAssignListState extends State<_UserAssignList> {
  List<Map<String, dynamic>>? _users;
  Set<String> _assigned = {};
  bool _loading = true;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final users = await widget.getUsers();
      final ids = await widget.getLinkUserIds(widget.linkId);
      if (mounted) {
        setState(() {
          _users = users;
          _assigned = ids.toSet();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final all = _users ?? [];
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((u) {
      final name =
          '${u['nombre'] ?? ''} ${u['paterno'] ?? ''} ${u['materno'] ?? ''}'
              .toLowerCase();
      return name.contains(q) ||
          (u['email'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: c.brand, strokeWidth: 2));
    }
    final allUsers = _users ?? [];
    if (allUsers.isEmpty) {
      return Center(
        child: Text('No hay usuarios con acceso a BI',
            style: TextStyle(color: c.ink3, fontSize: 13)),
      );
    }
    final visible = _filtered;
    return Column(
      children: [
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: SiRadius.rMd,
            border: Border.all(color: c.line),
          ),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Buscar usuario...',
              hintStyle: TextStyle(fontSize: 13, color: c.ink4),
              prefixIcon: Icon(Icons.search, size: 16, color: c.ink3),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, size: 14, color: c.ink3),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text('Sin resultados',
                      style: TextStyle(color: c.ink3, fontSize: 13)),
                )
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (ctx, i) {
                    final u = visible[i];
                    final id = u['id'].toString();
                    final name =
                        '${u['nombre'] ?? ''} ${u['paterno'] ?? ''} ${u['materno'] ?? ''}'
                            .trim();
                    final isOn = _assigned.contains(id);
                    return SwitchListTile(
                      dense: true,
                      title: Text(
                        name.isEmpty ? (u['email'] ?? id) : name,
                        style: TextStyle(fontSize: 13, color: c.ink),
                      ),
                      value: isOn,
                      activeColor: c.brand,
                      onChanged: (v) {
                        setState(() {
                          if (v)
                            _assigned.add(id);
                          else
                            _assigned.remove(id);
                        });
                        widget.toggleUserAccess(widget.linkId, id, v);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Papelera sheet ────────────────────────────────────────────────────────────

class _PapeleraSheet extends StatefulWidget {
  final SupabaseClient supabase;
  final VoidCallback onChanged;

  const _PapeleraSheet({required this.supabase, required this.onChanged});

  @override
  State<_PapeleraSheet> createState() => _PapeleraSheetState();
}

class _PapeleraSheetState extends State<_PapeleraSheet> {
  List<Map<String, dynamic>>? _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await widget.supabase
          .from('powerbi_links')
          .select('id, title, descripcion, grupo_id, bi_grupos(name)')
          .eq('is_active', false)
          .order('title');
      if (mounted) {
        setState(() {
          _items = (data as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore(String id) async {
    await widget.supabase
        .from('powerbi_links')
        .update({'is_active': true})
        .eq('id', id);
    widget.onChanged();
    _load();
  }

  Future<void> _deletePermanent(String id, BuildContext ctx) async {
    final c = SiColors.of(ctx);
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Eliminar permanentemente'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.supabase.from('powerbi_links').delete().eq('id', id);
    widget.onChanged();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: SiSpace.x4),
              decoration:
                  BoxDecoration(color: c.line, borderRadius: SiRadius.rPill),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cerrar', style: TextStyle(color: c.ink3, fontSize: 15)),
              ),
              Text('Papelera',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600, color: c.ink)),
              const SizedBox(width: 72),
            ],
          ),
          const SizedBox(height: SiSpace.x4),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: SiSpace.x8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_items == null || _items!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SiSpace.x8),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.delete_outline, size: 48, color: c.line),
                    const SizedBox(height: SiSpace.x3),
                    Text('La papelera está vacía',
                        style: TextStyle(color: c.ink3, fontSize: 14)),
                  ],
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items!.length,
                separatorBuilder: (_, __) => Divider(color: c.line2, height: 1),
                itemBuilder: (ctx, i) {
                  final item = _items![i];
                  final grupoName =
                      (item['bi_grupos'] as Map?)?['name']?.toString();
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.assessment_outlined,
                        size: 20, color: c.ink3),
                    title: Text(item['title']?.toString() ?? 'Sin título',
                        style: TextStyle(fontSize: 13, color: c.ink)),
                    subtitle: grupoName != null
                        ? Text(grupoName,
                            style: TextStyle(fontSize: 11, color: c.ink4))
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.restore, size: 18, color: c.brand),
                          tooltip: 'Restaurar',
                          onPressed: () => _restore(item['id'] as String),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_forever_outlined,
                              size: 18, color: c.danger),
                          tooltip: 'Eliminar permanentemente',
                          onPressed: () =>
                              _deletePermanent(item['id'] as String, context),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Grupos manager sheet ──────────────────────────────────────────────────────

class _GruposManagerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> grupos;
  final SupabaseClient supabase;
  final VoidCallback onChanged;

  const _GruposManagerSheet({
    required this.grupos,
    required this.supabase,
    required this.onChanged,
  });

  @override
  State<_GruposManagerSheet> createState() => _GruposManagerSheetState();
}

class _GruposManagerSheetState extends State<_GruposManagerSheet> {
  late List<Map<String, dynamic>> _grupos;
  bool _saving = false;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _grupos = List.from(widget.grupos);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final result = await widget.supabase
          .from('bi_grupos')
          .insert({'name': name})
          .select('id, name')
          .single();
      _ctrl.clear();
      setState(() {
        _grupos.add(Map<String, dynamic>.from(result));
        _grupos.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
        _saving = false;
      });
      widget.onChanged();
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _delete(String id) async {
    try {
      await widget.supabase.from('bi_grupos').delete().eq('id', id);
      setState(() => _grupos.removeWhere((g) => g['id'] == id));
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se puede eliminar: tiene reportes asignados')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: SiSpace.x4),
              decoration:
                  BoxDecoration(color: c.line, borderRadius: SiRadius.rPill),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cerrar', style: TextStyle(color: c.ink3, fontSize: 15)),
              ),
              Text('Grupos',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600, color: c.ink)),
              const SizedBox(width: 72),
            ],
          ),
          const SizedBox(height: SiSpace.x5),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del grupo',
                    prefixIcon: Icon(Icons.folder_outlined),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: SiSpace.x3),
              ElevatedButton(
                onPressed: _saving ? null : _add,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: const RoundedRectangleBorder(borderRadius: SiRadius.rMd),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Agregar'),
              ),
            ],
          ),
          const SizedBox(height: SiSpace.x4),
          if (_grupos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SiSpace.x6),
              child: Center(
                child: Text('Sin grupos creados',
                    style: TextStyle(color: c.ink3, fontSize: 13)),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _grupos.length,
                separatorBuilder: (_, __) => Divider(color: c.line2, height: 1),
                itemBuilder: (ctx, i) {
                  final g = _grupos[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.folder_outlined, color: c.brand, size: 18),
                    title: Text(g['name'] as String? ?? '',
                        style: TextStyle(fontSize: 14, color: c.ink)),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline, size: 18, color: c.danger),
                      onPressed: () => _delete(g['id'] as String),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Link viewer ───────────────────────────────────────────────────────────────

class _LinkViewer extends StatelessWidget {
  final String url;
  final String title;
  final String? linkId;
  final bool hasDataset;
  final VoidCallback? onClose;

  const _LinkViewer({
    required this.url,
    required this.title,
    this.linkId,
    this.hasDataset = false,
    this.onClose,
  });

  /// En pantallas angostas no cabe la vista dividida, así que el asistente se abre como
  /// hoja. Antes simplemente no estaba disponible en móvil.
  void _abrirAsistente(BuildContext context) {
    final c = SiColors.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.85,
        child: _BiAiPanel(
          reportTitle: title,
          linkId: linkId,
          hasDataset: hasDataset,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final mq = MediaQuery.of(context);
    final height = mq.size.height - mq.padding.top - mq.padding.bottom;
    final width = mq.size.width;
    const headerH = 56.0;
    final isWide = width > 700;

    return Container(
      height: height,
      color: c.panel,
      child: Column(
        children: [
          // Header
          Container(
            height: headerH,
            padding: const EdgeInsets.symmetric(horizontal: SiSpace.x4),
            decoration: BoxDecoration(
              color: c.panel,
              border: Border(bottom: BorderSide(color: c.line, width: 1)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: c.ink2),
                  onPressed: onClose ?? () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.ink),
                  ),
                ),
                if (isWide)
                  const SizedBox(width: 40)
                else
                  IconButton(
                    tooltip: 'Asistente IA',
                    icon: Icon(Icons.auto_awesome, size: 18, color: c.brand),
                    onPressed: () => _abrirAsistente(context),
                  ),
              ],
            ),
          ),
          // Body: AI panel (izquierda) + iframe (derecha)
          Expanded(
            child: isWide
                ? Row(
                    children: [
                      // AI assistant — 1/3
                      SizedBox(
                        width: width / 3,
                        child: _BiAiPanel(
                          reportTitle: title,
                          linkId: linkId,
                          hasDataset: hasDataset,
                        ),
                      ),
                      VerticalDivider(width: 1, color: c.line),
                      // iframe — 2/3
                      Expanded(
                        child: WebIframe(
                          url: url,
                          height: height - headerH,
                          width: width * 2 / 3,
                        ),
                      ),
                    ],
                  )
                : WebIframe(
                    url: url,
                    height: height - headerH,
                    width: width,
                  ),
          ),
        ],
      ),
    );
  }
}

// ── BI AI Panel ───────────────────────────────────────────────────────────────

class _BiAiPanel extends StatefulWidget {
  final String reportTitle;

  /// Al enviarse como pbi_context, la Edge Function cambia al modo analista: consulta el
  /// dataset y deja de exponer las herramientas administrativas.
  final String? linkId;

  /// Si el enlace no tiene workspace y dataset capturados, el asistente no puede leer
  /// cifras. Se declara en el panel en vez de dejar que el usuario lo descubra fallando.
  final bool hasDataset;

  const _BiAiPanel({
    required this.reportTitle,
    this.linkId,
    this.hasDataset = false,
  });

  @override
  State<_BiAiPanel> createState() => _BiAiPanelState();
}

class _BiAiPanelState extends State<_BiAiPanel> {
  static const _base = 'https://zkmbebybyyefmqcxjqrg.supabase.co/functions/v1';

  /// Función dedicada al análisis de reportes, con su propio modelo. Separada de
  /// ai-assistant para que un cambio en el analista no pueda romper al de RH.
  static const _fnAnalista = '$_base/bi-assistant';

  /// Sin dataset configurado no hay nada que analizar, así que se usa el asistente general
  /// para que al menos explique el panel desde su conocimiento.
  static const _fnGeneral = '$_base/ai-assistant';

  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_AiMsg> _messages = [];
  bool _loading = false;

  /// El modo analista requiere las dos cosas: un enlace identificado y un dataset
  /// capturado. Sin dataset la Edge Function respondería 422 en cada consulta, así que
  /// es mejor quedarse en modo conversacional y decirlo.
  bool get _modoAnalista => widget.linkId != null && widget.hasDataset;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _loading) return;
    _inputCtrl.clear();

    setState(() {
      _messages.add(_AiMsg(role: 'user', text: trimmed));
      _loading = true;
    });
    _scrollToBottom();

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Sin sesión activa');

      final rawMessages =
          _messages.where((m) => m.text.isNotEmpty).toList();
      final List<Map<String, String>> history = [];

      for (int i = 0; i < rawMessages.length; i++) {
        final m = rawMessages[i];
        String content = m.text;
        // Sin dataset no hay modo analista: se le da contexto del panel en el primer
        // mensaje para que al menos lo explique desde su conocimiento general.
        if (!_modoAnalista && i == 0 && m.role == 'user') {
          content =
              '[Panel Power BI activo: "${widget.reportTitle}"]\n\n'
              '$content\n\n'
              'Responde desde tu conocimiento general sobre Power BI y análisis de datos.';
        }
        history.add({'role': m.role, 'content': content});
      }

      final payload = <String, dynamic>{'messages': history};
      if (_modoAnalista) {
        payload['link_id'] = widget.linkId;
        payload['titulo'] = widget.reportTitle;
      }

      final resp = await http
          .post(
            Uri.parse(_modoAnalista ? _fnAnalista : _fnGeneral),
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          // El modo analista consulta Power BI y puede encadenar herramientas, así que
          // necesita más margen que una respuesta conversacional.
          .timeout(Duration(seconds: _modoAnalista ? 120 : 60));

      if (!mounted) return;

      if (resp.statusCode != 200) {
        final errBody = jsonDecode(resp.body) as Map<String, dynamic>;
        throw Exception(
            errBody['error']?.toString() ?? 'Error ${resp.statusCode}');
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final reply = (body['text'] as String? ?? '').trim();

      // Tabla de resultados, cuando el asistente consultó cifras.
      List<Map<String, dynamic>>? rows;
      Map<String, dynamic>? formatos;
      bool truncated = false;
      final structured = body['structured'];
      if (structured is Map && structured['type'] == 'pbi_rows') {
        final data = structured['data'];
        if (data is List && data.isNotEmpty) {
          rows = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        // Sin esto los porcentajes se pintan como 0.99 donde el panel dice 99.5%.
        final f = structured['formatos'];
        if (f is Map) formatos = Map<String, dynamic>.from(f);
        truncated = structured['truncated'] == true;
      }

      setState(() {
        _loading = false;
        _messages.add(_AiMsg(
          role: 'assistant',
          text: reply.isNotEmpty ? reply : '(Sin respuesta del modelo)',
          rows: rows,
          formatos: formatos,
          truncated: truncated,
        ));
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _messages.add(_AiMsg(role: 'assistant', text: 'Error: $e'));
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    return Column(
      children: [
        // Panel header
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: SiSpace.x4, vertical: SiSpace.x3),
          decoration:
              BoxDecoration(color: c.brandTint),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: c.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Asistente BI',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.brand),
                ),
              ),
            ],
          ),
        ),
        // Messages
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(SiSpace.x5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bar_chart_outlined,
                            size: 40, color: c.line),
                        const SizedBox(height: SiSpace.x3),
                        Text(
                          'Pregúntame sobre\n"${widget.reportTitle}"',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 13, color: c.ink3),
                        ),
                        const SizedBox(height: SiSpace.x3),
                        // Se declara la capacidad real: con dataset lee cifras, sin él
                        // sólo explica. Así el usuario no descubre el límite fallando.
                        Text(
                          _modoAnalista
                              ? 'Consulta las cifras reales del reporte'
                              : 'Sin dataset configurado: puedo explicar el panel, '
                                  'pero no leer sus cifras',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: _modoAnalista ? c.brand : c.warn,
                          ),
                        ),
                        const SizedBox(height: SiSpace.x5),
                        if (_modoAnalista) ...[
                          _QuickChip(
                            label: '¿Qué puedes consultar de este reporte?',
                            onTap: () => _send(
                                '¿Qué medidas y desgloses puedes consultar en este reporte?'),
                          ),
                          const SizedBox(height: SiSpace.x2),
                          _QuickChip(
                            label: 'Resumen del periodo actual',
                            onTap: () => _send(
                                'Dame un resumen de las cifras principales del periodo actual.'),
                          ),
                        ] else ...[
                          _QuickChip(
                            label: '¿Qué métricas muestra este panel?',
                            onTap: () => _send(
                                '¿Qué métricas o indicadores suele mostrar un panel llamado "${widget.reportTitle}"?'),
                          ),
                          const SizedBox(height: SiSpace.x2),
                          _QuickChip(
                            label: '¿Cómo interpreto los datos?',
                            onTap: () => _send(
                                '¿Cómo debo interpretar los datos de un reporte titulado "${widget.reportTitle}"?'),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(SiSpace.x3),
                  itemCount: _messages.length + (_loading ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (_loading && i == _messages.length) {
                      return _BubbleTyping(c: c);
                    }
                    final msg = _messages[i];
                    final rows = msg.rows;
                    if (rows == null) return _Bubble(msg: msg, c: c);
                    // Las cifras consultadas se muestran además como tabla: el texto del
                    // modelo interpreta, la tabla deja ver el dato tal como llegó.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Bubble(msg: msg, c: c),
                        _ResultTable(
                          rows: rows,
                          formatos: msg.formatos,
                          truncated: msg.truncated,
                          c: c,
                        ),
                      ],
                    );
                  },
                ),
        ),
        // Input
        Container(
          decoration: BoxDecoration(
            color: c.panel,
            border: Border(top: BorderSide(color: c.line)),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: SiSpace.x3, vertical: SiSpace.x2),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  minLines: 1,
                  maxLines: 4,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Escribe tu pregunta...',
                    hintStyle:
                        TextStyle(fontSize: 13, color: c.ink4),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: _send,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: _loading
                    ? null
                    : () => _send(_inputCtrl.text),
                icon: _loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: c.brand))
                    : Icon(Icons.send_rounded,
                        color: c.brand, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: c.brand.withValues(alpha: 0.4)),
          borderRadius: SiRadius.rPill,
          color: c.brandTint,
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.brand)),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _AiMsg msg;
  final SiColors c;
  const _Bubble({required this.msg, required this.c});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () =>
            Clipboard.setData(ClipboardData(text: msg.text)),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 340),
          decoration: BoxDecoration(
            color: isUser ? c.brand : c.bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isUser ? 14 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 14),
            ),
            border: isUser ? null : Border.all(color: c.line),
          ),
          child: Text(
            msg.text,
            style: TextStyle(
                fontSize: 13,
                color: isUser ? Colors.white : c.ink,
                height: 1.4),
          ),
        ),
      ),
    );
  }
}

class _BubbleTyping extends StatelessWidget {
  final SiColors c;
  const _BubbleTyping({required this.c});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: SizedBox(
          width: 36,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: c.brand),
        ),
      ),
    );
  }
}

class _AiMsg {
  final String role;
  final String text;

  /// Filas devueltas por pbi_consultar, para pintarlas como tabla debajo del texto.
  final List<Map<String, dynamic>>? rows;

  /// FormatString por medida. Imprescindible: los porcentajes llegan como fracción, y sin
  /// esta pista la tabla pinta 0.99 donde el panel dice 99.5%.
  final Map<String, dynamic>? formatos;

  final bool truncated;

  const _AiMsg({
    required this.role,
    required this.text,
    this.rows,
    this.formatos,
    this.truncated = false,
  });
}

/// Tabla de resultados de una consulta al dataset.
///
/// Las llaves llegan como "[Alias]" para las medidas y "Tabla[Columna]" para las
/// dimensiones; se limpian para el encabezado pero se conserva el orden original, que es
/// el que definió la consulta.
class _ResultTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic>? formatos;
  final bool truncated;
  final SiColors c;

  const _ResultTable({
    required this.rows,
    required this.truncated,
    required this.c,
    this.formatos,
  });

  /// El nombre de la medida dentro de "[Alias]", para cruzarlo con el mapa de formatos.
  static String _medida(String key) {
    final m = RegExp(r'^\[(.+)\]$').firstMatch(key);
    return m?.group(1) ?? key;
  }

  static String _encabezado(String key) {
    final m = RegExp(r'^(.*?)\[(.+)\]$').firstMatch(key);
    return m?.group(2) ?? key;
  }

  bool _esPorcentaje(String key) {
    final f = formatos?[_medida(key)];
    return f is String && f.contains('%');
  }

  /// Separador de miles, respetando el signo.
  static String _miles(String entero) {
    final signo = entero.startsWith('-') ? '-' : '';
    final digitos = entero.replaceFirst('-', '');
    final buf = StringBuffer();
    for (int i = 0; i < digitos.length; i++) {
      if (i > 0 && (digitos.length - i) % 3 == 0) buf.write(',');
      buf.write(digitos[i]);
    }
    return '$signo$buf';
  }

  String _celda(String key, dynamic v) {
    if (v == null) return '—';
    if (v is! num) return v.toString();

    // Los porcentajes se guardan como fracción: 0.9946 es 99.5%. Mostrar el crudo sería
    // un error de 100x que se lee como perfectamente razonable.
    if (_esPorcentaje(key)) {
      final pct = v * 100;
      // Un valor diminuto pero distinto de cero no debe verse como un cero redondo.
      if (pct != 0 && pct.abs() < 0.05) return '<0.1%';
      return '${pct.toStringAsFixed(1)}%';
    }

    final entero = v == v.roundToDouble() && v.abs() < 1e15;
    if (entero) return _miles(v.toInt().toString());

    if (v.abs() < 0.005) return '<0.01';
    final partes = v.toStringAsFixed(2).split('.');
    return '${_miles(partes[0])}.${partes[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final llaves = rows.first.keys.toList();

    return Container(
      margin: const EdgeInsets.only(top: SiSpace.x2, bottom: SiSpace.x2),
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Las tablas anchas se desplazan dentro de su caja, no arrastran el panel.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 34,
              dataRowMinHeight: 30,
              dataRowMaxHeight: 38,
              horizontalMargin: 12,
              columnSpacing: 20,
              columns: llaves
                  .map((k) => DataColumn(
                        label: Text(
                          _encabezado(k),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: c.ink2),
                        ),
                      ))
                  .toList(),
              rows: rows
                  .map((r) => DataRow(
                        cells: llaves
                            .map((k) => DataCell(Text(
                                  _celda(k, r[k]),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: c.ink,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ]),
                                )))
                            .toList(),
                      ))
                  .toList(),
            ),
          ),
          if (truncated)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'Lista recortada: hay más renglones de los que se muestran.',
                style: TextStyle(fontSize: 11, color: c.warn),
              ),
            ),
        ],
      ),
    );
  }
}
