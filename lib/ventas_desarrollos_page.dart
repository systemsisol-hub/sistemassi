import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/file_saver_util.dart';
import 'services/ventas_datos.dart';
import 'theme/si_theme.dart';
import 'ventas_comun.dart';

/// Lo que Sisol sabe de cada desarrollo: sus datos, su inventario, sus brochures y la información
/// adicional que se le escribe a mano.
///
/// Es un catálogo APARTE del de SOL (`ventas_desarrollos`, no `desarrollos`). Decidido el
/// 24/09/2026: Sisol tiene más desarrollos y va a tener reglas propias, y un cambio pensado para el
/// asistente interno no debe cambiar lo que se le dice a un cliente.
///
/// Lista y detalle en la misma pantalla, con las secciones apiladas y no en pestañas: el mismo
/// criterio que el usuario pidió para el panel de SOL el 03/09/2026 —son caras del mismo desarrollo
/// y separarlas obliga a entrar y salir—.
class VentasDesarrollosPage extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;
  const VentasDesarrollosPage({super.key, required this.role, required this.permissions});

  @override
  State<VentasDesarrollosPage> createState() => _VentasDesarrollosPageState();
}

/// El renglón de la lista que no es un desarrollo: el conocimiento que aplica a todos.
const _general = '_general';

