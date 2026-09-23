import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'correspondencia_listas.dart';
import 'services/correspondencia.dart';
import 'theme/si_theme.dart';

/// Correspondencia: comunicados de la empresa a los empleados.
///
/// Lo usan tres personas —decisión del usuario el 23/09/2026—, y el correo sale como «Comunicación
/// SI SOL»: sin el nombre de quien lo escribe, sin pie, y con los destinatarios en copia oculta. Quién
/// lo envió SÍ queda registrado, y se ve en el historial.
///
/// Tres pestañas: redactar, listas de distribución, y lo enviado.
///
/// La pantalla NO manda nada por sí misma ni escribe HTML: manda el DOCUMENTO del editor a la función
/// `correspondencia`, que es la que lo convierte a HTML con una lista cerrada de formatos, expande las
/// listas y decide si el comunicado sale. Lo que se valida aquí es sólo para avisar pronto.
///
/// El historial y las listas se leen directo de sus tablas, y quién puede lo decide RLS: los que
/// tienen el permiso ven TODO, no sólo lo suyo.
class CorrespondenciaPage extends StatefulWidget {
  const CorrespondenciaPage({super.key});

  @override
  State<CorrespondenciaPage> createState() => _CorrespondenciaPageState();
}

/// Algo que se puede elegir en «Para»: un compañero o una lista.
typedef _Opcion = ({bool esLista, String clave, String titulo, String detalle});

/// El cubo PRIVADO de las imágenes del editor. La función `correspondencia` las descarga de aquí y
/// las incrusta en el correo; la pantalla sólo las ve con URLs firmadas mientras se redacta.
const _cuboImagenes = 'correspondencia-imagenes';

class _CorrespondenciaPageState extends State<CorrespondenciaPage> {
  final _supabase = Supabase.instance.client;
  final _asuntoCtrl = TextEditingController();
  final _editor = QuillController.basic();

  /// El campo de destinatarios lo crea el `Autocomplete`; se guarda para poder vaciarlo al elegir.
  TextEditingController? _campoDest;

  /// Correos sueltos, tecleados o de compañeros elegidos uno por uno.
  final List<String> _destinatarios = [];

  /// Ids de las listas elegidas. Se mandan como ids: la función las expande al enviar.
  final List<String> _listasElegidas = [];

  List<Colaborador> _colaboradores = [];
  List<Map<String, dynamic>> _listas = [];
  List<Map<String, dynamic>> _enviados = [];

  bool _cargandoEnviados = true;
  bool _cargandoListas = true;
  bool _enviando = false;
  bool _subiendoImagen = false;

  /// Las URLs firmadas de las imágenes del editor, por nombre. Se guarda el FUTURO y no la URL: así
  /// cada reconstrucción del editor no vuelve a pedir la firma, que es lo que haría el `FutureBuilder`
  /// con un futuro nuevo cada vez.
  final Map<String, Future<String?>> _urlsImagenes = {};
  String? _avisoDest;

  /// Si el envío está configurado en el servidor. Lo ven quienes envían, que son los que tienen que
  /// saberlo antes de escribir un comunicado entero.
  Map<String, dynamic>? _config;

  @override
  void initState() {
    super.initState();
    _cargarColaboradores();
    _cargarListas();
    _cargarEnviados();
    _cargarConfig();
  }

  @override
  void dispose() {
    _asuntoCtrl.dispose();
    _editor.dispose();
    super.dispose();
  }

  Future<void> _cargarColaboradores() async {
    try {
      // `mail_pass` NO se pide, a propósito: esta pantalla no la necesita.
      final filas = await _supabase
          .from('profiles')
          .select('id, nombre, paterno, materno, mail_user, email')
          .eq('status_sys', 'ACTIVO')
          .order('nombre', ascending: true);
      final lista = <Colaborador>[];
      for (final f in filas) {
        final correo = correoDe(f);
        if (correo == null) continue;
        lista.add((id: f['id'].toString(), nombre: nombreDe(f) ?? correo, correo: correo));
      }
      if (mounted) setState(() => _colaboradores = lista);
    } catch (e) {
      debugPrint('Correspondencia: no se cargaron los colaboradores: $e');
    }
  }

