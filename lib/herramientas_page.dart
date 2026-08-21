import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/trash_service.dart';
import 'theme/si_theme.dart';

// El visor reusa el iframe de BI en lugar de duplicar el código de plataforma. Es el mismo widget:
// una URL dentro de un `HtmlElementView`. Importante para lo que aloja esta página: el iframe se crea
// SIN atributo `sandbox`, y por eso las herramientas pueden descargar archivos y abrir ventanas
// nuevas —que es justo lo que un visor con sandbox bloquea en silencio—.
import 'bi_web_iframe_stub.dart' if (dart.library.html) 'bi_web_iframe_web.dart';

/// Catálogo de herramientas HTML alojadas dentro del sistema.
///
/// Una «herramienta» es un archivo HTML autocontenido que mantiene alguien más y que nosotros sólo
/// servimos: el caso que estrena la página es un cotizador inmobiliario que llega ya empaquetado con
/// sus librerías, sus fuentes y sus planos dentro.
///
/// El archivo vive en Storage y no en `web/` del repositorio a propósito. En `web/` cada entrega
/// costaría recompilar y desplegar el sistema entero; aquí un administrador sube la versión nueva
/// desde esta misma pantalla.
class HerramientasPage extends StatefulWidget {
  final String role;
  final Map<String, dynamic> permissions;

  const HerramientasPage({
    super.key,
    required this.role,
    required this.permissions,
  });

  @override
  State<HerramientasPage> createState() => _HerramientasPageState();
}

class _HerramientasPageState extends State<HerramientasPage> {
  final _supabase = Supabase.instance.client;

  static const _bucket = 'herramientas';

  /// Hosts desde los que se entrega el HTML de las herramientas. Los dos son del MISMO proyecto de
  /// Pages, así que la función viaja en el mismo `git push` que la aplicación.
  ///
  /// Siempre es un host DISTINTO del que sirve la aplicación, y eso es lo importante: un host
  /// distinto es un origen distinto, y es lo que impide que el HTML del proveedor lea el
  /// `localStorage` donde `supabase_flutter` guarda el token de sesión.
  static const _hostProduccion = 'herramientas.sistemassi.com';

  /// Alias de rama de Pages. El subdominio de producción sirve el despliegue de `main`, así que
  /// apuntar ahí desde una previsualización pide el archivo a una versión que todavía no tiene la
  /// función: el iframe acabó mostrando la pantalla de acceso de sistemassi.
  ///
  /// Sirve además para poder PROBAR un cambio en la función antes de que llegue a producción, que de
  /// otro modo sería imposible.
  static const _hostPruebas = 'develop.sistemassi.pages.dev';

  /// El host de producción sólo cuando la aplicación se está sirviendo desde producción. Fuera de la
  /// web no hay `Uri.base` útil, y ahí la aplicación es la compilada, así que va a producción.
  static String get _hostHerramientas {
    if (!kIsWeb) return _hostProduccion;
    final propio = Uri.base.host;
    return (propio == 'sistemassi.com' || propio == 'www.sistemassi.com')
        ? _hostProduccion
        : _hostPruebas;
  }

  /// Cuánto vive la URL firmada con la que se abre una herramienta.
  ///
  /// Ocho horas y no cinco minutos como en los PDF del inventario: aquí el archivo pesa varios MB y
  /// una URL nueva en cada apertura es una URL distinta para el navegador, así que volvería a
  /// descargarlo entero cada vez. Con la misma URL durante la jornada, la segunda apertura sale de
  /// la caché.
  static const _vigenciaUrl = Duration(hours: 8);

  /// Margen con el que se descarta una URL guardada. Sin él, una firma a punto de caducar podría
  /// entregarse justo antes de expirar y la herramienta abriría en blanco.
  static const _margenUrl = Duration(minutes: 15);

  List<Map<String, dynamic>> _herramientas = [];
  bool _isLoading = true;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  final Map<String, String> _urlCache = {};
  final Map<String, DateTime> _urlVence = {};

  bool get _isAdmin => widget.role == 'admin';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static const _campos =
      'id, titulo, descripcion, grupo, archivo, version, archivo_bytes, '
      'subido_en, is_active, created_at';

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;

