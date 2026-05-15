import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

class TablasPage extends StatefulWidget {
  const TablasPage({super.key});

  @override
  State<TablasPage> createState() => _TablasPageState();
}

class _TablasPageState extends State<TablasPage> {
  List<Map<String, dynamic>> _all = [];
  bool _isLoading = true;
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(
          child: Image.asset('assets/sisol_loader.gif',
              width: 80,
              errorBuilder: (_, __, ___) =>
                  const CircularProgressIndicator()),
        ),
      );
    }

    final filtered = _filtered;

    return Scaffold(
      backgroundColor: c.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 700;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(c, filtered.length),
              Expanded(
                child: isDesktop
                    ? _buildDesktopTable(c, filtered)
                    : _buildMobileList(c, filtered),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(SiColors c, int count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Icon(Icons.mail_outline, size: 18, color: c.brand),
          const SizedBox(width: 10),
          Text('Mails Activos',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: c.ink)),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: c.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: c.brand)),
          ),
          const Spacer(),
          // Search
          SizedBox(
            width: 260,
            height: 34,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar nombre, correo...',
                hintStyle: TextStyle(color: c.ink3, fontSize: 13),
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
                filled: true,
                fillColor: c.hover,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.line)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.line)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.brand)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                isDense: true,
              ),
              style: TextStyle(fontSize: 13, color: c.ink),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.refresh, color: c.ink3, size: 18),
            tooltip: 'Actualizar',
            onPressed: _fetchData,
          ),
        ],
      ),
    );
  }

  // ── Desktop table ──────────────────────────────────────────────────────────

  Widget _buildDesktopTable(SiColors c, List<Map<String, dynamic>> filtered) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Column headers
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: c.hover,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12)),
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text('ID',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: c.ink3,
                            letterSpacing: 0.8)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text('NOMBRE',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: c.ink3,
                            letterSpacing: 0.8)),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text('CORREO',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: c.ink3,
                            letterSpacing: 0.8)),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            // Empty state
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    Icon(Icons.mail_outline, size: 48, color: c.line2),
                    const SizedBox(height: 12),
                    Text('Sin resultados',
                        style: TextStyle(color: c.ink3, fontSize: 13)),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: c.line),
                itemBuilder: (ctx, i) {
                  final r = filtered[i];
                  final nombre =
                      '${r['nombre'] ?? ''} ${r['paterno'] ?? ''} ${r['materno'] ?? ''}'
                          .trim();
                  final mail = r['mail_user'] as String? ?? '';
                  final numEmp =
                      r['numero_empleado']?.toString() ?? '—';
                  return _DesktopRow(
                    c: c,
                    numEmp: numEmp,
                    nombre: nombre,
                    mail: mail,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── Mobile list ────────────────────────────────────────────────────────────

  Widget _buildMobileList(SiColors c, List<Map<String, dynamic>> filtered) {
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mail_outline, size: 48, color: c.line2),
            const SizedBox(height: 12),
            Text('Sin resultados',
                style: TextStyle(color: c.ink3, fontSize: 13)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final r = filtered[i];
        final nombre =
            '${r['nombre'] ?? ''} ${r['paterno'] ?? ''} ${r['materno'] ?? ''}'
                .trim();
        final mail = r['mail_user'] as String? ?? '';

        return Container(
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.line),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: c.brand.withValues(alpha: 0.12),
              child: Text(
                nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                style: TextStyle(
                    color: c.brand,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ),
            title: Text(nombre.isEmpty ? '—' : nombre,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: c.ink)),
            subtitle: Text(mail,
                style: TextStyle(fontSize: 12, color: c.ink3)),
            trailing: IconButton(
              icon: Icon(Icons.copy, size: 16, color: c.ink3),
              tooltip: 'Copiar correo',
              onPressed: () => _copyMail(mail),
            ),
          ),
        );
      },
    );
  }

  void _copyMail(String mail) {
    Clipboard.setData(ClipboardData(text: mail));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Correo copiado'),
        backgroundColor: Color(0xFFB1CB34),
        duration: Duration(seconds: 1)));
  }
}

// ── Desktop row with hover ────────────────────────────────────────────────────

class _DesktopRow extends StatefulWidget {
  final SiColors c;
  final String numEmp;
  final String nombre;
  final String mail;

  const _DesktopRow({
    required this.c,
    required this.numEmp,
    required this.nombre,
    required this.mail,
  });

  @override
  State<_DesktopRow> createState() => _DesktopRowState();
}

class _DesktopRowState extends State<_DesktopRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        color: _hovered ? c.hover : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                widget.numEmp,
                style: TextStyle(fontSize: 13, color: c.ink3),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                widget.nombre.isEmpty ? '—' : widget.nombre,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: c.ink),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                widget.mail,
                style: TextStyle(fontSize: 13, color: c.ink2),
              ),
            ),
            SizedBox(
              width: 36,
              child: _hovered
                  ? IconButton(
                      icon: Icon(Icons.copy, size: 15, color: c.ink3),
                      tooltip: 'Copiar correo',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: widget.mail));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Correo copiado'),
                              backgroundColor: Color(0xFFB1CB34),
                              duration: Duration(seconds: 1)),
                        );
                      },
                    )
                  : const SizedBox(),
            ),
          ],
        ),
      ),
    );
  }
}
