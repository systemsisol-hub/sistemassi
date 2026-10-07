import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_service.dart';
import '../theme/si_theme.dart';
import 'notification_list_modal.dart' show estiloNotificacion;

/// Globos en la esquina para todo lo que hay que ver en el momento (07/10/2026):
///
///   * «Te faltan N minutos para tu evento»: revisa cada 30 s los eventos que empiezan en los
///     próximos 10 minutos y que son de la persona (los que creó y a los que la invitaron, sin los
///     rechazados). Cada evento avisa una vez por sesión.
///   * Cada notificación nueva de la campana (invitaciones, incidencias, altas y bajas, torneos…),
///     con su ícono y color. Las que ya estaban al abrir la app no salen: esas siguen en la campana.
///
/// Va encima de toda la app (en `MainNavigation`), así sale en cualquier página. Solo con la app
/// abierta: avisar con la app cerrada necesitaría notificaciones push.
class AvisoEventosProximos extends StatefulWidget {
  final void Function(String eventId) onAbrir;

  /// Para filtrar las notificaciones igual que la campana y abrirlas donde corresponde.
  final String role;
  final Map<String, dynamic> permissions;
  final void Function(Map<String, dynamic> notificacion) onAbrirNotificacion;

  const AvisoEventosProximos({
    super.key,
    required this.onAbrir,
    required this.role,
    required this.permissions,
    required this.onAbrirNotificacion,
  });

  @override
  State<AvisoEventosProximos> createState() => _AvisoEventosProximosState();
}

class _Globo {
  final String clave;
  final IconData icono;
  final Color color;
  final String Function() cabecera;
  final String titulo;
  final String? detalle;
  final VoidCallback alTocar;
  _Globo({
    required this.clave,
    required this.icono,
    required this.color,
    required this.cabecera,
    required this.titulo,
    this.detalle,
    required this.alTocar,
  });
}

class _AvisoEventosProximosState extends State<AvisoEventosProximos> {
  static const _anticipacion = Duration(minutes: 10);
  static const _seQuitaSolo = Duration(minutes: 3);
  static const _seQuitaSoloAviso = Duration(seconds: 20);

  /// Si llegan más de estas de golpe (p. ej. una alta masiva), sale un solo globo con el total.
  static const _maxDeGolpe = 3;

  final _avisados = <String>{};
  final _globos = <_Globo>[];
  Timer? _revision;
  Timer? _reloj;
  StreamSubscription<List<Map<String, dynamic>>>? _notificaciones;
  Set<String>? _yaVistas;

