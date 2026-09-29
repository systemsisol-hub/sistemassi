import 'checador.dart';

/// El resumen por persona del Checador propio, para la tabla de Registros.
///
/// Pedido del 29/09/2026: que la tabla de Registros sea como «Detalle por empleado» del Panel
/// —puntualidad, retardos, faltas, justificados, días a descontar y estatus— sin la columna de Zona,
/// y con los umbrales de la pestaña Configuración (`checador_umbrales`).
///
/// Es la misma cuenta que el Panel hace con appchecar, pero sobre `checadas`:
///
/// * Un día ESPERADO es uno en que el horario de la persona tiene entrada.
/// * RETARDO: entrada después de la tolerancia (el rojo del semáforo). La tolerancia no es retardo.
/// * FALTA: día esperado sin entrada y sin vacaciones aprobadas.
/// * JUSTIFICADO: día esperado sin entrada, pero cubierto por unas VACACIONES APROBADAS. Las
///   justificaciones de appchecar no se usan: vienen con su reporte, y el checador es independiente.
/// * INCOMPLETA: día pasado con entrada y sin fin de jornada.
/// * Días a descontar: retardos ÷ `retardos_por_descuento` (hacia abajo, por persona) + faltas.
///
/// Dos cosas que NO cuentan, a propósito:
///
/// * Los días anteriores a la primera checada del sistema. El checador empezó el 28/09/2026; sin
///   esto, la quincena del 16 al 30 de septiembre le pondría a todos diez faltas de días en que el
///   checador ni existía.
/// * Hoy, mientras la persona todavía está a tiempo: sin entrada antes de que acabe su tolerancia no
///   es falta todavía.

class ResumenChecador {
  ResumenChecador({required this.profileId});

  final String profileId;

  int esperados = 0;
  int asistio = 0;
  int evaluadas = 0;
  int retardos = 0;
  int faltas = 0;
  int justificados = 0;
  int incompletas = 0;
  int minutosTarde = 0;

  /// Los días del periodo con el formato que pinta la ficha (`FichaAsistencia`). Las fotos van como
  /// RUTA del bucket; la pantalla las firma antes de abrir la ficha.
  final List<Map<String, dynamic>> dias = [];

  double? get puntualidad => evaluadas == 0 ? null : (evaluadas - retardos) / evaluadas * 100;

  int diasDescuento(int retardosPorDescuento) =>
      retardos ~/ (retardosPorDescuento < 1 ? 1 : retardosPorDescuento) + faltas;
}

/// 'critico' | 'atencion' | 'puntual' | 'sin datos', con los cortes de Configuración.
String estatusDePuntualidad(double? pct, double criticoMax, double atencionMax) {
  if (pct == null) return 'sin datos';
  if (pct < criticoMax) return 'critico';
  if (pct <= atencionMax) return 'atencion';
  return 'puntual';
}

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Una solicitud de vacaciones de Incidencias: del día ISO al día ISO, y su estatus.
typedef SolicitudVacaciones = (String desde, String hasta, String estatus);

