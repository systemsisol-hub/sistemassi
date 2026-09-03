import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme/si_theme.dart';
import 'campos_globales.dart';
import 'unidades_panel.dart';
import 'widgets/texto_con_enlaces.dart';

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
              // El icono de SOL, distinto del robot de Soli: son dos asistentes y conviene que se
              // note desde el primer golpe de vista.
              icon: Icon(Icons.face_2, size: 16),
              iconMargin: EdgeInsets.zero,
              text: 'Chat',
            ),
            const Tab(
              height: 42,
              // Aqui el edificio SI corresponde: la pestaña es de desarrollos inmobiliarios.
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

/// El chat de SOL.
///
/// Habla con la función `sol-assistant`, que usa la MISMA cuenta de Ollama que Soli con otro
/// modelo. Si no hay modelo configurado la función lo dice en su respuesta y aquí se muestra tal
/// cual: es más útil que un error de red.
///
/// El hilo se guarda sólo en memoria. SOL no tiene puente de WhatsApp, así que no hay una segunda
/// vía que tenga que compartir la conversación —que es lo que obligó a guardarla en Soli—.
class _ChatSol extends StatefulWidget {
  const _ChatSol();

  @override
  State<_ChatSol> createState() => _ChatSolState();
}

class _ChatSolState extends State<_ChatSol> {
  final _supabase = Supabase.instance.client;
  final _entrada = TextEditingController();
  final _scroll = ScrollController();
  final _mensajes = <({bool mio, String texto, List<Map<String, dynamic>> docs})>[];
  bool _enviando = false;

  static const _ejemplos = [
    '¿Qué desarrollos tenemos?',
    '¿Cuánto cuesta AG117?',
    '¿Qué promociones hay vigentes?',
  ];

  @override
  void dispose() {
    _entrada.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _enviar([String? texto]) async {
    final pregunta = (texto ?? _entrada.text).trim();
    if (pregunta.isEmpty || _enviando) return;

    setState(() {
      _mensajes.add((mio: true, texto: pregunta, docs: const []));
      _entrada.clear();
      _enviando = true;
    });
    _alFinal();

    try {
      // Se manda el hilo completo para que pueda seguir el contexto —«¿y el enganche?» después de
      // preguntar por un desarrollo—. El tope de turnos lo pone la función, no esto.
      final r = await _supabase.functions.invoke('sol-assistant', body: {
        'messages': [
          for (final m in _mensajes)
            {'role': m.mio ? 'user' : 'assistant', 'content': m.texto},
        ],
      });
      final datos = r.data as Map<String, dynamic>?;
      final respuesta = (datos?['text'] ?? datos?['error'] ?? '').toString().trim();
      // Los documentos vienen APARTE del texto: los manda la función desde lo que devolvieron sus
      // herramientas, así que son enlaces reales por construcción. El modelo no los escribe.
      final docs = ((datos?['documentos'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _mensajes.add((
          mio: false,
          texto: respuesta.isEmpty ? 'No recibí respuesta.' : respuesta,
          docs: docs,
        ));
        _enviando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // El error se muestra: si es de permisos o de configuración, el texto lo dice y es lo que
        // hace falta leer.
        _mensajes.add((
            mio: false, texto: 'No se pudo consultar a SOL: $e', docs: const []));
        _enviando = false;
      });
    }
    _alFinal();
  }

  void _alFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return Column(
      children: [
        Expanded(
          child: _mensajes.isEmpty
              ? _bienvenida(c)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(SiSpace.x5),
                  itemCount: _mensajes.length + (_enviando ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _mensajes.length) return _pensando(c);
                    return _burbuja(c, _mensajes[i]);
                  },
                ),
        ),
        _barraEntrada(c),
      ],
    );
  }

  Widget _bienvenida(SiColors c) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(SiSpace.x6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.face_2, size: 52, color: c.line),
              const SizedBox(height: SiSpace.x4),
              Text('SOL, tu asistente comercial',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600, color: c.ink)),
              const SizedBox(height: SiSpace.x2),
              Text(
                'Pregúntale por desarrollos, precios y promociones. Responde sólo con lo que está '
                'capturado: lo que no tenga, lo dice.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.ink3, height: 1.5),
              ),
              const SizedBox(height: SiSpace.x5),
              // Tres ejemplos y no una lista larga: sirven para arrancar, no de manual.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: SiSpace.x2,
                runSpacing: SiSpace.x2,
                children: [
                  for (final e in _ejemplos)
                    OutlinedButton(
                      onPressed: () => _enviar(e),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.brand,
                        side: BorderSide(color: c.line),
                        padding: const EdgeInsets.symmetric(
                            horizontal: SiSpace.x4, vertical: SiSpace.x2),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 12.5)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _burbuja(
      SiColors c, ({bool mio, String texto, List<Map<String, dynamic>> docs}) m) {
    return Align(
      alignment: m.mio ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          margin: const EdgeInsets.only(bottom: SiSpace.x3),
          padding: const EdgeInsets.symmetric(
              horizontal: SiSpace.x4, vertical: SiSpace.x3),
          decoration: BoxDecoration(
            color: m.mio ? c.brand : c.panel,
            border: m.mio ? null : Border.all(color: c.line),
            borderRadius: SiRadius.rMd,
          ),
          // Los enlaces de SOL se pueden PULSAR y abren en otra pestaña, y el texto sigue
          // siendo seleccionable para copiar un precio. `TextoConEnlaces` ya resuelve las dos
          // cosas a la vez -se escribió para los avisos, con sus doce pruebas- y usa
          // `SelectionArea` con `Text.rich` justamente porque `SelectableText` se queda los
          // gestos y el enlace no responde.
          //
          // Sólo en las respuestas de SOL: en lo que uno escribió no hay enlaces que abrir, y el
          // texto va en blanco sobre el color de marca, donde un enlace azul no se leería.
          child: m.mio
              ? SelectionArea(
                  child: Text(
                    m.texto,
                    style: const TextStyle(
                        fontSize: 13.5, height: 1.5, color: Colors.white),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextoConEnlaces(
                      m.texto,
                      style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink),
                    ),
                    if (m.docs.isNotEmpty) _botonesDocumentos(c, m.docs),
                  ],
                ),
        ),
      ),
    );
  }

  /// Un botón por documento, con su nombre en lugar de la dirección.
  ///
  /// La dirección de Drive tiene setenta caracteres: en un teléfono es imposible atinarle con el
  /// dedo, y en pantalla tapa la respuesta. El botón dice «Brochure» y ocupa lo que ocupa un dedo.
  ///
  /// Y estos enlaces son auténticos por construcción: los manda la función desde lo que
  /// devolvieron sus herramientas, sin pasar por el texto del modelo. Es la misma razón por la que
  /// las vacaciones de Soli se pintan desde los datos crudos y no desde su prosa.
  Widget _botonesDocumentos(SiColors c, List<Map<String, dynamic>> docs) {
    return Padding(
      padding: const EdgeInsets.only(top: SiSpace.x3),
      child: Wrap(
        spacing: SiSpace.x2,
        runSpacing: SiSpace.x2,
        children: [
          for (final d in docs) _unBoton(c, d),
        ],
      ),
    );
  }

  Widget _unBoton(SiColors c, Map<String, dynamic> d) {
    final esCarpeta = d['es_carpeta'] == true;
    final interno = (d['visibilidad'] ?? '').toString() == 'INTERNO';
    // El nombre corto: la categoría, y el idioma o la variante sólo si distinguen algo.
    final extra = [d['idioma'], d['variante']]
        .where((v) => v != null && v.toString().isNotEmpty)
        .join(' · ');
    final etiqueta = (d['categoria'] ?? d['nombre'] ?? 'Documento').toString();

    return Tooltip(
      message: (d['nombre'] ?? '').toString(),
      child: InkWell(
        onTap: () async {
          final uri = Uri.tryParse((d['url'] ?? '').toString());
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        borderRadius: SiRadius.rMd,
        child: Container(
          // 44 de alto: lo mínimo para un objetivo táctil cómodo.
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
              horizontal: SiSpace.x4, vertical: SiSpace.x2),
          decoration: BoxDecoration(
            color: c.bg,
            border: Border.all(color: interno ? c.warn : c.brand),
            borderRadius: SiRadius.rMd,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(esCarpeta ? Icons.folder_outlined : Icons.picture_as_pdf,
                  size: 15, color: interno ? c.warn : c.brand),
              const SizedBox(width: SiSpace.x2),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(etiqueta,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: interno ? c.warn : c.brand)),
                  if (extra.isNotEmpty || interno)
                    Text(
                      [if (extra.isNotEmpty) extra, if (interno) 'interno']
                          .join(' · '),
                      style: TextStyle(fontSize: 10.5, color: c.ink4),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pensando(SiColors c) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: SiSpace.x3),
        padding: const EdgeInsets.symmetric(
            horizontal: SiSpace.x4, vertical: SiSpace.x3),
        decoration: BoxDecoration(
          color: c.panel,
          border: Border.all(color: c.line),
          borderRadius: SiRadius.rMd,
        ),
        child: Row(children: [
          SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.ink4)),
          const SizedBox(width: SiSpace.x3),
          Text('Consultando…', style: TextStyle(fontSize: 13, color: c.ink3)),
        ]),
      ),
    );
  }

  Widget _barraEntrada(SiColors c) {
    return Container(
      padding: const EdgeInsets.all(SiSpace.x4),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _entrada,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Pregúntale a SOL…',
                border: OutlineInputBorder(borderRadius: SiRadius.rMd),
              ),
              onSubmitted: (_) => _enviar(),
            ),
          ),
          const SizedBox(width: SiSpace.x3),
          IconButton.filled(
            onPressed: _enviando ? null : () => _enviar(),
            icon: const Icon(Icons.send, size: 17),
            tooltip: 'Enviar',
          ),
        ],
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
  /// El resumen de inventario por desarrollo, de la vista `v_desarrollo_inventario`.
  ///
  /// Es la MISMA vista que consulta SOL. Si el panel contara las unidades por su cuenta, un dia el
  /// panel diria «12 disponibles» y SOL diria otra cosa, y no habria forma de saber cual miente.
  Map<String, Map<String, dynamic>> _inventario = {};
  bool _cargando = true;
  String _busqueda = '';

  /// El desarrollo que se esta viendo. `null` = ninguno elegido todavia.
  ///
  /// En pantalla ancha, si no hay ninguno elegido se muestra el PRIMERO de la lista, pero sin
  /// escribir aqui: cambiar el estado desde `build` es un error de Flutter y ademas haria que en
  /// un telefono se abriera el detalle solo, sin que nadie lo pidiera.
  String? _elegido;

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
      final inv = await _supabase.from('v_desarrollo_inventario').select();

      final porDesarrollo = <String, List<Map<String, dynamic>>>{};
      for (final p in pro as List) {
        // `null` en `desarrollo_id` significa «aplica a todos». Se agrupa bajo una clave propia
        // para poder mostrarlas aparte en lugar de repetirlas en cada tarjeta.
        final clave = (p['desarrollo_id'] ?? 'TODOS').toString();
        (porDesarrollo[clave] ??= []).add(Map<String, dynamic>.from(p));
      }

      final porInventario = <String, Map<String, dynamic>>{};
      for (final i in inv as List) {
        porInventario[i['desarrollo_id'].toString()] =
            Map<String, dynamic>.from(i);
      }

      if (!mounted) return;
      setState(() {
        _desarrollos =
            (des as List).map((e) => Map<String, dynamic>.from(e)).toList();
        _promos = porDesarrollo;
        _inventario = porInventario;
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

    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_desarrollos.isEmpty) {
      return Column(children: [_cabecera(c), Expanded(child: _vacio(c))]);
    }

    // Lista y detalle en la MISMA pantalla.
    //
    // Antes cada desarrollo era una tarjeta con sus datos y sus promociones, y el inventario vivia
    // en una pantalla aparte a la que habia que entrar y salir. Peticion del usuario del
    // 03/09/2026, y tenia razon: son tres caras del mismo desarrollo y separarlas obliga a navegar
    // para algo que se consulta junto.
    //
    // Las tres secciones van APILADAS y no en pestañas internas. Unas pestañas aqui serian volver
    // a lo mismo en pequeño: seguir entrando y saliendo para ver algo del mismo desarrollo.
    return LayoutBuilder(builder: (context, caja) {
      final ancho = caja.maxWidth >= 900;
      final elegida = _filaElegida ?? (ancho && vistos.isNotEmpty ? vistos.first : null);

      if (!ancho) {
        // En un telefono no caben las dos, asi que aqui SI hay un paso: la lista, y al elegir el
        // detalle con una flecha para volver. Es lo unico que cabe.
        if (elegida == null) {
          return Column(children: [_cabecera(c), Expanded(child: _lista(c, vistos))]);
        }
        return Column(children: [
          _barraVolver(c, elegida),
          Expanded(child: _detalle(c, elegida)),
        ]);
      }

      return Column(children: [
        _cabecera(c),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 300, child: _lista(c, vistos)),
              Container(width: 1, color: c.line),
              Expanded(
                child: elegida == null
                    ? Center(
                        child: Text('Sin resultados para "$_busqueda"',
                            style: TextStyle(color: c.ink3)))
                    : _detalle(c, elegida),
              ),
            ],
          ),
        ),
      ]);
    });
  }

  Map<String, dynamic>? get _filaElegida {
    if (_elegido == null) return null;
    for (final d in _desarrollos) {
      if (d['id'].toString() == _elegido) return d;
    }
    // El elegido puede haber desaparecido -lo borraron, o el filtro lo escondio-.
    return null;
  }

  // ── La lista ───────────────────────────────────────────────────────────────

  Widget _lista(SiColors c, List<Map<String, dynamic>> vistos) {
    if (vistos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SiSpace.x5),
          child: Text('Sin resultados para "$_busqueda"',
              textAlign: TextAlign.center, style: TextStyle(color: c.ink3)),
        ),
      );
    }
    final elegida = _filaElegida ?? vistos.first;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: SiSpace.x2),
      itemCount: vistos.length,
      itemBuilder: (_, i) => _renglonLista(c, vistos[i],
          activo: vistos[i]['id'].toString() == elegida['id'].toString()),
    );
  }

  Widget _renglonLista(SiColors c, Map<String, dynamic> d, {required bool activo}) {
    final id = d['id'].toString();
    final inv = _inventario[id];
    final disponibles = int.tryParse('${inv?['disponibles'] ?? 0}') ?? 0;
    final promosVigentes = (_promos[id] ?? []).where(_vigente).length;

    return InkWell(
      onTap: () => setState(() => _elegido = id),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: SiSpace.x4, vertical: SiSpace.x3),
        decoration: BoxDecoration(
          color: activo ? c.brandTint : null,
          border: Border(
            left: BorderSide(
                color: activo ? c.brand : Colors.transparent, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (d['nombre'] ?? '').toString(),
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: activo ? FontWeight.w700 : FontWeight.w600,
                      color: d['is_active'] == true ? c.ink : c.ink3,
                    ),
                  ),
                ),
                if (d['etapa'] != null)
                  _etiqueta(c, d['etapa'].toString(), c.brand),
              ],
            ),
            const SizedBox(height: 3),
            // Lo que hace falta saber SIN abrir: si tiene inventario y si tiene promocion viva.
            // Son las dos preguntas que obligaban a entrar a cada uno para responderlas.
            Row(
              children: [
                Icon(Icons.grid_view_outlined, size: 11, color: c.ink4),
                const SizedBox(width: 3),
                Text(
                  disponibles > 0 ? '$disponibles disponibles' : 'sin inventario',
                  style: TextStyle(
                      fontSize: 11,
                      color: disponibles > 0 ? c.ink3 : c.ink4),
                ),
                if (promosVigentes > 0) ...[
                  const SizedBox(width: SiSpace.x3),
                  Icon(Icons.campaign_outlined, size: 11, color: c.success),
                  const SizedBox(width: 3),
                  Text('$promosVigentes',
                      style: TextStyle(fontSize: 11, color: c.success)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _barraVolver(SiColors c, Map<String, dynamic> d) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SiSpace.x2, vertical: SiSpace.x2),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => setState(() => _elegido = null),
            icon: const Icon(Icons.arrow_back, size: 18),
            tooltip: 'Todos los desarrollos',
          ),
          Expanded(
            child: Text((d['nombre'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── El detalle: las tres secciones, apiladas ──────────────────────────────

  Widget _detalle(SiColors c, Map<String, dynamic> d) {
    final id = d['id'].toString();
    return ListView(
      // La clave hace que al cambiar de desarrollo la vista vuelva ARRIBA. Sin ella se queda a la
      // altura a la que estaba, que con una tabla de 38 renglones deja al siguiente desarrollo
      // abierto por la mitad.
      key: ValueKey('detalle-$id'),
      padding: const EdgeInsets.all(SiSpace.x5),
      children: [
        _bloqueDatos(c, d),
        Divider(height: SiSpace.x8, color: c.line),
        _tituloSeccion(c, 'PROMOCIONES', Icons.campaign_outlined,
            accion: widget.puedeEditar
                ? () => _formPromo(
                    desarrolloId: id, nombreDesarrollo: (d['nombre'] ?? '').toString())
                : null,
            comoDice: 'Agregar promoción'),
        const SizedBox(height: SiSpace.x3),
        _bloquePromos(c, d, id),
        Divider(height: SiSpace.x8, color: c.line),
        _tituloSeccion(c, 'INVENTARIO DE UNIDADES', Icons.grid_view_outlined),
        const SizedBox(height: SiSpace.x3),
        // El inventario va AL FINAL a proposito: es lo unico que puede medir decenas de renglones,
        // y con las promociones debajo habria que pasar toda la tabla para llegar a ellas.
        InventarioDesarrollo(
          // Sin la clave, al cambiar de desarrollo Flutter reusa el mismo estado y se queda
          // mostrando las unidades del anterior hasta que termine de cargar las nuevas.
          key: ValueKey('inv-$id'),
          desarrolloId: id,
          nombreDesarrollo: (d['nombre'] ?? '').toString(),
          puedeEditar: widget.puedeEditar,
          // Los contadores de la lista y el rango de precios salen del inventario, asi que cuando
          // cambia hay que recargar lo de aqui.
          onCambio: _cargar,
        ),
      ],
    );
  }

  Widget _tituloSeccion(SiColors c, String texto, IconData icono,
      {VoidCallback? accion, String? comoDice}) {
    return Row(
      children: [
        Icon(icono, size: 14, color: c.ink3),
        const SizedBox(width: SiSpace.x2),
        Text(texto,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c.ink3,
                letterSpacing: .6)),
        const Spacer(),
        if (accion != null)
          TextButton.icon(
            onPressed: accion,
            icon: const Icon(Icons.add, size: 14),
            label: Text(comoDice ?? 'Agregar', style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  Widget _bloquePromos(SiColors c, Map<String, dynamic> d, String id) {
    final propias = _promos[id] ?? [];
    final generales = _promos['TODOS'] ?? [];
    if (propias.isEmpty && generales.isEmpty) {
      return Text('Sin promociones capturadas.',
          style: TextStyle(fontSize: 12.5, color: c.ink4));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in propias)
          _renglonPromo(c, p, id, (d['nombre'] ?? '').toString()),
        if (generales.isNotEmpty) ...[
          if (propias.isNotEmpty) const SizedBox(height: SiSpace.x3),
          Text('Aplican a todos los desarrollos',
              style: TextStyle(fontSize: 11, color: c.ink4, letterSpacing: .3)),
          const SizedBox(height: SiSpace.x2),
          for (final p in generales) _renglonPromo(c, p, null),
        ],
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
          // El mapa de campos abarca a TODOS los desarrollos, asi que vive en la cabecera y no
          // dentro del detalle de uno.
          OutlinedButton.icon(
            onPressed: _verCampos,
            icon: const Icon(Icons.table_chart_outlined, size: 15),
            label: const Text('Campos'),
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
  /// Los datos del desarrollo. Antes era la tarjeta de la lista; ahora es la primera seccion del
  /// detalle, sin marco propio: el marco lo pone la pantalla.
  Widget _bloqueDatos(SiColors c, Map<String, dynamic> d) {
    final id = d['id'].toString();
    final activo = d['is_active'] == true;
    final inv = _inventario[id];
    final disponibles = int.tryParse('${inv?['disponibles'] ?? 0}') ?? 0;
    final hayInv = disponibles > 0;

    return Column(
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
                                fontSize: 18,
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
                  icon: Icon(Icons.edit_outlined, size: 17, color: c.ink3),
                  tooltip: 'Editar los datos',
                ),
                IconButton(
                  onPressed: () => _borrarDesarrollo(d),
                  icon: Icon(Icons.delete_outline, size: 17, color: c.ink3),
                  tooltip: 'Eliminar el desarrollo',
                ),
              ],
            ],
          ),
          const SizedBox(height: SiSpace.x3),
          Wrap(
            spacing: SiSpace.x5,
            runSpacing: SiSpace.x2,
            children: [
              // El rango sale del inventario cuando hay unidades cargadas, y se dice de donde
              // salio. `desarrollos.precio_desde` es un numero que alguien teclea y los diez
              // desarrollos lo tenian en NULL; un rango calculado no puede contradecir a las
              // unidades que lo produjeron.
              _dato(
                  c,
                  hayInv ? 'Precio (de $disponibles disponibles)' : 'Precio',
                  '${_dinero(hayInv ? inv!['precio_desde'] : d['precio_desde'])} – '
                      '${_dinero(hayInv ? inv!['precio_hasta'] : d['precio_hasta'])} '
                      '${d['moneda'] ?? ''}'),
              if (d['enganche_pct'] != null)
                _dato(c, 'Enganche', '${d['enganche_pct']}%'),
              if (d['mensualidades'] != null)
                _dato(c, 'Mensualidades', '${d['mensualidades']}'),
              if (hayInv)
                _dato(c, 'Superficie',
                    '${inv!['m2_desde']} – ${inv['m2_hasta']} m²')
              else if (d['superficie_desde'] != null)
                _dato(c, 'Superficie',
                    '${d['superficie_desde']} – ${d['superficie_hasta'] ?? '?'} m²'),
            ],
          ),
          if ((d['url_folleto'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: SiSpace.x3),
            _enlaceFolleto(c, d['url_folleto'].toString()),
          ],
          if ((d['descripcion'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: SiSpace.x3),
            Text(d['descripcion'].toString(),
                style: TextStyle(fontSize: 12.5, color: c.ink2, height: 1.5)),
          ],
          if ((d['amenidades'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: SiSpace.x3),
            Text('AMENIDADES',
                style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700,
                    color: c.ink4, letterSpacing: .5)),
            const SizedBox(height: 2),
            Text(d['amenidades'].toString(),
                style: TextStyle(fontSize: 12.5, color: c.ink2, height: 1.5)),
          ],
      ],
    );
  }

  Widget _enlaceFolleto(SiColors c, String url) {
    // Abre en otra pestaña, y el botón de al lado copia. Al escribirlo dije que la aplicación no
    // traía `url_launcher` y me equivoqué: está en el pubspec y los avisos lo usan desde hace
    // semanas. Copiar era la solución a un problema que no existía.
    return Row(
      children: [
        Flexible(
          child: InkWell(
            onTap: () async {
              final uri = Uri.tryParse(url);
              if (uri == null) return;
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: Row(
              children: [
                Icon(Icons.link, size: 14, color: c.brand),
                const SizedBox(width: SiSpace.x2),
                Flexible(
                  child: Text(url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: c.brand,
                          decoration: TextDecoration.underline,
                          decorationColor: c.brand)),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            _aviso('Enlace del folleto copiado');
          },
          icon: Icon(Icons.copy, size: 13, color: c.ink4),
          tooltip: 'Copiar el enlace',
          visualDensity: VisualDensity.compact,
        ),
      ],
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

  void _verCampos() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    SiSpace.x5, SiSpace.x4, SiSpace.x3, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Campos del inventario',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
              const Expanded(child: CamposGlobales()),
            ],
          ),
        ),
      ),
    );
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

/// La configuración de SOL, sólo para verla.
///
/// NO se puede cambiar desde aquí, por decisión del usuario el 02/09/2026: toda la configuración
/// vive en variables de entorno de Supabase, igual que la de Soli.
///
/// Y se pregunta A LA FUNCIÓN en lugar de tener una copia en Dart, por lo mismo que en Soli: la
/// única fuente es el código que de verdad corre. Una copia aquí se queda vieja en cuanto alguien
/// toque la función, y entonces la pantalla miente sobre con qué modelo se está hablando.
class _ConfiguracionSol extends StatefulWidget {
  const _ConfiguracionSol();

  @override
  State<_ConfiguracionSol> createState() => _ConfiguracionSolState();
}

class _ConfiguracionSolState extends State<_ConfiguracionSol> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _config;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await _supabase.functions
          .invoke('sol-assistant', body: {'configuracion': true, 'messages': []});
      final d = r.data as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        if (d?['error'] != null) {
          _error = d!['error'].toString();
        } else {
          _config = d;
        }
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SiSpace.x6),
          child: Text('No se pudo leer la configuración: $_error',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.danger)),
        ),
      );
    }

    final cfg = _config!;
    final modelo = (cfg['modelo'] ?? '').toString();
    final respaldo = (cfg['modelo_respaldo'] ?? '').toString();
    final cuenta = cfg['cuenta_configurada'] == true;
    final herramientas = (cfg['herramientas'] as List?) ?? const [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(SiSpace.x6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Configuración de SOL',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: SiSpace.x2),
              Text(
                'Sólo de consulta. Todo esto vive en las variables de entorno de Supabase y no se '
                'puede cambiar desde la aplicación.',
                style: TextStyle(fontSize: 13, color: c.ink3, height: 1.5),
              ),
              const SizedBox(height: SiSpace.x5),

              _tarjeta(c, 'El modelo', [
                // Un hueco aquí no es un cero: es que nadie lo configuró, y se dice así.
                _fila(c, 'Modelo', modelo.isEmpty ? 'sin configurar' : modelo,
                    alerta: modelo.isEmpty),
                _fila(c, 'Respaldo',
                    respaldo.isEmpty ? 'sin respaldo configurado' : respaldo,
                    alerta: respaldo.isEmpty),
                _fila(c, 'Proveedor', (cfg['proveedor'] ?? '—').toString()),
                _fila(c, 'Cuenta',
                    cuenta ? 'configurada' : 'FALTA la llave del proveedor',
                    alerta: !cuenta),
                _fila(c, 'Comparte cuenta con',
                    (cfg['cuenta_compartida_con'] ?? '—').toString()),
              ]),
              const SizedBox(height: SiSpace.x4),

              _tarjeta(c, 'Qué sabe hacer', [
                for (final h in herramientas)
                  _fila(c, (h['nombre'] ?? '').toString(),
                      (h['que_hace'] ?? '').toString()),
              ]),
              const SizedBox(height: SiSpace.x4),

              _tarjeta(c, 'Hasta dónde llega', [
                Padding(
                  padding: const EdgeInsets.only(top: SiSpace.x2),
                  child: Text((cfg['ambito'] ?? '').toString(),
                      style: TextStyle(fontSize: 13, color: c.ink2, height: 1.5)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjeta(SiColors c, String titulo, List<Widget> hijos) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SiSpace.x4),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: SiRadius.rMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo.toUpperCase(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: c.ink3,
                  letterSpacing: .5)),
          const SizedBox(height: SiSpace.x2),
          ...hijos,
        ],
      ),
    );
  }

  Widget _fila(SiColors c, String etiqueta, String valor, {bool alerta = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 168,
            child: Text(etiqueta,
                style: TextStyle(fontSize: 12.5, color: c.ink3)),
          ),
          Expanded(
            child: SelectionArea(
              child: Text(valor,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: alerta ? c.danger : c.ink,
                      fontWeight: alerta ? FontWeight.w600 : FontWeight.w400)),
            ),
          ),
        ],
      ),
    );
  }
}
