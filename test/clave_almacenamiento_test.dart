import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/services/clave_almacenamiento.dart';

/// El caso que dio origen a esto: subir «CÓDIGO DE ÉTICA SISOL.pdf» a la base de conocimiento fallaba
/// con `InvalidKey`, porque Storage rechaza los caracteres fuera de ASCII y las tildes de «CÓDIGO» y
/// «ÉTICA» invalidan la clave.
void main() {
  group('claveDeArchivo', () {
    test('el caso reportado', () {
      expect(claveDeArchivo('CÓDIGO DE ÉTICA SISOL.pdf'),
          'CODIGO_DE_ETICA_SISOL.pdf');
    });

    test('un nombre que ya era válido no se toca', () {
      expect(claveDeArchivo('PoliticaTI.pdf'), 'PoliticaTI.pdf');
      expect(claveDeArchivo('manual-v2_final.docx'), 'manual-v2_final.docx');
    });

    test('la Ñ SÍ se convierte aquí', () {
      // Al contrario que en la búsqueda de personas, donde «Peñafiel» tiene que conservarse tal cual
      // porque así está en la base. La clave de Storage debe ser ASCII.
      expect(claveDeArchivo('Diseño de Año Nuevo.pdf'), 'Diseno_de_Ano_Nuevo.pdf');
    });

    test('la extensión se conserva y se pasa a minúsculas', () {
      expect(claveDeArchivo('REPORTE.PDF'), 'REPORTE.pdf');
      expect(claveDeArchivo('hoja.XLSX'), 'hoja.xlsx');
    });

    test('varios puntos: sólo el último delimita la extensión', () {
      expect(claveDeArchivo('informe.final.v2.pdf'), 'informe.final.v2.pdf');
    });

    test('los símbolos que rompen una URL se sustituyen', () {
      // Sin guion bajo colgando al final: mi primera expectativa lo llevaba y el código hacía bien
      // en quitarlo.
      expect(claveDeArchivo('Reporte #3 (final) 50%.pdf'),
          'Reporte_3_final_50.pdf');
      expect(claveDeArchivo('a/b\\c:d?e.pdf'), 'a_b_c_d_e.pdf');
    });

    test('no deja guiones bajos ni puntos sueltos en los extremos', () {
      expect(claveDeArchivo('  espacios  .pdf'), 'espacios.pdf');
      expect(claveDeArchivo('...raro...pdf'), 'raro.pdf');
    });

    test('nunca devuelve una cadena vacía', () {
      // Un nombre que al sanear no deja nada útil necesita algo que nombrar, o la clave quedaria
      // terminada en `/` y volveria a ser invalida.
      expect(claveDeArchivo('.pdf'), 'archivo.pdf');
      expect(claveDeArchivo('¿¡%&.pdf'), 'archivo.pdf');
      expect(claveDeArchivo(''), 'archivo');
      expect(claveDeArchivo('   '), 'archivo');
    });

    test('un archivo sin extensión no gana un punto de la nada', () {
      expect(claveDeArchivo('LEEME'), 'LEEME');
      expect(claveDeArchivo('CÓDIGO'), 'CODIGO');
    });

    test('un nombre larguísimo se recorta pero conserva la extensión', () {
      final largo = '${'a' * 200}.pdf';
      final clave = claveDeArchivo(largo);
      expect(clave.endsWith('.pdf'), isTrue);
      expect(clave.length, lessThanOrEqualTo(84));
    });

    test('el resultado SIEMPRE es una clave que Storage acepta', () {
      // La comprobación que de verdad importa: nada fuera de ASCII, y sólo los caracteres permitidos.
      for (final entrada in [
        'CÓDIGO DE ÉTICA SISOL.pdf',
        'Año 2026 — Presupuesto (v3).xlsx',
        'çédille & ampersand.docx',
        'ÑOÑO.pdf',
        '.pdf',
        'sin_extension',
      ]) {
        final clave = claveDeArchivo(entrada);
        expect(RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(clave), isTrue,
            reason: 'la clave de "$entrada" salió como "$clave"');
      }
    });
  });
}
