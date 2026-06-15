import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

class IssiPdfService {
  static Future<void> generateAsignacion(
    Map<String, dynamic> profile,
    Map<String, dynamic> item,
  ) async {
    final pdf = pw.Document();

    final logoImage = pw.MemoryImage(
      (await rootBundle.load('assets/logo.png')).buffer.asUint8List(),
    );

    pw.ImageProvider? profileImage;
    if (profile['foto_url'] != null && profile['foto_url'].toString().isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(profile['foto_url']));
        if (response.statusCode == 200) {
          profileImage = pw.MemoryImage(response.bodyBytes);
        }
      } catch (_) {}
    }

    final now = DateTime.now();
    final df = DateFormat('dd/MM/yyyy');

    final fullName = '${profile['nombre'] ?? ''} ${profile['paterno'] ?? ''} ${profile['materno'] ?? ''}'.trim();
    final displayName = fullName.isNotEmpty ? fullName : (item['usuario_nombre'] ?? 'Sin usuario');
    final area = profile['area'] ?? '---';
    final puesto = profile['puesto'] ?? '---';
    final email = profile['email'] ?? '---';
    final ubicacion = profile['ubicacion'] ?? item['ubicacion'] ?? '---';
    final numEmp = profile['numero_empleado'] ?? '---';

    final primaryColor = PdfColor.fromInt(0xFF344092);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Image(logoImage, width: 140),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('SI SOL INMOBILIARIAS, SAPI DE CV',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: primaryColor)),
                      pw.Text('ASIGNACIÓN DE ACTIVO FIJO',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text('CDMX a ${df.format(now)}',
                          style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // Employee card
              pw.Container(
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                ),
                padding: const pw.EdgeInsets.all(15),
                child: pw.Row(
                  children: [
                    if (profileImage != null)
                      pw.Container(
                        width: 70,
                        height: 70,
                        decoration: pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          image: pw.DecorationImage(image: profileImage, fit: pw.BoxFit.cover),
                          border: pw.Border.all(color: primaryColor, width: 2),
                        ),
                      )
                    else
                      pw.Container(
                        width: 70,
                        height: 70,
                        decoration: const pw.BoxDecoration(color: PdfColors.grey300, shape: pw.BoxShape.circle),
                        child: pw.Center(
                          child: pw.Text(
                            numEmp.toString().length > 4 ? numEmp.toString().substring(0, 4) : numEmp.toString(),
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    pw.SizedBox(width: 20),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(displayName.toUpperCase(),
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: primaryColor)),
                          pw.SizedBox(height: 5),
                          pw.Row(
                            children: [
                              _infoItem('Num. Empleado:', numEmp.toString()),
                              pw.SizedBox(width: 20),
                              _infoItem('Ubicación:', ubicacion),
                            ],
                          ),
                          pw.SizedBox(height: 3),
                          pw.Row(
                            children: [
                              _infoItem('Área:', area),
                              pw.SizedBox(width: 20),
                              _infoItem('Puesto:', puesto),
                            ],
                          ),
                          pw.SizedBox(height: 3),
                          _infoItem('Correo:', email),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Equipment section header
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 10),
                decoration: pw.BoxDecoration(
                  color: primaryColor,
                  borderRadius: const pw.BorderRadius.only(
                    topLeft: pw.Radius.circular(6),
                    topRight: pw.Radius.circular(6),
                  ),
                ),
                child: pw.Text('CARACTERÍSTICAS DEL EQUIPO',
                    style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
              ),

              // Equipment details grid
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                  borderRadius: const pw.BorderRadius.only(
                    bottomLeft: pw.Radius.circular(6),
                    bottomRight: pw.Radius.circular(6),
                  ),
                ),
                child: pw.Column(
                  children: [
                    _equipRow([
                      ['Tipo', item['tipo'] ?? '---'],
                      ['Marca', item['marca'] ?? '---'],
                      ['Modelo', item['modelo'] ?? '---'],
                      ['Serie (N/S)', item['n_s'] ?? '---'],
                    ]),
                    pw.Divider(height: 0, thickness: 0.5, color: PdfColors.grey300),
                    _equipRow([
                      ['IMEI', item['imei'] ?? '---'],
                      ['CPU', item['cpu'] ?? '---'],
                      ['RAM', item['ram'] ?? '---'],
                      ['SSD / HDD', item['ssd'] ?? '---'],
                    ]),
                    pw.Divider(height: 0, thickness: 0.5, color: PdfColors.grey300),
                    _equipRow([
                      ['GPU', item['gpu'] ?? '---'],
                      ['Condición', item['condicion'] ?? '---'],
                    ]),
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // Compromisos / Entendimiento / Aceptación
              _termsSection(primaryColor),

              pw.SizedBox(height: 16),
              pw.Spacer(),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _signatureBox('Entregó', 'Recursos Humanos / TI', 'SI SOL Inmobiliarias'),
                  _signatureBox('Recibí conforme', displayName, puesto),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'asignacion_${displayName.replaceAll(' ', '_')}_${item['tipo'] ?? 'equipo'}.pdf',
    );
  }

  static pw.Widget _infoItem(String label, String value) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(text: '$label ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
          pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  static pw.Widget _equipRow(List<List<String>> cells) {
    return pw.Row(
      children: List.generate(cells.length, (i) {
        final cell = cells[i];
        return pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(9),
            decoration: i < cells.length - 1
                ? const pw.BoxDecoration(
                    border: pw.Border(
                      right: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                    ),
                  )
                : null,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(cell[0], style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                pw.SizedBox(height: 2),
                pw.Text(cell[1], style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              ],
            ),
          ),
        );
      }),
    );
  }

  static pw.Widget _termsSection(PdfColor primaryColor) {
    const bodyStyle = pw.TextStyle(fontSize: 7.5);
    const bulletStyle = pw.TextStyle(fontSize: 7.5);

    pw.Widget section(String title, List<String> bullets) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: primaryColor)),
          pw.SizedBox(height: 3),
          ...bullets.map((b) => pw.Padding(
                padding: const pw.EdgeInsets.only(left: 8, bottom: 2),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('- ', style: bulletStyle),
                    pw.Expanded(child: pw.Text(b, style: bodyStyle)),
                  ],
                ),
              )),
        ],
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          section('Compromisos', [
            'Me comprometo a utilizar el equipo única y exclusivamente para fines laborales directamente relacionados con mis actividades dentro de la empresa.',
            'Asumo la responsabilidad de mantener el equipo y sus accesorios en óptimas condiciones, reportando de manera inmediata cualquier falla, daño o anomalía al departamento de sistemas.',
            'Entiendo que no está permitido instalar software no autorizado ni realizar modificaciones al equipo sin la previa autorización expresa del departamento de sistemas.',
            'En caso de robo, extravío o daño al equipo, asumo la total responsabilidad por cualquier pérdida o daño que ocurra como resultado de negligencia, mal uso o incumplimiento de las políticas de la empresa.',
            'Me comprometo a devolver el equipo y todos sus accesorios en las mismas condiciones en las que fueron recibidos, al momento de mi desvinculación de la empresa o cuando así sea formalmente requerido.',
          ]),
          pw.SizedBox(height: 8),
          section('Entendimiento', [
            'Reconozco y entiendo que el equipo es propiedad exclusiva de la empresa y que su uso está sujeto a las políticas y normativas internas establecidas.',
            'Acepto que el incumplimiento de este resguardo puede acarrear sanciones disciplinarias, incluyendo el descuento del valor total o parcial del equipo en caso de pérdida o daño que sea atribuible a mi responsabilidad.',
          ]),
          pw.SizedBox(height: 8),
          section('Aceptación', [
            'Por medio de mi firma, manifiesto mi aceptación total e incondicional de los términos y condiciones estipulados en el presente resguardo.',
          ]),
        ],
      ),
    );
  }

  static pw.Widget _signatureBox(String role, String name, String position) {
    return pw.Column(
      children: [
        pw.Text(role, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 40),
        pw.Container(width: 150, height: 0.5, color: PdfColors.black),
        pw.SizedBox(height: 5),
        pw.Text(name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
        pw.Text(position, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    );
  }
}
