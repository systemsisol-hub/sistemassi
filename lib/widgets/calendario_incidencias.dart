import 'package:flutter/material.dart';

import '../theme/si_theme.dart';

/// Calendario con TODAS las solicitudes de una persona, no sólo la última.
///
/// Vive en su propio archivo y recibe filas planas de `incidencias` —sin Supabase de por medio—
/// para poder probarse: la página que lo contenía pasa de las 2 000 líneas y exige sesión y rol.
///
/// ─── Lo que los datos reales obligan a resolver ──────────────────────────────
///
/// Medido sobre las 1 164 incidencias de 112 personas:
///
/// * **32 días tienen más de una solicitud** —hasta 6 encimadas, en 11 personas— y 21 de esos
///   traslapes mezclan estatus distintos, típicamente una APROBADA junto a una CANCELADA. Un día
///   sólo puede pintarse de un color, así que hay una precedencia explícita ([_rango]) y el resto
///   se revela en el tooltip del día. Nada queda escondido.
/// * **Una persona llega a tener solicitudes en 42 meses distintos.** Con flechas que avanzaran de
///   mes en mes, «mostrar todas» sería cierto en el código y falso en la práctica: 40 clics para
///   llegar a la primera. Las flechas saltan al mes anterior o siguiente **con solicitudes**.
/// * Hay una fila con `fecha_fin` anterior a `fecha_inicio`. El rango se corrige al vuelo en lugar
///   de dejar de pintarla, que es lo que hacía antes: un dato sucio no debe volverse invisible.
///
/// El día de regreso va en azul —`brand`— y no en verde: el verde es el color de APROBADA, y con
/// los dos iguales el regreso se leía como un día más de la solicitud.
class CalendarioIncidencias extends StatefulWidget {
  const CalendarioIncidencias({
    super.key,
    required this.incidencias,
    required this.colorDeEstatus,
  });

  /// Filas de `incidencias` de una sola persona. Se usan `fecha_inicio`, `fecha_fin`,
  /// `fecha_regreso`, `status` y `periodo`.
  final List<Map<String, dynamic>> incidencias;

  /// El mismo criterio de color que usa el resto de la página, para no tener dos verdades.
  final Color Function(String) colorDeEstatus;

  @override
  State<CalendarioIncidencias> createState() => _CalendarioIncidenciasState();
}

class _CalendarioIncidenciasState extends State<CalendarioIncidencias> {
  DateTime? _mes;

