import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';

class NotificationListModal extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;
  final String currentUserId;
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

class _NotificationListModalState extends State<NotificationListModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _all = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  StreamSubscription<List<Map<String, dynamic>>>? _streamSub;
  Timer? _debounce;
  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _fetchInitial();
    // Refresco silencioso en tiempo real
    _streamSub = NotificationService.allNotificationsStream.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        if (mounted) _fetchInitial(silent: true);
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _streamSub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _fetchInitial({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final data = await NotificationService.fetchPage(offset: 0, limit: _pageSize);
      if (mounted) {
        setState(() {
          _all = _visibilityFilter(data);
          _hasMore = data.length >= _pageSize;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final data = await NotificationService.fetchPage(offset: _all.length, limit: _pageSize);
      if (mounted) {
        setState(() {
          _all.addAll(_visibilityFilter(data));
          _hasMore = data.length >= _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  List<Map<String, dynamic>> _visibilityFilter(List<Map<String, dynamic>> data) {
    return data.where((n) {
      final type = n['type'] as String? ?? '';
      if (type == 'collaborator_alert' || type == 'status_sys_alert') {
        return widget.role == 'admin' && widget.permissions['show_users'] == true;
      }
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _filtered {
    switch (_tabController.index) {
      case 1:
        return _all
            .where((n) => (n['type'] as String? ?? '').contains('incidencia'))
            .toList();
      case 2:
        return _all.where((n) => n['type'] == 'event_invitation').toList();
      default:
        return _all;
    }
  }

  int get _incidenciasCount =>
      _all.where((n) => (n['type'] as String? ?? '').contains('incidencia')).length;
  int get _eventosCount =>
      _all.where((n) => n['type'] == 'event_invitation').length;

  Future<void> _delete(Map<String, dynamic> n) async {
    setState(() => _all.removeWhere((x) => x['id'] == n['id']));
    await NotificationService.deleteNotification(n['id']);
  }

  ({IconData icon, Color color}) _typeStyle(String type, String priority) {
    if (type == 'event_invitation') {
      return (
        icon: Icons.event,
        color: priority == 'Alta' ? Colors.red.shade600 : Colors.blue.shade600,
      );
    }
    if (type == 'collaborator_alert' || type == 'status_sys_alert') {
      return (icon: Icons.person_pin, color: Colors.orange.shade600);
    }
    if (type == 'incidencia_status') {
      return (icon: Icons.description, color: Colors.purple.shade600);
    }
    if (type == 'new_incidencia') {
      return (icon: Icons.add_circle_outline, color: Colors.teal.shade600);
    }
    return (icon: Icons.notifications, color: Colors.grey.shade600);
  }

  Widget _buildSubtitle(Map<String, dynamic> n) {
    final type = n['type'] as String? ?? '';
    final meta = (n['metadata'] as Map<String, dynamic>?) ?? {};
    final message = n['message'] as String? ?? '';
    final createdAt = DateTime.parse(n['created_at']).toLocal();
    final timeStr = DateFormat('dd/MM/yyyy HH:mm').format(createdAt);

    if (type == 'event_invitation') {
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
                  Text(DateFormat('dd/MM/yyyy HH:mm').format(date),
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(message, style: TextStyle(color: Colors.grey[800], fontSize: 13)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: priority == 'Alta' ? Colors.red.shade50 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: priority == 'Alta' ? Colors.red.shade200 : Colors.blue.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag,
                      size: 12,
                      color: priority == 'Alta' ? Colors.red.shade600 : Colors.blue.shade600),
                  const SizedBox(width: 4),
                  Text('Prioridad: $priority',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: priority == 'Alta' ? Colors.red.shade700 : Colors.blue.shade700,
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        const SizedBox(height: 4),
        Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Future<void> _handleTap(Map<String, dynamic> n) async {
    final isUnread = !(n['is_read'] ?? true);
    final type = n['type'] as String? ?? '';

    if (isUnread) {
      await NotificationService.markAsRead(n['id']);
      if (mounted) {
        setState(() {
          final idx = _all.indexWhere((x) => x['id'] == n['id']);
          if (idx != -1) _all[idx] = {..._all[idx], 'is_read': true};
        });
      }
    }

    if (type == 'event_invitation' && mounted) {
      final meta = (n['metadata'] as Map<String, dynamic>?) ?? {};
      Navigator.pop(context);
      widget.onNavigateToCalendar?.call(meta['event_id'] as String?);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = _all.where((n) => !(n['is_read'] ?? true)).length;
    final filtered = _filtered;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36,
              height: 4,
              decoration:
                  BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
            child: Row(
              children: [
                Text('Notificaciones',
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                if (unread > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration:
                        BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                    child: Text('$unread',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
                const Spacer(),
                if (unread > 0)
                  TextButton(
                    onPressed: () async {
                      await NotificationService.markAllAsRead();
                      _fetchInitial(silent: true);
                    },
                    child: const Text('Marcar leídas', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: theme.colorScheme.primary,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
            tabs: [
              Tab(text: 'Todas (${_all.length})'),
              Tab(text: 'Incidencias ($_incidenciasCount)'),
              Tab(text: 'Eventos ($_eventosCount)'),
            ],
          ),
          const Divider(height: 1),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_none, size: 56, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('Sin notificaciones',
                                style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        itemCount: filtered.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          // Botón "Cargar más" al final
                          if (index == filtered.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: _isLoadingMore
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2))
                                    : TextButton.icon(
                                        onPressed: _loadMore,
                                        icon: const Icon(Icons.expand_more, size: 16),
                                        label: const Text('Cargar más',
                                            style: TextStyle(fontSize: 13)),
                                      ),
                              ),
                            );
                          }

                          final n = filtered[index];
                          final isUnread = !(n['is_read'] ?? true);
                          final type = n['type'] as String? ?? '';
                          final meta = (n['metadata'] as Map<String, dynamic>?) ?? {};
                          final priority = meta['priority'] as String? ?? 'Normal';
                          final style = _typeStyle(type, priority);

                          return Dismissible(
                            key: Key(n['id']),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              decoration: BoxDecoration(
                                color: Colors.red.shade400,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.delete_outline, color: Colors.white),
                            ),
                            onDismissed: (_) => _delete(n),
                            child: Card(
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
                                contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                                onTap: () => _handleTap(n),
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor:
                                      isUnread ? style.color : Colors.grey[200],
                                  child: Icon(style.icon,
                                      color: isUnread ? Colors.white : Colors.grey[500],
                                      size: 18),
                                ),
                                title: Text(n['title'] ?? '',
                                    style: TextStyle(
                                        fontWeight:
                                            isUnread ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 13)),
                                subtitle: _buildSubtitle(n),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isUnread)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.only(right: 4),
                                        decoration: const BoxDecoration(
                                            color: Colors.red, shape: BoxShape.circle),
                                      ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline,
                                          size: 18, color: Colors.grey[400]),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 32, minHeight: 32),
                                      onPressed: () => _delete(n),
                                      tooltip: 'Eliminar',
                                    ),
                                  ],
                                ),
                              ),
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
