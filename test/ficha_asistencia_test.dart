import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sistemassi/theme/si_theme.dart';
import 'package:sistemassi/widgets/ficha_asistencia.dart';

/// La ficha salía en blanco en producción y no había forma de reproducirlo: montar el panel exige
/// sesión, permisos y tres consultas. Extraerla a un widget con datos planos permite pumpearla, y
/// cualquier excepción durante el build hace fallar esta prueba en lugar de dejar un hueco vacío.
void main() {
  setUpAll(() => initializeDateFormatting('es_MX', null));

  Map<String, dynamic> dia(
    String fecha, {
    String estado = 'CHECO',
    String? entrada = '08:05:00',
    String? salida = '18:02:00',
    bool retardo = false,
    int? minRetardo,
    bool salidaTemprano = false,
    int? minAntes,
    bool justificado = false,
    String? motivo,
    String? fotoEntrada = 'https://appchecar.com/a.jpg',
  }) =>
      {
        'fecha': fecha,
        'estado': estado,
        'esperado': true,
        'justificado': justificado,
        'justificacion_motivo': motivo,
        'justificacion_tipo': justificado ? 'INCAPACIDAD' : null,
        'hora_entrada': entrada,
        'hora_salida': salida,
        'tiene_entrada': entrada != null,
        'tiene_salida': salida != null,
        'es_retardo': retardo,
        'minutos_retardo': minRetardo,
        'salida_temprano': salidaTemprano,
        'minutos_antes': minAntes,
        'foto_entrada': fotoEntrada,
        'foto_salida': null,
      };

  Widget envolver(FichaAsistencia ficha) => MaterialApp(
        theme: SiTheme.light,
        home: Scaffold(body: Builder(builder: (_) => ficha)),
      );

  FichaAsistencia armar(List<Map<String, dynamic>> dias) => FichaAsistencia(
        nombre: 'MOISES CALDERA MEZA',
        numero: '2481',
        zona: 'Baja California',
        horario: 'Punta Pacifico L-S',
        estatus: 'puntual',
        puntualidad: 93.3,
        asistio: 14,
        esperados: 15,
        retardos: 1,
        faltas: 1,
        incompletas: 3,
        justificados: 0,
        minutosTarde: 16,
        // 4 retardos ÷ 3 = 1, más 1 falta = 2 días.
        diasDescuento: 2,
        reglaDescuento: 'Cada 3 retardos son 1 día, y cada falta sin justificar es 1 día.',
        dias: dias,
      );

  testWidgets('pinta las métricas y el calendario sin lanzar', (tester) async {
    await tester.pumpWidget(envolver(armar([
      dia('2026-07-16'),
      dia('2026-07-17', retardo: true, minRetardo: 16),
      dia('2026-07-18', salida: null),
      dia('2026-07-20', estado: 'FALTA', entrada: null, salida: null,
          fotoEntrada: null),
      dia('2026-07-21',
          justificado: true, motivo: 'Incapacidad', estado: 'JUSTIFICADO'),
      dia('2026-07-22', salidaTemprano: true, minAntes: 45, salida: '17:15:00'),
    ])));
    await tester.pumpAndSettle();

    // Cabecera y métricas.
    expect(find.text('MOISES CALDERA MEZA'), findsOneWidget);
    expect(find.text('93.3%'), findsOneWidget);
    expect(find.text('14/15'), findsOneWidget);
    // Días a descontar: sale del cálculo del panel, la ficha sólo lo pinta.
    expect(find.text('2'), findsWidgets);

    // El mes y los encabezados de la cuadrícula.
    expect(find.text('JULIO 2026'), findsOneWidget);
    expect(find.text('Dom'), findsOneWidget);
    expect(find.text('Sáb'), findsOneWidget);

    // Los días del mes: el 31 se pinta aunque no tenga datos. Se usa el 31 y no el 16 porque
    // «16» también es el valor del KPI de minutos tarde.
    expect(find.text('31'), findsOneWidget);
    expect(find.text('16'), findsWidgets);

    // Las horas, la falta y el hueco de la salida sin registrar.
    expect(find.text('08:05'), findsWidgets);
    expect(find.text('Falta'), findsOneWidget);
    expect(find.text('— sin registro'), findsWidgets);
    // El retardo muestra los minutos de más.
    expect(find.text('+16'), findsOneWidget);
    // Y la salida antes de hora también.
    expect(find.text('+45'), findsOneWidget);
  });

  testWidgets('sin días no se cae: avisa que no hay registros', (tester) async {
    await tester.pumpWidget(envolver(armar(const [])));
    await tester.pumpAndSettle();

    expect(find.text('MOISES CALDERA MEZA'), findsOneWidget);
    expect(find.text('Sin días registrados en el periodo'), findsOneWidget);
  });

  testWidgets('una fecha ilegible no tumba la ficha', (tester) async {
    // Defensa contra un dato sucio: antes `DateTime.parse` habría lanzado.
    await tester.pumpWidget(envolver(armar([
      {'fecha': 'no-es-fecha', 'estado': 'CHECO', 'esperado': true},
      dia('2026-07-16'),
    ])));
    await tester.pumpAndSettle();

    expect(find.text('JULIO 2026'), findsOneWidget);
  });

  testWidgets('en pantalla angosta cae a lista en vez de cuadricula', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(envolver(armar([
      dia('2026-07-16'),
      dia('2026-07-17', estado: 'FALTA', entrada: null, salida: null),
    ])));
    await tester.pumpAndSettle();

    // Siete columnas en 420px dejarían celdas de ~50px, donde no cabe una hora. Se espera la
    // lista: la ficha se pinta y el encabezado del mes NO aparece.
    expect(find.text('MOISES CALDERA MEZA'), findsOneWidget);
    expect(find.text('JULIO 2026'), findsNothing);
    expect(find.text('Falta'), findsOneWidget);
    expect(find.text('08:05'), findsOneWidget);
  });
}
