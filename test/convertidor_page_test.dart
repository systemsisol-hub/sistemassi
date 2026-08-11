import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/convertidor_page.dart';
import 'package:sistemassi/theme/si_theme.dart';

/// La página del Convertidor, montada de verdad.
///
/// Se puede pumpear porque no depende de Supabase: lo único que necesita es el selector de archivos y
/// el servicio, y ninguno se toca hasta que la persona elige algo. Vale la pena porque compilar no es
/// lo mismo que dibujar —el calendario de asistencia compilaba y salía en blanco en producción— y una
/// prueba así habría atrapado eso.
void main() {
  Widget envolver({bool oscuro = false}) => MaterialApp(
        theme: oscuro ? SiTheme.dark : SiTheme.light,
        home: const ConvertidorPage(),
      );

  testWidgets('se dibuja sin lanzar y explica de qué va', (tester) async {
    await tester.pumpWidget(envolver());
    await tester.pumpAndSettle();

    expect(find.text('Convertidor'), findsOneWidget);
    expect(find.textContaining('Un PDF a Markdown'), findsOneWidget);
    expect(find.text('Elegir archivo'), findsOneWidget);
    // El tope se anuncia antes de que alguien suba 40 MB para nada.
    expect(find.textContaining('25 MB'), findsOneWidget);
  });

  testWidgets('el aviso de privacidad está a la vista y no promete de más',
      (tester) async {
    await tester.pumpWidget(envolver());
    await tester.pumpAndSettle();

    expect(find.text('Tus documentos no se conservan'), findsOneWidget);
    expect(find.textContaining('servidor de la empresa'), findsOneWidget);
    // La parte incómoda también: medido contra la instancia, el nombre del archivo aparece en el
    // registro del servidor. Si alguien recorta el aviso, esta prueba falla.
    expect(find.textContaining('registro técnico'), findsOneWidget);
  });

  testWidgets('sin archivo no ofrece formatos ni botón de convertir',
      (tester) async {
    await tester.pumpWidget(envolver());
    await tester.pumpAndSettle();

    expect(find.text('CONVERTIR A'), findsNothing);
    expect(find.textContaining('Convertir a'), findsNothing);
  });

  testWidgets('en tema oscuro también se dibuja', (tester) async {
    await tester.pumpWidget(envolver(oscuro: true));
    await tester.pumpAndSettle();

    expect(find.text('Convertidor'), findsOneWidget);
    expect(find.text('Tus documentos no se conservan'), findsOneWidget);
  });

  testWidgets('en pantalla angosta no desborda', (tester) async {
    // Un móvil: el aviso y la tarjeta del archivo son los que más texto llevan.
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(envolver());
    await tester.pumpAndSettle();

    expect(find.text('Convertidor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
