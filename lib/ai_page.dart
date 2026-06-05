import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xl;
import 'theme/si_theme.dart';

class AiPage extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;

  const AiPage({
    super.key,
    this.role = 'usuario',
    this.permissions = const {},
  });

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMsg> _messages = [];
  bool _isLoading = false;
  _AttachedFile? _attachedFile;

  static const _fnUrl =
      'https://zkmbebybyyefmqcxjqrg.supabase.co/functions/v1/ai-assistant';

  static const _quickActions = [
    (Icons.search,              'Buscar colaborador',  'Quiero buscar a un colaborador específico'),
    (Icons.event_note_outlined, 'Nueva incidencia',    'Quiero crear una solicitud de vacaciones'),
  ];

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── File attachment ──────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'tsv', 'txt', 'md', 'xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final ext = (file.extension ?? '').toLowerCase();
    String content;

    try {
      if (ext == 'xlsx' || ext == 'xls') {
        content = _parseExcel(bytes);
      } else {
        // CSV, TSV, MD, TXT — leer como texto
        content = utf8.decode(bytes, allowMalformed: true);
      }
    } catch (e) {
      content = 'Error al leer el archivo: $e';
    }

    // Limitar a 40 000 caracteres para no saturar el contexto del modelo
    const maxChars = 40000;
    final truncated = content.length > maxChars;
    if (truncated) content = content.substring(0, maxChars);

    if (mounted) {
      setState(() {
        _attachedFile = _AttachedFile(
          name: file.name,
          ext: ext,
          content: content,
          truncated: truncated,
        );
      });
    }
  }

  String _parseExcel(Uint8List bytes) {
    final excel = xl.Excel.decodeBytes(bytes);
    final buf = StringBuffer();
    for (final sheetName in excel.tables.keys) {
      final sheet = excel.tables[sheetName]!;
      if (excel.tables.length > 1) buf.writeln('### Hoja: $sheetName\n');
      for (final row in sheet.rows) {
        buf.writeln(row.map((c) => c?.value?.toString() ?? '').join('\t'));
      }
      buf.writeln();
    }
    return buf.toString();
  }

  IconData _iconForExt(String ext) {
    switch (ext) {
      case 'csv':
      case 'tsv':
        return Icons.table_chart_outlined;
      case 'xlsx':
      case 'xls':
        return Icons.grid_on_outlined;
      case 'md':
        return Icons.article_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
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
    if ((trimmed.isEmpty && _attachedFile == null) || _isLoading) return;
    _inputCtrl.clear();

    // Build the message content, prepending file data if attached
    final file = _attachedFile;
    String userText = trimmed;
    String displayText = trimmed;

    if (file != null) {
      final truncNote = file.truncated
          ? '\n\n⚠️ Archivo truncado a los primeros 40 000 caracteres.'
          : '';
      userText =
          '📎 Archivo adjunto: ${file.name}\n\n'
          '```\n${file.content}\n```$truncNote'
          '${trimmed.isNotEmpty ? '\n\n$trimmed' : ''}';
      displayText = trimmed.isNotEmpty ? trimmed : 'Analiza este archivo.';
    }

    setState(() {
      _messages.add(_ChatMsg(
        role: 'user',
        text: displayText,
        attachedFileName: file?.name,
        attachedFileExt: file?.ext,
      ));
      _attachedFile = null;
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Sin sesión activa');

      // Build history — use displayText for older messages, userText is already
      // included in the last user message we just added with file content embedded
      final history = _messages
          .where((m) => m.text.isNotEmpty)
          .map((m) => {'role': m.role, 'content': m.text})
          .toList();
      // Replace the last user message text with the full content (file + question)
      if (history.isNotEmpty && history.last['role'] == 'user') {
        history[history.length - 1] = {'role': 'user', 'content': userText};
      }

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
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
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
                'Consulta información del equipo, gestiona incidencias\ny comunícate con lenguaje natural.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.ink3, height: 1.6),
              ),
              const SizedBox(height: 24),
              _buildCapabilitiesCard(c),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapabilitiesCard(SiColors c) {
    final isAdmin = widget.role == 'admin';

    final List<(IconData, String)> items = isAdmin
        ? [
            (Icons.people_outline,          'Consultar todos los colaboradores con datos completos'),
            (Icons.person_add_outlined,     'Dar de alta nuevos colaboradores'),
            (Icons.edit_outlined,           'Actualizar información de colaboradores'),
            (Icons.description_outlined,    'Ver y crear incidencias de cualquier usuario'),
            (Icons.inventory_2_outlined,    'Consultar el inventario completo de equipos'),
            (Icons.notifications_outlined,  'Enviar notificaciones al equipo'),
            (Icons.bar_chart_outlined,      'Generar reportes por área y ubicación'),
          ]
        : [
            (Icons.people_outline,         'Buscar colaboradores (nombre, área, puesto, ubicación)'),
            (Icons.description_outlined,   'Crear y consultar mis propias incidencias'),
            (Icons.inventory_2_outlined,   'Ver el equipo asignado a mi perfil'),
            (Icons.notifications_outlined, 'Enviar notificaciones'),
          ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: c.brandTint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isAdmin
                    ? Icons.admin_panel_settings_outlined
                    : Icons.person_outline,
                size: 15,
                color: c.brand,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAdmin ? 'Acceso de Administrador' : 'Acceso de Usuario',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.ink),
                ),
                Text(
                  isAdmin ? 'Puedes hacer todo lo siguiente:' : 'Puedes hacer lo siguiente:',
                  style: TextStyle(fontSize: 11, color: c.ink3),
                ),
              ],
            ),
          ]),
          const SizedBox(height: 14),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(item.$1, size: 15, color: c.brand),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.$2,
                    style: TextStyle(fontSize: 13, color: c.ink2, height: 1.4),
                  ),
                ),
              ],
            ),
          )),
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
        16, 10, 16,
        MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Archivo adjunto chip ──────────────────────────────────────
          if (_attachedFile != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.brandTint,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.brand.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(_iconForExt(_attachedFile!.ext), size: 16, color: c.brand),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _attachedFile!.name,
                              style: TextStyle(fontSize: 13, color: c.brand, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_attachedFile!.truncated)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text('truncado', style: TextStyle(fontSize: 11, color: c.warn)),
                            ),
                          GestureDetector(
                            onTap: () => setState(() => _attachedFile = null),
                            child: Icon(Icons.close, size: 16, color: c.brand),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Input row ─────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Botón adjuntar archivo
              GestureDetector(
                onTap: _isLoading ? null : _pickFile,
                child: Container(
                  width: 38,
                  height: 38,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _attachedFile != null ? c.brandTint : c.hover,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _attachedFile != null
                          ? c.brand.withOpacity(0.4)
                          : c.line,
                    ),
                  ),
                  child: Icon(
                    Icons.attach_file_rounded,
                    size: 18,
                    color: _attachedFile != null ? c.brand : c.ink3,
                  ),
                ),
              ),
              // Campo de texto
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: c.bg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: c.line),
                  ),
                  child: TextField(
                    controller: _inputCtrl,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _attachedFile != null
                          ? 'Pregunta sobre el archivo...'
                          : 'Escribe un mensaje...',
                      hintStyle: TextStyle(color: c.ink4, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                    style: TextStyle(fontSize: 14, color: c.ink),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Botón enviar
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
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.arrow_upward_rounded,
                          color: Colors.white, size: 20),
                ),
              ),
            ],
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
          if (isUser && msg.attachedFileName != null)
            Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78),
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconForExt(msg.attachedFileExt ?? ''),
                    size: 15,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      msg.attachedFileName!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
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

    if (type == 'vacaciones') {
      final data = s['data'] as Map<String, dynamic>?;
      if (data == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _VacationCard(data: data, c: c),
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

// ── Data models ───────────────────────────────────────────────────────────────

class _ChatMsg {
  final String role;
  final String text;
  final Map<String, dynamic>? structured;
  final bool isError;
  final String? attachedFileName;
  final String? attachedFileExt;

  const _ChatMsg({
    required this.role,
    required this.text,
    this.structured,
    this.isError = false,
    this.attachedFileName,
    this.attachedFileExt,
  });
}

class _AttachedFile {
  final String name;
  final String ext;
  final String content;
  final bool truncated;

  const _AttachedFile({
    required this.name,
    required this.ext,
    required this.content,
    required this.truncated,
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

// ── Vacation card ─────────────────────────────────────────────────────────────

class _VacationCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final SiColors c;
  const _VacationCard({required this.data, required this.c});

  @override
  Widget build(BuildContext context) {
    final nombre        = data['colaborador'] as String? ?? '';
    final numero        = data['numero_empleado'] as String?;
    final total         = data['total_disponible'] as int? ?? 0;
    final usaReingreso  = data['usa_fecha_reingreso'] as bool? ?? false;
    final periodos      = (data['periodos'] as List?)
            ?.cast<Map<String, dynamic>>() ?? [];

    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabecera ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: c.brandTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.beach_access_outlined,
                      size: 16, color: c.brand),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre.isEmpty ? 'Historial de Vacaciones' : nombre,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: c.ink),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        [
                          if (numero != null) 'Empleado #$numero',
                          if (usaReingreso) 'Cálculo desde reingreso',
                        ].join(' · '),
                        style: TextStyle(fontSize: 11, color: c.ink3),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: total > 0 ? c.successTint : c.hover,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: total > 0
                            ? c.success.withOpacity(0.3)
                            : c.line),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$total',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: total > 0 ? c.success : c.ink3,
                              height: 1.1)),
                      Text('disponibles',
                          style: TextStyle(
                              fontSize: 9,
                              color: total > 0 ? c.success : c.ink4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Encabezado de columnas ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: c.hover,
            child: Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text('Período',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: c.ink3))),
                _colHeader('Ley', c),
                _colHeader('Usados', c),
                _colHeader('Disponibles', c),
              ],
            ),
          ),
          // ── Filas de periodos ───────────────────────────────────────────
          ...periodos.map((p) {
            final esCurrent = p['es_periodo_actual'] as bool? ?? false;
            final disp      = p['dias_disponibles'] as int? ?? 0;
            final sol       = p['dias_solicitados'] as int? ?? 0;
            final ley       = p['dias_ley'] as int? ?? 0;
            final periodo   = p['periodo'] as String? ?? '';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: esCurrent
                    ? c.brand.withOpacity(0.05)
                    : Colors.transparent,
                border: Border(
                    bottom: BorderSide(color: c.line, width: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Row(children: [
                      if (esCurrent)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                              color: c.brand, shape: BoxShape.circle),
                        ),
                      Text(
                        periodo,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: esCurrent
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: esCurrent ? c.brand : c.ink),
                      ),
                    ]),
                  ),
                  _colVal('$ley', c.ink2, c),
                  _colVal('$sol', sol > 0 ? c.warn : c.ink4, c),
                  _colVal(
                    '$disp',
                    disp > 0 ? c.success : disp < 0 ? c.danger : c.ink3,
                    c,
                    bold: true,
                  ),
                ],
              ),
            );
          }),
          // ── Pie ─────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 12, color: c.ink4),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Días según Ley Federal del Trabajo. '
                    'Proporcional al tiempo transcurrido del periodo actual. '
                    'Se descuentan incidencias APROBADAS y PENDIENTES.',
                    style:
                        TextStyle(fontSize: 10, color: c.ink4, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _colHeader(String text, SiColors c) => SizedBox(
        width: 68,
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: c.ink3)),
      );

  Widget _colVal(String text, Color color, SiColors c,
          {bool bold = false}) =>
      SizedBox(
        width: 68,
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                fontWeight:
                    bold ? FontWeight.w600 : FontWeight.normal,
                color: color)),
      );
}
