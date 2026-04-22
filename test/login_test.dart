import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appsi/login_page.dart';

void main() {
  testWidgets('LoginPage tiene campos de email y contraseña', (WidgetTester tester) async {
    // Renderizamos la página de login
    await tester.pumpWidget(const MaterialApp(
      home: LoginPage(),
    ));

    // Verificamos que existan los campos de texto
    expect(find.byType(TextField), findsNWidgets(2));
    
    // Verificamos que el texto 'Correo Electrónico' sea visible
    expect(find.text('Correo Electrónico'), findsOneWidget);
    
    // Verificamos que el texto 'Contraseña' sea visible
    expect(find.text('Contraseña'), findsOneWidget);

    // Verificamos que el botón de 'INICIAR SESIÓN' sea visible
    expect(find.text('INICIAR SESIÓN'), findsOneWidget);
  });

  testWidgets('LoginPage muestra mensaje de error si los campos están vacíos', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LoginPage(),
    ));

    // Tap en el botón de iniciar sesión sin llenar nada
    await tester.tap(find.text('INICIAR SESIÓN'));
    await tester.pump();

    // Verificamos que aparezca el SnackBar con el mensaje de error
    expect(find.text('Por favor llena todos los campos'), findsOneWidget);
  });
}
