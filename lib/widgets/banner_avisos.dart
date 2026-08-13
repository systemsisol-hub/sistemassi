import 'package:flutter/material.dart';

import 'texto_con_enlaces.dart';

import '../avisos_store.dart';
import '../theme/si_theme.dart';

/// La franja de avisos que va bajo la barra de navegación.
///
/// Recibe la lista y un callback, no el almacén: así se puede pumpear en una prueba sin sesión ni
/// Supabase. Quien lo conecta al almacén es el shell.
///
/// ─── Con varios avisos a la vez ──────────────────────────────────────────────
///
/// Se muestra uno, el más grave, con un contador para desplegar el resto. Apilar franjas empuja la
/// página hacia abajo —con tres avisos se come 150px de alto antes de que empiece el contenido— y a
/// partir de la segunda la gente deja de leerlas. El contador conserva el acceso sin el costo.
class BannerAvisos extends StatefulWidget {
  const BannerAvisos({
    super.key,
    required this.avisos,
    required this.alDescartar,
  });

  /// Los avisos de banner sin descartar, en cualquier orden: aquí se ordenan por gravedad.
  final List<Aviso> avisos;

  final void Function(String id) alDescartar;

  @override
  State<BannerAvisos> createState() => _BannerAvisosState();
}

class _BannerAvisosState extends State<BannerAvisos> {
  bool _desplegado = false;

  @override
  Widget build(BuildContext context) {
    if (widget.avisos.isEmpty) return const SizedBox.shrink();

    final ordenados = [...widget.avisos]..sort((a, b) => a.peso.compareTo(b.peso));
    final visibles = _desplegado ? ordenados : ordenados.take(1).toList();
    final ocultos = ordenados.length - visibles.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final aviso in visibles)
          _Franja(
            aviso: aviso,
            restantes: aviso == visibles.last ? ocultos : 0,
            alDescartar: () => widget.alDescartar(aviso.id),
            alDesplegar: () => setState(() => _desplegado = true),
          ),
      ],
    );
  }
}

class _Franja extends StatelessWidget {
  const _Franja({
    required this.aviso,
    required this.restantes,
    required this.alDescartar,
    required this.alDesplegar,
  });

  final Aviso aviso;
  final int restantes;
  final VoidCallback alDescartar;
  final VoidCallback alDesplegar;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final (color, fondo, icono) = colorDeNivel(c, aviso.nivel);

    return Container(
      decoration: BoxDecoration(
        color: fondo,
        border: Border(
          bottom: BorderSide(color: c.line),
          // Una barra de color a la izquierda: el fondo teñido es suave a propósito —para no competir
          // con la página— y por sí solo no distingue bien amarillo de verde en pantallas malas.
          left: BorderSide(color: color, width: 3),
        ),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: SiSpace.x4, vertical: SiSpace.x2),
      child: Row(
        children: [
          Icon(icono, size: 16, color: color),
          const SizedBox(width: SiSpace.x2),
          Expanded(
            child: Wrap(
              spacing: SiSpace.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(aviso.titulo,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.ink)),
                // El mismo widget que en Social y en la ventana emergente: el aviso es el mismo,
                // asi que se comporta igual en los tres sitios.
                TextoConEnlaces(aviso.cuerpo,
                    style: TextStyle(fontSize: 12.5, color: c.ink2)),
              ],
            ),
          ),
          if (restantes > 0) ...[
            const SizedBox(width: SiSpace.x2),
            TextButton(
              onPressed: alDesplegar,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('+$restantes más',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: c.brand)),
            ),
          ],
          IconButton(
            onPressed: alDescartar,
            icon: const Icon(Icons.close, size: 15),
            color: c.ink3,
            tooltip: 'Descartar este aviso',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

/// Color, fondo e icono de cada nivel.
///
/// Sale del tema y no de `Colors.red` y compañía: `SiColors` trae una variante para modo oscuro, y un
/// rojo fijo sobre fondo oscuro se ve apagado. Compartido por los tres widgets de avisos para que el
/// mismo nivel no salga de dos colores según dónde aparezca.
(Color, Color, IconData) colorDeNivel(SiColors c, NivelAviso nivel) =>
    switch (nivel) {
      NivelAviso.critico => (c.danger, c.dangerTint, Icons.error_outline),
      NivelAviso.advertencia => (c.warn, c.warnTint, Icons.warning_amber_rounded),
      NivelAviso.info => (c.success, c.successTint, Icons.info_outline),
    };

/// Cómo se llama cada nivel en pantalla.
String etiquetaDeNivel(NivelAviso nivel) => switch (nivel) {
      NivelAviso.critico => 'Crítico',
      NivelAviso.advertencia => 'Advertencia',
      NivelAviso.info => 'Informativo',
    };
