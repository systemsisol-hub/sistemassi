import 'package:flutter/material.dart';

import '../theme/si_theme.dart';

/// La imagen de un aviso, en la ventana emergente y en el muro social.
///
/// ─── Tres decisiones ─────────────────────────────────────────────────────────
///
/// * **`BoxFit.contain` y no `cover`.** La imagen de un aviso suele ser un cartel con texto —una
///   convocatoria, un horario, un aviso de mantenimiento—, y recortarlo para llenar el hueco corta
///   justo lo que hay que leer.
/// * **`errorBuilder` obligatorio.** El archivo puede desaparecer del bucket, o la URL quedar mal
///   capturada. Sin esto, un aviso con una imagen muerta pinta el rectángulo roto de Flutter y ensucia
///   la tarjeta; con esto, el aviso se sigue leyendo y sólo falta la ilustración.
/// * **Se puede abrir en grande.** En la tercera columna de Social la tarjeta mide unos 380px, y un
///   cartel a ese tamaño no se lee. Al tocarla se abre a pantalla casi completa con zoom.
class ImagenAviso extends StatelessWidget {
  const ImagenAviso({
    super.key,
    required this.url,
    this.altoMaximo = 220,
  });

  final String url;

  /// Tope de alto. Sin él, un cartel vertical se come la ventana entera y empuja el botón de cerrar
  /// fuera de la pantalla.
  final double altoMaximo;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    return ClipRRect(
      borderRadius: SiRadius.rSm,
      child: Material(
        color: c.bg,
        child: InkWell(
          onTap: () => _abrirEnGrande(context),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: altoMaximo),
            child: SizedBox(
              width: double.infinity,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => _sinImagen(c),
                loadingBuilder: (context, hijo, progreso) => progreso == null
                    ? hijo
                    : SizedBox(
                        height: altoMaximo,
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: c.brand),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sinImagen(SiColors c) => Container(
        height: 64,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported_outlined, size: 16, color: c.ink4),
            const SizedBox(width: 6),
            Text('No se pudo cargar la imagen',
                style: TextStyle(fontSize: 11.5, color: c.ink4)),
          ],
        ),
      );

  void _abrirEnGrande(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(SiSpace.x4),
        child: Stack(
          children: [
            // InteractiveViewer para poder acercarse: un cartel con letra chica no se lee de un
            // vistazo ni a pantalla completa.
            InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: Image.network(url,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) =>
                        const SizedBox.shrink()),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close),
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.45),
                ),
                tooltip: 'Cerrar',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
