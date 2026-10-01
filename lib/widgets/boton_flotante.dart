import 'package:flutter/material.dart';

import '../theme/si_theme.dart';

/// Si la pantalla es de telefono: ahi la accion de crear va en el boton flotante y no en la barra.
///
/// Vale igual para la app que para la web abierta en un celular. En pantalla ancha se queda el
/// boton «+ Nuevo» de la barra.
bool esPantallaTelefono(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600;

/// Espacio a dejar al final de una lista para que el boton flotante no tape el ultimo renglon.
const double kEspacioBotonFlotante = 88;

/// El boton flotante de crear, igual en todas las paginas.
///
/// Se pone en `Scaffold.floatingActionButton` solo cuando [esPantallaTelefono]; con [visible] en
/// false no se pinta (p. ej. sin permiso de editar, o en una pestaña donde no se crea nada).
class BotonFlotanteNuevo extends StatelessWidget {
  const BotonFlotanteNuevo({
    super.key,
    required this.onPressed,
    required this.tooltip,
    this.icono = Icons.add,
  });

  final VoidCallback? onPressed;
  final String tooltip;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: tooltip,
      backgroundColor: c.brand,
      foregroundColor: Colors.white,
      elevation: 2,
      child: Icon(icono),
    );
  }
}

/// Un boton flotante chico para una segunda accion (p. ej. «Grupos» en BI), encima del de crear.
///
/// Va junto al principal con [BotonesFlotantes]. Lleva su propio `heroTag`: dos botones flotantes
/// con el mismo tag rompen la transicion entre paginas.
class BotonFlotanteSecundario extends StatelessWidget {
  const BotonFlotanteSecundario({
    super.key,
    required this.onPressed,
    required this.tooltip,
    required this.icono,
  });

  final VoidCallback? onPressed;
  final String tooltip;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return FloatingActionButton.small(
      heroTag: tooltip,
      onPressed: onPressed,
      tooltip: tooltip,
      backgroundColor: c.panel,
      foregroundColor: c.brand,
      elevation: 2,
      child: Icon(icono),
    );
  }
}

/// El secundario arriba y el de crear abajo, alineados a la derecha.
class BotonesFlotantes extends StatelessWidget {
  const BotonesFlotantes({super.key, required this.secundario, required this.principal});

  final Widget secundario;
  final Widget principal;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        secundario,
        const SizedBox(height: SiSpace.x3),
        principal,
      ],
    );
  }
}
