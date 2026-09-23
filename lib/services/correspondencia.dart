/// Lo que la pantalla de Correspondencia calcula y valida ANTES de mandar, para avisar pronto.
///
/// El servidor vuelve a validar y es el que manda: ver
/// `supabase/functions/correspondencia/validar.ts`. La expresión de correo es la MISMA en los dos
/// sitios, y las dos pruebas —`test/correspondencia_test.dart` y `verificar_correspondencia.mjs`—
/// usan la misma tabla de casos. Si un día se cambia una expresión y no la otra, la pantalla diría
/// «dirección válida» y el servidor la rechazaría al enviar; las tablas iguales son lo que lo delata.
///
/// Lo mismo con las listas: `correosDeLista` sigue el MISMO criterio que `resolverMiembros` del
/// servidor. Aquí sólo sirve para mostrar cuántos van a recibir; quien decide es el servidor, al enviar.
library;

/// Tope de destinatarios por COMUNICADO, contando los de las listas. El mismo que
/// `MAX_DESTINATARIOS` en el servidor, que envía en tandas de 50.
const maxDestinatarios = 500;
const maxAsunto = 200;
const maxCuerpo = 20000;

/// Un compañero que se puede elegir como destinatario o como miembro de una lista.
typedef Colaborador = ({String id, String nombre, String correo});

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
/// Directorio (`directorio_page.dart`) y que la función.
String? correoDe(Map<String, dynamic> perfil) {
  for (final campo in ['mail_user', 'email']) {
    final v = (perfil[campo] ?? '').toString().trim();
    if (v.isNotEmpty && esCorreo(v.toLowerCase())) return v.toLowerCase();
  }
  return null;
}

/// El nombre completo de un perfil, o `null` si no tiene.
String? nombreDe(Map<String, dynamic> perfil) {
  final n = [perfil['nombre'], perfil['paterno'], perfil['materno']]
      .map((x) => (x ?? '').toString().trim())
      .where((x) => x.isNotEmpty)
      .join(' ');
  return n.isEmpty ? null : n;
}

/// A qué correos llega HOY una lista, y cuántos de sus miembros ya no alcanza.
///
/// Cada miembro trae `correo` (tecleado) o `profiles` (el compañero, embebido por la consulta). Un
/// compañero sólo cuenta si sigue ACTIVO y tiene un correo válido: así se guardan las listas, por
/// persona y no por correo, para que no se queden viejas. Mismo criterio que `resolverMiembros` en
/// el servidor.
({List<String> correos, int omitidos}) correosDeLista(List<Map<String, dynamic>> miembros) {
  final correos = <String>[];
  var omitidos = 0;
  for (final m in miembros) {
    final tecleado = (m['correo'] ?? '').toString().trim().toLowerCase();
    if (tecleado.isNotEmpty) {
      if (!correos.contains(tecleado)) correos.add(tecleado);
      continue;
    }
    final p = m['profiles'];
    final suyo = p is Map && p['status_sys'] == 'ACTIVO'
        ? correoDe(Map<String, dynamic>.from(p))
        : null;
    if (suyo == null) {
      omitidos++;
    } else if (!correos.contains(suyo)) {
      correos.add(suyo);
    }
  }
  return (correos: correos, omitidos: omitidos);
}

/// Qué falta para poder mandar, o `null` si nada. Es sólo para avisar pronto: el servidor decide.
String? queFalta({
  required String asunto,
  required String cuerpo,
  required int destinatarios,
}) {
  if (destinatarios == 0) return 'Agrega al menos un destinatario o una lista.';
  if (destinatarios > maxDestinatarios) {
    return 'Son $destinatarios destinatarios y el máximo por comunicado es $maxDestinatarios.';
  }
  final a = asunto.trim();
  if (a.isEmpty) return 'Falta el asunto.';
  if (a.length > maxAsunto) return 'El asunto pasa de $maxAsunto caracteres.';
  if (cuerpo.trim().isEmpty) return 'Falta el mensaje.';
  if (cuerpo.trim().length > maxCuerpo) return 'El mensaje pasa de $maxCuerpo caracteres.';
  return null;
}
