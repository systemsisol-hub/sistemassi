import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'calendar_event_form_dialog.dart';
import 'calendar_event_search_dialog.dart';
import 'theme/si_theme.dart';
import 'widgets/boton_flotante.dart';

class CalendarPage extends StatefulWidget {
  final String? initialEventId;
  const CalendarPage({super.key, this.initialEventId});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final CalendarController _calendarController = CalendarController();

  int _calendarMode = 0; // 0=personal+seguidos, 1=grupal
  late EventDataSource _dataSource;
  bool _isLoading = true;
  CalendarView _currentView = CalendarView.month;
  DateTime _currentDisplayDate = DateTime.now();
  DateTime _selectedDate = DateTime.now();

  // ── Index helpers ──────────────────────────────────────────────────────────

  // Toggle: 0=Grupal, 1=Personal → maps from _calendarMode
  int get _toggleModeIndex => _calendarMode == 1 ? 0 : 1;

  int get _viewIndex {
    switch (_currentView) {
      case CalendarView.month:
        return 0;
      case CalendarView.week:
        return 1;
      case CalendarView.day:
        return 2;
      case CalendarView.schedule:
        return 3;
      default:
        return 0;
    }
  }

  void _setViewByIndex(int idx) {
    const views = [
      CalendarView.month,
      CalendarView.week,
      CalendarView.day,
      CalendarView.schedule,
    ];
    _calendarController.view = views[idx.clamp(0, 3)];
  }

