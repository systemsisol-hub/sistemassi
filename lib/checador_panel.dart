import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme/si_theme.dart';
import 'widgets/ficha_asistencia.dart';

/// Panel de asistencia: puntualidad, faltas y detalle por persona.
///
/// ─── Quién ve qué ────────────────────────────────────────────────────────────
///
/// No hay dos consultas, una para el administrador y otra para el usuario. Las políticas RLS de
/// `checador_registros` y `checador_justificaciones` filtran por `profile_id = auth.uid()` salvo
/// para administradores, así que el mismo código produce el panel de toda la empresa o el personal
/// según quién pregunte. Filtrar en la pantalla no sería control de acceso: la API respondería
/// igual.
///
/// Lo único que cambia por rol es la forma: un administrador ve el desglose por zona, el semáforo y
/// la tabla de todos; un usuario ve sus propias cifras y el detalle de sus días.
class ChecadorPanel extends StatefulWidget {
  const ChecadorPanel({super.key});

  @override
  State<ChecadorPanel> createState() => _ChecadorPanelState();
}

class _ChecadorPanelState extends State<ChecadorPanel> {
  final _supabase = Supabase.instance.client;
  final _buscarCtrl = TextEditingController();

  bool _cargando = true;
  String? _error;
  bool _esAdmin = false;

  List<Map<String, dynamic>> _entradas = [];
  List<Map<String, dynamic>> _dias = [];
  double _criticoMax = 70;
  double _atencionMax = 90;
  int _retardosPorDescuento = 3;

  DateTime? _desde;
  DateTime? _hasta;

