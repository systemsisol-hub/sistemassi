import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/si_theme.dart';
import 'fotos_equipo.dart';

/// Enlace que lleva el QR de la etiqueta: abre la ficha del equipo en la web (o pide iniciar sesión).
String enlaceDeEquipo(String numero) => 'https://sistemassi.com/?inv=$numero';

/// Etiqueta para pegar en el equipo: QR, número de inventario y modelo, en tamaño de etiqueta
/// (70 × 35 mm). Abre la vista de impresión del sistema.
Future<void> imprimirEtiquetaEquipo(Map<String, dynamic> item) async {
  final numero = item['numero_inventario']?.toString() ?? '';
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: const PdfPageFormat(70 * PdfPageFormat.mm, 35 * PdfPageFormat.mm,
        marginAll: 2 * PdfPageFormat.mm),
    build: (_) => pw.Row(
      children: [
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: enlaceDeEquipo(numero),
          width: 29 * PdfPageFormat.mm,
          height: 29 * PdfPageFormat.mm,
        ),
        pw.SizedBox(width: 3 * PdfPageFormat.mm),
        pw.Expanded(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('SI SOL', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
              pw.Text(numero,
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text('${item['marca'] ?? ''} ${item['modelo'] ?? ''}'.trim(),
                  style: const pw.TextStyle(fontSize: 7), maxLines: 2),
              if (item['n_s'] != null)
                pw.Text('S/N ${item['n_s']}', style: const pw.TextStyle(fontSize: 6)),
            ],
          ),
        ),
      ],
    ),
  ));
  await Printing.layoutPdf(
      name: 'Etiqueta $numero', onLayout: (_) async => doc.save());
}

/// Ficha del equipo: datos agrupados, garantía, fotos, historial de asignaciones y mantenimientos.
Future<void> mostrarFichaEquipo(
  BuildContext context, {
  required Map<String, dynamic> item,
  required bool puedeEditar,
  required VoidCallback onEditar,
  required IconData icono,
  required Color colorCondicion,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _Ficha(
      item: item,
      puedeEditar: puedeEditar,
      onEditar: () {
        Navigator.pop(sheetContext);
        onEditar();
      },
      icono: icono,
      colorCondicion: colorCondicion,
    ),
  );
}

