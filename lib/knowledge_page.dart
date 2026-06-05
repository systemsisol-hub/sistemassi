import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme/si_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants & helpers
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _kCategories = [
  'General',
  'Recursos Humanos',
  'Tecnología',
  'Procedimientos',
  'Aplicaciones',
  'Soporte',
];

const Map<String, (IconData, Color)> _kCatMeta = {
  'General':          (Icons.home_work_outlined,    Color(0xFF6366F1)),
  'Recursos Humanos': (Icons.people_outline,         Color(0xFF10B981)),
  'Tecnología':       (Icons.computer_outlined,      Color(0xFF3B82F6)),
  'Procedimientos':   (Icons.assignment_outlined,    Color(0xFFF59E0B)),
  'Aplicaciones':     (Icons.apps_outlined,          Color(0xFF8B5CF6)),
  'Soporte':          (Icons.support_agent_outlined, Color(0xFFEF4444)),
};

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inDays >= 365) {
    final y = (diff.inDays / 365).floor();
    return 'hace $y ${y == 1 ? "año" : "años"}';
  }
  if (diff.inDays >= 30) {
    final m = (diff.inDays / 30).floor();
    return 'hace $m ${m == 1 ? "mes" : "meses"}';
  }
  if (diff.inDays > 0) {
    return 'hace ${diff.inDays} ${diff.inDays == 1 ? "día" : "días"}';
  }
  if (diff.inHours > 0) return 'hace ${diff.inHours} h';
  if (diff.inMinutes > 0) return 'hace ${diff.inMinutes} min';
  return 'ahora mismo';
}

String _mimeFromExt(String ext) {
  switch (ext.toLowerCase()) {
    case 'pdf':  return 'application/pdf';
    case 'png':  return 'image/png';
    case 'jpg':
    case 'jpeg': return 'image/jpeg';
    case 'gif':  return 'image/gif';
    case 'webp': return 'image/webp';
    case 'doc':  return 'application/msword';
    case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':  return 'application/vnd.ms-excel';
    case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'zip':  return 'application/zip';
    case 'mp4':  return 'video/mp4';
    default:     return 'application/octet-stream';
  }
}

IconData _fileIcon(String? type) {
  if (type == null) return Icons.attach_file_outlined;
  if (type.contains('pdf'))   return Icons.picture_as_pdf_outlined;
  if (type.contains('image')) return Icons.image_outlined;
  if (type.contains('word') || type.contains('document')) return Icons.article_outlined;
  if (type.contains('excel') || type.contains('sheet'))   return Icons.table_chart_outlined;
  if (type.contains('zip'))   return Icons.archive_outlined;
  if (type.contains('video')) return Icons.video_file_outlined;
  return Icons.attach_file_outlined;
}

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null && await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

class _Article {
  final String id;
  final String title;
  final String description;
  final String content;
  final String category;
  final String audience;
  final String? fileUrl;
  final String? fileName;
  final String? fileType;
  final int? fileSize;
  final List<String> tags;
  final int views;
  final bool pinned;
  final String? createdByName;
  final DateTime createdAt;

  const _Article({
    required this.id,
    required this.title,
    required this.description,
    required this.content,
    required this.category,
    required this.audience,
    this.fileUrl,
    this.fileName,
    this.fileType,
    this.fileSize,
    required this.tags,
    required this.views,
    required this.pinned,
    this.createdByName,
    required this.createdAt,
  });

