import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sistemassi/services/checador.dart';

/// Las reglas del checador. Son las mismas del disparador `checada_antes_de_guardar`: si cambian
/// aquí y no allá, la pantalla ofrecería botones que la base rechaza.
void main() {
  group('lo que se puede checar', () {
    test('sin nada, sólo la entrada', () {
      expect(checadasPosibles({}), ['ENTRADA']);
    });
    test('después de entrar: comer o terminar, comer primero', () {
      expect(checadasPosibles({'ENTRADA'}), ['SALIDA_COMIDA', 'SALIDA']);
    });
    test('comiendo, sólo el regreso', () {
      expect(checadasPosibles({'ENTRADA', 'SALIDA_COMIDA'}), ['REGRESO_COMIDA']);
    });
    test('de regreso de comer, sólo terminar', () {
      expect(checadasPosibles({'ENTRADA', 'SALIDA_COMIDA', 'REGRESO_COMIDA'}), ['SALIDA']);
    });
    test('con la jornada terminada, nada', () {
      expect(checadasPosibles({'ENTRADA', 'SALIDA'}), isEmpty);
      expect(checadasPosibles(tiposDeChecada.toSet()), isEmpty);
    });
    test('cada tipo tiene nombre', () {
      for (final t in tiposDeChecada) {
        expect(nombreDeChecada[t], isNotNull, reason: t);
      }
    });
  });

  group('la foto', () {
    test('se reduce a 800 de ancho y sale en JPEG', () {
      final grande = img.Image(width: 1920, height: 1080);
      final lista = prepararFotoChecada(Uint8List.fromList(img.encodePng(grande)))!;
      final leida = img.decodeJpg(lista)!;
      expect(leida.width, anchoFotoChecada);
      expect(leida.height, 450);
    });
    test('una chica no se agranda', () {
      final chica = img.Image(width: 320, height: 240);
      final leida = img.decodeJpg(prepararFotoChecada(Uint8List.fromList(img.encodePng(chica)))!)!;
      expect(leida.width, 320);
    });
    test('lo que no es imagen da null, no una excepción', () {
      expect(prepararFotoChecada(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
    });
  });

  test('la ruta va en la carpeta de la persona y por día', () {
    final r = rutaFotoChecada('abc-123', DateTime(2026, 9, 8));
    expect(r, matches(RegExp(r'^abc-123/2026-09-08/[0-9a-f]{32}\.jpg$')));
    expect(rutaFotoChecada('abc-123', DateTime(2026, 9, 8)), isNot(r));
  });

  test('precisión en palabras', () {
    expect(precisionEnPalabras(12.4), '± 12 m');
    expect(precisionEnPalabras(2500), '± 2.5 km');
    expect(precisionEnPalabras(null), 'precisión desconocida');
  });

  test('enlace al mapa', () {
    expect(enlaceAlMapa(20.63, -87.07),
        'https://www.google.com/maps/search/?api=1&query=20.63,-87.07');
  });
}
