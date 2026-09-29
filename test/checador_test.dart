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

  group('horario y semáforo', () {
    // El horario «Ag117 L-S»: lunes a sábado, entrada 9:00 con 15 de tolerancia, salida 18:00
    // entre semana y 15:00 el sábado.
    final reglas = [
      for (var d = 1; d <= 5; d++) ...[
        {'day': d, 'tol': 15, 'time': '09:00:00', 'type': 'ENTRADA'},
        {'day': d, 'tol': 0, 'time': '18:00:00', 'type': 'SALIDA'},
      ],
      {'day': 6, 'tol': 15, 'time': '09:00:00', 'type': 'ENTRADA'},
      {'day': 6, 'tol': 0, 'time': '15:00:00', 'type': 'SALIDA'},
    ];

    test('el día del horario sale del día de la semana', () {
      final lunes = reglasDelDia(reglas, DateTime(2026, 9, 28));
      expect(lunes.entrada!.hora, '09:00');
      expect(lunes.salida!.hora, '18:00');
      expect(reglasDelDia(reglas, DateTime(2026, 10, 3)).salida!.hora, '15:00'); // sábado
      expect(reglasDelDia(reglas, DateTime(2026, 10, 4)).entrada, isNull); // domingo
      expect(reglasDelDia(null, DateTime(2026, 9, 28)).entrada, isNull);
    });

    test('entrada: verde, amarillo en tolerancia, rojo después', () {
      const r = ReglaDia(9 * 60, 15);
      expect(semaforoEntrada(8 * 60 + 50, r), Semaforo.verde);
      expect(semaforoEntrada(9 * 60, r), Semaforo.verde);
      expect(semaforoEntrada(9 * 60 + 1, r), Semaforo.amarillo);
      expect(semaforoEntrada(9 * 60 + 15, r), Semaforo.amarillo);
      expect(semaforoEntrada(9 * 60 + 16, r), Semaforo.rojo);
    });

    test('salida: rojo antes, verde a su hora, amarillo mucho después', () {
      const r = ReglaDia(18 * 60, 0);
      expect(semaforoSalida(17 * 60 + 59, r), Semaforo.rojo);
      expect(semaforoSalida(18 * 60, r), Semaforo.verde);
      expect(semaforoSalida(18 * 60 + 30, r), Semaforo.verde);
      expect(semaforoSalida(18 * 60 + 31, r), Semaforo.amarillo);
    });

    test('la hora local sale de dónde se checó', () {
      final utc = DateTime.utc(2026, 9, 28, 14, 5);
      // Playa del Carmen: UTC-5.
      expect(horaLocalDeChecada(utc, 20.63, -87.07), DateTime(2026, 9, 28, 9, 5));
      // Ciudad de México: UTC-6.
      expect(horaLocalDeChecada(utc, 19.43, -99.13), DateTime(2026, 9, 28, 8, 5));
      // Sin coordenadas, la del centro.
      expect(desfaseHorasDe(null, null), -6);
      // Ensenada: UTC-7 en verano, UTC-8 en invierno.
      expect(horaLocalDeChecada(DateTime.utc(2026, 7, 29, 16, 6), 31.87, -116.6),
          DateTime(2026, 7, 29, 9, 6));
      expect(horaLocalDeChecada(DateTime.utc(2026, 12, 1, 17, 0), 31.87, -116.6),
          DateTime(2026, 12, 1, 9, 0));
    });

    test('manda la hora local que calcula la base', () {
      // Una de appchecar: sin coordenadas, con la hora que la base sacó de su sucursal.
      final fila = {
        'registrada_en': '2026-07-16T13:12:00+00:00',
        'hora_local': '2026-07-16T08:12:00',
        'latitud': null,
        'longitud': null,
      };
      expect(horaLocalDeFila(fila), DateTime(2026, 7, 16, 8, 12));
      // Sin `hora_local`, se calcula por las coordenadas.
      expect(horaLocalDeFila({'registrada_en': '2026-09-29T13:24:00Z', 'latitud': 19.4, 'longitud': -99.1}),
          DateTime(2026, 9, 29, 7, 24));
    });

    test('la diferencia contra el horario', () {
      // El caso del pedido: checó 07:24 y su entrada es a las 08:00.
      final ocho = [
        {'day': 2, 'tol': 15, 'time': '08:00:00', 'type': 'ENTRADA'},
        {'day': 2, 'tol': 0, 'time': '18:00:00', 'type': 'SALIDA'},
      ];
      final martes = DateTime(2026, 9, 29, 7, 24);
      final d = diferenciaContraHorario('ENTRADA', martes, ocho)!;
      expect(d.minutos, -36);
      expect(d.color, Semaforo.verde);
      expect(diferenciaCorta(d.minutos), '- 36m');

      final tarde = diferenciaContraHorario('ENTRADA', DateTime(2026, 9, 29, 8, 12), ocho)!;
      expect((tarde.minutos, tarde.color), (12, Semaforo.amarillo));
      expect(diferenciaCorta(12), '+ 12m');
      expect(diferenciaContraHorario('ENTRADA', DateTime(2026, 9, 29, 9, 5), ocho)!.color,
          Semaforo.rojo);

      final salio = diferenciaContraHorario('SALIDA', DateTime(2026, 9, 29, 17, 45), ocho)!;
      expect((salio.minutos, salio.color), (-15, Semaforo.rojo));
      // Los ejemplos del pedido.
      expect(diferenciaCorta(8 * 60 + 12), '+ 8h 12m');
      expect(diferenciaCorta(-(60 + 32)), '- 1h 32m');
      expect(diferenciaCorta(5), '+ 5m');
      expect(diferenciaCorta(120), '+ 2h');
      expect(diferenciaCorta(0), '0m');

      // La comida no tiene hora; un día sin horario, tampoco.
      expect(diferenciaContraHorario('SALIDA_COMIDA', martes, ocho), isNull);
      expect(diferenciaContraHorario('ENTRADA', DateTime(2026, 9, 27, 8), ocho), isNull);
    });

    test('el contador', () {
      const e = ReglaDia(9 * 60, 15);
      const s = ReglaDia(18 * 60, 0);
      ({String texto, Semaforo? color}) a(int h, int m, {bool entro = false, bool salio = false}) =>
          contadorDelDia(
              ahora: DateTime(2026, 9, 28, h, m), entrada: e, salida: s,
              yaEntro: entro, yaSalio: salio);
      expect(a(8, 40).color, Semaforo.verde);
      expect(a(8, 40).texto, contains('20 min para tu entrada (09:00)'));
      expect(a(9, 10).color, Semaforo.amarillo);
      expect(a(9, 10).texto, contains('te quedan 5 min'));
      expect(a(10, 5).color, Semaforo.rojo);
      expect(a(10, 5).texto, contains('1 h 05 min de retardo'));
      expect(a(15, 0, entro: true).texto, contains('3 h para tu salida (18:00)'));
      expect(a(18, 10, entro: true).texto, contains('Ya es tu hora de salida'));
      expect(a(19, 0, entro: true).color, Semaforo.amarillo);
      expect(a(19, 0, entro: true, salio: true).color, isNull);
      expect(
          contadorDelDia(
                  ahora: DateTime(2026, 10, 4, 10), entrada: null, salida: null,
                  yaEntro: false, yaSalio: false)
              .texto,
          contains('no tienes horario'));
    });
  });
}