class _Ficha extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool puedeEditar;
  final VoidCallback onEditar;
  final IconData icono;
  final Color colorCondicion;

  const _Ficha({
    required this.item,
    required this.puedeEditar,
    required this.onEditar,
    required this.icono,
    required this.colorCondicion,
  });

  String? _v(String col) {
    final v = item[col]?.toString().trim();
    return v == null || v.isEmpty ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final condicion = (item['condicion'] ?? '').toString().toUpperCase();
    final secciones = <(String, List<(String, String?)>)>[
      ('Asignación', [
        ('Usuario', _v('usuario_nombre')),
        ('Ubicación', _v('ubicacion')),
      ]),
      ('Equipo', [
        ('Tipo', _v('tipo')),
        ('Marca', _v('marca')),
        ('Modelo', _v('modelo')),
        ('N/S', _v('n_s')),
        ('IMEI', _v('imei')),
      ]),
      ('Especificaciones', [
        ('CPU', _v('cpu')),
        ('SSD', _v('ssd')),
        ('RAM', _v('ram')),
        ('GPU', _v('gpu')),
      ]),
      ('Software y red', [
        ('Sistema operativo', _v('sistema_operativo')),
        ('Licencias', _v('licencias')),
        ('Antivirus', _v('antivirus')),
        ('Nombre del equipo', _v('nombre_equipo')),
        ('MAC', _v('mac')),
        ('Línea', _v('linea')),
        ('Compañía', _v('compania')),
      ]),
      ('Compra y garantía', [
        ('Fecha de compra', _v('fecha_compra')),
        ('Proveedor', _v('proveedor')),
        ('N° de factura', _v('factura')),
        ('Garantía hasta', _v('garantia_hasta')),
        ('Valor', item['valor'] == null ? null : '\$${item['valor']}'),
        ('Fecha actualización', _v('fecha_actualizacion')),
        ('Resguardo firmado', item['documento_pdf'] == null ? 'No cargado' : 'Cargado'),
      ]),
      ('Accesorios y observaciones', [
        ('Accesorios', _v('accesorios')),
        ('Observaciones', _v('observaciones')),
      ]),
      if (condicion == 'DESECHADO')
        ('Baja', [
          ('Fecha de baja', _v('fecha_baja')),
          ('Motivo', _v('motivo_baja')),
        ]),
    ];

    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(t.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: c.ink3)),
        );

    return Container(
      decoration: BoxDecoration(
          color: c.panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92, maxWidth: 760),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cerrar', style: TextStyle(fontSize: 16, color: c.ink3)),
              ),
              Text('Ficha del equipo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.ink)),
              puedeEditar
                  ? TextButton(
                      onPressed: onEditar,
                      child: Text('Editar',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold, color: c.brand)),
                    )
                  : const SizedBox(width: 64),
            ],
          ),
        ),
        Divider(height: 1, color: c.line),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: c.brand.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(icono, color: c.brand, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${item['marca'] ?? ''} ${item['modelo'] ?? ''}'.trim(),
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold, color: c.ink)),
                          Text(
                              [item['numero_inventario'], item['tipo']]
                                  .whereType<Object>()
                                  .join(' · '),
                              style: TextStyle(color: c.ink3, fontSize: 13)),
                        ],
                      ),
                    ),
                    _Chip(texto: condicion, color: colorCondicion),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _AvisoGarantia(hasta: _v('garantia_hasta')),
                    if (item['numero_inventario'] != null)
                      OutlinedButton.icon(
                        onPressed: () => imprimirEtiquetaEquipo(item),
                        icon: const Icon(Icons.qr_code_2, size: 18),
                        label: const Text('Etiqueta QR'),
                      ),
                  ],
                ),
                for (final (nombre, campos) in secciones)
                  if (campos.any((f) => f.$2 != null)) ...[
                    titulo(nombre),
                    for (final (etiqueta, valor) in campos)
                      if (valor != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 150,
                                child: Text(etiqueta,
                                    style: TextStyle(color: c.ink3, fontSize: 13)),
                              ),
                              Expanded(
                                child: SelectableText(valor,
                                    style: TextStyle(color: c.ink, fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                  ],
                titulo('Fotos'),
                FotosEquipoGaleria(itemId: item['id'] as String),
                titulo('Historial de asignaciones'),
                _Historial(equipoId: item['id'] as String),
                titulo('Mantenimientos'),
                _Mantenimientos(equipoId: item['id'] as String, puedeEditar: puedeEditar),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String texto;
  final Color color;
  const _Chip({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(texto,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
      );
}

/// «Garantía vigente», «vence en N días» (menos de 60) o «vencida».
class _AvisoGarantia extends StatelessWidget {
  final String? hasta;
  const _AvisoGarantia({required this.hasta});

  @override
  Widget build(BuildContext context) {
    final fecha = hasta == null ? null : DateTime.tryParse(hasta!);
    if (fecha == null) return const SizedBox.shrink();
    final hoy = DateTime.now();
    final dias = DateTime(fecha.year, fecha.month, fecha.day)
        .difference(DateTime(hoy.year, hoy.month, hoy.day))
        .inDays;
    final (texto, color) = dias < 0
        ? ('Garantía vencida', Colors.red)
        : dias <= 60
            ? ('Garantía vence en $dias días', Colors.orange)
            : ('Garantía vigente', Colors.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.verified_user_outlined, size: 16, color: color),
        const SizedBox(width: 6),
        Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
      ]),
    );
  }
}

/// Quién tuvo el equipo y cuándo (lo llena la base al cambiar el usuario).
class _Historial extends StatelessWidget {
  final String equipoId;
  const _Historial({required this.equipoId});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final f = DateFormat('d MMM yyyy', 'es');
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Supabase.instance.client
          .from('issi_asignaciones')
          .select('usuario_nombre, ubicacion, desde, hasta')
          .eq('equipo_id', equipoId)
          .order('desde', ascending: false)
          .then((r) => List<Map<String, dynamic>>.from(r)),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final filas = snap.data!;
        if (filas.isEmpty) {
          return Text('Sin registros',
              style: TextStyle(color: c.ink4, fontStyle: FontStyle.italic, fontSize: 13));
        }
        return Column(
          children: [
            for (final a in filas)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                    a['hasta'] == null ? Icons.person : Icons.person_outline,
                    color: a['hasta'] == null ? c.brand : c.ink4),
                title: Text(a['usuario_nombre']?.toString() ?? '—',
                    style: TextStyle(
                        fontWeight: a['hasta'] == null ? FontWeight.w600 : FontWeight.normal)),
                subtitle: Text([
                  '${f.format(DateTime.parse(a['desde']).toLocal())} – '
                      '${a['hasta'] == null ? 'hoy' : f.format(DateTime.parse(a['hasta']).toLocal())}',
                  if (a['ubicacion'] != null) a['ubicacion'],
                ].join(' · ')),
              ),
          ],
        );
      },
    );
  }
}