/// Resume a una persona en el periodo [desde]–[hasta], ambos incluidos.
///
/// [checadas] son las suyas, de cualquier fecha. [vacaciones] son sus solicitudes de Incidencias:
/// sólo las APROBADAS justifican un día sin entrada, pero todas se marcan en el calendario de la
/// ficha —las pendientes, como «por aprobar»—. Pedido del 29/09/2026. [inicio] es el primer día del
/// checador; [ahora], el reloj con que se decide si hoy ya cuenta.
ResumenChecador resumirPersona({
  required String profileId,
  required List<Map<String, dynamic>> checadas,
  required List<dynamic>? reglas,
  required DateTime desde,
  required DateTime hasta,
  required DateTime inicio,
  required List<SolicitudVacaciones> vacaciones,
  required DateTime ahora,
}) {
  final r = ResumenChecador(profileId: profileId);
  final porDia = <String, Map<String, Map<String, dynamic>>>{};
  for (final ch in checadas) {
    porDia.putIfAbsent(ch['fecha'].toString(), () => {})[ch['tipo'].toString()] = ch;
  }

  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  var d = DateTime(desde.year, desde.month, desde.day);
  final inicioDia = DateTime(inicio.year, inicio.month, inicio.day);
  if (d.isBefore(inicioDia)) d = inicioDia;
  var fin = DateTime(hasta.year, hasta.month, hasta.day);
  if (fin.isAfter(hoy)) fin = hoy;

  /// El estatus de las vacaciones que cubren [iso], o null. Si se enciman, manda la aprobada.
  String? vacacionesEn(String iso) {
    String? hallado;
    for (final v in vacaciones) {
      if (v.$1.compareTo(iso) <= 0 && iso.compareTo(v.$2) <= 0) {
        if (v.$3 == 'APROBADA') return 'APROBADA';
        hallado ??= v.$3;
      }
    }
    return hallado;
  }

  bool deVacaciones(String iso) => vacacionesEn(iso) == 'APROBADA';

  for (; !d.isAfter(fin); d = DateTime(d.year, d.month, d.day + 1)) {
    final iso = _iso(d);
    final reglasDia = reglasDelDia(reglas, d);
    final esperado = reglasDia.entrada != null;
    final del = porDia[iso] ?? const {};
    final entrada = del['ENTRADA'];
    final salida = del['SALIDA'];
    final esHoy = d.isAtSameMomentAs(hoy);

    // Hoy sin entrada y todavía a tiempo: ni falta ni nada, aún no se sabe.
    if (esHoy && entrada == null && esperado) {
      final m = ahora.hour * 60 + ahora.minute;
      if (m <= reglasDia.entrada!.minutos + reglasDia.entrada!.tolerancia) continue;
    }
    if (!esperado && del.isEmpty) continue;

    DateTime? local(Map<String, dynamic>? ch) {
      if (ch == null) return null;
      final t = DateTime.tryParse(ch['registrada_en']?.toString() ?? '');
      return t == null ? null : horaLocalDeChecada(t, ch['latitud'] as num?, ch['longitud'] as num?);
    }

    final hEntrada = local(entrada);
    final hSalida = local(salida);
    var esRetardo = false;
    var minutosRetardo = 0;
    var salidaTemprano = false;
    var minutosAntes = 0;

    if (hEntrada != null && reglasDia.entrada != null) {
      final m = hEntrada.hour * 60 + hEntrada.minute;
      if (semaforoEntrada(m, reglasDia.entrada!) == Semaforo.rojo) {
        esRetardo = true;
        minutosRetardo = m - reglasDia.entrada!.minutos;
      }
    }
    if (hSalida != null && reglasDia.salida != null) {
      final m = hSalida.hour * 60 + hSalida.minute;
      if (semaforoSalida(m, reglasDia.salida!) == Semaforo.rojo) {
        salidaTemprano = true;
        minutosAntes = reglasDia.salida!.minutos - m;
      }
    }

    final justificado = esperado && entrada == null && deVacaciones(iso);
    final falta = esperado && entrada == null && !justificado;

    if (esperado) {
      r.esperados++;
      if (entrada != null) {
        r.asistio++;
        r.evaluadas++;
        if (esRetardo) {
          r.retardos++;
          r.minutosTarde += minutosRetardo;
        }
        if (salida == null && !esHoy) r.incompletas++;
      } else if (justificado) {
        r.justificados++;
      } else {
        r.faltas++;
      }
    }

    r.dias.add({
      'fecha': iso,
      'estado': falta ? 'FALTA' : (justificado ? 'JUSTIFICADO' : 'ASISTENCIA'),
      'esperado': esperado,
      'tiene_entrada': entrada != null,
      'tiene_salida': salida != null,
      'hora_entrada': hEntrada == null ? null : _hhmm(hEntrada),
      'hora_salida': hSalida == null ? null : _hhmm(hSalida),
      'es_retardo': esRetardo,
      'minutos_retardo': minutosRetardo,
      'salida_temprano': salidaTemprano,
      'minutos_antes': minutosAntes,
      'justificado': justificado,
      'justificacion_tipo': justificado ? 'Vacaciones' : null,
      'foto_entrada': entrada?['foto'],
      'foto_salida': salida?['foto'],
      'vacaciones': vacacionesEn(iso),
    });
  }

  // Los días de vacaciones que no quedaron arriba —fines de semana, días que todavía no llegan, o
  // hoy mientras sigue a tiempo— también van al calendario: la ficha tiene que mostrar las
  // vacaciones completas, no sólo los días en que había que checar. No cuentan en nada.
  final yaEsta = {for (final x in r.dias) x['fecha'] as String};
  final inicioPeriodo = DateTime(desde.year, desde.month, desde.day);
  final finPeriodo = DateTime(hasta.year, hasta.month, hasta.day);
  for (var v = inicioPeriodo; !v.isAfter(finPeriodo); v = DateTime(v.year, v.month, v.day + 1)) {
    final iso = _iso(v);
    final estatus = vacacionesEn(iso);
    if (estatus == null || yaEsta.contains(iso)) continue;
    r.dias.add({
      'fecha': iso,
      'estado': 'VACACIONES',
      'esperado': reglasDelDia(reglas, v).entrada != null,
      'tiene_entrada': false,
      'tiene_salida': false,
      'vacaciones': estatus,
    });
  }
  r.dias.sort((a, b) => (a['fecha'] as String).compareTo(b['fecha'] as String));
  return r;
}
