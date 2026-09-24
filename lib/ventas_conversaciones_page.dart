import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/file_saver_util.dart';
import 'services/ventas_datos.dart';
import 'theme/si_theme.dart';
import 'ventas_comun.dart';

/// Las pláticas de los visitantes de sisol.com.mx con Sisol (`ventas_conversaciones`).
///
/// Sirven para ver qué pregunta la gente y qué contesta el agente, y para rescatar al que dio su
/// teléfono pero no llegó a ser lead. Los datos del cliente se sacan del hilo aquí, con las mismas
/// reglas que usa el Worker, porque la conversación no los guarda aparte.
class VentasConversacionesPage extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;
  const VentasConversacionesPage({super.key, required this.role, required this.permissions});

  @override
  State<VentasConversacionesPage> createState() => _VentasConversacionesPageState();
}

class _Conversacion {
  final Map<String, dynamic> fila;
  final List<Mensaje> hilo;
  final DatosCliente datos;
  final String desarrollo;
  _Conversacion(this.fila, this.hilo, this.datos, this.desarrollo);

  String get id => '${fila['id']}';
  String? get folioLead => (fila['ventas_leads'] as Map?)?['folio']?.toString();
  String get vistaPrevia =>
      hilo.firstWhere((m) => m.esCliente, orElse: () => const Mensaje('', '')).content;
}

class _VentasConversacionesPageState extends State<VentasConversacionesPage> {
  final _supabase = Supabase.instance.client;
  List<_Conversacion> _conversaciones = [];
  bool _cargando = true;
  String _busqueda = '';
  bool _soloConLead = false;

