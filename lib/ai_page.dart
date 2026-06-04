import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

class AiPage extends StatefulWidget {
  const AiPage({super.key});

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMsg> _messages = [];
  bool _isLoading = false;

  static const _fnUrl =
      'https://zkmbebybyyefmqcxjqrg.supabase.co/functions/v1/ai-assistant';

  static const _quickActions = [
    (Icons.people_outline,      'Empleados activos',         'Muéstrame los colaboradores con status ACTIVO'),
    (Icons.search,              'Buscar colaborador',        'Quiero buscar a un colaborador específico'),
    (Icons.event_note_outlined, 'Nueva incidencia',          'Quiero crear una solicitud de vacaciones'),
    (Icons.person_add_outlined, 'Nuevo colaborador',         'Quiero dar de alta a un nuevo colaborador'),
    (Icons.bar_chart_outlined,  'Resumen por área',          '¿Cuántos colaboradores hay por área?'),
    (Icons.location_on_outlined,'Por ubicación',             'Muéstrame colaboradores por ubicación'),
  ];

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
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;
    _inputCtrl.clear();

    setState(() {
      _messages.add(_ChatMsg(role: 'user', text: trimmed));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Sin sesión activa');

      // Build history (only text messages)
      final history = _messages
          .where((m) => m.text.isNotEmpty)
          .map((m) => {'role': m.role, 'content': m.text})
          .toList();

      final resp = await http.post(
        Uri.parse(_fnUrl),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'messages': history}),
      ).timeout(const Duration(seconds: 60));

