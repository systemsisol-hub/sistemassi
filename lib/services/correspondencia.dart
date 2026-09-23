/// Lo que la pantalla de Correspondencia valida ANTES de mandar, para avisar pronto.
///
/// El servidor vuelve a validar y es el que manda: ver
/// `supabase/functions/correspondencia/validar.ts`. La expresión de correo es la MISMA en los dos
/// sitios, y las dos pruebas —`test/correspondencia_test.dart` y `verificar_correspondencia.mjs`—
/// usan la misma tabla de casos. Si un día se cambia una expresión y no la otra, la pantalla diría
/// «dirección válida» y el servidor la rechazaría al enviar; las tablas iguales son lo que lo delata.
library;

/// Tope de destinatarios por mensaje. El mismo que `MAX_DESTINATARIOS` en el servidor.
const maxDestinatarios = 50;
const maxAsunto = 200;
const maxCuerpo = 20000;

final _correo = RegExp(r'^[^\s@<>(),;:"\[\]\\]+@[^\s@<>(),;:"\[\]\\]+\.[A-Za-z]{2,}$');

bool esCorreo(String s) => _correo.hasMatch(s);

/// Las direcciones de un texto pegado —separadas por coma, punto y coma, espacio o salto de línea,
/// que es como llegan de otro lado—, en minúsculas y sin repetir, apartando las que no son válidas.
///
/// `yaElegidos` son las que ya están en el mensaje, para no volver a añadirlas.
({List<String> validos, List<String> rechazados}) separarCorreos(
  String texto, {
  Iterable<String> yaElegidos = const [],
}) {
  final validos = <String>[];
  final rechazados = <String>[];
  final ya = yaElegidos.map((e) => e.toLowerCase()).toSet();

  for (final trozo in texto.split(RegExp(r'[\s,;]+'))) {
    final d = trozo.trim().toLowerCase();
    if (d.isEmpty) continue;
    if (!esCorreo(d)) {
      if (!rechazados.contains(d)) rechazados.add(d);
    } else if (!ya.contains(d) && !validos.contains(d)) {
      validos.add(d);
    }
  }
  return (validos: validos, rechazados: rechazados);
}

/// El correo con el que se le escribe a un colaborador.
///
/// El buzón de trabajo si lo tiene, y si no el correo de su cuenta: el MISMO criterio que el
/// Directorio (`directorio_page.dart`) y que la función al poner el `Reply-To`.
String? correoDe(Map<String, dynamic> perfil) {
  for (final campo in ['mail_user', 'email']) {
    final v = (perfil[campo] ?? '').toString().trim();
    if (v.isNotEmpty && esCorreo(v.toLowerCase())) return v.toLowerCase();
  }
  return null;
}

/// Qué falta para poder mandar, o `null` si nada. Es sólo para avisar pronto: el servidor decide.
String? queFalta({
  required String asunto,
  required String cuerpo,
  required int destinatarios,
}) {
  if (destinatarios == 0) return 'Agrega al menos un destinatario.';
  if (destinatarios > maxDestinatarios) {
    return 'Son $destinatarios destinatarios y el máximo por mensaje es $maxDestinatarios.';
  }
  final a = asunto.trim();
  if (a.isEmpty) return 'Falta el asunto.';
  if (a.length > maxAsunto) return 'El asunto pasa de $maxAsunto caracteres.';
  if (cuerpo.trim().isEmpty) return 'Falta el mensaje.';
  if (cuerpo.trim().length > maxCuerpo) return 'El mensaje pasa de $maxCuerpo caracteres.';
  return null;
}
