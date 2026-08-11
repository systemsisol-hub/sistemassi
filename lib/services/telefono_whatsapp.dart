/// Normalización de teléfonos para el puente de WhatsApp.
///
/// Vive aparte y sin dependencias para poder probarse, y porque la misma regla la aplican dos lados:
/// el panel al dar de alta un número y el webhook al recibir un mensaje. Si las dos no coincidieran,
/// alguien quedaría autorizado en la lista y sin respuesta en el teléfono.
///
/// ─── Qué obliga a los datos ──────────────────────────────────────────────────
///
/// Medido sobre los perfiles: los celulares capturados tienen entre 1 y 11 dígitos, y sólo 2 traen
/// lada de país. WhatsApp, en cambio, siempre entrega el número con país —para México `52`, y a veces
/// con el `1` histórico de móviles: `521`—. Así que hay que quitar el país al recibir y exigir 10
/// dígitos, que es la forma en la que está capturado casi todo.
class TelefonoWhatsApp {
  /// Los 10 dígitos del número, o `null` si no se puede afirmar cuál es.
  ///
  /// Acepta lo que llega de WhatsApp (`5215580180569@c.us`), lo que teclea una persona
  /// (`55 8018 0569`, `(558) 018-0569`) y lo que está en la base (`5580180569`).
  ///
  /// Devuelve `null` en lugar de adivinar cuando el resultado no tiene 10 dígitos. Un número de 8
  /// dígitos podría ser un fijo antiguo sin lada, y completarlo a ciegas apuntaría a otra persona.
  static String? normalizar(String? crudo) {
    if (crudo == null) return null;

    // Se corta en la arroba antes de limpiar: en `5215580180569@c.us` lo de después es la etiqueta
    // del servidor, y `@g.us` marca un GRUPO, que no se atiende.
    final sinSufijo = crudo.split('@').first;
    var d = sinSufijo.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return null;

    // 521XXXXXXXXXX: México con el 1 de móvil que WhatsApp sigue arrastrando.
    if (d.length == 13 && d.startsWith('521')) {
      d = d.substring(3);
    } else if (d.length == 12 && d.startsWith('52')) {
      d = d.substring(2);
    } else if (d.length == 11 && d.startsWith('1')) {
      // 1XXXXXXXXXX: el 1 suelto delante de un número de 10.
      d = d.substring(1);
    }

    return d.length == 10 ? d : null;
  }

  /// Si el identificador de chat corresponde a un grupo.
  ///
  /// Los grupos se ignoran: en un grupo no hay una sola persona detrás del mensaje, así que no se
  /// puede saber de quién serían «sus vacaciones».
  static bool esGrupo(String? chatId) =>
      (chatId ?? '').contains('@g.us') || (chatId ?? '').endsWith('-group');

  /// El `chatId` con el que se contesta, a partir de los 10 dígitos.
  ///
  /// Se manda con `52` y sin el `1`: es la forma que WhatsApp acepta hoy para México.
  static String chatIdDe(String diezDigitos) => '52$diezDigitos@c.us';

  /// Para mostrar: `55 8018 0569`.
  static String bonito(String diezDigitos) {
    if (diezDigitos.length != 10) return diezDigitos;
    return '${diezDigitos.substring(0, 2)} ${diezDigitos.substring(2, 6)} '
        '${diezDigitos.substring(6)}';
  }
}
