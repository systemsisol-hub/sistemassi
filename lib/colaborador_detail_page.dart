import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

class CollaboratorDetailPage extends StatefulWidget {
  final Map<String, dynamic> colab;

  const CollaboratorDetailPage({super.key, required this.colab});

  @override
  State<CollaboratorDetailPage> createState() => _CollaboratorDetailPageState();
}

class _CollaboratorDetailPageState extends State<CollaboratorDetailPage> {
  List<Map<String, dynamic>>? _assignedEquipment;
  bool _isLoadingEquipment = true;

  @override
  void initState() {
    super.initState();
    _fetchEquipment();
  }

  Future<void> _fetchEquipment() async {
    try {
      final userId = widget.colab['id'];
      if (userId == null) {
        if (mounted) setState(() => _isLoadingEquipment = false);
        return;
      }

      final data = await Supabase.instance.client
          .from('issi_inventory')
          .select()
          .eq('usuario_id', userId);
      
      if (mounted) {
        setState(() {
          _assignedEquipment = List<Map<String, dynamic>>.from(data);
          _isLoadingEquipment = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching equipment: $e');
      if (mounted) setState(() => _isLoadingEquipment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final colab = widget.colab;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('Ficha del Colaborador'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: OutlinedButton.icon(
              onPressed: () => _printFicha(context),
              icon: const Icon(Icons.print, size: 16),
              label: const Text('Imprimir Ficha'),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.brand,
                side: BorderSide(color: c.brand.withOpacity(0.4)),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SiSpace.x6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, c),
                const SizedBox(height: SiSpace.x6),
                
                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column
                      Expanded(
                        flex: 1,
                        child: Column(
                          children: [
                            _buildInfoCard(context, 'Datos Personales', [
                              _infoRow(context, Icons.wc, 'Género', colab['genero']),
                              _infoRow(context, Icons.calendar_today, 'Fecha Nac.', colab['fecha_nacimiento']),
                              _infoRow(context, Icons.location_city, 'Lugar Nac.', colab['lugar_nacimiento']),
                              _infoRow(context, Icons.favorite, 'Estado Civil', colab['estado_civil']),
                              _infoRow(context, Icons.straighten, 'Talla', colab['talla']),
                              _infoRow(context, Icons.school, 'Escolaridad', colab['escolaridad']),
                              _infoRow(context, Icons.info_outline, 'Detalle Esc.', colab['detalle_escolaridad']),
                            ]),
                            const SizedBox(height: SiSpace.x4),
                            _buildInfoCard(context, 'Datos Bancarios', [
                              _infoRow(context, Icons.account_balance, 'Banco', colab['banco']),
                              _infoRow(context, Icons.credit_card, 'Cuenta', colab['cuenta']),
                              _infoRow(context, Icons.numbers, 'Clabe', colab['clabe']),
                            ]),
                            const SizedBox(height: SiSpace.x4),
                            _buildEquipmentCard(context, c),
                          ],
                        ),
                      ),
                      const SizedBox(width: SiSpace.x4),
                      // Center Column
                      Expanded(
                        flex: 1,
                        child: Column(
                          children: [
                            _buildInfoCard(context, 'Domicilio y Contacto', [
                              _infoRow(context, Icons.home, 'Calle', '${colab['calle'] ?? ''} ${colab['no_calle'] ?? ''}'),
                              _infoRow(context, Icons.map, 'Colonia', colab['colonia']),
                              _infoRow(context, Icons.location_on, 'Municipio', colab['municipio_alcaldia']),
                              _infoRow(context, Icons.public, 'Estado Fed.', colab['estado_federal']),
                              _infoRow(context, Icons.pin_drop, 'C.P.', colab['codigo_postal']),
                              const Divider(height: 24),
                              _infoRow(context, Icons.phone, 'Teléfono', colab['telefono']),
                              _infoRow(context, Icons.smartphone, 'Celular', colab['celular']),
                              _infoRow(context, Icons.email, 'Email', colab['correo_personal']),
                            ]),
                            const SizedBox(height: SiSpace.x4),
                            _buildInfoCard(context, 'Referencia', [
                              _infoRow(context, Icons.person_outline, 'Nombre', colab['referencia_nombre']),
                              _infoRow(context, Icons.call, 'Teléfono', colab['referencia_telefono']),
                              _infoRow(context, Icons.family_restroom, 'Relación', colab['referencia_relacion']),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(width: SiSpace.x4),
                      // Right Column
                      Expanded(
                        flex: 1,
                        child: Column(
                          children: [
                            _buildInfoCard(context, 'Datos Empresa', [
                              _infoRow(context, Icons.business_center, 'Tipo', colab['empresa_tipo']),
                              _infoRow(context, Icons.account_tree, 'Área', colab['area']),
                              _infoRow(context, Icons.work, 'Puesto', colab['puesto']),
                              _infoRow(context, Icons.place, 'Ubicación', colab['ubicacion']),
                              _infoRow(context, Icons.business, 'Empresa', colab['empresa']),
                              _infoRow(context, Icons.person, 'Jefe Inmediato', colab['jefe_inmediato']),
                              _infoRow(context, Icons.group, 'Líder', colab['lider']),
                              _infoRow(context, Icons.person_pin, 'Gerente Reg.', colab['gerente_regional']),
                              _infoRow(context, Icons.supervisor_account, 'Director', colab['director']),
                              _infoRow(context, Icons.schedule, 'Horario', colab['horario']),
                            ]),
                            const SizedBox(height: SiSpace.x4),
                            _buildInfoCard(context, 'Area RH', [
                              _infoRow(context, Icons.person_search, 'Recluta', colab['recluta']),
                              _infoRow(context, Icons.badge, 'Reclutador', colab['reclutador']),
                              _infoRow(context, Icons.source, 'Fuente', colab['fuente_reclutamiento']),
                              _infoRow(context, Icons.event_available, 'Fecha Ingreso', colab['fecha_ingreso']),
                              _infoRow(context, Icons.history, 'Fecha Reingreso', colab['fecha_reingreso']),
                              _infoRow(context, Icons.sync, 'Fecha Cambio', colab['fecha_cambio']),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      _buildInfoCard(context, 'Datos Personales', [
                        _infoRow(context, Icons.wc, 'Género', colab['genero']),
                        _infoRow(context, Icons.calendar_today, 'Fecha Nac.', colab['fecha_nacimiento']),
                        _infoRow(context, Icons.straighten, 'Talla', colab['talla']),
                      ]),
                      const SizedBox(height: SiSpace.x4),
                      _buildEquipmentCard(context, c),
                      const SizedBox(height: SiSpace.x4),
                      _buildInfoCard(context, 'Datos Empresa', [
                        _infoRow(context, Icons.work, 'Puesto', colab['puesto']),
                        _infoRow(context, Icons.business, 'Empresa', colab['empresa']),
                      ]),
                    ],
                  ),

                if (colab['observaciones'] != null && colab['observaciones'].toString().isNotEmpty) ...[
                  const SizedBox(height: SiSpace.x4),
                  _buildInfoCard(context, 'Observaciones', [
                    Text(
                      colab['observaciones'],
                      style: TextStyle(fontSize: 13, color: c.ink2, height: 1.5),
                    ),
                  ]),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SiColors c) {
    final fullName = '${widget.colab['nombre'] ?? ''} ${widget.colab['paterno'] ?? ''} ${widget.colab['materno'] ?? ''}'.trim();
    final hasPhoto = (widget.colab['foto_url'] as String?)?.isNotEmpty == true;

    return Container(
      padding: const EdgeInsets.all(SiSpace.x6),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rLg,
        border: Border.all(color: c.line),
        boxShadow: SiShadows.sm,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: c.brandTint,
            backgroundImage: hasPhoto ? NetworkImage(widget.colab['foto_url']) : null,
            child: !hasPhoto
                ? Text(
                    widget.colab['nombre']?.substring(0, 1).toUpperCase() ?? '?',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c.brand),
                  )
                : null,
          ),
          const SizedBox(width: SiSpace.x6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildBadge(widget.colab['puesto'] ?? 'PUESTO NO ASIGNADO', c.brand, c.brandTint),
                    const SizedBox(width: 8),
                    _buildBadge('N° EMPLEADO: ${widget.colab['numero_empleado'] ?? '---'}', c.ink2, c.hover),
                  ],
                ),
              ],
            ),
          ),
          _buildBadge(widget.colab['status_rh'] ?? 'ACTIVO', c.success, c.successTint),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: SiRadius.rSm),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, String title, List<Widget> children) {
    final c = SiColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SiSpace.x5),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rLg,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.brand, letterSpacing: 1),
          ),
          const SizedBox(height: SiSpace.x4),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String label, dynamic value) {
    final c = SiColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c.ink3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 10, color: c.ink3, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  value?.toString() ?? '---',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEquipmentCard(BuildContext context, SiColors c) {
    return _buildInfoCard(context, 'Equipo Asignado', [
      if (_isLoadingEquipment)
        const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2)))
      else if (_assignedEquipment == null || _assignedEquipment!.isEmpty)
        Center(child: Padding(padding: const EdgeInsets.all(12), child: Text('Sin equipo asignado', style: TextStyle(fontSize: 12, color: c.ink3, fontStyle: FontStyle.italic))))
      else
        ..._assignedEquipment!.map((item) => _EquipmentRow(item: item, c: c)),
    ]);
  }

  Future<void> _printFicha(BuildContext context) async {
    final doc = pw.Document();
    final colab = widget.colab;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('FICHA DEL COLABORADOR', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text('SISTEMASSI', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('${colab['nombre']} ${colab['paterno']} ${colab['materno']}',
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.Text('N° Empleado: ${colab['numero_empleado']} | Puesto: ${colab['puesto']}'),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            _pwSection('DATOS PERSONALES', [
              ['Género', colab['genero']],
              ['Fecha Nacimiento', colab['fecha_nacimiento']],
              ['Lugar Nacimiento', colab['lugar_nacimiento']],
              ['RFC', colab['rfc']],
              ['CURP', colab['curp']],
              ['IMSS', colab['imss']],
              ['Talla', colab['talla']],
            ]),
            _pwSection('DATOS EMPRESA', [
              ['Tipo', colab['empresa_tipo']],
              ['Área', colab['area']],
              ['Puesto', colab['puesto']],
              ['Ubicación', colab['ubicacion']],
              ['Empresa', colab['empresa']],
              ['Jefe Inmediato', colab['jefe_inmediato']],
              ['Líder', colab['lider']],
              ['Gerente Regional', colab['gerente_regional']],
              ['Director', colab['director']],
              ['Horario', colab['horario']],
            ]),
            _pwSection('DATOS BANCARIOS', [
              ['Banco', colab['banco']],
              ['Cuenta', colab['cuenta']],
              ['Clabe', colab['clabe']],
            ]),
            _pwSection('AREA RH', [
              ['Recluta', colab['recluta']],
              ['Reclutador', colab['reclutador']],
              ['Fuente', colab['fuente_reclutamiento']],
              ['Fecha Ingreso', colab['fecha_ingreso']],
              ['Fecha Reingreso', colab['fecha_reingreso']],
              ['Fecha Cambio', colab['fecha_cambio']],
            ]),
            if (_assignedEquipment != null && _assignedEquipment!.isNotEmpty)
              _pwSection('EQUIPO ASIGNADO', _assignedEquipment!.map((e) => [
                e['tipo'] ?? 'Equipo',
                '${e['marca'] ?? ''} ${e['modelo'] ?? ''} (S/N: ${e['n_s'] ?? 'N/A'})'
              ]).toList()),
            
             _pwSection('DOMICILIO Y CONTACTO', [
              ['Calle', '${colab['calle']} ${colab['no_calle']}'],
              ['Colonia', colab['colonia']],
              ['Municipio', colab['municipio_alcaldia']],
              ['Estado', colab['estado_federal']],
              ['C.P.', colab['codigo_postal']],
              ['Celular', colab['celular']],
              ['Correo', colab['correo_personal']],
            ]),
            if (colab['observaciones'] != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 20),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('OBSERVACIONES', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.SizedBox(height: 5),
                    pw.Text(colab['observaciones'], style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  pw.Widget _pwSection(String title, List<List<dynamic>> rows) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 15),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
          pw.Divider(thickness: 0.5),
          pw.Table(
            children: rows.map((r) {
              return pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(r[0].toString(), style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
                  pw.Padding(padding: const pw.EdgeInsets.all(2), child: pw.Text(r[1]?.toString() ?? '---', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _EquipmentRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final SiColors c;
  const _EquipmentRow({required this.item, required this.c});

  @override
  Widget build(BuildContext context) {
    final tipo = item['tipo'] as String?;
    final condicion = item['condicion'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SiSpace.x2),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.brandTint,
              borderRadius: SiRadius.rMd,
            ),
            child: Icon(_iconForType(tipo), size: 15, color: c.brand),
          ),
          const SizedBox(width: SiSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${item['marca'] ?? ''} ${item['modelo'] ?? ''}'.trim(),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.ink)),
                if (item['n_s'] != null)
                  Text('S/N: ${item['n_s']}',
                      style: SiType.mono(size: 11, color: c.ink3)),
              ],
            ),
          ),
          if (condicion != null)
            _StatusChip(
                label: condicion.toUpperCase(),
                kind: _kindForCondition(condicion)),
        ],
      ),
    );
  }

  IconData _iconForType(String? tipo) {
    switch (tipo?.toLowerCase()) {
      case 'laptop': return Icons.laptop;
      case 'pc': return Icons.computer;
      case 'impresora': return Icons.print;
      case 'celular': return Icons.smartphone;
      case 'telefono': return Icons.phone;
      case 'monitor': return Icons.monitor;
      default: return Icons.devices;
    }
  }

  String _kindForCondition(String c) {
    switch (c.toLowerCase()) {
      case 'nuevo': return 'success';
      case 'usado': return 'warn';
      case 'dañado': return 'danger';
      default: return 'default';
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final String kind;
  const _StatusChip({required this.label, required this.kind});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    Color bg = c.hover;
    Color fg = c.ink2;

    if (kind == 'success') { bg = c.successTint; fg = c.success; }
    if (kind == 'warn') { bg = c.warnTint; fg = c.warn; }
    if (kind == 'danger') { bg = c.dangerTint; fg = c.danger; }
    if (kind == 'brand') { bg = c.brandTint; fg = c.brand; }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: SiRadius.rPill),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }
}
