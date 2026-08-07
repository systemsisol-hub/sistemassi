import 'package:flutter/material.dart';

import '../avisos_store.dart';
import '../theme/si_theme.dart';
import 'banner_avisos.dart' show colorDeNivel, etiquetaDeNivel;

/// La ventana emergente de un aviso.
///
/// Se separa del encolado ([mostrarAvisosEmergentes]) para poder pumpearla sola en una prueba: el
/// encolado necesita un `Navigator` y varias vueltas de reloj, y el contenido no.
class DialogoAviso extends StatelessWidget {
  const DialogoAviso({super.key, required this.aviso});

  final Aviso aviso;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final (color, fondo, icono) = colorDeNivel(c, aviso.nivel);

    return Dialog(
      backgroundColor: c.panel,
      insetPadding: const EdgeInsets.all(SiSpace.x6),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          // Un aviso largo no debe crecer más que la pantalla: sin tope, el botón de cerrar se queda
          // fuera y no hay forma de quitarlo.
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: fondo,
              padding: const EdgeInsets.all(SiSpace.x5),
              child: Row(
                children: [
                  Icon(icono, size: 22, color: color),
                  const SizedBox(width: SiSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(etiquetaDeNivel(aviso.nivel).toUpperCase(),
                            style: SiType.mono(
                                size: 9.5, color: color, letterSpacing: 0.8)),
                        const SizedBox(height: 2),
                        Text(aviso.titulo,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: c.ink)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(SiSpace.x5),
                child: SelectableText(aviso.cuerpo,
                    style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SiSpace.x5, 0, SiSpace.x5, SiSpace.x5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (aviso.insistirModal)
                    Expanded(
                      child: Text('Este aviso volverá a mostrarse',
                          style: TextStyle(fontSize: 11.5, color: c.ink3)),
                    ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Entendido'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Muestra los emergentes pendientes uno tras otro y acusa los que la persona confirmó.
///
/// ─── Decisiones que no son obvias ────────────────────────────────────────────
///
/// * `barrierDismissible: false`. Un aviso emergente existe para que se lea; cerrarlo con un clic
///   fuera lo convertiría en un estorbo que se quita sin mirar.
/// * Se acusa sólo si la persona apretó «Entendido», y sólo el canal MODAL: el banner del mismo aviso
///   sigue en pie. Si cerró con Escape, [AvisosStore.marcarMostrado] evita que reaparezca en esta
///   pantalla, pero el aviso sigue sin acuse y vuelve a la próxima. Acusar en los dos casos
///   convertiría un Escape accidental en un «ya lo vi» permanente.
/// * Se revisa `context.mounted` entre diálogos: entre uno y otro la persona puede haber cerrado
///   sesión, y seguir empujando ventanas sobre la pantalla de login sería un error.
Future<void> mostrarAvisosEmergentes(
  BuildContext context,
  AvisosStore store,
) async {
  for (final aviso in store.modalesPendientes) {
    if (!context.mounted) return;
    store.marcarMostrado(aviso.id);
    final confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DialogoAviso(aviso: aviso),
    );
    if (confirmado == true) {
      await store.marcarVisto(aviso.id, CanalAviso.modal);
    }
  }
}