  /// Las listas CON su gente, en una sola consulta: cada miembro trae su perfil embebido, que es lo
  /// que hace falta para saber a cuántos llega hoy.
  Future<void> _cargarListas() async {
    setState(() => _cargandoListas = true);
    try {
      final filas = await _supabase
          .from('listas_distribucion')
          .select('id, nombre, descripcion, actualizado_en, '
              'lista_miembros(id, correo, profile_id, '
              'profiles(nombre, paterno, materno, mail_user, email, status_sys))')
          .order('nombre', ascending: true);
      if (!mounted) return;
      setState(() {
        _listas = List<Map<String, dynamic>>.from(filas);
        // Una lista elegida que ya no existe —la borró otra persona— se quita del mensaje.
        _listasElegidas.removeWhere((id) => !_listas.any((l) => l['id'] == id));
      });
    } catch (e) {
      debugPrint('Correspondencia: no se cargaron las listas: $e');
    } finally {
      if (mounted) setState(() => _cargandoListas = false);
    }
  }

  Future<void> _cargarEnviados() async {
    setState(() => _cargandoEnviados = true);
    try {
      final filas = await _supabase
          .from('correspondencia')
          .select('id, remitente_nombre, asunto, destinatarios, listas, estado, error, creado_en')
          .order('creado_en', ascending: false)
          .limit(50);
      if (mounted) setState(() => _enviados = List<Map<String, dynamic>>.from(filas));
    } catch (e) {
      debugPrint('Correspondencia: no se cargó el historial: $e');
    } finally {
      if (mounted) setState(() => _cargandoEnviados = false);
    }
  }

  Future<void> _cargarConfig() async {
    try {
      final r = await _supabase.functions
          .invoke('correspondencia', body: {'configuracion': true});
      if (mounted) setState(() => _config = Map<String, dynamic>.from(r.data as Map));
    } catch (e) {
      if (mounted) {
        setState(() => _config = {'configurado': false, 'error': _mensajeDe(e)});
      }
    }
  }

  /// El texto que se le enseña a la persona, no el volcado técnico del error.
  String _mensajeDe(Object e) {
    if (e is FunctionException) {
      final d = e.details;
      if (d is Map && d['error'] != null) {
        final rechazados = (d['rechazados'] as List?)?.join(', ');
        return rechazados == null || rechazados.isEmpty
            ? d['error'].toString()
            : '${d['error']} ($rechazados)';
      }
      return 'El servidor respondió con el error ${e.status}.';
    }
    return e.toString();
  }

  Map<String, dynamic>? _lista(String id) => _listas.where((l) => l['id'] == id).firstOrNull;

  /// A quiénes va a llegar, contando las listas y sin repetir. Es una estimación para la pantalla: la
  /// cuenta de verdad la hace la función al enviar.
  List<String> get _todos {
    final todos = <String>{..._destinatarios};
    for (final id in _listasElegidas) {
      final l = _lista(id);
      if (l == null) continue;
      todos.addAll(correosDeLista(List<Map<String, dynamic>>.from(l['lista_miembros'] ?? const []))
          .correos);
    }
    return todos.toList();
  }

  void _agregarTexto(String texto) {
    final r = separarCorreos(texto, yaElegidos: _destinatarios);
    setState(() {
      _destinatarios.addAll(r.validos);
      _avisoDest = r.rechazados.isEmpty
          ? null
          : (r.rechazados.length == 1
              ? '«${r.rechazados.first}» no es una dirección válida.'
              : 'No son direcciones válidas: ${r.rechazados.join(', ')}.');
    });
    // Se deja en el campo sólo lo que no se pudo añadir, para que se pueda corregir.
    _campoDest?.text = r.rechazados.join(', ');
  }

  void _elegir(_Opcion o) {
    setState(() {
      if (o.esLista) {
        if (!_listasElegidas.contains(o.clave)) _listasElegidas.add(o.clave);
      } else if (!_destinatarios.contains(o.clave)) {
        _destinatarios.add(o.clave);
      }
      _avisoDest = null;
    });
    _campoDest?.clear();
  }

  String _nombreDeCorreo(String correo) =>
      _colaboradores.where((c) => c.correo == correo).firstOrNull?.nombre ?? correo;

