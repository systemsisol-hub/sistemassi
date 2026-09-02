import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

/// SOL: el asistente comercial.
///
/// Es un asistente APARTE de Soli, con su propio modelo y su propia llave, para que los costos de
/// los dos se puedan separar. Comparte con Soli una sola cosa a propósito —quién es quién, vía
/// `profiles` y los permisos— porque duplicar la definición de los permisos sería tener dos
/// verdades sobre la misma persona.
///
/// Tres pestañas: el Chat, el panel de Desarrollos donde se captura lo que SOL sabe, y su
/// Configuración. El panel vive DENTRO de SOL y no como sección del menú porque es la fuente de sus
/// respuestas, no otra sección del sistema. Mismo criterio que la configuración de Soli.
class SolPage extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;

  const SolPage({super.key, required this.role, required this.permissions});

  @override
  State<SolPage> createState() => _SolPageState();
}

class _SolPageState extends State<SolPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  bool get _esAdmin => widget.role == 'admin';
  bool get _puedeEditar =>
      _esAdmin || widget.permissions['edit_desarrollos'] == true;

  @override
  void initState() {
    super.initState();
    // La Configuración sólo la ve un administrador, así que la barra tiene dos o tres pestañas.
    _tabs = TabController(length: _esAdmin ? 3 : 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          _barra(c),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              // Las dos pestañas de contenido son listas largas que se leen, no se deslizan:
              // cambiar de pestaña arrastrando haría saltar al chat al intentar bajar por ellas.
              physics: const NeverScrollableScrollPhysics(),
              children: [
                const _ChatSol(),
                _PanelDesarrollos(puedeEditar: _puedeEditar),
                if (_esAdmin) const _ConfiguracionSol(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Mismo cromo que la barra de Soli y de Asistencia, para que las páginas con pestañas se vean
  /// igual.
  ///
  /// Los iconos son de los que YA usa la aplicación. `flutter build web` recorta MaterialIcons a los
  /// glifos usados y la sirve siempre en la misma URL, así que un icono nuevo sale en BLANCO para
  /// quien tenga la fuente en caché. Ya pasó con el del Convertidor.
  Widget _barra(SiColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: c.brand,
          unselectedLabelColor: c.ink3,
          indicatorColor: c.brand,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: [
            const Tab(
              height: 42,
              icon: Icon(Icons.smart_toy_outlined, size: 16),
              iconMargin: EdgeInsets.zero,
              text: 'Chat',
            ),
            const Tab(
              height: 42,
              icon: Icon(Icons.business, size: 16),
              iconMargin: EdgeInsets.zero,
              text: 'Desarrollos',
            ),
            if (_esAdmin)
              const Tab(
                height: 42,
                icon: Icon(Icons.settings_outlined, size: 16),
                iconMargin: EdgeInsets.zero,
                text: 'Configuración',
              ),
          ],
        ),
      ),
    );
  }
}

// ── Chat ─────────────────────────────────────────────────────────────────────

