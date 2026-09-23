import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/correspondencia.dart';
import 'theme/si_theme.dart';

/// La pestaña de listas de distribución de Correspondencia.
///
/// Las listas se COMPARTEN entre quienes tienen el permiso —todo sale como «Comunicación SI SOL», así
/// que una lista que arma una persona la usan las otras dos—, y quién puede tocarlas lo decide RLS,
/// no esta pantalla.
///
/// Los datos los carga la página y se reciben aquí, porque la pestaña de redactar también los
/// necesita: dos copias cargadas por separado acabarían diciendo cosas distintas de la misma lista.
class ListasDistribucionTab extends StatelessWidget {
  final List<Map<String, dynamic>> listas;
  final List<Colaborador> colaboradores;
  final bool cargando;
  final Future<void> Function() alCambiar;

  const ListasDistribucionTab({
    super.key,
    required this.listas,
    required this.colaboradores,
    required this.cargando,
    required this.alCambiar,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: SiSpace.x6, vertical: SiSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                'Grupos de destinatarios para no tener que elegirlos uno por uno. Los compañeros se '
                'guardan por persona: si cambian de correo se actualiza solo, y quien se da de baja '
                'deja de recibir.',
                style: TextStyle(fontSize: 13, color: c.ink3),
              ),
            ),
            SizedBox(width: SiSpace.x4),
            FilledButton.icon(
              onPressed: () => _abrir(context, null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nueva lista'),
            ),
          ]),
          SizedBox(height: SiSpace.x4),
          if (cargando)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (listas.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                  child: Text('Todavía no hay listas.', style: TextStyle(color: c.ink3))),
            )
          else
            for (final l in listas) _tarjeta(context, c, l),
        ],
      ),
    );
  }

  Widget _tarjeta(BuildContext context, SiColors c, Map<String, dynamic> l) {
    final miembros = List<Map<String, dynamic>>.from(l['lista_miembros'] ?? const []);
    final r = correosDeLista(miembros);
    final descripcion = (l['descripcion'] ?? '').toString().trim();
    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: SiSpace.x3),
      shape: RoundedRectangleBorder(
          borderRadius: SiRadius.rLg, side: BorderSide(color: c.line)),
      child: ListTile(
        leading: Icon(Icons.groups_outlined, color: c.brand),
        title: Text((l['nombre'] ?? '').toString(),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([
          if (descripcion.isNotEmpty) descripcion,
          r.correos.length == 1 ? '1 destinatario' : '${r.correos.length} destinatarios',
          // Se dice para que se limpie la lista, no para alarmar: al enviar se saltan solos.
          if (r.omitidos > 0)
            r.omitidos == 1 ? '1 ya no está activo' : '${r.omitidos} ya no están activos',
        ].join(' · ')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _abrir(context, l),
          ),
          IconButton(
            tooltip: 'Borrar',
            icon: Icon(Icons.delete_outline, size: 20, color: c.danger),
            onPressed: () => _borrar(context, l),
          ),
        ]),
      ),
    );
  }

  Future<void> _abrir(BuildContext context, Map<String, dynamic>? lista) async {
    final guardada = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogoLista(lista: lista, colaboradores: colaboradores),
    );
    if (guardada == true) await alCambiar();
  }

  Future<void> _borrar(BuildContext context, Map<String, dynamic> l) async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar lista'),
        content: Text('¿Borrar la lista «${l['nombre']}»? Los comunicados ya enviados a ella no '
            'cambian: el historial guarda el nombre que tenía.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (seguro != true) return;
    try {
      await Supabase.instance.client.from('listas_distribucion').delete().eq('id', l['id']);
      await alCambiar();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo borrar la lista: $e'),
          backgroundColor: Colors.red[700],
        ));
      }
    }
  }
}

/// Un miembro mientras se edita la lista. `id` es el del renglón guardado; `null` si es nuevo.
class _Miembro {
  final String? id;
  final String? profileId;
  final String? correo;
  final String etiqueta;
  final String? detalle;
  final bool alcanza;

  const _Miembro({
    this.id,
    this.profileId,
    this.correo,
    required this.etiqueta,
    this.detalle,
    this.alcanza = true,
  });

