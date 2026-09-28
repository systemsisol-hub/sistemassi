import 'package:web/web.dart' as web;

/// Quita `?token_hash=…&type=recovery` (o `?code=…`) de la barra de direcciones sin recargar.
///
/// El enlace de recuperación sirve UNA vez. Si se queda en la barra, recargar la página lo vuelve a
/// canjear, falla, y la persona ve «el enlace ya se usó» justo después de haber cambiado su
/// contraseña con éxito.
void quitarParametrosDeLaUrl() {
  final url = web.window.location;
  web.window.history.replaceState(null, '', '${url.pathname}${url.hash}');
}