  static const _diasSemana = ['D', 'L', 'M', 'X', 'J', 'V', 'S'];
  static const _meses = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];

  /// Cuál gana cuando varias solicitudes caen el mismo día. Menor número, más prioridad.
  ///
  /// APROBADA manda: si un día tiene una aprobada y una cancelada, la persona sí faltó, y pintarlo
  /// de rojo diría lo contrario. CANCELADA queda al final porque es la única que no significa nada
  /// en el calendario: es una solicitud que no ocurrió.
  static int _rango(String estatus) => switch (estatus) {
        'APROBADA' => 0,
        'CANCELADA' => 2,
        _ => 1,
      };

  static DateTime? _fecha(dynamic valor) {
    if (valor == null) return null;
    final d = DateTime.tryParse(valor.toString());
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  static String _clave(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Un registro por día marcado, ya resuelta la precedencia.
  Map<String, _DiaMarcado> get _marcas {
    final marcas = <String, _DiaMarcado>{};

    void marcar(DateTime dia, Map<String, dynamic> inc,
        {bool inicio = false, bool fin = false, bool regreso = false}) {
      final estatus = (inc['status'] ?? 'PENDIENTE').toString();
      final clave = _clave(dia);
      final previo = marcas[clave];
      final gana = previo == null || _rango(estatus) < _rango(previo.estatus);
      marcas[clave] = _DiaMarcado(
        estatus: gana ? estatus : previo.estatus,
        enRango: (previo?.enRango ?? false) || !regreso,
        esInicio: (previo?.esInicio ?? false) || inicio,
        esFin: (previo?.esFin ?? false) || fin,
        esRegreso: (previo?.esRegreso ?? false) || regreso,
        // Se acumulan todas: el color sólo puede contar una, el tooltip cuenta el resto.
        detalle: [...?previo?.detalle, _describir(inc)].toSet().toList(),
      );
    }

    for (final inc in widget.incidencias) {
      final inicio = _fecha(inc['fecha_inicio']);
      if (inicio == null) continue;
      // Una fila con fin anterior al inicio existe en la base. Se trata como de un solo día en vez
      // de descartarla: así se ve y se puede corregir.
      var fin = _fecha(inc['fecha_fin']) ?? inicio;
      if (fin.isBefore(inicio)) fin = inicio;

      for (var d = inicio;
          !d.isAfter(fin);
          d = DateTime(d.year, d.month, d.day + 1)) {
        marcar(d, inc, inicio: d == inicio, fin: d == fin);
      }
      final regreso = _fecha(inc['fecha_regreso']);
      if (regreso != null) marcar(regreso, inc, regreso: true);
    }
    return marcas;
  }

  static String _describir(Map<String, dynamic> inc) {
    final periodo = (inc['periodo'] ?? '').toString();
    final estatus = (inc['status'] ?? 'PENDIENTE').toString();
    final dias = inc['dias'];
    return [
      if (periodo.isNotEmpty) periodo,
      estatus,
      if (dias != null) '$dias día${dias == 1 ? '' : 's'}',
    ].join(' · ');
  }

  /// Los meses que tienen algo que mostrar, ordenados.
  List<DateTime> _mesesConDatos(Map<String, _DiaMarcado> marcas) {
    final meses = <String, DateTime>{};
    for (final clave in marcas.keys) {
      final d = DateTime.parse(clave);
      meses['${d.year}-${d.month}'] = DateTime(d.year, d.month);
    }
    final lista = meses.values.toList()..sort();
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final marcas = _marcas;
    final conDatos = _mesesConDatos(marcas);
    if (conDatos.isEmpty) return const SizedBox.shrink();

    // Arranca en el mes más reciente con solicitudes: es donde el dato importa y evita abrir en un
    // mes vacío. Se resuelve aquí y no en initState porque la lista cambia al recargar o al elegir
    // otra persona.
    final mes = _mes ?? conDatos.last;
    final anterior = conDatos.where((m) => m.isBefore(mes)).lastOrNull;
    final siguiente = conDatos.where((m) => m.isAfter(mes)).firstOrNull;

    final delMes = marcas.entries
        .where((e) => e.key.startsWith(
            '${mes.year}-${mes.month.toString().padLeft(2, '0')}'))
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SiSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _encabezado(c, conDatos.length),
            const SizedBox(height: SiSpace.x3),
            _navegacion(c, mes, anterior, siguiente, delMes),
            const SizedBox(height: 4),
            Row(
              children: _diasSemana
                  .map((d) => Expanded(
                        child: Center(
                          child: Text(d,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: c.ink4)),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 2),
            _cuadricula(c, mes, marcas),
            const SizedBox(height: SiSpace.x3),
            _leyenda(c, marcas),
          ],
        ),
      ),
    );
  }

  Widget _encabezado(SiColors c, int meses) {
    final total = widget.incidencias.length;
    return Row(
      children: [
        Icon(Icons.event_available_outlined, size: 14, color: c.brand),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Todas las solicitudes',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: c.ink),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: c.brand.withValues(alpha: 0.12),
            borderRadius: SiRadius.rPill,
          ),
          child: Text('$total en $meses ${meses == 1 ? "mes" : "meses"}',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold, color: c.brand)),
        ),
      ],
    );
  }

  Widget _navegacion(SiColors c, DateTime mes, DateTime? anterior,
      DateTime? siguiente, int dias) {
    return Row(
      children: [
        _BotonMes(
          icono: Icons.chevron_left,
          // Salta al mes con solicitudes, no al mes de calendario: con 42 meses de historia,
          // avanzar de uno en uno haría inalcanzable la primera.
          ayuda: anterior == null
              ? 'No hay solicitudes anteriores'
              : 'Ir a ${_meses[anterior.month - 1]} ${anterior.year}',
          alTocar:
              anterior == null ? null : () => setState(() => _mes = anterior),
        ),
        Expanded(
          child: Column(
            children: [
              Text('${_meses[mes.month - 1]} ${mes.year}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.ink)),
              Text(
                dias == 0
                    ? 'Sin días marcados'
                    : '$dias día${dias == 1 ? '' : 's'} marcado${dias == 1 ? '' : 's'}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: c.ink4),
              ),
            ],
          ),
        ),
        _BotonMes(
          icono: Icons.chevron_right,
          ayuda: siguiente == null
              ? 'No hay solicitudes posteriores'
              : 'Ir a ${_meses[siguiente.month - 1]} ${siguiente.year}',
          alTocar:
              siguiente == null ? null : () => setState(() => _mes = siguiente),
        ),
      ],
    );
  }

  Widget _cuadricula(
      SiColors c, DateTime mes, Map<String, _DiaMarcado> marcas) {
    final diasDelMes = DateUtils.getDaysInMonth(mes.year, mes.month);
    final hueco = DateTime(mes.year, mes.month, 1).weekday % 7; // domingo = 0
    final semanas = ((hueco + diasDelMes) / 7).ceil();

    return Column(
      children: [
        for (var semana = 0; semana < semanas; semana++)
          Row(
            children: List.generate(7, (col) {
              final dia = semana * 7 + col - hueco + 1;
              if (dia < 1 || dia > diasDelMes) {
                return const Expanded(child: SizedBox(height: 32));
              }
              final fecha = DateTime(mes.year, mes.month, dia);
              return Expanded(
                child: _Celda(
                  dia: dia,
                  marca: marcas[_clave(fecha)],
                  esHoy: DateUtils.isSameDay(fecha, DateTime.now()),
                  color: (m) => widget.colorDeEstatus(m),
                  brand: c.brand,
                ),
              );
            }),
          ),
      ],
    );
  }

  Widget _leyenda(SiColors c, Map<String, _DiaMarcado> marcas) {
    // Sólo los estatus que la persona tiene: en la base hay 1 151 aprobadas y 13 canceladas, así
    // que una leyenda fija anunciaría colores que casi nadie llega a ver.
    final estatus = marcas.values.map((m) => m.estatus).toSet().toList()
      ..sort((a, b) => _rango(a).compareTo(_rango(b)));
    return Wrap(
      spacing: SiSpace.x4,
      runSpacing: 4,
      children: [
        for (final e in estatus)
          _PuntoLeyenda(
              color: widget.colorDeEstatus(e), etiqueta: _titulo(e)),
        if (marcas.values.any((m) => m.esRegreso))
          _PuntoLeyenda(color: c.brand, etiqueta: 'Regreso'),
      ],
    );
  }

  static String _titulo(String estatus) =>
      estatus.isEmpty ? estatus : estatus[0] + estatus.substring(1).toLowerCase();
}