  String get clave => profileId ?? correo ?? '';
}

class _DialogoLista extends StatefulWidget {
  final Map<String, dynamic>? lista;
  final List<Colaborador> colaboradores;
  const _DialogoLista({required this.lista, required this.colaboradores});

  @override
  State<_DialogoLista> createState() => _DialogoListaState();
}

class _DialogoListaState extends State<_DialogoLista> {
  final _db = Supabase.instance.client;
  late final TextEditingController _nombre;
  late final TextEditingController _descripcion;
  TextEditingController? _campo;

  late final List<_Miembro> _originales;
  late final List<_Miembro> _miembros;
  bool _guardando = false;
  String? _aviso;

  bool get _nueva => widget.lista == null;

  @override
  void initState() {
    super.initState();
    final l = widget.lista;
    _nombre = TextEditingController(text: (l?['nombre'] ?? '').toString());
    _descripcion = TextEditingController(text: (l?['descripcion'] ?? '').toString());
    _originales = [
      for (final m in List<Map<String, dynamic>>.from(l?['lista_miembros'] ?? const []))
        _desdeFila(m),
    ];
    _miembros = [..._originales];
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  _Miembro _desdeFila(Map<String, dynamic> m) {
    final tecleado = (m['correo'] ?? '').toString();
    if (tecleado.isNotEmpty) {
      return _Miembro(id: m['id']?.toString(), correo: tecleado, etiqueta: tecleado);
    }
    final p = m['profiles'] is Map ? Map<String, dynamic>.from(m['profiles']) : <String, dynamic>{};
    final activo = p['status_sys'] == 'ACTIVO';
    final correo = correoDe(p);
    return _Miembro(
      id: m['id']?.toString(),
      profileId: m['profile_id']?.toString(),
      etiqueta: nombreDe(p) ?? '(sin nombre)',
      // Se ve quién ya no alcanza, para poder sacarlo: al enviar se salta solo, pero una lista que
      // se va llenando de gente que ya no recibe engaña sobre a cuántos llega.
      detalle: !activo ? 'Ya no está activo' : (correo ?? 'Sin correo válido'),
      alcanza: activo && correo != null,
    );
  }

  void _agregarColaborador(Colaborador c) {
    setState(() {
      if (!_miembros.any((m) => m.profileId == c.id)) {
        _miembros.add(_Miembro(profileId: c.id, etiqueta: c.nombre, detalle: c.correo));
      }
      _aviso = null;
    });
    _campo?.clear();
  }

  void _agregarTexto(String texto) {
    final ya = _miembros.where((m) => m.correo != null).map((m) => m.correo!);
    final r = separarCorreos(texto, yaElegidos: ya);
    setState(() {
      for (final d in r.validos) {
        // Si el correo es de un compañero, se guarda como compañero: así sigue su correo si cambia.
        final c = widget.colaboradores.where((x) => x.correo == d).firstOrNull;
        if (c != null) {
          if (!_miembros.any((m) => m.profileId == c.id)) {
            _miembros.add(_Miembro(profileId: c.id, etiqueta: c.nombre, detalle: c.correo));
          }
        } else {
          _miembros.add(_Miembro(correo: d, etiqueta: d));
        }
      }
      _aviso = r.rechazados.isEmpty ? null : 'No son direcciones válidas: ${r.rechazados.join(', ')}.';
    });
    _campo?.text = r.rechazados.join(', ');
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      setState(() => _aviso = 'Ponle un nombre a la lista.');
      return;
    }
    if (_miembros.isEmpty) {
      setState(() => _aviso = 'Agrega al menos una persona o un correo.');
      return;
    }
    final pendiente = _campo?.text.trim() ?? '';
    if (pendiente.isNotEmpty) {
      _agregarTexto(pendiente);
      if (_aviso != null) return;
    }

    setState(() => _guardando = true);
    try {
      final descripcion = _descripcion.text.trim();
      final datos = {'nombre': nombre, 'descripcion': descripcion.isEmpty ? null : descripcion};
      final String id;
      if (_nueva) {
        final fila = await _db.from('listas_distribucion').insert(datos).select('id').single();
        id = fila['id'].toString();
      } else {
        id = widget.lista!['id'].toString();
        await _db.from('listas_distribucion').update(datos).eq('id', id);
      }

      // Sólo se toca lo que cambió: se borran los que salieron y se insertan los que entraron. Así los
      // que se quedan conservan su renglón, y no se rehace la lista entera cada vez que se añade uno.
      final quitar = _originales
          .where((o) => !_miembros.any((m) => m.id == o.id))
          .map((o) => o.id!)
          .toList();
      if (quitar.isNotEmpty) {
        await _db.from('lista_miembros').delete().inFilter('id', quitar);
      }
      final nuevos = [
        for (final m in _miembros.where((m) => m.id == null))
          {'lista_id': id, 'profile_id': m.profileId, 'correo': m.correo},
      ];
      if (nuevos.isNotEmpty) await _db.from('lista_miembros').insert(nuevos);

      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      setState(() {
        _guardando = false;
        _aviso = e.code == '23505' ? 'Ya existe una lista con ese nombre.' : 'No se pudo guardar: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _guardando = false;
        _aviso = 'No se pudo guardar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final alcanzan = _miembros.where((m) => m.alcanza).length;
    return AlertDialog(
      title: Text(_nueva ? 'Nueva lista' : 'Editar lista'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nombre,
                maxLength: 80,
                decoration: const InputDecoration(
                    labelText: 'Nombre', hintText: 'p. ej. Todos CDMX', border: OutlineInputBorder()),
              ),
              SizedBox(height: SiSpace.x2),
              TextField(
                controller: _descripcion,
                maxLength: 300,
                decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)', border: OutlineInputBorder()),
              ),
              SizedBox(height: SiSpace.x2),
              Autocomplete<Colaborador>(
                displayStringForOption: (o) => o.correo,
                optionsBuilder: (v) {
                  final q = v.text.trim().toLowerCase();
                  if (q.length < 2) return const Iterable<Colaborador>.empty();
                  return widget.colaboradores
                      .where((o) => !_miembros.any((m) => m.profileId == o.id))
                      .where((o) => o.nombre.toLowerCase().contains(q) || o.correo.contains(q))
                      .take(8);
                },
                onSelected: _agregarColaborador,
                fieldViewBuilder: (context, ctrl, foco, alEnviar) {
                  _campo = ctrl;
                  return TextField(
                    controller: ctrl,
                    focusNode: foco,
                    decoration: InputDecoration(
                      labelText: 'Agregar',
                      hintText: 'Busca un compañero o escribe un correo y pulsa Enter',
                      border: const OutlineInputBorder(),
                      errorText: _aviso,
                    ),
                    onSubmitted: (t) {
                      final escrito = t.trim().toLowerCase();
                      if (esCorreo(escrito) || escrito.contains(RegExp(r'[\s,;]'))) {
                        _agregarTexto(t);
                      } else {
                        alEnviar();
                        if (ctrl.text.trim().isNotEmpty) _agregarTexto(ctrl.text);
                      }
                      foco.requestFocus();
                    },
                  );
                },
              ),
              SizedBox(height: SiSpace.x3),
              Text(
                '${_miembros.length} en la lista'
                '${alcanzan != _miembros.length ? ' · ${_miembros.length - alcanzan} ya no alcanza' : ''}',
                style: TextStyle(fontSize: 12, color: c.ink3),
              ),
              SizedBox(height: SiSpace.x2),
              Wrap(
                spacing: SiSpace.x2,
                runSpacing: SiSpace.x2,
                children: [
                  for (final m in _miembros)
                    InputChip(
                      avatar: Icon(
                        m.profileId != null ? Icons.person_outline : Icons.alternate_email,
                        size: 16,
                        color: m.alcanza ? null : c.danger,
                      ),
                      label: Text(m.etiqueta),
                      tooltip: m.detalle,
                      onDeleted: () => setState(() => _miembros.remove(m)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Guardando…' : 'Guardar'),
        ),
      ],
    );
  }
}
