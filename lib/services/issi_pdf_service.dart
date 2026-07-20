import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class IssiPdfService {
  static final _brand = PdfColor.fromInt(0xFF344092);

  // Márgenes diseñados para el template oficial:
  // top=90 → debajo del logo (≈75pt) + la curva superior
  // bottom=52 → sobre el footer con redes/sitio web
  // left=50, right=45 → dentro de la línea curva izquierda
  static const _pad = pw.EdgeInsets.fromLTRB(50, 90, 45, 52);

  static Future<void> generateAsignacion(
    Map<String, dynamic> profile,
    Map<String, dynamic> item,
  ) async {
    final pdf = pw.Document();

    final bgBytes = (await rootBundle.load('assets/acuerdo_bg.png')).buffer.asUint8List();
    final bgImage = pw.MemoryImage(bgBytes);

    final dateStr = DateFormat('dd/MM/yyyy').format(DateTime.now());

    final fullName = [profile['nombre'], profile['paterno'], profile['materno']]
        .where((s) => (s as String?)?.isNotEmpty == true)
        .join(' ');
    final displayName = fullName.isNotEmpty ? fullName : 'Sin nombre';
    final puesto = profile['puesto'] as String? ?? '';
    final area = profile['area'] as String? ?? '';

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.Container(
        constraints: const pw.BoxConstraints.expand(),
        decoration: pw.BoxDecoration(
          image: pw.DecorationImage(image: bgImage, fit: pw.BoxFit.fill),
        ),
        padding: _pad,
        child: _page1Content(displayName, puesto, area, dateStr),
      ),
    ));

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.Container(
        constraints: const pw.BoxConstraints.expand(),
        decoration: pw.BoxDecoration(
          image: pw.DecorationImage(image: bgImage, fit: pw.BoxFit.fill),
        ),
        padding: _pad,
        child: _page2Content(),
      ),
    ));

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'acuerdo_${displayName.replaceAll(' ', '_')}.pdf',
    );
  }

  // ── Page 1 ───────────────────────────────────────────────────────────────────

  static pw.Widget _page1Content(
      String name, String puesto, String area, String date) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.Text(
            'Acuerdo de Uso y Confidencialidad de Equipo de Trabajo',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _brand,
            ),
          ),
        ),
        pw.SizedBox(height: 14),

        // 1. Datos del colaborador — SISTEMA LLENA
        _sectionHeader('1. Datos del colaborador'),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          children: [
            pw.TableRow(children: [
              _labeledValue('Nombre completo:', name),
              _labeledValue('Puesto:', puesto),
            ]),
            pw.TableRow(children: [
              _labeledValue('Área / Proyecto:', area),
              _labeledValue('Fecha de firma:', date),
            ]),
          ],
        ),
        pw.SizedBox(height: 12),

        // 2. Datos del equipo asignado — VACÍO
        _sectionHeader('2. Datos del equipo asignado'),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          children: [
            pw.TableRow(children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: pw.Row(children: [
                  pw.Text('Tipo de equipo:',
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(width: 10),
                  ..._cbxRow(['Laptop', 'PC', 'Teléfono móvil', 'Otro: ___________']),
                ]),
              ),
            ]),
            pw.TableRow(children: [_emptyRow('Marca / Modelo:')]),
            pw.TableRow(children: [_emptyRow('Número de serie / Inventario:')]),
            pw.TableRow(children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: pw.Row(children: [
                  pw.Text('Accesorios entregados:',
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(width: 10),
                  ..._cbxRow(['Cargador', 'Mouse', 'Funda', 'Cable', 'Otro: _______']),
                ]),
              ),
            ]),
          ],
        ),
        pw.SizedBox(height: 12),

        // 3. Compromisos — VACÍO (solo checkboxes)
        _sectionHeader('3. Compromisos del colaborador'),
        pw.SizedBox(height: 3),
        pw.Text(
          '(Marque con una paloma cada punto para confirmar la aceptación de los términos de este acuerdo)',
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 5),
        _commitmentsTable(),

        pw.Spacer(),
        _pageNum('1'),
      ],
    );
  }

  // ── Page 2 ───────────────────────────────────────────────────────────────────

  static pw.Widget _page2Content() {
    const bodyS = pw.TextStyle(fontSize: 8.5);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // 4. Confidencialidad
        _sectionHeader('4. Confidencialidad de la información'),
        pw.SizedBox(height: 7),
        ..._confidentialityBullets.map((b) => pw.Padding(
              padding: const pw.EdgeInsets.only(left: 6, bottom: 6),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('- ', style: bodyS),
                  pw.Expanded(child: pw.Text(b, style: bodyS)),
                ],
              ),
            )),
        pw.SizedBox(height: 14),

        // 5. Declaración y firmas
        _sectionHeader('5. Declaración y firmas'),
        pw.SizedBox(height: 7),
        pw.Text(
          'Declaro haber recibido el equipo descrito en este acuerdo en buen estado y haber comprendido las responsabilidades y condiciones establecidas.',
          style: bodyS,
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _centerCell('Colaborador', bold: true),
                _centerCell('Gerencia de Tecnologías de la Información', bold: true),
              ],
            ),
            _sigRow('Nombre:', 'Nombre:'),
            _sigRow('Puesto:', 'Puesto:'),
            _sigRow('Firma:', 'Firma:', height: 42),
            _sigRow('Fecha de entrega:', 'Fecha de recepción:'),
          ],
        ),
        pw.SizedBox(height: 12),

        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(
            'Nota: Este acuerdo deberá conservarse en el expediente del colaborador y en el archivo de control de la Gerencia de Tecnologías de la Información.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),

        pw.Spacer(),

        pw.Center(child: pw.Text('Atentamente,', style: const pw.TextStyle(fontSize: 9))),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text('Dirección General',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
        ),
        pw.Center(
          child: pw.Text('SI SOL Inmobiliarias, S. A. P. I. de C. V.',
              style: const pw.TextStyle(fontSize: 9)),
        ),
        pw.SizedBox(height: 10),
        _pageNum('2'),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  static pw.Widget _sectionHeader(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      decoration: pw.BoxDecoration(
        color: _brand,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Text(text,
          style: pw.TextStyle(
              color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9)),
    );
  }

  static pw.Widget _labeledValue(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(
              text: '$label ',
              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
          pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 8.5)),
        ]),
      ),
    );
  }

  static pw.Widget _emptyRow(String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 18),
      child: pw.Text(label,
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
    );
  }

  static pw.Widget _cbx() => pw.Container(
        width: 9,
        height: 9,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 0.7),
        ),
      );

  static List<pw.Widget> _cbxRow(List<String> labels) {
    final out = <pw.Widget>[];
    for (final label in labels) {
      out.add(_cbx());
      out.add(pw.SizedBox(width: 3));
      out.add(pw.Text(label, style: const pw.TextStyle(fontSize: 8.5)));
      out.add(pw.SizedBox(width: 10));
    }
    return out;
  }

  static pw.Widget _commitmentsTable() {
    const items = [
      'Usaré el equipo exclusivamente para fines laborales relacionados con mis funciones en SI SOL Inmobiliarias, S. A. P. I. de C. V.',
      'No instalaré ni modificaré software, aplicaciones o configuraciones sin la autorización expresa de la Gerencia de Tecnologías de la Información.',
      'Mantendré el equipo en buen estado físico y operativo, reportando cualquier daño, pérdida o robo de inmediato.',
      'No compartiré ni prestaré el equipo a terceros en ninguna circunstancia.',
      'Protegeré la información contenida en el equipo conforme a la política de Adquisición y Asignación de Equipo de Cómputo y Telefonía.',
      'Devolveré el equipo de inmediato, en buen estado y con toda su información íntegra, al término de mi relación laboral o en cuanto la Gerencia de Tecnologías de la Información lo solicite. Me abstendré de borrar, alterar, formatear o extraer la información contenida en el equipo antes de su entrega, así como de establecer contraseñas o bloqueos que impidan a la empresa acceder a ella.',
      'Reconozco que el mal uso, daño o pérdida del equipo por negligencia comprobada podrá generar responsabilidad económica a mi cargo, conforme a los límites y al procedimiento previstos en la legislación laboral aplicable.',
      'Me comprometo a resguardar la información, archivos, diseños, datos y documentos generados durante el desempeño de mis funciones y a entregarlos de manera íntegra a la empresa cuando me sean requeridos o al término de mi relación laboral.',
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(10),
        1: pw.FixedColumnWidth(44),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: pw.Text('Compromiso',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              child: pw.Center(
                child: pw.Text('Acepto\n(  )',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
              ),
            ),
          ],
        ),
        ...items.asMap().entries.map(
              (e) => pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 5),
                  child: pw.Text('${e.key + 1}. ${e.value}',
                      style: const pw.TextStyle(fontSize: 7.8)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(5),
                  child: pw.Center(child: _cbx()),
                ),
              ]),
            ),
      ],
    );
  }

  static const _confidentialityBullets = [
    'Declaro conocer y aceptar que toda la información contenida, generada o procesada en el equipo asignado, así como los archivos, diseños, datos o documentos que genere durante el desempeño de mis funciones, son propiedad exclusiva de SI SOL Inmobiliarias, S. A. P. I. de C. V.',
    'Me comprometo a mantener confidencialidad absoluta sobre datos, archivos, correos y documentos a los que tenga acceso durante mis funciones.',
    'Trataré los datos personales a los que tenga acceso con motivo de mis funciones conforme a la Ley Federal de Protección de Datos Personales en Posesión de los Particulares y al aviso de privacidad de la empresa.',
    'Reconozco que la empresa podrá inspeccionar, auditar o monitorear el equipo asignado y la información contenida en él en cualquier momento, sin que exista expectativa de privacidad respecto de la información laboral.',
    'Queda estrictamente prohibida su reproducción, almacenamiento o transferencia a medios no autorizados.',
    'El incumplimiento de esta disposición será considerado una falta grave y podrá generar sanciones administrativas o legales.',
  ];

  static pw.Widget _centerCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Center(
        child: pw.Text(text,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: bold ? pw.FontWeight.bold : null,
            )),
      ),
    );
  }

  static pw.TableRow _sigRow(String left, String right, {double height = 22}) {
    pw.Widget cell(String label) => pw.Container(
          height: height,
          padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 4),
          child: pw.Text(label,
              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
        );
    return pw.TableRow(children: [cell(left), cell(right)]);
  }

  static pw.Widget _pageNum(String n) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Página $n de 2',
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
    );
  }
}