/// El chat, todavía sin función detrás.
///
/// Se entrega así a propósito. La cuenta del proveedor y la llave de SOL están en camino, y el panel
/// de Desarrollos ya sirve desde hoy: se puede ir capturando la información mientras el chat se
/// termina. Un chat que diga claramente que no está configurado es mejor que uno que dé un error de
/// red y parezca averiado.
class _ChatSol extends StatelessWidget {
  const _ChatSol();

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(SiSpace.x6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.smart_toy_outlined, size: 56, color: c.line),
              const SizedBox(height: SiSpace.x4),
              Text('SOL todavía no está conectado',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600, color: c.ink)),
              const SizedBox(height: SiSpace.x3),
              Text(
                'Falta darle su cuenta y su llave del proveedor de IA. Mientras tanto, en la '
                'pestaña de Desarrollos ya se puede capturar todo lo que SOL va a saber: '
                'precios, promociones y notas.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.ink3, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Panel de Desarrollos ─────────────────────────────────────────────────────

class _PanelDesarrollos extends StatefulWidget {
  final bool puedeEditar;
  const _PanelDesarrollos({required this.puedeEditar});

  @override
  State<_PanelDesarrollos> createState() => _PanelDesarrollosState();
}

class _PanelDesarrollosState extends State<_PanelDesarrollos> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _desarrollos = [];
  Map<String, List<Map<String, dynamic>>> _promos = {};
  bool _cargando = true;
  String _busqueda = '';

  static const etapas = ['PREVENTA', 'VENTA', 'ENTREGA', 'AGOTADO'];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final des = await _supabase.from('desarrollos').select().order('nombre');
      final pro = await _supabase
          .from('promociones')
          .select()
          .order('vigente_hasta', ascending: false);

      final porDesarrollo = <String, List<Map<String, dynamic>>>{};
      for (final p in pro as List) {
        // `null` en `desarrollo_id` significa «aplica a todos». Se agrupa bajo una clave propia
        // para poder mostrarlas aparte en lugar de repetirlas en cada tarjeta.
        final clave = (p['desarrollo_id'] ?? 'TODOS').toString();
        (porDesarrollo[clave] ??= []).add(Map<String, dynamic>.from(p));
      }

      if (!mounted) return;
      setState(() {
        _desarrollos =
            (des as List).map((e) => Map<String, dynamic>.from(e)).toList();
        _promos = porDesarrollo;
        _cargando = false;
      });
    } catch (e) {
      debugPrint('Error cargando desarrollos: $e');
      if (!mounted) return;
      setState(() => _cargando = false);
      _aviso('No se pudieron cargar los desarrollos: $e', error: true);
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

  /// Si una promoción está vigente HOY. Se calcula aquí y se pinta, para que nadie tenga que
  /// comparar fechas de cabeza: una promoción vencida citada a un cliente compromete algo que ya no
  /// existe.
  bool _vigente(Map<String, dynamic> p) {
    if (p['is_active'] != true) return false;
    final hoy = DateTime.now();
    final soloHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final desde = DateTime.tryParse((p['vigente_desde'] ?? '').toString());
    final hasta = DateTime.tryParse((p['vigente_hasta'] ?? '').toString());
    if (desde == null || hasta == null) return false;
    return !soloHoy.isBefore(desde) && !soloHoy.isAfter(hasta);
  }

  String _dinero(dynamic v) {
    if (v == null) return '—';
    final n = num.tryParse(v.toString());
    if (n == null) return '—';
    // Sin paquete de formato: se agrupa a mano en miles. `toStringAsFixed(0)` porque un precio de
    // lista con centavos no aporta y alarga la línea.
    final entero = n.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < entero.length; i++) {
      if (i > 0 && (entero.length - i) % 3 == 0) buf.write(',');
      buf.write(entero[i]);
    }
    return '\$$buf';
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final q = _busqueda.trim().toLowerCase();
    final vistos = _desarrollos.where((d) {
      if (q.isEmpty) return true;
      return ('${d['nombre']} ${d['ubicacion']} ${d['etapa']}')
          .toLowerCase()
          .contains(q);
    }).toList();

    return Column(
      children: [
        _cabecera(c),
        if (_cargando)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_desarrollos.isEmpty)
          Expanded(child: _vacio(c))
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(SiSpace.x5),
              children: [
                if (_promos['TODOS'] != null) _promosGenerales(c),
                for (final d in vistos) _tarjeta(c, d),
                if (vistos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(SiSpace.x8),
                    child: Center(
                      child: Text('Sin resultados para "$_busqueda"',
                          style: TextStyle(color: c.ink3)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cabecera(SiColors c) {
    return Container(
      padding: const EdgeInsets.all(SiSpace.x5),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar por nombre, ubicación o etapa…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(borderRadius: SiRadius.rMd),
                ),
                onChanged: (v) => setState(() => _busqueda = v),
              ),
            ),
          ),
          const SizedBox(width: SiSpace.x3),
          if (widget.puedeEditar)
            ElevatedButton.icon(
              onPressed: () => _formDesarrollo(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nuevo desarrollo'),
            ),
        ],
      ),
    );
  }

  Widget _vacio(SiColors c) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.business, size: 56, color: c.line),
            const SizedBox(height: SiSpace.x4),
            Text('Todavía no hay desarrollos capturados',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
            const SizedBox(height: SiSpace.x3),
            Text(
              widget.puedeEditar
                  ? 'Lo que capture aquí es exactamente lo que SOL va a poder responder. '
                      'Lo que no esté, no lo va a inventar: dirá que no lo tiene.'
                  : 'Pídale a quien administre el catálogo que capture los desarrollos.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.ink3, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  /// Las promociones que aplican a todos los desarrollos, arriba y una sola vez.
  Widget _promosGenerales(SiColors c) {
    final lista = _promos['TODOS']!;
    return Container(
      margin: const EdgeInsets.only(bottom: SiSpace.x4),
      padding: const EdgeInsets.all(SiSpace.x4),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: SiRadius.rMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign_outlined, size: 16, color: c.brand),
              const SizedBox(width: SiSpace.x2),
              Text('Promociones que aplican a todos',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.ink3,
                      letterSpacing: .4)),
            ],
          ),
          const SizedBox(height: SiSpace.x3),
          for (final p in lista) _renglonPromo(c, p, null),
        ],
      ),
    );
  }

  Widget _tarjeta(SiColors c, Map<String, dynamic> d) {
    final id = d['id'].toString();
    final promos = _promos[id] ?? [];
    final activo = d['is_active'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: SiSpace.x4),
      padding: const EdgeInsets.all(SiSpace.x4),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: SiRadius.rMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            (d['nombre'] ?? '').toString(),
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: activo ? c.ink : c.ink3),
                          ),
                        ),
                        if (d['etapa'] != null) ...[
                          const SizedBox(width: SiSpace.x2),
                          _etiqueta(c, d['etapa'].toString(), c.brand),
                        ],
                        if (!activo) ...[
                          const SizedBox(width: SiSpace.x2),
                          _etiqueta(c, 'INACTIVO', c.ink3),
                        ],
                      ],
                    ),
                    if (d['ubicacion'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(d['ubicacion'].toString(),
                            style: TextStyle(fontSize: 12.5, color: c.ink3)),
                      ),
                  ],
                ),
              ),
              if (widget.puedeEditar) ...[
                IconButton(
                  onPressed: () => _formDesarrollo(desarrollo: d),
                  icon: Icon(Icons.edit_outlined, size: 16, color: c.ink3),
                  tooltip: 'Editar',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () => _formPromo(desarrolloId: id,
                      nombreDesarrollo: (d['nombre'] ?? '').toString()),
                  icon: Icon(Icons.campaign_outlined, size: 16, color: c.ink3),
                  tooltip: 'Agregar promoción',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: () => _borrarDesarrollo(d),
                  icon: Icon(Icons.delete_outline, size: 16, color: c.ink3),
                  tooltip: 'Eliminar',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
          const SizedBox(height: SiSpace.x3),
          Wrap(
            spacing: SiSpace.x5,
            runSpacing: SiSpace.x2,
            children: [
              _dato(c, 'Precio',
                  '${_dinero(d['precio_desde'])} – ${_dinero(d['precio_hasta'])} ${d['moneda'] ?? ''}'),
              if (d['enganche_pct'] != null)
                _dato(c, 'Enganche', '${d['enganche_pct']}%'),
              if (d['mensualidades'] != null)
                _dato(c, 'Mensualidades', '${d['mensualidades']}'),
              if (d['superficie_desde'] != null)
                _dato(c, 'Superficie',
                    '${d['superficie_desde']} – ${d['superficie_hasta'] ?? '?'} m²'),
            ],
          ),
          if ((d['url_folleto'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: SiSpace.x3),
            _enlaceFolleto(c, d['url_folleto'].toString()),
          ],
          if (promos.isNotEmpty) ...[
            Divider(height: SiSpace.x6, color: c.line),
            for (final p in promos)
              _renglonPromo(c, p, id, (d['nombre'] ?? '').toString()),
          ],
        ],
      ),
    );
  }

  Widget _enlaceFolleto(SiColors c, String url) {
    // Se copia en lugar de abrirse: la aplicación no arrastra `url_launcher` y un enlace del Drive
    // se pega donde haga falta. Lo importante es que el enlace exista para poder mandarlo.
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: url));
        _aviso('Enlace del folleto copiado');
      },
      child: Row(
        children: [
          Icon(Icons.link, size: 14, color: c.brand),
          const SizedBox(width: SiSpace.x2),
          Flexible(
            child: Text(url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.brand)),
          ),
          const SizedBox(width: SiSpace.x2),
          Icon(Icons.copy, size: 12, color: c.ink4),
        ],
      ),
    );
  }

  Widget _renglonPromo(SiColors c, Map<String, dynamic> p, String? desarrolloId,
      [String? nombreDesarrollo]) {
    final vigente = _vigente(p);
    return Padding(
      padding: const EdgeInsets.only(bottom: SiSpace.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _etiqueta(c, vigente ? 'VIGENTE' : 'NO VIGENTE',
              vigente ? c.success : c.danger),
          const SizedBox(width: SiSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((p['titulo'] ?? '').toString(),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: vigente ? c.ink : c.ink3)),
                Text(
                  'Del ${p['vigente_desde']} al ${p['vigente_hasta']}'
                  '${(p['detalle'] ?? '').toString().isEmpty ? '' : ' · ${p['detalle']}'}',
                  style: TextStyle(fontSize: 11.5, color: c.ink3),
                ),
              ],
            ),
          ),
          if (widget.puedeEditar) ...[
            IconButton(
              onPressed: () => _formPromo(
                  promo: p,
                  desarrolloId: desarrolloId,
                  nombreDesarrollo: nombreDesarrollo),
              icon: Icon(Icons.edit_outlined, size: 14, color: c.ink4),
              tooltip: 'Editar promoción',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: () => _borrarPromo(p),
              icon: Icon(Icons.delete_outline, size: 14, color: c.ink4),
              tooltip: 'Eliminar promoción',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  Widget _dato(SiColors c, String etiqueta, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta,
            style: TextStyle(fontSize: 10.5, color: c.ink4, letterSpacing: .3)),
        Text(valor, style: TextStyle(fontSize: 13, color: c.ink)),
      ],
    );
  }

  Widget _etiqueta(SiColors c, String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(texto,
          style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  // ── Formularios ────────────────────────────────────────────────────────────

  Future<void> _formDesarrollo({Map<String, dynamic>? desarrollo}) async {
    final editando = desarrollo != null;
    final nombre = TextEditingController(text: desarrollo?['nombre']?.toString());
    final ubicacion =
        TextEditingController(text: desarrollo?['ubicacion']?.toString());
    final descripcion =
        TextEditingController(text: desarrollo?['descripcion']?.toString());
    final precioDesde =
        TextEditingController(text: desarrollo?['precio_desde']?.toString());
    final precioHasta =
        TextEditingController(text: desarrollo?['precio_hasta']?.toString());
    final enganche =
        TextEditingController(text: desarrollo?['enganche_pct']?.toString());
    final mensualidades =
        TextEditingController(text: desarrollo?['mensualidades']?.toString());
    final supDesde =
        TextEditingController(text: desarrollo?['superficie_desde']?.toString());
    final supHasta =
        TextEditingController(text: desarrollo?['superficie_hasta']?.toString());
    final amenidades =
        TextEditingController(text: desarrollo?['amenidades']?.toString());
    final folleto =
        TextEditingController(text: desarrollo?['url_folleto']?.toString());
    final notas = TextEditingController(text: desarrollo?['notas']?.toString());
    String? etapa = desarrollo?['etapa']?.toString();
    bool activo = desarrollo?['is_active'] != false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final c = SiColors.of(ctx);
        return StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            backgroundColor: c.panel,
            title: Text(editando ? 'Editar desarrollo' : 'Nuevo desarrollo',
                style: const TextStyle(fontSize: 17)),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                        controller: nombre,
                        decoration: const InputDecoration(
                            labelText: 'Nombre *',
                            helperText: 'Como lo van a nombrar los asesores al preguntar')),
                    const SizedBox(height: SiSpace.x4),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: ubicacion,
                              decoration: const InputDecoration(
                                  labelText: 'Ubicación'))),
                      const SizedBox(width: SiSpace.x3),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: etapa,
                          decoration:
                              const InputDecoration(labelText: 'Etapa'),
                          items: etapas
                              .map((e) => DropdownMenuItem(
                                  value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setD(() => etapa = v),
                        ),
                      ),
                    ]),
                    const SizedBox(height: SiSpace.x4),
                    // El rango va en la misma línea porque la base rechaza que el «hasta» sea menor
                    // que el «desde», y verlos juntos evita el viaje de ida y vuelta.
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: precioDesde,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Precio desde',
                                  prefixText: '\$ '))),
                      const SizedBox(width: SiSpace.x3),
                      Expanded(
                          child: TextField(
                              controller: precioHasta,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Precio hasta',
                                  prefixText: '\$ '))),
                    ]),
                    const SizedBox(height: SiSpace.x4),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: enganche,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Enganche', suffixText: '%'))),
                      const SizedBox(width: SiSpace.x3),
                      Expanded(
                          child: TextField(
                              controller: mensualidades,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Mensualidades'))),
                    ]),
                    const SizedBox(height: SiSpace.x4),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: supDesde,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Superficie desde',
                                  suffixText: 'm²'))),
                      const SizedBox(width: SiSpace.x3),
                      Expanded(
                          child: TextField(
                              controller: supHasta,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Superficie hasta',
                                  suffixText: 'm²'))),
                    ]),
                    const SizedBox(height: SiSpace.x4),
                    TextField(
                        controller: descripcion,
                        minLines: 2,
                        maxLines: 4,
                        decoration:
                            const InputDecoration(labelText: 'Descripción')),
                    const SizedBox(height: SiSpace.x4),
                    TextField(
                        controller: amenidades,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                            labelText: 'Amenidades',
                            helperText: 'Separadas por comas')),
                    const SizedBox(height: SiSpace.x4),
                    TextField(
                        controller: folleto,
                        decoration: const InputDecoration(
                            labelText: 'Enlace al folleto',
                            helperText:
                                'Se pega el enlace del Drive. SOL lo manda, no lo lee')),
                    const SizedBox(height: SiSpace.x4),
                    TextField(
                        controller: notas,
                        minLines: 2,
                        maxLines: 6,
                        decoration: const InputDecoration(
                            labelText: 'Notas para SOL',
                            helperText:
                                'Lo que no cabe en los campos y SOL debe saber igual')),
                    const SizedBox(height: SiSpace.x4),
                    SwitchListTile(
                      value: activo,
                      onChanged: (v) => setD(() => activo = v),
                      title: const Text('Activo', style: TextStyle(fontSize: 14)),
                      subtitle: Text(
                          activo
                              ? 'SOL lo puede mencionar'
                              : 'SOL NO lo va a mencionar',
                          style: TextStyle(fontSize: 11.5, color: c.ink3)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () async {
                  if (nombre.text.trim().isEmpty) {
                    _aviso('El nombre es obligatorio', error: true);
                    return;
                  }
                  Navigator.pop(ctx);
                  await _guardarDesarrollo(
                    id: desarrollo?['id']?.toString(),
                    datos: {
                      'nombre': nombre.text.trim().toUpperCase(),
                      'ubicacion': _oNulo(ubicacion.text),
                      'etapa': etapa,
                      'descripcion': _oNulo(descripcion.text),
                      'precio_desde': _numero(precioDesde.text),
                      'precio_hasta': _numero(precioHasta.text),
                      'enganche_pct': _numero(enganche.text),
                      'mensualidades': _entero(mensualidades.text),
                      'superficie_desde': _numero(supDesde.text),
                      'superficie_hasta': _numero(supHasta.text),
                      'amenidades': _oNulo(amenidades.text),
                      'url_folleto': _oNulo(folleto.text),
                      'notas': _oNulo(notas.text),
                      'is_active': activo,
                    },
                  );
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        });
      },
    );
  }

  String? _oNulo(String s) => s.trim().isEmpty ? null : s.trim();
  num? _numero(String s) => s.trim().isEmpty ? null : num.tryParse(s.trim());
  int? _entero(String s) => s.trim().isEmpty ? null : int.tryParse(s.trim());

  Future<void> _guardarDesarrollo(
      {String? id, required Map<String, dynamic> datos}) async {
    try {
      if (id == null) {
        await _supabase.from('desarrollos').insert(datos);
      } else {
        await _supabase.from('desarrollos').update(datos).eq('id', id);
      }
      _aviso('Desarrollo guardado');
      await _cargar();
    } catch (e) {
      // El mensaje de la base se muestra tal cual: si rechazó por el rango de precio invertido, eso
      // es exactamente lo que la persona necesita leer.
      debugPrint('Error guardando desarrollo: $e');
      _aviso('No se pudo guardar: $e', error: true);
    }
  }

  Future<void> _borrarDesarrollo(Map<String, dynamic> d) async {
    final ok = await _confirmar(
      '¿Eliminar ${d['nombre']}?',
      'Se borran también sus promociones. Si sólo quiere que SOL deje de mencionarlo, '
          'desactívelo en lugar de borrarlo.',
    );
    if (!ok) return;
    try {
      await _supabase.from('desarrollos').delete().eq('id', d['id'].toString());
      _aviso('Desarrollo eliminado');
      await _cargar();
    } catch (e) {
      _aviso('No se pudo eliminar: $e', error: true);
    }
  }

  Future<void> _formPromo({
    Map<String, dynamic>? promo,
    String? desarrolloId,
    String? nombreDesarrollo,
  }) async {
    final editando = promo != null;
    final titulo = TextEditingController(text: promo?['titulo']?.toString());
    final detalle = TextEditingController(text: promo?['detalle']?.toString());
    DateTime? desde = DateTime.tryParse((promo?['vigente_desde'] ?? '').toString());
    DateTime? hasta = DateTime.tryParse((promo?['vigente_hasta'] ?? '').toString());
    bool activa = promo?['is_active'] != false;

    String texto(DateTime? d) =>
        d == null ? 'Elegir' : d.toIso8601String().substring(0, 10);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final c = SiColors.of(ctx);
        return StatefulBuilder(builder: (ctx, setD) {
          Future<void> elegir(bool esDesde) async {
            final hoy = DateTime.now();
            final r = await showDatePicker(
              context: ctx,
              initialDate: (esDesde ? desde : hasta) ?? hoy,
              firstDate: DateTime(hoy.year - 1),
              lastDate: DateTime(hoy.year + 5),
            );
            if (r != null) setD(() => esDesde ? desde = r : hasta = r);
          }

          return AlertDialog(
            backgroundColor: c.panel,
            title: Text(editando ? 'Editar promoción' : 'Nueva promoción',
                style: const TextStyle(fontSize: 17)),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      desarrolloId == null
                          ? 'Aplica a TODOS los desarrollos'
                          : 'Aplica a ${nombreDesarrollo ?? 'este desarrollo'}',
                      style: TextStyle(fontSize: 12, color: c.ink3),
                    ),
                    const SizedBox(height: SiSpace.x4),
                    TextField(
                        controller: titulo,
                        decoration:
                            const InputDecoration(labelText: 'Título *')),
                    const SizedBox(height: SiSpace.x4),
                    TextField(
                        controller: detalle,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                            labelText: 'Detalle',
                            helperText: 'Condiciones, tal como se le pueden decir a un cliente')),
                    const SizedBox(height: SiSpace.x4),
                    // Las dos fechas son obligatorias, y no por rigor: sin fecha de fin, SOL
                    // seguiría citando la promoción para siempre.
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => elegir(true),
                          icon: const Icon(Icons.calendar_today, size: 14),
                          label: Text('Desde: ${texto(desde)}',
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                      ),
                      const SizedBox(width: SiSpace.x3),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => elegir(false),
                          icon: const Icon(Icons.calendar_today, size: 14),
                          label: Text('Hasta: ${texto(hasta)}',
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: SiSpace.x4),
                    SwitchListTile(
                      value: activa,
                      onChanged: (v) => setD(() => activa = v),
                      title:
                          const Text('Activa', style: TextStyle(fontSize: 14)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () async {
                  if (titulo.text.trim().isEmpty) {
                    _aviso('El título es obligatorio', error: true);
                    return;
                  }
                  if (desde == null || hasta == null) {
                    _aviso('Las dos fechas de vigencia son obligatorias',
                        error: true);
                    return;
                  }
                  Navigator.pop(ctx);
                  await _guardarPromo(
                    id: promo?['id']?.toString(),
                    datos: {
                      'desarrollo_id': desarrolloId,
                      'titulo': titulo.text.trim(),
                      'detalle': _oNulo(detalle.text),
                      'vigente_desde':
                          desde!.toIso8601String().substring(0, 10),
                      'vigente_hasta':
                          hasta!.toIso8601String().substring(0, 10),
                      'is_active': activa,
                    },
                  );
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _guardarPromo(
      {String? id, required Map<String, dynamic> datos}) async {
    try {
      if (id == null) {
        await _supabase.from('promociones').insert(datos);
      } else {
        // `desarrollo_id` no se reescribe al editar: mover una promoción de desarrollo es otra
        // operación, y hacerlo por descuido la aplicaría a un precio que no es el suyo.
        final copia = Map<String, dynamic>.from(datos)..remove('desarrollo_id');
        await _supabase.from('promociones').update(copia).eq('id', id);
      }
      _aviso('Promoción guardada');
      await _cargar();
    } catch (e) {
      debugPrint('Error guardando promoción: $e');
      _aviso('No se pudo guardar: $e', error: true);
    }
  }

  Future<void> _borrarPromo(Map<String, dynamic> p) async {
    final ok = await _confirmar('¿Eliminar la promoción?',
        '«${p['titulo']}». Si sólo terminó, desactívela para conservar el registro.');
    if (!ok) return;
    try {
      await _supabase.from('promociones').delete().eq('id', p['id'].toString());
      _aviso('Promoción eliminada');
      await _cargar();
    } catch (e) {
      _aviso('No se pudo eliminar: $e', error: true);
    }
  }

  Future<bool> _confirmar(String titulo, String detalle) async {
    final c = SiColors.of(context);
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.panel,
        title: Text(titulo, style: const TextStyle(fontSize: 16)),
        content: Text(detalle, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: c.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    return r == true;
  }
}

// ── Configuración ────────────────────────────────────────────────────────────

/// El modelo de SOL, editable sin desplegar.
///
/// La LLAVE no se edita aquí: `SOL_API_KEY` y `SOL_BASE_URL` viven en los secretos de Supabase,
/// porque un secreto en la base lo lee cualquiera con acceso al proyecto. Aquí sólo se dice CON QUÉ
/// modelo hablar, que no es un secreto y que conviene poder cambiar en caliente: el 12/08/2026 el
/// modelo de Soli empezó a fallar y se quedó muerta hasta que alguien entró al panel a cambiarlo.
class _ConfiguracionSol extends StatefulWidget {
  const _ConfiguracionSol();

  @override
  State<_ConfiguracionSol> createState() => _ConfiguracionSolState();
}

class _ConfiguracionSolState extends State<_ConfiguracionSol> {
  final _supabase = Supabase.instance.client;
  final _modelo = TextEditingController();
  final _respaldo = TextEditingController();
  final _instrucciones = TextEditingController();
  bool _cargando = true;
  String? _actualizado;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _modelo.dispose();
    _respaldo.dispose();
    _instrucciones.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final d = await _supabase.from('sol_config').select().maybeSingle();
      if (!mounted) return;
      setState(() {
        _modelo.text = (d?['modelo'] ?? '').toString();
        _respaldo.text = (d?['modelo_respaldo'] ?? '').toString();
        _instrucciones.text = (d?['instrucciones'] ?? '').toString();
        _actualizado = d?['actualizado_en']?.toString();
        _cargando = false;
      });
    } catch (e) {
      debugPrint('Error cargando la configuración de SOL: $e');
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardar() async {
    final c = SiColors.of(context);
    try {
      await _supabase.from('sol_config').update({
        'modelo': _modelo.text.trim().isEmpty ? null : _modelo.text.trim(),
        'modelo_respaldo':
            _respaldo.text.trim().isEmpty ? null : _respaldo.text.trim(),
        'instrucciones': _instrucciones.text.trim().isEmpty
            ? null
            : _instrucciones.text.trim(),
      }).eq('id', true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Configuración guardada'),
          backgroundColor: c.success));
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo guardar: $e'), backgroundColor: c.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(SiSpace.x6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('El modelo de SOL',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: SiSpace.x2),
              Text(
                'SOL usa un modelo y una cuenta distintos de los de Soli, para que los costos se '
                'puedan separar. Aquí se elige el modelo; se puede cambiar en caliente, sin '
                'desplegar nada.',
                style: TextStyle(fontSize: 13, color: c.ink3, height: 1.5),
              ),
              const SizedBox(height: SiSpace.x5),
              TextField(
                controller: _modelo,
                decoration: const InputDecoration(
                  labelText: 'Modelo',
                  helperText: 'El identificador exacto que da el proveedor',
                ),
              ),
              const SizedBox(height: SiSpace.x5),
              TextField(
                controller: _respaldo,
                decoration: const InputDecoration(
                  labelText: 'Modelo de respaldo',
                  helperText:
                      'Al que se cambia si el principal falla. Conviene que sea de otra familia: '
                      'si los dos son del mismo proveedor, la caída que tumbe a uno tumbará al otro',
                ),
              ),
              const SizedBox(height: SiSpace.x5),
              TextField(
                controller: _instrucciones,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Instrucciones adicionales',
                  helperText:
                      'Se añaden al final de su prompt. Para el tono y lo que no debe hacer; '
                      'los precios NO se ponen aquí, se capturan en Desarrollos',
                ),
              ),
              const SizedBox(height: SiSpace.x5),
              Container(
                padding: const EdgeInsets.all(SiSpace.x4),
                decoration: BoxDecoration(
                  color: c.panel,
                  border: Border.all(color: c.line),
                  borderRadius: SiRadius.rMd,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.vpn_key_outlined, size: 16, color: c.ink3),
                    const SizedBox(width: SiSpace.x3),
                    Expanded(
                      child: Text(
                        'La llave no se pone aquí. SOL_API_KEY y SOL_BASE_URL viven en los '
                        'secretos de Supabase: una llave guardada en la base la puede leer '
                        'cualquiera con acceso al proyecto.',
                        style:
                            TextStyle(fontSize: 12, color: c.ink3, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SiSpace.x5),
              Row(
                children: [
                  ElevatedButton(
                      onPressed: _guardar, child: const Text('Guardar')),
                  const SizedBox(width: SiSpace.x4),
                  if (_actualizado != null)
                    Text('Última vez: ${_actualizado!.substring(0, 16)}',
                        style: TextStyle(fontSize: 11.5, color: c.ink4)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
