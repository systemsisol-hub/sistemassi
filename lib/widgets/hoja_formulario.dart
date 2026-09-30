import 'package:flutter/material.dart';

import '../theme/si_theme.dart';

/// Abre un formulario como hoja que sube desde abajo, al estilo de iOS.
///
/// Es la forma de los formularios de crear o editar en toda la aplicacion. Las confirmaciones
/// sencillas («¿Eliminar?») siguen siendo alertas centradas, que es como las muestra iOS.
///
/// No se cierra tocando fuera ni arrastrando: un formulario a medio llenar se perderia de un
/// descuido. Se sale con «Cancelar».
Future<T?> mostrarHojaFormulario<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    // En pantalla ancha no se estira de lado a lado: queda del ancho de un formulario.
    constraints: const BoxConstraints(maxWidth: 720),
    builder: builder,
  );
}

/// El cuerpo de una hoja de formulario: encabezado «Cancelar | titulo | Guardar» y el contenido
/// con desplazamiento.
///
/// [onGuardar] en null deja el boton apagado (falta un dato, o ya se esta guardando).
/// Con [guardando] el boton muestra un indicador en lugar del texto.
class HojaFormulario extends StatelessWidget {
  const HojaFormulario({
    super.key,
    required this.titulo,
    required this.child,
    this.onGuardar,
    this.textoGuardar = 'Guardar',
    this.guardando = false,
    this.onCancelar,
    this.pie,
    this.relleno = const EdgeInsets.all(SiSpace.x5),
  });

  final String titulo;
  final Widget child;
  final VoidCallback? onGuardar;
  final String textoGuardar;
  final bool guardando;

  /// Por omision cierra la hoja sin devolver nada.
  final VoidCallback? onCancelar;

  /// Un renglon fijo bajo el contenido, fuera del desplazamiento (p. ej. por que no se puede
  /// guardar todavia).
  final Widget? pie;

  final EdgeInsetsGeometry relleno;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final mq = MediaQuery.of(context);

    // Con el teclado abierto la hoja sube: se le pone tope para que el encabezado no quede bajo
    // la hora. El margen de arriba se lee de la pantalla porque dentro de la hoja MediaQuery lo
    // trae en 0.
    final arriba = MediaQueryData.fromView(View.of(context)).padding.top;
    final disponible =
        mq.size.height - mq.viewInsets.bottom - arriba - SiSpace.x3;
    final tope = mq.size.height * 0.92;
    final alto = disponible < tope ? disponible : tope;

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: alto),
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    vertical: SiSpace.x2, horizontal: SiSpace.x2),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: guardando
                          ? null
                          : (onCancelar ?? () => Navigator.of(context).pop()),
                      child: Text('Cancelar',
                          style: TextStyle(fontSize: 15, color: c.ink3)),
                    ),
                    Expanded(
                      child: Text(
                        titulo,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: c.ink),
                      ),
                    ),
                    TextButton(
                      onPressed: guardando ? null : onGuardar,
                      child: guardando
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: c.brand))
                          : Text(
                              textoGuardar,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      onGuardar == null ? c.ink4 : c.brand),
                            ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: relleno,
                  child: child,
                ),
              ),
              if (pie != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: SiSpace.x5, vertical: SiSpace.x3),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.line)),
                  ),
                  child: pie,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