class _VentasDesarrollosPageState extends State<VentasDesarrollosPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _desarrollos = [];
  Map<String, int> _disponibles = {};
  bool _cargando = true;
  String _busqueda = '';
  String? _elegido;

  bool get _puedeEditar => puedeEditarVentas(widget.role, widget.permissions);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final des = await _supabase
          .from('ventas_desarrollos')
          .select()
          .order('estado', ascending: true)
          .order('municipio', ascending: true)
          .order('nombre', ascending: true);
      final uni = await _supabase
          .from('ventas_unidades')
          .select('desarrollo_id')
          .eq('estatus', 'DISPONIBLE');
      final disp = <String, int>{};
      for (final u in uni as List) {
        final id = '${u['desarrollo_id']}';
        disp[id] = (disp[id] ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() {
        _desarrollos = [for (final d in des as List) Map<String, dynamic>.from(d)];
        _disponibles = disp;
      });
    } catch (e) {
      debugPrint('Error cargando desarrollos de ventas: $e');
      if (mounted) avisoVentas(context, 'No se pudieron cargar los desarrollos: $e', error: true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<Map<String, dynamic>> get _vistos {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return _desarrollos;
    return _desarrollos
        .where((d) => '${d['nombre']} ${d['estado']} ${d['municipio']}'.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    if (_cargando && _desarrollos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final vistos = _vistos;
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          BarraVentas(
            pista: 'Buscar desarrollo',
            onBuscar: (v) => setState(() => _busqueda = v),
            acciones: [
              if (_puedeEditar)
                FilledButton.icon(
                  onPressed: () => _formDesarrollo(null),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Nuevo desarrollo'),
                ),
              IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh, size: 18), tooltip: 'Actualizar'),
            ],
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, caja) {
              final ancho = caja.maxWidth >= 900;
              final elegido = _elegido ?? (ancho && vistos.isNotEmpty ? '${vistos.first['id']}' : null);
              if (!ancho) {
                if (elegido == null) return _lista(c, vistos, null);
                return Column(children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _elegido = null),
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Todos los desarrollos'),
                    ),
                  ),
                  Expanded(child: _detalle(c, elegido)),
                ]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 300, child: _lista(c, vistos, elegido)),
                  Container(width: 1, color: c.line),
                  Expanded(child: elegido == null ? const SizedBox.shrink() : _detalle(c, elegido)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _lista(SiColors c, List<Map<String, dynamic>> vistos, String? elegido) {
    String? estadoPrevio;
    final hijos = <Widget>[
      _renglon(c, _general, 'Conocimiento general', 'Aplica a todos los desarrollos',
          activo: elegido == _general, icono: Icons.library_books_outlined),
    ];
    for (final d in vistos) {
      final estado = '${d['estado']}';
      if (estado != estadoPrevio) {
        estadoPrevio = estado;
        hijos.add(Padding(
          padding: const EdgeInsets.fromLTRB(SiSpace.x4, SiSpace.x4, SiSpace.x4, SiSpace.x1),
          child: Text(estado.toUpperCase(),
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.ink4, letterSpacing: .6)),
        ));
      }
      final id = '${d['id']}';
      final n = _disponibles[id] ?? 0;
      hijos.add(_renglon(
        c,
        id,
        '${d['nombre']}',
        '${d['municipio']} · ${n > 0 ? '$n disponibles' : 'sin inventario'}',
        activo: elegido == id,
        inactivo: d['is_active'] != true,
      ));
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: SiSpace.x2), children: hijos);
  }

  Widget _renglon(SiColors c, String id, String titulo, String sub,
      {required bool activo, bool inactivo = false, IconData? icono}) {
    return InkWell(
      onTap: () => setState(() => _elegido = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: SiSpace.x4, vertical: SiSpace.x3),
        decoration: BoxDecoration(
          color: activo ? c.brandTint : null,
          border: Border(left: BorderSide(color: activo ? c.brand : Colors.transparent, width: 3)),
        ),
        child: Row(children: [
          if (icono != null) ...[Icon(icono, size: 16, color: c.ink3), const SizedBox(width: SiSpace.x2)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: activo ? FontWeight.w700 : FontWeight.w600,
                      color: inactivo ? c.ink3 : c.ink)),
              Text(inactivo ? '$sub · inactivo' : sub, style: TextStyle(fontSize: 11, color: c.ink3)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _detalle(SiColors c, String id) {
    if (id == _general) {
      return ListView(
        key: const ValueKey('detalle-general'),
        padding: const EdgeInsets.all(SiSpace.x5),
        children: [
          const Text('Conocimiento general', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: SiSpace.x1),
          Text('Lo que Sisol debe saber de SI SOL en general (financiamiento, proceso de compra…). '
              'Tiene prioridad sobre la base de conocimiento de los PDF.',
              style: TextStyle(fontSize: 12.5, color: c.ink3)),
          const SizedBox(height: SiSpace.x4),
          _Conocimiento(key: const ValueKey('con-general'), desarrolloId: null, puedeEditar: _puedeEditar),
        ],
      );
    }
    final d = _desarrollos.where((x) => '${x['id']}' == id).firstOrNull;
    if (d == null) return const SizedBox.shrink();
    return ListView(
      key: ValueKey('detalle-$id'),
      padding: const EdgeInsets.all(SiSpace.x5),
      children: [
        _datos(c, d),
        Divider(height: SiSpace.x8, color: c.line),
        _Brochures(key: ValueKey('bro-$id'), desarrollo: d, puedeEditar: _puedeEditar, onCambio: _cargar),
        Divider(height: SiSpace.x8, color: c.line),
        _Conocimiento(key: ValueKey('con-$id'), desarrolloId: id, puedeEditar: _puedeEditar),
        Divider(height: SiSpace.x8, color: c.line),
        // El inventario va al final: es lo único que mide decenas de renglones.
        _Inventario(key: ValueKey('inv-$id'), desarrollo: d, puedeEditar: _puedeEditar, onCambio: _cargar),
      ],
    );
  }

  Widget _datos(SiColors c, Map<String, dynamic> d) {
    final alias = List<String>.from(d['alias'] ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text('${d['nombre']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          if (d['is_active'] != true) etiquetaVentas(c, 'Inactivo: Sisol no lo menciona', c.warn),
          if (_puedeEditar) ...[
            const SizedBox(width: SiSpace.x2),
            OutlinedButton.icon(
              onPressed: () => _formDesarrollo(d),
              icon: const Icon(Icons.edit_outlined, size: 15),
              label: const Text('Editar'),
            ),
          ],
        ]),
        const SizedBox(height: SiSpace.x1),
        Text('${d['municipio']}, ${d['estado']}', style: TextStyle(color: c.ink2)),
        const SizedBox(height: SiSpace.x3),
        if (d['url_pagina'] != null)
          InkWell(
            onTap: () => abrirUrl('${d['url_pagina']}'),
            child: Text('${d['url_pagina']}', style: TextStyle(color: c.brand, fontSize: 12.5)),
          ),
        if (alias.isNotEmpty) ...[
          const SizedBox(height: SiSpace.x2),
          Text('Lo reconoce también como: ${alias.join(', ')}', style: TextStyle(fontSize: 12, color: c.ink3)),
        ],
      ],
    );
  }

  Future<void> _formDesarrollo(Map<String, dynamic>? d) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => _FormDesarrollo(desarrollo: d),
    );
    if (guardado == true) await _cargar();
  }
}

