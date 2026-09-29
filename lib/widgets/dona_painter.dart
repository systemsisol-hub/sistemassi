import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dona del semáforo, la del Panel y la de Registros del Checador. Se dibuja a mano en lugar de
/// agregar una librería de gráficas: son tres segmentos, y el proyecto ya arrastra 82 paquetes desactualizados.
class DonaPainter extends CustomPainter {
  DonaPainter({required this.valores, required this.fondo});

  final List<(int, Color)> valores;
  final Color fondo;

  @override
  void paint(Canvas canvas, Size size) {
    final total = valores.fold<int>(0, (a, b) => a + b.$1);
    final centro = Offset(size.width / 2, size.height / 2);
    final radio = math.min(size.width, size.height) / 2 - 6;
    final grosor = radio * 0.32;
    final rect = Rect.fromCircle(center: centro, radius: radio - grosor / 2);

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..color = fondo;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (total == 0) return;

    // Arranca arriba y avanza en el sentido del reloj.
    var inicio = -math.pi / 2;
    for (final (n, color) in valores) {
      if (n == 0) continue;
      final barrido = math.pi * 2 * (n / total);
      canvas.drawArc(
        rect,
        inicio,
        // Un pelo menos para dejar una separación visible entre segmentos.
        barrido - 0.02,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = grosor
          ..strokeCap = StrokeCap.butt
          ..color = color,
      );
      inicio += barrido;
    }
  }

  @override
  bool shouldRepaint(DonaPainter old) =>
      old.valores != valores || old.fondo != fondo;
}