  factory _Article.fromJson(Map<String, dynamic> j) => _Article(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        description: j['description'] as String? ?? '',
        content: j['content'] as String? ?? '',
        category: j['category'] as String? ?? 'General',
        audience: j['audience'] as String? ?? 'all',
        fileUrl: j['file_url'] as String?,
        fileName: j['file_name'] as String?,
        fileType: j['file_type'] as String?,
        fileSize: j['file_size'] as int?,
        tags: (j['tags'] as List?)?.cast<String>() ?? [],
        views: j['views'] as int? ?? 0,
        pinned: j['pinned'] as bool? ?? false,
        createdByName: j['created_by_name'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// KnowledgePage
// ─────────────────────────────────────────────────────────────────────────────

class KnowledgePage extends StatefulWidget {
  final String role;
  const KnowledgePage({super.key, this.role = 'usuario'});

  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage>
    with SingleTickerProviderStateMixin {
  TabController? _tabCtrl;
  final _searchCtrl = TextEditingController();

  List<_Article> _articles = [];
  bool _loading = true;
  String? _error;
  String _selectedCategory = 'Todos';
  bool _showSearch = false;

  bool get _isAdmin => widget.role == 'admin';

  @override
  void initState() {
    super.initState();
    if (_isAdmin) {
      _tabCtrl = TabController(length: 2, vsync: this)
        ..addListener(() { if (mounted) setState(() {}); });
    }
    _load();
  }

  @override
  void dispose() {
    _tabCtrl?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await Supabase.instance.client
          .from('knowledge_articles')
          .select()
          .order('pinned', ascending: false)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _articles = (data as List).map((e) => _Article.fromJson(e)).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  List<_Article> _filtered(String audience) {
    final q = _searchCtrl.text.toLowerCase().trim();
    return _articles.where((a) {
      if (a.audience != audience) return false;
      if (_selectedCategory != 'Todos' && a.category != _selectedCategory) {
        return false;
      }
      if (q.isEmpty) return true;
      return a.title.toLowerCase().contains(q) ||
          a.description.toLowerCase().contains(q) ||
          a.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          _buildHeader(c),
          if (_isAdmin && _tabCtrl != null) _buildTabBar(c),
          _buildCategoryFilter(c),
          Expanded(child: _buildContent(c)),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton(
              onPressed: () => _openForm(context, c),
              backgroundColor: c.brand,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(SiColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.brandTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.library_books_outlined, size: 20, color: c.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _showSearch
                ? TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Buscar guías, artículos...',
                      hintStyle: TextStyle(color: c.ink4, fontSize: 14),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: TextStyle(fontSize: 15, color: c.ink),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Base de Conocimientos',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: c.ink)),
                      Text('Guías y recursos de la empresa',
                          style: TextStyle(fontSize: 12, color: c.ink3)),
                    ],
                  ),
          ),
          _showSearch
              ? IconButton(
                  icon: Icon(Icons.close, color: c.ink3),
                  onPressed: () => setState(() {
                    _showSearch = false;
                    _searchCtrl.clear();
                  }),
                )
              : IconButton(
                  icon: Icon(Icons.search, color: c.ink3),
                  onPressed: () => setState(() => _showSearch = true),
                ),
        ],
      ),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────

  Widget _buildTabBar(SiColors c) {
    return Container(
      color: c.panel,
      child: TabBar(
        controller: _tabCtrl!,
        tabs: const [
          Tab(icon: Icon(Icons.people_outline, size: 16), text: 'Colaboradores'),
          Tab(icon: Icon(Icons.admin_panel_settings_outlined, size: 16), text: 'Administradores'),
        ],
        labelColor: c.brand,
        unselectedLabelColor: c.ink3,
        indicatorColor: c.brand,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
      ),
    );
  }

  // ── Category filter ───────────────────────────────────────────────────────

  Widget _buildCategoryFilter(SiColors c) {
    final cats = ['Todos', ..._kCategories];
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.line, width: 0.5)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = cats[i];
          final sel = _selectedCategory == cat;
          final meta = _kCatMeta[cat];
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: sel ? c.brand : c.hover,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? c.brand : c.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (meta != null && !sel) ...[
                    Icon(meta.$1, size: 12, color: meta.$2),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    cat,
                    style: TextStyle(
                      fontSize: 12,
                      color: sel ? Colors.white : c.ink3,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Content ────────────────────────────────────────────────────────────────

  Widget _buildContent(SiColors c) {
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: c.brand, strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
          child: Text(_error!, style: TextStyle(color: c.danger)));
    }

    if (_isAdmin && _tabCtrl != null) {
      return TabBarView(
        controller: _tabCtrl!,
        children: [
          _buildList(_filtered('all'), c),
          _buildList(_filtered('admin'), c),
        ],
      );
    }

    return _buildList(_filtered('all'), c);
  }

  Widget _buildList(List<_Article> articles, SiColors c) {
    if (articles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 52, color: c.ink4),
            const SizedBox(height: 14),
            Text(
              _searchCtrl.text.isNotEmpty
                  ? 'Sin resultados para "${_searchCtrl.text}"'
                  : 'Aún no hay artículos aquí',
              style: TextStyle(fontSize: 15, color: c.ink3),
            ),
            if (_isAdmin && _searchCtrl.text.isEmpty) ...[
              const SizedBox(height: 8),
              Text('Toca + para agregar el primero',
                  style: TextStyle(fontSize: 13, color: c.ink4)),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: c.brand,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
        itemCount: articles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _ArticleCard(
          article: articles[i],
          c: c,
          onTap: () => _openDetail(context, articles[i], c),
        ),
      ),
    );
  }

  // ── Navigation to detail / form ───────────────────────────────────────────

  void _openDetail(BuildContext context, _Article article, SiColors c) {
    // Fire-and-forget views increment
    Supabase.instance.client.rpc(
      'increment_knowledge_views',
      params: {'article_id': article.id},
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ArticleDetailSheet(
        article: article,
        c: c,
        isAdmin: _isAdmin,
        onEdit: () {
          Navigator.pop(context);
          _openForm(context, c, article: article);
        },
        onDelete: () {
          Navigator.pop(context);
          _deleteArticle(context, article);
        },
      ),
    );
  }

  void _openForm(BuildContext context, SiColors c, {_Article? article}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ArticleFormSheet(
        c: c,
        article: article,
        onSaved: _load,
      ),
    );
  }

  Future<void> _deleteArticle(BuildContext context, _Article article) async {
    final c = SiColors.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.panel,
        title: const Text('Eliminar artículo'),
        content: Text(
            '¿Eliminar "${article.title}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Eliminar',
                  style: TextStyle(color: c.danger))),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      await Supabase.instance.client
          .from('knowledge_articles')
          .delete()
          .eq('id', article.id);

      if (article.fileUrl != null) {
        try {
          final uri = Uri.tryParse(article.fileUrl!);
          if (uri != null) {
            final segs = uri.pathSegments;
            final idx = segs.indexOf('knowledge-files');
            if (idx != -1 && idx < segs.length - 1) {
              final path = segs.sublist(idx + 1).join('/');
              await Supabase.instance.client.storage
                  .from('knowledge-files')
                  .remove([path]);
            }
          }
        } catch (_) {}
      }

      _load();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al eliminar: $e'),
              backgroundColor: c.danger),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ArticleCard  (forum-style list item)
// ─────────────────────────────────────────────────────────────────────────────

class _ArticleCard extends StatelessWidget {
  final _Article article;
  final SiColors c;
  final VoidCallback onTap;

  const _ArticleCard({
    required this.article,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final meta = _kCatMeta[article.category] ??
        (Icons.article_outlined, const Color(0xFF6366F1));
    final catColor = meta.$2;
    final catIcon  = meta.$1;

    return Material(
      color: c.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: category + pinned ──────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: catColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(catIcon, size: 18, color: catColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                article.title,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: c.ink),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (article.pinned) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.push_pin, size: 14, color: c.brand),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          article.category,
                          style: TextStyle(
                              fontSize: 11,
                              color: catColor,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // ── Description ─────────────────────────────────────────────
              if (article.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  article.description,
                  style: TextStyle(fontSize: 13, color: c.ink2, height: 1.45),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // ── Tags ────────────────────────────────────────────────────
              if (article.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: article.tags.take(4).map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.hover,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.line),
                      ),
                      child: Text(tag,
                          style: TextStyle(fontSize: 10, color: c.ink3)),
                    );
                  }).toList(),
                ),
              ],
              // ── Footer: file + views + date ──────────────────────────────
              const SizedBox(height: 10),
              Row(
                children: [
                  if (article.fileUrl != null) ...[
                    Icon(_fileIcon(article.fileType), size: 13, color: c.brand),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        article.fileName ?? 'Archivo adjunto',
                        style: TextStyle(
                            fontSize: 11,
                            color: c.brand,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Icon(Icons.remove_red_eye_outlined,
                      size: 13, color: c.ink4),
                  const SizedBox(width: 4),
                  Text('${article.views}',
                      style: TextStyle(fontSize: 11, color: c.ink4)),
                  const Spacer(),
                  if (article.createdByName != null) ...[
                    Text(article.createdByName!,
                        style: TextStyle(fontSize: 11, color: c.ink4)),
                    const SizedBox(width: 6),
                    Container(width: 2, height: 2,
                        decoration: BoxDecoration(
                            color: c.ink4, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                  ],
                  Text(_timeAgo(article.createdAt),
                      style: TextStyle(fontSize: 11, color: c.ink4)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ArticleDetailSheet
// ─────────────────────────────────────────────────────────────────────────────

class _ArticleDetailSheet extends StatelessWidget {
  final _Article article;
  final SiColors c;
  final bool isAdmin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ArticleDetailSheet({
    required this.article,
    required this.c,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final meta = _kCatMeta[article.category] ??
        (Icons.article_outlined, const Color(0xFF6366F1));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Column(
        children: [
          // ── Handle ──────────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: c.line, borderRadius: BorderRadius.circular(2)),
          ),
          // ── Title bar ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: meta.$2.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(meta.$1, size: 20, color: meta.$2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(article.category,
                          style: TextStyle(
                              fontSize: 11,
                              color: meta.$2,
                              fontWeight: FontWeight.w600)),
                      Text(article.title,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: c.ink),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (isAdmin) ...[
                  IconButton(
                    icon: Icon(Icons.edit_outlined, color: c.brand, size: 20),
                    onPressed: onEdit,
                    tooltip: 'Editar',
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: c.danger, size: 20),
                    onPressed: onDelete,
                    tooltip: 'Eliminar',
                  ),
                ],
                IconButton(
                  icon: Icon(Icons.close, color: c.ink3, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          // ── Scrollable body ───────────────────────────────────────────────
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                // Meta row
                Row(
                  children: [
                    if (article.pinned) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.brandTint,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.brand.withOpacity(0.3)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.push_pin, size: 11, color: c.brand),
                          const SizedBox(width: 4),
                          Text('Destacado',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: c.brand,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Icon(Icons.remove_red_eye_outlined,
                        size: 13, color: c.ink4),
                    const SizedBox(width: 4),
                    Text('${article.views} vistas',
                        style: TextStyle(fontSize: 12, color: c.ink4)),
                    if (article.createdByName != null) ...[
                      const SizedBox(width: 10),
                      Container(width: 3, height: 3,
                          decoration: BoxDecoration(
                              color: c.ink4, shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Text(article.createdByName!,
                          style: TextStyle(fontSize: 12, color: c.ink4)),
                    ],
                    const Spacer(),
                    Text(_timeAgo(article.createdAt),
                        style: TextStyle(fontSize: 12, color: c.ink4)),
                  ],
                ),
                // Tags
                if (article.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: article.tags.map((tag) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.hover,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.line),
                      ),
                      child: Text(tag,
                          style: TextStyle(fontSize: 12, color: c.ink3)),
                    )).toList(),
                  ),
                ],
                // Archivo adjunto
                if (article.fileUrl != null) ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _openUrl(article.fileUrl!),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.brandTint,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.brand.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: c.brand.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(_fileIcon(article.fileType),
                                size: 22, color: c.brand),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(article.fileName ?? 'Archivo adjunto',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: c.brand),
                                    overflow: TextOverflow.ellipsis),
                                if (article.fileSize != null)
                                  Text(_formatBytes(article.fileSize!),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: c.brand.withOpacity(0.7))),
                              ],
                            ),
                          ),
                          Icon(Icons.open_in_new,
                              size: 18, color: c.brand),
                        ],
                      ),
                    ),
                  ),
                ],
                // Descripción
                if (article.description.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(article.description,
                      style: TextStyle(
                          fontSize: 14,
                          color: c.ink2,
                          fontStyle: FontStyle.italic,
                          height: 1.55)),
                ],
                // Contenido
                if (article.content.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Divider(color: c.line),
                  const SizedBox(height: 16),
                  _ContentRenderer(content: article.content, c: c),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ContentRenderer  (simple pseudo-markdown)
// ─────────────────────────────────────────────────────────────────────────────

class _ContentRenderer extends StatelessWidget {
  final String content;
  final SiColors c;
  const _ContentRenderer({required this.content, required this.c});

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final widgets = <Widget>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.startsWith('# ')) {
        widgets.add(Text(line.substring(2),
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: c.ink,
                height: 1.3)));
        widgets.add(const SizedBox(height: 6));
      } else if (line.startsWith('## ')) {
        widgets.add(Text(line.substring(3),
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.ink,
                height: 1.3)));
        widgets.add(const SizedBox(height: 4));
      } else if (line.startsWith('### ')) {
        widgets.add(Text(line.substring(4),
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.ink,
                height: 1.3)));
        widgets.add(const SizedBox(height: 4));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Container(
                    width: 5, height: 5,
                    decoration: BoxDecoration(
                        color: c.brand, shape: BoxShape.circle)),
              ),
              Expanded(
                child: Text(line.substring(2),
                    style: TextStyle(
                        fontSize: 14, color: c.ink, height: 1.6)),
              ),
            ],
          ),
        ));
      } else if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 10));
      } else {
        widgets.add(SelectableText(
          line,
          style: TextStyle(fontSize: 14, color: c.ink, height: 1.65),
        ));
        widgets.add(const SizedBox(height: 2));
      }
    }

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ArticleFormSheet  (admin create / edit)
// ─────────────────────────────────────────────────────────────────────────────

