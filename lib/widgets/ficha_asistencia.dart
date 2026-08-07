import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/si_theme.dart';

/// Ficha de asistencia de una persona: sus métricas y el calendario del periodo.
///
/// Vive en su propio widget y recibe datos planos —sin Supabase de por medio— para poder probarse.
/// Nació de un fallo real: incrustada en el panel, el cuerpo del diálogo salía en blanco y sin
/// forma de reproducirlo, porque montar el panel exige sesión, permisos y tres consultas.
class FichaAsistencia extends StatelessWidget {
  const FichaAsistencia({
    super.key,
    required this.nombre,
    required this.numero,
    required this.zona,
    required this.horario,
    required this.estatus,
    required this.puntualidad,
    required this.asistio,
    required this.esperados,
    required this.retardos,
    required this.faltas,
    required this.incompletas,
    required this.justificados,
    required this.minutosTarde,
    required this.diasDescuento,
    required this.reglaDescuento,
    required this.dias,
  });

  final String nombre;
  final String numero;
  final String zona;
  final String horario;

  /// 'critico' | 'atencion' | 'puntual' | 'sin datos'
  final String estatus;
  final double? puntualidad;

  final int asistio;
  final int esperados;
  final int retardos;
  final int faltas;
  final int incompletas;
  final int justificados;
  final int minutosTarde;

  /// Días a descontar de esta persona y la regla con la que se calcularon, para poder explicarla.
  final int diasDescuento;
  final String reglaDescuento;

  /// Filas de `checador_dias` de esta persona, ordenadas por fecha.
  final List<Map<String, dynamic>> dias;

  static const _etiquetaEstatus = {
    'critico': 'Crítico',
    'atencion': 'Atención',
    'puntual': 'Puntual',
    'sin datos': 'Sin datos',
  };

  static const _diasSemana = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final color = switch (estatus) {
      'critico' => c.danger,
      'atencion' => c.warn,
      'puntual' => c.success,
      _ => c.ink3,
    };
    final porFecha = {for (final d in dias) d['fecha'].toString(): d};
    final anchoPantalla = MediaQuery.of(context).size.width;

    // Dialog y no AlertDialog: aquí el alto lo manda un Column con mainAxisSize.min y un Flexible
    // alrededor del área desplazable, que es una estructura predecible. AlertDialog mide su
    // contenido por dimensiones intrínsecas, y un viewport desplazable no las sabe calcular.
    return Dialog(
      backgroundColor: c.panel,
      insetPadding: const EdgeInsets.all(SiSpace.x6),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 820,
          // Sin tope de alto el diálogo crece más que la pantalla y el calendario se sale.
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _encabezado(context, c, color),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(SiSpace.x5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _kpis(c, color),
                    const SizedBox(height: SiSpace.x5),
                    // Abajo de 760px una cuadrícula de siete columnas deja celdas de ~50px, donde
                    // no cabe una hora. Ahí se cae a lista: es la misma información en el formato
                    // que el ancho permite.
                    if (anchoPantalla < 760)
                      _listaDias(context, c, porFecha)
                    else
                      for (final mes in _mesesDe(porFecha.keys)) ...[
                        _calendarioMes(context, c, mes, porFecha),
                        const SizedBox(height: SiSpace.x4),
                      ],
                    if (porFecha.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: SiSpace.x6),
                        child: Center(
                          child: Text('Sin días registrados en el periodo',
                              style: TextStyle(fontSize: 12.5, color: c.ink3)),
                        ),
                      )
                    else
                      _leyenda(c),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _encabezado(BuildContext context, SiColors c, Color color) {
    return Container(
      padding: const EdgeInsets.all(SiSpace.x5),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre,
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      [
                        if (numero.isNotEmpty) '#$numero',
                        if (zona.isNotEmpty) zona,
                        if (horario.isNotEmpty) horario,
                      ].join(' · '),
                      style: TextStyle(fontSize: 11.5, color: c.ink3),
                    ),
                    Container(
                      width: 7, height: 7,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    Text(_etiquetaEstatus[estatus] ?? estatus,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: color)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 19, color: c.ink3),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _kpis(SiColors c, Color color) {
    return Wrap(
      spacing: SiSpace.x2,
      runSpacing: SiSpace.x2,
      children: [
        _kpi(c, puntualidad == null ? '—' : '${puntualidad!.toStringAsFixed(1)}%',
            'Puntualidad', color),
        _kpi(c, '$asistio/$esperados', 'Asistió/esper.', c.ink),
        _kpi(c, '$retardos', 'Retardos', c.warn),
        _kpi(c, '$faltas', 'Faltas', c.danger),
        _kpi(c, '$incompletas', 'Incompletas', c.warn),
        _kpi(c, '$justificados', 'Justificados', c.ink2),
        _kpi(c, '$minutosTarde', 'Min. tarde', c.ink2),
        Tooltip(
          message: reglaDescuento,
          child: _kpi(c, '$diasDescuento', 'Días desc.',
              diasDescuento > 0 ? c.danger : c.success),
        ),
      ],
    );
  }

  Widget _kpi(SiColors c, String valor, String etiqueta, Color color) {
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(
          horizontal: SiSpace.x2, vertical: SiSpace.x3),
      decoration: BoxDecoration(
        color: c.hover,
        borderRadius: SiRadius.rMd,
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          Text(valor,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: 3),
          Text(etiqueta.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: SiType.mono(size: 8.5, color: c.ink3, letterSpacing: 0.4)),
        ],
      ),
    );
  }

