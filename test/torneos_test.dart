import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/services/torneos.dart';

/// El orden de las tablas tiene que ser el MISMO que usa `torneo_avanzar` en la base para decidir
/// quien pasa a finales; si no, la app marcaria como clasificado a alguien que no paso.
void main() {
  FilaTabla fila(String id, {int puntos = 0, int victorias = 0, double? media, String grupo = 'A'}) =>
      FilaTabla(
        userId: id,
        tipo: 'grupo',
        grupo: grupo,
        ronda: 1,
        puntos: puntos,
        carreras: media == null ? 0 : 1,
        carrerasTotal: 4,
        victorias: victorias,
        posicionMedia: media,
      );

  group('compararFilas', () {
    test('primero los puntos', () {
      final l = [fila('a', puntos: 10), fila('b', puntos: 20)]..sort(compararFilas);
      expect(l.map((f) => f.userId), ['b', 'a']);
    });

    test('empate de puntos: gana quien tiene más victorias', () {
      final l = [fila('a', puntos: 20, victorias: 1), fila('b', puntos: 20, victorias: 2)]
        ..sort(compararFilas);
      expect(l.map((f) => f.userId), ['b', 'a']);
    });

    test('luego la mejor posición promedio, y sin carreras al final', () {
      final l = [
        fila('sin', puntos: 0),
        fila('peor', puntos: 0, media: 3.5),
        fila('mejor', puntos: 0, media: 2.0),
      ]..sort(compararFilas);
      expect(l.map((f) => f.userId), ['mejor', 'peor', 'sin']);
    });

    test('empate total: por id, para que no cambie entre recargas', () {
      final l = [fila('z', puntos: 5, media: 2), fila('m', puntos: 5, media: 2)]..sort(compararFilas);
      expect(l.map((f) => f.userId), ['m', 'z']);
    });
  });

  test('tablasDeGrupos separa por grupo, ordena e ignora finales', () {
    final filas = [
      fila('a', puntos: 3, grupo: 'B'),
      fila('b', puntos: 10, grupo: 'A'),
      fila('c', puntos: 7, grupo: 'A'),
      const FilaTabla(
          userId: 'f', tipo: 'final', grupo: '1-1', ronda: 1, puntos: 10, carreras: 1,
          carrerasTotal: 1, victorias: 1),
    ];
    final t = tablasDeGrupos(filas);
    expect(t.keys, ['A', 'B']);
    expect(t['A']!.map((f) => f.userId), ['b', 'c']);
  });

  group('nombreCarrera', () {
    Carrera carrera(String tipo, {String? grupo, int ronda = 1, int? numero}) => Carrera(
          id: 'x',
          tipo: tipo,
          grupo: grupo,
          ronda: ronda,
          numero: numero,
          estado: 'programada',
          participantes: const [],
        );

    test('grupos', () {
      expect(nombreCarrera(carrera('grupo', grupo: 'B', numero: 3)), 'Carrera 3 · Grupo B');
    });

    test('la única carrera de su ronda es la Gran Final', () {
      expect(nombreCarrera(carrera('final', grupo: '2-1', ronda: 2), carrerasEnRonda: 1), 'Gran Final');
      expect(nombreCarrera(carrera('final', grupo: '1-2', ronda: 1), carrerasEnRonda: 2),
          'Ronda 1 · Carrera 2');
    });
  });

  test('rankingGarage solo cuenta carreras libres completadas', () {
    Carrera libre(String estado, List<(String, int, int)> ps, {String tipo = 'libre'}) => Carrera(
          id: estado,
          tipo: tipo,
          ronda: 1,
          estado: estado,
          participantes: [
            for (final p in ps) Participante(userId: p.$1, posicion: p.$2, puntos: p.$3),
          ],
        );
    final r = rankingGarage([
      libre('completada', [('a', 1, 10), ('b', 2, 7)]),
      libre('completada', [('b', 1, 10), ('a', 2, 7)]),
      libre('por_confirmar', [('a', 1, 10), ('b', 2, 7)]),
      libre('completada', [('a', 1, 10)], tipo: 'grupo'),
    ]);
    expect(r.map((x) => (x.userId, x.puntos, x.carreras, x.victorias)), [
      ('a', 17, 2, 1),
      ('b', 17, 2, 1),
    ]);
  });

  group('horarioLiga', () {
    test('día, hora de Postgres y lugar', () {
      expect(horarioLiga(diaSemana: 5, hora: '14:00:00', lugar: 'Constituyentes'),
          'Viernes 14:00 · Constituyentes');
    });

    test('lo que falte no deja separadores sueltos', () {
      expect(horarioLiga(diaSemana: 1), 'Lunes');
      expect(horarioLiga(lugar: ' AG117 '), 'AG117');
      expect(horarioLiga(), '');
    });
  });

  group('Liga.inscripcionAbierta', () {
    final ahora = DateTime(2026, 10, 10, 12);
    Liga liga({String fase = 'inscripcion', DateTime? cierre}) =>
        Liga(id: 'l', nombre: 'Liga', fase: fase, inscripcionCierra: cierre);

    test('abierta antes del cierre, vencida después', () {
      expect(liga(cierre: DateTime(2026, 10, 11)).inscripcionAbierta(ahora), isTrue);
      expect(liga(cierre: DateTime(2026, 10, 9)).inscripcionAbierta(ahora), isFalse);
      expect(liga(cierre: DateTime(2026, 10, 9)).inscripcionVencida(ahora), isTrue);
    });

    test('ya sorteada no está abierta aunque la fecha no haya llegado', () {
      expect(liga(fase: 'grupos', cierre: DateTime(2026, 10, 11)).inscripcionAbierta(ahora), isFalse);
      expect(liga(fase: 'grupos', cierre: DateTime(2026, 10, 11)).inscripcionVencida(ahora), isFalse);
    });
  });
}