class _ArticleFormSheet extends StatefulWidget {
  final SiColors c;
  final _Article? article;
  final VoidCallback onSaved;

  const _ArticleFormSheet({
    required this.c,
    this.article,
    required this.onSaved,
  });

  @override
  State<_ArticleFormSheet> createState() => _ArticleFormSheetState();
}

class _ArticleFormSheetState extends State<_ArticleFormSheet> {
  final _titleCtrl   = TextEditingController();
  final _descCtrl    = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _tagCtrl     = TextEditingController();

  String   _category = 'General';
  String   _audience = 'all';
  bool     _pinned   = false;
  bool     _saving   = false;
  String?  _error;

  List<String>  _tags      = [];
  Uint8List?    _fileBytes;
  String?       _fileName;
  String?       _fileExt;
  String?       _existingFileUrl;
  String?       _existingFileName;
  String?       _existingFileType;

  SiColors get c => widget.c;

  @override
  void initState() {
    super.initState();
    final a = widget.article;
    if (a != null) {
      _titleCtrl.text   = a.title;
      _descCtrl.text    = a.description;
      _contentCtrl.text = a.content;
      _category         = a.category;
      _audience         = a.audience;
      _pinned           = a.pinned;
      _tags             = List<String>.from(a.tags);
      _existingFileUrl  = a.fileUrl;
      _existingFileName = a.fileName;
      _existingFileType = a.fileType;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _contentCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf', 'png', 'jpg', 'jpeg', 'gif', 'webp',
        'doc', 'docx', 'xls', 'xlsx', 'zip', 'mp4', 'txt'
      ],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;
    setState(() {
      _fileBytes = f.bytes;
      _fileName  = f.name;
      _fileExt   = f.extension ?? '';
    });
  }

