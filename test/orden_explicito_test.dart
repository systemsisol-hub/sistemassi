import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Que ninguna consulta ordene sin decir en qué dirección.
///
/// ─── Por qué existe ────────────────────────────────────────────────────────
///
/// En `postgrest-dart` la firma es:
///
///   order(String column, {bool ascending = false, ...})
///
/// O sea que **`.order('nombre')` ordena Z→A**. Es lo contrario de lo que cualquiera espera al
/// leerlo, y estaba en las 21 llamadas del proyecto: el directorio, las contraseñas, los horarios,
/// las herramientas y los desarrollos salían todos al revés.
///
/// Lo reportó el usuario el 03/09/2026 —«los veo al reves»— y sobre la lista de desarrollos, que es
/// la que estaba mirando. Las otras veinte llevaban igual desde siempre y nadie las había
/// relacionado con esto.
///
/// La regla no es «usa ascendente»: es **dilo**. Hay sitios donde descendente es lo correcto —la
/// bitácora del checador se lee de lo más reciente hacia atrás— y ahí también hay que escribirlo,
/// porque una llamada que se apoya en un valor por omisión contraintuitivo es una trampa esperando
/// al siguiente que la lea.
///
/// Se lee el CÓDIGO FUENTE, como `menu_agrupado_test.dart`: no hay forma de comprobar esto
/// levantando widgets, y el fallo es invisible hasta que alguien mira una lista y la ve al revés.
void main() {
  test('ninguna llamada a .order() se queda sin ascending', () {
    final sinDireccion = <String>[];
    final conDireccion = <String>[];

    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lineas = f.readAsLinesSync();
      for (var i = 0; i < lineas.length; i++) {
        final l = lineas[i];
        if (!l.contains('.order(')) continue;
        // Los comentarios no son código.
        if (l.trimLeft().startsWith('//')) continue;

        // La dirección puede venir en la misma línea o en la siguiente, si la llamada se partió.
        final ventana = [l, if (i + 1 < lineas.length) lineas[i + 1]].join(' ');
        final donde = '${f.path.replaceAll(r'\', '/')}:${i + 1}';
        if (ventana.contains('ascending:')) {
          conDireccion.add(donde);
        } else {
          sinDireccion.add('$donde  ->  ${l.trim()}');
        }
      }
    }

    expect(conDireccion, isNotEmpty,
        reason: 'si no encontró ninguna llamada, la prueba no está probando nada');

    expect(sinDireccion, isEmpty,
        reason: 'En postgrest-dart `ascending` vale FALSE por omisión, así que estas ordenan Z→A '
            'sin decirlo. Agrega `ascending: true` (o `false`, si eso es lo que quieres):\n'
            '${sinDireccion.join('\n')}');
  });
}
