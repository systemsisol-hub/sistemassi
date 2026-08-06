import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme/si_theme.dart';

/// Puntualidad a partir de los reportes de appchecar.com.
///
/// El checador real es una aplicación de terceros; aquí sólo se lee el reporte que exporta. Se
/// sube el archivo, la Edge Function `checador-import` lo parsea y estas dos tarjetas leen la
/// vista `checador_entradas`.
///
/// El retardo NO se lee del reporte: la columna `Diferencia` de appchecar es un valor absoluto
/// sin signo, donde "4 min" se ve idéntico si la persona llegó 4 minutos antes o 4 tarde. Se
/// calcula en la vista contra nuestra tabla `schedules`. Por eso puede diferir un poco del
/// reporte de appchecar, que tiene su propia configuración de horarios: la tarjeta muestra las
/// dos cifras para que la diferencia sea visible en lugar de sorpresiva.
class ChecadorDashboard extends StatefulWidget {
  const ChecadorDashboard({super.key});

  @override
  State<ChecadorDashboard> createState() => _ChecadorDashboardState();
}

class _ChecadorDashboardState extends State<ChecadorDashboard> {
  final _supabase = Supabase.instance.client;

  bool _cargando = true;
  bool _subiendo = false;
  String? _error;
  bool _esAdmin = false;

  List<Map<String, dynamic>> _importaciones = [];
  String? _importacionSel;
  List<Map<String, dynamic>> _entradas = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Map<String, dynamic>? get _periodo {
    if (_importaciones.isEmpty) return null;
    return _importaciones.firstWhere(
      (i) => i['id'] == _importacionSel,
      orElse: () => _importaciones.first,
    );
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
            .from('profiles')
            .select('role')
            .eq('id', uid)
            .maybeSingle();
        _esAdmin = perfil?['role'] == 'admin';
      }

      final imps = await _supabase
          .from('checador_importaciones')
          .select('id, archivo, fecha_inicio, fecha_fin, filas_leidas, importado_en')
          .order('importado_en', ascending: false)
          .limit(50);
      _importaciones = List<Map<String, dynamic>>.from(imps);

      // Si la selección previa ya no existe (por ejemplo tras borrar un periodo), cae al más
      // reciente en lugar de quedarse mostrando un rango vacío.
      if (_importacionSel == null ||
          !_importaciones.any((i) => i['id'] == _importacionSel)) {
        _importacionSel = _importaciones.isEmpty ? null : _importaciones.first['id'] as String;
      }

