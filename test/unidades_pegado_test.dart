import 'package:flutter_test/flutter_test.dart';
import 'package:sistemassi/unidades_pegado.dart';

/// El encabezado REAL del archivo «DISPONIBLES AG117 SEPTIEMBRE 1.xlsx».
const encabezado =
    'Torre\tNivel\tTipo\tTipologia\t# Depto\tNumero\tVista\tAREA INTERIOR TECHADA M2\t'
    'AREA EXTERIOR TECHADA M2\tJARDIN TERRAZA NO TECHADA M2\tTOTAL INTERIOR M2\tM2 TOTAL\t'
    'Precio 2026 Redondeado Sept (Manual)';

/// Filas reales del archivo, copiadas tal cual —con el ruido de coma flotante incluido—.
const filaA103 =
    'A\t1\tDepto\tB Lock off\tA-103\tAG008\tCalle\t96.91\t16.82\t\t113.72999999999999\t113.72999999999999\t9310000';
const filaRoof =
    'A\t3 PH\tROOF\tROOF\tROOF\tAG110\tJardin\t\t\t59\t0\t59\t1770000';
const filaA01 =
    'A\tPB\tDepto\tC1\tA-01\tAG004\tJardin\t76\t7.56\t15.61\t83.56\t99.17\t7460000';

