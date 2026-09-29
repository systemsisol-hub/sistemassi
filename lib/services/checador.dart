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

// ─── El horario y el semáforo ────────────────────────────────────────────────
//
// Pedido del 28/09/2026: contar contra el horario de cada quien y pintarlo en semáforo.
//
// * ENTRADA — verde: a su hora o antes; amarillo: dentro de la tolerancia del horario (15 min en
//   todos hoy); rojo: después, es retardo. La misma regla que ya usa el Panel.
// * FIN DE JORNADA — rojo: se fue antes de su hora; verde: a su hora o hasta
//   [minutosHolguraSalida] después; amarillo: más tarde —tiempo extra, o se le olvidó checar—.
// * La comida no tiene hora en los horarios, así que no lleva color.

enum Semaforo { verde, amarillo, rojo }

/// Hasta cuánto después de su hora de salida el fin de jornada sigue en verde.
const minutosHolguraSalida = 30;

/// Una regla del horario para un día: la hora en minutos desde medianoche y su tolerancia.
class ReglaDia {
  final int minutos;
  final int tolerancia;
  const ReglaDia(this.minutos, this.tolerancia);

  String get hora =>
      '${(minutos ~/ 60).toString().padLeft(2, '0')}:${(minutos % 60).toString().padLeft(2, '0')}';
}

int? _minutosDe(dynamic hhmmss) {
  final p = hhmmss?.toString().split(':') ?? const <String>[];
  if (p.length < 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  return (h == null || m == null) ? null : h * 60 + m;
}

/// La entrada y la salida del horario para [dia]. En `schedules.rules` el día va de 0 (domingo) a
/// 6 (sábado); en Dart `weekday` va de 1 (lunes) a 7 (domingo).
({ReglaDia? entrada, ReglaDia? salida}) reglasDelDia(List<dynamic>? reglas, DateTime dia) {
  final d = dia.weekday % 7;
  ReglaDia? entrada, salida;
  for (final r in reglas ?? const []) {
    if (r is! Map || r['day'] != d) continue;
    final m = _minutosDe(r['time']);
    if (m == null) continue;
    final regla = ReglaDia(m, (r['tol'] as num?)?.toInt() ?? 0);
    if (r['type'] == 'ENTRADA') entrada = regla;
    if (r['type'] == 'SALIDA') salida = regla;
  }
  return (entrada: entrada, salida: salida);
}

Semaforo semaforoEntrada(int minutos, ReglaDia r) {
  if (minutos <= r.minutos) return Semaforo.verde;
  if (minutos <= r.minutos + r.tolerancia) return Semaforo.amarillo;
  return Semaforo.rojo;
}

Semaforo semaforoSalida(int minutos, ReglaDia r) {
  if (minutos < r.minutos) return Semaforo.rojo;
  if (minutos <= r.minutos + minutosHolguraSalida) return Semaforo.verde;
  return Semaforo.amarillo;
}

/// La diferencia de horas con UTC donde se checó.
///
/// Quintana Roo va en UTC-5 y el centro del país en UTC-6, y México ya no cambia de horario desde
/// 2022. Se decide por las coordenadas y no por el reloj de quien MIRA: un administrador en la
/// Ciudad de México vería las checadas de Playa del Carmen una hora corridas, y el semáforo saldría
/// mal.
int desfaseHorasDe(num? latitud, num? longitud) {
  if (latitud != null && longitud != null &&
      latitud >= 17.8 && latitud <= 21.8 && longitud >= -89.5 && longitud <= -86.5) {
    return -5;
  }
  return -6;
}

/// La hora de la checada en el lugar donde se hizo, lista para mostrar y comparar con el horario.
DateTime horaLocalDeChecada(DateTime registrada, num? latitud, num? longitud) {
  final u = registrada.toUtc().add(Duration(hours: desfaseHorasDe(latitud, longitud)));
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
}

/// Cuánto se separó una checada de su hora: negativo, antes; positivo, después. Con el color del
/// semáforo. Null si esa checada no tiene hora en el horario —la comida— o no hay horario ese día.
///
/// Pedido del 29/09/2026: en lugar del punto de color, la diferencia —«checó 07:24 y su entrada
/// es a las 08:00»: 36 min antes, en verde—.
({int minutos, Semaforo color})? diferenciaContraHorario(
    String tipo, DateTime horaLocal, List<dynamic>? reglas) {
  final r = reglasDelDia(reglas, horaLocal);
  final m = horaLocal.hour * 60 + horaLocal.minute;
  if (tipo == 'ENTRADA' && r.entrada != null) {
    return (minutos: m - r.entrada!.minutos, color: semaforoEntrada(m, r.entrada!));
  }
  if (tipo == 'SALIDA' && r.salida != null) {
    return (minutos: m - r.salida!.minutos, color: semaforoSalida(m, r.salida!));
  }
  return null;
}

/// La diferencia, corta y con signo: «- 1h 32m» antes de la hora, «+ 8h 12m» después, «0m» justo a
/// la hora. Pedido del 29/09/2026: sólo el número, y el color dice si está bien o mal.
String diferenciaCorta(int minutos) {
  if (minutos == 0) return '0m';
  final signo = minutos < 0 ? '-' : '+';
  final total = minutos.abs();
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '$signo ${m}m';
  if (m == 0) return '$signo ${h}h';
  return '$signo ${h}h ${m}m';
}

String duracionEnPalabras(int minutos) {
  if (minutos < 1) return 'menos de un minuto';
  if (minutos < 60) return '$minutos min';
  final h = minutos ~/ 60;
  final m = minutos % 60;
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')} min';
}

/// El contador de la pestaña Checador: cuánto falta, cuánto se lleva, y de qué color.
({String texto, Semaforo? color}) contadorDelDia({
  required DateTime ahora,
  required ReglaDia? entrada,
  required ReglaDia? salida,
  required bool yaEntro,
  required bool yaSalio,
}) {
  final m = ahora.hour * 60 + ahora.minute;
  if (yaSalio) return (texto: 'Jornada terminada.', color: null);
  if (entrada == null) {
    return (texto: 'Hoy no tienes horario de trabajo.', color: null);
  }
  if (!yaEntro) {
    if (m < entrada.minutos) {
      return (
        texto: 'Faltan ${duracionEnPalabras(entrada.minutos - m)} para tu entrada (${entrada.hora}).',
        color: Semaforo.verde,
      );
    }
    if (m <= entrada.minutos + entrada.tolerancia) {
      return (
        texto: 'Estás en tolerancia: te quedan '
            '${duracionEnPalabras(entrada.minutos + entrada.tolerancia - m)} para no tener retardo.',
        color: Semaforo.amarillo,
      );
    }
    return (
      texto: 'Llevas ${duracionEnPalabras(m - entrada.minutos)} de retardo (entrada ${entrada.hora}).',
      color: Semaforo.rojo,
    );
  }
  if (salida == null) return (texto: 'Tu horario de hoy no tiene hora de salida.', color: null);
  if (m < salida.minutos) {
    return (
      texto: 'Faltan ${duracionEnPalabras(salida.minutos - m)} para tu salida (${salida.hora}).',
      color: Semaforo.verde,
    );
  }
  if (m <= salida.minutos + minutosHolguraSalida) {
    return (texto: 'Ya es tu hora de salida (${salida.hora}).', color: Semaforo.verde);
  }
  return (
    texto: 'Llevas ${duracionEnPalabras(m - salida.minutos)} después de tu hora de salida '
        '(${salida.hora}).',
    color: Semaforo.amarillo,
  );
}
