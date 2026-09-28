import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/incidencias_page.dart';

/// «El periodo anterior» de Mis incidencias: el último periodo que la persona ya cumplió.
///
/// Pedido el 28/09/2026 como «actualmente sería la 2025 - 2026». Lo es para quien cumple años de
/// servicio entre enero y el día de hoy; para quien los cumple más adelante en el año, todavía es
/// el de un año antes.
void main() {
  final hoy = DateTime(2026, 9, 28);

  test('aniversario ya pasado este año: 2025 - 2026', () {
    expect(periodoCumplido(DateTime(2014, 3, 10), hoy), '2025 - 2026');
  });

  test('aniversario todavía por venir este año: 2024 - 2025', () {
    expect(periodoCumplido(DateTime(2014, 11, 15), hoy), '2024 - 2025');
  });

  test('el mismo día del aniversario ya cuenta como cumplido', () {
    expect(periodoCumplido(DateTime(2020, 9, 28), hoy), '2025 - 2026');
    expect(periodoCumplido(DateTime(2020, 9, 29), hoy), '2024 - 2025');
  });

  test('antes del primer año no hay periodo cumplido', () {
    expect(periodoCumplido(DateTime(2026, 1, 10), hoy), isNull);
    expect(periodoCumplido(DateTime(2025, 9, 29), hoy), isNull);
  });

  test('justo al cumplir el primer año', () {
    expect(periodoCumplido(DateTime(2025, 9, 28), hoy), '2025 - 2026');
  });

  test('sin fecha de ingreso', () {
    expect(periodoCumplido(null, hoy), isNull);
  });
}