  @override
  void initState() {
    super.initState();
    _revisar();
    _revision = Timer.periodic(const Duration(seconds: 30), (_) => _revisar());
    // Para que «faltan N minutos» se actualice mientras el globo está a la vista.
    _reloj = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _globos.isNotEmpty) setState(() {});
    });
    _notificaciones =
        NotificationService.allNotificationsStream.listen(_nuevasNotificaciones);
  }

  @override
  void dispose() {
    _revision?.cancel();
    _reloj?.cancel();
    _notificaciones?.cancel();
    super.dispose();
  }

  void _mostrar(_Globo g, Duration dura) {
    if (!mounted) return;
    setState(() => _globos.add(g));
    Future.delayed(dura, () {
      if (mounted) setState(() => _globos.remove(g));
    });
  }

  // ── Notificaciones de la campana ────────────────────────────────────────────

  bool _laPuedeVer(Map<String, dynamic> n) {
    final tipo = n['type'] as String? ?? '';
    if (tipo == 'collaborator_alert' || tipo == 'status_sys_alert') {
      return widget.role == 'admin' && widget.permissions['show_users'] == true;
    }
    return true;
  }

  void _nuevasNotificaciones(List<Map<String, dynamic>> todas) {
    final ids = {for (final n in todas) n['id'].toString()};
    // La primera lista es lo que ya había al abrir: solo se recuerda.
    if (_yaVistas == null) {
      _yaVistas = ids;
      return;
    }
    final nuevas = todas
        .where((n) =>
            !_yaVistas!.contains(n['id'].toString()) &&
            n['is_read'] != true &&
            _laPuedeVer(n))
        .toList();
    _yaVistas!.addAll(ids);
    if (nuevas.isEmpty) return;

    if (nuevas.length > _maxDeGolpe) {
      _mostrar(
        _Globo(
          clave: 'varias-${DateTime.now().millisecondsSinceEpoch}',
          icono: Icons.notifications_active,
          color: const Color(0xFF344092),
          cabecera: () => 'Notificaciones nuevas',
          titulo: 'Tienes ${nuevas.length} notificaciones nuevas',
          detalle: 'Ábrelas en la campana',
          alTocar: () {},
        ),
        _seQuitaSoloAviso,
      );
      return;
    }
    for (final n in nuevas) {
      final tipo = n['type'] as String? ?? '';
      final meta = (n['metadata'] as Map<String, dynamic>?) ?? {};
      final estilo = estiloNotificacion(tipo, meta['priority'] as String? ?? 'Normal');
      final titulo = (n['title'] as String?)?.trim();
      final mensaje = (n['message'] as String?)?.trim();
      _mostrar(
        _Globo(
          clave: 'n-${n['id']}',
          icono: estilo.icon,
          color: estilo.color,
          cabecera: () => 'Nueva notificación',
          titulo: (titulo?.isNotEmpty == true ? titulo : mensaje) ?? 'Notificación',
          detalle: titulo?.isNotEmpty == true ? mensaje : null,
          alTocar: () => widget.onAbrirNotificacion(n),
        ),
        _seQuitaSoloAviso,
      );
    }
  }

  // ── Eventos que están por empezar ───────────────────────────────────────────

  Future<void> _revisar() async {
    final yo = Supabase.instance.client.auth.currentUser?.id;
    if (yo == null) return;
    final ahora = DateTime.now().toUtc();
    final hasta = ahora.add(_anticipacion);
    try {
      final invitaciones = await Supabase.instance.client
          .from('event_invitations')
          .select('event_id')
          .eq('user_id', yo)
          .neq('status', 'declined');
      final ids = [for (final i in invitaciones) i['event_id'] as String];

      final consulta = Supabase.instance.client
          .from('events')
          .select('id, title, start_time, end_time, location')
          .gt('start_time', ahora.toIso8601String())
          .lte('start_time', hasta.toIso8601String());
      final eventos = await (ids.isEmpty
          ? consulta.eq('creator_id', yo)
          : consulta.or('creator_id.eq.$yo,id.in.(${ids.join(',')})'));

      for (final e in eventos) {
        final id = e['id'] as String;
        if (_avisados.contains(id)) continue;
        final inicio = DateTime.parse(e['start_time']).toLocal();
        final fin = DateTime.parse(e['end_time']).toLocal();
        if (fin.difference(inicio).inHours >= 24) continue; // los de todo el día no
        _avisados.add(id);
        final lugar = e['location']?.toString();
        _mostrar(
          _Globo(
            clave: 'e-$id',
            icono: Icons.alarm,
            color: const Color(0xFF344092),
            cabecera: () => _faltan(inicio),
            titulo: e['title']?.toString() ?? 'Evento',
            detalle: [
              DateFormat('HH:mm').format(inicio),
              if (lugar != null && lugar.isNotEmpty) lugar,
            ].join(' · '),
            alTocar: () => widget.onAbrir(id),
          ),
          _seQuitaSolo,
        );
      }
    } catch (e) {
      debugPrint('Recordatorio de eventos: $e');
    }
  }

  String _faltan(DateTime inicio) {
    final min = inicio.difference(DateTime.now()).inSeconds / 60;
    if (min <= 0.5) return 'Tu evento empieza ahora';
    final n = min.ceil();
    return 'Te ${n == 1 ? 'falta 1 minuto' : 'faltan $n minutos'} para tu evento';
  }

  @override
  Widget build(BuildContext context) {
    if (_globos.isEmpty) return const SizedBox.shrink();
    final c = SiColors.of(context);
    final ancho = MediaQuery.of(context).size.width;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 70,
      right: 16,
      left: ancho < 500 ? 16 : null,
      child: SizedBox(
        width: ancho < 500 ? null : 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final g in _globos)
              Padding(
                key: ValueKey(g.clave),
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(14),
                  color: c.panel,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      setState(() => _globos.remove(g));
                      g.alTocar();
                    },
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border(left: BorderSide(color: g.color, width: 4)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(g.icono, color: g.color),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(g.cabecera(),
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: g.color,
                                        fontSize: 13)),
                                const SizedBox(height: 2),
                                Text(g.titulo,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: c.ink,
                                        fontSize: 14),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                if (g.detalle != null && g.detalle!.isNotEmpty)
                                  Text(g.detalle!,
                                      style: TextStyle(color: c.ink3, fontSize: 12),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            icon: Icon(Icons.close, size: 18, color: c.ink3),
                            onPressed: () => setState(() => _globos.remove(g)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