  void _addTag(String raw) {
    final tag = raw.trim().replaceAll(',', '').trim();
    if (tag.isEmpty || _tags.contains(tag)) return;
    setState(() => _tags.add(tag));
    _tagCtrl.clear();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _error = 'El título es obligatorio');
      return;
    }
    setState(() { _saving = true; _error = null; });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      final db   = Supabase.instance.client;

      final payload = <String, dynamic>{
        'title':           _titleCtrl.text.trim(),
        'description':     _descCtrl.text.trim(),
        'content':         _contentCtrl.text.trim(),
        'category':        _category,
        'audience':        _audience,
        'pinned':          _pinned,
        'tags':            _tags,
        'created_by':      user?.id,
        'created_by_name': user?.userMetadata?['full_name']?.toString() ??
            user?.email?.split('@').first ?? 'Admin',
        'updated_at': DateTime.now().toIso8601String(),
      };

      String articleId;

      if (widget.article != null) {
        // Update existing
        await db.from('knowledge_articles').update(payload).eq('id', widget.article!.id);
        articleId = widget.article!.id;
      } else {
        // Insert new
        final res = await db.from('knowledge_articles').insert(payload).select('id').single();
        articleId = res['id'] as String;
      }

      // Upload new file if picked
      if (_fileBytes != null && _fileName != null) {
        final ext  = _fileExt ?? '';
        final mime = _mimeFromExt(ext);
        final path = '$articleId/${DateTime.now().millisecondsSinceEpoch}_$_fileName';

        await db.storage
            .from('knowledge-files')
            .uploadBinary(path, _fileBytes!,
                fileOptions: FileOptions(contentType: mime, upsert: true));

        final url = db.storage.from('knowledge-files').getPublicUrl(path);

        await db.from('knowledge_articles').update({
          'file_url':  url,
          'file_name': _fileName,
          'file_type': mime,
          'file_size': _fileBytes!.length,
        }).eq('id', articleId);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.article != null;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.97,
        builder: (_, ctrl) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: c.line, borderRadius: BorderRadius.circular(2)),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 12),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: c.brandTint,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    editing ? Icons.edit_outlined : Icons.add_circle_outline,
                    size: 18, color: c.brand,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  editing ? 'Editar artículo' : 'Nuevo artículo',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: c.ink),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: c.ink3),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
            ),
            Divider(height: 1, color: c.line),
            // Form body
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.dangerTint,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.danger.withOpacity(0.3)),
                      ),
                      child: Text(_error!,
                          style: TextStyle(fontSize: 13, color: c.danger)),
                    ),
                  // Title
                  _fieldLabel('Título *'),
                  _textField(_titleCtrl,
                      hint: 'Ej: Cómo usar el sistema de incidencias',
                      maxLines: 2),
                  const SizedBox(height: 16),
                  // Category + Audience row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('Categoría'),
                            Container(
                              decoration: BoxDecoration(
                                color: c.bg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: c.line),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 2),
                              child: DropdownButton<String>(
                                value: _category,
                                isExpanded: true,
                                underline: const SizedBox.shrink(),
                                dropdownColor: c.panel,
                                style: TextStyle(
                                    fontSize: 13, color: c.ink),
                                items: _kCategories.map((cat) {
                                  final meta = _kCatMeta[cat]!;
                                  return DropdownMenuItem(
                                    value: cat,
                                    child: Row(children: [
                                      Icon(meta.$1,
                                          size: 14, color: meta.$2),
                                      const SizedBox(width: 8),
                                      Text(cat,
                                          style: TextStyle(
                                              fontSize: 13, color: c.ink)),
                                    ]),
                                  );
                                }).toList(),
                                onChanged: (v) =>
                                    setState(() => _category = v!),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('Visible para'),
                            Container(
                              decoration: BoxDecoration(
                                color: c.bg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: c.line),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 2),
                              child: DropdownButton<String>(
                                value: _audience,
                                isExpanded: true,
                                underline: const SizedBox.shrink(),
                                dropdownColor: c.panel,
                                style: TextStyle(fontSize: 13, color: c.ink),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Row(children: [
                                      Icon(Icons.people_outline,
                                          size: 14, color: Color(0xFF10B981)),
                                      SizedBox(width: 8),
                                      Text('Todos'),
                                    ]),
                                  ),
                                  DropdownMenuItem(
                                    value: 'admin',
                                    child: Row(children: [
                                      Icon(Icons.admin_panel_settings_outlined,
                                          size: 14, color: Color(0xFF6366F1)),
                                      SizedBox(width: 8),
                                      Text('Solo admins'),
                                    ]),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _audience = v!),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Description
                  _fieldLabel('Descripción corta'),
                  _textField(_descCtrl,
                      hint: 'Breve resumen del contenido…', maxLines: 3),
                  const SizedBox(height: 16),
                  // Content
                  _fieldLabel('Contenido'),
                  Container(
                    decoration: BoxDecoration(
                      color: c.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.line),
                    ),
                    child: TextField(
                      controller: _contentCtrl,
                      maxLines: 12,
                      minLines: 6,
                      decoration: InputDecoration(
                        hintText:
                            'Escribe el contenido completo del artículo.\n\n'
                            'Puedes usar:\n'
                            '# Título grande\n'
                            '## Subtítulo\n'
                            '- Elemento de lista',
                        hintStyle: TextStyle(
                            color: c.ink4, fontSize: 13, height: 1.5),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(12),
                        isDense: true,
                      ),
                      style: TextStyle(
                          fontSize: 13, color: c.ink, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Tags
                  _fieldLabel('Etiquetas'),
                  if (_tags.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 6, runSpacing: 6,
                        children: _tags.map((tag) => Chip(
                          label: Text(tag,
                              style: TextStyle(
                                  fontSize: 12, color: c.brand)),
                          backgroundColor: c.brandTint,
                          side: BorderSide(
                              color: c.brand.withOpacity(0.3)),
                          deleteIconColor: c.brand,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onDeleted: () =>
                              setState(() => _tags.remove(tag)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 0),
                        )).toList(),
                      ),
                    ),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: _textField(
                          _tagCtrl,
                          hint: 'Escribe una etiqueta y presiona Enter',
                          onSubmitted: _addTag,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _addTag(_tagCtrl.text),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: c.brandTint,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: c.brand.withOpacity(0.3)),
                          ),
                          child: Icon(Icons.add, size: 18, color: c.brand),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // File attachment
                  _fieldLabel('Archivo adjunto'),
                  GestureDetector(
                    onTap: _pickFile,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: (_fileBytes != null || _existingFileUrl != null)
                            ? c.brandTint
                            : c.hover,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (_fileBytes != null || _existingFileUrl != null)
                              ? c.brand.withOpacity(0.4)
                              : c.line,
                          style: _fileBytes == null && _existingFileUrl == null
                              ? BorderStyle.solid
                              : BorderStyle.solid,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _fileBytes != null
                                ? _fileIcon(_mimeFromExt(_fileExt ?? ''))
                                : _existingFileUrl != null
                                    ? _fileIcon(_existingFileType)
                                    : Icons.cloud_upload_outlined,
                            size: 20,
                            color: (_fileBytes != null || _existingFileUrl != null)
                                ? c.brand
                                : c.ink3,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _fileBytes != null
                                  ? _fileName!
                                  : _existingFileUrl != null
                                      ? '${_existingFileName ?? 'Archivo actual'} (toca para cambiar)'
                                      : 'Toca para adjuntar un archivo',
                              style: TextStyle(
                                fontSize: 13,
                                color: (_fileBytes != null || _existingFileUrl != null)
                                    ? c.brand
                                    : c.ink3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_fileBytes != null)
                            GestureDetector(
                              onTap: () => setState(() {
                                _fileBytes = null;
                                _fileName  = null;
                                _fileExt   = null;
                              }),
                              child: Icon(Icons.close, size: 16, color: c.brand),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Pinned toggle
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: c.hover,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.line),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.push_pin_outlined,
                            size: 18, color: c.ink3),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Destacar artículo',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: c.ink)),
                              Text('Aparecerá primero en la lista',
                                  style: TextStyle(
                                      fontSize: 11, color: c.ink4)),
                            ],
                          ),
                        ),
                        Switch(
                          value: _pinned,
                          onChanged: (v) => setState(() => _pinned = v),
                          activeColor: c.brand,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
            // Save button
            Container(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20,
                  MediaQuery.of(context).padding.bottom + 12),
              decoration: BoxDecoration(
                color: c.panel,
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(
                          editing ? 'Guardar cambios' : 'Publicar artículo',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.ink3)),
      );

  Widget _textField(
    TextEditingController ctrl, {
    String hint = '',
    int maxLines = 1,
    void Function(String)? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.line),
      ),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        minLines: 1,
        textInputAction:
            onSubmitted != null ? TextInputAction.done : TextInputAction.newline,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: c.ink4, fontSize: 13),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
        style: TextStyle(fontSize: 13, color: c.ink),
      ),
    );
  }
}
