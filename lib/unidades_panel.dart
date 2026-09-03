import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';
import 'unidades_pegado.dart';

/// El inventario de un desarrollo: las unidades una por una.
///
/// ─── Se EMBEBE, no se empuja ────────────────────────────────────────────────
///
/// Al principio esto era una pantalla aparte, a la que se llegaba desde un boton de la tarjeta del
/// desarrollo. El usuario lo dijo claro el 03/09/2026: los datos, el inventario y las promociones
/// del mismo desarrollo estaban repartidos en tres sitios y obligaban a entrar y salir. Asi que ya
/// no trae Scaffold ni barra propia: es un bloque que se monta dentro del detalle del desarrollo.
///
/// Por eso la tabla NO tiene desplazamiento vertical propio: el de la pantalla que lo contiene se
/// encarga. Dos desplazamientos verticales anidados pelean entre si y el de dentro se come el
/// gesto del de fuera.
///
/// ─── Cómo se actualiza ──────────────────────────────────────────────────────
///
/// De dos maneras, y las dos hacen falta:
///
///   - **Pegando la lista del mes.** Es como llega el dato: un Excel mensual —«DISPONIBLES AG117
///     SEPTIEMBRE 1»— que sólo trae las disponibles. Se pega, se revisa qué cambia, y se guarda.
///   - **A mano, unidad por unidad.** Para lo que pasa a media semana: una unidad se aparta y no
///     hay por qué esperar a la lista del mes siguiente.
///
/// ─── Lo que NO se guarda ────────────────────────────────────────────────────
///
/// Los metros totales y el precio por m² son columnas generadas en la base. Aquí sólo se muestran.
/// El archivo los trae calculados y cuadran fila por fila, así que guardarlos sería tener el mismo
/// hecho en dos lugares —y en este proyecto eso siempre acaba en dos números distintos—.
class InventarioDesarrollo extends StatefulWidget {
  final String desarrolloId;
  final String nombreDesarrollo;
  final bool puedeEditar;

  /// Se avisa al padre cuando el inventario cambio, para que actualice lo que depende de el: los
  /// contadores de la lista y el rango de precios del desarrollo, que sale de las unidades.
  final VoidCallback? onCambio;

  const InventarioDesarrollo({
    super.key,
    required this.desarrolloId,
    required this.nombreDesarrollo,
    required this.puedeEditar,
    this.onCambio,
  });

  @override
  State<InventarioDesarrollo> createState() => _InventarioDesarrolloState();
}

