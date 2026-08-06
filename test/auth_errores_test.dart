import 'package:flutter_test/flutter_test.dart';
import 'package:gotrue/gotrue.dart';
import 'package:sistemassi/auth_errores.dart';

/// Los mensajes de error de las pantallas de contraseña son texto que ve el usuario, y GoTrue los
/// entrega siempre en inglés. Esta prueba fija los casos reales que llegan a esas pantallas.
///
/// Detecta palabras delatoras en inglés en lugar de comparar el mensaje completo: así sigue
/// pasando si se reescribe la redacción en español, pero falla si un caso se queda sin traducir.
final _ingles = RegExp(
  r'\b(password|should|characters|please|different|from|invalid|security|purposes|the)\b',
  caseSensitive: false,
);

void esperarEspanol(String msg) {
  expect(msg, isNotEmpty);
  expect(_ingles.hasMatch(msg), isFalse,
      reason: 'quedó texto en inglés sin traducir: "$msg"');
}

void main() {
  group('mensajeDeAuth traduce los errores de contraseña', () {
    test('contraseña nueva igual a la actual', () {
      final msg = mensajeDeAuth(AuthApiException(
          'New password should be different from the old password.',
          statusCode: '422',
          code: 'same_password'));
      esperarEspanol(msg);
      expect(msg, contains('distinta'));
    });

    test('demasiado corta: toma el número del servidor, no una constante nuestra', () {
      final msg = mensajeDeAuth(AuthWeakPasswordException(
          message: 'Password should be at least 8 characters.',
          statusCode: '422',
          reasons: const ['length']));
      esperarEspanol(msg);
      expect(msg, contains('8'));
    });

    test('sin variedad de caracteres', () {
      final msg = mensajeDeAuth(AuthWeakPasswordException(
          message: 'Password should contain at least one character of each.',
          statusCode: '422',
          reasons: const ['characters']));
      esperarEspanol(msg);
      expect(msg, contains('mayúsculas'));
    });

    test('corta y sin variedad: une los dos motivos', () {
      final msg = mensajeDeAuth(AuthWeakPasswordException(
          message: 'Password should be at least 10 characters.',
          statusCode: '422',
          reasons: const ['length', 'characters']));
      esperarEspanol(msg);
      expect(msg, contains('10'));
      expect(msg, contains(' y '));
    });

    test('contraseña filtrada', () {
      final msg = mensajeDeAuth(AuthWeakPasswordException(
          message: 'Password is known to be weak and easy to guess.',
          statusCode: '422',
          reasons: const ['pwned']));
      esperarEspanol(msg);
      expect(msg, contains('filtraciones'));
    });

    test('enlace de recuperación ya usado o caducado', () {
      final msg = mensajeDeAuth(AuthSessionMissingException());
      esperarEspanol(msg);
      expect(msg, contains('enlace'));
    });
  });

  group('mensajeDeAuth traduce el resto de las pantallas de acceso', () {
    test('credenciales incorrectas', () {
      esperarEspanol(mensajeDeAuth(AuthApiException('Invalid login credentials',
          statusCode: '400', code: 'invalid_credentials')));
    });

    test('límite de envío de correos', () {
      esperarEspanol(mensajeDeAuth(AuthApiException(
          'For security purposes, you can only request this after 51 seconds.',
          statusCode: '429',
          code: 'over_email_send_rate_limit')));
    });

    test('sin conexión', () {
      esperarEspanol(mensajeDeAuth(AuthRetryableFetchException()));
    });
  });

  group('respaldo cuando el error llega sin código', () {
    test('longitud mínima deducida del texto', () {
      final msg = mensajeDeAuth(
          AuthApiException('Password should be at least 6 characters.', statusCode: '422'));
      esperarEspanol(msg);
      expect(msg, contains('6'));
    });

    test('espera por seguridad, con los segundos del servidor', () {
      final msg = mensajeDeAuth(AuthApiException(
          'For security purposes, you can only request this after 9 seconds.',
          statusCode: '429'));
      esperarEspanol(msg);
      expect(msg, contains('9'));
    });
  });

  group('nunca se filtra texto en inglés a la pantalla', () {
    test('código desconocido cae a un mensaje genérico en español', () {
      esperarEspanol(mensajeDeAuth(AuthApiException('Something totally new happened',
          statusCode: '500', code: 'esto_no_existe')));
    });

    test('un error que no es de autenticación también', () {
      esperarEspanol(mensajeDeAuth(StateError('unexpected internal failure')));
    });
  });
}