  bool get _puedeEditar => puedeEditarVentas(widget.role, widget.permissions);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final devs = await _supabase.from('ventas_desarrollos').select('nombre, alias');
      final reDevs = {
        for (final d in devs as List)
          '${d['nombre']}': regexDeNombres(['${d['nombre']}', ...List<String>.from(d['alias'] ?? [])]),
      };
      final r = await _supabase
          .from('ventas_conversaciones')
          .select('id, created_at, updated_at, num_mensajes, origen, transcript, lead_id, '
              'ventas_leads(folio, nombre, tipo)')
          .order('updated_at', ascending: false)
          .limit(500);
      final lista = <_Conversacion>[];
      for (final f in r as List) {
        final fila = Map<String, dynamic>.from(f);
        final hilo = Mensaje.deTranscript(fila['transcript']);
        lista.add(_Conversacion(fila, hilo, datosDeConversacion(hilo), ultimoDesarrollo(hilo, reDevs)));
      }
      if (!mounted) return;
      setState(() => _conversaciones = lista);
    } catch (e) {
      debugPrint('Error cargando conversaciones: $e');
      if (mounted) avisoVentas(context, 'No se pudieron cargar las conversaciones: $e', error: true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<_Conversacion> get _vistas {
    final q = _busqueda.trim().toLowerCase();
    return _conversaciones.where((cv) {
      if (_soloConLead && cv.fila['lead_id'] == null) return false;
      if (q.isEmpty) return true;
      return cv.hilo.any((m) => m.content.toLowerCase().contains(q));
    }).toList();
  }

  bool _esHoy(dynamic v) {
    final d = DateTime.tryParse('${v ?? ''}');
    if (d == null) return false;
    final a = horaMexico(d), b = horaMexico(DateTime.now());
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final vistas = _vistas;
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          BarraVentas(
            pista: 'Buscar dentro de las conversaciones',
            onBuscar: (v) => setState(() => _busqueda = v),
            acciones: [
              FilterChip(
                label: const Text('Solo con lead'),
                selected: _soloConLead,
                onSelected: (v) => setState(() => _soloConLead = v),
              ),
              IconButton(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Actualizar',
              ),
            ],
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(SiSpace.x5),
                    children: [
                      Wrap(spacing: SiSpace.x3, runSpacing: SiSpace.x3, children: [
                        CifraVentas(
                            etiqueta: 'Conversaciones',
                            valor: _conversaciones.length,
                            icono: Icons.chat_outlined),
                        CifraVentas(
                            etiqueta: 'Activas hoy',
                            valor: _conversaciones.where((cv) => _esHoy(cv.fila['updated_at'])).length,
                            icono: Icons.calendar_month_outlined),
                        CifraVentas(
                            etiqueta: 'Terminaron en lead',
                            valor: _conversaciones.where((cv) => cv.fila['lead_id'] != null).length,
                            icono: Icons.person_add_alt_1,
                            color: c.success),
                      ]),
                      const SizedBox(height: SiSpace.x5),
                      if (vistas.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(SiSpace.x8),
                          child: Center(
                              child: Text('Sin conversaciones que coincidan.',
                                  style: TextStyle(color: c.ink3))),
                        )
                      else
                        for (final cv in vistas) _renglon(c, cv),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _renglon(SiColors c, _Conversacion cv) {
    final d = cv.datos;
    final datos = [
      if (d.nombre.isNotEmpty) d.nombre,
      if (d.telefono.isNotEmpty) d.telefono,
      if (d.email.isNotEmpty) d.email,
      if (d.presupuesto.isNotEmpty) d.presupuesto,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: SiSpace.x2),
      child: Material(
        color: c.panel,
        shape: RoundedRectangleBorder(
            borderRadius: SiRadius.rLg, side: BorderSide(color: c.line)),
        child: InkWell(
          borderRadius: SiRadius.rLg,
          onTap: () => _abrir(cv),
          child: Padding(
            padding: const EdgeInsets.all(SiSpace.x4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        datos.isEmpty ? 'Visitante sin datos' : datos.join(' · '),
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: datos.isEmpty ? c.ink3 : c.ink),
                      ),
                      const SizedBox(height: 3),
                      Text(cv.vistaPrevia,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: c.ink2)),
                    ],
                  ),
                ),
                const SizedBox(width: SiSpace.x3),
                if (cv.desarrollo.isNotEmpty) ...[
                  etiquetaVentas(c, cv.desarrollo, c.brand),
                  const SizedBox(width: SiSpace.x2),
                ],
                if (cv.fila['lead_id'] != null) ...[
                  etiquetaVentas(c, tipoTexto[(cv.fila['ventas_leads'] as Map?)?['tipo']] ?? 'Lead',
                      (cv.fila['ventas_leads'] as Map?)?['tipo'] == 'CLIENTE' ? c.success : c.warn),
                  const SizedBox(width: SiSpace.x2),
                ],
                SizedBox(
                  width: 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(fechaCorta(cv.fila['updated_at']), style: SiType.mono(size: 11.5, color: c.ink3)),
                      Text('${cv.fila['num_mensajes']} mensajes',
                          style: TextStyle(fontSize: 11.5, color: c.ink3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _abrir(_Conversacion cv) async {
    final borrada = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoConversacion(conversacion: cv, puedeBorrar: _puedeEditar),
    );
    if (borrada == true) await _cargar();
  }
}

class _DialogoConversacion extends StatelessWidget {
  final _Conversacion conversacion;
  final bool puedeBorrar;
  const _DialogoConversacion({required this.conversacion, required this.puedeBorrar});

  Future<void> _descargar() async {
    final cv = conversacion;
    final txt = conversacionTxt(cv.hilo,
        encabezado: 'Conversación con Sisol · ${fechaCorta(cv.fila['created_at'])} · ${cv.fila['origen']}');
    await FileSaverUtil.saveAndShare(Uint8List.fromList(utf8.encode(txt)), 'conversacion-sisol-${cv.id}.txt');
  }

  Future<void> _borrar(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar conversación'),
        content: const Text(
            'Se borra para siempre (por ejemplo, si el cliente pidió eliminar sus datos). '
            'El lead, si lo hay, se conserva.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await Supabase.instance.client.from('ventas_conversaciones').delete().eq('id', conversacion.id);
      if (context.mounted) Navigator.pop(context, true);
    } catch (e) {
      if (context.mounted) avisoVentas(context, 'No se pudo borrar: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final cv = conversacion;
    final folio = cv.folioLead;
    return Dialog(
      insetPadding: const EdgeInsets.all(SiSpace.x5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(SiSpace.x5, SiSpace.x4, SiSpace.x2, SiSpace.x2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Conversación',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        Text(
                          '${fechaCorta(cv.fila['created_at'])} · ${cv.fila['num_mensajes']} mensajes · ${cv.fila['origen']}',
                          style: TextStyle(fontSize: 12, color: c.ink3),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.line),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(SiSpace.x4),
                children: [for (final m in cv.hilo) _burbuja(c, m)],
              ),
            ),
            Divider(height: 1, color: c.line),
            Padding(
              padding: const EdgeInsets.all(SiSpace.x3),
              child: Wrap(
                spacing: SiSpace.x2,
                alignment: WrapAlignment.end,
                children: [
                  if (folio != null)
                    TextButton.icon(
                      onPressed: () => abrirUrl(urlCotizacion(folio)),
                      icon: const Icon(Icons.description_outlined, size: 16),
                      label: const Text('Ver cotización'),
                    ),
                  TextButton.icon(
                    onPressed: _descargar,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Descargar chat'),
                  ),
                  if (puedeBorrar)
                    TextButton.icon(
                      onPressed: () => _borrar(context),
                      style: TextButton.styleFrom(foregroundColor: c.danger),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Borrar'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _burbuja(SiColors c, Mensaje m) {
    final cliente = m.esCliente;
    return Align(
      alignment: cliente ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.only(bottom: SiSpace.x2),
        padding: const EdgeInsets.symmetric(horizontal: SiSpace.x3, vertical: SiSpace.x2),
        decoration: BoxDecoration(
          color: cliente ? c.brandTint : c.bg,
          borderRadius: SiRadius.rLg,
          border: Border.all(color: c.line),
        ),
        child: SelectableText(m.content, style: TextStyle(fontSize: 13, color: c.ink)),
      ),
    );
  }
}
