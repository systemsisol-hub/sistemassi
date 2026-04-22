import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'calendar_event_form_dialog.dart';

class EventSearchDialog extends StatefulWidget {
  final int calendarMode;

  const EventSearchDialog({super.key, required this.calendarMode});

  @override
  State<EventSearchDialog> createState() => _EventSearchDialogState();
}

class _EventSearchDialogState extends State<EventSearchDialog>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  late TabController _tabController;
  bool _isAdmin = false;
  bool _isLoading = true;
  bool _isSaving = false;

  List<dynamic> _searchResults = [];
  List<dynamic> _users = [];
  Map<String, bool> _subscriptions = {}; // userId -> isActive

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  Future<void> _init() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        final profile = await _supabase
            .from('profiles')
            .select('role')
            .eq('id', userId)
            .single();

        _isAdmin = profile['role'] == 'admin';

        if (_isAdmin) {
          await _loadUsers();
          await _loadSubscriptions();
        }
      }
    } catch (e) {
      debugPrint('Error initializing: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadUsers() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;

      final users = await _supabase
          .from('profiles')
          .select('id, full_name, email, permissions, role')
          .eq('status_sys', 'ACTIVO')
          .eq('permissions->>show_calendar', 'true')
          .neq('id', currentUserId ?? '')
          .order('full_name');

      final usersWithEventCount =
          await Future.wait((users as List).map((user) async {
        final eventCount = await _supabase
            .from('events')
            .select('id')
            .eq('creator_id', user['id'])
            .count(CountOption.exact);

        user['event_count'] = eventCount.count;
        return user;
      }));

      if (mounted) {
        setState(() {
          _users = usersWithEventCount;
        });
      }
    } catch (e) {
      debugPrint('Error loading users: $e');
    }
  }

  Future<void> _loadSubscriptions() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final subs = await _supabase
          .from('calendar_subscriptions')
          .select('followed_user_id, is_active')
          .eq('subscriber_id', userId);

      if (mounted) {
        setState(() {
          _subscriptions = {
            for (var s in subs)
              s['followed_user_id'] as String: s['is_active'] as bool
          };
        });
      }
    } catch (e) {
      debugPrint('Error loading subscriptions: $e');
    }
  }

  void _performSearch(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) setState(() => _searchResults = []);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final isPublic = widget.calendarMode == 1;

      final response = await _supabase
          .from('events')
          .select('id, title, start_time, end_time, location')
          .ilike('title', '%${query.trim()}%')
          .eq('is_public', isPublic)
          .order('start_time', ascending: true)
          .limit(20);

      if (mounted) {
        setState(() {
          _searchResults = response;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error searching events: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<dynamic> get _filteredUsers {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) return _users;
    return _users.where((u) {
      final name =
          (u['full_name'] ?? u['email'] ?? '').toString().toLowerCase();
      return name.contains(query);
    }).toList();
  }

  Future<void> _saveSubscriptions() async {
    setState(() => _isSaving = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('No se encontró usuario');

      for (var user in _users) {
        final userId2 = user['id'] as String;
        final isActive = _subscriptions[userId2] ?? false;

        // Use upsert with onConflict to handle both insert and update
        await _supabase.from('calendar_subscriptions').upsert({
          'subscriber_id': userId,
          'followed_user_id': userId2,
          'is_active': isActive,
        }, onConflict: 'subscriber_id,followed_user_id');
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving subscriptions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Color _getUserColor(String userId) {
    final hash = userId.hashCode;
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
      Colors.cyan
    ];
    return colors[hash.abs() % colors.length];
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 40,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar',
                      style: TextStyle(fontSize: 16, color: Colors.grey)),
                ),
                const Text(
                  'Buscar',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed:
                      _isAdmin ? (_isSaving ? null : _saveSubscriptions) : null,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(
                          'Guardar',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _isAdmin ? Colors.blue : Colors.grey,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isAdmin) ...[
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: theme.colorScheme.primary,
                  unselectedLabelColor: Colors.grey,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  tabs: const [
                    Tab(text: 'Eventos'),
                    Tab(text: 'Usuarios'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _searchController,
              onChanged: (val) {
                if (_isAdmin && _tabController.index == 1) {
                  setState(() {});
                } else {
                  _performSearch(val);
                }
              },
              decoration: InputDecoration(
                hintText: _isAdmin && _tabController.index == 1
                    ? 'Buscar usuario...'
                    : 'Buscar por título...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_isAdmin)
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.5,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildEventsList(),
                    _buildUsersList(),
                  ],
                ),
              )
            else
              _buildEventsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsList() {
    if (_searchController.text.isEmpty) {
      return Center(
        child: Text('Escribe para buscar eventos',
            style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Text('No se encontraron eventos',
            style: TextStyle(color: Colors.grey.shade600)),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final ev = _searchResults[index];
        final startTime = DateTime.parse(ev['start_time']).toLocal();
        final String formattedDate =
            DateFormat('dd MMM yyyy, HH:mm', 'es_MX').format(startTime);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(
              ev['title'] ?? 'Sin título',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(formattedDate,
                        style: const TextStyle(color: Colors.grey)),
                  ],
                ),
                if (ev['location'] != null &&
                    ev['location'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            ev['location'],
                            style: const TextStyle(color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            onTap: () {
              Navigator.pop(context);
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) =>
                    EventFormDialog(eventId: ev['id'].toString()),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildUsersList() {
    if (_filteredUsers.isEmpty) {
      return Center(
        child: Text(
          _searchController.text.isEmpty
              ? 'No hay usuarios con calendario visible'
              : 'No se encontraron usuarios',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: _filteredUsers.length,
      itemBuilder: (context, index) {
        final user = _filteredUsers[index];
        final userId = user['id'] as String;
        final userName = user['full_name'] ?? user['email'] ?? 'Usuario';
        final eventCount = user['event_count'] as int? ?? 0;
        final isActive = _subscriptions[userId] ?? false;
        final color = _getUserColor(userId);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isActive ? color.withOpacity(0.3) : Colors.grey.shade200,
              width: isActive ? 2 : 1,
            ),
          ),
          child: SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            secondary: CircleAvatar(
              backgroundColor: color,
              child: Text(
                userName[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              userName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '$eventCount evento${eventCount == 1 ? '' : 's'}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            value: isActive,
            activeColor: color,
            onChanged: (value) {
              setState(() {
                _subscriptions[userId] = value;
              });
            },
          ),
        );
      },
    );
  }
}