      if (_isAdmin) {
        final data = await _supabase
            .from('herramientas')
            .select(_campos)
            .order('titulo');
        _herramientas =
            (data as List).map((e) => Map<String, dynamic>.from(e)).toList();
      } else if (userId != null) {
        // Igual que en BI: se entra por la tabla de asignación y se trae la herramienta embebida.
        final data = await _supabase
            .from('herramientas_users')
            .select('herramientas($_campos)')
            .eq('user_id', userId);
        _herramientas = (data as List)
            .where((e) =>
                e['herramientas'] != null &&
                e['herramientas']['is_active'] == true)
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e['herramientas'] as Map))
            .toList()
          ..sort((a, b) => (a['titulo'] ?? '')
              .toString()
              .compareTo((b['titulo'] ?? '').toString()));
      } else {
        _herramientas = [];
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error cargando herramientas: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _aviso('No se pudieron cargar las herramientas: $e', error: true);
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _herramientas;
    final q = _searchQuery.toLowerCase();
    return _herramientas.where((h) {
      return (h['titulo'] ?? '').toString().toLowerCase().contains(q) ||
          (h['descripcion'] ?? '').toString().toLowerCase().contains(q) ||
          (h['grupo'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  void _aviso(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? SiColors.of(context).danger : null,
    ));
  }

  // ── Abrir ──────────────────────────────────────────────────────────────────

  Future<String?> _urlFirmada(Map<String, dynamic> h) async {
    final archivo = h['archivo'] as String?;
    if (archivo == null || archivo.isEmpty) return null;

    final id = h['id'].toString();
    final vence = _urlVence[id];
    if (vence != null && vence.isAfter(DateTime.now().add(_margenUrl))) {
      return _urlCache[id];
    }

    final firmada = await _supabase.storage
        .from(_bucket)
        .createSignedUrl(archivo, _vigenciaUrl.inSeconds);

    // No se usa la URL firmada tal cual: Supabase no puede ENTREGAR el HTML. Se comprobó pidiéndolo
    // —devuelve `Content-Type: text/plain`, sobrescribiendo el declarado, y añade una
    // `Content-Security-Policy: default-src 'none'; sandbox`—, y vale igual para Storage y para las
    // Edge Functions. El visor mostraba el CÓDIGO del cotizador.
    //
    // Lo entrega la Pages Function de `functions/h/[[ruta]].js`, que sólo necesita la ruta y el token
    // de esta firma. Y lo hace en OTRO nombre de host para que quede en otro origen: así el HTML del
    // proveedor no puede leer el `localStorage` donde vive el token de sesión. El detalle está en el
    // encabezado de esa función.
    final token = Uri.parse(firmada).queryParameters['token'];
    final url = token == null
        ? firmada
        : Uri.https(_hostHerramientas, '/h/$archivo', {'token': token}).toString();

    _urlCache[id] = url;
    _urlVence[id] = DateTime.now().add(_vigenciaUrl);
    return url;
  }

  Future<void> _abrir(Map<String, dynamic> h) async {
    if ((h['archivo'] as String?)?.isEmpty ?? true) {
      _aviso('Esta herramienta todavía no tiene archivo cargado.');
      return;
    }

    String? url;
    try {
      url = await _urlFirmada(h);
    } catch (e) {
      _aviso('No se pudo abrir la herramienta: $e', error: true);
      return;
    }
    if (url == null || !mounted) return;

    // Fuera de la web no hay iframe, así que se abre en el navegador del sistema. Ahí la descarga
    // del PDF y el enlace de WhatsApp funcionan igual que embebidos.
    if (!kIsWeb) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }

    if (!mounted) return;
    final titulo = (h['titulo'] ?? 'Herramienta').toString();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar',
      barrierColor: Colors.black54,
      transitionDuration: SiMotion.normal,
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: _VisorHerramienta(
              url: url!,
              titulo: titulo,
              onClose: () => Navigator.pop(ctx),
            ),
          ),
        ),
      ),
    );
  }

  // ── Administrar ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _getUsers() async {
    final data = await _supabase
        .from('profiles')
        .select('id, nombre, paterno, materno, email, status_sys, permissions')
        .eq('status_sys', 'ACTIVO')
        .order('nombre');
    return (data as List)
        .where((u) {
          final p = u['permissions'];
          return p is Map && p['show_herramientas'] == true;
        })
        .map((u) => Map<String, dynamic>.from(u))
        .toList();
  }

  Future<List<String>> _getAsignados(String herramientaId) async {
    final data = await _supabase
        .from('herramientas_users')
        .select('user_id')
        .eq('herramienta_id', herramientaId);
    return (data as List).map((e) => e['user_id'].toString()).toList();
  }

  Future<void> _toggleAcceso(
      String herramientaId, String userId, bool dar) async {
    try {
      if (dar) {
        // `upsert` sobre la restricción única en lugar de consultar y luego insertar: dos toques
        // rápidos en el mismo usuario chocarían contra la restricción y saldría un error feo.
        await _supabase.from('herramientas_users').upsert(
          {'herramienta_id': herramientaId, 'user_id': userId},
          onConflict: 'herramienta_id,user_id',
        );
      } else {
        await _supabase
            .from('herramientas_users')
            .delete()
            .eq('herramienta_id', herramientaId)
            .eq('user_id', userId);
      }
    } catch (e) {
      debugPrint('Error cambiando acceso a herramienta: $e');
    }
  }

  void _showForm({Map<String, dynamic>? herramienta}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HerramientaFormSheet(
        herramienta: herramienta,
        getUsers: _getUsers,
        getAsignados: _getAsignados,
        toggleAcceso: _toggleAcceso,
        onSave: (data) async {
          if (herramienta != null) {
            await _supabase
                .from('herramientas')
                .update(data)
                .eq('id', herramienta['id']);
          } else {
            await _supabase.from('herramientas').insert({
              ...data,
              'created_by': _supabase.auth.currentUser?.id,
            });
          }
          if (!mounted) return;
          _fetchData();
          _aviso(herramienta != null
              ? 'Herramienta actualizada'
              : 'Herramienta creada');
        },
      ),
    );
  }

  /// Límite de subida. Tiene que coincidir con `file_size_limit` del bucket: si aquí fuera mayor, el
  /// usuario esperaría la subida entera para recibir un error del servidor.
  static const _maxBytes = 50 * 1024 * 1024;

  Future<void> _subirArchivo(Map<String, dynamic> h) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['html', 'htm'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _aviso('No se pudo leer el archivo.', error: true);
      return;
    }
    if (bytes.length > _maxBytes) {
      _aviso('El archivo supera los 50 MB.', error: true);
      return;
    }

    final id = h['id'].toString();
    final version = ((h['version'] as int?) ?? 0) + 1;
    // La versión va en la ruta: sobrescribir una ruta fija dejaría a los navegadores sirviendo el
    // HTML anterior desde su caché, y nadie se enteraría de que cotiza con datos viejos.
    final path = '$id/v$version.html';

    setState(() => _isLoading = true);
    try {
      await _supabase.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'text/html',
              // Las mismas 8 horas que dura la firma. Con el `max-age=3600` por omisión de Storage,
              // el navegador revalidaría varios MB cada hora sin que el archivo haya cambiado.
              cacheControl: '28800',
            ),
          );

      await _supabase.from('herramientas').update({
        'archivo': path,
        'version': version,
        'archivo_bytes': bytes.length,
        'subido_por': _supabase.auth.currentUser?.id,
        'subido_en': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);

      // La firma guardada apunta al archivo anterior.
      _urlCache.remove(id);
      _urlVence.remove(id);

      await _fetchData();
      _aviso('Versión $version publicada (${_peso(bytes.length)}).');
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _aviso('No se pudo subir el archivo: $e', error: true);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> h) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar herramienta'),
        content: Text(
            '¿Enviar «${h['titulo']}» a la papelera? El archivo se conserva, así que se puede restaurar.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar',
                style: TextStyle(color: SiColors.of(context).danger)),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    try {
      // El archivo del bucket NO se borra: la papelera restaura la fila y, con ella, la ruta. Si se
      // borrara aquí, restaurar dejaría una herramienta que apunta a un archivo inexistente.
      await TrashService.moveToTrash(
        originTable: 'herramientas',
        originId: h['id'].toString(),
        data: Map<String, dynamic>.from(h),
        label: (h['titulo'] ?? 'Herramienta').toString(),
      );
      await _supabase.from('herramientas').delete().eq('id', h['id']);
      _urlCache.remove(h['id'].toString());
      _urlVence.remove(h['id'].toString());
      await _fetchData();
      _aviso('Herramienta enviada a la papelera');
    } catch (e) {
      _aviso('No se pudo eliminar: $e', error: true);
    }
  }

  static String _peso(int? bytes) {
    if (bytes == null || bytes <= 0) return '—';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  // ── Interfaz ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(
          child: Image.asset(
            'assets/sisol_loader.gif',
            width: 150,
            errorBuilder: (_, __, ___) =>
                CircularProgressIndicator(color: c.brand, strokeWidth: 2),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          _buildToolbar(c),
          Expanded(child: _buildContent(c, _filtered)),
        ],
      ),
    );
  }

  Widget _buildToolbar(SiColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: SiSpace.x6, vertical: SiSpace.x3),
      child: Row(
        children: [
          Container(
            width: 260,
            height: 36,
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: SiRadius.rMd,
              border: Border.all(color: c.line),
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar herramienta...',
                hintStyle: TextStyle(fontSize: 13, color: c.ink4),
                prefixIcon: Icon(Icons.search, size: 16, color: c.ink3),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 14, color: c.ink3),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          const Spacer(),
          if (_isAdmin)
            ElevatedButton.icon(
              onPressed: () => _showForm(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nueva',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: const RoundedRectangleBorder(borderRadius: SiRadius.rMd),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(SiColors c, List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _searchQuery.isEmpty ? Icons.apps_outlined : Icons.search_off,
              size: 56,
              color: c.line,
            ),
            const SizedBox(height: SiSpace.x4),
            Text(
              _searchQuery.isEmpty
                  ? (_isAdmin
                      ? 'No hay herramientas creadas'
                      : 'No tienes ninguna herramienta asignada')
                  : 'Sin resultados para "$_searchQuery"',
              style: TextStyle(color: c.ink3, fontSize: 15),
            ),
          ],
        ),
      );
    }

    // Agrupadas por el campo libre `grupo`, con las sueltas al final.
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final h in items) {
      final g = (h['grupo'] as String?)?.trim();
      grupos.putIfAbsent(g == null || g.isEmpty ? '' : g, () => []).add(h);
    }
    final nombres = grupos.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.compareTo(b);
      });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(SiSpace.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final nombre in nombres) ...[
            if (nombre.isNotEmpty || nombres.length > 1)
              Padding(
                padding: const EdgeInsets.only(
                    bottom: SiSpace.x3, top: SiSpace.x2),
                child: Text(
                  nombre.isEmpty ? 'Sin grupo' : nombre.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: c.ink3,
                  ),
                ),
              ),
            Wrap(
              spacing: SiSpace.x4,
              runSpacing: SiSpace.x4,
              children: [
                for (final h in grupos[nombre]!) _tarjeta(c, h),
              ],
            ),
            const SizedBox(height: SiSpace.x6),
          ],
        ],
      ),
    );
  }

  Widget _tarjeta(SiColors c, Map<String, dynamic> h) {
    final tieneArchivo = (h['archivo'] as String?)?.isNotEmpty ?? false;
    final activa = h['is_active'] == true;
    final version = (h['version'] as int?) ?? 0;

    return SizedBox(
      width: 320,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tieneArchivo ? () => _abrir(h) : null,
          child: Padding(
            padding: const EdgeInsets.all(SiSpace.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: c.brandTint,
                        borderRadius: SiRadius.rMd,
                      ),
                      child: Icon(Icons.apps_outlined,
                          size: 18, color: c.brand),
                    ),
                    const SizedBox(width: SiSpace.x3),
                    Expanded(
                      child: Text(
                        (h['titulo'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ),
                    if (!activa)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.warnTint,
                          borderRadius: SiRadius.rSm,
                        ),
                        child: Text('Inactiva',
                            style: TextStyle(fontSize: 10, color: c.warn)),
                      ),
                  ],
                ),
                if ((h['descripcion'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: SiSpace.x3),
                  Text(
                    h['descripcion'].toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.ink3, height: 1.4),
                  ),
                ],
                const SizedBox(height: SiSpace.x3),
                Text(
                  tieneArchivo
                      ? 'v$version · ${_peso(h['archivo_bytes'] as int?)}'
                      : 'Sin archivo cargado',
                  style: TextStyle(fontSize: 11, color: c.ink4),
                ),
                if (_isAdmin) ...[
                  Divider(height: SiSpace.x6, color: c.line),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => _subirArchivo(h),
                        icon: const Icon(Icons.upload_file, size: 15),
                        label: Text(
                          tieneArchivo ? 'Nueva versión' : 'Subir archivo',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(foregroundColor: c.brand),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => _showForm(herramienta: h),
                        icon: Icon(Icons.edit_outlined, size: 16, color: c.ink3),
                        tooltip: 'Editar',
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        onPressed: () => _eliminar(h),
                        icon: Icon(Icons.delete_outline,
                            size: 16, color: c.ink3),
                        tooltip: 'Eliminar',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Visor ────────────────────────────────────────────────────────────────────

/// Pantalla completa con la herramienta dentro de un iframe.
///
/// El iframe no lleva `sandbox`, así que la herramienta conserva lo que un visor sandboxeado
/// bloquea sin decir nada: la descarga del PDF que arma con jsPDF y el `target="_blank"` con el que
/// abre WhatsApp Web.
class _VisorHerramienta extends StatelessWidget {
  final String url;
  final String titulo;
  final VoidCallback onClose;

  const _VisorHerramienta({
    required this.url,
    required this.titulo,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final mq = MediaQuery.of(context);
    final height = mq.size.height - mq.padding.top - mq.padding.bottom;
    const headerH = 56.0;

    return Container(
      height: height,
      color: c.panel,
      child: Column(
        children: [
          Container(
            height: headerH,
            padding: const EdgeInsets.symmetric(horizontal: SiSpace.x4),
            decoration: BoxDecoration(
              color: c.panel,
              border: Border(bottom: BorderSide(color: c.line, width: 1)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: c.ink2),
                  onPressed: onClose,
                ),
                Expanded(
                  child: Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.ink),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.open_in_new, size: 18, color: c.ink2),
                  tooltip: 'Abrir en una pestaña nueva',
                  onPressed: () => launchUrl(Uri.parse(url),
                      mode: LaunchMode.externalApplication),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, box) => WebIframe(
                url: url,
                height: height - headerH,
                width: box.maxWidth,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Alta y edición ───────────────────────────────────────────────────────────

class _HerramientaFormSheet extends StatefulWidget {
  final Map<String, dynamic>? herramienta;
  final Future<List<Map<String, dynamic>>> Function() getUsers;
  final Future<List<String>> Function(String) getAsignados;
  final Future<void> Function(String, String, bool) toggleAcceso;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _HerramientaFormSheet({
    required this.getUsers,
    required this.getAsignados,
    required this.toggleAcceso,
    required this.onSave,
    this.herramienta,
  });

  @override
  State<_HerramientaFormSheet> createState() => _HerramientaFormSheetState();
}

class _HerramientaFormSheetState extends State<_HerramientaFormSheet> {
  late final TextEditingController _titulo;
  late final TextEditingController _descripcion;
  late final TextEditingController _grupo;
  late bool _activa;
  bool _guardando = false;

  bool get _esNueva => widget.herramienta == null;

  @override
  void initState() {
    super.initState();
    final h = widget.herramienta;
    _titulo = TextEditingController(text: h?['titulo'] as String?);
    _descripcion = TextEditingController(text: h?['descripcion'] as String?);
    _grupo = TextEditingController(text: h?['grupo'] as String?);
    _activa = h?['is_active'] as bool? ?? true;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _descripcion.dispose();
    _grupo.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final titulo = _titulo.text.trim();
    if (titulo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El título es obligatorio')),
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      await widget.onSave({
        'titulo': titulo,
        'descripcion': _descripcion.text.trim().isEmpty
            ? null
            : _descripcion.text.trim(),
        'grupo': _grupo.text.trim().isEmpty ? null : _grupo.text.trim(),
        'is_active': _activa,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo guardar: $e'),
          backgroundColor: SiColors.of(context).danger,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(SiSpace.x5),
            child: Row(
              children: [
                Text(
                  _esNueva ? 'Nueva herramienta' : 'Editar herramienta',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600, color: c.ink),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: c.ink3),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(SiSpace.x5),
              children: [
                TextField(
                  controller: _titulo,
                  decoration: const InputDecoration(
                    labelText: 'Título',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: SiSpace.x4),
                TextField(
                  controller: _descripcion,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: SiSpace.x4),
                TextField(
                  controller: _grupo,
                  decoration: const InputDecoration(
                    labelText: 'Grupo',
                    hintText: 'Ventas, Operación…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: SiSpace.x4),
                SwitchListTile(
                  value: _activa,
                  onChanged: (v) => setState(() => _activa = v),
                  title: const Text('Activa'),
                  subtitle: Text(
                    'Si se desactiva deja de aparecer para los usuarios asignados.',
                    style: TextStyle(fontSize: 12, color: c.ink3),
                  ),
                  activeColor: c.brand,
                  contentPadding: EdgeInsets.zero,
                ),
                if (!_esNueva) ...[
                  const SizedBox(height: SiSpace.x5),
                  Text(
                    'QUIÉN LA VE',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: c.ink3,
                    ),
                  ),
                  const SizedBox(height: SiSpace.x2),
                  Text(
                    'Sólo aparecen los usuarios que ya tienen el acceso «Herramientas» activado en su perfil.',
                    style: TextStyle(fontSize: 12, color: c.ink3),
                  ),
                  const SizedBox(height: SiSpace.x3),
                  _AsignarUsuarios(
                    herramientaId: widget.herramienta!['id'].toString(),
                    getUsers: widget.getUsers,
                    getAsignados: widget.getAsignados,
                    toggleAcceso: widget.toggleAcceso,
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          Padding(
            padding: const EdgeInsets.all(SiSpace.x5),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size(0, 44),
                  shape:
                      const RoundedRectangleBorder(borderRadius: SiRadius.rMd),
                ),
                child: Text(_guardando
                    ? 'Guardando…'
                    : (_esNueva ? 'Crear' : 'Guardar')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AsignarUsuarios extends StatefulWidget {
  final String herramientaId;
  final Future<List<Map<String, dynamic>>> Function() getUsers;
  final Future<List<String>> Function(String) getAsignados;
  final Future<void> Function(String, String, bool) toggleAcceso;

  const _AsignarUsuarios({
    required this.herramientaId,
    required this.getUsers,
    required this.getAsignados,
    required this.toggleAcceso,
  });

  @override
  State<_AsignarUsuarios> createState() => _AsignarUsuariosState();
}

class _AsignarUsuariosState extends State<_AsignarUsuarios> {
  List<Map<String, dynamic>> _users = [];
  Set<String> _asignados = {};
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await widget.getUsers();
      final asignados = await widget.getAsignados(widget.herramientaId);
      if (!mounted) return;
      setState(() {
        _users = users;
        _asignados = asignados.toSet();
        _cargando = false;
      });
    } catch (e) {
      debugPrint('Error cargando asignaciones: $e');
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _nombre(Map<String, dynamic> u) {
    final partes = [u['nombre'], u['paterno'], u['materno']]
        .where((p) => p != null && p.toString().trim().isNotEmpty)
        .map((p) => p.toString().trim());
    return partes.isEmpty ? (u['email'] ?? '—').toString() : partes.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    if (_cargando) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SiSpace.x5),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(color: c.brand, strokeWidth: 2),
          ),
        ),
      );
    }

    if (_users.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(SiSpace.x4),
        decoration: BoxDecoration(
          border: Border.all(color: c.line),
          borderRadius: SiRadius.rMd,
        ),
        child: Text(
          'Ningún usuario activo tiene el acceso «Herramientas». Actívalo en Usuarios y vuelve aquí.',
          style: TextStyle(fontSize: 13, color: c.ink3),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: SiRadius.rMd,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _users.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: c.line),
        itemBuilder: (_, i) {
          final u = _users[i];
          final id = u['id'].toString();
          final tiene = _asignados.contains(id);
          return CheckboxListTile(
            value: tiene,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: c.brand,
            title: Text(_nombre(u), style: const TextStyle(fontSize: 13)),
            subtitle: Text((u['email'] ?? '').toString(),
                style: TextStyle(fontSize: 11, color: c.ink4)),
            onChanged: (v) async {
              final dar = v ?? false;
              // Se pinta primero y se guarda después: la lista tiene que responder al toque, y un
              // fallo se corrige al recargar la hoja.
              setState(() => dar ? _asignados.add(id) : _asignados.remove(id));
              await widget.toggleAcceso(widget.herramientaId, id, dar);
            },
          );
        },
      ),
    );
  }
}
