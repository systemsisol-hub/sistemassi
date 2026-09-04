import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/incidencias_por_periodo.dart';

Map<String, dynamic> inc(String inicio, String status, int dias, String quien) => {
      'fecha_inicio': inicio,
      'status': status,
      'dias': dias,
      'usuario_id': quien,
    };

/// El índice de una quincena en la lista de 24: (mes - 1) * 2 + (mitad - 1).
int idx(int mes, int mitad) => (mes - 1) * 2 + (mitad - 1);

void main() {
  group('aniosConDatos', () {
    test('del más reciente al más viejo, sin repetir', () {
      expect(
          aniosConDatos([
            inc('2026-03-01', 'APROBADA', 3, 'a'),
            inc('2024-12-20', 'APROBADA', 5, 'b'),
            inc('2026-11-02', 'APROBADA', 2, 'c'),
            inc('2015-02-10', 'APROBADA', 7, 'd'),
          ]),
          [2026, 2024, 2015]);
    });

    test('una fila sin fecha no inventa un año', () {
      expect(
          aniosConDatos([
            {'fecha_inicio': null, 'status': 'APROBADA', 'dias': 3},
            inc('2026-01-01', 'APROBADA', 1, 'a'),
          ]),
          [2026]);
    });

    test('sin datos, lista vacía', () => expect(aniosConDatos([]), isEmpty));
  });

  group('el corte de la quincena', () {
    test('el día 1 y el 15 caen en la PRIMERA', () {
      final r = resumirAnio([
        inc('2026-07-01', 'APROBADA', 1, 'a'),
        inc('2026-07-15', 'APROBADA', 1, 'b'),
      ], 2026);
      expect(r[idx(7, 1)].registros, 2);
      expect(r[idx(7, 2)].registros, 0);
    });

    test('el día 16 abre la SEGUNDA', () {
      final r = resumirAnio([inc('2026-07-16', 'APROBADA', 1, 'a')], 2026);
      expect(r[idx(7, 1)].registros, 0);
      expect(r[idx(7, 2)].registros, 1);
    });

    test('el día 31 SÍ cae en la segunda, no se pierde', () {
      // «Del 16 al 30» dejaría el 31 fuera de toda quincena siete veces al año, y con él sus días.
      final r = resumirAnio([inc('2026-07-31', 'APROBADA', 4, 'a')], 2026);
      expect(r[idx(7, 2)].registros, 1);
      expect(r[idx(7, 2)].dias, 4);
      expect(r[idx(7, 2)].etiqueta, '16–31 julio');
    });

    test('febrero de un año NO bisiesto llega al 28', () {
      final r = resumirAnio([inc('2026-02-28', 'APROBADA', 1, 'a')], 2026);
      expect(r[idx(2, 2)].registros, 1);
      expect(r[idx(2, 2)].etiqueta, '16–28 febrero');
    });

    test('febrero BISIESTO llega al 29', () {
      final r = resumirAnio([inc('2028-02-29', 'APROBADA', 1, 'a')], 2028);
      expect(r[idx(2, 2)].registros, 1);
      expect(r[idx(2, 2)].etiqueta, '16–29 febrero');
    });

    test('abril, de 30 días', () {
      final r = resumirAnio([inc('2026-04-30', 'APROBADA', 1, 'a')], 2026);
      expect(r[idx(4, 2)].registros, 1);
      expect(r[idx(4, 2)].etiqueta, '16–30 abril');
    });
  });

  group('resumirAnio', () {
    test('siempre devuelve las VEINTICUATRO quincenas, incluidas las vacías', () {
      final r = resumirAnio([inc('2026-03-10', 'APROBADA', 3, 'a')], 2026);
      expect(r, hasLength(24));
      expect(r.first.etiqueta, '1–15 enero');
      expect(r.last.etiqueta, '16–31 diciembre');
      expect(r[idx(3, 1)].registros, 1);
      expect(r[idx(3, 2)].vacio, isTrue);
    });

    test('cuenta por estatus', () {
      final r = resumirAnio([
        inc('2026-03-02', 'APROBADA', 5, 'a'),
        inc('2026-03-05', 'PENDIENTE', 3, 'b'),
        inc('2026-03-08', 'CANCELADA', 4, 'c'),
      ], 2026);
      final q = r[idx(3, 1)];
      expect(q.registros, 3);
      expect(q.aprobadas, 1);
      expect(q.pendientes, 1);
      expect(q.canceladas, 1);
    });

    test('una CANCELADA no consume días ni cuenta como persona', () {
      final r = resumirAnio([
        inc('2026-03-02', 'APROBADA', 5, 'a'),
        inc('2026-03-03', 'CANCELADA', 40, 'z'),
      ], 2026);
      expect(r[idx(3, 1)].dias, 5, reason: 'los 40 de la cancelada NO entran');
      expect(r[idx(3, 1)].personas, 1);
    });

    test('una PENDIENTE SÍ consume días', () {
      final r = resumirAnio([
        inc('2026-03-02', 'APROBADA', 5, 'a'),
        inc('2026-03-03', 'PENDIENTE', 3, 'b'),
      ], 2026);
      expect(r[idx(3, 1)].dias, 8);
    });

    test('el periodo es el de fecha_inicio, no el de captura', () {
      // Pedidas el 3 de noviembre para el 20 de diciembre: cuentan en la SEGUNDA de diciembre.
      final r = resumirAnio([
        {
          'fecha_inicio': '2026-12-20',
          'created_at': '2026-11-03T10:00:00Z',
          'status': 'APROBADA',
          'dias': 5,
          'usuario_id': 'a',
        }
      ], 2026);
      expect(r[idx(11, 1)].registros, 0);
      expect(r[idx(12, 2)].registros, 1);
    });

    test('la misma persona dos veces en una quincena cuenta como UNA', () {
      final r = resumirAnio([
        inc('2026-03-02', 'APROBADA', 2, 'a'),
        inc('2026-03-09', 'APROBADA', 3, 'a'),
      ], 2026);
      expect(r[idx(3, 1)].registros, 2);
      expect(r[idx(3, 1)].personas, 1);
      expect(r[idx(3, 1)].dias, 5);
    });

    test('otro año no se cuela', () {
      final r = resumirAnio([
        inc('2025-03-02', 'APROBADA', 9, 'a'),
        inc('2026-03-02', 'APROBADA', 2, 'b'),
      ], 2026);
      expect(r[idx(3, 1)].registros, 1);
      expect(r[idx(3, 1)].dias, 2);
    });

    test('una fecha con hora se lee igual', () {
      final r = resumirAnio([
        {'fecha_inicio': '2026-03-02T00:00:00Z', 'status': 'APROBADA', 'dias': 2,
         'usuario_id': 'a'}
      ], 2026);
      expect(r[idx(3, 1)].registros, 1);
    });

    test('un estatus raro cuenta como registro y no ensucia las columnas', () {
      final r = resumirAnio([inc('2026-03-02', 'EN REVISION', 2, 'a')], 2026);
      final q = r[idx(3, 1)];
      expect(q.registros, 1);
      expect(q.aprobadas, 0);
      expect(q.pendientes, 0);
      expect(q.canceladas, 0);
      expect(q.dias, 2, reason: 'no está cancelada, así que sus días cuentan');
    });

    test('sin días no revienta', () {
      final r = resumirAnio([
        {'fecha_inicio': '2026-03-02', 'status': 'APROBADA', 'usuario_id': 'a'}
      ], 2026);
      expect(r[idx(3, 1)].dias, 0);
    });
  });

  group('totalDelAnio', () {
    test('los totales cuadran con la suma de las quincenas', () {
      final datos = [
        inc('2026-03-02', 'APROBADA', 5, 'a'),
        inc('2026-07-20', 'APROBADA', 3, 'b'),
        inc('2026-12-20', 'PENDIENTE', 2, 'c'),
        inc('2026-12-21', 'CANCELADA', 9, 'd'),
      ];
      final periodos = resumirAnio(datos, 2026);
      final t = totalDelAnio(datos, 2026);
      expect(t.registros, periodos.fold<int>(0, (s, p) => s + p.registros));
      expect(t.dias, periodos.fold<int>(0, (s, p) => s + p.dias));
      expect(t.registros, 4);
      expect(t.dias, 10, reason: '5 + 3 + 2, sin los 9 de la cancelada');
      expect(t.canceladas, 1);
    });

    test('las PERSONAS del año NO son la suma de las quincenales', () {
      // Quien tomó vacaciones en marzo y en julio es UNA persona en el año y dos sumando periodos.
      // Es el error clásico de esta clase de tabla.
      final datos = [
        inc('2026-03-02', 'APROBADA', 5, 'a'),
        inc('2026-07-20', 'APROBADA', 3, 'a'),
      ];
      expect(resumirAnio(datos, 2026).fold<int>(0, (s, p) => s + p.personas), 2,
          reason: 'sumando quincenas salen dos');
      expect(totalDelAnio(datos, 2026).personas, 1, reason: 'pero es una sola persona');
    });

    test('un año sin nada da ceros', () {
      final t = totalDelAnio([inc('2025-03-02', 'APROBADA', 5, 'a')], 2026);
      expect(t.registros, 0);
      expect(t.dias, 0);
      expect(t.personas, 0);
    });
  });
}
