import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduce los errores de autenticación de Supabase al español.
///
/// GoTrue responde siempre en inglés y no tiene opción de idioma, así que los mensajes llegaban
/// crudos a la pantalla: "New password should be different from the old password." Las
/// validaciones que hacemos aquí ya estaban en español, de modo que el usuario veía los dos
/// idiomas mezclados en el mismo recuadro de error.
///
/// Se traduce por `code` y no por el texto en inglés. El texto es descripción para
/// desarrolladores y cambia entre versiones de GoTrue sin aviso; el código es parte del contrato
/// público de la API. Queda un respaldo por texto para los errores que llegan sin código —
/// algunos se producen antes de recibir respuesta del servidor.
///
/// Lista de códigos: https://supabase.com/docs/guides/auth/debugging/error-codes
String mensajeDeAuth(Object error) {
  if (error is! AuthException) {
    debugPrint('auth: error no-Auth sin traducir: $error');
    return 'Ocurrió un error inesperado. Vuelve a intentarlo.';
  }

  // La contraseña débil se trata primero porque trae el motivo exacto en `reasons`, que es más
  // útil que un mensaje genérico: decir "muy débil" sin decir por qué obliga a adivinar.
  if (error is AuthWeakPasswordException) {
    return _contrasenaDebil(error);
  }

  // Sin sesión: en la pantalla de recuperación esto significa casi siempre que el enlace del
  // correo ya se usó o caducó, no que haya un problema con la contraseña escrita.
  if (error is AuthSessionMissingException) {
    return 'El enlace de recuperación ya se usó o caducó. Solicita uno nuevo desde '
        '«¿Olvidaste tu contraseña?».';
  }

  if (error is AuthRetryableFetchException) {
    return 'No se pudo conectar con el servidor. Revisa tu conexión e intenta de nuevo.';
  }

  final porCodigo = _porCodigo[error.code];
  if (porCodigo != null) return porCodigo;

  final porTexto = _porTexto(error.message);
  if (porTexto != null) return porTexto;

  // Sin traducción: se registra el original para poder agregarlo aquí, pero no se le muestra al
  // usuario un mensaje que no puede leer.
  debugPrint('auth: código sin traducir "${error.code}" — ${error.message}');
  return 'No se pudo completar la operación. Si el problema sigue, avisa a Sistemas.';
}

/// Extrae el número de caracteres que exige el servidor en lugar de repetir una constante de la
/// app: la política vive en la configuración de Supabase y puede cambiar sin tocar este código.
String _contrasenaDebil(AuthWeakPasswordException e) {
  final motivos = <String>[];

  if (e.reasons.contains('length')) {
    final n = RegExp(r'\d+').firstMatch(e.message)?.group(0);
    motivos.add(n == null ? 'ser más larga' : 'tener al menos $n caracteres');
  }
  if (e.reasons.contains('characters')) {
    motivos.add('combinar mayúsculas, minúsculas, números y símbolos');
  }
  if (e.reasons.contains('pwned')) {
    // Protección de contraseñas filtradas: la contraseña es válida en forma, pero aparece en
    // filtraciones públicas conocidas.
    return 'Esa contraseña aparece en filtraciones de datos conocidas. Elige una distinta.';
  }

  if (motivos.isEmpty) {
    return 'La contraseña es demasiado débil. Elige una más segura.';
  }
  return 'La contraseña debe ${motivos.join(' y ')}.';
}