  String _filtroEstatus = 'todos';
  String _filtroZona = 'todas';
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid != null) {
        final perfil = await _supabase
            .from('profiles').select('role').eq('id', uid).maybeSingle();
        _esAdmin = perfil?['role'] == 'admin';
      }

      final umbrales = await _supabase
          .from('checador_umbrales')
          .select('critico_max, atencion_max, retardos_por_descuento')
          .maybeSingle();
      if (umbrales != null) {
        _criticoMax = (umbrales['critico_max'] as num).toDouble();
        _atencionMax = (umbrales['atencion_max'] as num).toDouble();
        _retardosPorDescuento =
            ((umbrales['retardos_por_descuento'] as num?)?.toInt() ?? 3)
                .clamp(1, 100);
      }

      // El rango sale de los propios datos visibles y no de checador_importaciones, que es sólo
      // para administradores: un usuario normal no puede leer esa bitácora porque lleva nombres
      // de otros colaboradores.
      final entradas = await _supabase
          .from('checador_entradas')
          .select('profile_id, nombre_reporte, numero_empleado, sucursal, departamento, '
              'horario_nombre, fecha, hora, limite, es_retardo, minutos_retardo, '
              'justificado, justificacion_tipo, justificacion_motivo, foto_url')
          .order('fecha');
      _entradas = List<Map<String, dynamic>>.from(entradas);

      final dias = await _supabase
          .from('checador_dias')
          .select('profile_id, fecha, estado, horario_ambiguo, esperado, checo, incompleta, '
              'tiene_entrada, tiene_salida, hora_entrada, hora_salida, foto_entrada, '
              'foto_salida, limite_entrada, salida_esperada, es_retardo, minutos_retardo, '
              'salida_temprano, minutos_antes, justificado, justificacion_motivo, '
              'justificacion_tipo, horario_nombre')
          .order('fecha');
      _dias = List<Map<String, dynamic>>.from(dias);

      final fechas = _entradas.map((e) => e['fecha'].toString()).toList()..sort();
      if (fechas.isNotEmpty) {
        _desde = DateTime.parse(fechas.first);
        _hasta = DateTime.parse(fechas.last);
      }

      if (mounted) setState(() => _cargando = false);
    } catch (e) {
      debugPrint('panel checador: $e');
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  // ── Agregados ──────────────────────────────────────────────────────────────

  Iterable<Map<String, dynamic>> get _evaluadas =>
      _entradas.where((e) => e['es_retardo'] != null);

  int get _retardos => _evaluadas.where((e) => e['es_retardo'] == true).length;
  int get _aTiempo => _evaluadas.where((e) => e['es_retardo'] == false).length;
  /// Sólo los días que el horario pedía. La vista también trae los que alguien trabajó fuera de
  /// su horario —un sábado en una jornada L-V—, y ésos no entran en ninguna métrica.
  Iterable<Map<String, dynamic>> get _diasEsperados =>
      _dias.where((d) => d['esperado'] == true);

  int get _faltas => _diasEsperados.where((d) => d['estado'] == 'FALTA').length;

  /// Suma de los días a descontar de cada persona. Se suman los cocientes individuales y no se
  /// divide el total de retardos: eso daría 34 donde son 25.
  int get _diasDescuento =>
      _empleados.fold<int>(0, (a, f) => a + f.diasDescuento);
  int get _justificados =>
      _diasEsperados.where((d) => d['estado'] == 'JUSTIFICADO').length;
  bool get _hayHorarioAmbiguo => _dias.any((d) => d['horario_ambiguo'] == true);

  double? get _puntualidad {
    final n = _evaluadas.length;
    return n == 0 ? null : (_aTiempo / n) * 100;
  }

  String _estatusDe(double? pct) {
    if (pct == null) return 'sin datos';
    if (pct < _criticoMax) return 'critico';
    if (pct <= _atencionMax) return 'atencion';
    return 'puntual';
  }

  List<_FilaEmpleado> get _empleados {
    final porPersona = <String, _FilaEmpleado>{};

    for (final e in _entradas) {
      final clave = (e['profile_id'] ?? e['nombre_reporte'] ?? '?').toString();
      final fila = porPersona.putIfAbsent(
        clave,
        () => _FilaEmpleado(
          id: clave,
          nombre: (e['nombre_reporte'] ?? 'Sin nombre').toString(),
          numero: (e['numero_empleado'] ?? '').toString(),
          zona: (e['sucursal'] ?? '').toString(),
          horario: (e['horario_nombre'] ?? '').toString(),
        ),
      );
      if (e['es_retardo'] != null) {
        fila.evaluadas++;
        if (e['es_retardo'] == true) {
          fila.retardos++;
          fila.minutos += (e['minutos_retardo'] as num?)?.toInt() ?? 0;
        }
      }
    }

    // Las faltas y las checadas a medias viven en la otra vista, indexada por profile_id.
    for (final d in _diasEsperados) {
      final clave = (d['profile_id'] ?? '?').toString();
      final fila = porPersona[clave];
      if (fila == null) continue;
      fila.esperados++;
      if (d['checo'] == true) fila.asistio++;
      if (d['incompleta'] == true) fila.incompletas++;
      if (d['estado'] == 'FALTA') fila.faltas++;
      if (d['estado'] == 'JUSTIFICADO') fila.justificados++;
    }

    for (final f in porPersona.values) {
      f.estatus = _estatusDe(f.puntualidad);
      f.retardosPorDescuento = _retardosPorDescuento;
    }

    final lista = porPersona.values.toList()
      // Alfabético. Antes iba por puntualidad ascendente para poner arriba a quien atender, pero
      // con 45 personas se vuelve imposible localizar a alguien concreto; para eso están el
      // buscador y los filtros de estatus.
      ..sort((a, b) =>
          a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return lista;
  }

  /// Las zonas presentes, para el desplegable.
  List<String> get _zonas {
    final z = _empleados
        .map((f) => f.zona)
        .where((x) => x.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return z;
  }

  List<_FilaEmpleado> get _empleadosFiltrados {
    final q = _busqueda.trim().toLowerCase();
    return _empleados.where((f) {
      if (_filtroZona != 'todas' && f.zona != _filtroZona) return false;
      if (_filtroEstatus != 'todos' && f.estatus != _filtroEstatus) return false;
      if (q.isEmpty) return true;
      return f.nombre.toLowerCase().contains(q) ||
          f.numero.contains(q) ||
          f.zona.toLowerCase().contains(q);
    }).toList();
  }

  /// Puntualidad por zona. Se pondera por entradas y no promediando los porcentajes de cada
  /// persona: una zona con un empleado de un día no debe pesar igual que una con veinte.
  List<(String, double, int)> get _porZona {
    final aTiempo = <String, int>{};
    final total = <String, int>{};
    for (final e in _evaluadas) {
      final z = (e['sucursal'] ?? '—').toString();
      total[z] = (total[z] ?? 0) + 1;
      if (e['es_retardo'] == false) aTiempo[z] = (aTiempo[z] ?? 0) + 1;
    }
    final lista = total.entries
        .map((t) => (t.key, (aTiempo[t.key] ?? 0) / t.value * 100, t.value))
        .toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    return lista;
  }

  /// Días a descontar por zona. Se suma el descuento de CADA PERSONA y no se recalcula sobre los
  /// totales de la zona: el cociente de los retardos se redondea por persona, y hacerlo sobre el
  /// agregado inflaría la cifra.
  ///
  /// No respeta el filtro de zona de la tabla a propósito: la gráfica existe para comparar las
  /// zonas entre sí, y filtrada a una sola dejaría una barra.
  List<(String, int)> get _descuentoPorZona {
    final porZona = <String, int>{};
    for (final f in _empleados) {
      final z = f.zona.isEmpty ? 'Sin zona' : f.zona;
      porZona[z] = (porZona[z] ?? 0) + f.diasDescuento;
    }
    final lista = porZona.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return lista;
  }

  Map<String, int> get _semaforo {
    final cuenta = {'critico': 0, 'atencion': 0, 'puntual': 0};
    for (final f in _empleados) {
      if (cuenta.containsKey(f.estatus)) cuenta[f.estatus] = cuenta[f.estatus]! + 1;
    }
    return cuenta;
  }

  // ── Construcción ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    if (_cargando) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SiSpace.x12),
          child: CircularProgressIndicator(color: c.brand),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(SiSpace.x6),
        child: Text('No se pudieron leer los registros: $_error',
            style: TextStyle(fontSize: 13, color: c.danger)),
      );
    }
    if (_entradas.isEmpty && _dias.isEmpty) return _vacio(c);

    return RefreshIndicator(
      onRefresh: _cargar,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SiSpace.x6),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _barraPeriodo(c),
            const SizedBox(height: SiSpace.x4),
            _kpis(c),
            if (_hayHorarioAmbiguo) ...[
              const SizedBox(height: SiSpace.x3),
              _avisoHorarioAmbiguo(c),
            ],
            const SizedBox(height: SiSpace.x5),
            if (_esAdmin) ...[
              LayoutBuilder(
                builder: (context, box) {
                  final zona = _tarjetaZonas(c);
                  final semaforo = _tarjetaSemaforo(c);
                  if (box.maxWidth < 820) {
                    return Column(children: [
                      zona,
                      const SizedBox(height: SiSpace.x4),
                      semaforo,
                    ]);
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: zona),
                      const SizedBox(width: SiSpace.x4),
                      Expanded(flex: 2, child: semaforo),
                    ],
                  );
                },
              ),
              const SizedBox(height: SiSpace.x5),
              LayoutBuilder(
                builder: (context, box) {
                  final detalle = _tarjetaDetalle(c);
                  final zonas = _tarjetaDescuentoZona(c);
                  // Mismos flex que la fila de arriba —3 y 2— para que en pantalla ancha los cuatro
                  // bloques queden alineados en dos columnas.
                  if (box.maxWidth < _anchoParaDosColumnas) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        detalle,
                        const SizedBox(height: SiSpace.x4),
                        zonas,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: detalle),
                      const SizedBox(width: SiSpace.x4),
                      Expanded(flex: 2, child: zonas),
                    ],
                  );
                },
              ),
            ] else
              _tarjetaMisDias(c),
          ],
        ),
      ),
    );
  }

  Widget _barraPeriodo(SiColors c) {
    final fmt = DateFormat('d MMM y', 'es_MX');
    final rango = _desde == null
        ? 'Sin periodo'
        : '${fmt.format(_desde!)} – ${fmt.format(_hasta!)}';
    return Wrap(
      spacing: SiSpace.x2,
      runSpacing: SiSpace.x2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _pastilla(c, Icons.event_outlined, rango, c.brand),
        _pastilla(
          c,
          _esAdmin ? Icons.admin_panel_settings_outlined : Icons.person_outline,
          _esAdmin ? 'Todos los empleados' : 'Sólo tus registros',
          c.ink3,
        ),
        if (_esAdmin)
          _pastilla(c, Icons.groups_outlined,
              '${_empleados.length} en vista', c.ink3),
      ],
    );
  }

  Widget _pastilla(SiColors c, IconData icono, String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rPill,
        border: Border.all(color: c.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icono, size: 13, color: color),
        const SizedBox(width: 6),
        Text(texto, style: TextStyle(fontSize: 12, color: c.ink2)),
      ]),
    );
  }

  Widget _kpis(SiColors c) {
    final pct = _puntualidad;
    return Wrap(
      spacing: SiSpace.x3,
      runSpacing: SiSpace.x3,
      children: [
        _tarjetaKpi(c, 'Puntualidad',
            pct == null ? '—' : '${pct.toStringAsFixed(1)}%',
            'del periodo',
            pct == null
                ? c.ink3
                : pct < _criticoMax
                    ? c.danger
                    : pct <= _atencionMax
                        ? c.warn
                        : c.success),
        _tarjetaKpi(c, 'Retardos', '$_retardos', 'llegadas tarde', c.warn),
        _tarjetaKpi(c, 'Faltas', '$_faltas', 'sin justificar', c.danger),
        _tarjetaKpi(c, 'Justificados', '$_justificados', 'días', c.ink2),
        _tarjetaKpi(c, 'Días a descontar', '$_diasDescuento', 'para nómina',
            _diasDescuento > 0 ? c.danger : c.success),
        _tarjetaKpi(c, 'Días evaluados', '${_evaluadas.length}', 'con checada', c.ink2),
        if (_esAdmin)
          _tarjetaKpi(c, 'Empleados', '${_empleados.length}', 'en el periodo', c.ink2),
      ],
    );
  }

  Widget _tarjetaKpi(
      SiColors c, String titulo, String valor, String pie, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(SiSpace.x3),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rMd,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo.toUpperCase(),
              style: SiType.mono(size: 9.5, color: c.ink3, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Text(valor,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: 4),
          Text(pie, style: TextStyle(fontSize: 11, color: c.ink3)),
        ],
      ),
    );
  }

  Widget _avisoHorarioAmbiguo(SiColors c) {
    return Container(
      padding: const EdgeInsets.all(SiSpace.x3),
      decoration: BoxDecoration(
        color: c.warnTint,
        borderRadius: SiRadius.rMd,
        border: Border.all(color: c.warn.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 15, color: c.warn),
        const SizedBox(width: SiSpace.x2),
        Expanded(
          child: Text(
            'El horario de cada persona se deduce de sus propias checadas, porque no está '
            'capturado en su expediente. Alguien aparece con más de un horario en el periodo, '
            'así que sus faltas son aproximadas. Capturar el horario en el expediente lo '
            'volvería exacto.',
            style: TextStyle(fontSize: 11.5, color: c.ink2, height: 1.4),
          ),
        ),
      ]),
    );
  }

  // ── Zonas ──────────────────────────────────────────────────────────────────

  Widget _tarjetaZonas(SiColors c) {
    final zonas = _porZona;
    return _tarjeta(
      c,
      Icons.bar_chart_outlined,
      'Puntualidad por zona',
      zonas.isEmpty
          ? _sinDatos(c)
          : Column(
              children: [
                for (final z in zonas) ...[
                  _barraZona(c, z.$1, z.$2, z.$3),
                  const SizedBox(height: SiSpace.x3),
                ],
              ],
            ),
    );
  }

  Widget _barraZona(SiColors c, String zona, double pct, int entradas) {
    final color = pct < _criticoMax
        ? c.danger
        : pct <= _atencionMax
            ? c.warn
            : c.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(zona.isEmpty ? 'Sin zona' : zona,
                style: TextStyle(fontSize: 12.5, color: c.ink)),
          ),
          Text('${pct.toStringAsFixed(1)}%',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 6),
          Text('($entradas)', style: TextStyle(fontSize: 11, color: c.ink4)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: c.line,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  // ── Semáforo ───────────────────────────────────────────────────────────────

  Widget _tarjetaSemaforo(SiColors c) {
    final s = _semaforo;
    final total = s.values.fold<int>(0, (a, b) => a + b);
    return _tarjeta(
      c,
      Icons.donut_large_outlined,
      'Semáforo de seguimiento',
      total == 0
          ? _sinDatos(c)
          : Column(children: [
              SizedBox(
                height: 150,
                child: CustomPaint(
                  painter: _DonaPainter(
                    valores: [
                      (s['critico']!, c.danger),
                      (s['atencion']!, c.warn),
                      (s['puntual']!, c.success),
                    ],
                    fondo: c.line,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$total',
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: c.ink)),
                        Text('personas',
                            style: TextStyle(fontSize: 11, color: c.ink3)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SiSpace.x3),
              _leyenda(c, 'Crítico', s['critico']!, c.danger,
                  'menos de ${_criticoMax.toStringAsFixed(0)}%'),
              _leyenda(c, 'Atención', s['atencion']!, c.warn,
                  'hasta ${_atencionMax.toStringAsFixed(0)}%'),
              _leyenda(c, 'Puntual', s['puntual']!, c.success,
                  'más de ${_atencionMax.toStringAsFixed(0)}%'),
            ]),
    );
  }

  Widget _leyenda(SiColors c, String etiqueta, int n, Color color, String rango) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
          width: 9, height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(etiqueta, style: TextStyle(fontSize: 12.5, color: c.ink)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(rango, style: TextStyle(fontSize: 11, color: c.ink4)),
        ),
        Text('$n',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  Widget _nota(SiColors c, IconData icono, String texto) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 13, color: c.ink4),
        const SizedBox(width: SiSpace.x2),
        Expanded(
          child: Text(texto,
              style: TextStyle(fontSize: 10.5, color: c.ink3, height: 1.4)),
        ),
      ],
    );
  }

  // ── Días a descontar por zona ──────────────────────────────────────────────

  Widget _tarjetaDescuentoZona(SiColors c) {
    final zonas = _descuentoPorZona;
    final maximo = zonas.isEmpty
        ? 0
        : zonas.map((z) => z.$2).reduce((a, b) => a > b ? a : b);
    // La escala se redondea al múltiplo de 5 de arriba para que las marcas salgan en números
    // redondos en lugar de terminar en 47 o 82.
    final tope = maximo == 0 ? 5 : ((maximo / 5).ceil() * 5);
    final total = zonas.fold<int>(0, (a, z) => a + z.$2);

    return _tarjeta(
      c,
      Icons.money_off,
      'Días a descontar por zona',
      zonas.isEmpty
          ? _sinDatos(c)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 190,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Eje: sólo tres marcas. Con la tarjeta a 330px, más números se encimarían.
                      SizedBox(
                        width: 22,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final v in [tope, tope ~/ 2, 0])
                              Text('$v',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: c.ink4,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ])),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final z in zonas)
                              Expanded(
                                child: _barraVertical(c, z.$1, z.$2, tope),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SiSpace.x3),
                Divider(height: 1, color: c.line2),
                const SizedBox(height: SiSpace.x2),
                Row(children: [
                  Text('Total del periodo',
                      style: TextStyle(fontSize: 11.5, color: c.ink3)),
                  const Spacer(),
                  Text('$total ${total == 1 ? 'día' : 'días'}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: total > 0 ? c.danger : c.success)),
                ]),
                const SizedBox(height: SiSpace.x2),
                _nota(
                  c,
                  Icons.info_outline,
                  'Cada falta sin justificar es 1 día, y los retardos se acumulan según la regla '
                  'de Configuración. El cociente se redondea por persona.',
                ),
              ],
            ),
    );
  }

  /// Una barra con su valor dentro y el nombre de la zona debajo. El texto sale arriba de la barra
  /// cuando ésta es demasiado baja para contenerlo.
  Widget _barraVertical(SiColors c, String zona, int valor, int tope) {
    final fraccion = tope == 0 ? 0.0 : (valor / tope).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final alto = box.maxHeight * fraccion;
                final cabeDentro = alto >= 22;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!cabeDentro)
                      Text('$valor',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: c.ink2)),
                    // Tope de ancho: con la tarjeta ensanchada a ~700px, cuatro columnas Expanded
                    // darían barras de 170px que se ven como bloques, no como una gráfica.
                    Container(
                      height: alto,
                      width: box.maxWidth.clamp(0.0, 72.0),
                      decoration: BoxDecoration(
                        color: c.brand,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                      alignment: Alignment.center,
                      child: cabeDentro
                          ? Text('$valor',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white))
                          : null,
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 5),
          Text(zona,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9.5, height: 1.2, color: c.ink3)),
        ],
      ),
    );
  }

  // ── Detalle por empleado (administrador) ───────────────────────────────────

  Widget _tarjetaDetalle(SiColors c) {
    final filas = _empleadosFiltrados;
    final s = _semaforo;

    return _tarjeta(
      c,
      Icons.people_outline,
      'Detalle por empleado',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Buscador y zona en el mismo renglón. El relleno vertical se define una vez y lo
          // comparten los dos controles, para que no se desalineen.
          Row(children: [
            Expanded(
              child: TextField(
                controller: _buscarCtrl,
                onChanged: (v) => setState(() => _busqueda = v),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o número…',
                  hintStyle: TextStyle(fontSize: 13, color: c.ink4),
                  prefixIcon: Icon(Icons.search, size: 17, color: c.ink3),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 36, minHeight: 0),
                  isDense: true,
                  contentPadding: _rellenoControl,
                  border: OutlineInputBorder(borderRadius: SiRadius.rMd),
                ),
              ),
            ),
            // Con una sola zona el filtro no filtra nada; sólo estorbaría.
            if (_zonas.length > 1) ...[
              const SizedBox(width: SiSpace.x3),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  value: _zonas.contains(_filtroZona) ? _filtroZona : 'todas',
                  isExpanded: true,
                  isDense: true,
                  style: TextStyle(fontSize: 13, color: c.ink),
                  icon: Icon(Icons.expand_more, size: 18, color: c.ink3),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: _rellenoControl,
                    prefixIcon:
                        Icon(Icons.place_outlined, size: 15, color: c.ink3),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 32, minHeight: 0),
                    border: OutlineInputBorder(borderRadius: SiRadius.rMd),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'todas',
                      child: Text('Todas las zonas',
                          style: TextStyle(fontSize: 13, color: c.ink2)),
                    ),
                    for (final z in _zonas)
                      DropdownMenuItem(
                        value: z,
                        child: Text(z,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: c.ink2)),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _filtroZona = v ?? 'todas'),
                ),
              ),
            ],
          ]),
          const SizedBox(height: SiSpace.x3),
          Wrap(
            spacing: SiSpace.x2,
            runSpacing: SiSpace.x2,
            children: [
              _chipFiltro(c, 'todos', 'Todos', _empleados.length, c.brand),
              _chipFiltro(c, 'critico', 'Críticos', s['critico']!, c.danger),
              _chipFiltro(c, 'atencion', 'Atención', s['atencion']!, c.warn),
              _chipFiltro(c, 'puntual', 'Puntuales', s['puntual']!, c.success),
            ],
          ),
          const SizedBox(height: SiSpace.x3),
          if (filas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SiSpace.x6),
              child: Center(
                child: Text('Nadie coincide con el filtro',
                    style: TextStyle(fontSize: 12.5, color: c.ink3)),
              ),
            )
          else
            // Desplazable en horizontal por dentro: con ocho columnas la tabla no cabe en
            // pantallas medianas, y el cuerpo de la página no debe desplazarse de lado.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                // Suma de los anchos de las ocho columnas; con menos, la última se corta.
                constraints: const BoxConstraints(minWidth: 678),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _encabezadoTabla(c),
                    Divider(height: 1, color: c.line),
                    for (final f in filas) _filaTabla(c, f),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chipFiltro(
      SiColors c, String valor, String etiqueta, int n, Color color) {
    final activo = _filtroEstatus == valor;
    return InkWell(
      onTap: () => setState(() => _filtroEstatus = valor),
      borderRadius: SiRadius.rPill,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: activo ? color : c.panel,
          borderRadius: SiRadius.rPill,
          border: Border.all(color: activo ? color : c.line),
        ),
        child: Text('$etiqueta ($n)',
            style: TextStyle(
                fontSize: 12,
                fontWeight: activo ? FontWeight.w600 : FontWeight.normal,
                color: activo ? Colors.white : c.ink2)),
      ),
    );
  }

  /// Relleno vertical compartido por el buscador y el desplegable, para que queden a la
  /// misma altura sin ajustarlo a ojo en cada uno.
  static const _rellenoControl =
      EdgeInsets.symmetric(horizontal: 12, vertical: 10);

  /// Ancho útil a partir del cual la fila de abajo va en dos columnas. Lo manda la tabla: con flex 3
  /// recibe 3/5 del ancho, y necesita 762px para sus ocho columnas.
  ///
  /// Ancho útil a partir del cual la fila de abajo va en dos columnas.
  ///
  /// Sale de la cuenta, no del ojo: la tabla recibe 3/5 del ancho menos el gap, y de ahí hay que
  /// restar los 32px de relleno de la tarjeta para llegar a las columnas.
  ///     (678 + 32) × 5/3 + 16 = 1199.3
  /// Por eso las columnas suman 678 y no más: es lo que cabe sin recortarlas conservando este corte.
  /// Con los 762 que daban las columnas apenas apretadas haría falta 1340px, y en una laptop —donde
  /// el área útil ronda los 1200— la fila se habría quedado apilada.
  ///
  /// Es más alto que el corte de la fila de arriba (820) a propósito. Igualarlos alinearía los
  /// cuatro bloques en todo ancho, pero obligaría a apilar también la de arriba a 1200. Entre 820 y
  /// 1200 la fila de abajo va apilada a lo ancho, que es lo normal cuando dos filas tienen
  /// contenidos de distinto ancho mínimo.
  static const _anchoParaDosColumnas = 1200.0;

  /// Suman 678px, apretadas desde 838. Cada ancho está medido contra lo que tiene que caber: el
  /// encabezado en mono de 9.5 con 0.8 de letterSpacing —'DÍAS DESC.' pide unos 65px— o el
  /// contenido, que en ZONA es un nombre como 'Baja California' y en ESTATUS la píldora con
  /// 'Atención'.
  static const _anchos = [184.0, 96.0, 90.0, 58.0, 50.0, 50.0, 68.0, 82.0];

  Widget _encabezadoTabla(SiColors c) {
    const titulos = [
      'EMPLEADO', 'ZONA', '% PUNT.', 'RETARDOS', 'FALTAS', 'JUSTIF.',
      'DÍAS DESC.', 'ESTATUS'
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SiSpace.x2),
      child: Row(
        children: [
          for (var i = 0; i < titulos.length; i++)
            SizedBox(
              width: _anchos[i],
              child: Text(titulos[i],
                  style: SiType.mono(
                      size: 9.5, color: c.ink3, letterSpacing: 0.8)),
            ),
        ],
      ),
    );
  }

  Widget _filaTabla(SiColors c, _FilaEmpleado f) {
    final pct = f.puntualidad;
    final color = f.estatus == 'critico'
        ? c.danger
        : f.estatus == 'atencion'
            ? c.warn
            : f.estatus == 'puntual'
                ? c.success
                : c.ink3;

    Widget celda(int i, Widget hijo) =>
        SizedBox(width: _anchos[i], child: hijo);

    return InkWell(
      onTap: () => _mostrarFicha(f),
      child: Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line2)),
      ),
      padding: const EdgeInsets.symmetric(vertical: SiSpace.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          celda(
            0,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.nombre,
                    // Con la columna en 184px, un nombre de cuatro apellidos se iría a tres
                    // renglones y estiraría toda la fila.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.brand,
                        decoration: TextDecoration.underline,
                        decorationColor: c.brand.withValues(alpha: 0.3))),
                Text(
                  [
                    if (f.numero.isNotEmpty) '#${f.numero}',
                    if (f.horario.isNotEmpty) f.horario,
                  ].join(' · '),
                  style: TextStyle(fontSize: 10.5, color: c.ink3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          celda(
            1,
            Text(f.zona.isEmpty ? '—' : f.zona,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.ink2)),
          ),
          celda(
            2,
            Row(children: [
              SizedBox(
                width: 42,
                child: Text(pct == null ? '—' : '${pct.toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ((pct ?? 0) / 100).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: c.line,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
            ]),
          ),
          celda(3, _num(c, f.retardos, f.retardos > 0 ? c.warn : c.ink3)),
          celda(4, _num(c, f.faltas, f.faltas > 0 ? c.danger : c.ink3)),
          celda(5, _num(c, f.justificados, c.ink3)),
          celda(
            6,
            Tooltip(
              message: f.diasDescuento == 0
                  ? 'Sin días a descontar'
                  : '${f.retardos} retardos ÷ ${f.retardosPorDescuento} = '
                      '${f.retardos ~/ f.retardosPorDescuento} · '
                      'faltas: ${f.faltas}',
              child: _num(c, f.diasDescuento,
                  f.diasDescuento > 0 ? c.danger : c.ink3),
            ),
          ),
          celda(
            7,
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: SiRadius.rPill,
                ),
                child: Text(_etiquetaEstatus[f.estatus] ?? f.estatus,
                    style: TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  static const _etiquetaEstatus = {
    'critico': 'Crítico',
    'atencion': 'Atención',
    'puntual': 'Puntual',
    'sin datos': 'Sin datos',
  };

  Widget _num(SiColors c, int n, Color color) => Text('$n',
      style: TextStyle(
          fontSize: 12.5,
          fontWeight: n > 0 ? FontWeight.w600 : FontWeight.normal,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()]));

  // ── Ficha por empleado ─────────────────────────────────────────────────────

  /// Abre el detalle al tocar el renglón. No hace otra consulta: los días ya están cargados para
  /// toda la vista, así que basta filtrar por la persona.
  ///
  /// La ficha vive en su propio widget con datos planos para poder probarse. Salió de un fallo real:
  /// incrustada aquí, su cuerpo aparecía en blanco y no había forma de reproducirlo, porque montar
  /// este panel exige sesión, permisos y tres consultas.
  Future<void> _mostrarFicha(_FilaEmpleado f) async {
    final dias = _dias.where((d) => d['profile_id'].toString() == f.id).toList()
      ..sort((a, b) => a['fecha'].toString().compareTo(b['fecha'].toString()));

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => FichaAsistencia(
        nombre: f.nombre,
        numero: f.numero,
        zona: f.zona,
        horario: f.horario,
        estatus: f.estatus,
        puntualidad: f.puntualidad,
        asistio: f.asistio,
        esperados: f.esperados,
        retardos: f.retardos,
        faltas: f.faltas,
        incompletas: f.incompletas,
        justificados: f.justificados,
        minutosTarde: f.minutos,
        diasDescuento: f.diasDescuento,
        reglaDescuento: 'Cada ${f.retardosPorDescuento} retardos son 1 día, '
            'y cada falta sin justificar es 1 día.',
        dias: dias,
      ),
    );
  }

  // ── Vista personal (usuario) ──────────────────────────────────────────────

  Widget _tarjetaMisDias(SiColors c) {
    // Un renglón por día que el horario pedía, con lo que pasó ese día.
    final porFecha = <String, Map<String, dynamic>>{};
    for (final e in _entradas) {
      porFecha[e['fecha'].toString()] = e;
    }
    final dias = [..._dias]..sort(
        (a, b) => b['fecha'].toString().compareTo(a['fecha'].toString()));

    final fmt = DateFormat('EEE d MMM', 'es_MX');

    return _tarjeta(
      c,
      Icons.event_note_outlined,
      'Mis días',
      dias.isEmpty
          ? _sinDatos(c)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final d in dias)
                  _filaMiDia(c, d, porFecha[d['fecha'].toString()], fmt),
              ],
            ),
    );
  }

  Widget _filaMiDia(SiColors c, Map<String, dynamic> dia,
      Map<String, dynamic>? entrada, DateFormat fmt) {
    final estado = dia['estado'].toString();
    final (Color color, String etiqueta) = switch (estado) {
      'FALTA' => (c.danger, 'Falta'),
      'JUSTIFICADO' => (c.ink3, 'Justificado'),
      _ => entrada?['es_retardo'] == true
          ? (c.warn, 'Retardo')
          : (c.success, 'A tiempo'),
    };

    final detalle = <String>[
      if (entrada?['hora'] != null && estado != 'JUSTIFICADO')
        'Entró ${entrada!['hora'].toString().substring(0, 5)}',
      if (entrada?['limite'] != null && estado != 'JUSTIFICADO')
        'límite ${entrada!['limite'].toString().substring(0, 5)}',
      if ((entrada?['minutos_retardo'] as num? ?? 0) > 0)
        '${entrada!['minutos_retardo']} min tarde',
      if (dia['estado'] == 'JUSTIFICADO' && entrada?['justificacion_motivo'] != null)
        entrada!['justificacion_motivo'].toString(),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line2)),
      ),
      padding: const EdgeInsets.symmetric(vertical: SiSpace.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4, height: 34,
            margin: const EdgeInsets.only(right: SiSpace.x3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(fmt.format(DateTime.parse(dia['fecha'].toString())),
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: c.ink)),
          ),
          SizedBox(
            width: 88,
            child: Text(etiqueta,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ),
          Expanded(
            child: Text(detalle.join(' · '),
                style: TextStyle(fontSize: 11.5, color: c.ink3)),
          ),
        ],
      ),
    );
  }

  // ── Piezas compartidas ────────────────────────────────────────────────────

  Widget _tarjeta(SiColors c, IconData icono, String titulo, Widget cuerpo) {
    return Container(
      padding: const EdgeInsets.all(SiSpace.x4),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rMd,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icono, size: 16, color: c.brand),
            const SizedBox(width: SiSpace.x2),
            Text(titulo,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
          ]),
          const SizedBox(height: SiSpace.x4),
          cuerpo,
        ],
      ),
    );
  }

  Widget _sinDatos(SiColors c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: SiSpace.x5),
        child: Center(
          child: Text('Sin datos en el periodo',
              style: TextStyle(fontSize: 12.5, color: c.ink3)),
        ),
      );

  Widget _vacio(SiColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SiSpace.x10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insights_outlined, size: 48, color: c.line),
            const SizedBox(height: SiSpace.x4),
            Text('Todavía no hay registros del checador',
                style: TextStyle(fontSize: 14, color: c.ink2)),
            const SizedBox(height: SiSpace.x2),
            Text(
              _esAdmin
                  ? 'Carga los reportes de appchecar desde la pestaña de Configuración.'
                  : 'Cuando se carguen los reportes, aquí verás tus días.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: c.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaEmpleado {
  _FilaEmpleado({
    required this.id,
    required this.nombre,
    required this.numero,
    required this.zona,
    required this.horario,
  });

  /// `profile_id`, para volver a filtrar sus días al abrir la ficha.
  final String id;
  final String nombre;
  final String numero;
  final String zona;
  final String horario;

  int evaluadas = 0;
  int retardos = 0;
  int faltas = 0;
  int justificados = 0;
  int minutos = 0;
  int esperados = 0;
  int asistio = 0;
  int incompletas = 0;
  String estatus = 'sin datos';

  /// Cuántos retardos equivalen a un día de descuento, según la configuración vigente.
  int retardosPorDescuento = 3;

  double? get puntualidad =>
      evaluadas == 0 ? null : (evaluadas - retardos) / evaluadas * 100;

  /// Días a descontar: el cociente de los retardos más las faltas sin justificar.
  ///
  /// Se redondea hacia abajo y POR PERSONA. Hacerlo sobre el total daría 34 días donde en realidad
  /// son 25: dos personas con 2 retardos cada una no hacen un día de descuento, y el error siempre
  /// caería en contra del trabajador.
  int get diasDescuento => (retardos ~/ retardosPorDescuento) + faltas;
}