      await _cargarEntradas();
      if (mounted) setState(() => _cargando = false);
    } catch (e) {
      debugPrint('checador: error al cargar: $e');
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _cargarEntradas() async {
    final p = _periodo;
    if (p == null) {
      _entradas = [];
      return;
    }
    final datos = await _supabase
        .from('checador_entradas')
        .select('clave, numero_empleado, nombre_reporte, departamento, fecha, hora, '
            'horario_nombre, limite, minutos_retardo, es_retardo, retardo_reportado, '
            'justificado, justificacion_motivo, justificacion_tipo')
        .gte('fecha', p['fecha_inicio'])
        .lte('fecha', p['fecha_fin'])
        .order('fecha');
    _entradas = List<Map<String, dynamic>>.from(datos);
  }

  // ── Carga del reporte ──────────────────────────────────────────────────────

  Future<void> _subirReporte() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      // El reporte de appchecar dice .xls pero es HTML; se aceptan las dos extensiones porque el
      // servidor no se fía de la extensión y valida el contenido buscando los encabezados.
      allowedExtensions: ['xls', 'xlsx', 'html', 'htm'],
      withData: true,
    );
    if (resultado == null || resultado.files.isEmpty) return;
    final archivo = resultado.files.first;
    final bytes = archivo.bytes;
    if (bytes == null) return;

    setState(() => _subiendo = true);
    try {
      final res = await _supabase.functions.invoke('checador-import', body: {
        'archivo': archivo.name,
        'contenido_base64': base64Encode(bytes),
      });
      final cuerpo = res.data;
      if (cuerpo is! Map || cuerpo['ok'] != true) {
        throw Exception(cuerpo is Map ? (cuerpo['error'] ?? cuerpo) : cuerpo);
      }
      if (mounted) setState(() => _subiendo = false);
      // El periodo recién cargado pasa a ser el seleccionado.
      _importacionSel = cuerpo['importacion_id'] as String?;
      await _cargar();
      if (mounted) await _mostrarResumen(Map<String, dynamic>.from(cuerpo));
    } catch (e) {
      if (mounted) setState(() => _subiendo = false);
      final msg = e is FunctionException
          ? (e.details is Map ? '${(e.details as Map)['error'] ?? e.details}' : '${e.details}')
          : '$e';
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('No se pudo cargar el reporte'),
            content: SizedBox(width: 420, child: SelectableText(msg)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CERRAR'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// El resumen es lo que permite confiar en la carga. Un import que sólo dijera "listo"
  /// escondería justo lo que importa: un empleado o un horario que no se pudo unir.
  Future<void> _mostrarResumen(Map<String, dynamic> r) async {
    final c = SiColors.of(context);
    final filas = Map<String, dynamic>.from(r['filas'] as Map);
    final periodo = Map<String, dynamic>.from(r['periodo'] as Map);
    final sin = Map<String, dynamic>.from(r['sin_empatar'] as Map);
    final empleadosSin = List<dynamic>.from(sin['empleados'] ?? const []);
    final horariosSin = List<dynamic>.from(sin['horarios'] ?? const []);
    final ambiguos = List<dynamic>.from(sin['ambiguos'] ?? const []);
    final todoEmpatado =
        empleadosSin.isEmpty && horariosSin.isEmpty && ambiguos.isEmpty;

    // Los dos reportes de appchecar entran por el mismo botón, así que el resumen se adapta: el de
    // checadas trae entradas/salidas y empleados; el de incidencias, personas y motivos.
    final esIncidencias = r['tipo'] == 'incidencias';
    final regs = r['registros'] == null
        ? null
        : Map<String, dynamic>.from(r['registros'] as Map);
    final motivos = r['motivos'] == null
        ? null
        : Map<String, dynamic>.from(r['motivos'] as Map);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(esIncidencias
            ? 'Incidencias cargadas'
            : 'Reporte de checadas cargado'),
        content: SizedBox(
          width: 460,
          child: SelectionArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _lineaResumen('Periodo',
                    '${_fFecha(periodo['inicio'])} – ${_fFecha(periodo['fin'])}'
                    '  (${periodo['dias']} días)', c),
                _lineaResumen(
                    esIncidencias ? 'Días justificados' : 'Filas leídas',
                    '${filas['leidas']}', c),
                _lineaResumen('Nuevas', '${filas['nuevas']}', c),
                _lineaResumen('Actualizadas', '${filas['actualizadas']}', c),
                if ((filas['omitidas'] as num? ?? 0) > 0)
                  _lineaResumen('Omitidas', '${filas['omitidas']}', c),
                if (regs != null)
                  _lineaResumen('Entradas / Salidas',
                      '${regs['entradas']} / ${regs['salidas']}', c),
                _lineaResumen(esIncidencias ? 'Personas' : 'Empleados',
                    '${esIncidencias ? r['personas'] : r['empleados']}', c),
                if (motivos != null && motivos.isNotEmpty)
                  _lineaResumen(
                      'Motivos',
                      motivos.entries
                          .map((e) =>
                              '${_etiquetaMotivo[e.key] ?? e.key}: ${e.value}')
                          .join(' · '),
                      c),
                const SizedBox(height: SiSpace.x3),
                if (todoEmpatado)
                  Row(children: [
                    Icon(Icons.check_circle_outline, size: 16, color: c.success),
                    const SizedBox(width: SiSpace.x2),
                    Expanded(
                      child: Text(
                        'Todos los empleados y horarios se unieron correctamente.',
                        style: TextStyle(fontSize: 12, color: c.ink2),
                      ),
                    ),
                  ])
                else ...[
                  // Las dos faltas tienen consecuencias distintas y hay que decirlo por separado:
                  // un horario sin empatar sí saca esas entradas del cálculo, pero un empleado sin
                  // perfil no — la puntualidad se calcula con el horario del reporte, no con el
                  // perfil. Decir que "no entran en el cálculo" en los dos casos alarmaba de más.
                  if (empleadosSin.isNotEmpty) ...[
                    Row(children: [
                      Icon(Icons.person_search_outlined, size: 16, color: c.warn),
                      const SizedBox(width: SiSpace.x2),
                      Expanded(
                        child: Text(
                          esIncidencias
                              // Sin perfil la justificación no se puede pegar al día, así que ese
                              // día sigue contando como una entrada normal — y como el registro
                              // viene a la hora del horario, contaría como puntual.
                              ? '${empleadosSin.length} '
                                  '${empleadosSin.length == 1 ? 'nombre' : 'nombres'} del reporte '
                                  'no existe en el sistema, así que esos días NO quedaron '
                                  'justificados y siguen contando en la puntualidad.'
                              : '${empleadosSin.length} '
                                  '${empleadosSin.length == 1 ? 'empleado' : 'empleados'} del '
                                  'reporte no se pudo ligar a un colaborador del sistema. Sí '
                                  'cuentan en la puntualidad, con el nombre que trae el reporte, '
                                  'pero quedan sin vincular a su expediente.',
                          style: TextStyle(fontSize: 12, color: c.ink2),
                        ),
                      ),
                    ]),
                    const SizedBox(height: SiSpace.x2),
                    Text(
                      empleadosSin
                          .map((e) => '${e['nombre']} (${e['numero']})')
                          .join(', '),
                      style: TextStyle(fontSize: 12, color: c.ink3),
                    ),
                  ],
                  // Un nombre que aparece en dos perfiles: no se justifica el día de nadie, porque
                  // adivinar le asignaría la falta a la persona equivocada.
                  if (ambiguos.isNotEmpty) ...[
                    if (empleadosSin.isNotEmpty) const SizedBox(height: SiSpace.x3),
                    Row(children: [
                      Icon(Icons.error_outline, size: 16, color: c.danger),
                      const SizedBox(width: SiSpace.x2),
                      Expanded(
                        child: Text(
                          '${ambiguos.length} '
                          '${ambiguos.length == 1 ? 'nombre coincide' : 'nombres coinciden'} con '
                          'más de un colaborador, así que no se justificó ese día. Hay que '
                          'distinguirlos en el sistema antes de volver a subir el archivo.',
                          style: TextStyle(fontSize: 12, color: c.ink2),
                        ),
                      ),
                    ]),
                    const SizedBox(height: SiSpace.x2),
                    Text(ambiguos.join(', '),
                        style: TextStyle(fontSize: 12, color: c.ink3)),
                  ],
                  if (horariosSin.isNotEmpty) ...[
                    if (empleadosSin.isNotEmpty || ambiguos.isNotEmpty)
                      const SizedBox(height: SiSpace.x3),
                    Row(children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: c.danger),
                      const SizedBox(width: SiSpace.x2),
                      Expanded(
                        child: Text(
                          '${horariosSin.length} '
                          '${horariosSin.length == 1 ? 'horario' : 'horarios'} del reporte no '
                          'existe aquí. Esas entradas SÍ quedan fuera del cálculo de puntualidad, '
                          'porque sin horario no hay hora de entrada contra la que comparar. '
                          'Créalos con el mismo nombre y vuelve a subir el reporte.',
                          style: TextStyle(fontSize: 12, color: c.ink2),
                        ),
                      ),
                    ]),
                    const SizedBox(height: SiSpace.x2),
                    Text(horariosSin.join(', '),
                        style: TextStyle(fontSize: 12, color: c.ink3)),
                  ],
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('LISTO')),
        ],
      ),
    );
  }

  Widget _lineaResumen(String etiqueta, String valor, SiColors c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: Text(etiqueta, style: TextStyle(fontSize: 12, color: c.ink3)),
            ),
            Expanded(
              child: Text(valor,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: c.ink)),
            ),
          ],
        ),
      );

  // ── Agregados ──────────────────────────────────────────────────────────────

  /// Sólo las entradas con horario resuelto para ese día. Las demás no son "a tiempo": no se
  /// sabe, y meterlas en el denominador ensuciaría el porcentaje.
  Iterable<Map<String, dynamic>> get _evaluadas =>
      _entradas.where((e) => e['es_retardo'] != null);

  int get _retardos => _evaluadas.where((e) => e['es_retardo'] == true).length;
  int get _aTiempo => _evaluadas.where((e) => e['es_retardo'] == false).length;

  /// Días con falta justificada. La persona no checó: el reporte de checadas trae un registro a la
  /// hora del horario, pero es un relleno administrativo, no una llegada.
  Iterable<Map<String, dynamic>> get _justificadas =>
      _entradas.where((e) => e['justificado'] == true);

  /// Los que quedan fuera del cálculo por no tener regla de horario ese día. Se cuentan aparte de
  /// los justificados: «no sabemos» y «no vino, y está justificado» no son lo mismo, y juntarlos
  /// en una sola cifra sería engañoso.
  int get _sinHorario =>
      _entradas.length - _evaluadas.length - _justificadas.length;

  /// Conteo por motivo, de mayor a menor.
  List<(String, int)> get _porMotivo {
    final cuenta = <String, int>{};
    for (final e in _justificadas) {
      final tipo = (e['justificacion_tipo'] ?? 'OTRO').toString();
      cuenta[tipo] = (cuenta[tipo] ?? 0) + 1;
    }
    final lista = cuenta.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return lista;
  }

  static const _etiquetaMotivo = {
    'INCAPACIDAD': 'Incapacidad',
    'VACACIONES': 'Vacaciones',
    'FALLA_APP': 'Falla de la app',
    'PERMISO': 'Permiso',
    'OTRO': 'Otros',
  };
  int get _minutos => _evaluadas.fold<int>(
      0, (s, e) => s + ((e['minutos_retardo'] as num?)?.toInt() ?? 0));
  int get _reportadosPorAppchecar =>
      _entradas.where((e) => e['retardo_reportado'] == true).length;

  List<_FilaPersona> get _ranking {
    final porPersona = <String, _FilaPersona>{};
    for (final e in _evaluadas) {
      final clave = (e['clave'] ?? e['numero_empleado'] ?? '?').toString();
      final fila = porPersona.putIfAbsent(
        clave,
        () => _FilaPersona(
          nombre: (e['nombre_reporte'] ?? 'Sin nombre').toString(),
          departamento: (e['departamento'] ?? '').toString(),
        ),
      );
      fila.evaluadas++;
      if (e['es_retardo'] == true) {
        fila.retardos++;
        fila.minutos += (e['minutos_retardo'] as num?)?.toInt() ?? 0;
      }
    }
    final lista = porPersona.values.where((f) => f.retardos > 0).toList()
      ..sort((a, b) {
        final porRetardos = b.retardos.compareTo(a.retardos);
        return porRetardos != 0 ? porRetardos : b.minutos.compareTo(a.minutos);
      });
    return lista;
  }

  // ── Construcción ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    if (_cargando) {
      return Card(
        margin: EdgeInsets.zero,
        child: SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator(color: c.brand)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        final kpis = _buildTarjetaKpis(c);
        final ranking = _buildTarjetaRanking(c);
        // Por debajo de 700px las dos tarjetas lado a lado quedan demasiado angostas para las
        // cifras; se apilan.
        if (box.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [kpis, const SizedBox(height: SiSpace.x4), ranking],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: kpis),
            const SizedBox(width: SiSpace.x4),
            Expanded(child: ranking),
          ],
        );
      },
    );
  }

  Widget _buildTarjetaKpis(SiColors c) {
    final p = _periodo;
    final evaluadas = _evaluadas.length;
    final pct = evaluadas == 0 ? null : (_aTiempo / evaluadas) * 100;

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _encabezado(
            c: c,
            icono: Icons.verified_outlined,
            titulo: 'Puntualidad',
            accion: _esAdmin
                ? Tooltip(
                    message: 'Cargar reporte de appchecar',
                    child: InkWell(
                      onTap: _subiendo ? null : _subirReporte,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _subiendo ? c.line : c.brand,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _subiendo
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.upload_file,
                                size: 18, color: Colors.white),
                      ),
                    ),
                  )
                : null,
          ),
          Divider(height: 1, color: c.line),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(SiSpace.x4),
              child: Text('No se pudieron leer los registros: $_error',
                  style: TextStyle(fontSize: 12, color: c.danger)),
            )
          else if (p == null)
            _vacio(c)
          else
            Padding(
              padding: const EdgeInsets.all(SiSpace.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _selectorPeriodo(c),
                  const SizedBox(height: SiSpace.x4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        pct == null ? '—' : '${pct.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: pct == null
                              ? c.ink3
                              : pct >= 90
                                  ? c.success
                                  : pct >= 75
                                      ? c.warn
                                      : c.danger,
                        ),
                      ),
                      const SizedBox(width: SiSpace.x2),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('a tiempo',
                            style: TextStyle(fontSize: 12, color: c.ink3)),
                      ),
                    ],
                  ),
                  const SizedBox(height: SiSpace.x4),
                  Wrap(
                    spacing: SiSpace.x6,
                    runSpacing: SiSpace.x3,
                    children: [
                      _cifra('Entradas', '$evaluadas', c.ink, c),
                      _cifra('A tiempo', '$_aTiempo', c.success, c),
                      _cifra('Retardos', '$_retardos', c.danger, c),
                      _cifra('Minutos acumulados', _fNum(_minutos), c.warn, c),
                    ],
                  ),
                  if (_justificadas.isNotEmpty) ...[
                    const SizedBox(height: SiSpace.x3),
                    _nota(
                      c,
                      Icons.event_busy_outlined,
                      '${_justificadas.length} '
                      '${_justificadas.length == 1 ? 'falta justificada' : 'faltas justificadas'}'
                      ' — ${_porMotivo.map((m) => '${_etiquetaMotivo[m.$1] ?? m.$1}: ${m.$2}').join(' · ')}.'
                      ' Esos días la persona no checó, así que quedan fuera de la puntualidad.',
                    ),
                  ],
                  if (_sinHorario > 0) ...[
                    const SizedBox(height: SiSpace.x3),
                    _nota(
                      c,
                      Icons.help_outline,
                      '$_sinHorario ${_sinHorario == 1 ? 'entrada' : 'entradas'} sin regla de '
                      'horario para ese día. No cuentan como retardo ni como puntual.',
                    ),
                  ],
                  const SizedBox(height: SiSpace.x3),
                  Divider(height: 1, color: c.line2),
                  const SizedBox(height: SiSpace.x3),
                  // Contraste con el veredicto propio de appchecar, que viaja en el color de la
                  // celda de su reporte. Coincidir es la señal de que nuestros horarios están
                  // bien capturados; separarse apunta a un horario que difiere entre los dos
                  // sistemas, no a un error de cálculo.
                  _nota(
                    c,
                    _retardos == _reportadosPorAppchecar
                        ? Icons.check_circle_outline
                        : Icons.compare_arrows,
                    _retardos == _reportadosPorAppchecar
                        ? 'Coincide con appchecar: los dos cuentan $_retardos fuera de tiempo. '
                            'Los horarios capturados aquí son los mismos que tiene el checador.'
                        : 'appchecar marca $_reportadosPorAppchecar fuera de tiempo y el cálculo '
                            'contra nuestros horarios da $_retardos. La diferencia apunta a un '
                            'horario que no está igual en los dos sistemas.',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTarjetaRanking(SiColors c) {
    final ranking = _ranking;
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _encabezado(
            c: c,
            icono: Icons.trending_down,
            titulo: 'Retardos por persona',
            contador: ranking.isEmpty ? null : '${ranking.length}',
          ),
          Divider(height: 1, color: c.line),
          if (_periodo == null)
            _vacio(c)
          else if (ranking.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SiSpace.x8),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline, size: 40, color: c.success),
                    const SizedBox(height: SiSpace.x3),
                    Text('Nadie llegó tarde en el periodo',
                        style: TextStyle(fontSize: 13, color: c.ink3)),
                  ],
                ),
              ),
            )
          else
            ConstrainedBox(
              // Con muchas personas la tarjeta crecería sin fin y empujaría la página; se acota
              // y se hace desplazable por dentro.
              constraints: const BoxConstraints(maxHeight: 420),
              child: SelectionArea(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: ranking.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: c.line2),
                  itemBuilder: (ctx, i) => _filaPersona(ranking[i], c),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filaPersona(_FilaPersona f, SiColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: SiSpace.x4, vertical: SiSpace.x2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.nombre,
                    softWrap: true,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: c.ink)),
                if (f.departamento.isNotEmpty)
                  Text(f.departamento,
                      style: TextStyle(fontSize: 11, color: c.ink3)),
              ],
            ),
          ),
          const SizedBox(width: SiSpace.x2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${f.retardos} de ${f.evaluadas}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.danger,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              Text('${_fNum(f.minutos)} min',
                  style: TextStyle(
                      fontSize: 11,
                      color: c.ink3,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _selectorPeriodo(SiColors c) {
    final p = _periodo!;
    final etiqueta =
        '${_fFecha(p['fecha_inicio'])} – ${_fFecha(p['fecha_fin'])}';
    if (_importaciones.length == 1) {
      return Row(
        children: [
          Icon(Icons.event_outlined, size: 15, color: c.ink4),
          const SizedBox(width: SiSpace.x2),
          Text(etiqueta, style: TextStyle(fontSize: 12, color: c.ink2)),
        ],
      );
    }
    return Row(
      children: [
        Icon(Icons.event_outlined, size: 15, color: c.ink4),
        const SizedBox(width: SiSpace.x2),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: p['id'] as String,
              isDense: true,
              isExpanded: true,
              style: TextStyle(fontSize: 12, color: c.ink2),
              items: [
                for (final i in _importaciones)
                  DropdownMenuItem(
                    value: i['id'] as String,
                    child: Text(
                      '${_fFecha(i['fecha_inicio'])} – ${_fFecha(i['fecha_fin'])}',
                      style: TextStyle(fontSize: 12, color: c.ink2),
                    ),
                  ),
              ],
              onChanged: (v) async {
                if (v == null || v == _importacionSel) return;
                setState(() {
                  _importacionSel = v;
                  _cargando = true;
                });
                try {
                  await _cargarEntradas();
                } catch (e) {
                  _error = '$e';
                }
                if (mounted) setState(() => _cargando = false);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _encabezado({
    required SiColors c,
    required IconData icono,
    required String titulo,
    String? contador,
    Widget? accion,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          SiSpace.x4, SiSpace.x3, SiSpace.x2, SiSpace.x3),
      child: Row(
        children: [
          Icon(icono, size: 17, color: c.brand),
          const SizedBox(width: SiSpace.x2),
          Text(titulo,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
          if (contador != null) ...[
            const SizedBox(width: SiSpace.x2),
            Text(contador, style: TextStyle(fontSize: 12, color: c.ink3)),
          ],
          const Spacer(),
          if (accion != null) accion,
        ],
      ),
    );
  }

  Widget _cifra(String etiqueta, String valor, Color color, SiColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(valor,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()])),
        Text(etiqueta, style: TextStyle(fontSize: 11, color: c.ink3)),
      ],
    );
  }

  Widget _nota(SiColors c, IconData icono, String texto) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 14, color: c.ink4),
        const SizedBox(width: SiSpace.x2),
        Expanded(
          child: Text(texto,
              style: TextStyle(fontSize: 11, color: c.ink3, height: 1.4)),
        ),
      ],
    );
  }

  Widget _vacio(SiColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: SiSpace.x8, horizontal: SiSpace.x4),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.upload_file, size: 40, color: c.line),
            const SizedBox(height: SiSpace.x3),
            Text('Todavía no hay registros del checador',
                style: TextStyle(fontSize: 13, color: c.ink3)),
            const SizedBox(height: SiSpace.x1),
            Text(
              _esAdmin
                  ? 'Carga el reporte que exporta appchecar con el botón de arriba.'
                  : 'Un administrador debe cargar el reporte de appchecar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: c.ink4),
            ),
          ],
        ),
      ),
    );
  }

  static final _fmtFecha = DateFormat('d MMM y', 'es_MX');
  static final _fmtNum = NumberFormat.decimalPattern('es_MX');

  static String _fFecha(dynamic iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso.toString());
    return d == null ? iso.toString() : _fmtFecha.format(d);
  }

  static String _fNum(int n) => _fmtNum.format(n);
}

class _FilaPersona {
  _FilaPersona({required this.nombre, required this.departamento});

  final String nombre;
  final String departamento;
  int evaluadas = 0;
  int retardos = 0;
  int minutos = 0;
}