  // ── Calendario ─────────────────────────────────────────────────────────────

  /// Los meses que toca el periodo. Casi siempre uno, pero una quincena a caballo entre dos meses
  /// debe pintar los dos.
  static List<DateTime> _mesesDe(Iterable<String> fechas) {
    final meses = <String, DateTime>{};
    for (final f in fechas) {
      final d = DateTime.tryParse(f);
      if (d == null) continue;
      meses['${d.year}-${d.month}'] = DateTime(d.year, d.month);
    }
    final lista = meses.values.toList()..sort();
    return lista;
  }

  Widget _calendarioMes(BuildContext context, SiColors c, DateTime mes,
      Map<String, Map<String, dynamic>> porFecha) {
    final primero = DateTime(mes.year, mes.month);
    final diasDelMes = DateTime(mes.year, mes.month + 1, 0).day;
    // DateTime.weekday va de 1 (lunes) a 7 (domingo); la cuadrícula arranca en domingo.
    final huecoInicial = primero.weekday % 7;
    final semanas = ((huecoInicial + diasDelMes) / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(DateFormat('MMMM y', 'es_MX').format(mes).toUpperCase(),
            style: SiType.mono(size: 10, color: c.ink3, letterSpacing: 1)),
        const SizedBox(height: SiSpace.x2),
        Row(
          children: [
            for (final d in _diasSemana)
              Expanded(
                child: Center(
                  child: Text(d,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: c.ink3)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var semana = 0; semana < semanas; semana++)
          // IntrinsicHeight es imprescindible aquí, y fue el origen de que el diálogo saliera en
          // blanco: un `Row` con crossAxisAlignment.stretch dentro de un SingleChildScrollView
          // recibe alto infinito, así que estiraba las celdas a infinito y la maquetación
          // reventaba con «BoxConstraints forces an infinite height». IntrinsicHeight mide primero
          // la celda más alta y con eso stretch ya tiene un número finito al que igualar.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _celda(context, c,
                        (semana * 7 + col) - huecoInicial + 1, diasDelMes, mes,
                        porFecha),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _celda(BuildContext context, SiColors c, int dia, int diasDelMes,
      DateTime mes, Map<String, Map<String, dynamic>> porFecha) {
    // minHeight y no height: con altura fija, dos renglones de hora desbordaban la celda y Flutter
    // dejaba el diálogo en blanco. Con mínimo, la fila entera crece hasta la celda más alta.
    const minAlto = 58.0;

    if (dia < 1 || dia > diasDelMes) {
      return Container(
        constraints: const BoxConstraints(minHeight: minAlto),
        decoration:
            BoxDecoration(border: Border.all(color: c.line2, width: 0.5)),
      );
    }

    final clave =
        '${mes.year}-${mes.month.toString().padLeft(2, '0')}-${dia.toString().padLeft(2, '0')}';
    final d = porFecha[clave];
    final esFalta = d?['estado'] == 'FALTA';
    final justificado = d?['justificado'] == true;
    final foto = (d?['foto_entrada'] ?? d?['foto_salida'])?.toString();

    return Container(
      constraints: const BoxConstraints(minHeight: minAlto),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      decoration: BoxDecoration(
        // Un tinte de fondo para lo que exige atención: se distingue antes de leer las horas.
        color: esFalta
            ? c.dangerTint
            : justificado
                ? c.warnTint
                : null,
        border: Border.all(color: c.line2, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(dia.toString().padLeft(2, '0'),
                  style: TextStyle(
                      fontSize: 10.5,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: d == null ? c.ink4 : c.ink2)),
              const Spacer(),
              if (foto != null && foto.isNotEmpty) _botonFoto(context, c, foto),
            ],
          ),
          if (d != null)
            if (esFalta)
              Text('Falta',
                  style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: c.danger))
            else ...[
              _hora(c, d['hora_entrada'], d['es_retardo'] == true,
                  d['minutos_retardo'], d['tiene_entrada'] != true),
              _hora(c, d['hora_salida'], d['salida_temprano'] == true,
                  d['minutos_antes'], d['tiene_salida'] != true),
            ],
        ],
      ),
    );
  }

  /// Los mismos días en lista, para cuando la cuadrícula no cabe.
  Widget _listaDias(BuildContext context, SiColors c,
      Map<String, Map<String, dynamic>> porFecha) {
    final claves = porFecha.keys.toList()..sort();
    final fmt = DateFormat('EEE d MMM', 'es_MX');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final k in claves)
          if (DateTime.tryParse(k) != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration:
                  BoxDecoration(border: Border(bottom: BorderSide(color: c.line2))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(fmt.format(DateTime.parse(k)),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: c.ink)),
                  ),
                  Expanded(
                    child: porFecha[k]!['estado'] == 'FALTA'
                        ? Text('Falta',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: c.danger))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _hora(
                                  c,
                                  porFecha[k]!['hora_entrada'],
                                  porFecha[k]!['es_retardo'] == true,
                                  porFecha[k]!['minutos_retardo'],
                                  porFecha[k]!['tiene_entrada'] != true),
                              _hora(
                                  c,
                                  porFecha[k]!['hora_salida'],
                                  porFecha[k]!['salida_temprano'] == true,
                                  porFecha[k]!['minutos_antes'],
                                  porFecha[k]!['tiene_salida'] != true),
                            ],
                          ),
                  ),
                  if ((porFecha[k]!['foto_entrada'] ?? porFecha[k]!['foto_salida']) != null)
                    _botonFoto(
                        context,
                        c,
                        (porFecha[k]!['foto_entrada'] ??
                                porFecha[k]!['foto_salida'])
                            .toString()),
                ],
              ),
            ),
      ],
    );
  }

  /// Una hora del día. Verde cuando está en regla, rojo cuando no, y un guion cuando falta el
  /// registro — que es el caso de 140 de los 588 días esperados, casi siempre la salida.
  Widget _hora(
      SiColors c, dynamic hora, bool malo, dynamic minutos, bool faltante) {
    if (faltante || hora == null) {
      return Text('— sin registro',
          style: TextStyle(fontSize: 9.5, color: c.warn),
          maxLines: 1,
          overflow: TextOverflow.ellipsis);
    }
    final texto = hora.toString();
    final min = minutos is num ? minutos.toInt() : 0;
    return Row(
      children: [
        Text(texto.length >= 5 ? texto.substring(0, 5) : texto,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: malo ? c.danger : c.success,
                fontFeatures: const [FontFeature.tabularFigures()])),
        if (malo && min > 0) ...[
          const SizedBox(width: 3),
          Flexible(
            child: Text('+$min',
                style: TextStyle(fontSize: 9, color: c.danger),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ],
    );
  }

  /// Abre la foto en otra pestaña. No se dibuja en línea porque vive en appchecar.com, que no manda
  /// cabeceras CORS: en web `Image.network` fallaría bajo CanvasKit y dejaría un hueco roto.
  Widget _botonFoto(BuildContext context, SiColors c, String url) {
    return Tooltip(
      message: 'Ver la foto de la checada',
      child: InkWell(
        onTap: () async {
          final ok = await launchUrl(Uri.parse(url),
              mode: LaunchMode.externalApplication);
          if (!ok) {
            await Clipboard.setData(ClipboardData(text: url));
          }
        },
        onLongPress: () => Clipboard.setData(ClipboardData(text: url)),
        borderRadius: BorderRadius.circular(4),
        child: Icon(Icons.photo_camera_outlined, size: 13, color: c.brand),
      ),
    );
  }

  Widget _leyenda(SiColors c) {
    Widget punto(Color color, String texto) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(texto, style: TextStyle(fontSize: 10.5, color: c.ink3)),
          ],
        );

    return Wrap(
      spacing: SiSpace.x4,
      runSpacing: SiSpace.x2,
      children: [
        punto(c.success, 'En regla'),
        punto(c.danger, 'Retardo o salida antes de hora'),
        punto(c.warn, 'Sin registro / justificado'),
      ],
    );
  }
}
