import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';
import '../calendar_event_form_dialog.dart';

class NotificationListModal extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;
  final String currentUserId;
  /// Called when the user taps an event notification — navigate to Calendar.
  final Function(String?)? onNavigateToCalendar;

  const NotificationListModal({
    super.key,
    required this.role,
    required this.permissions,
    required this.currentUserId,
    this.onNavigateToCalendar,
  });

  @override
  State<NotificationListModal> createState() => _NotificationListModalState();
}

class _NotificationListModalState extends State<NotificationListModal> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final data = await NotificationService.fetchRecent();
      setState(() {
        _notifications = data.where((n) {
          final type = n['type'] as String? ?? '';
          if (type == 'collaborator_alert' || type == 'status_sys_alert') {
            return widget.role == 'admin' && widget.permissions['show_users'] == true;
          }
          if (type == 'incidencia_status') {
            return n['user_id'] == widget.currentUserId;
          }
          return true;
        }).toList()
          ..sort((a, b) {
            final aRead = a['is_read'] == true ? 1 : 0;
            final bRead = b['is_read'] == true ? 1 : 0;
            if (aRead != bRead) return aRead.compareTo(bRead);
            return (b['created_at'] as String).compareTo(a['created_at'] as String);
          });
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Build the icon + color for each notification type.
  ({IconData icon, Color color}) _typeStyle(String type, String priority) {
    if (type == 'event_invitation') {
      final isHigh = priority == 'Alta';
      return (icon: Icons.event, color: isHigh ? Colors.red.shade600 : Colors.blue.shade600);
    }
    if (type == 'collaborator_alert' || type == 'status_sys_alert') {
      return (icon: Icons.person_pin, color: Colors.orange.shade600);
    }
    if (type == 'incidencia_status') {
      return (icon: Icons.description, color: Colors.purple.shade600);
    }
    return (icon: Icons.notifications, color: Colors.grey.shade600);
  }

  Widget _buildEventSubtitle(Map<String, dynamic> meta, String message) {
    final title = meta['event_title'] as String? ?? '';
    final dateStr = meta['event_date'] as String? ?? '';
    final priority = meta['priority'] as String? ?? 'Normal';

    DateTime? date;
    if (dateStr.isNotEmpty) {
      try { date = DateTime.parse(dateStr).toLocal(); } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (date != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(date),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        if (message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Text(
              message,
              style: TextStyle(color: Colors.grey[800], fontSize: 13),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: priority == 'Alta' ? Colors.red.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: priority == 'Alta' ? Colors.red.shade200 : Colors.blue.shade200,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.flag, size: 12,
                    color: priority == 'Alta' ? Colors.red.shade600 : Colors.blue.shade600),
                const SizedBox(width: 4),
                Text(
                  'Prioridad: $priority',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: priority == 'Alta' ? Colors.red.shade700 : Colors.blue.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleEventTap(Map<String, dynamic> notification) async {
    final meta = (notification['metadata'] as Map<String, dynamic>?) ?? {};
    final eventId = meta['event_id'] as String?;

    // Mark as read
    if (!(notification['is_read'] ?? true)) {
      await NotificationService.markAsRead(notification['id']);
    }

    if (!mounted) return;

    // Close the modal
    Navigator.pop(context);

    // Navigate to calendar tab with event details
    widget.onNavigateToCalendar?.call(eventId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Notificaciones',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await NotificationService.markAllAsRead();
                    _loadNotifications();
                  },
                  child: const Text('Marcar todas como leídas'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_none, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text('No tienes notificaciones',
                                style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _notifications.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final notification = _notifications[index];
                          final isUnread = !(notification['is_read'] ?? true);
                          final createdAt = DateTime.parse(notification['created_at']);
                          final type = notification['type'] as String? ?? '';
                          final meta = (notification['metadata'] as Map<String, dynamic>?) ?? {};
                          final priority = meta['priority'] as String? ?? 'Normal';
                          final style = _typeStyle(type, priority);
                          final isEvent = type == 'event_invitation';

                          return Card(
                            elevation: 0,
                            color: isUnread
                                ? theme.colorScheme.primary.withOpacity(0.05)
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isUnread
                                    ? theme.colorScheme.primary.withOpacity(0.2)
                                    : Colors.grey[200]!,
                              ),
                            ),
                            child: ListTile(
                              onTap: () async {
                                if (isEvent) {
                                  await _handleEventTap(notification);
                                } else {
                                  if (isUnread) {
                                    await NotificationService.markAsRead(notification['id']);
                                    _loadNotifications();
                                  }
                                }
                              },
                              leading: CircleAvatar(
                                backgroundColor: isUnread
                                    ? style.color
                                    : Colors.grey[200],
                                child: Icon(
                                  style.icon,
                                  color: isUnread ? Colors.white : Colors.grey[600],
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                notification['title'],
                                style: TextStyle(
                                  fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              subtitle: isEvent
                                  ? _buildEventSubtitle(meta, notification['message'] ?? '')
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(notification['message'] ?? ''),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',
                                          style: const TextStyle(
                                              fontSize: 10, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                              trailing: isUnread
                                  ? Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                    )
                                  : isEvent
                                      ? const Icon(Icons.arrow_forward_ios,
                                          size: 14, color: Colors.grey)
                                      : null,
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
