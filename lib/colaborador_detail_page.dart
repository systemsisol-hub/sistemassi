import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'theme/si_theme.dart';

class CollaboratorDetailPage extends StatefulWidget {
  final Map<String, dynamic> colab;

  const CollaboratorDetailPage({super.key, required this.colab});

  @override
  State<CollaboratorDetailPage> createState() => _CollaboratorDetailPageState();
}

class _CollaboratorDetailPageState extends State<CollaboratorDetailPage> {
  List<Map<String, dynamic>>? _assignedEquipment;
  String? _scheduleName;
  bool _isLoadingEquipment = true;
  bool _isLoadingSchedule = true;

  @override
  void initState() {
    super.initState();
    _fetchEquipment();
    _fetchSchedule();
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

  Future<void> _fetchSchedule() async {
    try {
      final scheduleId = widget.colab['horario'];
      if (scheduleId == null || scheduleId.toString().isEmpty) {
        if (mounted) setState(() => _isLoadingSchedule = false);
        return;
      }

      // If it looks like an ID (numeric or UUID), fetch name
      final data = await Supabase.instance.client
          .from('schedules')
          .select('name')
          .eq('id', scheduleId)
          .maybeSingle();
      
      if (mounted) {
        setState(() {
          _scheduleName = data?['name'];
          _isLoadingSchedule = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching schedule: $e');
      if (mounted) setState(() => _isLoadingSchedule = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;
    final colab = widget.colab;

    final horarioDisplay = _isLoadingSchedule 
      ? 'Cargando...' 
      : (_scheduleName ?? colab['horario'] ?? '---');

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
                              _infoRow(context, Icons.schedule, 'Horario', horarioDisplay),
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
                        _infoRow(context, Icons.schedule, 'Horario', horarioDisplay),
                      ]),
                    ],
                  ),

                if (colab['observaciones'] != null && colab['observaciones'].toString().isNotEmpty) ...[
                  const SizedBox(height: SiSpace.x4),
                  _buildInfoCard(context, 'Observaciones', [
                    Text(
                      colab['observaciones'].toString().replaceAll('\\n', '\n'),
                      style: TextStyle(fontSize: 13, color: c.ink2, height: 1.5),
                      softWrap: true,
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
                    const SizedBox(width: 8),
                    _buildBadge('ANTIGÜEDAD: ${_calculateAntiguedad()}', c.warn, c.warnTint),
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

  String _calculateAntiguedad() {
    try {
      final ingreso = widget.colab['fecha_ingreso'];
      final reingreso = widget.colab['fecha_reingreso'];
      final cambio = widget.colab['fecha_cambio'];

      List<DateTime> dates = [];
      if (ingreso != null && ingreso.toString().isNotEmpty) {
        final d = DateTime.tryParse(ingreso.toString());
        if (d != null) dates.add(d);
      }
      if (reingreso != null && reingreso.toString().isNotEmpty) {
        final d = DateTime.tryParse(reingreso.toString());
        if (d != null) dates.add(d);
      }
      if (cambio != null && cambio.toString().isNotEmpty) {
        final d = DateTime.tryParse(cambio.toString());
        if (d != null) dates.add(d);
      }

      if (dates.isEmpty) return '---';

      // Get the most recent date
      dates.sort((a, b) => b.compareTo(a));
      final baseDate = dates.first;
      final now = DateTime.now();
      
      final diff = now.difference(baseDate);
      final years = (diff.inDays / 365).floor();
      final months = ((diff.inDays % 365) / 30).floor();

      if (years > 0) {
        return '$years añ${years == 1 ? 'o' : 'os'}${months > 0 ? ', $months mes${months == 1 ? '' : 'es'}' : ''}';
      } else if (months > 0) {
        return '$months mes${months == 1 ? '' : 'es'}';
      } else {
        return '${diff.inDays} días';
      }
    } catch (e) {
      return '---';
    }
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
    final scheduleDisplay = _scheduleName ?? colab['horario'] ?? '---';
    final brandColor = PdfColor.fromInt(0xFF344092);

    // Load logo
    pw.MemoryImage? logoImage;
    try {
      final logoData = await rootBundle.load('assets/logo.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (e) {
      debugPrint('Could not load logo: $e');
    }

    // Load collaborator photo
    pw.MemoryImage? profileImage;
    if (colab['foto_url'] != null && colab['foto_url'].toString().isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(colab['foto_url']));
        if (response.statusCode == 200) {
          profileImage = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        debugPrint('Could not load profile photo: $e');
      }
    }

    // Load Material Icons Font
    pw.Font? iconFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/MaterialIcons-Regular.ttf');
      iconFont = pw.Font.ttf(fontData);
    } catch (e) {
      // Fallback: try to find it in common paths if not in assets
      debugPrint('Could not load icon font from assets: $e');
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            // Header with Logo, Title and Photo
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null)
                  pw.Container(
                    height: 60,
                    child: pw.Image(logoImage),
                  )
                else
                  pw.Text('SISTEMASSI', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: brandColor)),
                
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('FICHA DE IDENTIFICACIÓN', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: brandColor)),
                    pw.Text('DEPARTAMENTO DE RECURSOS HUMANOS', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.Text(DateTime.now().toString().split(' ').first, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
                  ],
                ),

                if (profileImage != null)
                  pw.Container(
                    width: 60,
                    height: 60,
                    decoration: pw.BoxDecoration(
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(30)),
                      image: pw.DecorationImage(image: profileImage, fit: pw.BoxFit.cover),
                    ),
                  )
                else
                  pw.Container(width: 60, height: 60),
              ],
            ),
            pw.SizedBox(height: 20),
            
            // Name and Main Info Header
            pw.Container(
              padding: const pw.EdgeInsets.all(15),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFEFF1FA),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Row(
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('${colab['nombre']} ${colab['paterno']} ${colab['materno']}'.toUpperCase(),
                          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: brandColor)),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        children: [
                          _pwBadge('N° EMPLEADO: ${colab['numero_empleado']}', PdfColors.grey800, PdfColors.white),
                          pw.SizedBox(width: 10),
                          _pwBadge('PUESTO: ${colab['puesto'] ?? '---'}', PdfColors.grey800, PdfColors.white),
                          pw.SizedBox(width: 10),
                          _pwBadge('ANTIGÜEDAD: ${_calculateAntiguedad()}', PdfColor.fromInt(0xFFD99531), PdfColor.fromInt(0xFFFCF4E4)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            // Data Grid
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      _pwCard('DATOS PERSONALES', [
                        [Icons.wc, 'Género', colab['genero']],
                        [Icons.calendar_today, 'Fecha Nacimiento', colab['fecha_nacimiento']],
                        [Icons.location_city, 'Lugar Nacimiento', colab['lugar_nacimiento']],
                        [Icons.info_outline, 'RFC', colab['rfc']],
                        [Icons.info_outline, 'CURP', colab['curp']],
                        [Icons.info_outline, 'IMSS', colab['imss']],
                        [Icons.straighten, 'Talla', colab['talla']],
                      ], brandColor, iconFont),
                      _pwCard('DATOS BANCARIOS', [
                        [Icons.account_balance, 'Banco', colab['banco']],
                        [Icons.credit_card, 'Cuenta', colab['cuenta']],
                        [Icons.numbers, 'Clabe', colab['clabe']],
                      ], brandColor, iconFont),
                    ],
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      _pwCard('DATOS EMPRESA', [
                        [Icons.business_center, 'Tipo', colab['empresa_tipo']],
                        [Icons.account_tree, 'Área', colab['area']],
                        [Icons.place, 'Ubicación', colab['ubicacion']],
                        [Icons.business, 'Empresa', colab['empresa']],
                        [Icons.person, 'Jefe Inmediato', colab['jefe_inmediato']],
                        [Icons.group, 'Líder', colab['lider']],
                        [Icons.person_pin, 'Gerente Reg.', colab['gerente_regional']],
                        [Icons.supervisor_account, 'Director', colab['director']],
                        [Icons.schedule, 'Horario', scheduleDisplay],
                      ], brandColor, iconFont),
                      _pwCard('AREA RH', [
                        [Icons.person_search, 'Recluta', colab['recluta']],
                        [Icons.badge, 'Reclutador', colab['reclutador']],
                        [Icons.source, 'Fuente', colab['fuente_reclutamiento']],
                        [Icons.event_available, 'Ingreso', colab['fecha_ingreso']],
                      ], brandColor, iconFont),
                    ],
                  ),
                ),
              ],
            ),
            
            _pwCard('DOMICILIO Y CONTACTO', [
              [Icons.home, 'Calle', '${colab['calle']} ${colab['no_calle']}'],
              [Icons.map, 'Colonia', colab['colonia']],
              [Icons.public, 'Estado', colab['estado_federal']],
              [Icons.smartphone, 'Celular', colab['celular']],
              [Icons.email, 'Correo', colab['correo_personal']],
            ], brandColor, iconFont),

            if (_assignedEquipment != null && _assignedEquipment!.isNotEmpty)
              _pwCard('EQUIPO ASIGNADO', _assignedEquipment!.map((e) => [
                Icons.devices,
                e['tipo'] ?? 'Equipo',
                '${e['marca'] ?? ''} ${e['modelo'] ?? ''} (S/N: ${e['n_s'] ?? 'N/A'})'
              ]).toList(), brandColor, iconFont),

            if (colab['observaciones'] != null && colab['observaciones'].toString().isNotEmpty)
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey200),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('OBSERVACIONES', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: brandColor)),
                    pw.SizedBox(height: 5),
                    pw.Text(colab['observaciones'].toString().replaceAll('\\n', '\n'), style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save(), name: 'Ficha_${colab['numero_empleado']}.pdf');
  }

  pw.Widget _pwCard(String title, List<List<dynamic>> rows, PdfColor brandColor, pw.Font? iconFont) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey200),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: brandColor)),
          pw.SizedBox(height: 5),
          pw.Table(
            columnWidths: {
              0: const pw.FixedColumnWidth(15), // Icon
              1: const pw.FlexColumnWidth(2),   // Label
              2: const pw.FlexColumnWidth(3),   // Value
            },
            children: rows.map((r) {
              final IconData? iconData = r[0] is IconData ? r[0] : null;
              final String label = r.length > 2 ? r[1].toString() : r[0].toString();
              final String value = r.length > 2 ? r[2]?.toString() ?? '---' : r[1]?.toString() ?? '---';

              return pw.TableRow(
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: iconData != null && iconFont != null 
                      ? pw.Text(String.fromCharCode(iconData.codePoint), style: pw.TextStyle(font: iconFont, fontSize: 8, color: PdfColors.grey600))
                      : pw.SizedBox(),
                  ),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: pw.Text(label, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700))),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: pw.Text(value, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  pw.Widget _pwBadge(String text, PdfColor fg, PdfColor bg) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: bg == PdfColors.white ? pw.Border.all(color: PdfColors.grey300) : null,
      ),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: fg)),
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
