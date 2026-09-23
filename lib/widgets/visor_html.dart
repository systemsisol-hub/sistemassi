import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/si_theme.dart';

// El visor reusa el iframe de BI en lugar de duplicar el código de plataforma. Es el mismo widget:
// una URL dentro de un `HtmlElementView`. El iframe se crea SIN atributo `sandbox`, y por eso el HTML
// puede descargar archivos y abrir ventanas nuevas —que es justo lo que un visor con sandbox bloquea
// en silencio—.
import '../bi_web_iframe_stub.dart' if (dart.library.html) '../bi_web_iframe_web.dart';

/// Visor de los archivos HTML que SUBE la gente: las herramientas y los de Conocimientos.
///
/// Los dos tienen el mismo problema y la misma solución, y por eso viven aquí y no en cada página.
///
/// Supabase no puede ENTREGAR un HTML: lo devuelve como `text/plain` con un `sandbox` encima. Lo
/// entrega una Pages Function (`functions/h/` para las herramientas, `functions/c/` para
/// Conocimientos) a partir del `token` de una URL firmada. Y lo hace en OTRO nombre de host para que
/// quede en otro origen: así el HTML subido no puede leer el `localStorage` donde `supabase_flutter`
/// guarda el token de sesión. El detalle está en el encabezado de esas funciones.

const _hostProduccion = 'herramientas.sistemassi.com';

/// Alias de rama de Pages. El subdominio de producción sirve el despliegue de `main`, así que apuntar
/// ahí desde una previsualización pide el archivo a una versión que todavía no tiene la función: el
/// iframe acabó mostrando la pantalla de acceso de sistemassi.
///
/// Sirve además para poder PROBAR un cambio en la función antes de que llegue a producción.
const _hostPruebas = 'develop.sistemassi.pages.dev';

/// El host de producción sólo cuando la aplicación se está sirviendo desde producción. Fuera de la web
/// no hay `Uri.base` útil, y ahí la aplicación es la compilada, así que va a producción.
String get _hostHtml {
  if (!kIsWeb) return _hostProduccion;
  final propio = Uri.base.host;
  return (propio == 'sistemassi.com' || propio == 'www.sistemassi.com')
      ? _hostProduccion
      : _hostPruebas;
}

/// Convierte la URL firmada de Storage en la dirección que sí entrega el HTML: la misma ruta y el
/// mismo `token`, pedidos a la Pages Function de [prefijo] en el host aislado.
String urlHtmlAislado(String firmada, String prefijo, String ruta) {
  final token = Uri.parse(firmada).queryParameters['token'];
  if (token == null) return firmada;
  return Uri.https(_hostHtml, '/$prefijo/$ruta', {'token': token}).toString();
}

/// Abre el HTML a pantalla completa dentro de la aplicación. Fuera de la web no hay iframe, así que
/// se abre en el navegador del sistema.
Future<void> abrirVisorHtml(
  BuildContext context, {
  required String url,
  required String titulo,
}) async {
  if (!kIsWeb) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return;
  }
  if (!context.mounted) return;
  await showGeneralDialog(
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
          width: MediaQuery.of(ctx).size.width,
          height: MediaQuery.of(ctx).size.height,
          child: VisorHtml(
            url: url,
            titulo: titulo,
            onClose: () => Navigator.pop(ctx),
          ),
        ),
      ),
    ),
  );
}

class VisorHtml extends StatelessWidget {
  final String url;
  final String titulo;
  final VoidCallback onClose;

  const VisorHtml({
    super.key,
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
                    overflow: TextOverflow.ellipsis,
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
