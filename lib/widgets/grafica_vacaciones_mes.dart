import 'package:flutter/material.dart';

import '../theme/si_theme.dart';

/// En qué meses del año toma vacaciones una persona, sumando todo su historial.
///
/// Va junto al Historial de Vacaciones y responde lo único que esa tabla no puede: la tabla dice
/// cuántos días le tocan y cuántos pidió por periodo, pero no *cuándo* descansa. Y hay patrón de
/// verdad: en la empresa diciembre concentra 609 días aprobados y mayo 482, contra 162 de junio.
///
/// ─── De dónde sale cada número ───────────────────────────────────────────────
///
/// Los `dias` de cada solicitud se suman completos al mes de su `fecha_inicio`, sin repartirlos día
/// por día entre los meses que abarca. No es pereza: medido sobre las 1 151 solicitudes aprobadas,
/// `dias` no coincide ni con el tramo del calendario —791 de 1 151— ni con los días hábiles del
/// tramo —816—, y 88 declaran MÁS días de los que su rango abarca. Es un campo independiente, y es
/// el mismo que la tabla de al lado usa para calcular el saldo. Repartirlo por día daría totales que
/// no cuadran con la tabla vecina, y dos verdades distintas en la misma pantalla son peores que un
/// caso de borde documentado: sólo 103 de 1 151 solicitudes cruzan de un mes a otro.
///
/// Se cuentan sólo las APROBADAS, igual que el saldo de la tabla.
class GraficaVacacionesPorMes extends StatelessWidget {
  const GraficaVacacionesPorMes({super.key, required this.incidencias});

  /// Filas de `incidencias` de una sola persona. Se usan `fecha_inicio`, `dias` y `status`.
  final List<Map<String, dynamic>> incidencias;

  static const _meses = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  static const _mesesLargos = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  /// Días por mes, índice 0 = enero.
  List<int> get _porMes {
    final total = List.filled(12, 0);
    for (final inc in incidencias) {
      if (inc['status'] != 'APROBADA') continue;
      final fecha = DateTime.tryParse((inc['fecha_inicio'] ?? '').toString());
      if (fecha == null) continue;
      total[fecha.month - 1] += (inc['dias'] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  /// El pie de la tarjeta. Contempla el empate: si dos meses tienen el mismo máximo, los dos van
  /// resaltados en la gráfica, así que nombrar sólo uno se contradiría con lo que se ve.
  static String _piePreferido(List<int> porMes, int maximo) {
    final altos = [
      for (var m = 0; m < 12; m++)
        if (porMes[m] == maximo) _mesesLargos[m]
    ];
    if (altos.length == 1) return 'Su mes con más días: ${altos.first}';
    final ultimo = altos.removeLast();
    return 'Sus meses con más días: ${altos.join(', ')} y $ultimo';
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final theme = Theme.of(context);
    final porMes = _porMes;
    final maximo = porMes.reduce((a, b) => a > b ? a : b);
    final total = porMes.fold<int>(0, (a, b) => a + b);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // El mismo encabezado que el Historial, para que se lean como dos piezas de lo mismo.
          Container(
            color: c.hover,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.bar_chart_rounded,
                    size: 18, color: theme.colorScheme.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Vacaciones por mes',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: theme.colorScheme.secondary)),
                ),
                if (total > 0)
                  Text('$total día${total == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 11, color: c.ink3)),
              ],
            ),
          ),
          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: SiSpace.x6),
              child: Text('Sin vacaciones aprobadas todavía',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: c.ink3)),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                children: [
                  for (var m = 0; m < 12; m++)
                    _Barra(
                      etiqueta: _meses[m],
                      dias: porMes[m],
                      fraccion: maximo == 0 ? 0 : porMes[m] / maximo,
                      // El mes más alto se resalta: es la lectura que la gente busca de un golpe.
                      destacado: porMes[m] == maximo,
                    ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: c.hover,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _piePreferido(porMes, maximo),
                style: TextStyle(fontSize: 11, color: c.ink2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({
    required this.etiqueta,
    required this.dias,
    required this.fraccion,
    required this.destacado,
  });

  final String etiqueta;
  final int dias;
  final double fraccion;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final vacio = dias == 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(etiqueta,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: destacado ? FontWeight.w700 : FontWeight.w400,
                    color: vacio ? c.ink4 : c.ink2)),
          ),
          Expanded(
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                color: c.line2,
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.centerLeft,
              // Un mes en cero deja ver la barra de fondo vacía, que dice «cero» mejor que un hueco.
              child: fraccion <= 0
                  ? null
                  : FractionallySizedBox(
                      widthFactor: fraccion.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: destacado
                              ? c.brand
                              : c.brand.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
            ),
          ),
          SizedBox(
            width: 26,
            child: Text('$dias',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: destacado ? FontWeight.w700 : FontWeight.w400,
                    color: vacio ? c.ink4 : c.ink,
                    fontFeatures: const [FontFeature.tabularFigures()]),),
          ),
        ],
      ),
    );
  }
}
