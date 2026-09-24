import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/file_saver_util.dart';
import 'services/ventas_datos.dart';
import 'theme/si_theme.dart';
import 'ventas_comun.dart';

/// Los prospectos que capturó Sisol en sisol.com.mx (`ventas_leads`).
///
/// Un lead es un visitante que dejó nombre, correo, teléfono y presupuesto: en ese momento el
/// Worker lo guarda, le avisa al asesor por WhatsApp y le da al cliente el enlace de su cotización.
/// Aquí no se crean ni se editan: son lo que el cliente escribió.
class VentasLeadsPage extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;
  const VentasLeadsPage({super.key, required this.role, required this.permissions});

  @override
  State<VentasLeadsPage> createState() => _VentasLeadsPageState();
}

class _VentasLeadsPageState extends State<VentasLeadsPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _leads = [];
  bool _cargando = true;
  String _busqueda = '';
  String? _desarrollo;
  final _notificando = <String>{};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final r = await _supabase
          .from('ventas_leads')
          .select('id, folio, created_at, nombre, email, telefono, presupuesto, desarrollo, '
              'resumen, notificado, notificado_en, ventas_desarrollos(nombre)')
          .order('created_at', ascending: false)
          .limit(1000);
      if (!mounted) return;
      setState(() => _leads = [for (final l in r as List) Map<String, dynamic>.from(l)]);
    } catch (e) {
      debugPrint('Error cargando leads: $e');
      if (mounted) avisoVentas(context, 'No se pudieron cargar los leads: $e', error: true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// El desarrollo como lo muestra el catálogo; si el chat no lo pudo ligar, como lo capturó.
  String _desarrolloDe(Map<String, dynamic> l) =>
      ((l['ventas_desarrollos'] as Map?)?['nombre'] ?? l['desarrollo'] ?? '').toString();

  List<Map<String, dynamic>> get _vistos {
    final q = _busqueda.trim().toLowerCase();
    return _leads.where((l) {
      if (_desarrollo != null && _desarrolloDe(l) != _desarrollo) return false;
      if (q.isEmpty) return true;
      return '${l['nombre']} ${l['email']} ${l['telefono']}'.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _notificar(Map<String, dynamic> l) async {
    final folio = '${l['folio']}';
    setState(() => _notificando.add(folio));
    try {
      final error = await SisolApi.notificar(folio);
      if (!mounted) return;
      if (error == null) {
        avisoVentas(context, 'Aviso enviado al asesor.');
        await _cargar();
      } else {
        avisoVentas(context, error, error: true);
      }
    } catch (e) {
      if (mounted) avisoVentas(context, 'No se pudo enviar: $e', error: true);
    } finally {
      if (mounted) setState(() => _notificando.remove(folio));
    }
  }

  Future<void> _exportar() async {
    final csv = leadsCsv(_vistos, urlCotizacion: urlCotizacion);
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    await FileSaverUtil.saveAndShare(Uint8List.fromList(utf8.encode(csv)), 'leads-sisol-$hoy.csv');
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final vistos = _vistos;
    final rep = repetidos(_leads);
    final hoy = horaMexico(DateTime.now());
    final deHoy = _leads.where((l) {
      final d = DateTime.tryParse('${l['created_at']}');
      if (d == null) return false;
      final m = horaMexico(d);
      return m.year == hoy.year && m.month == hoy.month && m.day == hoy.day;
    }).length;
    final desarrollos = _leads.map(_desarrolloDe).where((d) => d.isNotEmpty).toSet().toList()..sort();

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          BarraVentas(
            pista: 'Buscar por nombre, correo o teléfono',
            onBuscar: (v) => setState(() => _busqueda = v),
            acciones: [
              DropdownButton<String?>(
                value: _desarrollo,
                hint: const Text('Todos los desarrollos'),
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos los desarrollos')),
                  for (final d in desarrollos) DropdownMenuItem(value: d, child: Text(d)),
                ],
                onChanged: (v) => setState(() => _desarrollo = v),
              ),
              OutlinedButton.icon(
                onPressed: vistos.isEmpty ? null : _exportar,
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Exportar CSV'),
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
                            etiqueta: 'Leads totales',
                            valor: _leads.length,
                            icono: Icons.person_add_alt_1),
                        CifraVentas(etiqueta: 'Leads hoy', valor: deHoy, icono: Icons.calendar_month_outlined),
                        CifraVentas(
                            etiqueta: 'Notificados al asesor',
                            valor: _leads.where((l) => l['notificado'] == true).length,
                            icono: Icons.check_circle_outline,
                            color: c.success),
                      ]),
                      const SizedBox(height: SiSpace.x5),
                      if (vistos.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(SiSpace.x8),
                          child: Center(
                              child: Text('Sin leads que coincidan.',
                                  style: TextStyle(color: c.ink3))),
                        )
                      else
                        _tabla(c, vistos, rep),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tabla(SiColors c, List<Map<String, dynamic>> vistos,
      ({Map<String, int> emails, Map<String, int> telefonos}) rep) {
    Widget repetido(int n) => n > 1
        ? Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Tooltip(
              message: 'Aparece en $n leads',
              child: etiquetaVentas(c, '×$n', c.warn),
            ),
          )
        : const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rLg,
        border: Border.all(color: c.line),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.ink2),
          dataTextStyle: TextStyle(fontSize: 12.5, color: c.ink),
          dataRowMaxHeight: 64,
          columns: const [
            DataColumn(label: Text('Fecha')),
            DataColumn(label: Text('Nombre')),
            DataColumn(label: Text('Correo')),
            DataColumn(label: Text('Teléfono')),
            DataColumn(label: Text('Presupuesto')),
            DataColumn(label: Text('Desarrollo')),
            DataColumn(label: Text('Resumen')),
            DataColumn(label: Text('Asesor')),
            DataColumn(label: Text('Cotización')),
          ],
          rows: [
            for (final l in vistos)
              DataRow(cells: [
                DataCell(Text(fechaCorta(l['created_at']), style: SiType.mono(size: 11.5))),
                DataCell(Text('${l['nombre']}', style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  SelectableText('${l['email']}'),
                  repetido(rep.emails['${l['email']}'.trim().toLowerCase()] ?? 0),
                ])),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  SelectableText('${l['telefono']}', style: SiType.mono(size: 12)),
                  repetido(rep.telefonos['${l['telefono']}'.replaceAll(RegExp(r'\D'), '')] ?? 0),
                ])),
                DataCell(Text('${l['presupuesto']}')),
                DataCell(etiquetaVentas(c, _desarrolloDe(l), c.brand)),
                DataCell(SizedBox(
                  width: 260,
                  child: Text('${l['resumen'] ?? ''}',
                      maxLines: 3, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.ink2)),
                )),
                DataCell(_celdaAsesor(c, l)),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(
                    onPressed: () => abrirUrl(urlCotizacion('${l['folio']}')),
                    child: const Text('Ver PDF'),
                  ),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: urlCotizacion('${l['folio']}')));
                      avisoVentas(context, 'Enlace copiado.');
                    },
                    icon: const Icon(Icons.copy, size: 15),
                    tooltip: 'Copiar enlace',
                  ),
                ])),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _celdaAsesor(SiColors c, Map<String, dynamic> l) {
    if (l['notificado'] == true) return etiquetaVentas(c, 'Avisado', c.success);
    final folio = '${l['folio']}';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      etiquetaVentas(c, 'Pendiente', c.warn),
      const SizedBox(width: SiSpace.x2),
      _notificando.contains(folio)
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : TextButton(onPressed: () => _notificar(l), child: const Text('Notificar')),
    ]);
  }
}
