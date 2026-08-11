import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'services/convertidor_service.dart';
import 'services/file_saver_util.dart';
import 'theme/si_theme.dart';

/// Convertidor de documentos: se sube un archivo y se descarga en otro formato.
///
/// El trabajo lo hace un Stirling PDF autoalojado, al que el navegador llama directo —ver
/// [ConvertidorService] para el por qué y para la advertencia de seguridad pendiente—.
///
/// Los formatos que se ofrecen no son la lista de la documentación: son los que se probaron uno por
/// uno contra la instancia. Excel y CSV quedaron fuera porque devuelven vacío.
class ConvertidorPage extends StatefulWidget {
  const ConvertidorPage({super.key});

  @override
  State<ConvertidorPage> createState() => _ConvertidorPageState();
}

class _ConvertidorPageState extends State<ConvertidorPage> {
  Uint8List? _bytes;
  String? _nombre;

  FormatoDestino? _destino;
  bool _convirtiendo = false;
  String? _error;
  ArchivoConvertido? _resultado;
  bool _verMas = false;

  List<FormatoDestino> get _destinos =>
      _nombre == null ? const [] : ConvertidorService.destinosPara(_nombre!);

  Future<void> _elegir() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ConvertidorService.extensionesAceptadas,
      withData: true,
    );
    final archivo = r?.files.firstOrNull;
    if (archivo == null || archivo.bytes == null) return;

    setState(() {
      _bytes = archivo.bytes;
      _nombre = archivo.name;
      _error = null;
      _resultado = null;
      _verMas = false;
      // Se preselecciona el primer destino: en la mayoría de los casos —un PDF a Markdown, un Word a
      // PDF— es el que la persona venía a buscar, y así el botón de convertir está listo de una vez.
      final posibles = ConvertidorService.destinosPara(archivo.name);
      _destino = posibles.isEmpty ? null : posibles.first;
    });
  }

  Future<void> _convertir() async {
    final bytes = _bytes;
    final nombre = _nombre;
    final destino = _destino;
    if (bytes == null || nombre == null || destino == null) return;

    setState(() {
      _convirtiendo = true;
      _error = null;
      _resultado = null;
    });
    try {
      final r = await ConvertidorService.convertir(
        bytes: bytes,
        nombreOriginal: nombre,
        destino: destino,
      );
      if (!mounted) return;
      setState(() => _resultado = r);
      // Se descarga solo: en un convertidor, pedir un clic extra para recibir lo que ya está listo
      // es fricción sin motivo. El botón de volver a descargar queda por si el navegador lo bloqueó.
      await _descargar();
    } on ConvertidorError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo convertir: $e');
    } finally {
      if (mounted) setState(() => _convirtiendo = false);
    }
  }

  Future<void> _descargar() async {
    final r = _resultado;
    if (r == null) return;
    try {
      await FileSaverUtil.saveAndShare(r.bytes, r.nombre);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo guardar el archivo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    return Scaffold(
      backgroundColor: c.bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SiSpace.x6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _encabezado(c),
                const SizedBox(height: SiSpace.x5),
                _tarjetaArchivo(c),
                if (_nombre != null) ...[
                  const SizedBox(height: SiSpace.x4),
                  _tarjetaFormatos(c),
                ],
                if (_error != null) ...[
                  const SizedBox(height: SiSpace.x4),
                  _aviso(c, _error!, c.danger, Icons.error_outline),
                ],
                if (_resultado != null && _error == null) ...[
                  const SizedBox(height: SiSpace.x4),
                  _tarjetaResultado(c),
                ],
                const SizedBox(height: SiSpace.x5),
                _notaPrivacidad(c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Qué pasa con el documento que sube la persona.
  ///
  /// Se dice porque no es evidente: un convertidor en línea normalmente manda tu archivo a un
  /// tercero. Este no. Y se dice completo —incluido el nombre en el registro— porque prometer más
  /// privacidad de la que hay es peor que no decir nada: lo comprobé midiendo, y el nombre del
  /// archivo sí aparece en el registro técnico del servidor aunque el contenido no se guarde.
  Widget _notaPrivacidad(SiColors c) => Container(
        padding: const EdgeInsets.all(SiSpace.x4),
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: SiRadius.rMd,
          border: Border.all(color: c.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, size: 16, color: c.ink3),
            const SizedBox(width: SiSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tus documentos no se conservan',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: c.ink2)),
                  const SizedBox(height: 2),
                  Text(
                      'Se procesan en un servidor de la empresa, no en un servicio '
                      'de terceros. Ni el archivo que subes ni el resultado quedan '
                      'guardados: el resultado se descarga a tu equipo y nada más. '
                      'El nombre del archivo sí aparece en el registro técnico del '
                      'servidor.',
                      style: TextStyle(fontSize: 11.5, height: 1.4, color: c.ink3)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _encabezado(SiColors c) => Row(
        children: [
          Icon(Icons.swap_horiz, size: 22, color: c.brand),
          const SizedBox(width: SiSpace.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Convertidor',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: c.ink)),
                Text(
                    'Un PDF a Markdown, Word, texto o imágenes. O un Word, Excel '
                    'o PowerPoint a PDF.',
                    style: TextStyle(fontSize: 12.5, color: c.ink3)),
              ],
            ),
          ),
        ],
      );

  Widget _tarjetaArchivo(SiColors c) {
    final hay = _nombre != null;
    return Container(
      padding: const EdgeInsets.all(SiSpace.x5),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rMd,
        border: Border.all(color: hay ? c.brand : c.line, width: hay ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Icon(hay ? Icons.description_outlined : Icons.upload_file_outlined,
              size: 28, color: hay ? c.brand : c.ink4),
          const SizedBox(width: SiSpace.x4),
          Expanded(
            child: hay
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_nombre!,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: c.ink),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      Text(_tamano(_bytes!.length),
                          style: TextStyle(fontSize: 11.5, color: c.ink3)),
                    ],
                  )
                : Text(
                    'Elige un archivo. Hasta '
                    '${ConvertidorService.maximoBytes ~/ 1024 ~/ 1024} MB.',
                    style: TextStyle(fontSize: 13, color: c.ink3)),
          ),
          const SizedBox(width: SiSpace.x3),
          hay
              ? OutlinedButton(
                  onPressed: _convirtiendo ? null : _elegir,
                  child: const Text('Cambiar'),
                )
              : FilledButton.icon(
                  onPressed: _elegir,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Elegir archivo'),
                ),
        ],
      ),
    );
  }

  Widget _tarjetaFormatos(SiColors c) {
    final principales = _destinos.where((d) => d.principal).toList();
    final otros = _destinos.where((d) => !d.principal).toList();
    final visibles = _verMas ? [...principales, ...otros] : principales;

    return Container(
      padding: const EdgeInsets.all(SiSpace.x5),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rMd,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('CONVERTIR A',
              style: SiType.mono(size: 9.5, color: c.ink3, letterSpacing: 0.8)),
          const SizedBox(height: SiSpace.x3),
          for (final d in visibles) _opcion(c, d),
          if (otros.isNotEmpty && !_verMas)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _verMas = true),
                child: Text('Más formatos (${otros.length})',
                    style: TextStyle(fontSize: 12.5, color: c.brand)),
              ),
            ),
          const SizedBox(height: SiSpace.x4),
          FilledButton.icon(
            onPressed: _convirtiendo || _destino == null ? null : _convertir,
            icon: _convirtiendo
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.swap_horiz, size: 18),
            label: Text(_convirtiendo
                ? 'Convirtiendo…'
                : 'Convertir a ${_destino?.etiqueta ?? ''}'),
          ),
          if (_convirtiendo)
            Padding(
              padding: const EdgeInsets.only(top: SiSpace.x2),
              child: Text(
                  'Un documento de muchas páginas puede tardar varios segundos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: c.ink4)),
            ),
        ],
      ),
    );
  }

  Widget _opcion(SiColors c, FormatoDestino d) {
    final activo = _destino?.id == d.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: _convirtiendo ? null : () => setState(() => _destino = d),
        borderRadius: SiRadius.rSm,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: SiSpace.x3, vertical: SiSpace.x3),
          decoration: BoxDecoration(
            color: activo ? c.brandTint : c.bg,
            borderRadius: SiRadius.rSm,
            border: Border.all(color: activo ? c.brand : c.line),
          ),
          child: Row(
            children: [
              Icon(
                  activo
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 16,
                  color: activo ? c.brand : c.ink4),
              const SizedBox(width: SiSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.etiqueta,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                activo ? FontWeight.w700 : FontWeight.w500,
                            color: c.ink)),
                    Text(d.descripcion,
                        style: TextStyle(fontSize: 11.5, color: c.ink3)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: SiRadius.rPill,
                  border: Border.all(color: c.line),
                ),
                child: Text('.${d.extension}',
                    style: SiType.mono(size: 10, color: c.ink2)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaResultado(SiColors c) {
    final r = _resultado!;
    return Container(
      padding: const EdgeInsets.all(SiSpace.x4),
      decoration: BoxDecoration(
        color: c.successTint,
        borderRadius: SiRadius.rMd,
        border: Border.all(color: c.success),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 20, color: c.success),
          const SizedBox(width: SiSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.nombre,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.ink)),
                Text('Listo · ${_tamano(r.bytes.length)}',
                    style: TextStyle(fontSize: 11.5, color: c.ink3)),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _descargar,
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Descargar'),
          ),
        ],
      ),
    );
  }

  Widget _aviso(SiColors c, String texto, Color color, IconData icono) =>
      Container(
        padding: const EdgeInsets.all(SiSpace.x4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: SiRadius.rMd,
          border: Border.all(color: color),
        ),
        child: Row(
          children: [
            Icon(icono, size: 18, color: color),
            const SizedBox(width: SiSpace.x3),
            Expanded(
              child: Text(texto,
                  style: TextStyle(fontSize: 12.5, color: c.ink2)),
            ),
          ],
        ),
      );

  static String _tamano(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