      if (!mounted) return;

      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode != 200) {
        throw Exception(body['error']?.toString() ?? 'Error ${resp.statusCode}');
      }

      setState(() {
        _isLoading = false;
        _messages.add(_ChatMsg(
          role: 'assistant',
          text: body['text'] as String? ?? '',
          structured: body['structured'] as Map<String, dynamic>?,
        ));
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _messages.add(_ChatMsg(
          role: 'assistant',
          text: 'Error: $e',
          isError: true,
        ));
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final isEmpty = _messages.isEmpty;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          Expanded(
            child: isEmpty
                ? _buildWelcome(c)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _messages.length) return _TypingBubble(c: c);
                      return _buildBubble(_messages[i], c);
                    },
                  ),
          ),
          if (isEmpty) _buildQuickActions(c),
          _buildInputBar(c),
        ],
      ),
    );
  }

  // ── Welcome screen ───────────────────────────────────────────────────────────

  Widget _buildWelcome(SiColors c) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [c.brand, c.brand.withOpacity(0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy_outlined, size: 36, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text(
            'Asistente de RRHH',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c.ink),
          ),
          const SizedBox(height: 8),
          Text(
            'Consulta colaboradores, gestiona incidencias\ny administra el equipo con lenguaje natural.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: c.ink3, height: 1.6),
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  // ── Quick action chips ───────────────────────────────────────────────────────

  Widget _buildQuickActions(SiColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _quickActions.map((a) {
          return ActionChip(
            avatar: Icon(a.$1, size: 15, color: c.brand),
            label: Text(a.$2, style: TextStyle(fontSize: 13, color: c.brand)),
            backgroundColor: c.brandTint,
            side: BorderSide(color: c.brand.withOpacity(0.25)),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            onPressed: () => _send(a.$3),
          );
        }).toList(),
      ),
    );
  }

  // ── Input bar ────────────────────────────────────────────────────────────────

  Widget _buildInputBar(SiColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: EdgeInsets.fromLTRB(
        16, 12, 16,
        MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: c.line),
              ),
              child: TextField(
                controller: _inputCtrl,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Escribe un mensaje...',
                  hintStyle: TextStyle(color: c.ink4, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  isDense: true,
                ),
                style: TextStyle(fontSize: 14, color: c.ink),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isLoading ? null : () => _send(_inputCtrl.text),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _isLoading ? c.brand.withOpacity(0.4) : c.brand,
                shape: BoxShape.circle,
              ),
              child: _isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.arrow_upward_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ── Message bubble ───────────────────────────────────────────────────────────

  Widget _buildBubble(_ChatMsg msg, SiColors c) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 5),
              child: Row(children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [c.brand, c.brand.withOpacity(0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.smart_toy_outlined,
                      size: 14, color: Colors.white),
                ),
                const SizedBox(width: 6),
                Text('Asistente IA',
                    style: TextStyle(
                        fontSize: 11,
                        color: c.ink3,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          if (msg.text.isNotEmpty)
            Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? c.brand
                    : (msg.isError ? c.dangerTint : c.panel),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                border: isUser ? null : Border.all(color: c.line),
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  fontSize: 14,
                  color: isUser
                      ? Colors.white
                      : (msg.isError ? c.danger : c.ink),
                  height: 1.5,
                ),
              ),
            ),
          if (!isUser && msg.structured != null)
            _buildStructured(msg.structured!, c),
        ],
      ),
    );
  }

  // ── Structured result cards ───────────────────────────────────────────────────

  Widget _buildStructured(Map<String, dynamic> s, SiColors c) {
    final type = s['type'] as String?;

    if (type == 'collaborators') {
      final list =
          (s['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (list.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: list
              .take(15)
              .map((item) => _CollaboratorCard(item: item, c: c))
              .toList(),
        ),
      );
    }

    if (type == 'success') {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.successTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.success.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: c.success),
              const SizedBox(width: 8),
              Text('Operación completada correctamente',
                  style: TextStyle(
                      fontSize: 13,
                      color: c.success,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _ChatMsg {
  final String role;
  final String text;
  final Map<String, dynamic>? structured;
  final bool isError;

  const _ChatMsg({
    required this.role,
    required this.text,
    this.structured,
    this.isError = false,
  });
}

// ── Typing indicator ──────────────────────────────────────────────────────────

class _TypingBubble extends StatefulWidget {
  final SiColors c;
  const _TypingBubble({required this.c});

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [c.brand, c.brand.withOpacity(0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy_outlined,
                size: 14, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: c.line),
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final t = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
                  final opacity =
                      (0.25 + 0.75 * (t < 0.5 ? t * 2 : (1 - t) * 2))
                          .clamp(0.25, 1.0);
                  return Container(
                    width: 7,
                    height: 7,
                    margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
                    decoration: BoxDecoration(
                      color: c.brand.withOpacity(opacity),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Collaborator card ─────────────────────────────────────────────────────────

class _CollaboratorCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final SiColors c;

  const _CollaboratorCard({required this.item, required this.c});

  @override
  Widget build(BuildContext context) {
    final name =
        '${item['nombre'] ?? ''} ${item['paterno'] ?? ''} ${item['materno'] ?? ''}'
            .trim();
    final initials = name
        .split(' ')
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e[0])
        .join()
        .toUpperCase();
    final statusRh = (item['status_rh'] ?? 'ACTIVO') as String;
    final Color statusColor;
    switch (statusRh) {
      case 'ACTIVO':
        statusColor = c.success;
        break;
      case 'BAJA':
        statusColor = c.danger;
        break;
      default:
        statusColor = c.warn;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: c.brandTint,
            backgroundImage: (item['foto_url'] as String?)?.isNotEmpty == true
                ? NetworkImage(item['foto_url'])
                : null,
            child: (item['foto_url'] as String?)?.isNotEmpty != true
                ? Text(initials,
                    style: TextStyle(
                        color: c.brand,
                        fontWeight: FontWeight.bold,
                        fontSize: 13))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      name.isEmpty ? 'Sin nombre' : name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.ink),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: statusColor.withOpacity(0.4)),
                    ),
                    child: Text(statusRh,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: statusColor)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(
                  [
                    if (item['numero_empleado'] != null)
                      '#${item['numero_empleado']}',
                    if (item['puesto'] != null) item['puesto'],
                  ].join(' · '),
                  style: TextStyle(fontSize: 11, color: c.ink3),
                  overflow: TextOverflow.ellipsis,
                ),
                if (item['area'] != null || item['ubicacion'] != null)
                  Text(
                    [item['area'], item['ubicacion']]
                        .where((e) => e != null)
                        .join(' — '),
                    style: TextStyle(fontSize: 11, color: c.ink4),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
