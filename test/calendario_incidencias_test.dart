import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/theme/si_theme.dart';
import 'package:sistemassi/widgets/calendario_incidencias.dart';

/// El calendario de la página de Incidencias pintaba UNA solicitud —la última por `created_at`— y
/// debe pintar todas. Estas pruebas cubren lo que eso destapa, midiendo contra los datos reales:
/// 1 164 incidencias de 112 personas, 32 días con más de una solicitud encimada y una persona con
/// solicitudes repartidas en 42 meses.
void main() {
  Color colorDeEstatus(String estatus) => switch (estatus) {
        'APROBADA' => Colors.green,
        'CANCELADA' => Colors.red,
        _ => Colors.orange,
      };

  Map<String, dynamic> inc(
    String inicio,
    String fin, {
    String status = 'APROBADA',
    String periodo = '2026',
    String? regreso,
    int? dias,
  }) =>
      {
        'fecha_inicio': inicio,
        'fecha_fin': fin,
        'fecha_regreso': regreso,
        'status': status,
        'periodo': periodo,
        'dias': dias,
      };

  Widget envolver(List<Map<String, dynamic>> incidencias) => MaterialApp(
        theme: SiTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              // El ancho real: la tarjeta vive en una columna de flex 1 junto a la tabla.
              width: 320,
              child: CalendarioIncidencias(
                incidencias: incidencias,
                colorDeEstatus: colorDeEstatus,
              ),
            ),
          ),
        ),
      );

  /// Cuántos días del mes visible están marcados.
  ///
  /// Se cuentan los tooltips y no los Container pintados: cada día marcado lleva el suyo con el
  /// detalle de sus solicitudes, mientras que buscar decoraciones también atrapaba la píldora del
  /// encabezado. Los dos fijos son las flechas de mes.
  int diasMarcados(WidgetTester tester) =>
      tester.widgetList<Tooltip>(find.byType(Tooltip)).length - 2;

  testWidgets('cuenta todas las solicitudes, no sólo la última', (tester) async {
    await tester.pumpWidget(envolver([
      inc('2026-01-05', '2026-01-09'),
      inc('2026-03-02', '2026-03-06'),
      inc('2026-07-20', '2026-07-24'),
    ]));
    await tester.pumpAndSettle();

    // El encabezado dice el total y en cuántos meses está repartido.
    expect(find.text('3 en 3 meses'), findsOneWidget);
    expect(find.text('Todas las solicitudes'), findsOneWidget);
  });

  testWidgets('abre en el mes más reciente con solicitudes', (tester) async {
    await tester.pumpWidget(envolver([
      inc('2026-01-05', '2026-01-09'),
      inc('2026-07-20', '2026-07-24'),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Julio 2026'), findsOneWidget);
    expect(find.text('5 días marcados'), findsOneWidget);
  });

  testWidgets('las flechas saltan al mes CON solicitudes, no al de al lado',
      (tester) async {
    // Es la diferencia entre mostrar todas y que sean inalcanzables: hay personas con solicitudes
    // en 42 meses distintos, y de mes en mes harían falta decenas de clics.
    await tester.pumpWidget(envolver([
      inc('2023-02-06', '2023-02-10'),
      inc('2026-07-20', '2026-07-24'),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Julio 2026'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    // Un salto, no 41.
    expect(find.text('Febrero 2023'), findsOneWidget);
    expect(find.text('5 días marcados'), findsOneWidget);
  });

  testWidgets('en el extremo la flecha queda apagada y no navega',
      (tester) async {
    await tester.pumpWidget(envolver([inc('2026-07-20', '2026-07-24')]));
    await tester.pumpAndSettle();

    final ayudas = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message)
        .toList();
    expect(ayudas, contains('No hay solicitudes anteriores'));
    expect(ayudas, contains('No hay solicitudes posteriores'));

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('Julio 2026'), findsOneWidget);
  });

  testWidgets('dos solicitudes en el mismo mes se pintan las dos',
      (tester) async {
    // Con la versión vieja sólo se veía una de las dos.
    await tester.pumpWidget(envolver([
      inc('2026-07-06', '2026-07-08', periodo: 'Primera'),
      inc('2026-07-20', '2026-07-24', periodo: 'Segunda'),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('8 días marcados'), findsOneWidget);
    expect(diasMarcados(tester), 8);
  });

  testWidgets('un día con dos estatus se pinta APROBADA y el tooltip guarda las dos',
      (tester) async {
    // Caso real: CAMILA RODRIGUEZ tiene una APROBADA y una CANCELADA sobre los mismos días. El día
    // sí fue de descanso, así que no puede quedar en rojo, pero la cancelada no debe desaparecer.
    await tester.pumpWidget(envolver([
      inc('2026-07-16', '2026-07-21',
          status: 'APROBADA', periodo: 'Vacaciones 2026', dias: 6),
      inc('2026-07-16', '2026-07-21',
          status: 'CANCELADA', periodo: 'Vacaciones 2026', dias: 6),
    ]));
    await tester.pumpAndSettle();

    // Un solo bloque de 6 días, no doce.
    expect(find.text('6 días marcados'), findsOneWidget);

    final tooltips = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message ?? '')
        .where((m) => m.contains('Vacaciones'))
        .toList();
    expect(tooltips, isNotEmpty);
    // Las dos solicitudes en el mismo tooltip.
    expect(tooltips.first, contains('APROBADA'));
    expect(tooltips.first, contains('CANCELADA'));

    // La leyenda anuncia los colores que de verdad están pintados. Como la aprobada le gana TODOS
    // sus días a la cancelada, ningún día quedó en rojo: ofrecer 'Cancelada' en la leyenda sería
    // prometer un color que no aparece en la cuadrícula. La cancelada sigue viva en el tooltip.
    expect(find.text('Aprobada'), findsOneWidget);
    expect(find.text('Cancelada'), findsNothing);
    // Y los seis días son uno solo pintado seis veces, no dos rangos superpuestos.
    expect(diasMarcados(tester), 6);
  });

  testWidgets('una fila con fin anterior al inicio se pinta igual',
      (tester) async {
    // Existe una en la base. Antes el rango salía vacío y la solicitud era invisible.
    await tester.pumpWidget(envolver([
      inc('2026-07-20', '2026-07-15', periodo: 'Dato sucio'),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Julio 2026'), findsOneWidget);
    expect(find.text('1 día marcado'), findsOneWidget);
  });

  testWidgets('el regreso se marca aunque caiga en otro mes', (tester) async {
    await tester.pumpWidget(envolver([
      inc('2026-07-28', '2026-07-31', regreso: '2026-08-01'),
    ]));
    await tester.pumpAndSettle();

    // Abre en agosto: es el mes más reciente con algo marcado, y ese algo es el regreso.
    expect(find.text('Agosto 2026'), findsOneWidget);
    expect(find.text('Regreso'), findsOneWidget);
  });

  testWidgets('el regreso no se pinta del color de una aprobada', (tester) async {
    // El regreso salía en verde igual que APROBADA, así que se leía como un día más de vacaciones.
    await tester.pumpWidget(envolver([
      inc('2026-07-28', '2026-07-31', regreso: '2026-08-01'),
    ]));
    await tester.pumpAndSettle();

    // El 1 de agosto: único día del mes visible, y el único '1' suelto de la cuadrícula.
    final circulo = tester
        .widgetList<Container>(find.ancestor(
            of: find.text('1'), matching: find.byType(Container)))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.shape == BoxShape.circle && d.color != null);

    final color = circulo.color!;
    expect(color, isNot(colorDeEstatus('APROBADA')));
    // Y se lee como azul: el canal azul domina sobre los otros dos.
    expect(color.b, greaterThan(color.g),
        reason: 'el día de regreso debe ser azul, no verde');
    expect(color.b, greaterThan(color.r));
  });

  testWidgets('sin fechas utilizables no pinta tarjeta a medias',
      (tester) async {
    await tester.pumpWidget(envolver([
      {'fecha_inicio': null, 'status': 'APROBADA', 'periodo': 'x'},
      {'fecha_inicio': 'no-es-fecha', 'status': 'APROBADA', 'periodo': 'y'},
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsNothing);
  });

  testWidgets('doce meses de solicitudes son todos alcanzables', (tester) async {
    // Recorre el año entero de ida y vuelta: si la navegación se atorara en algún mes, aquí falla.
    await tester.pumpWidget(envolver([
      for (var m = 1; m <= 12; m++)
        inc('2026-${m.toString().padLeft(2, '0')}-10',
            '2026-${m.toString().padLeft(2, '0')}-12'),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('12 en 12 meses'), findsOneWidget);
    expect(find.text('Diciembre 2026'), findsOneWidget);

    for (var i = 0; i < 11; i++) {
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
    }
    expect(find.text('Enero 2026'), findsOneWidget);
    expect(find.text('3 días marcados'), findsOneWidget);
  });
}
