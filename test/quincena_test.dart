import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/services/quincena.dart';

/// Pedido tal cual: «los periodos serán del 1 al 15 y del 16 al 30 o 31 según el mes».
///
/// El «según el mes» es toda la prueba. Un 30 fijo dejaría el día 31 fuera de cualquier quincena siete
/// veces al año —y con él las faltas y los retardos de ese día— y en febrero contaría días que no
/// existen. Es un fallo que no se ve mirando la pantalla: sólo aparece el 31 de un mes concreto.
void main() {
  group('los cortes del mes', () {
    test('la primera quincena siempre es del 1 al 15', () {
      for (final mes in [1, 2, 4, 12]) {
        final q = Quincena(2026, mes, 1);
        expect(q.diaInicial, 1);
        expect(q.diaFinal, 15, reason: 'mes $mes');
      }
    });

    test('la segunda llega al ultimo dia REAL del mes', () {
      expect(Quincena(2026, 1, 2).diaFinal, 31, reason: 'enero');
      expect(Quincena(2026, 4, 2).diaFinal, 30, reason: 'abril');
      expect(Quincena(2026, 7, 2).diaFinal, 31, reason: 'julio');
      expect(Quincena(2026, 12, 2).diaFinal, 31, reason: 'diciembre');
    });

    test('febrero, bisiesto y no bisiesto', () {
      expect(Quincena(2026, 2, 2).diaFinal, 28, reason: '2026 no es bisiesto');
      expect(Quincena(2028, 2, 2).diaFinal, 29, reason: '2028 sí lo es');
      // El caso que casi todas las reglas caseras fallan: los múltiplos de 100 no son bisiestos, salvo
      // los de 400.
      expect(Quincena(2100, 2, 2).diaFinal, 28, reason: '2100 no es bisiesto');
      expect(Quincena(2000, 2, 2).diaFinal, 29, reason: '2000 sí lo es');
    });
  });

  group('a que quincena pertenece una fecha', () {
    test('el dia 15 es de la primera y el 16 de la segunda', () {
      expect(Quincena.deIso('2026-07-15')!.mitad, 1);
      expect(Quincena.deIso('2026-07-16')!.mitad, 2);
    });

    test('el primero y el ultimo dia del mes caen en su quincena', () {
      expect(Quincena.deIso('2026-07-01')!.mitad, 1);
      expect(Quincena.deIso('2026-07-31')!.mitad, 2);
    });

    test('una fecha ilegible no revienta', () {
      for (final malo in [null, '', '2026-07', 'ayer', '____-__-__']) {
        expect(Quincena.deIso(malo), isNull, reason: 'con "$malo"');
      }
    });
  });

  group('contiene', () {
    test('el dia 31 NO se queda fuera: es el caso que motivo la prueba', () {
      final q = Quincena(2026, 7, 2);
      expect(q.contiene('2026-07-31'), isTrue);
      expect(q.contiene('2026-07-16'), isTrue);
      // Y el 15 es de la otra.
      expect(q.contiene('2026-07-15'), isFalse);
    });

    test('no se cuela el mes vecino', () {
      final q = Quincena(2026, 7, 2);
      expect(q.contiene('2026-08-01'), isFalse);
      expect(q.contiene('2026-06-30'), isFalse);
    });

    test('febrero no cuenta dias que no existen', () {
      final q = Quincena(2026, 2, 2);
      expect(q.hastaIso, '2026-02-28');
      expect(q.contiene('2026-02-28'), isTrue);
      // Un 29 de febrero de un año no bisiesto no debería existir en los datos, y si aparece por un
      // error de captura, queda fuera en lugar de colarse.
      expect(q.contiene('2026-02-29'), isFalse);
    });

    test('cada dia del mes cae en EXACTAMENTE una quincena', () {
      // La propiedad que de verdad importa: ni un día sin periodo, ni un día en dos.
      for (final (anio, mes) in [(2026, 1), (2026, 2), (2028, 2), (2026, 4), (2026, 12)]) {
        final primera = Quincena(anio, mes, 1);
        final segunda = Quincena(anio, mes, 2);
        for (var d = 1; d <= segunda.ultimoDia; d++) {
          final iso = '$anio-${mes.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
          final dentro = [primera.contiene(iso), segunda.contiene(iso)].where((x) => x).length;
          expect(dentro, 1, reason: '$iso cayó en $dentro quincenas');
        }
      }
    });
  });

  group('presentacion y orden', () {
    test('la etiqueta dice el rango y el año', () {
      expect(Quincena(2026, 7, 1).etiqueta, '1 al 15 de julio 2026');
      expect(Quincena(2026, 7, 2).etiqueta, '16 al 31 de julio 2026');
      expect(Quincena(2026, 2, 2).etiqueta, '16 al 28 de febrero 2026');
    });

    test('la clave ordena cronologicamente como texto', () {
      final claves = [
        Quincena(2026, 7, 2), Quincena(2026, 7, 1),
        Quincena(2025, 12, 2), Quincena(2026, 1, 1),
      ].map((q) => q.clave).toList()
        ..sort();
      expect(claves, ['2025-12-2', '2026-01-1', '2026-07-1', '2026-07-2']);
    });

    test('dos quincenas del mismo tramo son iguales', () {
      expect(Quincena(2026, 7, 2), Quincena(2026, 7, 2));
      expect(Quincena(2026, 7, 2) == Quincena(2026, 7, 1), isFalse);
      // Igualdad y hashCode a la par: el desplegable las mete en un Set.
      expect({Quincena(2026, 7, 2), Quincena(2026, 7, 2)}.length, 1);
    });
  });
}
