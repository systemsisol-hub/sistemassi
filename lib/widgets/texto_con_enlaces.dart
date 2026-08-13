import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Un trozo de texto: o es texto normal, o es un enlace.
///
/// Se separa de la parte visual a propósito, para poder probar la detección sin montar un widget.
class TrozoDeTexto {
  final String texto;

  /// La dirección a la que lleva, ya lista para abrir. `null` si es texto normal.
  final String? destino;
  const TrozoDeTexto(this.texto, [this.destino]);

  bool get esEnlace => destino != null;
}

/// Los caracteres que suelen ir DETRÁS de un enlace en una frase, no dentro.
///
/// «Entra a https://sisol.mx.» lleva un punto final que es de la frase, no de la dirección, y con él
/// dentro el enlace se rompe. Igual con la coma, el punto y coma y el cierre de comillas.
const _colgantes = '.,;:!?«»"\'';

/// Parte un texto en trozos, marcando cuáles son enlaces.
///
/// Reconoce tres formas, que son las que la gente escribe de verdad en un aviso:
///
///   - `https://…` y `http://…`
///   - `www.…` sin protocolo, que es como se escribe a mano. Se le añade `https://` al abrirlo,
///     porque sin protocolo el navegador lo tomaría como una ruta relativa del propio sitio.
///   - un correo, que se abre con `mailto:`
///
/// Deliberadamente NO reconoce dominios a secas —«pasa por sisol.mx»— porque entonces cualquier
/// palabra con punto se volvería un enlace: «el archivo config.ini», «la versión 2.0», o una frase
/// sin espacio tras el punto. Un enlace de más que no lleva a ninguna parte es peor que uno de menos
/// que se puede copiar.
List<TrozoDeTexto> partirEnEnlaces(String texto) {
  if (texto.isEmpty) return const [];

  final re = RegExp(
    r'(?:https?://|www\.)[^\s<>"]+'
    r'|[\w.+%-]+@[\w-]+(?:\.[\w-]+)+',
    caseSensitive: false,
  );

  final trozos = <TrozoDeTexto>[];
  var cursor = 0;

  for (final m in re.allMatches(texto)) {
    var enlace = m.group(0)!;

    // Los signos que quedaron pegados al final son de la frase. Se devuelven al texto normal en lugar
    // de tirarlos: forman parte de lo que escribió la persona.
    var sobrante = '';
    while (enlace.isNotEmpty && _colgantes.contains(enlace[enlace.length - 1])) {
      sobrante = enlace[enlace.length - 1] + sobrante;
      enlace = enlace.substring(0, enlace.length - 1);
    }
    // Un paréntesis de cierre sólo cuelga si no se abrió dentro del propio enlace, que es legítimo:
    // los enlaces de Wikipedia los llevan.
    while (enlace.endsWith(')') && !enlace.contains('(')) {
      sobrante = ')$sobrante';
      enlace = enlace.substring(0, enlace.length - 1);
    }
    // Si al quitar lo colgante no queda nada utilizable, no era un enlace.
    if (enlace.length < 4) continue;

    if (m.start > cursor) {
      trozos.add(TrozoDeTexto(texto.substring(cursor, m.start)));
    }
    trozos.add(TrozoDeTexto(enlace, _destinoDe(enlace)));
    if (sobrante.isNotEmpty) trozos.add(TrozoDeTexto(sobrante));
    cursor = m.end;
  }

  if (cursor < texto.length) trozos.add(TrozoDeTexto(texto.substring(cursor)));
  return trozos;
}

String _destinoDe(String enlace) {
  final bajo = enlace.toLowerCase();
  if (bajo.startsWith('http://') || bajo.startsWith('https://')) return enlace;
  if (bajo.startsWith('www.')) return 'https://$enlace';
  return 'mailto:$enlace';
}

/// Texto de un aviso: seleccionable, y con los enlaces en los que se puede hacer clic.
///
/// ─── Por qué es un widget compartido ─────────────────────────────────────────
///
/// El cuerpo de un aviso se pinta en TRES sitios —la lista de Social, el banner de arriba y la
/// ventana emergente— y antes cada uno lo hacía a su manera: dos con un `Text` pelado y el diálogo
/// con un `SelectableText`. El resultado era que el mismo aviso se podía seleccionar en la ventana
/// emergente y no en Social, y el enlace no se podía pulsar en ninguno de los tres. Arreglarlo sólo
/// donde se reportó habría dejado las otras dos mitades del problema en pie.
///
/// ─── Por qué `SelectionArea` y no `SelectableText` ───────────────────────────
///
/// `SelectableText` gestiona los gestos él mismo, así que los `recognizer` de sus spans no llegan a
/// dispararse: el texto se selecciona pero el enlace no responde, que es la mitad del pedido.
/// `SelectionArea` envolviendo un `Text.rich` da las dos cosas, porque la selección la pone el
/// ancestro y el toque sigue siendo del span.
class TextoConEnlaces extends StatefulWidget {
  final String texto;
  final TextStyle? style;

  /// El color del enlace. Si se omite, el de marca del tema.
  final Color? colorEnlace;
  const TextoConEnlaces(this.texto, {super.key, this.style, this.colorEnlace});

  @override
  State<TextoConEnlaces> createState() => _TextoConEnlacesState();
}

class _TextoConEnlacesState extends State<TextoConEnlaces> {
  /// Un reconocedor por enlace, y hay que DESTRUIRLOS.
  ///
  /// `TapGestureRecognizer` retiene recursos: crearlos dentro de `build` los fuga en cada repintado,
  /// y en una lista de avisos que se repinta con cada cambio del almacén eso se acumula.
  final _gestos = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _limpiar();
    super.dispose();
  }

  void _limpiar() {
    for (final g in _gestos) {
      g.dispose();
    }
    _gestos.clear();
  }

  Future<void> _abrir(String destino) async {
    final uri = Uri.tryParse(destino);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      // Se avisa en lugar de callar: un clic que no hace nada parece que la aplicación se colgó.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir $destino')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final trozos = partirEnEnlaces(widget.texto);
    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final colorEnlace = widget.colorEnlace ?? Theme.of(context).colorScheme.primary;

    // Los reconocedores se rehacen en cada build, así que primero se destruyen los de la vuelta
    // anterior. Sin esto la fuga es la misma que crearlos en `build` sin más.
    _limpiar();

    return SelectionArea(
      child: Text.rich(
        TextSpan(
          children: [
            for (final t in trozos)
              if (!t.esEnlace)
                TextSpan(text: t.texto, style: base)
              else
                TextSpan(
                  text: t.texto,
                  style: base.copyWith(
                    color: colorEnlace,
                    decoration: TextDecoration.underline,
                    decorationColor: colorEnlace,
                  ),
                  // El cursor de mano: sin él no se ve que sea pulsable hasta que alguien lo intenta.
                  mouseCursor: SystemMouseCursors.click,
                  recognizer: () {
                    final g = TapGestureRecognizer()..onTap = () => _abrir(t.destino!);
                    _gestos.add(g);
                    return g;
                  }(),
                ),
          ],
        ),
      ),
    );
  }
}