void main() {
  group('leerPegado', () {
    test('lee una fila real con el encabezado del archivo', () {
      final r = leerPegado('$encabezado\n$filaA103');
      expect(r.errores, isEmpty);
      expect(r.traiaEncabezado, isTrue);
      expect(r.unidades, hasLength(1));

      final u = r.unidades.single;
      expect(u.numero, 'AG008');
      expect(u.depto, 'A-103');
      expect(u.torre, 'A');
      expect(u.nivel, '1');
      expect(u.tipo, 'Depto');
      expect(u.tipologia, 'B Lock off');
      expect(u.vista, 'Calle');
      expect(u.m2InteriorTechada, 96.91);
      expect(u.m2ExteriorTechada, 16.82);
      expect(u.m2JardinTerraza, isNull);
      expect(u.precio, 9310000);
    });

    test('el ruido de coma flotante se redondea a dos decimales', () {
      // 113.72999999999999 es lo que trae el Excel. Sin redondear, ese ruido llega a la base.
      final r = leerPegado('$encabezado\n$filaA103');
      // Las columnas calculadas se ignoran, así que el ruido sólo podría entrar por las de datos.
      // Se comprueba con una que sí lo traiga.
      final conRuido = leerPegado('$encabezado\n'
          'C\t1\tDepto\tA\tC-104\tAG047\tColindancia\t50.94\t7.41\t\t58.349999999999994\t58.349999999999994\t4950000');
      expect(conRuido.unidades.single.m2InteriorTechada, 50.94);
      expect(r.unidades.single.m2InteriorTechada, 96.91);
    });

    test('las dos columnas calculadas NO se leen', () {
      final r = leerPegado('$encabezado\n$filaA01');
      expect(r.columnasIgnoradas, isEmpty,
          reason: 'las calculadas se ignoran a propósito, no son columnas desconocidas');

      final fila = r.unidades.single.aFila('un-id');
      expect(fila.containsKey('m2_total'), isFalse,
          reason: 'es columna generada: Postgres rechaza el insert si se manda');
      expect(fila.containsKey('m2_total_interior'), isFalse);
      expect(fila.containsKey('precio_m2'), isFalse);
    });

    test('el nombre de la columna del precio cambia cada mes y sigue funcionando', () {
      // Es «Sept» en este archivo. En octubre será otro, y amarrarse al texto exacto habría hecho
      // que la carga del mes siguiente fallara sin razón aparente.
      for (final nombre in [
        'Precio 2026 Redondeado Sept (Manual)',
        'Precio 2026 Redondeado Oct (Manual)',
        'PRECIO LISTA',
        'Precio',
      ]) {
        final enc = encabezado.replaceAll(
            'Precio 2026 Redondeado Sept (Manual)', nombre);
        final r = leerPegado('$enc\n$filaA103');
        expect(r.unidades.single.precio, 9310000, reason: 'falló con «$nombre»');
      }
    });

    test('una azotea trae sólo jardín y se lee sin inventar los otros metros', () {
      final r = leerPegado('$encabezado\n$filaRoof');
      final u = r.unidades.single;
      expect(u.numero, 'AG110');
      expect(u.tipo, 'ROOF');
      expect(u.m2InteriorTechada, isNull);
      expect(u.m2ExteriorTechada, isNull);
      expect(u.m2JardinTerraza, 59);
      expect(u.precio, 1770000);
    });

    test('sin encabezado usa el orden del archivo y no se come la primera fila', () {
      final r = leerPegado('$filaA01\n$filaA103');
      expect(r.traiaEncabezado, isFalse);
      expect(r.unidades.map((u) => u.numero), ['AG004', 'AG008']);
    });

    test('el precio se entiende con signo y comas', () {
      final base = filaA103.replaceAll('9310000', r'$9,310,000.00');
      final r = leerPegado('$encabezado\n$base');
      expect(r.errores, isEmpty);
      expect(r.unidades.single.precio, 9310000);
    });

    test('un número repetido dentro del pegado se reporta, no se guarda', () {
      // Si pasara, la base rechazaría el lote entero por la restricción de unicidad y el mensaje
      // no diría cuál fue.
      final r = leerPegado('$encabezado\n$filaA103\n$filaA103');
      expect(r.unidades, hasLength(1));
      expect(r.errores, hasLength(1));
      expect(r.errores.single.motivo, contains('AG008'));
      expect(r.errores.single.motivo, contains('repetido'));
    });

    test('una fila sin número y una sin precio se reportan por separado', () {
      // Se vacían las DOS columnas de clave: con sólo `Numero` en blanco, el `Depto` toma su
      // lugar y la fila es válida —que es lo que comprueba la prueba de abajo—.
      final sinNumero =
          filaA01.replaceAll('\tAG004\t', '\t\t').replaceAll('\tA-01\t', '\t\t');
      final sinPrecio = filaA103.replaceAll('\t9310000', '\t');
      final r = leerPegado('$encabezado\n$sinNumero\n$sinPrecio');
      expect(r.unidades, isEmpty);
      expect(r.errores, hasLength(2));
      expect(r.errores[0].motivo, contains('sin número'));
      expect(r.errores[1].motivo, contains('no trae precio'));
      expect(r.errores[0].linea, 2, reason: 'la línea es la del texto, contando el encabezado');
      expect(r.errores[1].linea, 3);
    });

    test('si no hay columna Numero, el Depto es la clave', () {
      // Muchas listas identifican la unidad sólo por su número de departamento. Dentro de un
      // desarrollo eso identifica igual de bien que un código interno.
      final r = leerPegado('Torre\tNivel\tTipologia\t# Depto\tVista\tPrecio\n'
          'A\t1\tB Lock off\tA-103\tCalle\t9310000');
      expect(r.errores, isEmpty);
      expect(r.unidades.single.numero, 'A-103');
      expect(r.unidades.single.depto, 'A-103');
    });

    test('cuando vienen las dos columnas, manda Numero', () {
      final r = leerPegado('$encabezado\n$filaA103');
      expect(r.unidades.single.numero, 'AG008');
      expect(r.unidades.single.depto, 'A-103');
    });

    test('columnas en otro orden, y una de sobra', () {
      // Con encabezado el orden no importa, y lo que no se reconoce se REPORTA en lugar de
      // guardarse en la columna equivocada.
      final r = leerPegado(
          'Numero\tPrecio\tVista\tTorre\tNivel\tTipologia\tVendedor\t# Depto\n'
          'AG008\t9310000\tCalle\tA\t1\tB Lock off\tRodrigo\tA-103');
      expect(r.errores, isEmpty);
      expect(r.columnasIgnoradas, ['Vendedor']);
      final u = r.unidades.single;
      expect(u.numero, 'AG008');
      expect(u.depto, 'A-103');
      expect(u.vista, 'Calle');
      expect(u.precio, 9310000);
    });

    test('acentos y mayúsculas en el encabezado', () {
      final r = leerPegado('TORRE\tNIVEL\tTIPOLOGÍA\tNÚMERO\tVISTA\tPRECIO DE LISTA\n'
          'A\t1\tB Lock off\tAG008\tCalle\t9310000');
      expect(r.errores, isEmpty);
      expect(r.unidades.single.numero, 'AG008');
      expect(r.unidades.single.tipologia, 'B Lock off');
    });

    test('una lista de CASAS todavía no se reconoce, y falla diciéndolo', () {
      // Documenta el límite a propósito. «Manzana 5 Lote 12» no se puede convertir en clave sin
      // ver una lista real: el lote 12 existe en cada manzana. Fallar claro es mejor que cargar
      // trescientas casas con la clave equivocada.
      final r = leerPegado(
          'Manzana\tLote\tModelo\tM2 Terreno\tM2 Construccion\tPrecio\n'
          '5\t12\tJade 3R\t160\t142.5\t3850000');
      expect(r.unidades, isEmpty);
      expect(r.errores.single.motivo, contains('sin número'));
    });

    test('el número se guarda en mayúsculas', () {
      final r = leerPegado('$encabezado\n${filaA103.replaceAll('AG008', 'ag008')}');
      expect(r.unidades.single.numero, 'AG008');
    });

    test('pegar algo sin tabuladores lo dice en lugar de partir por coma', () {
      // Partir por coma convertiría «7,460,000» en tres celdas.
      final r = leerPegado('A,PB,Depto,C1,A-01,AG004,Jardin,76,7.56,15.61,83.56,99.17,7460000');
      expect(r.unidades, isEmpty);
      expect(r.errores.single.motivo, contains('copia las filas desde Excel'));
    });

    test('acepta punto y coma', () {
      final r = leerPegado(encabezado.replaceAll('\t', ';') +
          '\n' +
          filaA103.replaceAll('\t', ';'));
      expect(r.errores, isEmpty);
      expect(r.unidades.single.numero, 'AG008');
    });

    test('texto vacío no revienta', () {
      final r = leerPegado('   \n\n  ');
      expect(r.vacio, isTrue);
      expect(r.errores, isEmpty);
    });

    test('renglones en blanco entre filas se ignoran', () {
      final r = leerPegado('$encabezado\n\n$filaA01\n\n\n$filaA103\n');
      expect(r.errores, isEmpty);
      expect(r.unidades, hasLength(2));
    });
  });

  group('compararInventario', () {
    Map<String, dynamic> enBase(String numero,
            {num? precio,
            String estatus = 'DISPONIBLE',
            String? depto = 'A-103',
            String? torre = 'A',
            String? nivel = '1',
            String? tipo = 'Depto',
            String? tipologia = 'B Lock off',
            String? vista = 'Calle',
            num? interior = 96.91,
            num? exterior = 16.82,
            num? jardin}) =>
        {
          'numero': numero,
          'precio': precio,
          'estatus': estatus,
          'depto': depto,
          'torre': torre,
          'nivel': nivel,
          'tipo': tipo,
          'tipologia': tipologia,
          'vista': vista,
          'm2_interior_techada': interior,
          'm2_exterior_techada': exterior,
          'm2_jardin_terraza': jardin,
        };

    test('una unidad que no está en la base es nueva', () {
      final p = leerPegado('$encabezado\n$filaA103').unidades;
      final r = compararInventario(p, []);
      expect(r.nuevas.map((u) => u.numero), ['AG008']);
      expect(r.cambiosDePrecio, isEmpty);
      expect(r.desaparecidas, isEmpty);
    });

    test('idéntica no aparece como cambio', () {
      final p = leerPegado('$encabezado\n$filaA103').unidades;
      final r = compararInventario(p, [enBase('AG008', precio: 9310000)]);
      expect(r.sinNovedades, isTrue);
      expect(r.sinCambio, 1);
    });

    test('un precio distinto se reporta con el anterior y la diferencia', () {
      final p = leerPegado('$encabezado\n$filaA103').unidades;
      final r = compararInventario(p, [enBase('AG008', precio: 9000000)]);
      expect(r.cambiosDePrecio, hasLength(1));
      final c = r.cambiosDePrecio.single;
      expect(c.numero, 'AG008');
      expect(c.anterior, 9000000);
      expect(c.nuevo, 9310000);
      expect(c.diferencia, 310000);
    });

    test('la que ya no viene en la lista aparece como desaparecida', () {
      final p = leerPegado('$encabezado\n$filaA103').unidades;
      final r = compararInventario(
          p, [enBase('AG008', precio: 9310000), enBase('AG010', precio: 6200000)]);
      expect(r.desaparecidas.map((u) => u['numero']), ['AG010']);
    });

    test('una ya marcada vendida NO se reporta como desaparecida cada mes', () {
      // Repetirla mes con mes taparía lo que sí cambió.
      final p = leerPegado('$encabezado\n$filaA103').unidades;
      final r = compararInventario(p, [
        enBase('AG008', precio: 9310000),
        enBase('AG010', precio: 6200000, estatus: 'VENDIDO'),
      ]);
      expect(r.desaparecidas, isEmpty);
    });

    test('una marcada vendida que REAPARECE en la lista es un cambio', () {
      final p = leerPegado('$encabezado\n$filaA103').unidades;
      final r = compararInventario(
          p, [enBase('AG008', precio: 9310000, estatus: 'VENDIDO')]);
      expect(r.cambiosDeDatos.map((u) => u.numero), ['AG008'],
          reason: 'volver a estar disponible es de los cambios más importantes');
      expect(r.sinNovedades, isFalse);
    });

    test('un cambio de vista o tipología se detecta', () {
      final p = leerPegado('$encabezado\n$filaA103').unidades;
      final r = compararInventario(
          p, [enBase('AG008', precio: 9310000, vista: 'Jardin')]);
      expect(r.cambiosDeDatos.map((u) => u.numero), ['AG008']);
      expect(r.cambiosDePrecio, isEmpty, reason: 'el precio no cambió');
    });

    test('el número se compara sin importar mayúsculas', () {
      final p = leerPegado('$encabezado\n$filaA103').unidades;
      final r = compararInventario(p, [enBase('ag008', precio: 9310000)]);
      expect(r.nuevas, isEmpty);
      expect(r.sinCambio, 1);
    });

    test('un precio nulo en la base cuenta como cambio, con anterior desconocido', () {
      final p = leerPegado('$encabezado\n$filaA103').unidades;
      final r = compararInventario(p, [enBase('AG008', precio: null)]);
      expect(r.cambiosDePrecio.single.anterior, isNull);
      expect(r.cambiosDePrecio.single.diferencia, isNull);
    });
  });
}