// ── Formulario del desarrollo ────────────────────────────────────────────────

class _FormDesarrollo extends StatefulWidget {
  final Map<String, dynamic>? desarrollo;
  const _FormDesarrollo({this.desarrollo});

  @override
  State<_FormDesarrollo> createState() => _FormDesarrolloState();
}

class _FormDesarrolloState extends State<_FormDesarrollo> {
  late final _estado = TextEditingController(text: widget.desarrollo?['estado'] ?? '');
  late final _municipio = TextEditingController(text: widget.desarrollo?['municipio'] ?? '');
  late final _nombre = TextEditingController(text: widget.desarrollo?['nombre'] ?? '');
  late final _url = TextEditingController(text: widget.desarrollo?['url_pagina'] ?? '');
  late final _alias =
      TextEditingController(text: List<String>.from(widget.desarrollo?['alias'] ?? []).join(', '));
  late bool _activo = widget.desarrollo?['is_active'] ?? true;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    for (final t in [_estado, _municipio, _nombre, _url, _alias]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty || _estado.text.trim().isEmpty || _municipio.text.trim().isEmpty) {
      setState(() => _error = 'Estado, municipio y nombre son obligatorios.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final fila = {
      'estado': _estado.text.trim(),
      'municipio': _municipio.text.trim(),
      'nombre': nombre,
      'url_pagina': _url.text.trim().isEmpty ? null : _url.text.trim(),
      'alias': _alias.text.split(',').map((a) => a.trim().toLowerCase()).where((a) => a.isNotEmpty).toList(),
      'is_active': _activo,
    };
    try {
      final sb = Supabase.instance.client.from('ventas_desarrollos');
      if (widget.desarrollo == null) {
        // El slug se fija al crear: nombra los brochures y la página, y cambiarlo después dejaría
        // huérfanos los archivos que ya se subieron.
        await sb.insert({...fila, 'slug': slugDe(nombre)});
      } else {
        await sb.update(fila).eq('id', widget.desarrollo!['id']);
      }
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      setState(() => _error = e.code == '23505' ? 'Ya existe un desarrollo con ese nombre.' : e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    Widget campo(TextEditingController t, String etiqueta, {String? ayuda}) => Padding(
          padding: const EdgeInsets.only(bottom: SiSpace.x3),
          child: TextField(
            controller: t,
            decoration: InputDecoration(
              labelText: etiqueta,
              helperText: ayuda,
              border: const OutlineInputBorder(borderRadius: SiRadius.rMd),
            ),
          ),
        );
    return AlertDialog(
      title: Text(widget.desarrollo == null ? 'Nuevo desarrollo' : 'Editar ${widget.desarrollo!['nombre']}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            campo(_estado, 'Estado'),
            campo(_municipio, 'Municipio'),
            campo(_nombre, 'Nombre'),
            campo(_url, 'Página en sisol.com.mx', ayuda: 'Se abre en la tarjeta que muestra el chat.'),
            campo(_alias, 'Otros nombres',
                ayuda: 'Separados por coma. Cómo lo escriben los clientes, p. ej. «pp, punta».'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _activo,
              onChanged: (v) => setState(() => _activo = v),
              title: const Text('Activo'),
              subtitle: const Text('Si está inactivo, Sisol no lo ofrece ni cita su inventario.'),
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: c.danger)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardando ? null : _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

Widget _tituloSeccion(SiColors c, String texto, IconData icono, {List<Widget> acciones = const []}) {
  return Row(children: [
    Icon(icono, size: 14, color: c.ink3),
    const SizedBox(width: SiSpace.x2),
    Expanded(
      child: Text(texto,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.ink3, letterSpacing: .6)),
    ),
    ...acciones,
  ]);
}

// ── Brochures ────────────────────────────────────────────────────────────────

class _Brochures extends StatefulWidget {
  final Map<String, dynamic> desarrollo;
  final bool puedeEditar;
  final VoidCallback onCambio;
  const _Brochures({super.key, required this.desarrollo, required this.puedeEditar, required this.onCambio});

  @override
  State<_Brochures> createState() => _BrochuresState();
}

class _BrochuresState extends State<_Brochures> {
  String? _subiendo;

  Future<void> _subir(String idioma) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    final bytes = r?.files.single.bytes;
    if (bytes == null) return;
    final archivo = '${widget.desarrollo['slug']}-$idioma.pdf';
    setState(() => _subiendo = idioma);
    try {
      final sb = Supabase.instance.client;
      await sb.storage.from('ventas-brochures').uploadBinary(
            archivo,
            bytes,
            fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
          );
      await sb.from('ventas_desarrollos').update({'brochure_$idioma': archivo}).eq('id', widget.desarrollo['id']);
      if (mounted) avisoVentas(context, 'Brochure subido. Sisol ya lo ofrece en el chat.');
      widget.onCambio();
    } catch (e) {
      if (mounted) avisoVentas(context, 'No se pudo subir: $e', error: true);
    } finally {
      if (mounted) setState(() => _subiendo = null);
    }
  }

  Future<void> _quitar(String idioma) async {
    final archivo = widget.desarrollo['brochure_$idioma'] as String?;
    if (archivo == null) return;
    try {
      final sb = Supabase.instance.client;
      await sb.from('ventas_desarrollos').update({'brochure_$idioma': null}).eq('id', widget.desarrollo['id']);
      await sb.storage.from('ventas-brochures').remove([archivo]);
      widget.onCambio();
    } catch (e) {
      if (mounted) avisoVentas(context, 'No se pudo quitar: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    Widget ranura(String idioma, String etiqueta) {
      final archivo = widget.desarrollo['brochure_$idioma'] as String?;
      return Container(
        width: 300,
        padding: const EdgeInsets.all(SiSpace.x3),
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: SiRadius.rLg,
          border: Border.all(color: c.line),
        ),
        child: Row(children: [
          etiquetaVentas(c, idioma.toUpperCase(), c.brand),
          const SizedBox(width: SiSpace.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(etiqueta, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text(archivo ?? 'Sin archivo', style: TextStyle(fontSize: 11.5, color: c.ink3)),
            ]),
          ),
          if (archivo != null)
            IconButton(
              onPressed: () => abrirUrl('$urlSisol/brochures/$archivo'),
              icon: const Icon(Icons.visibility_outlined, size: 17),
              tooltip: 'Ver',
            ),
          if (widget.puedeEditar)
            _subiendo == idioma
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    onPressed: () => _subir(idioma),
                    icon: const Icon(Icons.upload_file, size: 17),
                    tooltip: archivo == null ? 'Subir PDF' : 'Reemplazar PDF',
                  ),
          if (widget.puedeEditar && archivo != null)
            IconButton(
              onPressed: () => _quitar(idioma),
              icon: Icon(Icons.delete_outline, size: 17, color: c.danger),
              tooltip: 'Quitar',
            ),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _tituloSeccion(c, 'BROCHURES', Icons.description_outlined),
      const SizedBox(height: SiSpace.x1),
      Text('El chat ofrece el del idioma del cliente; si solo hay uno, ofrece ese.',
          style: TextStyle(fontSize: 12, color: c.ink3)),
      const SizedBox(height: SiSpace.x3),
      Wrap(spacing: SiSpace.x3, runSpacing: SiSpace.x3, children: [
        ranura('es', 'Español'),
        ranura('en', 'Inglés'),
      ]),
    ]);
  }
}

// ── Conocimiento adicional ───────────────────────────────────────────────────

class _Conocimiento extends StatefulWidget {
  final String? desarrolloId;
  final bool puedeEditar;
  const _Conocimiento({super.key, required this.desarrolloId, required this.puedeEditar});

  @override
  State<_Conocimiento> createState() => _ConocimientoState();
}

class _ConocimientoState extends State<_Conocimiento> {
  List<Map<String, dynamic>> _fragmentos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final q = Supabase.instance.client.from('ventas_conocimiento').select();
      final r = widget.desarrolloId == null
          ? await q.isFilter('desarrollo_id', null).order('created_at', ascending: true)
          : await q.eq('desarrollo_id', widget.desarrolloId!).order('created_at', ascending: true);
      if (!mounted) return;
      setState(() => _fragmentos = [for (final f in r as List) Map<String, dynamic>.from(f)]);
    } catch (e) {
      debugPrint('Error cargando conocimiento: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _editar(Map<String, dynamic>? f) async {
    final titulo = TextEditingController(text: f?['titulo'] ?? '');
    final contenido = TextEditingController(text: f?['contenido'] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(f == null ? 'Nuevo fragmento' : 'Editar fragmento'),
        content: SizedBox(
          width: 620,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: titulo,
              decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder()),
            ),
            const SizedBox(height: SiSpace.x3),
            TextField(
              controller: contenido,
              minLines: 8,
              maxLines: 18,
              decoration: const InputDecoration(
                labelText: 'Contenido',
                alignLabelWithHint: true,
                helperText: 'Sisol lo lee tal cual. Precios y disponibilidad van en el inventario, no aquí.',
                border: OutlineInputBorder(),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    final t = titulo.text.trim(), co = contenido.text.trim();
    titulo.dispose();
    contenido.dispose();
    if (ok != true) return;
    if (t.isEmpty || co.isEmpty) {
      if (mounted) avisoVentas(context, 'Título y contenido son obligatorios.', error: true);
      return;
    }
    try {
      final sb = Supabase.instance.client.from('ventas_conocimiento');
      if (f == null) {
        await sb.insert({'desarrollo_id': widget.desarrolloId, 'titulo': t, 'contenido': co});
      } else {
        await sb.update({'titulo': t, 'contenido': co}).eq('id', f['id']);
      }
      await _cargar();
    } catch (e) {
      if (mounted) avisoVentas(context, 'No se pudo guardar: $e', error: true);
    }
  }

  Future<void> _activar(Map<String, dynamic> f, bool v) async {
    try {
      await Supabase.instance.client.from('ventas_conocimiento').update({'is_active': v}).eq('id', f['id']);
      await _cargar();
    } catch (e) {
      if (mounted) avisoVentas(context, 'No se pudo cambiar: $e', error: true);
    }
  }

  Future<void> _borrar(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar fragmento'),
        content: Text('«${f['titulo']}» se borra para siempre. Si solo quieres que Sisol deje de usarlo, desactívalo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.from('ventas_conocimiento').delete().eq('id', f['id']);
      await _cargar();
    } catch (e) {
      if (mounted) avisoVentas(context, 'No se pudo borrar: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _tituloSeccion(c, 'INFORMACIÓN ADICIONAL', Icons.library_books_outlined, acciones: [
        if (widget.puedeEditar)
          TextButton.icon(
            onPressed: () => _editar(null),
            icon: const Icon(Icons.add, size: 15),
            label: const Text('Nuevo fragmento'),
          ),
      ]),
      const SizedBox(height: SiSpace.x3),
      if (_cargando)
        const LinearProgressIndicator()
      else if (_fragmentos.isEmpty)
        Text('Sin información adicional.', style: TextStyle(fontSize: 12.5, color: c.ink3))
      else
        for (final f in _fragmentos)
          Container(
            margin: const EdgeInsets.only(bottom: SiSpace.x2),
            padding: const EdgeInsets.all(SiSpace.x3),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: SiRadius.rLg,
              border: Border.all(color: c.line),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${f['titulo']}',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: f['is_active'] == true ? c.ink : c.ink3)),
                  const SizedBox(height: 2),
                  Text('${f['contenido']}',
                      maxLines: 3, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.ink2)),
                ]),
              ),
              if (widget.puedeEditar) ...[
                Switch(value: f['is_active'] == true, onChanged: (v) => _activar(f, v)),
                IconButton(onPressed: () => _editar(f), icon: const Icon(Icons.edit_outlined, size: 16), tooltip: 'Editar'),
                IconButton(
                    onPressed: () => _borrar(f),
                    icon: Icon(Icons.delete_outline, size: 16, color: c.danger),
                    tooltip: 'Borrar'),
              ] else if (f['is_active'] != true)
                etiquetaVentas(c, 'Inactivo', c.ink3),
            ]),
          ),
    ]);
  }
}

