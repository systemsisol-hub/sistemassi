import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/services/correspondencia.dart';

/// La validación de la pantalla de Correspondencia.
///
/// La tabla de CORREOS es la misma, caso por caso, que la de
/// `supabase/functions/correspondencia/verificar_correspondencia.mjs`. La pantalla valida para avisar
/// pronto y el servidor para mandar; si las dos expresiones se separan, alguien ve «dirección válida»
/// y luego un rechazo. Que las dos tablas pasen es lo que garantiza que dicen lo mismo.
void main() {
  group('qué es una dirección de correo (tabla compartida con el servidor)', () {
    const siSon = [
      'ana@sisol.com.mx',
      'a.b+c@x.co',
      'nombre.apellido@bonanzaprisma.com',
      'ANA@SISOL.COM.MX',
    ];
    const noSon = [
      '',
      'ana',
      'ana@',
      '@sisol.com',
      'ana@@sisol.com',
      'ana sisol@x.com',
      'ana@sisol',
      'ana@sisol.c',
      '"ana"@x.com',
      'ana<@x.com',
      'a,b@x.com',
    ];
    for (final c in siSon) {
      test('«$c» es correo', () => expect(esCorreo(c), isTrue));
    }
    for (final c in noSon) {
      test('«$c» NO es correo', () => expect(esCorreo(c), isFalse));
    }
  });

  group('lo que se pega de otro lado', () {
    test('separa por coma, punto y coma y salto de línea, en minúsculas y sin repetir', () {
      final r = separarCorreos('Ana@Sisol.com.mx, beto@x.com; ana@sisol.com.mx\ncarla@y.org');
      expect(r.validos, ['ana@sisol.com.mx', 'beto@x.com', 'carla@y.org']);
      expect(r.rechazados, isEmpty);
    });

    test('aparta la que no es y conserva las buenas', () {
      final r = separarCorreos('ana@x.com, no-es-correo beto@y.com');
      expect(r.validos, ['ana@x.com', 'beto@y.com']);
      expect(r.rechazados, ['no-es-correo']);
    });

    test('no vuelve a añadir las que ya estaban en el mensaje', () {
      final r = separarCorreos('ana@x.com, beto@y.com', yaElegidos: ['ANA@x.com']);
      expect(r.validos, ['beto@y.com']);
    });

    test('un texto vacío no da nada', () {
      final r = separarCorreos('  ,; \n ');
      expect(r.validos, isEmpty);
      expect(r.rechazados, isEmpty);
    });
  });

  group('el correo de un colaborador', () {
    test('el buzón de trabajo antes que el de la cuenta, como el Directorio', () {
      expect(correoDe({'mail_user': 'Ana@Sisol.com.mx', 'email': 'otra@x.com'}), 'ana@sisol.com.mx');
    });
    test('sin buzón de trabajo, el de la cuenta', () {
      expect(correoDe({'mail_user': '', 'email': 'ana@x.com'}), 'ana@x.com');
    });
    test('si el buzón no es un correo válido, tampoco se usa', () {
      expect(correoDe({'mail_user': 'ana', 'email': 'ana@x.com'}), 'ana@x.com');
    });
    test('sin ninguno, nada', () {
      expect(correoDe({'mail_user': null, 'email': null}), isNull);
    });
  });

  group('qué falta para mandar', () {
    const bien = (asunto: 'Junta', cuerpo: 'Hola', n: 1);

    test('uno completo no pide nada', () {
      expect(queFalta(asunto: bien.asunto, cuerpo: bien.cuerpo, destinatarios: bien.n), isNull);
    });
    test('sin destinatarios lo dice primero', () {
      expect(queFalta(asunto: '', cuerpo: '', destinatarios: 0), contains('destinatario'));
    });
    test('pasado el tope, lo dice con el número', () {
      expect(queFalta(asunto: 'a', cuerpo: 'b', destinatarios: maxDestinatarios + 1),
          contains('$maxDestinatarios'));
    });
    test('exactamente el tope sí se puede', () {
      expect(queFalta(asunto: 'a', cuerpo: 'b', destinatarios: maxDestinatarios), isNull);
    });
    test('sin asunto', () {
      expect(queFalta(asunto: '   ', cuerpo: 'b', destinatarios: 1), 'Falta el asunto.');
    });
    test('sin mensaje', () {
      expect(queFalta(asunto: 'a', cuerpo: '  ', destinatarios: 1), 'Falta el mensaje.');
    });
  });
}
