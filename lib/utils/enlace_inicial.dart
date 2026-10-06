/// Número de inventario que traía el enlace con el que se abrió la web (`?inv=INV-0001`, el QR de
/// la etiqueta de un equipo).
///
/// Se guarda en cuanto arranca la app: Flutter reescribe la dirección a `/` al cargar y el `?inv=`
/// desaparece antes de que se inicie sesión y se arme la navegación. `MainNavigation` lo usa una vez
/// y lo vacía.
String? equipoDelEnlace;