// ── Inventario ───────────────────────────────────────────────────────────────

class _Inventario extends StatefulWidget {
  final Map<String, dynamic> desarrollo;
  final bool puedeEditar;
  final VoidCallback onCambio;
  const _Inventario({super.key, required this.desarrollo, required this.puedeEditar, required this.onCambio});

  @override
  State<_Inventario> createState() => _InventarioState();
}

class _InventarioState extends State<_Inventario> {
  List<Map<String, dynamic>> _unidades = [];
  bool _cargando = true;

  String get _id => '${widget.desarrollo['id']}';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await Supabase.instance.client
          .from('ventas_unidades')
          .select()
          .eq('desarrollo_id', _id)
          .order('orden', ascending: true);
      if (!mounted) return;
      setState(() => _unidades = [for (final u in r as List) Map<String, dynamic>.from(u)]);
    } catch (e) {
      debugPrint('Error cargando unidades: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cambio() async {
    await _cargar();
    widget.onCambio();
  }

  Future<void> _descargarPlantilla() async {
    const csv = '﻿tipo,nivel,numero,area_int,area_ext,area_total,precio_mxn,precio_usd,fecha_escritura,estatus\r\n'
        '"Depa 2R","5","502","75","12","87","3500000","175000","Mar 2027","Disponible"\r\n';
    await FileSaverUtil.saveAndShare(
        Uint8List.fromList(utf8.encode(csv)), 'plantilla-inventario-${widget.desarrollo['slug']}.csv');
  }

  Future<void> _pegar() async {
    final texto = TextEditingController();
    PegadoVentas? leido;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = SiColors.of(ctx);
        return AlertDialog(
          title: Text('Cargar inventario de ${widget.desarrollo['nombre']}'),
          content: SizedBox(
            width: 720,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Copia la tabla de Excel CON su fila de títulos y pégala aquí. '
                  'Reemplaza TODO el inventario actual de este desarrollo (${_unidades.length} unidades).',
                  style: TextStyle(fontSize: 12.5, color: c.ink2)),
              const SizedBox(height: SiSpace.x3),
              TextField(
                controller: texto,
                minLines: 8,
                maxLines: 14,
                style: SiType.mono(size: 12),
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Tipo\tNivel\tNúmero\t…'),
                onChanged: (v) => set(() => leido = v.trim().isEmpty ? null : leerPegadoVentas(v)),
              ),
              const SizedBox(height: SiSpace.x3),
              if (leido != null) ...[
                Text('${leido!.filas.length} unidades listas para cargar.',
                    style: TextStyle(fontWeight: FontWeight.w600, color: leido!.filas.isEmpty ? c.danger : c.success)),
                if (leido!.ignoradas.isNotEmpty)
                  Text('Columnas que no se guardan: ${leido!.ignoradas.join(', ')}',
                      style: TextStyle(fontSize: 12, color: c.ink3)),
                for (final e in leido!.errores.take(6)) Text(e, style: TextStyle(fontSize: 12, color: c.danger)),
                if (leido!.errores.length > 6)
                  Text('…y ${leido!.errores.length - 6} avisos más.', style: TextStyle(fontSize: 12, color: c.danger)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: (leido?.filas.isNotEmpty ?? false) ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Reemplazar inventario'),
            ),
          ],
        );
      }),
    );
    texto.dispose();
    if (ok != true || leido == null) return;
    try {
      // En una transacción (ver la migración): o entran todas o el inventario no cambia.
      final n = await Supabase.instance.client.rpc('ventas_reemplazar_inventario', params: {
        'p_desarrollo': _id,
        'p_filas': leido!.filas,
      });
      if (mounted) avisoVentas(context, '$n unidades cargadas.');
      await _cambio();
    } catch (e) {
      if (mounted) avisoVentas(context, 'No se pudo cargar el inventario: $e', error: true);
      await _cargar();
    }
  }

  Future<void> _editar(Map<String, dynamic>? u) async {
    final fila = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FormUnidad(unidad: u),
    );
    if (fila == null) return;
    try {
      final sb = Supabase.instance.client.from('ventas_unidades');
      if (u == null) {
        final orden = _unidades.fold<int>(0, (m, x) => (x['orden'] as int? ?? 0) > m ? x['orden'] as int : m) + 1;
        await sb.insert({...fila, 'desarrollo_id': _id, 'orden': orden});
      } else {
        await sb.update(fila).eq('id', u['id']);
      }
      await _cambio();
    } catch (e) {
      if (mounted) avisoVentas(context, 'No se pudo guardar: $e', error: true);
    }
  }

  Future<void> _borrar(Map<String, dynamic> u) async {
    try {
      await Supabase.instance.client.from('ventas_unidades').delete().eq('id', u['id']);
      await _cambio();
    } catch (e) {
      if (mounted) avisoVentas(context, 'No se pudo borrar: $e', error: true);
    }
  }

  Color _colorEstatus(SiColors c, String e) => switch (e) {
        'DISPONIBLE' => c.success,
        'VENDIDO' => c.ink3,
        _ => c.warn,
      };

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    String cifra(dynamic v) => v == null ? '' : '${v is num && v == v.roundToDouble() ? v.round() : v}';
    final disponibles = _unidades.where((u) => u['estatus'] == 'DISPONIBLE').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _tituloSeccion(c, 'INVENTARIO · ${_unidades.length} unidades, $disponibles disponibles', Icons.inventory_2_outlined,
          acciones: [
            if (widget.puedeEditar) ...[
              TextButton.icon(onPressed: _pegar, icon: const Icon(Icons.content_paste, size: 15), label: const Text('Pegar desde Excel')),
              TextButton.icon(onPressed: () => _editar(null), icon: const Icon(Icons.add, size: 15), label: const Text('Unidad')),
            ],
            IconButton(onPressed: _descargarPlantilla, icon: const Icon(Icons.download, size: 16), tooltip: 'Plantilla CSV'),
          ]),
      const SizedBox(height: SiSpace.x1),
      Text('Es lo único de donde Sisol toma precios: lo que no esté aquí no lo cotiza.',
          style: TextStyle(fontSize: 12, color: c.ink3)),
      const SizedBox(height: SiSpace.x3),
      if (_cargando)
        const LinearProgressIndicator()
      else if (_unidades.isEmpty)
        Text('Sin inventario cargado.', style: TextStyle(fontSize: 12.5, color: c.ink3))
      else
        Container(
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: SiRadius.rLg,
            border: Border.all(color: c.line),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.ink2),
              dataTextStyle: TextStyle(fontSize: 12.5, color: c.ink),
              columnSpacing: 22,
              columns: [
                const DataColumn(label: Text('Tipo')),
                const DataColumn(label: Text('Nivel')),
                const DataColumn(label: Text('Número')),
                const DataColumn(label: Text('m² int.'), numeric: true),
                const DataColumn(label: Text('m² ext.'), numeric: true),
                const DataColumn(label: Text('m² total'), numeric: true),
                const DataColumn(label: Text('Precio MXN'), numeric: true),
                const DataColumn(label: Text('Precio USD'), numeric: true),
                const DataColumn(label: Text('Escritura')),
                const DataColumn(label: Text('Estatus')),
                if (widget.puedeEditar) const DataColumn(label: Text('')),
              ],
              rows: [
                for (final u in _unidades)
                  DataRow(cells: [
                    DataCell(Text('${u['tipo'] ?? ''}')),
                    DataCell(Text('${u['nivel'] ?? ''}')),
                    DataCell(Text('${u['numero'] ?? ''}', style: SiType.mono(size: 12))),
                    DataCell(Text(cifra(u['area_int']))),
                    DataCell(Text(cifra(u['area_ext']))),
                    DataCell(Text(cifra(u['area_total']))),
                    DataCell(Text(u['precio_mxn'] == null ? '' : dinero(u['precio_mxn']))),
                    DataCell(Text(u['precio_usd'] == null ? '' : dinero(u['precio_usd']))),
                    DataCell(Text('${u['fecha_escritura'] ?? ''}')),
                    DataCell(etiquetaVentas(c, estatusTexto['${u['estatus']}'] ?? '${u['estatus']}',
                        _colorEstatus(c, '${u['estatus']}'))),
                    if (widget.puedeEditar)
                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(onPressed: () => _editar(u), icon: const Icon(Icons.edit_outlined, size: 15), tooltip: 'Editar'),
                        IconButton(
                            onPressed: () => _borrar(u),
                            icon: Icon(Icons.delete_outline, size: 15, color: c.danger),
                            tooltip: 'Borrar'),
                      ])),
                  ]),
              ],
            ),
          ),
        ),
    ]);
  }
}

