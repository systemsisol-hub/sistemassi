import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// El checador propio del sistema: las reglas, sin pantalla, para poder probarlas.
///
/// Las mismas reglas las aplica la base —ver 20260928180000_checadas.sql—, que es la que manda.
/// Aquí están para que la pantalla sólo ofrezca lo que se puede hacer, en lugar de dejar pulsar un
/// botón y responder con un error.

/// Las cuatro checadas, en el orden del día. El valor es el que se guarda en `checadas.tipo`.
const tiposDeChecada = ['ENTRADA', 'SALIDA_COMIDA', 'REGRESO_COMIDA', 'SALIDA'];

/// Cómo se nombra cada una en pantalla.
const nombreDeChecada = {
  'ENTRADA': 'Entrada',
  'SALIDA_COMIDA': 'Salida a comer',
  'REGRESO_COMIDA': 'Regreso de comer',
  'SALIDA': 'Fin de jornada',
};

/// Lo que se puede checar ahora, dado lo que ya se checó hoy. El primero es el más probable.
///
/// * Sin entrada, sólo la entrada.
/// * Con la jornada terminada, nada.
/// * Afuera comiendo, sólo el regreso.
/// * Adentro: salir a comer —si no se ha hecho— o terminar la jornada.
List<String> checadasPosibles(Set<String> hechas) {
  if (!hechas.contains('ENTRADA')) return ['ENTRADA'];
  if (hechas.contains('SALIDA')) return const [];
  if (hechas.contains('SALIDA_COMIDA') && !hechas.contains('REGRESO_COMIDA')) {
    return ['REGRESO_COMIDA'];
  }
  return [
    if (!hechas.contains('SALIDA_COMIDA')) 'SALIDA_COMIDA',
    'SALIDA',
  ];
}

/// Ancho máximo de la foto que se guarda. Basta para reconocer a la persona y deja cada foto en
/// unas decenas de KB: son cuatro por persona por día.
const anchoFotoChecada = 800;

/// La foto lista para subir: orientada, reducida y en JPEG. Null si los bytes no son una imagen.
Uint8List? prepararFotoChecada(Uint8List original) {
  final img.Image? leida;
  try {
    leida = img.decodeImage(original);
  } catch (_) {
    return null;
  }
  if (leida == null) return null;
  var foto = img.bakeOrientation(leida);
  if (foto.width > anchoFotoChecada) {
    foto = img.copyResize(foto, width: anchoFotoChecada, interpolation: img.Interpolation.average);
  }
  return img.encodeJpg(foto, quality: 75);
}

final _azar = Random.secure();

/// Dónde se guarda la foto: en la carpeta de la persona —la política del bucket sólo le deja subir
/// ahí— y por día, con un nombre al azar para que no se pueda adivinar la de otro.
String rutaFotoChecada(String usuarioId, DateTime ahora) {
  final dia = '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-'
      '${ahora.day.toString().padLeft(2, '0')}';
  final nombre = List.generate(16, (_) => _azar.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '$usuarioId/$dia/$nombre.jpg';
}

/// El enlace al mapa de unas coordenadas. Sin llave de ningún servicio: abre Google Maps.
String enlaceAlMapa(num latitud, num longitud) =>
    'https://www.google.com/maps/search/?api=1&query=$latitud,$longitud';

/// La precisión en palabras: el GPS de un teléfono da decenas de metros; una computadora, que la
/// saca de la red, puede dar kilómetros. Quien revisa tiene que saber cuál de las dos es.
String precisionEnPalabras(num? metros) {
  if (metros == null) return 'precisión desconocida';
  if (metros < 1000) return '± ${metros.round()} m';
  return '± ${(metros / 1000).toStringAsFixed(1)} km';
}
