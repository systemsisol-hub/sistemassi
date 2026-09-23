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

import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

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

// ─── Imágenes del editor ──────────────────────────────────────────────────────

/// Ancho máximo de una imagen en el correo.
///
/// Es el ancho habitual de un correo. Importa por dos razones: el peso —la imagen viaja DENTRO de
/// cada mensaje, y una foto de celular de 4 MB a 74 personas es un comunicado que tarda en abrir— y
/// Outlook de escritorio, que ignora `max-width` y pinta la imagen a su tamaño real, así que una
/// foto de 4000 píxeles se sale de la pantalla. Reducida aquí, no hay nada que ignorar.
const anchoMaximoImagen = 800;

/// Las imágenes que se pueden elegir. El servidor sólo acepta lo que sale de `prepararImagen`: PNG,
/// JPEG o GIF, con un nombre de 32 hexadecimales.
const extensionesImagen = ['jpg', 'jpeg', 'png', 'gif', 'webp'];

/// La imagen lista para subir: girada, reducida y en un formato que acepta el correo. `null` si no
/// se puede leer.
///
/// * **Se gira según sus metadatos.** Las fotos de celular guardan la rotación aparte, en EXIF, y al
///   reescribir la imagen los metadatos se pierden: sin `bakeOrientation` salen de lado.
/// * **Se reduce** a `anchoMaximoImagen` si es más ancha.
/// * **Se reescribe** como JPEG, o como PNG si tiene transparencia —un logotipo sobre fondo
///   transparente saldría con fondo negro en JPEG—. WebP se convierte: muchos clientes de correo no
///   lo muestran.
/// * **El GIF se deja como está**, para no romper una animación.
({Uint8List bytes, String extension, String tipo})? prepararImagen(
  Uint8List original,
  String nombreArchivo,
) {
  final ext = nombreArchivo.split('.').last.toLowerCase();
  if (ext == 'gif') return (bytes: original, extension: 'gif', tipo: 'image/gif');

  // `decodeImage` no siempre devuelve null con un archivo que no es imagen: con algunos datos rotos
  // LANZA. La prueba lo atrapó; sin esto la pantalla enseñaba la excepción en vez de «no se pudo leer».
  final img.Image? leida;
  try {
    leida = img.decodeImage(original);
  } catch (_) {
    return null;
  }
  if (leida == null) return null;
  var imagen = img.bakeOrientation(leida);
  if (imagen.width > anchoMaximoImagen) {
    imagen = img.copyResize(imagen,
        width: anchoMaximoImagen, interpolation: img.Interpolation.average);
  }
  if (imagen.hasAlpha) {
    return (bytes: img.encodePng(imagen), extension: 'png', tipo: 'image/png');
  }
  return (bytes: img.encodeJpg(imagen, quality: 85), extension: 'jpg', tipo: 'image/jpeg');
}

final _azar = Random.secure();

/// Un nombre nuevo para una imagen: 32 hexadecimales al azar y su extensión.
///
/// Es la forma EXACTA que acepta el servidor (`esRutaImagen` en contenido.ts): la función sólo
/// descarga nombres así, y de esa manera no se le puede pedir que descargue otra cosa.
String nombreImagen(String extension) {
  final hex = List.generate(16, (_) => _azar.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  return '$hex.$extension';
}

/// Si es el nombre de una imagen subida por el editor. El mismo criterio que `esRutaImagen` del
/// servidor: la pantalla sólo pinta como imagen lo que el correo va a llevar como imagen.
bool esRutaImagen(String v) => RegExp(r'^[0-9a-f]{32}\.(png|jpg|gif)$').hasMatch(v);

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