  String get _displayTitle {
    const monthsNames = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    const monthAbbr = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
    ];
    final m = _currentDisplayDate.month - 1;
    final y = _currentDisplayDate.year;
    switch (_currentView) {
      case CalendarView.week:
        return '${monthAbbr[m]} $y';
      case CalendarView.day:
        return DateFormat('EEEE, d MMM yyyy', 'es').format(_currentDisplayDate);
      case CalendarView.schedule:
        return '${monthsNames[m]} $y';
      default:
        return '${monthsNames[m]} $y';
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _dataSource = EventDataSource([]);
    // Hoy elegido de entrada: en el teléfono la lista de abajo decía «Sin fecha seleccionada».
    _calendarController.selectedDate = _selectedDate;
    _fetchEvents();

    if (widget.initialEventId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showEventDetails(widget.initialEventId!);
      });
    }
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _fetchEvents() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

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

      List<dynamic> response = [];
      if (_calendarMode == 1) {
        response = await _supabase
            .from('events')
            .select('*, profiles(full_name, id)')
            .eq('is_public', true)
            .order('start_time', ascending: true);
      } else {
        final myEvents = await _supabase
            .from('events')
            .select('*, profiles(full_name, id)')
            .eq('creator_id', userId)
            .eq('is_public', false)
            .order('start_time', ascending: true);
        response = [...myEvents];

        if (followedUserIds.isNotEmpty) {
          for (var followedId in followedUserIds) {
            final followedEvents = await _supabase
                .from('events')
                .select('*, profiles(full_name, id)')
                .eq('creator_id', followedId)
                .order('start_time', ascending: true);
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
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching events: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getUserColor(String userId) {
    final hash = userId.hashCode;
    final colors = [
      Colors.orange, Colors.purple, Colors.teal, Colors.pink,
      Colors.indigo, Colors.amber, Colors.cyan, Colors.lime,
    ];
    return colors[hash.abs() % colors.length];
  }

  // ── Calendar callbacks ─────────────────────────────────────────────────────

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
      if (shouldUpdate) setState(() {});
    });
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
      setState(() => _selectedDate = details.date!);
    }
  }

  // ── Navigation helpers ─────────────────────────────────────────────────────

  void _prevPeriod() {
    final d = _currentDisplayDate;
    switch (_currentView) {
      case CalendarView.week:
        _calendarController.displayDate = d.subtract(const Duration(days: 7));
        break;
      case CalendarView.day:
        _calendarController.displayDate = d.subtract(const Duration(days: 1));
        break;
      default:
        _calendarController.displayDate = DateTime(d.year, d.month - 1);
    }
  }

  void _nextPeriod() {
    final d = _currentDisplayDate;
    switch (_currentView) {
      case CalendarView.week:
        _calendarController.displayDate = d.add(const Duration(days: 7));
        break;
      case CalendarView.day:
        _calendarController.displayDate = d.add(const Duration(days: 1));
        break;
      default:
        _calendarController.displayDate = DateTime(d.year, d.month + 1);
    }
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showEventDetails(String eventId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EventFormDialog(eventId: eventId),
    ).then((_) => _fetchEvents());
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

  void _showMonthsGrid() {
    final c = SiColors.of(context);
    int selectedYear = _currentDisplayDate.year;
    const months = [
      'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
      'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: c.panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(Icons.chevron_left, color: c.ink),
                        onPressed: () => setModalState(() => selectedYear--),
                      ),
                      Text(selectedYear.toString(),
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: c.ink)),
                      IconButton(
                        icon: Icon(Icons.chevron_right, color: c.ink),
                        onPressed: () => setModalState(() => selectedYear++),
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
                          color: c.hover,
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
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: c.ink)),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── UI components ──────────────────────────────────────────────────────────

  Widget _buildSegmentedToggle(
    SiColors c,
    List<String> labels,
    int selected,
    void Function(int) onTap, {
    bool compact = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: c.hover,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (i) {
          final isSelected = i == selected;
          return GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 14,
                vertical: compact ? 5 : 7,
              ),
              decoration: BoxDecoration(
                color: isSelected ? c.panel : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1))
                      ]
                    : null,
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: compact ? 12 : 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? c.ink : c.ink3,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildLegend(SiColors c) {
    final items = _calendarMode == 1
        ? [
            _LegendItem('Grupal', Colors.green.shade600),
            _LegendItem('Alta prio.', Colors.red.shade700),
          ]
        : [
            _LegendItem('Propios', Colors.blue.shade500),
            _LegendItem('Seguidos', Colors.orange),
            _LegendItem('Alta prio.', Colors.red.shade700),
          ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: items
          .map((item) => Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: item.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(item.label,
                        style: TextStyle(
                            fontSize: 11,
                            color: c.ink3,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  /// Tarjeta con los datos del evento al pasar el ratón por encima (web y tablet con ratón). En
  /// pantallas táctiles no se activa: ahí se toca el evento y se abre su detalle.
  Widget _conDetalle(SiColors c, Appointment ap, Widget child) {
    final notas = (ap.notes ?? '').split('\n');
    final creador = notas
        .where((l) => l.startsWith('Creado por:'))
        .map((l) => l.replaceAll('Creado por:', '').trim())
        .firstOrNull;
    var descripcion =
        notas.where((l) => !l.startsWith('Creado por:')).join('\n').trim();
    if (descripcion.length > 240) descripcion = '${descripcion.substring(0, 240)}…';

    final dia = DateFormat("EEE d 'de' MMM", 'es');
    final hora = DateFormat('HH:mm');
    final mismoDia = ap.startTime.year == ap.endTime.year &&
        ap.startTime.month == ap.endTime.month &&
        ap.startTime.day == ap.endTime.day;
    final cuando = ap.isAllDay
        ? (mismoDia
            ? '${dia.format(ap.startTime)} · Todo el día'
            : '${dia.format(ap.startTime)} – ${dia.format(ap.endTime)}')
        : mismoDia
            ? '${dia.format(ap.startTime)} · ${hora.format(ap.startTime)} – ${hora.format(ap.endTime)}'
            : '${dia.format(ap.startTime)} ${hora.format(ap.startTime)} – ${dia.format(ap.endTime)} ${hora.format(ap.endTime)}';

    return Tooltip(
      triggerMode: TooltipTriggerMode.manual,
      waitDuration: const Duration(milliseconds: 300),
      preferBelow: true,
      padding: const EdgeInsets.all(12),
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      richMessage: TextSpan(
        style: TextStyle(fontSize: 12, color: c.ink2, height: 1.4),
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: ap.color, shape: BoxShape.circle),
            ),
          ),
          TextSpan(
              text: ap.subject,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
          TextSpan(text: '\n$cuando'),
          if (creador != null && creador.isNotEmpty)
            TextSpan(
                text: '\nCreado por $creador',
                style: TextStyle(color: c.ink3)),
          if (descripcion.isNotEmpty) TextSpan(text: '\n\n$descripcion'),
        ],
      ),
      child: child,
    );
  }

  /// Panel derecho del diseño ancho (web y tablet): los eventos del día elegido en la cuadrícula
  /// (hoy al entrar) y debajo los próximos. Antes solo tenía los próximos: si los eventos del mes
  /// ya habían pasado, el panel salía vacío y al elegir un día no había dónde ver los suyos.
  Widget _buildSideAgenda(SiColors c, double width) {
    final now = DateTime.now();
    final appointments = List<Appointment>.from(_dataSource.appointments ?? []);
    final diaIni = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final diaFin = diaIni.add(const Duration(days: 1));
    final delDia = appointments
        .where((a) => a.startTime.isBefore(diaFin) && a.endTime.isAfter(diaIni))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final upcoming = appointments
        .where((a) => !a.endTime.isBefore(now) && !delDia.contains(a))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final toShow = upcoming.take(10).toList();

    const monthsAbbr = [
      'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN',
      'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'
    ];
    final esHoy = diaIni == DateTime(now.year, now.month, now.day);
    final tituloDia = esHoy
        ? 'HOY'
        : DateFormat("EEEE d 'de' MMMM", 'es').format(diaIni).toUpperCase();

    Widget encabezado(String texto, int cuantos) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  texto,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: c.ink3,
                      letterSpacing: 1.5),
                ),
              ),
              if (cuantos > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$cuantos',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: c.brand),
                  ),
                ),
            ],
          ),
        );

    Widget vacio(String texto) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(texto,
              style: TextStyle(
                  color: c.ink3, fontSize: 13, fontStyle: FontStyle.italic)),
        );

    Widget evento(Appointment app) {
      final monthAbbr = monthsAbbr[app.startTime.month - 1];
      final notes = app.notes ?? '';
      final creatorLine = notes
          .split('\n')
          .where((l) => l.startsWith('Creado por:'))
          .firstOrNull;
      final creatorName = creatorLine?.replaceAll('Creado por: ', '').trim();

      return _conDetalle(c, app, InkWell(
        onTap: () => _showEventDetails(app.id.toString()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      monthAbbr,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: app.color,
                          letterSpacing: 0.5),
                    ),
                    Text(
                      app.startTime.day.toString(),
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: c.ink,
                          height: 1.1),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.subject,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.ink),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('HH:mm', 'es').format(app.startTime) +
                          (creatorName != null ? ' · $creatorName' : ''),
                      style: TextStyle(fontSize: 11, color: c.ink3),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ));
    }

    List<Widget> lista(List<Appointment> apps) => [
          for (var i = 0; i < apps.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: c.line, indent: 24, endIndent: 24),
            evento(apps[i]),
          ],
        ];

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(left: BorderSide(color: c.line)),
      ),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          encabezado(tituloDia, delDia.length),
          if (delDia.isEmpty)
            vacio('Sin eventos este día')
          else
            ...lista(delDia),
          Divider(height: 1, color: c.line),
          encabezado('PRÓXIMOS EVENTOS', toShow.length),
          if (toShow.isEmpty)
            vacio('Sin próximos eventos')
          else
            ...lista(toShow),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    const monthsNames = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    final currentMonthName = monthsNames[_currentDisplayDate.month - 1];
    final subtitle = _calendarMode == 1
        ? 'Eventos de tu equipo y usuarios que sigues.'
        : 'Tus eventos y calendarios personales.';

    return Scaffold(
      backgroundColor: c.bg,
      floatingActionButton: esPantallaTelefono(context)
          ? BotonFlotanteNuevo(
              onPressed: _showAddEventDialog,
              tooltip: 'Nuevo evento',
            )
          : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 800;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── TOP HEADER ───────────────────────────────────────────────
                Container(
                  color: c.bg,
                  padding: EdgeInsets.fromLTRB(24, 16, 24, isDesktop ? 12 : 8),
                  child: isDesktop
                      ? Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Calendario',
                                    style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: c.ink)),
                                const SizedBox(height: 2),
                                Text(
                                  '$currentMonthName ${_currentDisplayDate.year} · $subtitle',
                                  style: TextStyle(
                                      fontSize: 12, color: c.ink3),
                                ),
                              ],
                            ),
                            const Spacer(),
                            _buildSegmentedToggle(
                              c,
                              ['Grupal', 'Personal'],
                              _toggleModeIndex,
                              (idx) {
                                setState(() =>
                                    _calendarMode = idx == 0 ? 1 : 0);
                                _fetchEvents();
                              },
                            ),
                            const SizedBox(width: 10),
                            _buildSegmentedToggle(
                              c,
                              ['Mes', 'Semana', 'Día', 'Agenda'],
                              _viewIndex,
                              _setViewByIndex,
                              compact: true,
                            ),
                            const SizedBox(width: 10),
                            // Search
                            IconButton(
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) => EventSearchDialog(
                                      calendarMode: _calendarMode),
                                ).then((_) => _fetchEvents());
                              },
                              icon: Icon(Icons.search, color: c.ink3, size: 20),
                              tooltip: 'Buscar',
                              constraints: const BoxConstraints(
                                  minWidth: 36, minHeight: 36),
                              padding: EdgeInsets.zero,
                            ),
                            const SizedBox(width: 4),
                            FilledButton.icon(
                              onPressed: _showAddEventDialog,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Nuevo evento',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              style: FilledButton.styleFrom(
                                backgroundColor: c.brand,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        )
                      // Mobile header
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Calendario',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: c.ink)),
                            Row(
                              children: [
                                _buildSegmentedToggle(
                                  c,
                                  ['Grupal', 'Personal'],
                                  _toggleModeIndex,
                                  (idx) {
                                    setState(() =>
                                        _calendarMode = idx == 0 ? 1 : 0);
                                    _fetchEvents();
                                  },
                                  compact: true,
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (context) => EventSearchDialog(
                                          calendarMode: _calendarMode),
                                    ).then((_) => _fetchEvents());
                                  },
                                  icon:
                                      Icon(Icons.search, color: c.ink3, size: 20),
                                  constraints: const BoxConstraints(
                                      minWidth: 36, minHeight: 36),
                                  padding: EdgeInsets.zero,
                                ),
                                // En el telefono el «+» es el boton flotante.
                                if (!esPantallaTelefono(context)) ...[
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: _showAddEventDialog,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                          color: c.brand,
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: const Icon(Icons.add,
                                          size: 18, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                ),

                // ── CALENDAR NAV BAR ─────────────────────────────────────────
                Container(
                  color: c.bg,
                  padding: const EdgeInsets.fromLTRB(12, 0, 16, 10),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _prevPeriod,
                        icon: Icon(Icons.chevron_left, color: c.ink3),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                      ),
                      GestureDetector(
                        onTap: _showMonthsGrid,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            _displayTitle,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: c.ink),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _nextPeriod,
                        icon: Icon(Icons.chevron_right, color: c.ink3),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _calendarController.displayDate = DateTime.now();
                            _selectedDate = DateTime.now();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            border: Border.all(color: c.line),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('Hoy',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: c.ink)),
                        ),
                      ),
                      const Spacer(),
                      if (isDesktop) _buildLegend(c),
                    ],
                  ),
                ),

                Divider(height: 1, color: c.line),

                // ── MAIN CONTENT ─────────────────────────────────────────────
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            SfCalendarTheme(
                              data: SfCalendarThemeData(
                                backgroundColor: c.bg,
                                headerBackgroundColor: c.bg,
                                viewHeaderBackgroundColor: c.bg,
                                agendaBackgroundColor: c.panel,
                                allDayPanelColor: c.panel,
                                cellBorderColor: c.line,
                                activeDatesBackgroundColor: c.bg,
                                todayBackgroundColor: c.brand,
                                trailingDatesBackgroundColor: c.bg,
                                leadingDatesBackgroundColor: c.bg,
                                selectionBorderColor: Colors.transparent,
                                todayHighlightColor: c.brand,
                                viewHeaderDayTextStyle: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: c.ink3,
                                    letterSpacing: 0.5),
                                viewHeaderDateTextStyle:
                                    TextStyle(color: c.ink, fontSize: 11),
                                activeDatesTextStyle:
                                    TextStyle(color: c.ink, fontSize: 12),
                                todayTextStyle: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12),
                                trailingDatesTextStyle:
                                    TextStyle(color: c.ink4, fontSize: 12),
                                leadingDatesTextStyle:
                                    TextStyle(color: c.ink4, fontSize: 12),
                                timeTextStyle:
                                    TextStyle(color: c.ink3, fontSize: 11),
                                timeIndicatorTextStyle:
                                    TextStyle(color: c.brand, fontSize: 10),
                                agendaDayTextStyle: TextStyle(
                                    color: c.ink,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 22),
                                agendaDateTextStyle:
                                    TextStyle(color: c.ink3, fontSize: 11),
                                weekNumberBackgroundColor: c.hover,
                                weekNumberTextStyle:
                                    TextStyle(color: c.ink3, fontSize: 11),
                              ),
                              child: SfCalendar(
                              key: ValueKey('calendar_$isDesktop'),
                              controller: _calendarController,
                              view: CalendarView.month,
                              onViewChanged: _onViewChanged,
                              allowedViews: const [
                                CalendarView.day,
                                CalendarView.week,
                                CalendarView.month,
                                CalendarView.schedule,
                              ],
                              dataSource: _dataSource,
                              onTap: _onAppointmentTap,
                              headerHeight: 0,
                              cellBorderColor: Colors.transparent,
                              backgroundColor: c.bg,
                              todayHighlightColor: c.brand,
                              selectionDecoration:
                                  const BoxDecoration(color: Colors.transparent),
                              monthViewSettings: MonthViewSettings(
                                dayFormat: 'EEE',
                                showAgenda: !isDesktop,
                                showTrailingAndLeadingDates: false,
                                appointmentDisplayMode:
                                    MonthAppointmentDisplayMode.none,
                                agendaStyle: AgendaStyle(
                                  backgroundColor: c.panel,
                                  // Blanco como en las etiquetas del mes: el fondo es el color del
                                  // evento y el texto oscuro casi no se leía sobre el verde.
                                  appointmentTextStyle: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                  dateTextStyle:
                                      TextStyle(color: c.ink3, fontSize: 11),
                                  dayTextStyle: TextStyle(
                                      color: c.ink,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 22),
                                ),
                              ),
                              timeSlotViewSettings: TimeSlotViewSettings(
                                  startHour: 0,
                                  endHour: 24,
                                  timeTextStyle:
                                      TextStyle(color: c.ink3, fontSize: 11)),
                              monthCellBuilder: (context, details) {
                                final isSelected =
                                    details.date.year == _selectedDate.year &&
                                        details.date.month ==
                                            _selectedDate.month &&
                                        details.date.day == _selectedDate.day;
                                final isToday =
                                    details.date.year == DateTime.now().year &&
                                        details.date.month ==
                                            DateTime.now().month &&
                                        details.date.day == DateTime.now().day;

                                if (details.date.month !=
                                    _currentDisplayDate.month) {
                                  return const SizedBox.shrink();
                                }

                                return ClipRect(
                                  child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                        top: BorderSide(color: c.line)),
                                    color: isSelected && isDesktop
                                        ? c.brand.withValues(alpha: 0.06)
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(height: 4),
                                      Center(
                                        child: Container(
                                          width: 26,
                                          height: 26,
                                          decoration: BoxDecoration(
                                            color: isToday
                                                ? c.brand
                                                : Colors.transparent,
                                            shape: BoxShape.circle,
                                            // En el teléfono la lista de abajo es la del día
                                            // elegido: sin este aro no se sabía de qué día era.
                                            border: isSelected && !isToday && !isDesktop
                                                ? Border.all(color: c.brand, width: 1.5)
                                                : null,
                                          ),
                                          child: Center(
                                            child: Text(
                                              details.date.day.toString(),
                                              style: TextStyle(
                                                color: isToday
                                                    ? Colors.white
                                                    : c.ink,
                                                fontWeight: isToday
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (details.appointments.isNotEmpty)
                                        Flexible(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            // En el teléfono uno y «+N»: con dos etiquetas la celda
                                            // se desbordaba. Todos se ven en la lista del día.
                                            children: [
                                              ...details.appointments
                                                .take(isDesktop ? 2 : 1)
                                                .map((app) {
                                              final ap = app as Appointment;
                                              final chip = Container(
                                                width: double.infinity,
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 3,
                                                        vertical: 1),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                        vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: ap.color
                                                      .withValues(alpha: 0.9),
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                ),
                                                child: Text(
                                                  '${DateFormat('HH:mm').format(ap.startTime)} ${ap.subject}',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w600),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              );
                                              return isDesktop
                                                  ? _conDetalle(c, ap, chip)
                                                  : chip;
                                            }),
                                              if (details.appointments.length > (isDesktop ? 2 : 1))
                                                Text(
                                                  '+${details.appointments.length - (isDesktop ? 2 : 1)}',
                                                  style: TextStyle(
                                                      color: c.ink3,
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.w600),
                                                ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  ),
                                );
                              },
                            ), // SfCalendar
                            ), // SfCalendarTheme
                            if (_isLoading)
                              Positioned.fill(
                                child: Container(
                                  color: c.bg.withValues(alpha: 0.7),
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
                      if (isDesktop) _buildSideAgenda(c, 320),
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
}

// ── Data ────────────────────────────────────────────────────────────────────

class _LegendItem {
  final String label;
  final Color color;
  const _LegendItem(this.label, this.color);
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
