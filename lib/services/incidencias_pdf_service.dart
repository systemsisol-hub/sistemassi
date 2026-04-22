import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

class IncidenciasPdfService {
  static Future<void> generateVacationRequest(
    Map<String, dynamic> profile,
    Map<String, dynamic> incidencia,
  ) async {
    final pdf = pw.Document();

    final logoImage = pw.MemoryImage(
      (await rootBundle.load('assets/logo.png')).buffer.asUint8List(),
    );

    // Get profile image if available
    pw.ImageProvider? profileImage;
    if (profile['foto_url'] != null && profile['foto_url'].toString().isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(profile['foto_url']));
        if (response.statusCode == 200) {
          profileImage = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        print('Error fetching profile image: $e');
      }
    }

    final now = DateTime.now();
    final df = DateFormat('dd/MM/yyyy');
    final dfFull = DateFormat('EEEE, d \'de\' MMMM \'del\' yyyy', 'es_MX');

    final elaborationDate = incidencia['created_at'] != null 
        ? DateTime.parse(incidencia['created_at']) 
        : now;
    final startDate = DateTime.parse(incidencia['fecha_inicio']);
    final endDate = DateTime.parse(incidencia['fecha_fin']);
    final returnDate = DateTime.parse(incidencia['fecha_regreso']);

    final fullName = '${profile['nombre'] ?? ''} ${profile['paterno'] ?? ''} ${profile['materno'] ?? ''}'.trim();
    final area = profile['area'] ?? '---';
    final puesto = profile['puesto'] ?? profile['role'] ?? '---';
    final email = profile['email'] ?? '---';
    final ubicacion = profile['ubicacion'] ?? '---';
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
              // Top Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Image(logoImage, width: 140),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('SI SOL INMOBILIARIAS, SAPI DE CV', 
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: primaryColor)),
                      pw.Text('SOLICITUD DE VACACIONES', 
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text('CDMX a ${df.format(now)}', 
                        style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              
              // Employee Card
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
                        child: pw.Center(child: pw.Text(numEmp, style: const pw.TextStyle(fontSize: 10))),
                      ),
                    pw.SizedBox(width: 20),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(fullName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: primaryColor)),
                          pw.SizedBox(height: 5),
                          pw.Row(
                            children: [
                              _infoItem('Num. Empleado:', numEmp),
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Dates Grid
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 10),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _dateColumn('FECHA DE ELABORACIÓN', df.format(elaborationDate)),
                    _dateColumn('FECHA DE INICIO', df.format(startDate)),
                    _dateColumn('FECHA DE FIN', df.format(endDate)),
                    _dateColumn('FECHA DE REGRESO', df.format(returnDate)),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Request Text
              pw.Text(
                'Por medio del presente solicito ${incidencia['dias']} dias(s) de vacaciones, las cuales serán disfrutadas del día ${df.format(startDate)} al ${df.format(endDate)}, sin contar domingos o días festivos, que estén dentro de este período.',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'La fecha en que debo incorporarme a trabajar, es a partir del día: ${dfFull.format(returnDate)}.',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.SizedBox(height: 20),

              pw.Spacer(),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _signatureBox('Solicitante', fullName, puesto),
                  _signatureBox('Vo. Bo. Jefe Inmediato', profile['jefe_inmediato'] ?? '---', 'Jefe Directo'),
                ],
              ),
              pw.SizedBox(height: 30),

              // Footer Note
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey50,
                  border: pw.Border.all(color: PdfColors.grey200, width: 0.5),
                ),
                child: pw.Text(
                  'Nota: Esta solicitud deberá ser entregada con las firmas correspondientes a Desarrollo Humano con al menos 3 días de anticipación a la fecha en que se tomarán los días de vacaciones, de no hacerse así, la solicitud NO procederá.',
                  style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );

    // Show preview/print dialog
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'solicitud_vacaciones_${fullName.replaceAll(' ', '_')}.pdf',
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

  static pw.Widget _dateColumn(String label, String date) {
    return pw.Column(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        pw.SizedBox(height: 2),
        pw.Text(date, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
      ],
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