/// Lo que se sabe de un día ya con la precedencia resuelta.
class _DiaMarcado {
  const _DiaMarcado({
    required this.estatus,
    required this.enRango,
    required this.esInicio,
    required this.esFin,
    required this.esRegreso,
    required this.detalle,
  });

  final String estatus;
  final bool enRango;
  final bool esInicio;
  final bool esFin;
  final bool esRegreso;

  /// Todas las solicitudes que caen este día, para el tooltip.
  final List<String> detalle;
}

class _Celda extends StatelessWidget {
  const _Celda({
    required this.dia,
    required this.marca,
    required this.esHoy,
    required this.color,
    required this.brand,
  });

  final int dia;
  final _DiaMarcado? marca;
  final bool esHoy;
  final Color Function(String) color;
  final Color brand;

  @override
  Widget build(BuildContext context) {
    final m = marca;
    final colorEstatus = m == null ? brand : color(m.estatus);
    final extremo = (m?.esInicio ?? false) || (m?.esFin ?? false);

    BorderRadius? radio;
    if (m != null && m.enRango) {
      if (m.esInicio && m.esFin) {
        radio = BorderRadius.circular(20);
      } else if (m.esInicio) {
        radio = const BorderRadius.horizontal(left: Radius.circular(20));
      } else if (m.esFin) {
        radio = const BorderRadius.horizontal(right: Radius.circular(20));
      } else {
        radio = BorderRadius.zero;
      }
    }

    Color? circulo;
    if (m?.esRegreso ?? false) {
      // Azul, no verde: el verde ya es el color de APROBADA, y con los dos en verde el día de
      // regreso se leía como un día más de la solicitud. Se usa `brand` en lugar de un Colors.blue
      // suelto porque es el azul de la paleta y cambia solo en tema oscuro.
      circulo = brand;
    } else if (extremo) {
      circulo = colorEstatus;
    }

    final celda = SizedBox(
      height: 32,
      child: Stack(
        children: [
          if (m != null && m.enRango)
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: colorEstatus.withValues(alpha: 0.18),
                  borderRadius: radio,
                ),
              ),
            ),
          Center(
            child: Container(
              width: 26,
              height: 26,
              decoration: circulo != null
                  ? BoxDecoration(color: circulo, shape: BoxShape.circle)
                  : esHoy
                      ? BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: brand, width: 1.5))
                      : null,
              alignment: Alignment.center,
              child: Text(
                '$dia',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      (circulo != null || esHoy) ? FontWeight.bold : FontWeight.normal,
                  color: circulo != null ? Colors.white : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // El tooltip es lo que hace visibles los días con varias solicitudes encimadas: el color sólo
    // alcanza para una.
    if (m == null || m.detalle.isEmpty) return celda;
    return Tooltip(message: m.detalle.join('\n'), child: celda);
  }
}

class _BotonMes extends StatelessWidget {
  const _BotonMes({
    required this.icono,
    required this.ayuda,
    required this.alTocar,
  });

  final IconData icono;
  final String ayuda;

  /// `null` deja el botón apagado: no hay solicitudes en esa dirección.
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Tooltip(
      message: ayuda,
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icono,
              size: 18, color: alTocar == null ? c.ink4 : c.ink3),
        ),
      ),
    );
  }
}

class _PuntoLeyenda extends StatelessWidget {
  const _PuntoLeyenda({required this.color, required this.etiqueta});

  final Color color;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(etiqueta, style: TextStyle(fontSize: 11, color: c.ink3)),
      ],
    );
  }
}
