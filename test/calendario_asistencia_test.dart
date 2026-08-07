import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sistemassi/theme/si_theme.dart';
import 'package:sistemassi/widgets/ficha_asistencia.dart';

/// El calendario se sacó de [FichaAsistencia] para que la vista de un usuario normal muestre lo
/// mismo que el administrador ve en la ficha de cualquiera, en lugar de la lista que tenía antes.
///
/// Estas pruebas cubren el uso incrustado, que es el nuevo: la ficha ya tiene las suyas. Importan
/// sobre todo porque el corte cuadrícula/lista pasó de medir el ancho de la PANTALLA a medir el del
/// contenedor —dentro de la página el calendario convive con la barra de navegación, y la pantalla
/// no dice cuánto espacio le queda.
void main() {
  setUpAll(() => initializeDateFormatting('es_MX', null));

  Map<String, dynamic> dia(
    String fecha, {
    String estado = 'CHECO',
    String? entrada = '08:05:00',
    String? salida = '18:02:00',
    bool justificado = false,
    String? tipo,
    String? motivo,
  }) =>
      {
        'fecha': fecha,
        'estado': estado,
        'esperado': true,
        'justificado': justificado,
        'justificacion_tipo': tipo,
        'justificacion_motivo': motivo,
        'hora_entrada': entrada,
        'hora_salida': salida,
        'tiene_entrada': entrada != null,
        'tiene_salida': salida != null,
        'es_retardo': false,
        'minutos_retardo': null,
        'salida_temprano': false,
        'minutos_antes': null,
        'foto_entrada': null,
        'foto_salida': null,
      };

  /// El ancho se fija con un SizedBox y no con la ventana: es el contenedor lo que el widget mide.
  Widget envolver(List<Map<String, dynamic>> dias, double ancho) => MaterialApp(
        theme: SiTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: ancho,
              child: CalendarioAsistencia(dias: dias),
            ),
          ),
        ),
      );

  testWidgets('en una tarjeta ancha pinta la cuadricula del mes', (tester) async {
    await tester.pumpWidget(envolver([
      dia('2026-07-16'),
      dia('2026-07-17', salida: null),
      dia('2026-07-20', estado: 'FALTA', entrada: null, salida: null),
    ], 700));
    await tester.pumpAndSettle();

    expect(find.text('JULIO 2026'), findsOneWidget);
    expect(find.text('Dom'), findsOneWidget);
    expect(find.text('Sáb'), findsOneWidget);
    // El mes completo, no sólo los días con datos.
    expect(find.text('31'), findsOneWidget);
    expect(find.text('08:05'), findsWidgets);
    expect(find.text('Falta'), findsOneWidget);
    // La salida que nadie registró no se inventa.
    expect(find.text('— sin registro'), findsWidgets);
  });

  testWidgets('por debajo del minimo cae a lista', (tester) async {
    // 400px entre siete columnas dejaría celdas de 57px, donde no cabe una hora.
    await tester.pumpWidget(envolver([
      dia('2026-07-16'),
      dia('2026-07-20', estado: 'FALTA', entrada: null, salida: null),
    ], 400));
    await tester.pumpAndSettle();

    expect(find.text('JULIO 2026'), findsNothing);
    expect(find.text('08:05'), findsOneWidget);
    expect(find.text('Falta'), findsOneWidget);
  });

  testWidgets('546px es el corte exacto entre cuadricula y lista', (tester) async {
    // El límite documentado, probado por los dos lados para que nadie lo mueva sin darse cuenta.
    for (final (ancho, esperaCuadricula) in [(545.0, false), (546.0, true)]) {
      await tester.pumpWidget(envolver([dia('2026-07-16')], ancho));
      await tester.pumpAndSettle();
      expect(find.text('JULIO 2026'),
          esperaCuadricula ? findsOneWidget : findsNothing,
          reason: 'a $ancho px se esperaba '
              '${esperaCuadricula ? "cuadrícula" : "lista"}');
    }
  });

  testWidgets('el motivo de un dia justificado va en el tooltip', (tester) async {
    // El tinte amarillo dice que está justificado; el motivo sólo se veía en la lista vieja y no
    // debía perderse al cambiarla por el calendario.
    await tester.pumpWidget(envolver([
      dia('2026-07-21',
          estado: 'JUSTIFICADO',
          justificado: true,
          tipo: 'INCAPACIDAD',
          motivo: 'Incapacidad del IMSS'),
    ], 700));
    await tester.pumpAndSettle();

    final tooltips = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message)
        .toList();
    expect(tooltips, contains('INCAPACIDAD · Incapacidad del IMSS'));
  });

  testWidgets('un dia sin justificar no lleva tooltip', (tester) async {
    await tester.pumpWidget(envolver([dia('2026-07-16')], 700));
    await tester.pumpAndSettle();

    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('sin dias avisa en lugar de dejar un hueco', (tester) async {
    await tester.pumpWidget(envolver(const [], 700));
    await tester.pumpAndSettle();

    expect(find.text('Sin días registrados en el periodo'), findsOneWidget);
    expect(find.text('JULIO 2026'), findsNothing);
  });
}
