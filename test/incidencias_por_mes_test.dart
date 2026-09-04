import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/incidencias_por_mes.dart';

Map<String, dynamic> inc(String inicio, String status, int dias, String quien) => {
      'fecha_inicio': inicio,
      'status': status,
      'dias': dias,
      'usuario_id': quien,
    };

void main() {
  group('aniosConDatos', () {
    test('del más reciente al más viejo, sin repetir', () {
      final r = aniosConDatos([
        inc('2026-03-01', 'APROBADA', 3, 'a'),
        inc('2024-12-20', 'APROBADA', 5, 'b'),
        inc('2026-11-02', 'APROBADA', 2, 'c'),
        inc('2015-02-10', 'APROBADA', 7, 'd'),
      ]);
      expect(r, [2026, 2024, 2015]);
    });

    test('una fila sin fecha no inventa un año', () {
      final r = aniosConDatos([
        {'fecha_inicio': null, 'status': 'APROBADA', 'dias': 3},
        inc('2026-01-01', 'APROBADA', 1, 'a'),
      ]);
      expect(r, [2026]);
    });

    test('sin datos, lista vacía', () => expect(aniosConDatos([]), isEmpty));
  });

  group('resumirAnio', () {
    test('siempre devuelve los DOCE meses, incluidos los vacíos', () {
      // Un mes sin registros es información: diciembre se llena y febrero no. Saltárselo haría
      // parecer que falta un dato en lugar de que fue un mes tranquilo.
      final r = resumirAnio([inc('2026-03-10', 'APROBADA', 3, 'a')], 2026);
      expect(r, hasLength(12));
      expect(r.map((m) => m.mes), List.generate(12, (i) => i + 1));
      expect(r[2].registros, 1, reason: 'marzo');
      expect(r[1].vacio, isTrue, reason: 'febrero');
      expect(r[2].nombreMes, 'Marzo');
    });

    test('cuenta por estatus y suma los días', () {
      final r = resumirAnio([
        inc('2026-03-02', 'APROBADA', 5, 'a'),
        inc('2026-03-15', 'PENDIENTE', 3, 'b'),
        inc('2026-03-20', 'CANCELADA', 4, 'c'),
      ], 2026);
      final marzo = r[2];
      expect(marzo.registros, 3);
      expect(marzo.aprobadas, 1);
      expect(marzo.pendientes, 1);
      expect(marzo.canceladas, 1);
    });

    test('una CANCELADA no consume días ni cuenta como persona', () {
      // Es la regla que ya usa la página para el saldo: la cancelada se dio de baja.
      final r = resumirAnio([
        inc('2026-03-02', 'APROBADA', 5, 'a'),
        inc('2026-03-20', 'CANCELADA', 40, 'z'),
      ], 2026);
      expect(r[2].dias, 5, reason: 'los 40 de la cancelada NO entran');
      expect(r[2].personas, 1, reason: 'la persona de la cancelada tampoco');
    });

    test('una PENDIENTE SÍ consume días', () {
      // Decisión de junio, con su comentario largo en la página: una pendiente reserva los días.
      final r = resumirAnio([
        inc('2026-03-02', 'APROBADA', 5, 'a'),
        inc('2026-03-15', 'PENDIENTE', 3, 'b'),
      ], 2026);
      expect(r[2].dias, 8);
    });

    test('el mes es el de fecha_inicio, no el de captura', () {
      // Unas vacaciones pedidas en noviembre para diciembre cuentan en DICIEMBRE.
      final r = resumirAnio([
        {
          'fecha_inicio': '2026-12-20',
          'created_at': '2026-11-03T10:00:00Z',
          'status': 'APROBADA',
          'dias': 5,
          'usuario_id': 'a',
        }
      ], 2026);
      expect(r[10].registros, 0, reason: 'noviembre');
      expect(r[11].registros, 1, reason: 'diciembre');
    });

    test('la misma persona dos veces en un mes cuenta como UNA', () {
      final r = resumirAnio([
        inc('2026-03-02', 'APROBADA', 2, 'a'),
        inc('2026-03-20', 'APROBADA', 3, 'a'),
      ], 2026);
      expect(r[2].registros, 2);
      expect(r[2].personas, 1);
      expect(r[2].dias, 5);
    });

    test('otro año no se cuela', () {
      final r = resumirAnio([
        inc('2025-03-02', 'APROBADA', 9, 'a'),
        inc('2026-03-02', 'APROBADA', 2, 'b'),
      ], 2026);
      expect(r[2].registros, 1);
      expect(r[2].dias, 2);
    });

    test('una fecha con hora se lee igual', () {
      final r = resumirAnio([
        {'fecha_inicio': '2026-03-02T00:00:00Z', 'status': 'APROBADA', 'dias': 2,
         'usuario_id': 'a'}
      ], 2026);
      expect(r[2].registros, 1);
    });

    test('un estatus raro cuenta como registro pero no como ninguno de los tres', () {
      // No se supone nada: se ve en el total de registros y no ensucia las columnas.
      final r = resumirAnio([inc('2026-03-02', 'EN REVISION', 2, 'a')], 2026);
      expect(r[2].registros, 1);
      expect(r[2].aprobadas, 0);
      expect(r[2].pendientes, 0);
      expect(r[2].canceladas, 0);
      expect(r[2].dias, 2, reason: 'no está cancelada, así que sus días cuentan');
    });

    test('sin días no revienta', () {
      final r = resumirAnio([
        {'fecha_inicio': '2026-03-02', 'status': 'APROBADA', 'usuario_id': 'a'}
      ], 2026);
      expect(r[2].dias, 0);
    });
  });

  group('totalDelAnio', () {
    test('los totales cuadran con la suma de los meses', () {
      final datos = [
        inc('2026-03-02', 'APROBADA', 5, 'a'),
        inc('2026-07-10', 'APROBADA', 3, 'b'),
        inc('2026-12-20', 'PENDIENTE', 2, 'c'),
        inc('2026-12-21', 'CANCELADA', 9, 'd'),
      ];
      final meses = resumirAnio(datos, 2026);
      final t = totalDelAnio(datos, 2026);
      expect(t.registros, meses.fold<int>(0, (s, m) => s + m.registros));
      expect(t.dias, meses.fold<int>(0, (s, m) => s + m.dias));
      expect(t.registros, 4);
      expect(t.dias, 10, reason: '5 + 3 + 2, sin los 9 de la cancelada');
      expect(t.canceladas, 1);
    });

    test('las PERSONAS del año NO son la suma de las mensuales', () {
      // Quien tomó vacaciones en marzo y en julio es UNA persona en el año y dos en la suma de los
      // meses. Es el error clásico de esta clase de tabla.
      final datos = [
        inc('2026-03-02', 'APROBADA', 5, 'a'),
        inc('2026-07-10', 'APROBADA', 3, 'a'),
      ];
      final meses = resumirAnio(datos, 2026);
      expect(meses.fold<int>(0, (s, m) => s + m.personas), 2,
          reason: 'sumando los meses salen dos');
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
