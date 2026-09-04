/// Resume las incidencias por QUINCENA, para la tabla que sólo ven los administradores.
///
/// ─── Por qué por quincena ──────────────────────────────────────────────────
///
/// Petición del usuario el 04/09/2026: «que empiece el 1 y cuando seleccione el siguiente periodo
/// sea del 16 en adelante». Es el periodo con el que se trabaja de verdad —la nómina va por
/// quincena—, así que un resumen mensual obliga a partirlo a mano cada vez.
///
/// La definición NO se escribe aquí: viene de `services/quincena.dart`, que ya la tenía con sus
/// pruebas y resuelve el borde que importa —la segunda quincena llega al ÚLTIMO día del mes, sean
/// 28, 29, 30 o 31—. Escribir «del 16 al 30» dejaría el día 31 fuera de toda quincena siete veces
/// al año.
///
/// ─── Por qué vive aparte ───────────────────────────────────────────────────
///
/// Es aritmética sobre registros, que es donde se esconde un desfase de un día o un día contado
/// dos veces. Aquí entra una lista de filas y sale una lista de periodos, así que se prueba sin
/// levantar la pantalla ni tocar la base.
///
/// ─── Las dos reglas que hereda ─────────────────────────────────────────────
///
/// Ninguna es nueva: las dos estaban tomadas en `incidencias_page.dart` y aquí se respetan para no
/// crear una tercera versión de la misma regla.
///
///   1. **El periodo es el de `fecha_inicio`**, no el de `created_at`. Unas vacaciones pedidas el 3
///      de noviembre para el 20 de diciembre cuentan en la SEGUNDA de diciembre: lo que le interesa
///      a quien mira esta tabla es cuándo falta la gente, no cuándo llenó el papel.
///   2. **Los días los consumen APROBADA y PENDIENTE.** Una pendiente reserva los días —decisión de
///      junio, con su comentario largo en la página— y una CANCELADA no consume nada.
library;

import 'services/quincena.dart';

/// Una quincena ya resumida.
class PeriodoResumen {
  final Quincena quincena;
  final int registros;
  final int aprobadas;
  final int pendientes;
  final int canceladas;

  /// Días de las APROBADAS y PENDIENTES. Las canceladas no cuentan.
  final int dias;

  /// Cuántas personas distintas, sin contar las canceladas.
  final int personas;

  const PeriodoResumen({
    required this.quincena,
    this.registros = 0,
    this.aprobadas = 0,
    this.pendientes = 0,
    this.canceladas = 0,
    this.dias = 0,
    this.personas = 0,
  });

  bool get vacio => registros == 0;
  String get etiqueta => quincena.etiquetaCorta;
}

/// El total de un año, sin quincena propia.
class TotalResumen {
  final int registros;
  final int aprobadas;
  final int pendientes;
  final int canceladas;
  final int dias;
  final int personas;

  const TotalResumen({
    this.registros = 0,
    this.aprobadas = 0,
    this.pendientes = 0,
    this.canceladas = 0,
    this.dias = 0,
    this.personas = 0,
  });
}

String? _isoDe(Map<String, dynamic> inc) {
  final v = inc['fecha_inicio'];
  if (v == null) return null;
  final t = v.toString();
  return t.length >= 10 ? t.substring(0, 10) : null;
}

/// Los años que tienen al menos un registro, del más reciente al más viejo.
///
/// Sale de los datos y no de un rango escrito a mano: hay historia desde 2015 y un tope fijo
/// dejaría fuera el primer año que se pase de él, sin que nadie se enterara.
List<int> aniosConDatos(List<Map<String, dynamic>> incidencias) {
  final anios = <int>{};
  for (final inc in incidencias) {
    final q = Quincena.deIso(_isoDe(inc));
    if (q != null) anios.add(q.anio);
  }
  return anios.toList()..sort((a, b) => b.compareTo(a));
}

/// Las VEINTICUATRO quincenas de un año, incluidas las que no tienen nada.
///
/// Las vacías se devuelven a propósito: una quincena sin registros es información —la segunda de
/// diciembre se llena y la primera de febrero no—, y saltársela haría que la tabla pareciera tener
/// un hueco de datos en lugar de un periodo tranquilo.
List<PeriodoResumen> resumirAnio(List<Map<String, dynamic>> incidencias, int anio) {
  // Índice 0..23: (mes - 1) * 2 + (mitad - 1).
  final registros = List<int>.filled(24, 0);
  final aprobadas = List<int>.filled(24, 0);
  final pendientes = List<int>.filled(24, 0);
  final canceladas = List<int>.filled(24, 0);
  final dias = List<int>.filled(24, 0);
  final personas = List.generate(24, (_) => <String>{});

  for (final inc in incidencias) {
    final q = Quincena.deIso(_isoDe(inc));
    if (q == null || q.anio != anio) continue;
    final i = (q.mes - 1) * 2 + (q.mitad - 1);
    final estatus = (inc['status'] ?? '').toString().toUpperCase();

    registros[i]++;
    switch (estatus) {
      case 'APROBADA':
        aprobadas[i]++;
        break;
      case 'PENDIENTE':
        pendientes[i]++;
        break;
      case 'CANCELADA':
        canceladas[i]++;
        break;
    }

    // Una CANCELADA no consume días ni cuenta como persona ausente: se dio de baja.
    if (estatus == 'CANCELADA') continue;
    dias[i] += int.tryParse('${inc['dias'] ?? 0}') ?? 0;
    final quien = (inc['usuario_id'] ?? '').toString();
    if (quien.isNotEmpty) personas[i].add(quien);
  }

  return [
    for (var mes = 1; mes <= 12; mes++)
      for (var mitad = 1; mitad <= 2; mitad++)
        () {
          final i = (mes - 1) * 2 + (mitad - 1);
          return PeriodoResumen(
            quincena: Quincena(anio, mes, mitad),
            registros: registros[i],
            aprobadas: aprobadas[i],
            pendientes: pendientes[i],
            canceladas: canceladas[i],
            dias: dias[i],
            personas: personas[i].length,
          );
        }(),
  ];
}

/// El total del año.
///
/// `personas` NO es la suma de las quincenales: quien tomó vacaciones en marzo y en julio es UNA
/// persona en el año y dos en la suma de los periodos. Se recuenta sobre el año completo, que es el
/// error clásico de esta clase de tabla.
TotalResumen totalDelAnio(List<Map<String, dynamic>> incidencias, int anio) {
  final periodos = resumirAnio(incidencias, anio);
  final delAnio = <String>{};
  for (final inc in incidencias) {
    final q = Quincena.deIso(_isoDe(inc));
    if (q == null || q.anio != anio) continue;
    if ((inc['status'] ?? '').toString().toUpperCase() == 'CANCELADA') continue;
    final quien = (inc['usuario_id'] ?? '').toString();
    if (quien.isNotEmpty) delAnio.add(quien);
  }

  var registros = 0, aprobadas = 0, pendientes = 0, canceladas = 0, dias = 0;
  for (final p in periodos) {
    registros += p.registros;
    aprobadas += p.aprobadas;
    pendientes += p.pendientes;
    canceladas += p.canceladas;
    dias += p.dias;
  }
  return TotalResumen(
    registros: registros,
    aprobadas: aprobadas,
    pendientes: pendientes,
    canceladas: canceladas,
    dias: dias,
    personas: delAnio.length,
  );
}
