import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/services/checador_resumen.dart';

/// El resumen por persona de Registros: la misma cuenta que «Detalle por empleado» del Panel, sobre
/// el checador propio.
void main() {
  // Lunes a viernes, entrada 9:00 con 15 de tolerancia, salida 18:00.
  final reglas = [
    for (var d = 1; d <= 5; d++) ...[
      {'day': d, 'tol': 15, 'time': '09:00:00', 'type': 'ENTRADA'},
      {'day': d, 'tol': 0, 'time': '18:00:00', 'type': 'SALIDA'},
    ],
  ];

  // Una checada en la Ciudad de México: UTC-6, así que las 9:05 locales son las 15:05 UTC.
  Map<String, dynamic> ch(String fecha, String tipo, int h, int m) => {
        'fecha': fecha,
        'tipo': tipo,
        'registrada_en': DateTime.utc(
                int.parse(fecha.substring(0, 4)),
                int.parse(fecha.substring(5, 7)),
                int.parse(fecha.substring(8, 10)),
                h + 6,
                m)
            .toIso8601String(),
        'latitud': 19.43,
        'longitud': -99.13,
        'foto': 'u/$fecha/$tipo.jpg',
      };

  test('una semana: a tiempo, tolerancia, retardo, falta y vacaciones', () {
    final r = resumirPersona(
      profileId: 'u',
      checadas: [
        ch('2026-09-28', 'ENTRADA', 8, 50), ch('2026-09-28', 'SALIDA', 18, 5), // lunes, bien
        ch('2026-09-29', 'ENTRADA', 9, 10), ch('2026-09-29', 'SALIDA', 18, 0), // martes, tolerancia
        ch('2026-09-30', 'ENTRADA', 9, 40), // miércoles: retardo e incompleta
        // jueves 1: falta
        // viernes 2: vacaciones
      ],
      reglas: reglas,
      desde: DateTime(2026, 9, 28),
      hasta: DateTime(2026, 10, 4),
      inicio: DateTime(2026, 9, 28),
      vacaciones: [('2026-10-02', '2026-10-02')],
      ahora: DateTime(2026, 10, 5, 12),
    );
    expect(r.esperados, 5);
    expect(r.asistio, 3);
    expect(r.evaluadas, 3);
    expect(r.retardos, 1, reason: 'la tolerancia no es retardo');
    expect(r.minutosTarde, 40);
    expect(r.faltas, 1);
    expect(r.justificados, 1);
    expect(r.incompletas, 1);
    expect(r.puntualidad!.round(), 67);
    expect(r.diasDescuento(3), 1, reason: '1 retardo no llega a 3; la falta sí cuenta');
    expect(r.dias.firstWhere((d) => d['fecha'] == '2026-10-01')['estado'], 'FALTA');
    expect(r.dias.firstWhere((d) => d['fecha'] == '2026-10-02')['justificacion_tipo'], 'Vacaciones');
    expect(r.dias.firstWhere((d) => d['fecha'] == '2026-09-30')['hora_entrada'], '09:40');
  });

  test('antes de que existiera el checador no hay faltas', () {
    final r = resumirPersona(
      profileId: 'u', checadas: const [], reglas: reglas,
      desde: DateTime(2026, 9, 16), hasta: DateTime(2026, 9, 30),
      inicio: DateTime(2026, 9, 28), vacaciones: const [],
      ahora: DateTime(2026, 10, 1, 12),
    );
    expect(r.esperados, 3, reason: 'sólo 28, 29 y 30');
    expect(r.faltas, 3);
  });

  test('hoy, todavía a tiempo, no es falta', () {
    final antes = resumirPersona(
      profileId: 'u', checadas: const [], reglas: reglas,
      desde: DateTime(2026, 9, 29), hasta: DateTime(2026, 9, 29),
      inicio: DateTime(2026, 9, 28), vacaciones: const [],
      ahora: DateTime(2026, 9, 29, 9, 10),
    );
    expect((antes.esperados, antes.faltas), (0, 0));
    final despues = resumirPersona(
      profileId: 'u', checadas: const [], reglas: reglas,
      desde: DateTime(2026, 9, 29), hasta: DateTime(2026, 9, 29),
      inicio: DateTime(2026, 9, 28), vacaciones: const [],
      ahora: DateTime(2026, 9, 29, 9, 20),
    );
    expect(despues.faltas, 1);
  });

  test('hoy, con entrada y sin salida, no es incompleta todavía', () {
    final r = resumirPersona(
      profileId: 'u', checadas: [ch('2026-09-29', 'ENTRADA', 8, 55)], reglas: reglas,
      desde: DateTime(2026, 9, 29), hasta: DateTime(2026, 9, 29),
      inicio: DateTime(2026, 9, 28), vacaciones: const [],
      ahora: DateTime(2026, 9, 29, 12),
    );
    expect(r.incompletas, 0);
    expect(r.puntualidad, 100);
  });

  test('sin horario no hay días esperados, pero sí se ve lo que checó', () {
    final r = resumirPersona(
      profileId: 'u', checadas: [ch('2026-09-29', 'ENTRADA', 8, 55)], reglas: null,
      desde: DateTime(2026, 9, 28), hasta: DateTime(2026, 9, 30),
      inicio: DateTime(2026, 9, 28), vacaciones: const [],
      ahora: DateTime(2026, 10, 1),
    );
    expect(r.esperados, 0);
    expect(r.puntualidad, isNull);
    expect(r.dias.length, 1);
  });

  test('el estatus sale de los umbrales de Configuración', () {
    expect(estatusDePuntualidad(null, 70, 90), 'sin datos');
    expect(estatusDePuntualidad(69.9, 70, 90), 'critico');
    expect(estatusDePuntualidad(70, 70, 90), 'atencion');
    expect(estatusDePuntualidad(90, 70, 90), 'atencion');
    expect(estatusDePuntualidad(90.1, 70, 90), 'puntual');
  });

  test('días a descontar: el cociente es por persona y hacia abajo', () {
    final r = ResumenChecador(profileId: 'u')
      ..retardos = 5
      ..faltas = 2;
    expect(r.diasDescuento(3), 3);
    expect(r.diasDescuento(0), 7, reason: 'un umbral en cero no divide entre cero');
  });
}