  Future<void> _enviar() async {
    // Lo que quede escrito en el campo cuenta: quien teclea una dirección y pulsa «Enviar» sin darle
    // Enter espera que vaya incluida.
    final pendiente = _campoDest?.text.trim() ?? '';
    if (pendiente.isNotEmpty) {
      _agregarTexto(pendiente);
      if (_avisoDest != null) return;
    }

    final todos = _todos;
    final falta = queFalta(
      asunto: _asuntoCtrl.text,
      cuerpo: _editor.document.toPlainText(),
      destinatarios: todos.length,
    );
    if (falta != null) {
      _aviso(falta, error: true);
      return;
    }

    // Se confirma porque no se puede deshacer: un comunicado que salió, salió.
    final n = todos.length;
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar comunicado'),
        content: Text('¿Enviar «${_asuntoCtrl.text.trim()}» a '
            '${n == 1 ? _nombreDeCorreo(todos.first) : '$n destinatarios'}?'
            '${_listasElegidas.isNotEmpty ? '\n\nLas listas se revisan al enviar: si alguien entró '
                'o salió, la cuenta final puede cambiar un poco.' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (seguro != true || !mounted) return;

    setState(() => _enviando = true);
    try {
      final r = await _supabase.functions.invoke('correspondencia', body: {
        'asunto': _asuntoCtrl.text.trim(),
        // El DOCUMENTO del editor, no HTML: el HTML lo escribe la función. Ver contenido.ts.
        'contenido': _editor.document.toDelta().toJson(),
        'destinatarios': _destinatarios,
        'listas': _listasElegidas,
      });
      final datos = Map<String, dynamic>.from(r.data as Map);
      if (!mounted) return;
      final enviados = datos['enviados'] ?? 0;
      final total = datos['total'] ?? 0;
      final omitidos = (datos['omitidos'] as num?)?.toInt() ?? 0;
      final nota = omitidos > 0
          ? ' $omitidos de las listas ya no están activos o no tienen correo, y se saltaron.'
          : '';
      if (datos['estado'] == 'ENVIADO') {
        _aviso('Comunicado enviado a $enviados ${enviados == 1 ? 'destinatario' : 'destinatarios'}.$nota');
        setState(() {
          _destinatarios.clear();
          _listasElegidas.clear();
          _asuntoCtrl.clear();
          _editor.clear();
        });
      } else {
        // Salió, pero no a todos: se dice a cuántos, y se deja el borrador para revisar.
        _aviso('Salió a $enviados de $total. ${datos['error'] ?? ''}$nota', error: true);
      }
    } catch (e) {
      // Si falla, el borrador se queda intacto para poder reintentar sin volver a escribirlo.
      if (mounted) _aviso('No se pudo enviar: ${_mensajeDe(e)}', error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
      _cargarEnviados();
    }
  }

  Future<String?> _urlDeImagen(String ruta) => _urlsImagenes.putIfAbsent(
        ruta,
        () => _supabase.storage
            .from(_cuboImagenes)
            .createSignedUrl(ruta, 60 * 60)
            .then<String?>((u) => u)
            .catchError((Object _) => null),
      );

  /// Elige una imagen, la deja lista para el correo, la sube y la mete donde está el cursor.
  ///
  /// Se sube en el momento y no al enviar: así el editor la puede mostrar mientras se redacta, que es
  /// lo que permite ver cómo va a quedar el comunicado.
  Future<void> _insertarImagen() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensionesImagen,
      withData: true,
    );
    final archivo = r?.files.firstOrNull;
    if (archivo == null || archivo.bytes == null) return;

    setState(() => _subiendoImagen = true);
    // Un fotograma para que se pinte el indicador: reducir una foto grande tarda un par de segundos
    // en la web, y sin esto la pantalla parece colgada.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      final lista = prepararImagen(archivo.bytes!, archivo.name);
      if (lista == null) {
        _aviso('No se pudo leer «${archivo.name}» como imagen.', error: true);
        return;
      }
      // El mismo tope que impone el cubo. Tras reducirla casi nunca se alcanza, pero un GIF se sube
      // tal cual y ese sí puede pasarse.
      if (lista.bytes.length > 5 * 1024 * 1024) {
        final mb = (lista.bytes.length / 1024 / 1024).toStringAsFixed(1);
        _aviso('La imagen pesa $mb MB y el máximo es 5 MB.', error: true);
        return;
      }
      final ruta = nombreImagen(lista.extension);
      await _supabase.storage.from(_cuboImagenes).uploadBinary(
            ruta,
            lista.bytes,
            fileOptions: FileOptions(contentType: lista.tipo, upsert: false),
          );
      final i = _editor.selection.baseOffset < 0 ? 0 : _editor.selection.baseOffset;
      _editor.replaceText(i, 0, BlockEmbed.image(ruta), TextSelection.collapsed(offset: i + 1));
    } catch (e) {
      _aviso('No se pudo subir la imagen: $e', error: true);
    } finally {
      if (mounted) setState(() => _subiendoImagen = false);
    }
  }

  void _aviso(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? Colors.red[700] : null,
      duration: Duration(seconds: error ? 8 : 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Material(
            color: c.bg,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(icon: Icon(Icons.edit_outlined, size: 18), text: 'Nuevo comunicado'),
                Tab(
                  icon: const Icon(Icons.groups_outlined, size: 18),
                  text: 'Listas${_listas.isEmpty ? '' : ' (${_listas.length})'}',
                ),
                const Tab(icon: Icon(Icons.outbox_outlined, size: 18), text: 'Enviados'),
              ],
            ),
          ),
        ),
        body: TabBarView(children: [
          _pestanaRedactar(c),
          ListasDistribucionTab(
            listas: _listas,
            colaboradores: _colaboradores,
            cargando: _cargandoListas,
            alCambiar: _cargarListas,
          ),
          _pestanaEnviados(c),
        ]),
      ),
    );
  }

  Widget _pestanaRedactar(SiColors c) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: SiSpace.x6, vertical: SiSpace.x4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _avisoConfiguracion(c),
              _campoDestinatarios(c),
              SizedBox(height: SiSpace.x4),
              TextField(
                controller: _asuntoCtrl,
                maxLength: maxAsunto,
                decoration: const InputDecoration(labelText: 'Asunto', border: OutlineInputBorder()),
              ),
              SizedBox(height: SiSpace.x2),
              _editorConBarra(c),
              SizedBox(height: SiSpace.x2),
              Text(
                'Sale como «Comunicación SI SOL», sin tu nombre. Cada destinatario lo recibe sin ver a '
                'los demás. Queda registrado que lo enviaste tú.',
                style: TextStyle(fontSize: 12, color: c.ink3),
              ),
              SizedBox(height: SiSpace.x4),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _enviando ? null : _enviar,
                  icon: _enviando
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send, size: 18),
                  label: Text(_enviando ? 'Enviando…' : 'Enviar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// El editor con SÓLO los botones de formato que la función sabe convertir a HTML.
  ///
  /// Cada botón encendido aquí tiene que existir en `contenido.ts`, y viceversa. Uno de más —tamaño de
  /// letra, código, sangría— aparecería en pantalla y desaparecería en el correo sin avisar, que es de
  /// las cosas que peor se entienden. Lo que llegue por PEGAR con otros formatos, el servidor lo manda
  /// como texto normal.
  Widget _editorConBarra(SiColors c) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: SiRadius.rMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QuillSimpleToolbar(
            controller: _editor,
            config: QuillSimpleToolbarConfig(
              multiRowsDisplay: true,
              showFontFamily: false,
              showFontSize: false,
              showSmallButton: false,
              showLineHeightButton: false,
              showInlineCode: false,
              showCodeBlock: false,
              showListCheck: false,
              showIndent: false,
              showSearchButton: false,
              showSubscript: false,
              showSuperscript: false,
              showDirection: false,
              // Los de portapapeles no se tocan: ya vienen apagados, y son «experimentales» en esta
              // versión de flutter_quill, así que nombrarlos sólo da avisos.
              showAlignmentButtons: true,
              showJustifyAlignment: false,
              // Las imágenes entran SÓLO por aquí: suben al cubo privado con un nombre que la
              // función reconoce. Una imagen pegada no pasa por aquí, y por eso no va en el correo.
              customButtons: [
                QuillToolbarCustomButtonOptions(
                  icon: _subiendoImagen
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.image_outlined),
                  tooltip: 'Insertar imagen',
                  onPressed: _subiendoImagen ? null : _insertarImagen,
                ),
              ],
              buttonOptions: QuillSimpleToolbarButtonOptions(
                // Títulos 1 a 3 y normal: los que convierte la función. Del 4 al 6 no existen allí.
                selectHeaderStyleDropdownButton: QuillToolbarSelectHeaderStyleDropdownButtonOptions(
                  attributes: [Attribute.h1, Attribute.h2, Attribute.h3, Attribute.header],
                ),
              ),
            ),
          ),
          Divider(height: 1, color: c.line),
          SizedBox(
            height: 340,
            child: QuillEditor.basic(
              controller: _editor,
              config: QuillEditorConfig(
                placeholder: 'Escribe el comunicado…',
                padding: const EdgeInsets.all(12),
                embedBuilders: [_ImagenDelCorreo(_urlDeImagen)],
                // Sin esto, PEGAR algo con un video u otro elemento revienta el editor: flutter_quill
                // lanza UnimplementedError con cualquier incrustado que no sepa pintar.
                unknownEmbedBuilder: const _IncrustadoNoIncluido(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Avisa si el servidor de correo no está listo, antes de que alguien escriba un comunicado entero
  /// y descubra al enviar que no puede salir.
  Widget _avisoConfiguracion(SiColors c) {
    final cfg = _config;
    if (cfg == null) return const SizedBox.shrink();
    final configurado = cfg['configurado'] == true;
    final puertoOk = cfg['puerto_ok'] != false;
    final remitenteOk = cfg['remitente_ok'] != false;
    if (configurado && puertoOk && remitenteOk) return const SizedBox.shrink();

    final texto = cfg['error'] != null
        ? 'No se pudo consultar la configuración del correo: ${cfg['error']}'
        : !configurado
            ? 'El envío todavía no está configurado. Faltan los datos del servidor SMTP en los '
                'secretos de la función «correspondencia».'
            : !puertoOk
                ? (cfg['motivo_puerto'] ?? 'El puerto configurado no se puede usar.').toString()
                : (cfg['motivo_remitente'] ?? 'La dirección del remitente no es válida.').toString();
    return Container(
      margin: EdgeInsets.only(bottom: SiSpace.x4),
      padding: EdgeInsets.all(SiSpace.x3),
      decoration: BoxDecoration(
        color: c.warnTint,
        borderRadius: SiRadius.rMd,
        border: Border.all(color: c.warn.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, color: c.warn, size: 20),
        SizedBox(width: SiSpace.x2),
        Expanded(child: Text(texto, style: TextStyle(fontSize: 13, color: c.ink))),
      ]),
    );
  }

  Widget _campoDestinatarios(SiColors c) {
    final total = _todos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_listasElegidas.isNotEmpty || _destinatarios.isNotEmpty) ...[
          Wrap(
            spacing: SiSpace.x2,
            runSpacing: SiSpace.x2,
            children: [
              for (final id in _listasElegidas)
                InputChip(
                  avatar: Icon(Icons.groups_outlined, size: 16, color: c.brand),
                  label: Text(() {
                    final l = _lista(id);
                    final n = correosDeLista(
                            List<Map<String, dynamic>>.from(l?['lista_miembros'] ?? const []))
                        .correos
                        .length;
                    return '${l?['nombre'] ?? 'Lista'} ($n)';
                  }()),
                  onDeleted: () => setState(() => _listasElegidas.remove(id)),
                ),
              for (final d in _destinatarios)
                InputChip(
                  label: Text(_nombreDeCorreo(d)),
                  tooltip: d,
                  onDeleted: () => setState(() => _destinatarios.remove(d)),
                ),
            ],
          ),
          SizedBox(height: SiSpace.x2),
        ],
        Autocomplete<_Opcion>(
          displayStringForOption: (o) => o.titulo,
          optionsBuilder: (valor) {
            final q = valor.text.trim().toLowerCase();
            if (q.length < 2) return const Iterable<_Opcion>.empty();
            // Las listas primero: si alguien escribe «cdmx» casi seguro busca la lista, no a una
            // persona que viva ahí.
            final listas = _listas
                .where((l) => !_listasElegidas.contains(l['id']))
                .where((l) => (l['nombre'] ?? '').toString().toLowerCase().contains(q))
                .map<_Opcion>((l) => (
                      esLista: true,
                      clave: l['id'].toString(),
                      titulo: l['nombre'].toString(),
                      detalle: 'Lista · ${correosDeLista(List<Map<String, dynamic>>.from(
                          l['lista_miembros'] ?? const [])).correos.length} destinatarios',
                    ));
            final personas = _colaboradores
                .where((o) => !_destinatarios.contains(o.correo))
                .where((o) => o.nombre.toLowerCase().contains(q) || o.correo.contains(q))
                .map<_Opcion>((o) => (esLista: false, clave: o.correo, titulo: o.nombre, detalle: o.correo));
            return [...listas, ...personas].take(10);
          },
          onSelected: _elegir,
          optionsViewBuilder: (context, onSelected, opciones) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: SiRadius.rMd,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300, maxWidth: 480),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final o in opciones)
                      ListTile(
                        dense: true,
                        leading: Icon(o.esLista ? Icons.groups_outlined : Icons.person_outline,
                            size: 18),
                        title: Text(o.titulo),
                        subtitle: Text(o.detalle),
                        onTap: () => onSelected(o),
                      ),
                  ],
                ),
              ),
            ),
          ),
          fieldViewBuilder: (context, ctrl, foco, alEnviar) {
            _campoDest = ctrl;
            return TextField(
              controller: ctrl,
              focusNode: foco,
              decoration: InputDecoration(
                labelText: 'Para',
                hintText: 'Busca una lista o un compañero, o escribe un correo y pulsa Enter',
                border: const OutlineInputBorder(),
                errorText: _avisoDest,
                helperText: '$total de $maxDestinatarios destinatarios',
              ),
              onSubmitted: (t) {
                // Si lo escrito ya es un correo completo, gana lo escrito. Si no, Enter elige la
                // sugerencia resaltada. Al revés, teclear «ana@cliente.com» y pulsar Enter añadiría
                // a la compañera Ana, que sale sugerida porque su nombre también empieza por «ana».
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
      ],
    );
  }

  Widget _pestanaEnviados(SiColors c) {
    return RefreshIndicator(
      onRefresh: _cargarEnviados,
      child: ListView(
        padding: EdgeInsets.symmetric(horizontal: SiSpace.x6, vertical: SiSpace.x4),
        children: [
          if (_cargandoEnviados)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_enviados.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                  child: Text('Todavía no hay comunicados enviados.', style: TextStyle(color: c.ink3))),
            )
          else
            for (final m in _enviados) _filaEnviado(c, m),
        ],
      ),
    );
  }

  Widget _filaEnviado(SiColors c, Map<String, dynamic> m) {
    final estado = (m['estado'] ?? '').toString();
    final (color, fondo) = switch (estado) {
      'ENVIADO' => (c.success, c.successTint),
      'FALLIDO' => (c.danger, c.dangerTint),
      _ => (c.warn, c.warnTint),
    };
    final dest = (m['destinatarios'] as List?)?.cast<String>() ?? const [];
    final listas = (m['listas'] as List?)?.cast<String>() ?? const [];
    final fecha = DateTime.tryParse((m['creado_en'] ?? '').toString())?.toLocal();
    final detalle = [
      if (listas.isNotEmpty) listas.map((l) => '«$l»').join(', '),
      dest.length == 1 ? _nombreDeCorreo(dest.first) : '${dest.length} destinatarios',
      if (fecha != null) DateFormat('dd/MM/yyyy HH:mm').format(fecha),
      // El registro de quién lo mandó, que el correo ya no lleva: aquí es donde se ve.
      'por ${m['remitente_nombre'] ?? '—'}',
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      padding: EdgeInsets.symmetric(vertical: SiSpace.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((m['asunto'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(detalle, style: TextStyle(fontSize: 12, color: c.ink3)),
                if ((estado == 'FALLIDO' || estado == 'PARCIAL') && m['error'] != null) ...[
                  const SizedBox(height: 4),
                  Text(m['error'].toString(), style: TextStyle(fontSize: 12, color: c.danger)),
                ],
              ],
            ),
          ),
          SizedBox(width: SiSpace.x2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: fondo, borderRadius: SiRadius.rPill),
            child: Text(estado,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
          ),
        ],
      ),
    );
  }
}

