import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/theme/si_theme.dart';
import 'package:sistemassi/widgets/grafica_vacaciones_mes.dart';

/// La gráfica que acompaña al Historial de Vacaciones: en qué meses descansa la persona.
///
/// Lo que estas pruebas fijan es sobre todo de dónde sale cada número, porque hay una decisión que
/// se puede «corregir» por error más adelante: los `dias` de una solicitud se suman completos al mes
/// de `fecha_inicio` y no se reparten entre los meses que abarca. Es deliberado — `dias` no coincide
/// ni con el tramo del calendario ni con los días hábiles, y es el campo que la tabla vecina usa
/// para el saldo, así que repartirlo daría dos totales distintos en la misma pantalla.
void main() {
  Map<String, dynamic> inc(String inicio, int dias,
          {String status = 'APROBADA'}) =>
      {'fecha_inicio': inicio, 'dias': dias, 'status': status};

  Widget envolver(List<Map<String, dynamic>> incidencias) => MaterialApp(
        theme: SiTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              // Un tercio de una pantalla de 1400px.
              width: 435,
              child: GraficaVacacionesPorMes(incidencias: incidencias),
            ),
          ),
        ),
      );

  testWidgets('suma los días por mes y nombra el mes más alto', (tester) async {
    await tester.pumpWidget(envolver([
      inc('2026-12-20', 8),
      inc('2025-12-23', 4), // otro diciembre: se acumula sobre el mismo mes
      inc('2026-05-04', 10),
      inc('2026-01-07', 3),
    ]));
    await tester.pumpAndSettle();

    // Total en el encabezado.
    expect(find.text('25 días'), findsOneWidget);
    // Diciembre acumula 8 + 4 de dos años distintos.
    expect(find.text('12'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Su mes con más días: diciembre'), findsOneWidget);
    // Los doce meses se dibujan, también los vacíos: tres con datos, nueve en cero.
    expect(find.text('Jun'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(9));
  });

  testWidgets('las canceladas no cuentan', (tester) async {
    await tester.pumpWidget(envolver([
      inc('2026-05-04', 10),
      inc('2026-06-01', 6, status: 'CANCELADA'),
      inc('2026-07-01', 5, status: 'PENDIENTE'),
    ]));
    await tester.pumpAndSettle();

    // Sólo los 10 aprobados: igual que el saldo de la tabla, que también ignora lo demás.
    expect(find.text('10 días'), findsOneWidget);
    expect(find.text('Su mes con más días: mayo'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(11));
  });

  testWidgets('una solicitud a caballo entre dos meses cuenta en el de inicio',
      (tester) async {
    // Decisión deliberada y documentada: `dias` es un campo propio —hay 88 solicitudes que declaran
    // más días de los que su rango abarca— y es el que usa la tabla de al lado. Repartirlo por día
    // daría un total distinto al de la tabla. Sólo 103 de 1 151 solicitudes cruzan de mes.
    await tester.pumpWidget(envolver([
      {
        'fecha_inicio': '2026-07-29',
        'fecha_fin': '2026-08-04',
        'dias': 7,
        'status': 'APROBADA',
      },
    ]));
    await tester.pumpAndSettle();

    expect(find.text('7 días'), findsOneWidget);
    expect(find.text('Su mes con más días: julio'), findsOneWidget);
    // Agosto queda en cero: los 7 días completos se fueron a julio.
    expect(find.text('0'), findsNWidgets(11));
  });

  testWidgets('con empate nombra los dos meses', (tester) async {
    // Si dos meses empatan, los dos salen resaltados en la gráfica: nombrar sólo uno se
    // contradiría con lo que se ve.
    await tester.pumpWidget(envolver([
      inc('2026-05-04', 6),
      inc('2026-12-20', 6),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Sus meses con más días: mayo y diciembre'), findsOneWidget);
  });

  testWidgets('sin aprobadas avisa en lugar de dibujar doce ceros',
      (tester) async {
    await tester.pumpWidget(envolver([
      inc('2026-05-04', 10, status: 'CANCELADA'),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Sin vacaciones aprobadas todavía'), findsOneWidget);
    expect(find.text('Ene'), findsNothing);
  });

  testWidgets('sin incidencias no se cae', (tester) async {
    await tester.pumpWidget(envolver(const []));
    await tester.pumpAndSettle();

    expect(find.text('Sin vacaciones aprobadas todavía'), findsOneWidget);
  });

  testWidgets('una fecha ilegible o un día nulo no tumban la gráfica',
      (tester) async {
    await tester.pumpWidget(envolver([
      {'fecha_inicio': 'no-es-fecha', 'dias': 5, 'status': 'APROBADA'},
      {'fecha_inicio': null, 'dias': 5, 'status': 'APROBADA'},
      {'fecha_inicio': '2026-05-04', 'dias': null, 'status': 'APROBADA'},
      inc('2026-10-01', 4),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('4 días'), findsOneWidget);
    expect(find.text('Su mes con más días: octubre'), findsOneWidget);
  });
}