const _porCodigo = <String, String>{
  // ── Cambio de contraseña ────────────────────────────────────────────────────
  'same_password':
      'La contraseña nueva debe ser distinta de la actual.',
  'reauthentication_needed':
      'Por seguridad, vuelve a iniciar sesión antes de cambiar tu contraseña.',
  'reauthentication_not_valid':
      'El código de verificación no es correcto. Solicita uno nuevo.',
  'session_not_found':
      'La sesión expiró. Inicia sesión de nuevo.',

  // ── Enlaces y códigos de recuperación ───────────────────────────────────────
  'otp_expired':
      'El enlace de recuperación caducó. Solicita uno nuevo.',
  'otp_disabled':
      'El acceso por enlace está desactivado. Avisa a Sistemas.',
  'bad_jwt':
      'El enlace no es válido. Solicita uno nuevo desde «¿Olvidaste tu contraseña?».',
  'invalid_jwt':
      'El enlace no es válido. Solicita uno nuevo desde «¿Olvidaste tu contraseña?».',
  'flow_state_expired':
      'El enlace caducó. Solicita uno nuevo.',
  'flow_state_not_found':
      'El enlace ya se usó o no es válido. Solicita uno nuevo.',
  'bad_code_verifier':
      'El enlace se abrió en un navegador distinto al que lo solicitó. Ábrelo en el mismo '
          'navegador o solicita uno nuevo.',

  // ── Inicio de sesión ────────────────────────────────────────────────────────
  'invalid_credentials':
      'Correo o contraseña incorrectos.',
  'email_not_confirmed':
      'Tu correo aún no está confirmado. Revisa tu bandeja de entrada.',
  'user_not_found':
      'No encontramos una cuenta con ese correo.',
  'user_banned':
      'Esta cuenta está suspendida. Avisa a Sistemas.',
  'no_authorization':
      'Necesitas iniciar sesión para continuar.',

  // ── Límites de intentos ─────────────────────────────────────────────────────
  'over_request_rate_limit':
      'Demasiados intentos seguidos. Espera unos minutos antes de volver a intentarlo.',
  'over_email_send_rate_limit':
      'Ya se enviaron varios correos. Espera unos minutos antes de solicitar otro.',
  'request_timeout':
      'El servidor tardó demasiado en responder. Vuelve a intentarlo.',

  // ── Datos inválidos ─────────────────────────────────────────────────────────
  'validation_failed':
      'Revisa los datos: algo no tiene el formato correcto.',
  'email_exists':
      'Ya existe una cuenta con ese correo.',
  'user_already_exists':
      'Ya existe una cuenta con ese correo.',
  'email_provider_disabled':
      'El acceso por correo está desactivado. Avisa a Sistemas.',
  'signup_disabled':
      'El registro de cuentas nuevas está desactivado.',
  'captcha_failed':
      'No se pudo verificar que no eres un robot. Recarga la página e intenta de nuevo.',

  // ── Fallas del servidor ─────────────────────────────────────────────────────
  'unexpected_failure':
      'El servidor tuvo un problema inesperado. Vuelve a intentarlo en un momento.',
};

/// Respaldo por texto, para los errores que llegan sin `code`. Se compara en minúsculas y por
/// fragmento porque GoTrue intercala datos variables en el mensaje.
String? _porTexto(String mensaje) {
  final m = mensaje.toLowerCase();
  if (m.contains('different from the old password')) {
    return _porCodigo['same_password'];
  }
  if (m.contains('invalid login credentials')) {
    return _porCodigo['invalid_credentials'];
  }
  if (m.contains('email not confirmed')) {
    return _porCodigo['email_not_confirmed'];
  }
  if (m.contains('auth session missing')) {
    return _porCodigo['session_not_found'];
  }
  if (m.contains('known to be weak')) {
    return 'Esa contraseña aparece en filtraciones de datos conocidas. Elige una distinta.';
  }
  if (m.contains('should be at least')) {
    final n = RegExp(r'\d+').firstMatch(mensaje)?.group(0);
    return n == null
        ? 'La contraseña es demasiado corta.'
        : 'La contraseña debe tener al menos $n caracteres.';
  }
  // "For security purposes, you can only request this after N seconds."
  if (m.contains('for security purposes')) {
    final n = RegExp(r'\d+').firstMatch(mensaje)?.group(0);
    return n == null
        ? 'Espera un momento antes de volver a intentarlo.'
        : 'Por seguridad, espera $n segundos antes de volver a intentarlo.';
  }
  if (m.contains('rate limit') || m.contains('too many requests')) {
    return _porCodigo['over_request_rate_limit'];
  }
  if (m.contains('failed host lookup') ||
      m.contains('socketexception') ||
      m.contains('clientexception')) {
    return 'No se pudo conectar con el servidor. Revisa tu conexión e intenta de nuevo.';
  }
  return null;
}
