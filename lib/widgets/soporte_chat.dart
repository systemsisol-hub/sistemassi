import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/si_theme.dart';

const _kWebhookUrl =
    'https://n8n.sisol.red/webhook/sisol-soporte-chat/chat';

class _Msg {
  final String text;
  final bool fromUser;
  _Msg(this.text, {required this.fromUser});
}

class SoporteChat extends StatefulWidget {
  const SoporteChat({super.key});

  @override
  State<SoporteChat> createState() => _SoporteChatState();
}

class _SoporteChatState extends State<SoporteChat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  final _messages = <_Msg>[
    _Msg(
      '¡Hola! Soy el asistente de soporte técnico de SISOL. ¿En qué puedo ayudarte?',
      fromUser: false,
    ),
  ];
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  final _sessionId = _genId();

  bool _open     = false;
  bool _sending  = false;
  bool _typing   = false;

  static String _genId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random();
    return List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 240));
    _fade  = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(
            begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _anim.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) _anim.forward();
    else _anim.reverse();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();
    setState(() {
      _messages.add(_Msg(text, fromUser: true));
      _sending = true;
      _typing  = true;
    });
    _scrollDown();

    try {
      final res = await http
          .post(
            Uri.parse(_kWebhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'action'   : 'sendMessage',
              'sessionId': _sessionId,
              'chatInput': text,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;

      String reply =
          'No pude obtener respuesta. Por favor intenta de nuevo.';
      if (res.statusCode == 200) {
        try {
          final d = jsonDecode(res.body);
          if (d is Map) {
            reply = d['output']?.toString() ??
                    d['text']?.toString()   ??
                    d['message']?.toString() ?? reply;
          } else if (d is List && d.isNotEmpty) {
            final f = d.first;
            reply = f['output']?.toString() ??
                    f['text']?.toString()   ?? reply;
          }
        } catch (_) {
          if (res.body.isNotEmpty) reply = res.body;
        }
      }

      setState(() {
        _messages.add(_Msg(reply, fromUser: false));
        _sending = false;
        _typing  = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(_Msg(
          'Error de conexión. Verifica tu internet e intenta de nuevo.',
          fromUser: false,
        ));
        _sending = false;
        _typing  = false;
      });
    }
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c      = SiColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size   = MediaQuery.of(context).size;
    final isWide = size.width >= 720;

    return Stack(
      children: [
        // ── Chat panel ──────────────────────────────────────────────────────
        if (_open || _anim.status != AnimationStatus.dismissed)
          Positioned(
            bottom: isWide ? 88 : 82,
            right:  isWide ? 24 : 12,
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: _Panel(
                  c:       c,
                  isDark:  isDark,
                  isWide:  isWide,
                  size:    size,
                  messages: _messages,
                  scroll:  _scroll,
                  ctrl:    _ctrl,
                  typing:  _typing,
                  sending: _sending,
                  onSend:  _send,
                  onClose: _toggle,
                ),
              ),
            ),
          ),

        // ── FAB ─────────────────────────────────────────────────────────────
        Positioned(
          bottom: isWide ? 24 : 16,
          right:  isWide ? 24 : 12,
          child: _Fab(open: _open, c: c, onTap: _toggle),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAB button
// ─────────────────────────────────────────────────────────────────────────────

class _Fab extends StatelessWidget {
  final bool _open;
  final SiColors _c;
  final VoidCallback onTap;
  const _Fab({required bool open, required SiColors c, required this.onTap})
      : _open = open,
        _c    = c;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: _open ? _c.ink2 : _c.brand,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (_open ? _c.ink : _c.brand).withOpacity(0.28),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Icon(
              _open
                  ? Icons.close_rounded
                  : Icons.support_agent_rounded,
              key: ValueKey(_open),
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat panel
// ─────────────────────────────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  final SiColors c;
  final bool isDark;
  final bool isWide;
  final Size size;
  final List<_Msg> messages;
  final ScrollController scroll;
  final TextEditingController ctrl;
  final bool typing;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onClose;

  const _Panel({
    required this.c,
    required this.isDark,
    required this.isWide,
    required this.size,
    required this.messages,
    required this.scroll,
    required this.ctrl,
    required this.typing,
    required this.sending,
    required this.onSend,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final w = isWide ? 356.0 : (size.width - 24.0);
    const h = 480.0;

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.45 : 0.13),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            _Header(c: c, onClose: onClose),
            Expanded(
              child: _MessageList(
                c: c,
                messages: messages,
                scroll: scroll,
                typing: typing,
              ),
            ),
            _InputBar(
              c: c,
              ctrl: ctrl,
              sending: sending,
              onSend: onSend,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final SiColors c;
  final VoidCallback onClose;
  const _Header({required this.c, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      color: c.brand,
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Center(
              child: Icon(Icons.support_agent_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Soporte Técnico SISOL',
                    style: SiType.sans(
                        size: 13,
                        weight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: -0.2)),
                Text('Estamos aquí para ayudarte',
                    style: SiType.sans(
                        size: 11,
                        color: Colors.white.withOpacity(0.72))),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.13),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Center(
                child: Icon(Icons.close_rounded,
                    color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message list
// ─────────────────────────────────────────────────────────────────────────────

class _MessageList extends StatelessWidget {
  final SiColors c;
  final List<_Msg> messages;
  final ScrollController scroll;
  final bool typing;

  const _MessageList({
    required this.c,
    required this.messages,
    required this.scroll,
    required this.typing,
  });

  @override
  Widget build(BuildContext context) {
    final count = messages.length + (typing ? 1 : 0);
    return Container(
      color: c.bg,
      child: ListView.builder(
        controller: scroll,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        itemCount: count,
        itemBuilder: (_, i) {
          if (typing && i == messages.length) {
            return _TypingBubble(c: c);
          }
          return _Bubble(msg: messages[i], c: c);
        },
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Msg msg;
  final SiColors c;
  const _Bubble({required this.msg, required this.c});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.fromUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 26, height: 26,
              margin: const EdgeInsets.only(right: 7),
              decoration:
                  BoxDecoration(color: c.brandTint, shape: BoxShape.circle),
              child: Center(
                child: Icon(Icons.support_agent_rounded,
                    size: 14, color: c.brand),
              ),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: isUser ? c.brand : c.panel,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(12),
                  topRight:    const Radius.circular(12),
                  bottomLeft:  Radius.circular(isUser ? 12 : 3),
                  bottomRight: Radius.circular(isUser ? 3  : 12),
                ),
                border: isUser ? null : Border.all(color: c.line),
              ),
              child: Text(
                msg.text,
                style: SiType.sans(
                    size: 13,
                    color: isUser ? Colors.white : c.ink,
                    height: 1.5),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  final SiColors c;
  const _TypingBubble({required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 26, height: 26,
            margin: const EdgeInsets.only(right: 7),
            decoration:
                BoxDecoration(color: c.brandTint, shape: BoxShape.circle),
            child: Center(
              child: Icon(Icons.support_agent_rounded,
                  size: 14, color: c.brand),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(12),
                topRight:    Radius.circular(12),
                bottomRight: Radius.circular(12),
                bottomLeft:  Radius.circular(3),
              ),
              border: Border.all(color: c.line),
            ),
            child: _Dots(c: c),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Input bar
// ─────────────────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final SiColors c;
  final TextEditingController ctrl;
  final bool sending;
  final VoidCallback onSend;

  const _InputBar({
    required this.c,
    required this.ctrl,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: c.hover,
                borderRadius: SiRadius.rMd,
                border: Border.all(color: c.line),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      enabled: !sending,
                      style: SiType.sans(size: 13, color: c.ink),
                      decoration: InputDecoration(
                        hintText: 'Escribe tu mensaje...',
                        hintStyle: SiType.sans(size: 13, color: c.ink4),
                        border:              InputBorder.none,
                        enabledBorder:       InputBorder.none,
                        focusedBorder:       InputBorder.none,
                        disabledBorder:      InputBorder.none,
                        errorBorder:         InputBorder.none,
                        focusedErrorBorder:  InputBorder.none,
                        isDense:             true,
                        contentPadding:      EdgeInsets.zero,
                        filled:              false,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: sending ? null : onSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: sending ? c.ink4 : c.brand,
                borderRadius: SiRadius.rMd,
              ),
              child: Center(
                child: sending
                    ? const SizedBox(
                        width: 15, height: 15,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated typing dots
// ─────────────────────────────────────────────────────────────────────────────

class _Dots extends StatefulWidget {
  final SiColors c;
  const _Dots({required this.c});

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = (_ctrl.value - i / 3.0) % 1.0;
          final t     = phase < 0.5 ? phase / 0.5 : (1 - phase) / 0.5;
          return Container(
            width:  6, height: 6,
            margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
            decoration: BoxDecoration(
              color:  widget.c.ink3.withOpacity(0.25 + t * 0.65),
              shape:  BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}
