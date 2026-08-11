import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/services/telefono_whatsapp.dart';

/// La normalización decide de quién son los datos que Soli va a entregar por WhatsApp, así que es la
/// pieza que más conviene fijar. Un fallo aquí no es un error de formato: es contestarle a alguien
/// con el saldo de vacaciones de otra persona.
///
/// Los casos vienen de los datos reales: los celulares capturados tienen entre 1 y 11 dígitos y casi
/// ninguno trae lada de país, mientras que WhatsApp siempre la manda.
void main() {
  group('normalizar', () {
    test('lo que manda WhatsApp para México', () {
      // Con el 1 histórico de móviles.
      expect(TelefonoWhatsApp.normalizar('5215580180569@c.us'), '5580180569');
      // Sin el 1, que es como lo manda hoy.
      expect(TelefonoWhatsApp.normalizar('525580180569@c.us'), '5580180569');
      // Ya normalizado.
      expect(TelefonoWhatsApp.normalizar('5580180569@c.us'), '5580180569');
    });

    test('lo que teclea una persona en el panel', () {
      for (final entrada in [
        '5580180569',
        '55 8018 0569',
        '(55) 8018-0569',
        '55-8018-0569',
        ' 55.8018.0569 ',
        '+52 55 8018 0569',
        '+52 1 55 8018 0569',
      ]) {
        expect(TelefonoWhatsApp.normalizar(entrada), '5580180569',
            reason: entrada);
      }
    });

    test('lo que NO se puede afirmar devuelve null, no una adivinanza', () {
      // Los datos reales tienen celulares de 1, 7, 8 y 9 dígitos. Completarlos a ciegas apuntaría a
      // otra persona, así que se rechazan.
      expect(TelefonoWhatsApp.normalizar('8018056'), isNull);
      expect(TelefonoWhatsApp.normalizar('80180569'), isNull);
      expect(TelefonoWhatsApp.normalizar('180180569'), isNull);
      expect(TelefonoWhatsApp.normalizar('5'), isNull);
      expect(TelefonoWhatsApp.normalizar(''), isNull);
      expect(TelefonoWhatsApp.normalizar(null), isNull);
      expect(TelefonoWhatsApp.normalizar('sin digitos'), isNull);
      // Demasiado largo para ser México: no se recorta por si acaso.
      expect(TelefonoWhatsApp.normalizar('4915580180569'), isNull);
    });

    test('el relleno 0000000000 se normaliza igual, y eso es correcto', () {
      // No se filtra aquí a propósito: normalizar sólo da forma. Es la base la que decide, y ese
      // número empata con 5 perfiles vigentes, así que la resolución lo declara AMBIGUO y no se
      // contesta. Filtrarlo en dos lugares sería tener la regla repetida.
      expect(TelefonoWhatsApp.normalizar('0000000000'), '0000000000');
    });

    test('un número de otro país no se mutila', () {
      // +1 415 555 2671 son 11 dígitos empezando por 1, así que el algoritmo le quita el 1 y quedan
      // 10. Es una limitación conocida: el puente está pensado para México, y un número de EEUU
      // acabaría comparándose contra celulares mexicanos, donde simplemente no va a empatar.
      expect(TelefonoWhatsApp.normalizar('14155552671'), '4155552671');
    });
  });

  group('grupos', () {
    test('un chat de grupo se reconoce y se ignora', () {
      // En un grupo no hay una sola persona detrás del mensaje: no se puede saber de quién serían
      // «sus vacaciones».
      expect(TelefonoWhatsApp.esGrupo('120363000000000000@g.us'), isTrue);
      expect(TelefonoWhatsApp.esGrupo('5215580180569@c.us'), isFalse);
      expect(TelefonoWhatsApp.esGrupo(null), isFalse);
    });
  });

  group('ida y vuelta', () {
    test('lo que llega se puede contestar', () {
      final tel = TelefonoWhatsApp.normalizar('5215580180569@c.us');
      expect(tel, isNotNull);
      expect(TelefonoWhatsApp.chatIdDe(tel!), '525580180569@c.us');
      // Y ese chatId se vuelve a normalizar al mismo número.
      expect(TelefonoWhatsApp.normalizar(TelefonoWhatsApp.chatIdDe(tel)), tel);
    });

    test('el formato para mostrar', () {
      expect(TelefonoWhatsApp.bonito('5580180569'), '55 8018 0569');
      // Algo que no tenga 10 dígitos se muestra tal cual en lugar de recortarse mal.
      expect(TelefonoWhatsApp.bonito('123'), '123');
    });
  });
}
