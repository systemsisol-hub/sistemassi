import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
    test('el tope alcanza para toda la plantilla (74 empleados)', () {
      // Con el tope de 50 de antes, una lista de «todos» ya no se podía mandar.
      expect(maxDestinatarios, greaterThanOrEqualTo(74));
    });
  });

  // El MISMO criterio que `resolverMiembros` del servidor, con los mismos casos: la pantalla lo usa
  // para decir a cuántos llega, y si contara distinto que el servidor, mentiría antes de enviar.
  group('a quién llega una lista hoy', () {
    final r = correosDeLista([
      {'profiles': {'mail_user': 'Ana@Sisol.com.mx', 'email': 'ana.cuenta@x.com', 'status_sys': 'ACTIVO'}},
      {'profiles': {'mail_user': '', 'email': 'beto@x.com', 'status_sys': 'ACTIVO'}},
      {'profiles': {'mail_user': 'carla@sisol.com.mx', 'email': null, 'status_sys': 'BAJA'}},
      {'profiles': {'mail_user': 'no-es-correo', 'email': '', 'status_sys': 'ACTIVO'}},
      {'profiles': null},
      {'correo': 'Externo@Cliente.com'},
      {'correo': 'ana@sisol.com.mx'},
    ]);

    test('del compañero, el buzón de trabajo antes que el de la cuenta', () {
      expect(r.correos, contains('ana@sisol.com.mx'));
    });
    test('sin buzón de trabajo, el de la cuenta', () => expect(r.correos, contains('beto@x.com')));
    test('el correo tecleado va en minúsculas', () => expect(r.correos, contains('externo@cliente.com')));
    test('quien se dio de BAJA ya no recibe', () {
      expect(r.correos, isNot(contains('carla@sisol.com.mx')));
    });
    test('se cuentan los que ya no alcanza (baja, sin correo, borrado)', () => expect(r.omitidos, 3));
    test('y no se repite quien está dos veces', () {
      expect(r.correos.where((c) => c == 'ana@sisol.com.mx').length, 1);
    });
  });

  group('el nombre de un perfil', () {
    test('completo', () => expect(nombreDe({'nombre': 'Ana', 'paterno': 'López', 'materno': 'R'}), 'Ana López R'));
    test('sin materno', () => expect(nombreDe({'nombre': 'Ana', 'paterno': 'López'}), 'Ana López'));
    test('sin nada', () => expect(nombreDe({'nombre': ' ', 'paterno': null}), isNull));
  });

  // ─── Las imágenes del editor ──────────────────────────────────────────────
  group('la imagen que se sube', () {
    Uint8List jpg(int ancho, int alto) => img.encodeJpg(img.Image(width: ancho, height: alto));

    test('una foto ancha se reduce al ancho de correo, sin deformarse', () {
      final r = prepararImagen(jpg(4000, 2000), 'foto.jpg')!;
      final leida = img.decodeImage(r.bytes)!;
      expect(leida.width, anchoMaximoImagen);
      expect(leida.height, anchoMaximoImagen ~/ 2);
      expect(r.extension, 'jpg');
    });

    test('pesa mucho menos que la original', () {
      final original = jpg(4000, 3000);
      final r = prepararImagen(original, 'foto.jpg')!;
      expect(r.bytes.length, lessThan(original.length));
    });

    test('una estrecha no se agranda', () {
      final r = prepararImagen(jpg(300, 200), 'chica.jpg')!;
      expect(img.decodeImage(r.bytes)!.width, 300);
    });

    test('se gira según sus metadatos (las fotos de celular salían de lado)', () {
      // Orientación EXIF 6: «gira 90°». La imagen guardada es ancha, pero se debe VER alta.
      final ancha = img.Image(width: 200, height: 100);
      ancha.exif.imageIfd.orientation = 6;
      final r = prepararImagen(img.encodeJpg(ancha), 'celular.jpg')!;
      final leida = img.decodeImage(r.bytes)!;
      expect(leida.width, 100, reason: 'sin bakeOrientation la foto sale de lado');
      expect(leida.height, 200);
    });

    test('con transparencia sale en PNG, para no ponerle fondo negro a un logotipo', () {
      final logo = img.Image(width: 50, height: 50, numChannels: 4);
      final r = prepararImagen(img.encodePng(logo), 'logo.png')!;
      expect(r.extension, 'png');
      expect(r.tipo, 'image/png');
    });

    test('un WebP se convierte: muchos clientes de correo no lo muestran', () {
      // No hay codificador WebP en la librería, así que se usa un PNG sin transparencia con nombre
      // .webp: lo que se prueba es que la salida nunca es webp.
      final r = prepararImagen(img.encodePng(img.Image(width: 40, height: 40)), 'x.webp')!;
      expect(r.extension, isNot('webp'));
    });

    test('un GIF se deja tal cual, para no romper la animación', () {
      final gif = img.encodeGif(img.Image(width: 30, height: 30));
      final r = prepararImagen(gif, 'anim.gif')!;
      expect(r.bytes, same(gif));
      expect(r.extension, 'gif');
    });

    test('algo que no es imagen no revienta: devuelve null', () {
      expect(prepararImagen(Uint8List.fromList([1, 2, 3, 4]), 'x.jpg'), isNull);
    });
  });

  // El nombre decide qué descarga la función: tiene que salir con la forma EXACTA que acepta.
  group('el nombre de la imagen', () {
    test('32 hexadecimales y su extensión, como exige el servidor', () {
      for (final ext in ['jpg', 'png', 'gif']) {
        expect(esRutaImagen(nombreImagen(ext)), isTrue, reason: nombreImagen(ext));
      }
    });
    test('cada vez uno distinto', () {
      final nombres = {for (var i = 0; i < 200; i++) nombreImagen('jpg')};
      expect(nombres.length, 200);
    });
    // Los mismos casos que `verificar_contenido.mjs`: la pantalla sólo pinta como imagen lo que el
    // correo va a llevar como imagen.
    for (final mala in [
      '../secreto.png',
      'https://x.com/a.png',
      'x.png',
      '${'A3F1' * 8}.png',
      '${'a3f1' * 8}.svg',
      '${'a3f1' * 8}.png?x=1',
      'data:image/png;base64,AAAA',
    ]) {
      test('«${mala.length > 30 ? '${mala.substring(0, 30)}…' : mala}» no es una imagen del editor',
          () => expect(esRutaImagen(mala), isFalse));
    }
  });

  // ─── El editor sólo ofrece lo que el servidor sabe convertir ──────────────
  //
  // La barra de herramientas está en `correspondencia_page.dart` y el conversor a HTML en
  // `supabase/functions/correspondencia/contenido.ts`. Un botón encendido aquí que el conversor no
  // conozca aparecería en pantalla y DESAPARECERÍA en el correo sin avisar. Se lee el fuente, como
  // `menu_agrupado_test.dart`, para que la prueba no pueda quedar mirando una copia vieja.
  group('la barra del editor y el conversor dicen lo mismo', () {
    final pagina = File('lib/correspondencia_page.dart').readAsStringSync();
    final conversor = File('supabase/functions/correspondencia/contenido.ts').readAsStringSync();

    // Los formatos que el conversor NO tiene y que por eso tienen que estar apagados en la barra.
    const apagados = [
      'showFontFamily', 'showFontSize', 'showSmallButton', 'showLineHeightButton',
      'showInlineCode', 'showCodeBlock', 'showListCheck', 'showIndent',
      'showSubscript', 'showSuperscript', 'showDirection', 'showJustifyAlignment',
    ];
    for (final b in apagados) {
      test('«$b» está apagado', () {
        expect(RegExp('$b:\\s*false').hasMatch(pagina), isTrue,
            reason: 'Encendido, ofrecería un formato que el correo no lleva.');
      });
    }

    test('los títulos se limitan a 1, 2 y 3', () {
      expect(pagina, contains('attributes: [Attribute.h1, Attribute.h2, Attribute.h3, Attribute.header]'));
    });

    // Y del otro lado, que el conversor sí maneja cada formato que la barra deja encendido.
    const conversorManeja = {
      'negrita': 'attrs.bold',
      'cursiva': 'attrs.italic',
      'subrayado': 'attrs.underline',
      'tachado': 'attrs.strike',
      'color': 'attrs.color',
      'color de fondo': 'attrs.background',
      'enlace': 'attrs.link',
      'títulos': 'attrs.header',
      'listas': 'attrs.list',
      'cita': 'attrs.blockquote',
      'alineación': 'attrs.align',
    };
    for (final e in conversorManeja.entries) {
      test('el conversor maneja «${e.key}»', () {
        expect(conversor, contains(e.value),
            reason: 'La barra lo ofrece y el conversor lo ignoraría: saldría como texto normal.');
      });
    }
  });
}