/// Mantenimientos y reparaciones; quien edita el inventario puede agregarlos.
class _Mantenimientos extends StatefulWidget {
  final String equipoId;
  final bool puedeEditar;
  const _Mantenimientos({required this.equipoId, required this.puedeEditar});

  @override
  State<_Mantenimientos> createState() => _MantenimientosState();
}

class _MantenimientosState extends State<_Mantenimientos> {
  late Future<List<Map<String, dynamic>>> _filas = _cargar();

  Future<List<Map<String, dynamic>>> _cargar() => Supabase.instance.client
      .from('issi_mantenimientos')
      .select()
      .eq('equipo_id', widget.equipoId)
      .order('fecha', ascending: false)
      .then((r) => List<Map<String, dynamic>>.from(r));

  Future<void> _agregar() async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormMantenimiento(equipoId: widget.equipoId),
    );
    if (guardado == true && mounted) setState(() => _filas = _cargar());
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final f = DateFormat('d MMM yyyy', 'es');
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _filas,
      builder: (context, snap) {
        final filas = snap.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (filas == null)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (filas.isEmpty)
              Text('Sin mantenimientos',
                  style: TextStyle(color: c.ink4, fontStyle: FontStyle.italic, fontSize: 13))
            else
              for (final m in filas)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.build_outlined, color: c.ink3),
                  title: Text(
                      '${m['tipo']} · ${f.format(DateTime.parse(m['fecha'].toString()))}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    if (m['descripcion'] != null) m['descripcion'],
                    if (m['realizado_por'] != null) 'Por ${m['realizado_por']}',
                    if (m['costo'] != null) '\$${m['costo']}',
                  ].join(' · ')),
                ),
            if (widget.puedeEditar)
              TextButton.icon(
                onPressed: _agregar,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar mantenimiento'),
              ),
          ],
        );
      },
    );
  }
}

class _FormMantenimiento extends StatefulWidget {
  final String equipoId;
  const _FormMantenimiento({required this.equipoId});

  @override
  State<_FormMantenimiento> createState() => _FormMantenimientoState();
}

class _FormMantenimientoState extends State<_FormMantenimiento> {
  static const _tipos = ['PREVENTIVO', 'CORRECTIVO', 'REPARACION', 'ACTUALIZACION'];
  String _tipo = _tipos.first;
  DateTime _fecha = DateTime.now();
  final _descripcion = TextEditingController();
  final _costo = TextEditingController();
  final _realizadoPor = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _descripcion.dispose();
    _costo.dispose();
    _realizadoPor.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_descripcion.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Describe qué se hizo')));
      return;
    }
    setState(() => _guardando = true);
    try {
      await Supabase.instance.client.from('issi_mantenimientos').insert({
        'equipo_id': widget.equipoId,
        'fecha': DateFormat('yyyy-MM-dd').format(_fecha),
        'tipo': _tipo,
        'descripcion': _descripcion.text.trim(),
        'costo': double.tryParse(_costo.text.trim()),
        'realizado_por':
            _realizadoPor.text.trim().isEmpty ? null : _realizadoPor.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
            color: c.panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancelar', style: TextStyle(fontSize: 16, color: c.ink3)),
                ),
                Text('Mantenimiento',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.ink)),
                TextButton(
                  onPressed: _guardando ? null : _guardar,
                  child: Text('Guardar',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold, color: c.brand)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              DropdownButtonFormField<String>(
                value: _tipo,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Tipo', prefixIcon: Icon(Icons.build_outlined)),
                items: _tipos.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _tipo = v!),
              ),
              const SizedBox(height: 16),
              TextField(
                readOnly: true,
                controller:
                    TextEditingController(text: DateFormat('yyyy-MM-dd').format(_fecha)),
                decoration: const InputDecoration(
                    labelText: 'Fecha', prefixIcon: Icon(Icons.event_outlined)),
                onTap: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: _fecha,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2101));
                  if (d != null) setState(() => _fecha = d);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descripcion,
                minLines: 3,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Qué se hizo *',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_outlined)),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _realizadoPor,
                    decoration: const InputDecoration(
                        labelText: 'Realizado por', prefixIcon: Icon(Icons.person_outline)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _costo,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Costo', prefixIcon: Icon(Icons.attach_money)),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
