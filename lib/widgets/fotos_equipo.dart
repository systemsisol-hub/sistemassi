import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/si_theme.dart';

/// Fotos de un equipo del inventario.
///
/// Viven en el bucket privado `issi-docs`, junto al resguardo firmado, en
/// `inventario/<id del equipo>/fotos/<marca de tiempo>.jpg`. No hay columna en la tabla: la carpeta
/// es la lista de fotos.
class FotosInventario {
  FotosInventario._();

  static const _bucket = 'issi-docs';
  static String _carpeta(String id) => 'inventario/$id/fotos';

  static StorageFileApi get _st => Supabase.instance.client.storage.from(_bucket);

  /// Rutas de las fotos del equipo, de la más vieja a la más nueva.
  static Future<List<String>> listar(String id) async {
    final archivos = await _st.list(path: _carpeta(id));
    final nombres = archivos
        .map((f) => f.name)
        .where((n) => n.isNotEmpty && !n.startsWith('.'))
        .toList()
      ..sort();
    return [for (final n in nombres) '${_carpeta(id)}/$n'];
  }

  /// URLs firmadas (1 hora) para mostrar las fotos.
  static Future<List<String>> urls(List<String> rutas) async {
    if (rutas.isEmpty) return [];
    final firmadas = await _st.createSignedUrls(rutas, 3600);
    return [for (final f in firmadas) f.signedUrl];
  }

  static Future<void> subir(String id, Uint8List bytes) async {
    final nombre = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _st.uploadBinary('${_carpeta(id)}/$nombre', bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'));
  }

  static Future<void> borrar(List<String> rutas) async {
    if (rutas.isNotEmpty) await _st.remove(rutas);
  }
}

/// Lo que se eligió en el formulario y todavía no se guarda: las fotos nuevas se suben y las
/// quitadas se borran hasta que se pulsa «Guardar» (un equipo nuevo aún no tiene id).
class FotosPendientes {
  final List<Uint8List> nuevas = [];
  final List<String> aBorrar = [];

  Future<void> aplicar(String id) async {
    for (final b in nuevas) {
      await FotosInventario.subir(id, b);
    }
    await FotosInventario.borrar(aBorrar);
  }
}

/// Sección «Fotos» del formulario: las que ya tiene el equipo y las nuevas, con botones para
/// tomar una en el momento o elegir de la galería.
class FotosEquipoEditor extends StatefulWidget {
  final String? itemId;
  final FotosPendientes pendientes;

  const FotosEquipoEditor({super.key, required this.itemId, required this.pendientes});

  @override
  State<FotosEquipoEditor> createState() => _FotosEquipoEditorState();
}

class _FotosEquipoEditorState extends State<FotosEquipoEditor> {
  List<String> _rutas = [];
  List<String> _urls = [];
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final id = widget.itemId;
    if (id == null) return;
    setState(() => _cargando = true);
    try {
      final rutas = await FotosInventario.listar(id);
      final urls = await FotosInventario.urls(rutas);
      if (mounted) setState(() { _rutas = rutas; _urls = urls; });
    } catch (e) {
      debugPrint('Error al leer las fotos del equipo: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _agregar(ImageSource origen) async {
    final picker = ImagePicker();
    try {
      final elegidas = origen == ImageSource.camera
          ? [
              if (await picker.pickImage(
                      source: ImageSource.camera, maxWidth: 1600, imageQuality: 70)
                  case final f?)
                f
            ]
          : await picker.pickMultiImage(maxWidth: 1600, imageQuality: 70);
      for (final f in elegidas) {
        widget.pendientes.nuevas.add(await f.readAsBytes());
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error al elegir fotos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir la cámara o la galería: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final visibles = [
      for (var i = 0; i < _rutas.length; i++)
        if (!widget.pendientes.aBorrar.contains(_rutas[i])) i,
    ];

    Widget miniatura(ImageProvider img, VoidCallback quitar) => Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image(image: img, width: 88, height: 88, fit: BoxFit.cover),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: InkWell(
                onTap: quitar,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.photo_camera_outlined, size: 18, color: c.ink3),
            const SizedBox(width: 8),
            Text('Fotos del equipo',
                style: TextStyle(fontWeight: FontWeight.w600, color: c.ink2)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _agregar(ImageSource.camera),
              icon: const Icon(Icons.photo_camera, size: 18),
              label: const Text('Tomar foto'),
            ),
            TextButton.icon(
              onPressed: () => _agregar(ImageSource.gallery),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Subir'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_cargando)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (visibles.isEmpty && widget.pendientes.nuevas.isEmpty)
          Text('Sin fotos',
              style: TextStyle(color: c.ink4, fontStyle: FontStyle.italic, fontSize: 13))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final i in visibles)
                miniatura(NetworkImage(_urls[i]),
                    () => setState(() => widget.pendientes.aBorrar.add(_rutas[i]))),
              for (final b in widget.pendientes.nuevas)
                miniatura(MemoryImage(b),
                    () => setState(() => widget.pendientes.nuevas.remove(b))),
            ],
          ),
      ],
    );
  }
}

/// Galería de solo lectura para la ficha del equipo: toca una foto para verla completa.
class FotosEquipoGaleria extends StatefulWidget {
  final String itemId;
  const FotosEquipoGaleria({super.key, required this.itemId});

  @override
  State<FotosEquipoGaleria> createState() => _FotosEquipoGaleriaState();
}

class _FotosEquipoGaleriaState extends State<FotosEquipoGaleria> {
  List<String>? _urls;

  @override
  void initState() {
    super.initState();
    FotosInventario.listar(widget.itemId)
        .then(FotosInventario.urls)
        .then((u) => mounted ? setState(() => _urls = u) : null)
        .catchError((e) {
      debugPrint('Error al leer las fotos del equipo: $e');
      if (mounted) setState(() => _urls = []);
      return null;
    });
  }

  void _verCompleta(int inicio) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            PageView(
              controller: PageController(initialPage: inicio),
              children: [
                for (final u in _urls!)
                  InteractiveViewer(child: Center(child: Image.network(u))),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final urls = _urls;
    if (urls == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (urls.isEmpty) {
      return Text('Sin fotos',
          style: TextStyle(color: c.ink4, fontStyle: FontStyle.italic, fontSize: 13));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < urls.length; i++)
          InkWell(
            onTap: () => _verCompleta(i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(urls[i], width: 110, height: 110, fit: BoxFit.cover),
            ),
          ),
      ],
    );
  }
}