/// Una imagen dentro del editor.
///
/// Sólo se pinta como imagen la subida con el botón —un nombre del cubo privado—, porque es la única
/// que el correo va a llevar. Una imagen PEGADA trae otra cosa —una dirección de internet, o la
/// imagen entera en texto— y la función la omite; aquí se dice, en vez de mostrarla como si fuera a
/// salir.
class _ImagenDelCorreo extends EmbedBuilder {
  const _ImagenDelCorreo(this.urlDe);

  final Future<String?> Function(String ruta) urlDe;

  @override
  String get key => BlockEmbed.imageType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final ruta = embedContext.node.value.data.toString();
    if (!esRutaImagen(ruta)) return const _IncrustadoNoIncluido().build(context, embedContext);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: FutureBuilder<String?>(
        future: urlDe(ruta),
        builder: (context, s) {
          if (s.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
          }
          final url = s.data;
          if (url == null) return const Text('[no se pudo mostrar la imagen]');
          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              errorBuilder: (_, __, ___) => const Text('[no se pudo mostrar la imagen]'),
            ),
          );
        },
      ),
    );
  }
}

/// Lo que se pinta en el editor en lugar de un elemento que el correo no va a llevar —una imagen
/// pegada, un video—: se dice en el propio editor, en vez de dejar que alguien crea que va a salir.
class _IncrustadoNoIncluido extends EmbedBuilder {
  const _IncrustadoNoIncluido();

  @override
  String get key => 'no-incluido';

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text('[esto no se incluye en el correo: usa el botón de imagen]',
          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
    );
  }
}
