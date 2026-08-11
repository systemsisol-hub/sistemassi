import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/services/convertidor_service.dart';

/// Lo que se puede probar del convertidor sin el servidor: qué formatos se ofrecen y con qué nombre
/// se entrega el archivo.
///
/// El nombre importa más de lo que parece. Se comprobó contra la instancia que `pdf/img` devuelve un
/// **ZIP** cuando son varias páginas y un **PNG** cuando es una sola; si el cliente adivinara la
/// extensión, el usuario acabaría con un archivo que el sistema no sabe abrir. Por eso se usa el
/// nombre que manda el servidor, y estas pruebas fijan ese comportamiento.
void main() {
  group('nombreDeRespuesta', () {
    test('toma el nombre de la cabecera del servidor', () {
      // La forma real que devuelve la instancia: `form-data`, no el `attachment` habitual.
      expect(
        ConvertidorService.nombreDeRespuesta(
            'form-data; name="attachment"; filename="reporte.docx"',
            respaldo: 'x.docx'),
        'reporte.docx',
      );
    });

    test('reconoce el ZIP de las imágenes, que es el caso que más engaña', () {
      expect(
        ConvertidorService.nombreDeRespuesta(
            'form-data; name="attachment"; filename="doc_convertedToImages.zip"',
            respaldo: 'doc.png'),
        'doc_convertedToImages.zip',
      );
    });

    test('sin cabecera usa el respaldo', () {
      expect(ConvertidorService.nombreDeRespuesta(null, respaldo: 'doc.md'),
          'doc.md');
      expect(ConvertidorService.nombreDeRespuesta('', respaldo: 'doc.md'),
          'doc.md');
      expect(
          ConvertidorService.nombreDeRespuesta('attachment', respaldo: 'doc.md'),
          'doc.md');
    });

    test('acepta el nombre sin comillas', () {
      expect(
        ConvertidorService.nombreDeRespuesta('attachment; filename=hoja.txt',
            respaldo: 'x.txt'),
        'hoja.txt',
      );
    });

    test('descarta cualquier ruta que venga del servidor', () {
      // No se confía en lo que responde: un nombre con ruta podría escribir donde no debe.
      expect(
        ConvertidorService.nombreDeRespuesta(
            r'attachment; filename="../../etc/passwd"',
            respaldo: 'seguro.txt'),
        'passwd',
      );
      expect(
        ConvertidorService.nombreDeRespuesta(
            r'attachment; filename="C:\temp\a.docx"',
            respaldo: 'seguro.txt'),
        'a.docx',
      );
    });
  });

  group('nombreConExtension', () {
    test('cambia la extensión y conserva el nombre', () {
      expect(ConvertidorService.nombreConExtension('Reporte final.pdf', 'md'),
          'Reporte final.md');
    });

    test('un nombre sin extensión sólo la gana', () {
      expect(ConvertidorService.nombreConExtension('Reporte', 'txt'),
          'Reporte.txt');
    });

    test('un nombre oculto no se queda sin base', () {
      // '.gitignore' tiene el punto en la posición 0: partir ahí dejaría el nombre vacío.
      expect(ConvertidorService.nombreConExtension('.oculto', 'pdf'),
          '.oculto.pdf');
    });

    test('conserva los puntos intermedios', () {
      expect(
          ConvertidorService.nombreConExtension('acta.v2.final.pdf', 'docx'),
          'acta.v2.final.docx');
    });
  });

  group('destinosPara', () {
    test('un PDF ofrece varios destinos, y ninguno es PDF otra vez', () {
      final d = ConvertidorService.destinosPara('reporte.pdf');
      expect(d.length, greaterThan(5));
      expect(d.map((x) => x.id), contains('markdown'));
      expect(d.map((x) => x.id), contains('docx'));
      // PDF/A sí es un PDF, pero es otro formato; convertir un PDF a PDF a secas no tiene sentido.
      expect(d.map((x) => x.id), isNot(contains('pdf')));
    });

    test('cualquier otra cosa sólo va a PDF', () {
      for (final n in ['carta.docx', 'datos.xlsx', 'foto.png', 'notas.txt']) {
        final d = ConvertidorService.destinosPara(n);
        expect(d.length, 1, reason: n);
        expect(d.first.id, 'pdf', reason: n);
      }
    });

    test('la extensión se compara sin importar mayúsculas', () {
      expect(ConvertidorService.destinosPara('REPORTE.PDF').length,
          greaterThan(5));
    });

    test('Excel y CSV NO se ofrecen', () {
      // Comprobado contra la instancia: devuelven 204 sin contenido incluso con un PDF que lleva una
      // tabla HTML de verdad. Ofrecerlos sería prometer un archivo vacío.
      final ids = ConvertidorService.destinosPara('x.pdf').map((d) => d.id);
      expect(ids, isNot(contains('xlsx')));
      expect(ids, isNot(contains('csv')));
    });
  });

  group('tipoMimeDe', () {
    // La causa del fallo reportado. Medido contra la instancia: pdf/word con la parte declarada como
    // `application/pdf` devuelve 200 y 5 990 bytes; con `application/octet-stream` devuelve 400 y cero
    // bytes, con el detalle «File must be in PDF format». MultipartFile.fromBytes declara
    // octet-stream por omision, asi que sin esto Word y PDF/A no funcionan nunca.
    test('un PDF se declara como application/pdf', () {
      expect(ConvertidorService.tipoMimeDe('reporte.pdf').toString(),
          'application/pdf');
    });

    test('no importan las mayusculas de la extension', () {
      expect(ConvertidorService.tipoMimeDe('REPORTE.PDF').toString(),
          'application/pdf');
    });

    test('los de oficina llevan su tipo, que LibreOffice usa', () {
      expect(ConvertidorService.tipoMimeDe('a.docx').toString(),
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      expect(ConvertidorService.tipoMimeDe('a.xlsx').toString(),
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      expect(ConvertidorService.tipoMimeDe('a.png').toString(), 'image/png');
      expect(ConvertidorService.tipoMimeDe('a.txt').toString(), 'text/plain');
    });

    test('lo desconocido cae a octet-stream y no revienta', () {
      expect(ConvertidorService.tipoMimeDe('a.xyz').toString(),
          'application/octet-stream');
      expect(ConvertidorService.tipoMimeDe('sin_extension').toString(),
          'application/octet-stream');
    });

    test('toda extension aceptada tiene un tipo declarado', () {
      // Si alguien agrega una extension al selector y olvida el tipo, el servidor la rechazaria con
      // un 400 dificil de explicar.
      for (final e in ConvertidorService.extensionesAceptadas) {
        expect(ConvertidorService.tipoMimeDe('archivo.$e').toString(),
            isNot('application/octet-stream'),
            reason: 'falta el tipo MIME de .$e');
      }
    });
  });

  group('mensajes de error', () {
    // El fallo que costo una sesion: se comprobaba «cuerpo vacio» ANTES del estado, y como este
    // servidor devuelve 400 con CERO bytes, cualquier peticion mal formada se reportaba como «no
    // encontro contenido» y culpaba al documento. Estas pruebas fijan que el numero salga siempre.
    test('un 400 con cuerpo vacio NO se reporta como falta de contenido', () {
      final m = ConvertidorService.mensajeDeErrorParaPruebas(
          400, ConvertidorService.desdePdf.first, Uint8List(0));
      expect(m, contains('400'));
      expect(m.toLowerCase(), isNot(contains('no encontró contenido')));
    });

    test('cada estado conocido menciona su codigo', () {
      for (final e in [400, 413, 415, 422, 500, 502, 504, 418]) {
        final m = ConvertidorService.mensajeDeErrorParaPruebas(
            e, ConvertidorService.aPdf, Uint8List(0));
        expect(m, contains('$e'), reason: 'estado $e');
      }
    });

    test('agrega el texto del servidor cuando lo manda', () {
      final cuerpo = Uint8List.fromList(
          '{"detail":"outputFormat invalido"}'.codeUnits);
      final m = ConvertidorService.mensajeDeErrorParaPruebas(
          400, ConvertidorService.aPdf, cuerpo);
      expect(m, contains('outputFormat invalido'));
    });

    test('nunca vuelca un binario en el mensaje', () {
      // Un ZIP empieza con PK y trae bytes de control: no es un mensaje para leer.
      final zip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x00, 0x01, 0x02]);
      final m = ConvertidorService.mensajeDeErrorParaPruebas(
          500, ConvertidorService.aPdf, zip);
      expect(m, isNot(contains('PK')));
      expect(m, contains('500'));
    });
  });

  group('catálogo', () {
    test('cada destino trae los campos obligatorios de su endpoint', () {
      // Los saqué del OpenAPI de la instancia: sin ellos el servidor responde 400. `pdf/img` exige
      // cinco, y es el que más fácil se rompe si alguien agrega un formato copiando otro.
      final porId = {
        for (final d in ConvertidorService.desdePdf) d.id: d,
      };
      expect(porId['docx']!.campos, {'outputFormat': 'docx'});
      expect(porId['txt']!.campos, {'outputFormat': 'txt'});
      expect(porId['pdfa']!.campos, {'outputFormat': 'pdfa-2b'});
      expect(porId['png_zip']!.campos.keys,
          containsAll(['colorType', 'dpi', 'imageFormat', 'pageNumbers', 'singleOrMultiple']));
      expect(porId['png_zip']!.campos['singleOrMultiple'], 'multiple');
      expect(porId['png']!.campos['singleOrMultiple'], 'single');
      // Los que no piden nada, no deben llevar campos de más.
      expect(porId['markdown']!.campos, isEmpty);
      expect(porId['html']!.campos, isEmpty);
    });

    test('la extensión del ZIP de imágenes no es png', () {
      final porId = {for (final d in ConvertidorService.desdePdf) d.id: d};
      expect(porId['png_zip']!.extension, 'zip');
      expect(porId['png']!.extension, 'png');
    });

    test('no hay ids repetidos', () {
      final ids = ConvertidorService.desdePdf.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('todos los destinos tienen ruta, extensión y descripción', () {
      for (final d in [...ConvertidorService.desdePdf, ConvertidorService.aPdf]) {
        expect(d.ruta, isNotEmpty, reason: d.id);
        expect(d.extension, isNotEmpty, reason: d.id);
        expect(d.descripcion, isNotEmpty, reason: d.id);
        expect(d.etiqueta, isNotEmpty, reason: d.id);
      }
    });

    test('el selector acepta las entradas que el catálogo sabe convertir', () {
      expect(ConvertidorService.extensionesAceptadas, contains('pdf'));
      for (final e in ['docx', 'xlsx', 'pptx', 'png', 'html', 'txt']) {
        expect(ConvertidorService.extensionesAceptadas, contains(e), reason: e);
      }
    });
  });
}
