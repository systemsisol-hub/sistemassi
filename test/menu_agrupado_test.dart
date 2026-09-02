import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El menú lateral se pinta desde DOS listas que tienen que coincidir, y nada lo comprobaba.
///
/// `_buildPages()` decide qué páginas existen; `_navGroups` decide en qué sección va cada una. Y
/// `_buildGroupedItems` sólo pinta las que están en un grupo: una página que exista pero no figure
/// en ninguna sección **desaparece del menú sin dar ningún error**.
///
/// Pasó el 28/08/2026 con SOL. Se agregó a `_buildPages()`, se compiló sin errores, se desplegó, y
/// no estaba en el menú. El código sí estaba en el paquete servido —se comprobó descargando el
/// `main.dart.js`—; lo que faltaba era el renglón en `_navGroups`. Media hora buscando en la caché,
/// en los permisos y en el despliegue un fallo que eran dos listas separándose.
///
/// Se lee el FUENTE en lugar de montar el widget, por lo mismo que los arneses de las funciones:
/// así la prueba no puede quedar verificando una copia vieja de las listas.
void main() {
  final fuente = File('lib/main_navigation.dart').readAsStringSync();

  /// Los títulos de `_navGroups`, con la sección en la que está cada uno.
  Map<String, String> seccionPorTitulo() {
    final bloque = RegExp(r'_navGroups = <\(String, List<String>\)>\[(.*?)\n\];', dotAll: true)
        .firstMatch(fuente);
    expect(bloque, isNotNull,
        reason: 'no se encontró `_navGroups` en main_navigation.dart');

    final mapa = <String, String>{};
    final grupo = RegExp(r"\(\s*'([^']+)'\s*,\s*\[([^\]]*)\]\s*\)");
    for (final m in grupo.allMatches(bloque!.group(1)!)) {
      final seccion = m.group(1)!;
      for (final t in RegExp(r"'([^']+)'").allMatches(m.group(2)!)) {
        final titulo = t.group(1)!;
        expect(mapa.containsKey(titulo), isFalse,
            reason: '«$titulo» está en dos secciones: ${mapa[titulo]} y $seccion');
        mapa[titulo] = seccion;
      }
    }
    return mapa;
  }

  /// Los títulos que `_buildPages()` puede añadir. Se toman los literales `'title': '...'`.
  Set<String> titulosDePaginas() {
    final encontrados = RegExp(r"'title':\s*'([^']+)'").allMatches(fuente);
    return encontrados.map((m) => m.group(1)!).toSet();
  }

  test('toda página del menú pertenece a una sección', () {
    final secciones = seccionPorTitulo();
    final paginas = titulosDePaginas();

    final huerfanas = paginas.where((p) => !secciones.containsKey(p)).toList()..sort();
    expect(huerfanas, isEmpty,
        reason: 'Estas páginas existen pero NO están en `_navGroups`, así que no se pintan '
            'en el menú y nadie las va a encontrar: ${huerfanas.join(', ')}');
  });

  test('ninguna sección nombra una página que no existe', () {
    final secciones = seccionPorTitulo();
    final paginas = titulosDePaginas();

    // Un título en `_navGroups` que ya no corresponda a ninguna página no rompe nada hoy, pero es
    // el rastro de un borrado a medias y lo siguiente que se agregue ahí puede no aparecer.
    final sobrantes = secciones.keys.where((s) => !paginas.contains(s)).toList()..sort();
    expect(sobrantes, isEmpty,
        reason: '`_navGroups` nombra páginas que ya no existen: ${sobrantes.join(', ')}');
  });
}
