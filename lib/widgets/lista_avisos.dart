import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../avisos_store.dart';
import '../theme/si_theme.dart';
import 'banner_avisos.dart' show colorDeNivel, etiquetaDeNivel;
import 'texto_con_enlaces.dart';
import 'imagen_aviso.dart';

/// Los avisos vigentes para la tercera columna de Social, que hasta ahora decía «Próximamente».
///
/// Aquí NO se acusa nada. El banner y el emergente piden a la persona que los quite de en medio; el
/// muro es donde va a buscar lo que ya no está en pantalla, así que marcarlo como visto por pasar por
/// ahí vaciaría justo el lugar al que uno vuelve a consultar.
class ListaAvisos extends StatelessWidget {
  const ListaAvisos({super.key, required this.avisos});

  /// Los avisos de canal social, en cualquier orden: aquí se ordenan por gravedad.
  final List<Aviso> avisos;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final ordenados = [...avisos]..sort((a, b) => a.peso.compareTo(b.peso));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.campaign_outlined, size: 20, color: c.brand),
            const SizedBox(width: SiSpace.x2),
            Text('Avisos',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: c.ink)),
            const Spacer(),
            if (ordenados.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c.brand.withValues(alpha: 0.12),
                  borderRadius: SiRadius.rPill,
                ),
                child: Text('${ordenados.length}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: c.brand)),
              ),
          ],
        ),
        const SizedBox(height: SiSpace.x3),
        if (ordenados.isEmpty)
          Container(
            padding: const EdgeInsets.all(SiSpace.x6),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: SiRadius.rMd,
              border: Border.all(color: c.line),
            ),
            child: Column(
              children: [
                Icon(Icons.check_circle_outline, size: 28, color: c.ink4),
                const SizedBox(height: SiSpace.x2),
                Text('Sin avisos por ahora',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: c.ink3)),
              ],
            ),
          )
        else
          for (final aviso in ordenados) ...[
            _Tarjeta(aviso: aviso),
            const SizedBox(height: SiSpace.x3),
          ],
      ],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.aviso});

  final Aviso aviso;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final (color, fondo, icono) = colorDeNivel(c, aviso.nivel);

    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rMd,
        border: Border.all(color: c.line),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: fondo,
            padding: const EdgeInsets.symmetric(
                horizontal: SiSpace.x3, vertical: SiSpace.x2),
            child: Row(
              children: [
                Icon(icono, size: 15, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(aviso.titulo,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: c.ink)),
                ),
                Text(etiquetaDeNivel(aviso.nivel),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(SiSpace.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (aviso.imagenUrl != null) ...[
                  // Más baja que en el emergente: en la columna de Social conviven varias tarjetas y
                  // una imagen alta dejaría las demás fuera de vista. Se toca para verla completa.
                  ImagenAviso(url: aviso.imagenUrl!, altoMaximo: 160),
                  const SizedBox(height: SiSpace.x2),
                ],
                // Seleccionable y con los enlaces pulsables; ver `texto_con_enlaces.dart`. Era un
                // `Text` pelado, y es el sitio donde se reporto: un aviso con un enlace no se podia
                // ni pulsar ni copiar.
                TextoConEnlaces(aviso.cuerpo,
                    style:
                        TextStyle(fontSize: 12.5, height: 1.45, color: c.ink2)),
                if (aviso.hasta != null) ...[
                  const SizedBox(height: SiSpace.x2),
                  Text('Vigente hasta el ${_fecha(aviso.hasta!)}',
                      style: TextStyle(fontSize: 11, color: c.ink4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Sin `intl` inicializado el formato con nombre de mes lanza. En el muro un aviso vale más que su
  // fecha bonita, así que se cae a números en lugar de tumbar la columna.
  String _fecha(DateTime d) {
    try {
      return DateFormat('d \'de\' MMMM', 'es_MX').format(d);
    } catch (_) {
      return '${d.day}/${d.month}/${d.year}';
    }
  }
}
