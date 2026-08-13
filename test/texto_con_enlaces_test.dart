import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/widgets/texto_con_enlaces.dart';

/// El caso reportado: un aviso con un enlace no se podía pulsar ni seleccionar en la página de Social.
///
/// Se prueba la DETECCIÓN, que es donde está la lógica y donde se puede equivocar; el pintado es un
/// `SelectionArea` con un `Text.rich` y no tiene nada que decidir.
void main() {
  /// Sólo los trozos que son enlaces, con su destino ya resuelto.
  List<(String, String)> enlaces(String s) => partirEnEnlaces(s)
      .where((t) => t.esEnlace)
      .map((t) => (t.texto, t.destino!))
      .toList();

  /// El texto rearmado. Tiene que ser IGUAL al original: partirlo no puede perder ni un carácter.
  String rearmado(String s) => partirEnEnlaces(s).map((t) => t.texto).join();

  group('partirEnEnlaces', () {
    test('el caso reportado: un enlace en medio del aviso', () {
      const aviso = 'Registra tus vacaciones en https://sisol.mx/vacaciones antes del viernes.';
      expect(enlaces(aviso), [('https://sisol.mx/vacaciones', 'https://sisol.mx/vacaciones')]);
      expect(rearmado(aviso), aviso);
    });

    test('el punto final es de la frase, no del enlace', () {
      // Con el punto dentro, el enlace lleva a una dirección que no existe.
      expect(enlaces('Entra a https://sisol.mx.'), [('https://sisol.mx', 'https://sisol.mx')]);
      expect(rearmado('Entra a https://sisol.mx.'), 'Entra a https://sisol.mx.');
    });

    test('la coma y los dos puntos también', () {
      expect(enlaces('Ve a https://sisol.mx, por favor'),
          [('https://sisol.mx', 'https://sisol.mx')]);
      expect(enlaces('Aquí: https://sisol.mx;'), [('https://sisol.mx', 'https://sisol.mx')]);
    });

    test('«www.» sin protocolo se abre con https', () {
      // Sin protocolo el navegador lo tomaría como una ruta del propio sitio.
      expect(enlaces('Visita www.sisol.mx hoy'), [('www.sisol.mx', 'https://www.sisol.mx')]);
    });

    test('un correo se abre con mailto', () {
      expect(enlaces('Escribe a rh@sisol.com.mx'), [('rh@sisol.com.mx', 'mailto:rh@sisol.com.mx')]);
    });

    test('varios enlaces en el mismo aviso', () {
      const s = 'Formato en https://a.mx/f y dudas a rh@sisol.mx';
      expect(enlaces(s), [
        ('https://a.mx/f', 'https://a.mx/f'),
        ('rh@sisol.mx', 'mailto:rh@sisol.mx'),
      ]);
      expect(rearmado(s), s);
    });

    test('un paréntesis de cierre cuelga, salvo si el enlace abrió uno', () {
      expect(enlaces('(ver https://sisol.mx/a)'), [('https://sisol.mx/a', 'https://sisol.mx/a')]);
      // Los enlaces de Wikipedia llevan paréntesis dentro y son parte de la dirección.
      expect(enlaces('https://es.wikipedia.org/wiki/Mexico_(pais)'),
          [('https://es.wikipedia.org/wiki/Mexico_(pais)',
            'https://es.wikipedia.org/wiki/Mexico_(pais)')]);
    });

    test('NO convierte en enlace cualquier palabra con punto', () {
      // Un enlace de más que no lleva a ninguna parte es peor que uno de menos que se puede copiar.
      for (final s in [
        'Revisa el archivo config.ini',
        'Ya salió la versión 2.0',
        'Terminó la junta.Empezamos el lunes',
        'Sin enlaces por aquí',
      ]) {
        expect(enlaces(s), isEmpty, reason: 'no debía detectar nada en "$s"');
        expect(rearmado(s), s);
      }
    });

    test('el texto se conserva entero, siempre', () {
      // La propiedad que de verdad importa: pintar no puede comerse caracteres.
      for (final s in [
        '',
        'https://sisol.mx',
        'https://sisol.mx.',
        '  espacios  https://sisol.mx  y mas  ',
        'dos\nrenglones con https://sisol.mx en el segundo',
        'rh@sisol.mx, ventas@sisol.mx.',
        '¿Es https://sisol.mx?',
      ]) {
        expect(rearmado(s), s, reason: 'se perdió texto en "$s"');
      }
    });

    test('el signo de interrogación no entra en el enlace', () {
      expect(enlaces('¿Es https://sisol.mx?'), [('https://sisol.mx', 'https://sisol.mx')]);
    });

    test('una consulta con ? SÍ es parte del enlace', () {
      // Aquí el `?` va en medio, no colgando al final: es una dirección con parámetros.
      expect(enlaces('Abre https://sisol.mx/f?id=7 ahora'),
          [('https://sisol.mx/f?id=7', 'https://sisol.mx/f?id=7')]);
    });

    test('texto vacío no revienta', () {
      expect(partirEnEnlaces(''), isEmpty);
    });
  });
}
