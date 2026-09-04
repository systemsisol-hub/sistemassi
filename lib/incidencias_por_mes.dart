/// Resume las incidencias por mes, para la tabla que sólo ven los administradores.
///
/// ─── Por qué vive aparte ───────────────────────────────────────────────────
///
/// Es aritmética sobre registros, que es donde se esconde un desfase de un mes o un día contado
/// dos veces. Aquí entra una lista de filas y sale una lista de meses, así que se puede probar sin
/// levantar la pantalla ni tocar la base.
///
/// ─── Las dos decisiones que hereda ─────────────────────────────────────────
///
/// Ninguna de las dos es nueva: las dos ya estaban tomadas en `incidencias_page.dart` y aquí se
/// respetan para no crear una tercera versión de la misma regla.
///
///   1. **El mes es el de `fecha_inicio`**, no el de `created_at`. Unas vacaciones pedidas en
///      noviembre para diciembre cuentan en DICIEMBRE: lo que le interesa a quien mira esta tabla
///      es cuándo falta la gente, no cuándo llenó el papel.
///   2. **Los días los consumen APROBADA y PENDIENTE.** Una pendiente reserva los días —decisión de
///      junio, con su comentario largo en la página—, y una CANCELADA no consume nada. Contar sólo
///      las aprobadas daría un número más bajo que el que la propia página usa para el saldo.
library;

/// Un mes ya resumido.
class MesResumen {
  final int anio;
  final int mes;
  final int registros;
  final int aprobadas;
  final int pendientes;
  final int canceladas;

  /// Días de las APROBADAS y PENDIENTES. Las canceladas no cuentan.
  final int dias;

  /// Cuántas personas distintas, sin contar las canceladas.
  final int personas;

  const MesResumen({
    required this.anio,
    required this.mes,
    this.registros = 0,
    this.aprobadas = 0,
    this.pendientes = 0,
    this.canceladas = 0,
    this.dias = 0,
    this.personas = 0,
  });

  bool get vacio => registros == 0;

  static const nombres = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  String get nombreMes => nombres[mes - 1];
}

DateTime? _inicioDe(Map<String, dynamic> inc) {
  final v = inc['fecha_inicio'];
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse(v.toString());
}

/// Los años que tienen al menos un registro, del más reciente al más viejo.
///
/// Sale de los datos y no de un rango escrito a mano: hay historia desde 2015 y ponerle un tope
/// fijo dejaría fuera el primer año que se pase de él, sin que nadie se enterara.
List<int> aniosConDatos(List<Map<String, dynamic>> incidencias) {
  final anios = <int>{};
  for (final inc in incidencias) {
    final d = _inicioDe(inc);
    if (d != null) anios.add(d.year);
  }
  final lista = anios.toList()..sort((a, b) => b.compareTo(a));
  return lista;
}

/// Los DOCE meses de un año, incluidos los que no tienen nada.
///
/// Los vacíos se devuelven a propósito: un mes sin registros es información —diciembre siempre se
/// llena y febrero no—, y saltárselo haría que la tabla pareciera tener un hueco de datos en lugar
/// de un mes tranquilo.
List<MesResumen> resumirAnio(List<Map<String, dynamic>> incidencias, int anio) {
  final registros = List<int>.filled(13, 0);
  final aprobadas = List<int>.filled(13, 0);
  final pendientes = List<int>.filled(13, 0);
  final canceladas = List<int>.filled(13, 0);
  final dias = List<int>.filled(13, 0);
  final personas = List.generate(13, (_) => <String>{});

  for (final inc in incidencias) {
    final d = _inicioDe(inc);
    if (d == null || d.year != anio) continue;
    final m = d.month;
    final estatus = (inc['status'] ?? '').toString().toUpperCase();

    registros[m]++;
    switch (estatus) {
      case 'APROBADA':
        aprobadas[m]++;
        break;
      case 'PENDIENTE':
        pendientes[m]++;
        break;
      case 'CANCELADA':
        canceladas[m]++;
        break;
    }

    // Una CANCELADA no consume días ni cuenta como persona ausente: se dio de baja.
    if (estatus == 'CANCELADA') continue;
    dias[m] += int.tryParse('${inc['dias'] ?? 0}') ?? 0;
    final quien = (inc['usuario_id'] ?? '').toString();
    if (quien.isNotEmpty) personas[m].add(quien);
  }

  return [
    for (var m = 1; m <= 12; m++)
      MesResumen(
        anio: anio,
        mes: m,
        registros: registros[m],
        aprobadas: aprobadas[m],
        pendientes: pendientes[m],
        canceladas: canceladas[m],
        dias: dias[m],
        personas: personas[m].length,
      ),
  ];
}

/// El total del año.
///
/// `personas` NO es la suma de las mensuales: quien tomó vacaciones en marzo y en julio es UNA
/// persona en el año y dos en la suma de los meses. Se recuenta sobre el año completo.
MesResumen totalDelAnio(List<Map<String, dynamic>> incidencias, int anio) {
  final meses = resumirAnio(incidencias, anio);
  final delAnio = <String>{};
  for (final inc in incidencias) {
    final d = _inicioDe(inc);
    if (d == null || d.year != anio) continue;
    if ((inc['status'] ?? '').toString().toUpperCase() == 'CANCELADA') continue;
    final quien = (inc['usuario_id'] ?? '').toString();
    if (quien.isNotEmpty) delAnio.add(quien);
  }

  var registros = 0, aprobadas = 0, pendientes = 0, canceladas = 0, dias = 0;
  for (final m in meses) {
    registros += m.registros;
    aprobadas += m.aprobadas;
    pendientes += m.pendientes;
    canceladas += m.canceladas;
    dias += m.dias;
  }
  return MesResumen(
    anio: anio,
    mes: 1,
    registros: registros,
    aprobadas: aprobadas,
    pendientes: pendientes,
    canceladas: canceladas,
    dias: dias,
    personas: delAnio.length,
  );
}