class _FormUnidad extends StatefulWidget {
  final Map<String, dynamic>? unidad;
  const _FormUnidad({this.unidad});

  @override
  State<_FormUnidad> createState() => _FormUnidadState();
}

class _FormUnidadState extends State<_FormUnidad> {
  static const _texto = ['tipo', 'nivel', 'numero', 'fecha_escritura'];
  static const _numeros = ['area_int', 'area_ext', 'area_total', 'precio_mxn', 'precio_usd'];
  static const _etiquetas = {
    'tipo': 'Tipo',
    'nivel': 'Nivel',
    'numero': 'Número',
    'fecha_escritura': 'Fecha de escritura',
    'area_int': 'm² interior',
    'area_ext': 'm² exterior',
    'area_total': 'm² total',
    'precio_mxn': 'Precio MXN',
    'precio_usd': 'Precio USD',
  };

  late final Map<String, TextEditingController> _c = {
    for (final k in [..._texto, ..._numeros])
      k: TextEditingController(text: widget.unidad?[k] == null ? '' : '${widget.unidad![k]}'),
  };
  late String _estatus = widget.unidad?['estatus'] ?? 'DISPONIBLE';

  @override
  void dispose() {
    for (final t in _c.values) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.unidad == null ? 'Nueva unidad' : 'Editar unidad'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Wrap(spacing: SiSpace.x3, runSpacing: SiSpace.x3, children: [
            for (final k in [..._texto, ..._numeros])
              SizedBox(
                width: 230,
                child: TextField(
                  controller: _c[k],
                  keyboardType: _numeros.contains(k) ? const TextInputType.numberWithOptions(decimal: true) : null,
                  decoration: InputDecoration(
                      labelText: _etiquetas[k], isDense: true, border: const OutlineInputBorder()),
                ),
              ),
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<String>(
                initialValue: _estatus,
                decoration: const InputDecoration(labelText: 'Estatus', isDense: true, border: OutlineInputBorder()),
                items: [
                  for (final e in estatusVentas) DropdownMenuItem(value: e, child: Text(estatusTexto[e]!)),
                ],
                onChanged: (v) => setState(() => _estatus = v ?? _estatus),
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            for (final k in _texto) k: _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim(),
            for (final k in _numeros) k: numeroDe(_c[k]!.text),
            'estatus': _estatus,
          }),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
