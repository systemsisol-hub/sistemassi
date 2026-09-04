/// Filtra los registros de incidencias por QUINCENA, para la tabla que sólo ven los
/// administradores.
///
/// ─── Qué es esto ───────────────────────────────────────────────────────────
///
/// Petición del usuario el 04/09/2026: una tabla con los REGISTROS —elaboración, estatus, nombre,
/// periodo, días, inicio, fin y regreso— y que los muestre por quincena. No es un resumen: es la
/// lista, filtrada.
///
/// La definición de quincena NO se escribe aquí: viene de `services/quincena.dart`, que ya la tenía
/// con sus pruebas desde el panel de Asistencia. Eso trae resuelto el borde que importa —la segunda
/// quincena llega al ÚLTIMO día del mes, sean 28, 29, 30 o 31—.
///
/// ─── La decisión que hay que decir ─────────────────────────────────────────
///
/// **Una incidencia cae en la quincena donde EMPIEZA**, aunque termine en otra. Hay casos reales:
/// una del 28 de agosto al 2 de septiembre. Se cuenta una sola vez, en la segunda de agosto, por
/// dos razones:
///
///   1. Partirla obligaría a repartir los días entre dos quincenas, y esa cuenta no está en los
///      datos —no se sabe cuántos días hábiles cayeron de cada lado—.
///   2. Contarla en las dos la duplicaría, y el total de la tabla dejaría de cuadrar con el número
///      de registros que hay.
///
/// Vive aparte porque el borde de la quincena es donde se pierde un renglón sin que nadie lo note,
/// y aquí se puede probar sin levantar la pantalla.
library;

import 'services/quincena.dart';

/// Los totales de un conjunto de registros.
class TotalesQuincena {
  final int registros;
  final int aprobadas;
  final int pendientes;
  final int canceladas;

  /// Días de las APROBADAS y PENDIENTES. Las canceladas no cuentan —es la misma regla que usa el
  /// saldo de vacaciones en la página, no una nueva—.
  final int dias;
  final int personas;

  const TotalesQuincena({
    this.registros = 0,
    this.aprobadas = 0,
    this.pendientes = 0,
    this.canceladas = 0,
    this.dias = 0,
    this.personas = 0,
  });
}

/// La fecha de inicio en `AAAA-MM-DD`, o `null`.
String? isoInicio(Map<String, dynamic> inc) {
  final v = inc['fecha_inicio'];
  if (v == null) return null;
  final t = v.toString();
  return t.length >= 10 ? t.substring(0, 10) : null;
}

/// Las quincenas que tienen al menos un registro, de la más reciente a la más antigua.
///
/// Sale de los datos y no de un rango escrito a mano: hay historia desde 2015, y un tope fijo
/// dejaría fuera el primer periodo que se pase de él sin que nadie se enterara.
List<Quincena> quincenasConDatos(List<Map<String, dynamic>> incidencias) {
  final vistas = <String, Quincena>{};
  for (final inc in incidencias) {
    final q = Quincena.deIso(isoInicio(inc));
    if (q != null) vistas[q.clave] = q;
  }
  final lista = vistas.values.toList()
    ..sort((a, b) => b.clave.compareTo(a.clave));
  return lista;
}

/// Los registros que EMPIEZAN dentro de la quincena, del más reciente al más viejo por elaboración.
///
/// Se ordena por `created_at` porque es lo primero que pide la tabla y es como se revisa: lo último
/// que entró, arriba. Con dos registros elaborados el mismo día, desempata la fecha de inicio para
/// que el orden no cambie de un repintado a otro.
List<Map<String, dynamic>> registrosDe(
  List<Map<String, dynamic>> incidencias,
  Quincena q,
) {
  final dentro = incidencias.where((inc) {
    final iso = isoInicio(inc);
    return iso != null && q.contiene(iso);
  }).toList();

  dentro.sort((a, b) {
    final ca = (a['created_at'] ?? '').toString();
    final cb = (b['created_at'] ?? '').toString();
    final porFecha = cb.compareTo(ca);
    if (porFecha != 0) return porFecha;
    return (isoInicio(b) ?? '').compareTo(isoInicio(a) ?? '');
  });
  return dentro;
}

/// Los totales de un conjunto ya filtrado.
TotalesQuincena totalesDe(List<Map<String, dynamic>> registros) {
  var aprobadas = 0, pendientes = 0, canceladas = 0, dias = 0;
  final personas = <String>{};

  for (final inc in registros) {
    final estatus = (inc['status'] ?? '').toString().toUpperCase();
    switch (estatus) {
      case 'APROBADA':
        aprobadas++;
        break;
      case 'PENDIENTE':
        pendientes++;
        break;
      case 'CANCELADA':
        canceladas++;
        break;
    }
    // Una CANCELADA no consume días ni cuenta como persona ausente: se dio de baja.
    if (estatus == 'CANCELADA') continue;
    dias += int.tryParse('${inc['dias'] ?? 0}') ?? 0;
    final quien = (inc['usuario_id'] ?? '').toString();
    if (quien.isNotEmpty) personas.add(quien);
  }

  return TotalesQuincena(
    registros: registros.length,
    aprobadas: aprobadas,
    pendientes: pendientes,
    canceladas: canceladas,
    dias: dias,
    personas: personas.length,
  );
}

/// `2026-08-31` como `31/08/2026`, que es como se lee aquí.
///
/// Devuelve una raya con lo que no sea una fecha: una celda vacía en una tabla de fechas se
/// confunde con un dato perdido, y una raya se lee como «no hay».
String fechaCorta(dynamic v) {
  if (v == null) return '—';
  final t = v.toString();
  if (t.length < 10) return '—';
  final a = t.substring(0, 4);
  final m = t.substring(5, 7);
  final d = t.substring(8, 10);
  if (int.tryParse(a) == null || int.tryParse(m) == null || int.tryParse(d) == null) {
    return '—';
  }
  return '$d/$m/$a';
}
