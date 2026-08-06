import 'package:flutter/material.dart';

import '../ai_page.dart';
import '../asistente_store.dart';
import '../theme/si_theme.dart';

/// Panel lateral del asistente, con su encabezado y el chat dentro.
///
/// Se monta **como hermano del área de páginas**, no dentro de ella. El shell pinta la página con
/// `Expanded(child: currentPage['widget'])`, así que todo lo que viva ahí adentro se destruye al
/// cambiar de página. Colgado del shell, el panel sobrevive la navegación.
///
/// La conversación en sí vive en [AsistenteStore], de modo que el panel y la página completa de IA
/// muestran el mismo hilo, y el contenido aguantaría incluso si este widget se reconstruyera.
class AsistentePanel extends StatelessWidget {
  const AsistentePanel({
    super.key,
    required this.role,
    required this.permissions,
    this.ancho,
  });

  final String role;
  final Map<String, dynamic> permissions;

  /// Ancho fijo en escritorio. En móvil se pasa null y ocupa todo.
  final double? ancho;

  static const double anchoEscritorio = 380;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final store = AsistenteStore.instancia;

    final contenido = Column(
      children: [
        Container(
          height: SiLayout.headerHeight,
          padding: const EdgeInsets.only(left: SiSpace.x4, right: SiSpace.x2),
          decoration: BoxDecoration(
            color: c.panel,
            border: Border(bottom: BorderSide(color: c.line, width: 1)),
          ),
          child: Row(
            children: [
              Icon(Icons.smart_toy_outlined, size: 17, color: c.brand),
              const SizedBox(width: SiSpace.x2),
              Text('Soli',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
              const Spacer(),
              // Limpiar sólo aparece con conversación: un botón que no hace nada invita a
              // presionarlo para averiguar qué hace.
              ListenableBuilder(
                listenable: store,
                builder: (context, _) => store.vacia
                    ? const SizedBox.shrink()
                    : IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Nueva conversación',
                        icon: Icon(Icons.add_comment_outlined,
                            size: 17, color: c.ink3),
                        onPressed: store.limpiarConversacion,
                      ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Cerrar',
                icon: Icon(Icons.close, size: 18, color: c.ink3),
                onPressed: store.cerrarPanel,
              ),
            ],
          ),
        ),
        Expanded(
          child: AiPage(
            role: role,
            permissions: permissions,
            compacto: true,
          ),
        ),
      ],
    );

    return Container(
      width: ancho,
      decoration: BoxDecoration(
        color: c.bg,
        border: ancho == null
            ? null
            : Border(left: BorderSide(color: c.line, width: 1)),
      ),
      child: contenido,
    );
  }
}
