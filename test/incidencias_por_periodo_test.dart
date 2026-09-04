import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/incidencias_por_periodo.dart';
import 'package:sistemassi/services/quincena.dart';

Map<String, dynamic> reg({
  required String inicio,
  String status = 'APROBADA',
  int dias = 1,
  String quien = 'a',
  String? elaborada,
  String? fin,
  String? regreso,
  String nombre = 'ALGUIEN',
  String periodo = '2025 - 2026',
}) =>
    {
      'created_at': elaborada ?? '${inicio}T10:00:00Z',
      'status': status,
      'nombre_usuario': nombre,
      'periodo': periodo,
      'dias': dias,
      'fecha_inicio': inicio,
      'fecha_fin': fin ?? inicio,
      'fecha_regreso': regreso,
      'usuario_id': quien,
    };

void main() {
  group('quincenasConDatos', () {
    test('de la más reciente a la más antigua, sin repetir', () {
      final q = quincenasConDatos([
        reg(inicio: '2026-08-20'),
        reg(inicio: '2026-08-03'),
        reg(inicio: '2026-08-28'),
        reg(inicio: '2025-01-14'),
      ]);
      expect(q.map((x) => x.clave), ['2026-08-2', '2026-08-1', '2025-01-1']);
      expect(q.first.etiquetaCorta, '16–31 agosto');
    });

    test('una fila sin fecha no crea una quincena', () {
      final q = quincenasConDatos([
        {'fecha_inicio': null, 'status': 'APROBADA'},
        reg(inicio: '2026-08-03'),
      ]);
      expect(q, hasLength(1));
    });

    test('sin datos, lista vacía', () => expect(quincenasConDatos([]), isEmpty));
  });

  group('el borde de la quincena', () {
    final datos = [
      reg(inicio: '2026-07-01', quien: 'a'),
      reg(inicio: '2026-07-15', quien: 'b'),
      reg(inicio: '2026-07-16', quien: 'c'),
      reg(inicio: '2026-07-31', quien: 'd'),
    ];

    test('el 1 y el 15 caen en la PRIMERA', () {
      final r = registrosDe(datos, const Quincena(2026, 7, 1));
      expect(r.map((x) => x['usuario_id']).toSet(), {'a', 'b'});
    });

    test('el 16 y el 31 caen en la SEGUNDA', () {
      // «Del 16 al 30» perdería el día 31 siete veces al año, y con él su renglón.
      final r = registrosDe(datos, const Quincena(2026, 7, 2));
      expect(r.map((x) => x['usuario_id']).toSet(), {'c', 'd'});
    });

    test('febrero no bisiesto llega al 28', () {
      final r = registrosDe([reg(inicio: '2026-02-28')], const Quincena(2026, 2, 2));
      expect(r, hasLength(1));
    });

    test('febrero bisiesto llega al 29', () {
      final r = registrosDe([reg(inicio: '2028-02-29')], const Quincena(2028, 2, 2));
      expect(r, hasLength(1));
    });

    test('una quincena vecina no se lleva nada', () {
      expect(registrosDe(datos, const Quincena(2026, 6, 2)), isEmpty);
      expect(registrosDe(datos, const Quincena(2026, 8, 1)), isEmpty);
    });
  });

  group('una incidencia que CRUZA la quincena', () {
    // Caso real de la base: del 28 de agosto al 2 de septiembre.
    final cruzada = reg(
        inicio: '2026-08-28', fin: '2026-09-02', regreso: '2026-09-03', dias: 4);

    test('cuenta en la quincena donde EMPIEZA', () {
      expect(registrosDe([cruzada], const Quincena(2026, 8, 2)), hasLength(1));
    });

    test('y NO aparece en la quincena donde termina', () {
      // Contarla en las dos la duplicaría y el total dejaría de cuadrar con los registros.
      expect(registrosDe([cruzada], const Quincena(2026, 9, 1)), isEmpty);
    });

    test('sus días se cuentan una sola vez', () {
      expect(totalesDe(registrosDe([cruzada], const Quincena(2026, 8, 2))).dias, 4);
    });
  });

  group('el orden', () {
    test('lo último elaborado va arriba', () {
      final r = registrosDe([
        reg(inicio: '2026-08-20', elaborada: '2026-08-01T09:00:00Z', quien: 'viejo'),
        reg(inicio: '2026-08-25', elaborada: '2026-08-10T09:00:00Z', quien: 'nuevo'),
      ], const Quincena(2026, 8, 2));
      expect(r.map((x) => x['usuario_id']), ['nuevo', 'viejo']);
    });

    test('con la misma elaboración desempata la fecha de inicio', () {
      // Sin desempate, el orden puede cambiar de un repintado a otro y la tabla «baila».
      final r = registrosDe([
        reg(inicio: '2026-08-18', elaborada: '2026-08-05T09:00:00Z', quien: 'temprano'),
        reg(inicio: '2026-08-25', elaborada: '2026-08-05T09:00:00Z', quien: 'tarde'),
      ], const Quincena(2026, 8, 2));
      expect(r.map((x) => x['usuario_id']), ['tarde', 'temprano']);
    });
  });

  group('totalesDe', () {
    test('cuenta por estatus y suma los días', () {
      final t = totalesDe([
        reg(inicio: '2026-08-20', status: 'APROBADA', dias: 3, quien: 'a'),
        reg(inicio: '2026-08-21', status: 'PENDIENTE', dias: 2, quien: 'b'),
        reg(inicio: '2026-08-22', status: 'CANCELADA', dias: 9, quien: 'c'),
      ]);
      expect(t.registros, 3);
      expect(t.aprobadas, 1);
      expect(t.pendientes, 1);
      expect(t.canceladas, 1);
      expect(t.dias, 5, reason: 'los 9 de la cancelada NO entran');
      expect(t.personas, 2, reason: 'la persona de la cancelada tampoco');
    });

    test('la misma persona dos veces cuenta como UNA', () {
      final t = totalesDe([
        reg(inicio: '2026-08-20', dias: 2, quien: 'a'),
        reg(inicio: '2026-08-25', dias: 3, quien: 'a'),
      ]);
      expect(t.registros, 2);
      expect(t.personas, 1);
      expect(t.dias, 5);
    });

    test('un estatus raro cuenta como registro y sus días también', () {
      final t = totalesDe([reg(inicio: '2026-08-20', status: 'EN REVISION', dias: 2)]);
      expect(t.registros, 1);
      expect(t.aprobadas, 0);
      expect(t.dias, 2, reason: 'no está cancelada');
    });

    test('sin días no revienta', () {
      final t = totalesDe([
        {'fecha_inicio': '2026-08-20', 'status': 'APROBADA', 'usuario_id': 'a'}
      ]);
      expect(t.dias, 0);
    });

    test('conjunto vacío da ceros', () {
      final t = totalesDe([]);
      expect(t.registros, 0);
      expect(t.dias, 0);
      expect(t.personas, 0);
    });
  });

  group('fechaCorta', () {
    test('de ISO a día/mes/año', () {
      expect(fechaCorta('2026-08-31'), '31/08/2026');
      expect(fechaCorta('2026-08-31T10:00:00Z'), '31/08/2026');
    });

    test('lo que no es fecha da raya, no una celda vacía', () {
      // Una celda vacía en una tabla de fechas se confunde con un dato perdido.
      expect(fechaCorta(null), '—');
      expect(fechaCorta(''), '—');
      expect(fechaCorta('por definir'), '—');
      expect(fechaCorta('20xx-08-31'), '—');
    });
  });
}
