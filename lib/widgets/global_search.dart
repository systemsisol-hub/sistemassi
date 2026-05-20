import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/si_theme.dart';

// ── Public API ────────────────────────────────────────────────────────────────

Future<void> showGlobalSearch({
  required BuildContext context,
  required String role,
  required Map<String, dynamic> permissions,
  required List<Map<String, dynamic>> pages,
  required ValueChanged<int> onSelectPage,
}) {
  if (role != 'admin') return Future.value();

  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar búsqueda',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: SiMotion.normal,
    transitionBuilder: (ctx, anim, _, child) {
      final curved =
          CurvedAnimation(parent: anim, curve: SiMotion.easeOut);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (ctx, _, __) => _GlobalSearchDialog(
      permissions: permissions,
      pages: pages,
      onSelectPage: (i) {
        Navigator.of(ctx).pop();
        onSelectPage(i);
      },
    ),
  );
}

// ── Data model ────────────────────────────────────────────────────────────────

class _Result {
  final String category;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _Result({
    required this.category,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
}

// ── Dialog widget ─────────────────────────────────────────────────────────────

class _GlobalSearchDialog extends StatefulWidget {
  final Map<String, dynamic> permissions;
  final List<Map<String, dynamic>> pages;
  final ValueChanged<int> onSelectPage;

  const _GlobalSearchDialog({
    required this.permissions,
    required this.pages,
    required this.onSelectPage,
  });

  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;
  final ScrollController _scrollCtrl = ScrollController();

  List<_Result> _results = [];
  bool _loading = false;
  int _selectedIdx = -1;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    _ctrl = TextEditingController()..addListener(_onQueryChanged);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Keyboard ──────────────────────────────────────────────────────────────

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _activateSelected();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _moveSelection(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selectedIdx =
          (_selectedIdx + delta).clamp(0, _results.length - 1);
    });
    _scrollToSelected();
  }

  void _activateSelected() {
    if (_selectedIdx >= 0 && _selectedIdx < _results.length) {
      _results[_selectedIdx].onTap();
    }
  }

  void _scrollToSelected() {
    if (!_scrollCtrl.hasClients) return;
    const rowH = 52.0;
    final target = (_selectedIdx * rowH)
        .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.animateTo(target,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut);
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  void _onQueryChanged() {
    _debounce?.cancel();
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _selectedIdx = -1;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _selectedIdx = -1;
    });
    _debounce =
        Timer(const Duration(milliseconds: 280), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final lower = q.toLowerCase();
    final futures = <Future<List<_Result>>>[
      Future.value(_searchPages(lower)),
      _searchColaboradores(lower),
      if (widget.permissions['show_issi'] == true)
        _searchInventario(lower),
      if (widget.permissions['show_external_contacts'] == true)
        _searchContactos(lower),
    ];
    final groups = await Future.wait(futures);
    if (!mounted) return;
    setState(() {
      _results = groups.expand((g) => g).toList();
      _loading = false;
    });
  }

  // ── Search sources ────────────────────────────────────────────────────────

  List<_Result> _searchPages(String q) {
    return [
      for (var i = 0; i < widget.pages.length; i++)
        if ((widget.pages[i]['title'] as String)
            .toLowerCase()
            .contains(q))
          _Result(
            category: 'Páginas',
            icon: widget.pages[i]['icon'] as IconData,
            title: widget.pages[i]['title'] as String,
            subtitle: 'Ir a esta sección',
            onTap: () => widget.onSelectPage(i),
          ),
    ];
  }

