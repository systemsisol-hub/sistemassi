import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/si_theme.dart';

/// Carga de los reportes de appchecar y bitácora de lo cargado.
///
/// Los dos reportes —checadas e incidencias— entran por el mismo botón: la Edge Function los
/// distingue por sus encabezados, así que no hay que elegir el tipo.
///
/// El resumen del import es lo que permite confiar en la carga. Ya destapó tres cosas que un
/// «listo» habría escondido: 16 colaboradores sin vincular por un tope de paginación, un número de
/// empleado que pertenecía a otra persona, y un nombre que no empataba por un `full_name`
/// incompleto.
class CargaReportes extends StatefulWidget {
  const CargaReportes({super.key, this.alCargar});

  /// Se avisa al terminar para que el panel vuelva a leer.
  final VoidCallback? alCargar;

  @override
  State<CargaReportes> createState() => _CargaReportesState();
}

class _CargaReportesState extends State<CargaReportes> {
  final _supabase = Supabase.instance.client;

  bool _subiendo = false;
  bool _cargando = true;
  List<Map<String, dynamic>> _importaciones = [];

  static const _etiquetaMotivo = {
    'INCAPACIDAD': 'Incapacidad',
    'VACACIONES': 'Vacaciones',
    'FALLA_APP': 'Falla de la app',
    'PERMISO': 'Permiso',
    'OTRO': 'Otros',
  };

  @override
  void initState() {
    super.initState();
    _leerBitacora();
  }

  Future<void> _leerBitacora() async {
    try {
      final datos = await _supabase
          .from('checador_importaciones')
          .select('archivo, fecha_inicio, fecha_fin, filas_leidas, filas_nuevas, importado_en')
          .order('importado_en', ascending: false)
          .limit(20);
      if (mounted) {
        setState(() {
          _importaciones = List<Map<String, dynamic>>.from(datos);
          _cargando = false;
        });
      }
    } catch (e) {
      debugPrint('bitácora de importaciones: $e');
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _subir() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      // El reporte dice .xls pero es HTML. El servidor no se fía de la extensión: valida el
      // contenido buscando los encabezados.
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
      await _leerBitacora();
      widget.alCargar?.call();
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
                  child: const Text('CERRAR')),
            ],
          ),
        );
      }
    }
  }

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
                _linea('Periodo',
                    '${_fFecha(periodo['inicio'])} – ${_fFecha(periodo['fin'])}'
                    '  (${periodo['dias']} días)', c),
                _linea(esIncidencias ? 'Días justificados' : 'Filas leídas',
                    '${filas['leidas']}', c),
                _linea('Nuevas', '${filas['nuevas']}', c),
                _linea('Actualizadas', '${filas['actualizadas']}', c),
                if ((filas['omitidas'] as num? ?? 0) > 0)
                  _linea('Omitidas', '${filas['omitidas']}', c),
                if (regs != null)
                  _linea('Entradas / Salidas',
                      '${regs['entradas']} / ${regs['salidas']}', c),
                _linea(esIncidencias ? 'Personas' : 'Empleados',
                    '${esIncidencias ? r['personas'] : r['empleados']}', c),
                if (motivos != null && motivos.isNotEmpty)
                  _linea(
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
                        esIncidencias
                            ? 'Todas las personas se reconocieron.'
                            : 'Todos los empleados y horarios se unieron correctamente.',
                        style: TextStyle(fontSize: 12, color: c.ink2),
                      ),
                    ),
                  ])
                else ...[
                  if (empleadosSin.isNotEmpty) ...[
                    Row(children: [
                      Icon(Icons.person_search_outlined, size: 16, color: c.warn),
                      const SizedBox(width: SiSpace.x2),
                      Expanded(
                        child: Text(
                          esIncidencias
                              ? '${empleadosSin.length} '
                                  '${empleadosSin.length == 1 ? 'nombre' : 'nombres'} del reporte '
                                  'no existe en el sistema, así que esos días NO quedaron '
                                  'justificados y siguen contando en la puntualidad.'
                              : '${empleadosSin.length} '
                                  '${empleadosSin.length == 1 ? 'empleado' : 'empleados'} no se '
                                  'pudo ligar a un colaborador. Sí cuentan en la puntualidad, con '
                                  'el nombre del reporte, pero quedan sin vincular.',
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
                          'distinguirlos antes de volver a subir el archivo.',
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
                          'existe aquí. Esas entradas SÍ quedan fuera del cálculo de puntualidad. '
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

  Widget _linea(String etiqueta, String valor, SiColors c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(etiqueta,
                  style: TextStyle(fontSize: 12, color: c.ink3)),
            ),
            Expanded(
              child: Text(valor,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: c.ink)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

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
            Icon(Icons.upload_file, size: 16, color: c.brand),
            const SizedBox(width: SiSpace.x2),
            Text('Reportes de App Checar',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
          ]),
          const SizedBox(height: SiSpace.x2),
          Text(
            'Sube el reporte de checadas o el de incidencias. Se reconocen solos, y volver a subir '
            'un periodo actualiza en lugar de duplicar.',
            style: TextStyle(fontSize: 12, color: c.ink3, height: 1.4),
          ),
          const SizedBox(height: SiSpace.x4),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _subiendo ? null : _subir,
              icon: _subiendo
                  ? const SizedBox(
                      width: 15, height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_file, size: 17),
              label: Text(_subiendo ? 'Procesando…' : 'Cargar reporte'),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: SiRadius.rMd),
              ),
            ),
          ),
          const SizedBox(height: SiSpace.x4),
          Divider(height: 1, color: c.line),
          const SizedBox(height: SiSpace.x3),
          Text('CARGAS RECIENTES',
              style: SiType.mono(size: 9.5, color: c.ink3, letterSpacing: 0.8)),
          const SizedBox(height: SiSpace.x2),
          if (_cargando)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SiSpace.x4),
              child: Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: c.brand),
                ),
              ),
            )
          else if (_importaciones.isEmpty)
            Text('Todavía no se ha cargado ningún reporte.',
                style: TextStyle(fontSize: 12, color: c.ink4))
          else
            for (final i in _importaciones)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Icon(Icons.description_outlined, size: 13, color: c.ink4),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_fFecha(i['fecha_inicio'])} – ${_fFecha(i['fecha_fin'])}',
                      style: TextStyle(fontSize: 12, color: c.ink2),
                    ),
                  ),
                  Text('${i['filas_leidas']} filas · ${i['filas_nuevas']} nuevas',
                      style: TextStyle(fontSize: 11, color: c.ink3)),
                ]),
              ),
        ],
      ),
    );
  }

  static final _fmt = DateFormat('d MMM y', 'es_MX');

  static String _fFecha(dynamic iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso.toString());
    return d == null ? iso.toString() : _fmt.format(d);
  }
}
