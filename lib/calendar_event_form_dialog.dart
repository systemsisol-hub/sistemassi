import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class EventFormDialog extends StatefulWidget {
  final String? eventId;
  final DateTime? initialDate;
  final bool? isPublic;
  const EventFormDialog(
      {super.key, this.eventId, this.initialDate, this.isPublic});

  @override
  State<EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends State<EventFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _supabase = Supabase.instance.client;

  DateTime _startDate = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.now();
  DateTime _endDate = DateTime.now().add(const Duration(hours: 1));
  TimeOfDay _endTime = TimeOfDay.now().replacing(
    hour: (TimeOfDay.now().hour + 1) % 24,
  );

  bool _isPublic = true;
  String _priority = 'Normal';
  String _recurrence = 'No repetir';
  DateTime? _recurrenceEndDate;
  final List<String> _recurrenceOptions = [
    'No repetir',
    'Diariamente',
    'Semanalmente',
    'Mensualmente',
    'Anualmente'
  ];

  List<Map<String, dynamic>> _profiles = [];
  final List<String> _selectedUserIds = [];
  bool _isLoading = false;
  bool _isFetchingEvent = false;
  String? _creatorId;
  late bool _isViewingData;
  final Map<String, dynamic> _userLookup = {};

  String? _myAttendanceStatus; // 'pending', 'accepted', 'declined'
  final _rejectionReasonController = TextEditingController();
  final Map<String, Map<String, dynamic>> _invitationDetails =
      {}; // userId -> {status, rejection_reason}

  bool get _isEditMode => widget.eventId != null;
  bool get _canEdit =>
      !_isEditMode || _creatorId == _supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _isViewingData = _isEditMode;
    if (_isEditMode) {
      _isFetchingEvent = true;
    } else {
      if (widget.initialDate != null) {
        _startDate = widget.initialDate!;
        _endDate = widget.initialDate!.add(const Duration(hours: 1));
      }
      if (widget.isPublic != null) {
        _isPublic = widget.isPublic!;
      }
    }
    _fetchUsers().then((_) {
      if (_isEditMode) {
        _fetchEventData();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _fetchEventData() async {
    setState(() => _isFetchingEvent = true);
    try {
      final eventResponse = await _supabase
          .from('events')
          .select()
          .eq('id', widget.eventId!)
          .single();
      final invResponse = await _supabase
          .from('event_invitations')
          .select('user_id, status, rejection_reason')
          .eq('event_id', widget.eventId!);

      if (mounted) {
        setState(() {
          _titleController.text = eventResponse['title'] ?? '';
          _locationController.text = eventResponse['location'] ?? '';
          _descriptionController.text = eventResponse['description'] ?? '';
          _isPublic = eventResponse['is_public'] ?? true;
          _priority = eventResponse['priority'] ?? 'Normal';
          _recurrence = eventResponse['recurrence'] ?? 'No repetir';
          _creatorId = eventResponse['creator_id'];

          final st = DateTime.parse(eventResponse['start_time']).toLocal();
          final et = DateTime.parse(eventResponse['end_time']).toLocal();
          _startDate = DateTime(st.year, st.month, st.day);
          _startTime = TimeOfDay.fromDateTime(st);
          _endDate = DateTime(et.year, et.month, et.day);
          _endTime = TimeOfDay.fromDateTime(et);

          _selectedUserIds.clear();
          _invitationDetails.clear();
          for (var inv in invResponse) {
            final uId = inv['user_id'] as String;
            _selectedUserIds.add(uId);
            _invitationDetails[uId] = {
              'status': inv['status'],
              'rejection_reason': inv['rejection_reason'],
            };
            if (uId == _supabase.auth.currentUser?.id) {
              _myAttendanceStatus = inv['status'] as String?;
              _rejectionReasonController.text =
                  inv['rejection_reason'] as String? ?? '';
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching event data: $e');
    } finally {
      if (mounted) setState(() => _isFetchingEvent = false);
    }
  }

  Future<void> _fetchUsers() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;

      List<Map<String, dynamic>> allUsers = [];
      int offset = 0;
      const int limit = 1000;

      while (true) {
        final data = await _supabase
            .from('profiles')
            .select('id, full_name, email, permissions')
            .range(offset, offset + limit - 1);

        allUsers.addAll(List<Map<String, dynamic>>.from(data));
        if (data.length < limit) break;
        offset += limit;
      }

      if (mounted) {
        setState(() {
          // Llenar el diccionario de búsqueda para todos los usuarios (incluso yo)
          for (var u in allUsers) {
            _userLookup[u['id'] as String] = u;
          }

          // La lista de _profiles solo debe tener a los usuarios SELECCIONABLES (excluyendo a mi mismo)
          _profiles = allUsers.where((user) {
            if (user['id'] == currentUserId) return false;

            final perms = user['permissions'] as Map<String, dynamic>?;
            if (perms == null) return false;

            // Check robustly for true or "true"
            final hasPerm = perms['show_calendar'];
            return hasPerm == true || hasPerm == 'true';
          }).toList();

          // Sort alphabetically locally
          _profiles.sort((a, b) {
            final nameA =
                (a['full_name'] ?? a['email'] ?? '').toString().toLowerCase();
            final nameB =
                (b['full_name'] ?? b['email'] ?? '').toString().toLowerCase();
            return nameA.compareTo(nameB);
          });
        });
      }
    } catch (e) {
      debugPrint('Error fetching users: $e');
    }
  }

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_titleController.text.trim().isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('Usuario no autenticado');

      final startDateTime = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
        _startTime.hour,
        _startTime.minute,
      );
      final endDateTime = DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        _endTime.hour,
        _endTime.minute,
      );

      if (endDateTime.isBefore(startDateTime)) {
        throw Exception('La fecha de fin no puede ser anterior al inicio');
      }

      if (_isEditMode) {
        // Update single event (no recurrence regeneration on edit)
        await _supabase.from('events').update({
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'location': _locationController.text.trim(),
          'recurrence': _recurrence,
          'start_time': startDateTime.toUtc().toIso8601String(),
          'end_time': endDateTime.toUtc().toIso8601String(),
          'priority': _priority,
          'is_public': _isPublic,
        }).eq('id', widget.eventId!);

        final eventId = widget.eventId!;
        await _supabase
            .from('event_invitations')
            .delete()
            .eq('event_id', eventId);
        if (!_isPublic && _selectedUserIds.isNotEmpty) {
          final invitations = _selectedUserIds
              .map((userId) => {
                    'event_id': eventId,
                    'user_id': userId,
                    'status': 'pending',
                  })
              .toList();
          await _supabase.from('event_invitations').insert(invitations);
        }
      } else {
        final duration = endDateTime.difference(startDateTime);
        final List<DateTime> starts;

        if (_recurrence != 'No repetir' && _recurrenceEndDate != null) {
          starts = _generateOccurrences(
              startDateTime, _recurrence, _recurrenceEndDate!);
        } else {
          starts = [startDateTime];
        }

        for (final occStart in starts) {
          final occEnd = occStart.add(duration);
          final eventResponse = await _supabase
              .from('events')
              .insert({
                'title': _titleController.text.trim(),
                'description': _descriptionController.text.trim(),
                'location': _locationController.text.trim(),
                'recurrence': _recurrence,
                'priority': _priority,
                'start_time': occStart.toUtc().toIso8601String(),
                'end_time': occEnd.toUtc().toIso8601String(),
                'creator_id': currentUserId,
                'is_public': _isPublic,
              })
              .select()
              .single();

          final eventId = eventResponse['id'];
          if (!_isPublic && _selectedUserIds.isNotEmpty) {
            final invitations = _selectedUserIds
                .map((userId) => {
                      'event_id': eventId,
                      'user_id': userId,
                      'status': 'pending',
                    })
                .toList();
            await _supabase.from('event_invitations').insert(invitations);
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_isEditMode
                  ? 'Evento actualizado exitosamente'
                  : 'Evento creado exitosamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<DateTime> _generateOccurrences(
      DateTime start, String recurrence, DateTime endDate) {
    final occurrences = <DateTime>[];
    DateTime current = start;
    while (!current.isAfter(endDate)) {
      occurrences.add(current);
      switch (recurrence) {
        case 'Diariamente':
          current = current.add(const Duration(days: 1));
          break;
        case 'Semanalmente':
          current = current.add(const Duration(days: 7));
          break;
        case 'Mensualmente':
          current = DateTime(current.year, current.month + 1, current.day,
              current.hour, current.minute);
          break;
        case 'Anualmente':
          current = DateTime(current.year + 1, current.month, current.day,
              current.hour, current.minute);
          break;
        default:
          break;
      }
      if (occurrences.length > 500) break; // safety cap
    }
    return occurrences;
  }

  Future<void> _pickRecurrenceEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _recurrenceEndDate ?? _startDate.add(const Duration(days: 30)),
      firstDate: _startDate.add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null && mounted) {
      setState(() => _recurrenceEndDate = picked);
    }
  }

  Future<void> _deleteEvent() async {
    final isRecurring = _recurrence != 'No repetir';

    // For recurring events, ask whether to delete just this one or all in the series
    String? choice;
    if (isRecurring) {
      choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Eliminar evento'),
          content: const Text(
              'Este es un evento con repetición. ¿Qué deseas eliminar?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'single'),
              child: const Text('Solo este evento',
                  style: TextStyle(color: Colors.orange)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'all'),
              child: const Text('Todos los eventos',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (choice == null) return;
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Eliminar evento'),
          content: const Text(
              '¿Estás seguro de que deseas eliminar este evento? Esta acción no se puede deshacer.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
                  const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Eliminar', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      choice = 'single';
    }

    setState(() => _isLoading = true);

    try {
      if (widget.eventId != null) {
        if (choice == 'all') {
          // Delete all events in the series (same title + creator + recurrence)
          await _supabase
              .from('events')
              .delete()
              .eq('title', _titleController.text.trim())
              .eq('creator_id', _creatorId!)
              .eq('recurrence', _recurrence);
        } else {
          await _supabase.from('events').delete().eq('id', widget.eventId!);
        }

        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(choice == 'all'
                    ? 'Todos los eventos eliminados'
                    : 'Evento eliminado exitosamente')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar evento: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Helper date/time pickers
  Future<void> _pickDateTime(bool isStart) async {
    final DateTime initialDate = isStart ? _startDate : _endDate;
    final TimeOfDay initialTime = isStart ? _startTime : _endTime;

    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );

    if (date == null) return;
    if (!mounted) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (time == null) return;

    setState(() {
      if (isStart) {
        _startDate = date;
        _startTime = time;
        final newStart =
            DateTime(date.year, date.month, date.day, time.hour, time.minute);
        final currentEnd = DateTime(_endDate.year, _endDate.month, _endDate.day,
            _endTime.hour, _endTime.minute);
        if (currentEnd.isBefore(newStart)) {
          _endDate = newStart.add(const Duration(hours: 1));
          _endTime = TimeOfDay.fromDateTime(_endDate);
        }
      } else {
        _endDate = date;
        _endTime = time;
      }
    });
  }

  bool _isUrl(String text) {
    final t = text.trim().toLowerCase();
    return t.startsWith('http://') ||
        t.startsWith('https://') ||
        t.startsWith('www.');
  }

  Future<void> _launchUrl(String urlText) async {
    var u = urlText.trim();
    if (u.startsWith('www.')) {
      u = 'https://$u';
    }
    final uri = Uri.tryParse(u);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el enlace')),
        );
      }
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copiado al portapapeles')),
    );
  }

  Widget _buildPriorityChip(String label, Color color) {
    final isSelected = _priority == label;
    return GestureDetector(
      onTap: _canEdit ? () => setState(() => _priority = label) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: isSelected ? 2 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  String _formatDetailedDate(DateTime d) {
    const weekDays = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo'
    ];
    const months = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre'
    ];
    final weekdayStr = weekDays[d.weekday - 1];
    final monthStr = months[d.month - 1];
    return '$weekdayStr, ${d.day} de $monthStr de ${d.year}';
  }

  Future<void> _updateAttendance(String status) async {
    setState(() => _isLoading = true);
    try {
      await _supabase
          .from('event_invitations')
          .update({
            'status': status,
            'rejection_reason': status == 'declined'
                ? _rejectionReasonController.text.trim()
                : null,
          })
          .eq('event_id', widget.eventId!)
          .eq('user_id', _supabase.auth.currentUser!.id);

      // Enviar notificación al organizador
      final currentUserId = _supabase.auth.currentUser!.id;
      final u = _userLookup[currentUserId] ?? {};
      final userName = u['full_name'] ?? u['email'] ?? 'Un invitado';
      final reason = _rejectionReasonController.text.trim();

      await _supabase.from('notifications').insert({
        'user_id': _creatorId,
        'title': status == 'accepted'
            ? 'Confirmación de Asistencia'
            : 'Cancelación de Asistencia',
        'message':
            '$userName ha ${status == 'accepted' ? 'confirmado' : 'rechazado'} su asistencia al evento "${_titleController.text}"${status == 'declined' && reason.isNotEmpty ? '.\nMotivo: $reason' : ''}',
        'type': 'event_invitation',
        'metadata': {
          'event_id': widget.eventId,
          'event_title': _titleController.text,
          'event_date': DateTime(_startDate.year, _startDate.month,
                  _startDate.day, _startTime.hour, _startTime.minute)
              .toUtc()
              .toIso8601String(),
          'priority': _priority,
          'status': status,
        }
      });

      if (mounted) {
        setState(() {
          _myAttendanceStatus = status;
          _isLoading = false;
        });
        Navigator.pop(context, true); // Cierra el modal de detalles
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'accepted'
                ? 'Asistencia confirmada 👍'
                : 'Asistencia rechazada 🛑'),
            backgroundColor: status == 'accepted' ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al actualizar asistencia: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildDetailsView() {
    final startStr = _startTime.format(context);
    final endStr = _endTime.format(context);

    return SingleChildScrollView(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(
            _titleController.text.isNotEmpty
                ? _titleController.text
                : 'Sin título',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.calendar_today, color: Colors.grey, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _formatDetailedDate(_startDate),
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.access_time, color: Colors.grey, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$startStr - $endStr',
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_locationController.text.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined,
                    color: Colors.grey, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _locationController.text,
                        style: const TextStyle(
                            fontSize: 16, color: Colors.black87),
                      ),
                      if (_isUrl(_locationController.text)) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            InkWell(
                              onTap: () => _launchUrl(_locationController.text),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.open_in_browser,
                                      size: 18, color: Colors.blue),
                                  SizedBox(width: 4),
                                  Text('Abrir',
                                      style: TextStyle(
                                          color: Colors.blue,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: () =>
                                  _copyToClipboard(_locationController.text),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.copy,
                                      size: 18, color: Colors.blue),
                                  SizedBox(width: 4),
                                  Text('Copiar',
                                      style: TextStyle(
                                          color: Colors.blue,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                _copyToClipboard(_locationController.text);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Compartir copiado al portapapeles')));
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.share,
                                      size: 18, color: Colors.blue),
                                  SizedBox(width: 4),
                                  Text('Compartir',
                                      style: TextStyle(
                                          color: Colors.blue,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

          if (_descriptionController.text.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.notes, color: Colors.grey, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _descriptionController.text,
                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ],

          // --- SECCIÓN DE ASISTENCIA PARA INVITADOS ---
          if (_myAttendanceStatus != null &&
              _creatorId != _supabase.auth.currentUser?.id) ...[
            const SizedBox(height: 24),
            const Text('Tu Asistencia',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _isLoading ? null : () => _updateAttendance('accepted'),
                    icon: Icon(Icons.check,
                        color: _myAttendanceStatus == 'accepted'
                            ? Colors.white
                            : Colors.grey),
                    label: const Text('Asistiré'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _myAttendanceStatus == 'accepted'
                          ? Colors.green
                          : Colors.grey.shade100,
                      foregroundColor: _myAttendanceStatus == 'accepted'
                          ? Colors.white
                          : Colors.black87,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () =>
                            setState(() => _myAttendanceStatus = 'declined'),
                    icon: Icon(Icons.close,
                        color: _myAttendanceStatus == 'declined'
                            ? Colors.white
                            : Colors.grey),
                    label: const Text('Rechazar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _myAttendanceStatus == 'declined'
                          ? Colors.red
                          : Colors.grey.shade100,
                      foregroundColor: _myAttendanceStatus == 'declined'
                          ? Colors.white
                          : Colors.black87,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
            if (_myAttendanceStatus == 'declined') ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _rejectionReasonController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Motivo de rechazo',
                  hintText: 'Ej. Cruce de horarios',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      _isLoading ? null : () => _updateAttendance('declined'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Confirmar Rechazo',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],

          if (_creatorId != null) ...[
            const SizedBox(height: 24),
            Text(_isPublic ? 'Organizador' : 'Invitados',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),

            // 1. Mostrar el creador primero
            Builder(builder: (context) {
              final p = _userLookup[_creatorId] ?? {'full_name': 'Usuario'};
              final name = p['full_name'] ?? p['email'] ?? 'Usuario';

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade800,
                  child: Text(name[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white)),
                ),
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Organizador',
                    style: TextStyle(color: Colors.blue)),
              );
            }),

            // 2. Mostrar el resto de los invitados
            if (!_isPublic)
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _selectedUserIds.length,
                itemBuilder: (context, index) {
                  final id = _selectedUserIds[index];
                  if (id == _creatorId)
                    return const SizedBox.shrink(); // evitar duplicado

                  final p = _userLookup[id] ?? {'full_name': 'Usuario'};
                  final name = p['full_name'] ?? p['email'] ?? 'Usuario';

                  final inviteDetail = _invitationDetails[id] ?? {};
                  final status = inviteDetail['status'] ?? 'pending';
                  final reason = inviteDetail['rejection_reason'] ?? '';

                  Color avatarBg;
                  if (status == 'accepted') {
                    avatarBg = Colors.green.shade400;
                  } else if (status == 'declined') {
                    avatarBg = Colors.red.shade400;
                  } else {
                    avatarBg = Colors.blue.shade300;
                  }

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: avatarBg,
                      child: Text(name[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: status == 'declined'
                        ? Text(
                            'Rechazado: ${reason.isNotEmpty ? reason : 'Sin motivo'}',
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12))
                        : status == 'accepted'
                            ? const Text('Asistirá',
                                style: TextStyle(
                                    color: Colors.green, fontSize: 12))
                            : const Text('Pendiente',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormView(DateFormat format) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 40,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Tipo: Publico / Personal
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _canEdit
                          ? () => setState(() => _isPublic = true)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _isPublic ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _isPublic
                              ? [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2))
                                ]
                              : null,
                        ),
                        child: const Center(
                          child: Text('Público',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _canEdit
                          ? () => setState(() => _isPublic = false)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !_isPublic ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: !_isPublic
                              ? [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2))
                                ]
                              : null,
                        ),
                        child: const Center(
                          child: Text('Personal',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 2. Título
            TextFormField(
              controller: _titleController,
              readOnly: !_canEdit,
              decoration: InputDecoration(
                labelText: 'Título',
                hintText: 'Título del evento',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.title, color: Colors.grey),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),

            // Ubicación
            TextFormField(
              controller: _locationController,
              readOnly: !_canEdit,
              decoration: const InputDecoration(
                labelText: 'Ubicación / URL',
                hintText: 'Añadir ubicación o URL',
                border: OutlineInputBorder(),
                prefixIcon:
                    Icon(Icons.location_on_outlined, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),

            // Descripción
            TextFormField(
              controller: _descriptionController,
              readOnly: !_canEdit,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                hintText: 'Añadir descripción',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),

            // Fechas
            Row(
              children: [
                Expanded(
                  child: _buildDateTimePicker(
                    label: 'Inicio',
                    date: _startDate,
                    time: _startTime,
                    onTap: _canEdit ? () => _pickDateTime(true) : null,
                    format: format,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDateTimePicker(
                    label: 'Fin',
                    date: _endDate,
                    time: _endTime,
                    onTap: _canEdit ? () => _pickDateTime(false) : null,
                    format: format,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Priority selector
            Row(
              children: [
                const Icon(Icons.flag, color: Colors.grey),
                const SizedBox(width: 12),
                const Text('Prioridad',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const Spacer(),
                _buildPriorityChip('Normal', Colors.blue),
                const SizedBox(width: 8),
                _buildPriorityChip('Alta', Colors.red),
              ],
            ),
            const SizedBox(height: 16),

            // Opción de repetir
            DropdownButtonFormField<String>(
              value: _recurrence,
              decoration: const InputDecoration(
                labelText: 'Repetir',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.repeat, color: Colors.grey),
              ),
              items: _recurrenceOptions.map((e) {
                return DropdownMenuItem(value: e, child: Text(e));
              }).toList(),
              onChanged: _canEdit
                  ? (val) {
                      if (val != null) {
                        setState(() => _recurrence = val);
                      }
                    }
                  : null,
            ),

            // Repetir end date (shown only when recurrence is active)
            if (_recurrence != 'No repetir') ...[
              const SizedBox(height: 16),
              TextFormField(
                readOnly: true,
                onTap: _canEdit ? _pickRecurrenceEndDate : null,
                decoration: InputDecoration(
                  labelText: 'Repetir hasta',
                  border: const OutlineInputBorder(),
                  prefixIcon:
                      const Icon(Icons.event_repeat, color: Colors.grey),
                  suffixIcon: const Icon(Icons.calendar_today, size: 18),
                  fillColor:
                      _recurrenceEndDate == null ? Colors.red.shade50 : null,
                ),
                controller: TextEditingController(
                  text: _recurrenceEndDate != null
                      ? DateFormat('dd/MM/yyyy').format(_recurrenceEndDate!)
                      : '',
                ),
              ),
            ],

            // Invitados (solo si es Personal)
            if (!_isPublic) ...[
              const SizedBox(height: 20),
              const Text('Invitados',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              if (_profiles.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _profiles.length,
                  itemBuilder: (context, index) {
                    final p = _profiles[index];
                    final id = p['id'] as String;
                    final name = p['full_name'] ?? p['email'] ?? 'Usuario';
                    final isSelected = _selectedUserIds.contains(id);

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor:
                            isSelected ? Colors.blue : Colors.grey.shade200,
                        child: Text(name[0].toUpperCase(),
                            style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black54)),
                      ),
                      title: Text(name),
                      trailing: Switch(
                        value: isSelected,
                        activeColor: Colors.blue,
                        onChanged: _canEdit
                            ? (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedUserIds.add(id);
                                  } else {
                                    _selectedUserIds.remove(id);
                                  }
                                });
                              }
                            : null,
                      ),
                      onTap: _canEdit
                          ? () {
                              setState(() {
                                if (isSelected) {
                                  _selectedUserIds.remove(id);
                                } else {
                                  _selectedUserIds.add(id);
                                }
                              });
                            }
                          : null,
                    );
                  },
                ),
            ],

            if (_isEditMode && _canEdit) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _deleteEvent,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('Eliminar Evento',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.red),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimePicker({
    required String label,
    required DateTime date,
    required TimeOfDay time,
    required VoidCallback? onTap,
    required DateFormat format,
  }) {
    return TextFormField(
      readOnly: true,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.access_time, color: Colors.grey),
        suffixIcon: const Icon(Icons.calendar_today, size: 18),
      ),
      controller: TextEditingController(
        text: format.format(
            DateTime(date.year, date.month, date.day, time.hour, time.minute)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('dd/MM/yyyy HH:mm');
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Stack(
        children: [
          Padding(
            padding:
                const EdgeInsets.only(top: 60.0), // Space for handle and header
            child: _isFetchingEvent
                ? Center(
                    child: Image.asset(
                      'assets/sisol_loader.gif',
                      width: 150,
                      errorBuilder: (context, error, stackTrace) =>
                          const CircularProgressIndicator(),
                      frameBuilder:
                          (context, child, frame, wasSynchronouslyLoaded) =>
                              frame == null
                                  ? const CircularProgressIndicator()
                                  : child,
                    ),
                  )
                : (_isViewingData
                    ? _buildDetailsView()
                    : _buildFormView(format)),
          ),

          // Header / Drag handle
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2))
                  ]),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      if (!_isViewingData && _isEditMode) {
                        setState(() => _isViewingData = true);
                      } else {
                        Navigator.pop(context);
                      }
                    },
                    child: Text(
                        !_isViewingData && _isEditMode ? 'Atrás' : 'Cancelar',
                        style:
                            const TextStyle(fontSize: 16, color: Colors.grey)),
                  ),
                  Text(_isEditMode ? 'Detalle del Evento' : 'Nuevo Evento',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  if (_isViewingData && _canEdit)
                    TextButton(
                      onPressed: () => setState(() => _isViewingData = false),
                      child: const Text('Editar',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue)),
                    )
                  else if (_canEdit)
                    TextButton(
                      onPressed: _isLoading ? null : _saveEvent,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Guardar',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue)),
                    )
                  else
                    const SizedBox(width: 60),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
