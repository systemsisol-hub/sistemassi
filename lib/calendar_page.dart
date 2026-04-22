import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'calendar_event_form_dialog.dart';
import 'calendar_event_search_dialog.dart';

class CalendarPage extends StatefulWidget {
  final String? initialEventId;
  const CalendarPage({super.key, this.initialEventId});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final CalendarController _calendarController = CalendarController();

  int _calendarMode = 0;
  late EventDataSource _dataSource;
  bool _isLoading = true;
  CalendarView _currentView = CalendarView.month;
  DateTime _currentDisplayDate = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _dataSource = EventDataSource([]);
    _fetchEvents();

    if (widget.initialEventId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showEventDetails(widget.initialEventId!);
      });
    }
  }

  void _showEventDetails(String eventId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EventFormDialog(eventId: eventId),
    ).then((_) => _fetchEvents());
  }

  void _onViewChanged(ViewChangedDetails details) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final view = _calendarController.view ?? CalendarView.month;
      final date = details.visibleDates[details.visibleDates.length ~/ 2];

      bool shouldUpdate = false;
      if (_currentView != view) {
        _currentView = view;
        shouldUpdate = true;
      }
      if (_currentDisplayDate.month != date.month ||
          _currentDisplayDate.year != date.year) {
        _currentDisplayDate = date;
        shouldUpdate = true;
      }

      if (shouldUpdate) {
        setState(() {});
      }
    });
  }

  Future<void> _fetchEvents() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Get followed users first
      Set<String> followedUserIds = {};
      if (_calendarMode == 0) {
        final subscriptions = await _supabase
            .from('calendar_subscriptions')
            .select('followed_user_id')
            .eq('subscriber_id', userId)
            .eq('is_active', true);

        followedUserIds = {
          for (var s in subscriptions) s['followed_user_id'] as String
        };
      }

      // Fetch events based on calendar mode
      List<dynamic> response = [];
      if (_calendarMode == 1) {
        // Grupal - only public events
        response = await _supabase
            .from('events')
            .select('*, profiles(full_name, id)')
            .eq('is_public', true)
            .order('start_time');
      } else {
        // Personal - user's own events (private)
        final myEvents = await _supabase
            .from('events')
            .select('*, profiles(full_name, id)')
            .eq('creator_id', userId)
            .eq('is_public', false)
            .order('start_time');
        response = [...myEvents];

        // Also get followed users' events (both private and public)
        if (followedUserIds.isNotEmpty) {
          for (var followedId in followedUserIds) {
            final followedEvents = await _supabase
                .from('events')
                .select('*, profiles(full_name, id)')
                .eq('creator_id', followedId)
                .order('start_time');
            response = [...response, ...followedEvents];
          }
        }
      }

      final List<Appointment> loadedEvents = [];
      for (var ev in response) {
        final startTime = DateTime.parse(ev['start_time']).toLocal();
        final endTime = DateTime.parse(ev['end_time']).toLocal();
        final isAllDay = (endTime.difference(startTime).inHours >= 24);
        final creatorName = ev['profiles']?['full_name'] ?? 'Usuario';
        final creatorId = ev['profiles']?['id'] as String?;
        final isFollowedUser =
            creatorId != null && followedUserIds.contains(creatorId);

        final priority = ev['priority'] ?? 'Normal';
        Color eventColor;
        if (priority == 'Alta') {
          eventColor = Colors.red.shade700;
        } else if (isFollowedUser) {
          eventColor = _getUserColor(creatorId!);
        } else {
          eventColor =
              _calendarMode == 1 ? Colors.green.shade600 : Colors.blue.shade500;
        }

        loadedEvents.add(Appointment(
          id: ev['id'],
          startTime: startTime,
          endTime: endTime,
          subject: ev['title'],
          notes: '${ev['description'] ?? ''}\nCreado por: $creatorName',
          color: eventColor,
          isAllDay: isAllDay,
        ));
      }

      if (mounted) {
        _dataSource.updateAppointments(loadedEvents);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching events: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Color _getUserColor(String userId) {
    final hash = userId.hashCode;
    final colors = [
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
      Colors.lime,
    ];
    return colors[hash.abs() % colors.length];
  }

  void _showAddEventDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EventFormDialog(
        initialDate: _calendarController.selectedDate ?? DateTime.now(),
        isPublic: _calendarMode == 1,
      ),
    ).then((_) => _fetchEvents());
  }

  void _onAppointmentTap(CalendarTapDetails details) {
    if (details.targetElement == CalendarElement.appointment) {
      final Appointment appointment = details.appointments!.first;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) =>
            EventFormDialog(eventId: appointment.id.toString()),
      ).then((_) => _fetchEvents());
    } else if (details.targetElement == CalendarElement.calendarCell) {
      setState(() {
        _selectedDate = details.date!;
      });
    }
  }

  String get _bottomLeftButtonText {
    if (_currentView == CalendarView.month) return 'Día';
    if (_currentView == CalendarView.day) return 'Sem';
    if (_currentView == CalendarView.week) return 'Mes';
    return 'Día';
  }

  void _onBottomLeftButtonPressed() {
    setState(() {
      if (_currentView == CalendarView.month) {
        _calendarController.displayDate = DateTime.now();
        _calendarController.view = CalendarView.day;
      } else if (_currentView == CalendarView.day) {
        _calendarController.view = CalendarView.week;
      } else if (_currentView == CalendarView.week) {
        _calendarController.view = CalendarView.month;
      }
    });
  }

  void _showMonthsGrid() {
    int selectedYear = _currentDisplayDate.year;
    final months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic'
    ];

    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () {
                          setModalState(() {
                            selectedYear--;
                          });
                        },
                      ),
                      Text(selectedYear.toString(),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () {
                          setModalState(() {
                            selectedYear++;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: 12,
                    itemBuilder: (context, index) {
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.pop(context);
                            setState(() {
                              _currentView = CalendarView.month;
                              _calendarController.view = CalendarView.month;
                              _calendarController.displayDate =
                                  DateTime(selectedYear, index + 1, 1);
                            });
                          },
                          child: Center(
                            child: Text(months[index],
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w500)),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          });
        });
  }

  Widget _buildGlassPill({required Widget child, EdgeInsetsGeometry? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]),
          child: child,
        ),
      ),
    );
  }

  Widget _buildSideAgenda(double width) {
    final appointments = _dataSource.appointments ?? [];
    final selectedEvents = appointments.where((app) {
      final appointment = app as Appointment;
      return appointment.startTime.year == _selectedDate.year &&
          appointment.startTime.month == _selectedDate.month &&
          appointment.startTime.day == _selectedDate.day;
    }).toList();

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(-5, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE', 'es').format(_selectedDate).toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade500,
                      letterSpacing: 1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('d MMMM, yyyy', 'es').format(_selectedDate),
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: selectedEvents.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_available,
                            size: 64, color: Colors.grey.shade200),
                        const SizedBox(height: 16),
                        Text('Sin eventos planeados',
                            style: TextStyle(
                                color: Colors.grey.shade400,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: selectedEvents.length,
                    itemBuilder: (context, index) {
                      final app = selectedEvents[index] as Appointment;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade100),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _showEventDetails(app.id.toString()),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: app.color,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          app.subject,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Colors.black87),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${DateFormat('HH:mm', 'es').format(app.startTime)} - ${DateFormat('HH:mm', 'es').format(app.endTime)}',
                                          style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500),
                                        ),
                                        if (app.notes != null &&
                                            app.notes!.contains('Creado por:'))
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              app.notes!
                                                  .split('\n')
                                                  .last
                                                  .replaceAll(
                                                      'Creado por: ', ''),
                                              style: TextStyle(
                                                  color: Colors.grey.shade500,
                                                  fontSize: 12),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right,
                                      color: Colors.grey.shade300, size: 20),
                                ],
                              ),
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

  @override
  Widget build(BuildContext context) {
    final currentYear = _currentDisplayDate.year;
    final monthsNames = [
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
    final currentMonthName = monthsNames[_currentDisplayDate.month - 1];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 800;

            return Column(
              children: [
                // Top Navigation Bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildGlassPill(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: _showMonthsGrid,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0, vertical: 4.0),
                                child: Text(
                                  '$currentYear',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87),
                                ),
                              ),
                            ),
                            Container(
                                width: 1,
                                height: 16,
                                color: Colors.grey.withOpacity(0.2)),
                            GestureDetector(
                              onTap: _onBottomLeftButtonPressed,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0, vertical: 4.0),
                                child: Text(
                                  _bottomLeftButtonText,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildGlassPill(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Vista Toggle Icon
                            GestureDetector(
                              onTap: () {
                                setState(() => _calendarMode =
                                    (_calendarMode == 0 ? 1 : 0));
                                _fetchEvents();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    shape: BoxShape.circle),
                                child: Icon(
                                    _calendarMode == 0
                                        ? Icons.groups
                                        : Icons.person,
                                    color: Colors.black87,
                                    size: 20),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                                width: 1,
                                height: 20,
                                color: Colors.grey.withOpacity(0.2)),
                            const SizedBox(width: 4),
                            // Search
                            GestureDetector(
                              onTap: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) => EventSearchDialog(
                                      calendarMode: _calendarMode),
                                ).then((_) => _fetchEvents());
                              },
                              child: const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Icon(Icons.search,
                                      color: Colors.black87, size: 22)),
                            ),
                            const SizedBox(width: 4),
                            // Add
                            GestureDetector(
                              onTap: _showAddEventDialog,
                              child: const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Icon(Icons.add,
                                      color: Colors.black87, size: 22)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Month Title
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24.0, vertical: 8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      currentMonthName,
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                    ),
                  ),
                ),

                // Main Content Area
                Expanded(
                  child: Row(
                    children: [
                      // Left Side: Calendar
                      Expanded(
                        child: Stack(
                          children: [
                            SfCalendar(
                              key: ValueKey('calendar_$isDesktop'),
                              controller: _calendarController,
                              view: CalendarView.month,
                              onViewChanged: _onViewChanged,
                              allowedViews: const [
                                CalendarView.day,
                                CalendarView.week,
                                CalendarView.month
                              ],
                              dataSource: _dataSource,
                              onTap: _onAppointmentTap,
                              headerHeight: 0,
                              cellBorderColor: Colors.transparent,
                              viewHeaderStyle: const ViewHeaderStyle(
                                dayTextStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey),
                              ),
                              monthViewSettings: MonthViewSettings(
                                dayFormat: 'EEEEE',
                                showAgenda: !isDesktop, // Only mobile agenda
                                showTrailingAndLeadingDates: false,
                                appointmentDisplayMode:
                                    MonthAppointmentDisplayMode.indicator,
                              ),
                              timeSlotViewSettings: const TimeSlotViewSettings(
                                  startHour: 0, endHour: 24),
                              monthCellBuilder: (context, details) {
                                final isSelected = details.date.year ==
                                        _selectedDate.year &&
                                    details.date.month == _selectedDate.month &&
                                    details.date.day == _selectedDate.day;
                                final isToday =
                                    details.date.year == DateTime.now().year &&
                                        details.date.month ==
                                            DateTime.now().month &&
                                        details.date.day == DateTime.now().day;

                                if (details.date.month !=
                                    _currentDisplayDate.month)
                                  return const SizedBox.shrink();

                                return Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                        top: BorderSide(
                                            color: Colors.grey.shade100)),
                                    color: isSelected && isDesktop
                                        ? Colors.blue.shade50.withOpacity(0.5)
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(height: 2),
                                      Center(
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: isToday
                                                ? Colors.redAccent
                                                : Colors.transparent,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            details.date.day.toString(),
                                            style: TextStyle(
                                              color: isToday
                                                  ? Colors.white
                                                  : Colors.black87,
                                              fontWeight: isToday
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (isDesktop &&
                                          details.appointments.isNotEmpty)
                                        Flexible(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: details.appointments
                                                .take(1)
                                                .map((app) {
                                              final ap = app as Appointment;
                                              return Container(
                                                width: double.infinity,
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 2,
                                                        vertical: 1),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                        vertical: 1),
                                                decoration: BoxDecoration(
                                                    color: ap.color,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            2)),
                                                child: Text(
                                                  ap.subject,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 8,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                              selectionDecoration: BoxDecoration(
                                color: Colors.transparent,
                                border: Border.all(
                                    color: Colors.blue.withOpacity(0.5),
                                    width: 2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            if (_isLoading)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.white.withOpacity(0.5),
                                  child: Center(
                                    child: Image.asset(
                                        'assets/sisol_loader.gif',
                                        width: 100,
                                        errorBuilder: (_, __, ___) =>
                                            const CircularProgressIndicator()),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Right Side: Desktop Agenda
                      if (isDesktop) _buildSideAgenda(380),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabIcon(IconData icon, int mode) {
    return const SizedBox.shrink(); // Obsolete
  }
}

class EventDataSource extends CalendarDataSource {
  EventDataSource(List<Appointment> source) {
    appointments = source;
  }

  void updateAppointments(List<Appointment> newAppointments) {
    appointments = newAppointments;
    notifyListeners(CalendarDataSourceAction.reset, newAppointments);
  }
}
