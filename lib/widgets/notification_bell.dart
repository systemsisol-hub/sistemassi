import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import 'notification_list_modal.dart';

class NotificationBell extends StatelessWidget {
  final String role;
  final Map<String, dynamic> permissions;
  final String currentUserId;
  final Function(String?)? onNavigateToCalendar;

  const NotificationBell({
    super.key,
    required this.role,
    required this.permissions,
    required this.currentUserId,
    this.onNavigateToCalendar,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: NotificationService.allNotificationsStream,
      builder: (context, snapshot) {
        final all = snapshot.data ?? [];

        // Count only unread notifications that this user is allowed to see
        final unreadCount = all.where((n) {
          if (n['is_read'] == true) return false;
          final type = n['type'] as String? ?? '';
          if (type == 'collaborator_alert' || type == 'status_sys_alert') {
            return role == 'admin' && permissions['show_users'] == true;
          }
          if (type == 'incidencia_status') {
            return n['user_id'] == currentUserId;
          }
          return true;
        }).length;

        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                  ),
                  builder: (context) => NotificationListModal(
                    role: role,
                    permissions: permissions,
                    currentUserId: currentUserId,
                    onNavigateToCalendar: onNavigateToCalendar,
                  ),
                );
              },
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    unreadCount > 9 ? '9+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