  Future<List<_Result>> _searchColaboradores(String q) async {
    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('nombre, paterno, numero_empleado, puesto')
          .or('nombre.ilike.%$q%,paterno.ilike.%$q%'
              ',numero_empleado.ilike.%$q%,puesto.ilike.%$q%')
          .limit(5);
      return (rows as List).map((r) {
        final nombre =
            '${r['nombre'] ?? ''} ${r['paterno'] ?? ''}'.trim();
        final parts = <String>[
          if (r['numero_empleado'] != null)
            'No. ${r['numero_empleado']}',
          if (r['puesto'] != null) r['puesto'] as String,
        ];
        return _Result(
          category: 'Colaboradores',
          icon: Icons.person_outline,
          title: nombre.isEmpty ? '---' : nombre,
          subtitle: parts.isEmpty ? null : parts.join(' · '),
          onTap: () => widget.onSelectPage(
              widget.pages.indexWhere((p) => p['title'] == 'Usuarios')),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<_Result>> _searchInventario(String q) async {
    try {
      final rows = await Supabase.instance.client
          .from('issi_inventory')
          .select('marca, modelo, n_s, tipo')
          .or('marca.ilike.%$q%,modelo.ilike.%$q%'
              ',n_s.ilike.%$q%,tipo.ilike.%$q%')
          .limit(5);
      return (rows as List).map((r) {
        final title =
            '${r['marca'] ?? ''} ${r['modelo'] ?? ''}'.trim();
        final parts = <String>[
          if (r['tipo'] != null) r['tipo'] as String,
          if (r['n_s'] != null) 'S/N: ${r['n_s']}',
        ];
        return _Result(
          category: 'Inventario',
          icon: Icons.inventory_2_outlined,
          title: title.isEmpty ? '---' : title,
          subtitle: parts.isEmpty ? null : parts.join(' · '),
          onTap: () => widget.onSelectPage(widget.pages
              .indexWhere((p) => p['title'] == 'Inventario')),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<_Result>> _searchIncidencias(String q) async {
    try {
      final rows = await Supabase.instance.client
          .from('incidencias')
          .select('nombre_usuario, status, periodo')
          .or('nombre_usuario.ilike.%$q%'
              ',periodo.ilike.%$q%,status.ilike.%$q%')
          .limit(5);
      return (rows as List).map((r) {
        final parts = <String>[
          if (r['status'] != null) r['status'] as String,
          if (r['periodo'] != null) r['periodo'] as String,
        ];
        return _Result(
          category: 'Incidencias',
          icon: Icons.description_outlined,
          title: r['nombre_usuario'] ?? '---',
          subtitle: parts.isEmpty ? null : parts.join(' · '),
          onTap: () => widget.onSelectPage(widget.pages
              .indexWhere((p) => p['title'] == 'Incidencias')),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<_Result>> _searchContactos(String q) async {
    try {
      final rows = await Supabase.instance.client
          .from('external_contacts')
          .select('nombre, empresa, correo')
          .or('nombre.ilike.%$q%,empresa.ilike.%$q%,correo.ilike.%$q%')
          .limit(5);
      return (rows as List).map((r) {
        final parts = <String>[
          if (r['empresa'] != null) r['empresa'] as String,
          if (r['correo'] != null) r['correo'] as String,
        ];
        return _Result(
          category: 'Contactos',
          icon: Icons.contact_phone_outlined,
          title: r['nombre'] ?? '---',
          subtitle: parts.isEmpty ? null : parts.join(' · '),
          onTap: () => widget.onSelectPage(widget.pages
              .indexWhere((p) => p['title'] == 'Contactos')),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    // Group results by category (insertion order)
    final grouped = <String, List<_Result>>{};
    for (final r in _results) {
      grouped.putIfAbsent(r.category, () => []).add(r);
    }

    final hasQuery = _ctrl.text.trim().isNotEmpty;
    final hasResults = _results.isNotEmpty;
    final showEmpty = hasQuery && !_loading && !hasResults;
    final showFooter = hasQuery && (hasResults || showEmpty);

    return Align(
      alignment: const Alignment(0, -0.28),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 560,
          constraints: const BoxConstraints(maxHeight: 540),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: SiRadius.rXl,
            border: Border.all(color: c.line),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              // ── Input row ────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: SiSpace.x4, vertical: SiSpace.x3),
                child: Row(
                  children: [
                    AnimatedSwitcher(
                      duration: SiMotion.fast,
                      child: _loading
                          ? SizedBox(
                              key: const ValueKey('spin'),
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: c.brand,
                              ),
                            )
                          : Icon(
                              key: const ValueKey('icon'),
                              Icons.search,
                              size: 17,
                              color: c.ink3,
                            ),
                    ),
                    const SizedBox(width: SiSpace.x3),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focusNode,
                        style: TextStyle(
                          fontSize: 15,
                          color: c.ink,
                          fontFamily: SiType.fontFamily,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Buscar colaborador, activo, incidencia...',
                          hintStyle:
                              TextStyle(fontSize: 15, color: c.ink4),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.hover,
                        border: Border.all(color: c.line),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Esc',
                          style: SiType.mono(size: 10, color: c.ink3)),
                    ),
                  ],
                ),
              ),

              // ── Results ──────────────────────────────────────
              if (hasQuery) ...[
                Divider(color: c.line, height: 1),
                if (showEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: SiSpace.x8, horizontal: SiSpace.x4),
                    child: Text(
                      'Sin resultados para "${_ctrl.text.trim()}"',
                      style: TextStyle(fontSize: 13, color: c.ink3),
                    ),
                  )
                else if (hasResults)
                  Flexible(
                    child: ListView(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          vertical: SiSpace.x2),
                      shrinkWrap: true,
                      children: [
                        for (final entry in grouped.entries) ...[
                          _SectionLabel(label: entry.key, c: c),
                          for (final r in entry.value)
                            _ResultTile(
                              result: r,
                              isSelected:
                                  _results.indexOf(r) == _selectedIdx,
                              c: c,
                            ),
                        ],
                      ],
                    ),
                  ),
              ],

              // ── Footer ───────────────────────────────────────
              if (showFooter) ...[
                Divider(color: c.line, height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SiSpace.x4, vertical: SiSpace.x2),
                  child: Row(
                    children: [
                      _ShortcutHint(label: '↑↓', hint: 'Navegar', c: c),
                      const SizedBox(width: SiSpace.x4),
                      _ShortcutHint(
                          label: '↵', hint: 'Seleccionar', c: c),
                      const SizedBox(width: SiSpace.x4),
                      _ShortcutHint(label: 'Esc', hint: 'Cerrar', c: c),
                    ],
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

// ── Section label ─────────────────────────────────────────────────────────────

const _categoryIcons = <String, IconData>{
  'Páginas': Icons.grid_view_outlined,
  'Colaboradores': Icons.group_outlined,
  'Inventario': Icons.inventory_2_outlined,
  'Incidencias': Icons.description_outlined,
  'Contactos': Icons.contact_phone_outlined,
};

class _SectionLabel extends StatelessWidget {
  final String label;
  final SiColors c;
  const _SectionLabel({required this.label, required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          SiSpace.x4, SiSpace.x3, SiSpace.x4, SiSpace.x1),
      child: Row(
        children: [
          Icon(_categoryIcons[label] ?? Icons.folder_outlined,
              size: 11, color: c.ink3),
          const SizedBox(width: SiSpace.x1),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: SiType.fontFamily,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: c.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Result tile ───────────────────────────────────────────────────────────────

class _ResultTile extends StatefulWidget {
  final _Result result;
  final bool isSelected;
  final SiColors c;
  const _ResultTile(
      {required this.result, required this.isSelected, required this.c});

  @override
  State<_ResultTile> createState() => _ResultTileState();
}

class _ResultTileState extends State<_ResultTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlight = widget.isSelected || _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.result.onTap,
        child: AnimatedContainer(
          duration: SiMotion.fast,
          margin: const EdgeInsets.symmetric(
              horizontal: SiSpace.x2, vertical: 1),
          padding: const EdgeInsets.symmetric(
              horizontal: SiSpace.x3, vertical: SiSpace.x2),
          decoration: BoxDecoration(
            color: highlight ? widget.c.hover : Colors.transparent,
            borderRadius: SiRadius.rMd,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: widget.c.brandTint,
                  borderRadius: SiRadius.rSm,
                ),
                alignment: Alignment.center,
                child: Icon(widget.result.icon,
                    size: 15, color: widget.c.brand),
              ),
              const SizedBox(width: SiSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.result.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: widget.c.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.result.subtitle != null)
                      Text(
                        widget.result.subtitle!,
                        style:
                            TextStyle(fontSize: 11, color: widget.c.ink3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (widget.isSelected)
                Icon(Icons.keyboard_return,
                    size: 13, color: widget.c.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shortcut hint ─────────────────────────────────────────────────────────────

class _ShortcutHint extends StatelessWidget {
  final String label;
  final String hint;
  final SiColors c;
  const _ShortcutHint(
      {required this.label, required this.hint, required this.c});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: c.hover,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label, style: SiType.mono(size: 10, color: c.ink3)),
        ),
        const SizedBox(width: 4),
        Text(hint, style: TextStyle(fontSize: 11, color: c.ink3)),
      ],
    );
  }
}