/// Dona del semáforo. Se dibuja a mano en lugar de agregar una librería de gráficas: son tres
/// segmentos, y el proyecto ya arrastra 82 paquetes desactualizados.
class _DonaPainter extends CustomPainter {
  _DonaPainter({required this.valores, required this.fondo});

  final List<(int, Color)> valores;
  final Color fondo;

  @override
  void paint(Canvas canvas, Size size) {
    final total = valores.fold<int>(0, (a, b) => a + b.$1);
    final centro = Offset(size.width / 2, size.height / 2);
    final radio = math.min(size.width, size.height) / 2 - 6;
    final grosor = radio * 0.32;
    final rect = Rect.fromCircle(center: centro, radius: radio - grosor / 2);

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..color = fondo;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (total == 0) return;

    // Arranca arriba y avanza en el sentido del reloj.
    var inicio = -math.pi / 2;
    for (final (n, color) in valores) {
      if (n == 0) continue;
      final barrido = math.pi * 2 * (n / total);
      canvas.drawArc(
        rect,
        inicio,
        // Un pelo menos para dejar una separación visible entre segmentos.
        barrido - 0.02,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = grosor
          ..strokeCap = StrokeCap.butt
          ..color = color,
      );
      inicio += barrido;
    }
  }

  @override
  bool shouldRepaint(_DonaPainter old) =>
      old.valores != valores || old.fondo != fondo;
}
