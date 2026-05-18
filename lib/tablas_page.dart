import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

class TablasPage extends StatelessWidget {
  const TablasPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 700;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _MailsActivosTable()),
                      const SizedBox(width: 16),
                      Expanded(child: _EmptyTablePlaceholder(c: c)),
                      const SizedBox(width: 16),
                      Expanded(child: _EmptyTablePlaceholder(c: c)),
                    ],
                  )
                : _MailsActivosTable(),
          );
        },
      ),
    );
  }
}

// ── Placeholder for future tables ─────────────────────────────────────────────

class _EmptyTablePlaceholder extends StatelessWidget {
  final SiColors c;
  const _EmptyTablePlaceholder({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_chart_outlined, size: 32, color: c.line2),
            const SizedBox(height: 8),
            Text('Próximamente',
                style: TextStyle(fontSize: 13, color: c.ink4)),
          ],
        ),
      ),
    );
  }
}

// ── Mails Activos table ───────────────────────────────────────────────────────

class _MailsActivosTable extends StatefulWidget {
  @override
  State<_MailsActivosTable> createState() => _MailsActivosTableState();
}

class _MailsActivosTableState extends State<_MailsActivosTable> {
  static const _pageSize = 10;

  List<Map<String, dynamic>> _all = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  int _page = 0;

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
      final data = await Supabase.instance.client
          .from('profiles')
          .select('nombre, paterno, materno, mail_user, numero_empleado')
          .eq('status_rh', 'ACTIVO')
          .not('mail_user', 'is', null)
          .order('numero_empleado', ascending: true, nullsFirst: false);

      if (mounted) {
        setState(() {
          _all = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error TablasPage: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _all;
    final q = _searchQuery.toLowerCase();
    return _all.where((r) {
      final name =
          '${r['nombre'] ?? ''} ${r['paterno'] ?? ''} ${r['materno'] ?? ''}'
              .toLowerCase();
      final mail = (r['mail_user'] ?? '').toString().toLowerCase();
      final num = (r['numero_empleado'] ?? '').toString().toLowerCase();
      return name.contains(q) || mail.contains(q) || num.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final filtered = _filtered;
    final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 9999);
    final page = _page.clamp(0, totalPages - 1);
    final pageItems =
        filtered.skip(page * _pageSize).take(_pageSize).toList();

    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Card header ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: c.panel,
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(
                  children: [
                    Icon(Icons.mail_outline, size: 15, color: c.brand),
                    const SizedBox(width: 7),
                    Text('Mails Activos',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: c.ink)),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.brand.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${filtered.length}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: c.brand)),
                    ),
                    const Spacer(),
                    if (_isLoading)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: c.brand),
                      )
                    else
                      GestureDetector(
                        onTap: _fetchData,
                        child: Icon(Icons.refresh, size: 15, color: c.ink3),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                // Search
                SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar...',
                      hintStyle: TextStyle(color: c.ink4, fontSize: 12),
                      prefixIcon:
                          Icon(Icons.search, size: 14, color: c.ink3),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 32, minHeight: 30),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _page = 0;
                                });
                              },
                              child:
                                  Icon(Icons.clear, size: 13, color: c.ink3),
                            )
                          : null,
                      suffixIconConstraints:
                          const BoxConstraints(minWidth: 28, minHeight: 30),
                      filled: true,
                      fillColor: c.hover,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide:
                              BorderSide(color: c.brand, width: 1.5)),
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    style: TextStyle(fontSize: 12, color: c.ink),
                    onChanged: (v) => setState(() {
                      _searchQuery = v;
                      _page = 0;
                    }),
                  ),
                ),
              ],
            ),
          ),

          // ── Column headers ───────────────────────────────────────────────
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.hover,
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text('ID',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: c.ink3,
                          letterSpacing: 0.6)),
                ),
                Expanded(
                  child: Text('NOMBRE',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: c.ink3,
                          letterSpacing: 0.6)),
                ),
                Expanded(
                  child: Text('CORREO',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: c.ink3,
                          letterSpacing: 0.6)),
                ),
              ],
            ),
          ),

          // ── Rows ─────────────────────────────────────────────────────────
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (pageItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.mail_outline, size: 36, color: c.line2),
                  const SizedBox(height: 8),
                  Text('Sin resultados',
                      style: TextStyle(fontSize: 12, color: c.ink3)),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pageItems.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: c.line),
              itemBuilder: (ctx, i) {
                final r = pageItems[i];
                final nombre =
                    '${r['nombre'] ?? ''} ${r['paterno'] ?? ''} ${r['materno'] ?? ''}'
                        .trim();
                final mail = r['mail_user'] as String? ?? '';
                final numEmp =
                    r['numero_empleado']?.toString() ?? '—';

                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(numEmp,
                            style:
                                TextStyle(fontSize: 12, color: c.ink3)),
                      ),
                      Expanded(
                        child: Text(
                          nombre.isEmpty ? '—' : nombre,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: c.ink),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          mail,
                          style: TextStyle(fontSize: 12, color: c.ink2),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // ── Pagination ───────────────────────────────────────────────────
          if (!_isLoading && filtered.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: Icon(Icons.chevron_left,
                        size: 18,
                        color: page > 0 ? c.ink2 : c.line),
                    onPressed: page > 0
                        ? () => setState(() => _page = page - 1)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${page + 1} / $totalPages',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: c.ink3),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: Icon(Icons.chevron_right,
                        size: 18,
                        color: page < totalPages - 1 ? c.ink2 : c.line),
                    onPressed: page < totalPages - 1
                        ? () => setState(() => _page = page + 1)
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
