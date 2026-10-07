import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/si_theme.dart';

/// Globo en la esquina que avisa «te faltan N minutos para tu evento».
///
/// Revisa cada 30 s los eventos que empiezan en los próximos 10 minutos y que son de la persona:
/// los que creó y a los que la invitaron (sin contar los que rechazó). Cada evento avisa una vez por
/// sesión. Va encima de toda la app (en `MainNavigation`), así sale en cualquier página.
///
/// Solo funciona con la app abierta: avisar con la app cerrada necesitaría notificaciones push.
class AvisoEventosProximos extends StatefulWidget {
  final void Function(String eventId) onAbrir;
  const AvisoEventosProximos({super.key, required this.onAbrir});

  @override
  State<AvisoEventosProximos> createState() => _AvisoEventosProximosState();
}

class _Globo {
  final String id;
  final String titulo;
  final DateTime inicio;
  final String? lugar;
  _Globo(this.id, this.titulo, this.inicio, this.lugar);
}

class _AvisoEventosProximosState extends State<AvisoEventosProximos> {
  static const _anticipacion = Duration(minutes: 10);
  static const _seQuitaSolo = Duration(minutes: 3);

  final _avisados = <String>{};
  final _globos = <_Globo>[];
  Timer? _revision;
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _revisar();
    _revision = Timer.periodic(const Duration(seconds: 30), (_) => _revisar());
    // Para que «faltan N minutos» se actualice mientras el globo está a la vista.
    _reloj = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _globos.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _revision?.cancel();
    _reloj?.cancel();
    super.dispose();
  }

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

      var consulta = Supabase.instance.client
          .from('events')
          .select('id, title, start_time, end_time, location')
          .gt('start_time', ahora.toIso8601String())
          .lte('start_time', hasta.toIso8601String());
      final eventos = await (ids.isEmpty
          ? consulta.eq('creator_id', yo)
          : consulta.or('creator_id.eq.$yo,id.in.(${ids.join(',')})'));

      final nuevos = <_Globo>[];
      for (final e in eventos) {
        final id = e['id'] as String;
        if (_avisados.contains(id)) continue;
        final inicio = DateTime.parse(e['start_time']).toLocal();
        final fin = DateTime.parse(e['end_time']).toLocal();
        if (fin.difference(inicio).inHours >= 24) continue; // los de todo el día no
        _avisados.add(id);
        nuevos.add(_Globo(id, e['title']?.toString() ?? 'Evento', inicio,
            e['location']?.toString()));
      }
      if (nuevos.isEmpty || !mounted) return;
      setState(() => _globos.addAll(nuevos));
      for (final g in nuevos) {
        Future.delayed(_seQuitaSolo, () {
          if (mounted) setState(() => _globos.remove(g));
        });
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
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(14),
                  color: c.panel,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      setState(() => _globos.remove(g));
                      widget.onAbrir(g.id);
                    },
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border(left: BorderSide(color: c.brand, width: 4)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.alarm, color: c.brand),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_faltan(g.inicio),
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: c.brand,
                                        fontSize: 13)),
                                const SizedBox(height: 2),
                                Text(g.titulo,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: c.ink,
                                        fontSize: 14),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                Text(
                                    [
                                      DateFormat('HH:mm').format(g.inicio),
                                      if (g.lugar != null && g.lugar!.isNotEmpty) g.lugar!,
                                    ].join(' · '),
                                    style: TextStyle(color: c.ink3, fontSize: 12)),
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
