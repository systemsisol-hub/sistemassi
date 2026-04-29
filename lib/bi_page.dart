import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webviewx_plus/webviewx_plus.dart';
import 'bi_web_iframe_stub.dart' if (dart.library.html) 'bi_web_iframe.dart'
    as iframe_impl;

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
  List<Map<String, dynamic>> _userLinks = [];
  List<Map<String, dynamic>> _availableUsers = [];
  bool _isLoading = true;
  bool get _isAdmin => widget.role == 'admin';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;

      // Obtener perfil del usuario actual para verificar permisos
      Map<String, dynamic>? currentUserProfile;
      try {
        final profileData = await _supabase
            .from('profiles')
            .select('permissions')
            .eq('id', userId ?? '')
            .single();
        currentUserProfile = Map<String, dynamic>.from(profileData);
      } catch (e) {
        debugPrint('Error fetching current user profile: $e');
      }

      final hasPowerBiPermission = currentUserProfile?['permissions'] is Map &&
          currentUserProfile?['permissions']['show_powerbi'] == true;

      // Si tiene permiso show_powerbi, puede ver los enlaces asignados o creados
      if (hasPowerBiPermission) {
        // Enlaces donde el usuario está asignado
        final userLinksData = await _supabase
            .from('powerbi_link_users')
            .select(
                'link_id, powerbi_links(id, title, url, descripcion, is_active, created_by)')
            .eq('user_id', userId ?? '');

        final assignedLinks = (userLinksData as List)
            .where((item) {
              final link = item['powerbi_links'];
              return link != null && link['is_active'] == true;
            })
            .map((item) =>
                Map<String, dynamic>.from(item['powerbi_links'] as Map))
            .toList();

        // Enlaces donde el usuario es el creador
        final createdLinksData = await _supabase
            .from('powerbi_links')
            .select('id, title, url, descripcion, is_active, created_by')
            .eq('created_by', userId ?? '')
            .eq('is_active', true);

        final createdLinks = (createdLinksData as List)
            .map((link) => Map<String, dynamic>.from(link))
            .toList();

        // Combinar y eliminar duplicados
        final allLinks = [...assignedLinks, ...createdLinks];
        final uniqueLinks = <String, Map<String, dynamic>>{};
        for (final link in allLinks) {
          uniqueLinks[link['id'].toString()] = link;
        }
        _links = uniqueLinks.values.toList();
      } else {
        _links = [];
      }
      _userLinks = _links;

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching Power BI data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getUsers() async {
    if (_availableUsers.isNotEmpty) return _availableUsers;

    final usersData = await _supabase
        .from('profiles')
        .select('id, nombre, paterno, materno, email, status_sys, permissions')
        .eq('status_sys', 'ACTIVO')
        .order('nombre');

    _availableUsers = (usersData as List)
        .where((user) {
          final perms = user['permissions'];
          return perms is Map && perms['show_powerbi'] == true;
        })
        .map((user) => Map<String, dynamic>.from(user))
        .toList();

    return _availableUsers;
  }

  Future<List<String>> _getLinkUserIds(String linkId) async {
    final data = await _supabase
        .from('powerbi_link_users')
        .select('user_id')
        .eq('link_id', linkId);
    return (data as List).map((e) => e['user_id'].toString()).toList();
  }

  Future<void> _toggleUserAccess(String linkId, String userId, bool add) async {
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

  Future<void> _openLink(Map<String, dynamic> link) async {
    final url = link['url'] as String?;
    final htmlCode = link['descripcion'] as String?;

    if (url != null && url.isNotEmpty) {
      showGeneralDialog(
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
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: _LinkViewer(
                  url: url,
                  title: link['title'] ?? 'Reporte',
                  onClose: () => Navigator.pop(dialogContext),
                ),
              ),
            ),
          );
        },
      );
    } else if (htmlCode != null && htmlCode.isNotEmpty) {
      if (mounted) {
        _showHtmlViewer(htmlCode, link['title'] ?? 'Reporte');
      }
    }
  }

  void _showHtmlViewer(String htmlCode, String title) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar',
                        style: TextStyle(fontSize: 16, color: Colors.grey)),
                  ),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 60),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  htmlCode,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLinkForm({Map<String, dynamic>? link}) {
    if (!mounted) return;
    final isEditing = link != null;
    final titleCtrl = TextEditingController(text: link?['title']);
    final urlCtrl = TextEditingController(text: link?['url']);
    final htmlCtrl = TextEditingController(text: link?['descripcion']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          bool saving = false;
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 40,
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
                        child: const Text('Cancelar',
                            style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ),
                      Text(
                        isEditing ? 'Editar Enlace' : 'Nuevo Enlace',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (titleCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('El título es obligatorio')));
                            return;
                          }
                          setModalState(() => saving = true);
                          try {
                            final data = {
                              'title': titleCtrl.text.trim().toUpperCase(),
                              'url': urlCtrl.text.trim().isEmpty
                                  ? null
                                  : urlCtrl.text.trim(),
                              'descripcion': htmlCtrl.text.trim().isEmpty
                                  ? null
                                  : htmlCtrl.text.trim(),
                              'is_active': true,
                              'created_by': _supabase.auth.currentUser?.id,
                            };
                            if (isEditing) {
                              await _supabase
                                  .from('powerbi_links')
                                  .update(data)
                                  .eq('id', link['id']);
                            } else {
                              await _supabase
                                  .from('powerbi_links')
                                  .insert(data);
                            }
                            if (mounted) {
                              Navigator.pop(context);
                              _fetchData();
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(isEditing
                                          ? 'Enlace actualizado'
                                          : 'Enlace creado')));
                            }
                          } catch (e) {
                            setModalState(() => saving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: Colors.red));
                            }
                          }
                        },
                        child: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Guardar',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Título *',
                          prefixIcon: Icon(Icons.title))),
                  const SizedBox(height: 16),
                  TextField(
                      controller: urlCtrl,
                      decoration: const InputDecoration(
                          labelText: 'URL', prefixIcon: Icon(Icons.link))),
                  const SizedBox(height: 16),
                  TextField(
                      controller: htmlCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Descripción',
                          prefixIcon: Icon(Icons.code))),
                  if (isEditing && _isAdmin) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    const Text('Asignar a usuarios',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: StatefulBuilder(
                        builder: (ctx, setListState) {
                          return FutureBuilder<List<Map<String, dynamic>>>(
                            future: _getUsers(),
                            builder: (usersCtx, userSnapshot) {
                              if (!userSnapshot.hasData) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              return FutureBuilder<List<String>>(
                                future: _getLinkUserIds(link['id']),
                                builder: (assignedCtx, assignedSnapshot) {
                                  final assignedIds = assignedSnapshot.hasData
                                      ? assignedSnapshot.data!.toSet()
                                      : <String>{};
                                  return ListView.builder(
                                    itemCount: userSnapshot.data!.length,
                                    itemBuilder: (listCtx, index) {
                                      final user = userSnapshot.data![index];
                                      final userId = user['id'].toString();
                                      final fullName =
                                          '${user['nombre']} ${user['paterno']} ${user['materno']}'
                                              .trim();
                                      final isAssigned =
                                          assignedIds.contains(userId);
                                      return SwitchListTile(
                                        dense: true,
                                        title: Text(fullName,
                                            style:
                                                const TextStyle(fontSize: 14)),
                                        value: isAssigned,
                                        onChanged: (value) async {
                                          if (value) {
                                            assignedIds.add(userId);
                                          } else {
                                            assignedIds.remove(userId);
                                          }
                                          setListState(() {});
                                          _toggleUserAccess(
                                              link['id'], userId, value);
                                        },
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteLink(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Enlace'),
        content: const Text('¿Estás seguro de eliminar este enlace?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _supabase.from('powerbi_links').delete().eq('id', id);
        _fetchData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enlace eliminado')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Center(
        child: Image.asset(
          'assets/sisol_loader.gif',
          width: 150,
          errorBuilder: (context, error, stackTrace) =>
              const CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 800) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child:
                      _isAdmin ? _buildAdminHeader(theme) : _buildUserHeader(theme),
                );
              },
            ),
          ),
          _isAdmin ? _buildAdminContent(theme) : _buildUserContent(theme),
        ],
      ),
    );
  }

  Widget _buildUserHeader(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildGlassPill(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                isDense: true,
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
              ),
              style: const TextStyle(fontSize: 14),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminHeader(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildGlassPill(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar...',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    isDense: true,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () => setState(() => _searchQuery = ''),
                          )
                        : null,
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const VerticalDivider(
                  width: 1, thickness: 1, indent: 8, endIndent: 8),
              IconButton(
                icon: const Icon(Icons.add, size: 22),
                onPressed: () => _showLinkForm(),
                tooltip: 'Nuevo Enlace',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGlassPill({required Widget child, EdgeInsetsGeometry? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildUserContent(ThemeData theme) {
    final filteredLinks = _searchQuery.isEmpty
        ? _userLinks
        : _userLinks.where((link) {
            final title = (link['title'] ?? '').toString().toLowerCase();
            return title.contains(_searchQuery.toLowerCase());
          }).toList();

    if (filteredLinks.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _searchQuery.isEmpty
                    ? Icons.bar_chart_outlined
                    : Icons.search_off,
                size: 64,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isEmpty
                    ? 'No tienes acceso a ningún reporte'
                    : 'No se encontraron resultados',
                style: TextStyle(color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    return SliverFillRemaining(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 800;
          return isDesktop
              ? _buildUserTableDesktop(filteredLinks)
              : _buildUserListMobile(filteredLinks, theme);
        },
      ),
    );
  }

  Widget _buildUserTableDesktop(List<Map<String, dynamic>> filteredLinks) {
    final screenWidth = MediaQuery.of(context).size.width;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey[200]!)),
        child: PaginatedDataTable(
          dataRowMaxHeight: 54,
          dataRowMinHeight: 54,
          columnSpacing: 20,
          horizontalMargin: 24,
          header: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: TextEditingController(text: _searchQuery)..selection = TextSelection.fromPosition(TextPosition(offset: _searchQuery.length)),
                decoration: InputDecoration(
                  hintText: 'Buscar reportes...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: theme.colorScheme.primary)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
          ),
          columns: [
            DataColumn(label: SizedBox(width: screenWidth * 0.3, child: Text('TÍTULO', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
            DataColumn(label: SizedBox(width: screenWidth * 0.4, child: Text('DESCRIPCIÓN', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
            const DataColumn(label: SizedBox()), // Acciones
          ],
          source: _LinksDataSource(
            links: filteredLinks,
            isAdmin: false,
            onEdit: (link) {},
            onDelete: (id) {},
            onTap: (link) => _openLink(link),
          ),
          rowsPerPage: filteredLinks.isEmpty ? 1 : (filteredLinks.length > 10 ? 10 : filteredLinks.length),
          showCheckboxColumn: false,
        ),
      ),
    );
  }

  Widget _buildUserListMobile(
      List<Map<String, dynamic>> filteredLinks, ThemeData theme) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: filteredLinks.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final link = filteredLinks[index];
        final descripcion = link['descripcion']?.toString() ?? '';

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
              backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
              child: Icon(
                Icons.assessment,
                color: theme.colorScheme.primary,
              ),
            ),
            title: Text(
              link['title'] ?? 'Sin título',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(descripcion.isEmpty ? '-' : descripcion),
            trailing: Icon(Icons.arrow_forward_ios,
                size: 16, color: Colors.grey[400]),
            onTap: () => _openLink(link),
          ),
        );
      },
    );
  }

  Widget _buildAdminContent(ThemeData theme) {
    final filteredLinks = _searchQuery.isEmpty
        ? _links
        : _links.where((link) {
            final title = (link['title'] ?? '').toString().toLowerCase();
            return title.contains(_searchQuery.toLowerCase());
          }).toList();

    if (filteredLinks.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _searchQuery.isEmpty ? Icons.link_off : Icons.search_off,
                size: 64,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isEmpty
                    ? 'No hay enlaces creados'
                    : 'No se encontraron resultados',
                style: TextStyle(color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    return SliverFillRemaining(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 800;
          return isDesktop
              ? _buildAdminTableDesktop(filteredLinks)
              : _buildAdminListMobile(filteredLinks, theme);
        },
      ),
    );
  }

  Widget _buildAdminTableDesktop(List<Map<String, dynamic>> filteredLinks) {
    final screenWidth = MediaQuery.of(context).size.width;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey[200]!)),
        child: PaginatedDataTable(
          dataRowMaxHeight: 54,
          dataRowMinHeight: 54,
          columnSpacing: 20,
          horizontalMargin: 24,
          header: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 350),
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: TextEditingController(text: _searchQuery)..selection = TextSelection.fromPosition(TextPosition(offset: _searchQuery.length)),
                decoration: InputDecoration(
                  hintText: 'Buscar reportes...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: theme.colorScheme.primary)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
          ),
          actions: [
            SizedBox(
              height: 38,
              child: ElevatedButton.icon(
                onPressed: () => _showLinkForm(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Enlace', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
          ],
          columns: [
            DataColumn(label: SizedBox(width: screenWidth * 0.3, child: Text('TÍTULO', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
            DataColumn(label: SizedBox(width: screenWidth * 0.4, child: Text('DESCRIPCIÓN', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1)))),
            const DataColumn(label: SizedBox()), // Acciones
          ],
          source: _LinksDataSource(
            links: filteredLinks,
            isAdmin: true,
            onEdit: (link) => _showLinkForm(link: link),
            onDelete: (id) => _deleteLink(id),
            onTap: (link) => _openLink(link),
          ),
          rowsPerPage: filteredLinks.isEmpty ? 1 : (filteredLinks.length > 10 ? 10 : filteredLinks.length),
          showCheckboxColumn: false,
        ),
      ),
    );
  }

  Widget _buildAdminListMobile(
      List<Map<String, dynamic>> filteredLinks, ThemeData theme) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: filteredLinks.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final link = filteredLinks[index];
        final descripcion = link['descripcion']?.toString() ?? '';

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
              backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
              child: Icon(
                Icons.assessment,
                color: theme.colorScheme.primary,
              ),
            ),
            title: Text(
              link['title'] ?? 'Sin título',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(descripcion.isEmpty ? '-' : descripcion),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'edit') {
                  _showLinkForm(link: link);
                } else if (value == 'delete') {
                  _deleteLink(link['id']);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20),
                      SizedBox(width: 12),
                      Text('Editar'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      SizedBox(width: 12),
                      Text('Eliminar', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
            onTap: () => _openLink(link),
          ),
        );
      },
    );
  }
}

class _LinkViewer extends StatefulWidget {
  final String url;
  final String title;
  final VoidCallback? onClose;
  final bool showErrorHandling;

  const _LinkViewer({
    required this.url,
    required this.title,
    this.onClose,
    this.showErrorHandling = false,
  });

  @override
  State<_LinkViewer> createState() => _LinkViewerState();
}

class _LinkViewerState extends State<_LinkViewer> {
  bool _hasError = false;

  void _handleClose() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.pop(context);
    }
  }

  void _retry() {
    setState(() => _hasError = false);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final topPadding = MediaQuery.of(context).padding.top;
    final isFullScreen = screenHeight > 600;
    const headerHeight = 56.0;
    final availableHeight = screenHeight - topPadding - bottomPadding;
    final double modalHeight =
        isFullScreen ? availableHeight : availableHeight * 0.9;
    final double webViewHeight = modalHeight - headerHeight;

    return Container(
      height: modalHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: isFullScreen
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: headerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: isFullScreen
                  ? BorderRadius.zero
                  : const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _handleClose,
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          Expanded(
            child: widget.showErrorHandling && _hasError
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error al cargar',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  )
                : kIsWeb
                    ? iframe_impl.WebIframeWidget(
                        url: widget.url,
                        height: webViewHeight > 0 ? webViewHeight : 400.0,
                        width: MediaQuery.of(context).size.width,
                      )
                    : WebViewX(
                        key: ValueKey(_hasError),
                        initialContent: widget.url,
                        initialSourceType: SourceType.urlBypass,
                        height: webViewHeight > 0 ? webViewHeight : 400.0,
                        width: MediaQuery.of(context).size.width,
                        javascriptMode: JavascriptMode.unrestricted,
                        onWebResourceError: widget.showErrorHandling
                            ? (error) => setState(() => _hasError = true)
                            : null,
                      ),
          ),
        ],
      ),
    );
  }
}

