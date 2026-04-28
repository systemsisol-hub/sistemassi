import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'theme/si_theme.dart';

class CollaboratorDetailPage extends StatelessWidget {
  final Map<String, dynamic> colab;

  const CollaboratorDetailPage({super.key, required this.colab});

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final isDesktop = MediaQuery.of(context).size.width > 900;

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
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, c),
                const SizedBox(height: SiSpace.x6),
                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 1,
                        child: Column(
                          children: [
                            _buildInfoCard(context, 'Datos Personales', [
                              _infoRow('Género', colab['genero']),
                              _infoRow('Fecha Nac.', colab['fecha_nacimiento']),
                              _infoRow('Lugar Nac.', colab['lugar_nacimiento']),
                              _infoRow('Estado Civil', colab['estado_civil']),
                              _infoRow('Talla', colab['talla']),
                              _infoRow('Escolaridad', colab['escolaridad']),
                              _infoRow('Detalle Esc.', colab['detalle_escolaridad']),
                            ]),
                            const SizedBox(height: SiSpace.x4),
                            _buildInfoCard(context, 'Datos Bancarios', [
                              _infoRow('Banco', colab['banco']),
                              _infoRow('Cuenta', colab['cuenta']),
                              _infoRow('Clabe', colab['clabe']),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(width: SiSpace.x4),
                      Expanded(
                        flex: 1,
                        child: Column(
                          children: [
                            _buildInfoCard(context, 'Domicilio y Contacto', [
                              _infoRow('Calle', '${colab['calle'] ?? ''} ${colab['no_calle'] ?? ''}'),
                              _infoRow('Colonia', colab['colonia']),
                              _infoRow('Municipio', colab['municipio_alcaldia']),
                              _infoRow('Estado Fed.', colab['estado_federal']),
                              _infoRow('C.P.', colab['codigo_postal']),
                              const Divider(height: 24),
                              _infoRow('Teléfono', colab['telefono']),
                              _infoRow('Celular', colab['celular']),
                              _infoRow('Email', colab['correo_personal']),
                            ]),
                            const SizedBox(height: SiSpace.x4),
                            _buildInfoCard(context, 'Referencia', [
                              _infoRow('Nombre', colab['referencia_nombre']),
                              _infoRow('Teléfono', colab['referencia_telefono']),
                              _infoRow('Relación', colab['referencia_relacion']),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(width: SiSpace.x4),
                      Expanded(
                        flex: 1,
                        child: Column(
                          children: [
                            _buildInfoCard(context, 'Datos Empresa', [
                              _infoRow('Tipo', colab['empresa_tipo']),
                              _infoRow('Área', colab['area']),
                              _infoRow('Puesto', colab['puesto']),
                              _infoRow('Ubicación', colab['ubicacion']),
                              _infoRow('Empresa', colab['empresa']),
                              _infoRow('Jefe Inmediato', colab['jefe_inmediato']),
                              _infoRow('Líder', colab['lider']),
                              _infoRow('Gerente Reg.', colab['gerente_regional']),
                              _infoRow('Director', colab['director']),
                              _infoRow('Horario', colab['horario']),
                            ]),
                            const SizedBox(height: SiSpace.x4),
                            _buildInfoCard(context, 'Area RH', [
                              _infoRow('Recluta', colab['recluta']),
                              _infoRow('Reclutador', colab['reclutador']),
                              _infoRow('Fuente', colab['fuente_reclutamiento']),
                              _infoRow('Fecha Ingreso', colab['fecha_ingreso']),
                              _infoRow('Fecha Reingreso', colab['fecha_reingreso']),
                              _infoRow('Fecha Cambio', colab['fecha_cambio']),
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
                        _infoRow('Género', colab['genero']),
                        _infoRow('Fecha Nac.', colab['fecha_nacimiento']),
                        _infoRow('Lugar Nac.', colab['lugar_nacimiento']),
                        _infoRow('Talla', colab['talla']),
                      ]),
                      const SizedBox(height: SiSpace.x4),
                      _buildInfoCard(context, 'Datos Empresa', [
                        _infoRow('Tipo', colab['empresa_tipo']),
                        _infoRow('Área', colab['area']),
                        _infoRow('Puesto', colab['puesto']),
                        _infoRow('Empresa', colab['empresa']),
                      ]),
                      // ... more cards could be added here for mobile
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
    final fullName = '${colab['nombre'] ?? ''} ${colab['paterno'] ?? ''} ${colab['materno'] ?? ''}'.trim();
    final hasPhoto = (colab['foto_url'] as String?)?.isNotEmpty == true;

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
            backgroundImage: hasPhoto ? NetworkImage(colab['foto_url']) : null,
            child: !hasPhoto
                ? Text(
                    colab['nombre']?.substring(0, 1).toUpperCase() ?? '?',
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
                    _buildBadge(colab['puesto'] ?? 'PUESTO NO ASIGNADO', c.brand, c.brandTint),
                    const SizedBox(width: 8),
                    _buildBadge('ID: ${colab['numero_empleado'] ?? '---'}', c.ink2, c.hover),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c.ink3)),
              const SizedBox(height: 4),
              _buildBadge(colab['status_rh'] ?? 'ACTIVO', c.success, c.successTint),
            ],
          ),
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

  Widget _infoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? '---',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printFicha(BuildContext context) async {
    final doc = pw.Document();

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
                    pw.Text('ID: ${colab['numero_empleado']} | Puesto: ${colab['puesto']}'),
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