class _InventarioDesarrolloState extends State<InventarioDesarrollo> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _unidades = [];
  Map<String, dynamic>? _resumen;
  /// Cómo llama ESTE desarrollo a cada campo: `{'torre': 'EDIFICIO'}`.
  ///
  /// Se aprende del encabezado del Excel al pegarlo, así que la tabla acaba diciendo «EDIFICIO» en
  /// Vidamar y «Torre» en AG117 sin que nadie lo configure. Es la respuesta a «en AG117 torre sería
  /// edificio en Vidamar»: un solo campo, y el nombre es un dato del desarrollo.
  Map<String, String> _etiquetas = {};
  bool _cargando = true;
  String _filtro = 'DISPONIBLE';
  String _busqueda = '';

  static const estatuses = ['DISPONIBLE', 'APARTADO', 'VENDIDO', 'NO_DISPONIBLE'];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final uni = await _supabase
          .from('unidades')
          .select()
          .eq('desarrollo_id', widget.desarrolloId)
          .order('numero', ascending: true);
      // El resumen sale de la vista, la MISMA que usa SOL. Si se contara aquí, el panel y el
      // asistente podrían acabar dando totales distintos.
      final res = await _supabase
          .from('v_desarrollo_inventario')
          .select()
          .eq('desarrollo_id', widget.desarrolloId)
          .maybeSingle();
      final des = await _supabase
          .from('desarrollos')
          .select('etiquetas')
          .eq('id', widget.desarrolloId)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _unidades =
            (uni as List).map((e) => Map<String, dynamic>.from(e)).toList();
        _resumen = res == null ? null : Map<String, dynamic>.from(res);
        _etiquetas = ((des?['etiquetas'] ?? {}) as Map)
            .map((k, v) => MapEntry(k.toString(), v.toString()));
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _aviso('No se pudo cargar el inventario: $e', error: true);
    }
  }

  void _aviso(String texto, {bool error = false}) {
    if (!mounted) return;
    final c = SiColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? c.danger : c.success,
    ));
  }

  static String dinero(dynamic v) {
    if (v == null) return '—';
    final n = num.tryParse(v.toString());
    if (n == null) return '—';
    final entero = n.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < entero.length; i++) {
      if (i > 0 && (entero.length - i) % 3 == 0) buf.write(',');
      buf.write(entero[i]);
    }
    return '\$$buf';
  }

  static String metros(dynamic v) {
    if (v == null) return '—';
    final n = num.tryParse(v.toString());
    if (n == null) return '—';
    return '${n.toStringAsFixed(2)} m²';
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final q = _busqueda.trim().toLowerCase();
    final vistas = _unidades.where((u) {
      if (_filtro != 'TODAS' && (u['estatus'] ?? '') != _filtro) return false;
      if (q.isEmpty) return true;
      return ('${u['numero']} ${u['depto']} ${u['sector']} ${u['torre']} '
              '${u['nivel']} ${u['tipologia']} ${u['vista']}')
          .toLowerCase()
          .contains(q);
    }).toList();

    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.all(SiSpace.x8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabecera(c),
        if (_unidades.isEmpty) _vacio(c) else _tabla(c, vistas),
      ],
    );
  }

  Widget _vacio(SiColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SiSpace.x6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.grid_view_outlined, size: 40, color: c.ink3),
            const SizedBox(height: SiSpace.x4),
            Text('Sin inventario cargado',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
            const SizedBox(height: SiSpace.x2),
            Text(
              widget.puedeEditar
                  ? 'Copia las filas del Excel de disponibles y pégalas con el botón de arriba.\n'
                      'Mientras no haya unidades, SOL contesta que el precio no está capturado.'
                  : 'Todavía no se ha cargado el inventario de este desarrollo.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: c.ink3, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cabecera(SiColors c) {
    final r = _resumen;
    final listaAl = r?['lista_al'];
    return Container(
      padding: const EdgeInsets.only(bottom: SiSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: SiSpace.x5,
            runSpacing: SiSpace.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _contador(c, 'Disponibles', r?['disponibles'], c.success),
              _contador(c, 'Apartadas', r?['apartadas'], c.warn),
              _contador(c, 'Vendidas', r?['vendidas'], c.ink3),
              _contador(c, 'Totales', r?['unidades_totales'], c.ink),
              if (r?['precio_desde'] != null)
                _dato(c, 'Precio disponible',
                    '${dinero(r!['precio_desde'])} – ${dinero(r['precio_hasta'])}'),
              if (r?['m2_desde'] != null)
                _dato(c, 'Superficie',
                    '${metros(r!['m2_desde'])} – ${metros(r['m2_hasta'])}'),
              if (listaAl != null)
                _dato(c, 'Lista del', listaAl.toString().split('T').first),
            ],
          ),
          const SizedBox(height: SiSpace.x3),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _busqueda = v),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Buscar por número, depto, torre, tipología…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(borderRadius: SiRadius.rSm),
                  ),
                ),
              ),
              const SizedBox(width: SiSpace.x3),
              DropdownButton<String>(
                value: _filtro,
                underline: const SizedBox.shrink(),
                items: ['DISPONIBLE', 'APARTADO', 'VENDIDO', 'NO_DISPONIBLE', 'TODAS']
                    .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(_bonito(e), style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) => setState(() => _filtro = v ?? 'DISPONIBLE'),
              ),
              if (widget.puedeEditar) ...[
                const SizedBox(width: SiSpace.x3),
                FilledButton.icon(
                  onPressed: _pegarLista,
                  icon: const Icon(Icons.content_paste, size: 15),
                  label: const Text('Pegar lista del Excel'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _bonito(String estatus) => switch (estatus) {
        'NO_DISPONIBLE' => 'No disponible',
        'TODAS' => 'Todas',
        'DISPONIBLE' => 'Disponibles',
        'APARTADO' => 'Apartadas',
        'VENDIDO' => 'Vendidas',
        _ => estatus,
      };

  Widget _contador(SiColors c, String etiqueta, dynamic valor, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${valor ?? 0}',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        Text(etiqueta, style: TextStyle(fontSize: 11, color: c.ink3)),
      ],
    );
  }

  Widget _dato(SiColors c, String etiqueta, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(valor,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: c.ink)),
        Text(etiqueta, style: TextStyle(fontSize: 11, color: c.ink3)),
      ],
    );
  }

  /// Si ALGUNA unidad de este desarrollo trae sector.
  ///
  /// AG117 no lo usa y Vidamar si, asi que la columna aparece o no segun el desarrollo. Una columna
  /// vacia entre once ya ocupadas solo estorba, y la tabla ya desborda a lo ancho.
  bool get _haySector =>
      _unidades.any((u) => (u['sector'] ?? '').toString().trim().isNotEmpty);

  /// El título de una columna: el nombre que le da este desarrollo, o el de siempre.
  String _titulo(String columna, String porDefecto) =>
      (_etiquetas[columna] ?? porDefecto).toUpperCase();

  Widget _tabla(SiColors c, List<Map<String, dynamic>> filas) {
    if (filas.isEmpty) {
      return Center(
        child: Text('Nada con ese filtro', style: TextStyle(color: c.ink3)),
      );
    }
    // Solo desplazamiento HORIZONTAL. El vertical lo pone la pantalla que contiene este bloque:
    // dos verticales anidados pelean por el gesto y gana el de dentro, que es justo lo que no se
    // quiere cuando la tabla es lo ultimo de una pagina larga.
    //
    // A lo ancho si desborda -once columnas- y por eso rueda en su propio contenedor, para que la
    // pagina nunca se mueva de lado.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.only(bottom: SiSpace.x2),
        child: DataTable(
          headingRowHeight: 38,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 46,
          columnSpacing: 22,
          headingTextStyle: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: c.ink3),
          dataTextStyle: TextStyle(fontSize: 12.5, color: c.ink),
          columns: [
            const DataColumn(label: Text('CLAVE')),
            DataColumn(label: Text(_titulo('depto', 'Depto'))),
            if (_haySector) DataColumn(label: Text(_titulo('sector', 'Sector'))),
            DataColumn(label: Text(_titulo('torre', 'Torre'))),
            DataColumn(label: Text(_titulo('nivel', 'Nivel'))),
            DataColumn(label: Text(_titulo('tipologia', 'Tipología'))),
            const DataColumn(label: Text('VISTA')),
            const DataColumn(label: Text('M² TOTAL'), numeric: true),
            const DataColumn(label: Text('PRECIO'), numeric: true),
            const DataColumn(label: Text('\$/M²'), numeric: true),
            const DataColumn(label: Text('ESTATUS')),
            const DataColumn(label: Text('')),
          ],
          rows: filas.map((u) {
            return DataRow(cells: [
              DataCell(Text((u['numero'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              DataCell(Text((u['depto'] ?? '—').toString())),
              if (_haySector) DataCell(Text((u['sector'] ?? '—').toString())),
              DataCell(Text((u['torre'] ?? '—').toString())),
              DataCell(Text((u['nivel'] ?? '—').toString())),
              DataCell(Text((u['tipologia'] ?? '—').toString())),
              DataCell(Text((u['vista'] ?? '—').toString())),
              DataCell(Text(metros(u['m2_total']))),
              DataCell(Text(dinero(u['precio']),
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              DataCell(Text(dinero(u['precio_m2']),
                  style: TextStyle(color: c.ink3))),
              DataCell(_etiquetaEstatus(c, (u['estatus'] ?? '').toString())),
              DataCell(widget.puedeEditar
                  ? IconButton(
                      icon: Icon(Icons.edit_outlined, size: 16, color: c.ink3),
                      tooltip: 'Editar',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _editarUnidad(u),
                    )
                  : const SizedBox.shrink()),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _etiquetaEstatus(SiColors c, String estatus) {
    final color = switch (estatus) {
      'DISPONIBLE' => c.success,
      'APARTADO' => c.warn,
      'VENDIDO' => c.danger,
      _ => c.ink3,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: SiRadius.rSm,
      ),
      child: Text(_bonito(estatus).replaceAll('Disponibles', 'Disponible'),
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  // ── Editar una unidad ──────────────────────────────────────────────────────

  Future<void> _editarUnidad(Map<String, dynamic> u) async {
    final precio = TextEditingController(text: (u['precio'] ?? '').toString());
    final notas = TextEditingController(text: (u['notas'] ?? '').toString());
    var estatus = (u['estatus'] ?? 'DISPONIBLE').toString();

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = SiColors.of(ctx);
        return StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: Text('${u['numero']} · ${u['depto'] ?? ''}',
                style: const TextStyle(fontSize: 16)),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${u['tipologia'] ?? ''} · ${u['torre'] ?? ''} '
                    '${u['nivel'] ?? ''} · ${metros(u['m2_total'])}',
                    style: TextStyle(fontSize: 12.5, color: c.ink3),
                  ),
                  const SizedBox(height: SiSpace.x4),
                  DropdownButtonFormField<String>(
                    initialValue: estatus,
                    decoration: const InputDecoration(
                        labelText: 'Estatus', isDense: true),
                    items: estatuses
                        .map((e) => DropdownMenuItem(
                            value: e,
                            child: Text(_bonito(e)
                                .replaceAll('Disponibles', 'Disponible')
                                .replaceAll('Apartadas', 'Apartada')
                                .replaceAll('Vendidas', 'Vendida'))))
                        .toList(),
                    onChanged: (v) => setD(() => estatus = v ?? estatus),
                  ),
                  const SizedBox(height: SiSpace.x4),
                  TextField(
                    controller: precio,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Precio', isDense: true, prefixText: '\$ '),
                  ),
                  const SizedBox(height: SiSpace.x4),
                  TextField(
                    controller: notas,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Notas', isDense: true),
                  ),
                  const SizedBox(height: SiSpace.x3),
                  Text(
                    'Los metros y el precio por m² no se editan aquí: los calcula la base a '
                    'partir de las superficies de la lista.',
                    style: TextStyle(fontSize: 11, color: c.ink3, height: 1.4),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Guardar')),
            ],
          );
        });
      },
    );

    if (guardar != true) return;
    try {
      await _supabase.from('unidades').update({
        'estatus': estatus,
        'precio': double.tryParse(precio.text.replaceAll(RegExp(r'[^0-9.]'), '')),
        'notas': notas.text.trim().isEmpty ? null : notas.text.trim(),
        'actualizado_por': _supabase.auth.currentUser?.id,
      }).eq('id', u['id']);
      _aviso('${u['numero']} actualizada');
      await _cargar();
      widget.onCambio?.call();
    } catch (e) {
      _aviso('No se pudo guardar: $e', error: true);
    }
  }

  // ── Pegar la lista del mes ─────────────────────────────────────────────────

  Future<void> _pegarLista() async {
    final texto = TextEditingController();
    var listaAl = DateTime.now();

    final resultado = await showDialog<ResultadoPegado>(
      context: context,
      builder: (ctx) {
        final c = SiColors.of(ctx);
        return StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: const Text('Pegar la lista del Excel',
                style: TextStyle(fontSize: 16)),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Selecciona las filas en Excel —con el encabezado, si puedes— y pégalas aquí. '
                    'Antes de guardar nada te muestro qué cambia.',
                    style: TextStyle(fontSize: 12.5, color: c.ink3, height: 1.4),
                  ),
                  const SizedBox(height: SiSpace.x4),
                  TextField(
                    controller: texto,
                    maxLines: 10,
                    minLines: 6,
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'Torre\tNivel\tTipo\t…',
                      border: OutlineInputBorder(borderRadius: SiRadius.rSm),
                    ),
                  ),
                  const SizedBox(height: SiSpace.x4),
                  Row(
                    children: [
                      Text('Fecha de la lista:',
                          style: TextStyle(fontSize: 12.5, color: c.ink3)),
                      const SizedBox(width: SiSpace.x3),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 14),
                        label: Text(
                            '${listaAl.day}/${listaAl.month}/${listaAl.year}',
                            style: const TextStyle(fontSize: 12.5)),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: listaAl,
                            firstDate: DateTime(2024),
                            lastDate: DateTime.now().add(const Duration(days: 60)),
                          );
                          if (d != null) setD(() => listaAl = d);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: SiSpace.x2),
                  Text(
                    'Es la fecha del archivo, no la de hoy. Sin ella, un precio de hace cinco '
                    'meses se ve igual que uno de ayer.',
                    style: TextStyle(fontSize: 11, color: c.ink3, height: 1.4),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, leerPegado(texto.text)),
                child: const Text('Revisar'),
              ),
            ],
          );
        });
      },
    );

    if (resultado == null || !mounted) return;
    if (resultado.vacio && resultado.errores.isNotEmpty) {
      _aviso(resultado.errores.first.motivo, error: true);
      return;
    }
    if (resultado.vacio) {
      _aviso('No se leyó ninguna unidad', error: true);
      return;
    }
    await _confirmar(resultado, listaAl);
  }

  /// La vista previa. Es la decisión que se tomó a propósito: la lista sólo trae las disponibles,
  /// así que una unidad ausente normalmente está vendida —pero también puede faltar porque alguien
  /// copió mal el rango. Marcar sin preguntar convertiría un error de copiado en inventario perdido.
  Future<void> _confirmar(ResultadoPegado r, DateTime listaAl) async {
    final cmp = compararInventario(r.unidades, _unidades);
    var marcarDesaparecidas = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = SiColors.of(ctx);
        return StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: const Text('Qué va a cambiar', style: TextStyle(fontSize: 16)),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Se leyeron ${r.unidades.length} unidades'
                        '${r.traiaEncabezado ? " (con encabezado)" : " (sin encabezado, se usó el orden del archivo)"}.',
                        style: TextStyle(fontSize: 12.5, color: c.ink3)),
                    if (r.claveCompuestaDe.isNotEmpty) ...[
                      const SizedBox(height: SiSpace.x2),
                      Text(
                          'La lista no trae una columna de clave propia, así que cada unidad se '
                          'identifica por ${r.claveCompuestaDe} — la combinación más corta que no '
                          'se repite en tu lista. Ejemplo: «${r.unidades.first.numero}».',
                          style: TextStyle(fontSize: 11.5, color: c.ink3, height: 1.4)),
                    ],
                    if (r.columnasIgnoradas.isNotEmpty) ...[
                      const SizedBox(height: SiSpace.x2),
                      Text('Columnas que no se reconocieron y NO se guardan: '
                          '${r.columnasIgnoradas.join(", ")}',
                          style: TextStyle(fontSize: 11.5, color: c.warn)),
                    ],
                    const SizedBox(height: SiSpace.x4),
                    _linea(c, 'Nuevas', cmp.nuevas.length, c.success,
                        cmp.nuevas.take(8).map((u) => u.numero).join(', ')),
                    _linea(
                        c,
                        'Cambian de precio',
                        cmp.cambiosDePrecio.length,
                        c.warn,
                        cmp.cambiosDePrecio
                            .take(6)
                            .map((x) =>
                                '${x.numero}: ${dinero(x.anterior)} → ${dinero(x.nuevo)}')
                            .join('  ·  ')),
                    _linea(c, 'Cambian otros datos', cmp.cambiosDeDatos.length,
                        c.brand, cmp.cambiosDeDatos.take(8).map((u) => u.numero).join(', ')),
                    _linea(c, 'Sin cambio', cmp.sinCambio, c.ink3, ''),
                    if (cmp.desaparecidas.isNotEmpty) ...[
                      const Divider(height: SiSpace.x6),
                      Text(
                          '${cmp.desaparecidas.length} unidades que hoy figuran disponibles '
                          'YA NO vienen en la lista:',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: c.ink)),
                      const SizedBox(height: 4),
                      Text(
                          cmp.desaparecidas
                              .map((u) => u['numero'].toString())
                              .join(', '),
                          style: TextStyle(fontSize: 11.5, color: c.ink3)),
                      const SizedBox(height: SiSpace.x2),
                      CheckboxListTile(
                        value: marcarDesaparecidas,
                        onChanged: (v) =>
                            setD(() => marcarDesaparecidas = v ?? true),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Marcarlas como NO DISPONIBLE',
                            style: TextStyle(fontSize: 12.5)),
                        subtitle: Text(
                            'No se borran: se conservan con su historia y dejan de aparecerle a '
                            'SOL. Si crees que faltan por un error de copiado, desmárcalo.',
                            style: TextStyle(fontSize: 11, color: c.ink3, height: 1.4)),
                      ),
                    ],
                    if (r.errores.isNotEmpty) ...[
                      const Divider(height: SiSpace.x6),
                      Text('${r.errores.length} filas se van a omitir:',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: c.danger)),
                      const SizedBox(height: 4),
                      for (final e in r.errores.take(10))
                        Text('  línea ${e.linea}: ${e.motivo}',
                            style: TextStyle(fontSize: 11.5, color: c.ink3)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar')),
              FilledButton(
                onPressed: cmp.sinNovedades && r.errores.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: Text(cmp.sinNovedades ? 'Nada que guardar' : 'Guardar'),
              ),
            ],
          );
        });
      },
    );

    if (ok != true) return;
    await _guardar(r, cmp, listaAl, marcarDesaparecidas);
  }

  Widget _linea(SiColors c, String etiqueta, int n, Color color, String detalle) {
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: SiSpace.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: SiSpace.x2),
            Text('$etiqueta: $n',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: c.ink)),
          ]),
          if (detalle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Text(detalle,
                  style: TextStyle(fontSize: 11.5, color: c.ink3, height: 1.4)),
            ),
        ],
      ),
    );
  }

  Future<void> _guardar(
    ResultadoPegado r,
    Comparacion cmp,
    DateTime listaAl,
    bool marcarDesaparecidas,
  ) async {
    try {
      final usuario = _supabase.auth.currentUser?.id;
      // `aFila` ya trae el estatus que decia la lista -DISPONIBLE si no traia columna-, asi que
      // aqui no se fuerza ninguno. Antes se escribia DISPONIBLE a todas, y una lista que marcara
      // VENDIDO habria acabado ofreciendo unidades vendidas.
      final filas = r.unidades
          .map((u) => {
                ...u.aFila(widget.desarrolloId, listaAl: listaAl),
                'actualizado_por': usuario,
              })
          .toList();

      // Un solo upsert para las 38: `onConflict` sobre la restricción de unicidad, así que una
      // unidad que ya existe se actualiza y una nueva se inserta, sin tener que preguntar antes
      // cuál es cuál. Las columnas que no van en el payload —`notas`— se conservan.
      await _supabase
          .from('unidades')
          .upsert(filas, onConflict: 'desarrollo_id,numero');

      if (marcarDesaparecidas && cmp.desaparecidas.isNotEmpty) {
        // NO_DISPONIBLE y no VENDIDO: sabemos que salió de la lista, no sabemos si se apartó o se
        // vendió. Escribir «vendido» sería inventar un dato que nadie dijo.
        await _supabase
            .from('unidades')
            .update({'estatus': 'NO_DISPONIBLE', 'actualizado_por': usuario})
            .inFilter('id', cmp.desaparecidas.map((u) => u['id']).toList());
      }

      // Las etiquetas que dijo el encabezado. Se MEZCLAN con las que ya había: si el Excel del mes
      // siguiente trae una columna menos, la etiqueta de la que falta no tiene por qué borrarse.
      if (r.etiquetas.isNotEmpty) {
        final mezcla = {..._etiquetas, ...r.etiquetas};
        await _supabase
            .from('desarrollos')
            .update({'etiquetas': mezcla}).eq('id', widget.desarrolloId);
      }

      // Y las columnas que aparecieron sin campo donde guardarse, con un ejemplo.
      //
      // No se crean columnas por si acaso: se registra lo que de verdad apareció, y cuando una se
      // repita en varios desarrollos se crea con evidencia. Se pidió así —«ir viendo un global»—.
      for (final col in r.columnasIgnoradas) {
        final ya = await _supabase
            .from('columnas_sin_mapear')
            .select('id,veces')
            .eq('desarrollo_id', widget.desarrolloId)
            .eq('columna', col)
            .maybeSingle();
        if (ya == null) {
          await _supabase.from('columnas_sin_mapear').insert({
            'desarrollo_id': widget.desarrolloId,
            'columna': col,
            'ejemplo': r.ejemplosIgnorados[col],
          });
        } else {
          await _supabase.from('columnas_sin_mapear').update({
            'veces': (int.tryParse('${ya['veces']}') ?? 1) + 1,
            'ejemplo': r.ejemplosIgnorados[col],
            'ultima_vez': DateTime.now().toIso8601String(),
          }).eq('id', ya['id']);
        }
      }

      final partes = <String>[
        '${r.unidades.length} unidades guardadas',
        if (cmp.nuevas.isNotEmpty) '${cmp.nuevas.length} nuevas',
        if (cmp.cambiosDePrecio.isNotEmpty)
          '${cmp.cambiosDePrecio.length} con precio nuevo',
        if (marcarDesaparecidas && cmp.desaparecidas.isNotEmpty)
          '${cmp.desaparecidas.length} marcadas no disponibles',
      ];
      _aviso(partes.join(' · '));
      await _cargar();
      widget.onCambio?.call();
    } catch (e) {
      _aviso('No se pudo guardar: $e', error: true);
    }
  }
}