class _LinksDataSource extends DataTableSource {
  final List<Map<String, dynamic>> links;
  final bool isAdmin;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(String) onDelete;
  final void Function(Map<String, dynamic>) onTap;

  _LinksDataSource({
    required this.links,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= links.length) return null;
    final link = links[index];
    final descripcion = link['descripcion']?.toString() ?? '-';
    final truncateDesc = descripcion.length > 50
        ? '${descripcion.substring(0, 50)}...'
        : descripcion;

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(
          Text(
            (link['title'] ?? 'Sin título').toString().toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          onTap: () => onTap(link),
        ),
        DataCell(
          Tooltip(
            message: descripcion,
            child: Text(
              truncateDesc,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
        ),
        DataCell(
          Align(
            alignment: Alignment.centerRight,
            child: isAdmin
                ? PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, color: Colors.grey),
                    tooltip: 'Acciones',
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                    onSelected: (value) {
                      if (value == 'edit') onEdit(link);
                      if (value == 'delete') onDelete(link['id']);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                              leading: Icon(Icons.edit_outlined, color: Colors.blue),
                              title: Text('Editar'),
                              dense: true)),
                      const PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                              leading: Icon(Icons.delete_outline, color: Colors.red),
                              title: Text('Eliminar', style: TextStyle(color: Colors.red)),
                              dense: true)),
                    ],
                  )
                : IconButton(
                    icon: const Icon(Icons.open_in_new, size: 18, color: Colors.blue),
                    onPressed: () => onTap(link),
                    tooltip: 'Abrir Reporte',
                  ),
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => links.length;

  @override
  int get selectedRowCount => 0;
}
