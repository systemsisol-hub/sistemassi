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

    test('una lista de CASAS carga, y la manzana entra en la clave', () {
      // El lote 12 existe en cada manzana, así que el lote solo no puede ser la clave. La escalera
      // lo resuelve midiendo: con dos manzanas que repiten el lote 12, sube a manzana + lote.
      final r = leerPegado(
          'Manzana\tLote\tModelo\tM2 Terreno\tM2 Construccion\tPrecio\n'
          '5\t12\tJade 3R\t160\t142.5\t3850000\n'
          '5\t13\tJade 3R\t160\t142.5\t3850000\n'
          '6\t12\tAgata 2R\t150\t120\t3200000');
      expect(r.errores, isEmpty);
      expect(r.unidades.map((u) => u.numero), ['5 12', '5 13', '6 12']);
      expect(r.unidades.first.sector, '5');
      expect(r.unidades.first.tipologia, 'Jade 3R');
    });

    test('terreno y construcción van a campos PROPIOS, y no se suman', () {
      // Una casa de 160 m² de terreno y 142.5 de construcción no es una casa de 302.5: son dos
      // superficies distintas. Cada una tiene su campo y NINGUNA entra en el total.
      final r = leerPegado(
          'Manzana\tLote\tModelo\tM2 Terreno\tM2 Construccion\tRecamaras\tBaños\tPrecio\n'
          '5\t12\tJade 3R\t160\t142.5\t3\t2.5\t3850000');
      expect(r.errores, isEmpty);
      expect(r.columnasIgnoradas, isEmpty);

      final u = r.unidades.single;
      expect(u.m2Terreno, 160);
      expect(u.m2Construccion, 142.5);
      expect(u.recamaras, 3);
      expect(u.banos, 2.5, reason: 'los baños llevan decimal: «2.5 baños» es real');
      expect(u.m2Superficie, isNull, reason: 'ninguna de las dos es «la» superficie');
      expect(u.m2InteriorTechada, isNull);

      final fila = u.aFila('x');
      expect(fila['m2_terreno'], 160);
      expect(fila['m2_construccion'], 142.5);
      expect(fila.containsKey('m2_total'), isFalse,
          reason: 'sigue siendo columna generada; la base decide, no el pegado');
    });

    test('las etiquetas salen del encabezado, sin teclear nada', () {
      // «en AG117 torre sería edificio en Vidamar»: el campo es uno y el nombre es un dato del
      // desarrollo, que ya viene escrito en el Excel.
      final r = leerPegado('CLUSTER\tEDIFICIO\tDEPTO.\tSUP. M2\tPRECIO\n'
          'LORETO\tA\t101\t158\t4797270');
      expect(r.etiquetas['sector'], 'CLUSTER');
      expect(r.etiquetas['torre'], 'EDIFICIO');
      expect(r.etiquetas['depto'], 'DEPTO.');
      expect(r.etiquetas['m2_superficie'], 'SUP. M2',
          reason: 'la llave es el nombre de la COLUMNA, que es como la busca la vista');

      final ag = leerPegado('$encabezado\n$filaA103');
      expect(ag.etiquetas['torre'], 'Torre',
          reason: 'el MISMO campo, con el nombre que le da cada lista');
      expect(ag.etiquetas['depto'], '# Depto');
    });

    test('una columna huérfana se reporta CON un ejemplo de su valor', () {
      // «apareció una columna TIPO DE CAMBIO» no dice lo suficiente para decidir si crear un campo.
      final r = leerPegado('DEPTO.\tPRECIO\tVENDEDOR\tTIPO DE CAMBIO\n'
          '101\t100\t\t18.50\n'
          '102\t200\tRodrigo\t18.50');
      expect(r.columnasIgnoradas, ['VENDEDOR', 'TIPO DE CAMBIO']);
      expect(r.ejemplosIgnorados['TIPO DE CAMBIO'], '18.50');
      expect(r.ejemplosIgnorados['VENDEDOR'], 'Rodrigo',
          reason: 'el ejemplo sale de la primera fila que traiga algo, no de la primera fila');
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

  // ── VIDAMAR: la otra forma de lista que existe de verdad ───────────────────
  //
  // Se trae 17 filas reales porque las tres cosas que hay que probar sólo se ven con todas: que la
  // clave necesita los tres campos, que la superficie viene de un solo número, y que el estatus
  // viene en la lista.
  group('VIDAMAR', () {
    const encVidamar = 'CLUSTER\tEDIFICIO\tDEPTO.\tNIVEL\tSUP. M2\tPRECIO\tESTATUS';
    const filasVidamar = [
      'CLUSTER III\tA\t1\tPB\t155\t \$4,899,000.00 \tDISPONIBLE',
      'CLUSTER III\tC\tPH2\tPH\t210\t \$5,249,000.00 \tDISPONIBLE',
      'COSTA AZUL\tA\t202\tN2\t151.27\t \$4,954,000.00 \tDISPONIBLE',
      'LORETO\tA\t101\tN1\t158\t \$4,797,270.00 \tDISPONIBLE',
      'LORETO\tA\t202\tN2\t158\t \$5,003,270.00 \tDISPONIBLE',
      'LORETO\tC\t101\tN1\t158\t \$4,797,270.00 \tDISPONIBLE',
      'LORETO\tC\t102\tN1\t158\t \$4,797,270.00 \tDISPONIBLE',
      'LORETO\tC\tPH1\tPH\t292.73\t \$6,451,070.00 \tDISPONIBLE',
      'LORETO\tB\t101\tN1\t158\t \$4,797,270.00 \tDISPONIBLE',
      'LORETO\tB\t102\tN1\t158\t \$4,797,270.00 \tDISPONIBLE',
      'LORETO\tB\t201\tN2\t158\t \$5,003,270.00 \tDISPONIBLE',
      'LORETO\tB\t202\tN2\t158\t \$5,003,270.00 \tDISPONIBLE',
      'LORETO\tD\t101\tN1\t158\t \$4,797,270.00 \tDISPONIBLE',
      'LORETO\tD\t102\tN1\t158\t \$4,797,270.00 \tDISPONIBLE',
      'PUNTA ARENA\tD\t101\tN1\t158\t \$5,046,489.00 \tDISPONIBLE',
      'PUNTA ARENA\tD\t102\tN2\t158\t \$5,216,684.00 \tDISPONIBLE',
      'PUNTA ARENA\tD\t201\tN2\t158\t \$5,216,684.00 \tDISPONIBLE',
    ];
    final pegado = '$encVidamar\n${filasVidamar.join('\n')}';

    test('las 17 filas entran, sin errores y sin columnas sin reconocer', () {
      final r = leerPegado(pegado);
      expect(r.errores, isEmpty);
      expect(r.unidades, hasLength(17));
      expect(r.columnasIgnoradas, isEmpty,
          reason: 'las siete columnas de Vidamar deben tener destino');
    });

    test('la clave necesita CLUSTER + EDIFICIO + DEPTO., y sale única', () {
      // Medido: el depto solo da 7 claves distintas de 17, y edificio + depto da 14. Sólo las tres
      // juntas dan 17. Si la escalera se quedara corta, dos unidades se pisarían al guardar.
      final r = leerPegado(pegado);
      expect(r.claveCompuestaDe, 'sector + torre + depto');
      final claves = r.unidades.map((u) => u.numero).toList();
      expect(claves.toSet(), hasLength(17), reason: 'sin claves repetidas');
      expect(claves, contains('LORETO A 101'));
      expect(claves, contains('LORETO C 101'));
      expect(claves, contains('PUNTA ARENA D 101'),
          reason: 'los tres son «101» y tienen que quedar distintos');
    });

    test('«DEPTO.» con punto se reconoce', () {
      // El punto rompía el empate y la lista entera fallaba con «sin número de unidad».
      final r = leerPegado(pegado);
      expect(r.unidades.first.depto, '1');
    });

    test('«EDIFICIO» es la torre y «CLUSTER» el sector', () {
      final u = leerPegado(pegado).unidades.first;
      expect(u.torre, 'A');
      expect(u.sector, 'CLUSTER III');
      expect(u.nivel, 'PB');
    });

    test('la superficie de un solo número va a m2Superficie, no al desglose', () {
      final u = leerPegado(pegado).unidades.first;
      expect(u.m2Superficie, 155);
      expect(u.m2InteriorTechada, isNull,
          reason: 'meterla en «interior techada» seria etiquetarla mal');
      // La base calcula m2_total de esta, y del desglose cuando lo hay.
      expect(u.aFila('x')['m2_superficie'], 155);
      expect(u.aFila('x').containsKey('m2_total'), isFalse);
    });

    test('el precio con \$, comas y espacios alrededor', () {
      final u = leerPegado(pegado).unidades.first;
      expect(u.precio, 4899000);
    });

    test('con desglose, una columna de total se IGNORA', () {
      // AG117 trae las tres partes y además «M2 TOTAL». Guardar el total además del desglose seria
      // tener el mismo hecho escrito y calculado a la vez.
      final r = leerPegado('$encabezado\n$filaA01');
      expect(r.unidades.single.m2Superficie, isNull);
      expect(r.unidades.single.m2InteriorTechada, 76);
      expect(r.columnasIgnoradas, isEmpty);
    });
  });

  // ── La plantilla oficial ───────────────────────────────────────────────────
  //
  // Es LA prueba que hace confiable el Excel que se reparte a los desarrollos. El encabezado de la
  // plantilla se genera de `encabezadoCanonico`, y aquí se comprueba que el propio lector lo
  // entiende entero. Sin esto, cualquier cambio en un reconocedor dejaría la plantilla prometiendo
  // una columna que al pegarse se descarta —y nadie lo notaría hasta que faltara el dato—.
  group('plantilla', () {
    test('el lector entiende su PROPIA plantilla, columna por columna', () {
      final campos = encabezadoCanonico.keys.toList();
      final enc = campos.map((c) => encabezadoCanonico[c]!).join('\t');
      // Una fila con un valor plausible en cada columna.
      final valores = <String, String>{
        'numero': 'A-101', 'sector': 'COTO 4', 'torre': 'B', 'nivel': 'N2',
        'depto': '101', 'tipo': 'Casa', 'tipologia': 'Jade 3R', 'vista': 'Jardin',
        'orientacion': 'Norte',
        'm2InteriorTechada': '96.91', 'm2ExteriorTechada': '16.82',
        'm2JardinTerraza': '15.61', 'm2Superficie': '158',
        'm2Terreno': '160', 'm2Construccion': '142.5',
        'frente': '8', 'fondo': '20',
        'recamaras': '3', 'banos': '2.5', 'estacionamientos': '2',
        'niveles': '2', 'amueblado': 'SI',
        'mantenimiento': '1800', 'entregaEstimada': '31/12/2027',
        'precio': r'$3,850,000.00', 'estatus': 'DISPONIBLE',
      };
      // DOS filas, una de cada forma de superficie: la plantilla ofrece las cuatro columnas para
      // que cada desarrollo llene la que le toque, y llenar las dos a la vez con números que no
      // cuadran es un error —comprobado más abajo—.
      final conDesglose = campos
          .map((c) => c == 'm2Superficie' ? '' : (valores[c] ?? ''))
          .join('\t');
      final conSuperficie = campos
          .map((c) => const {
                'm2InteriorTechada',
                'm2ExteriorTechada',
                'm2JardinTerraza'
              }.contains(c)
              ? ''
              : (c == 'depto' ? '102' : (c == 'numero' ? 'A-102' : (valores[c] ?? ''))))
          .join('\t');

      final r = leerPegado('$enc\n$conDesglose\n$conSuperficie');
      expect(r.errores, isEmpty);
      expect(r.columnasIgnoradas, isEmpty,
          reason: 'la plantilla NO puede traer una columna que el lector descarte');
      expect(r.unidades, hasLength(2));

      expect(r.unidades.last.m2Superficie, 158,
          reason: 'la fila que sólo trae SUPERFICIE la guarda');
      expect(r.unidades.last.m2InteriorTechada, isNull);

      // Y que cada columna aterrice donde debe.
      final u = r.unidades.first;
      expect(u.numero, 'A-101', reason: 'con NUMERO propio, manda ese');
      expect(u.sector, 'COTO 4');
      expect(u.torre, 'B');
      expect(u.nivel, 'N2');
      expect(u.depto, '101');
      expect(u.tipo, 'Casa');
      expect(u.tipologia, 'Jade 3R');
      expect(u.vista, 'Jardin');
      expect(u.orientacion, 'Norte');
      expect(u.m2InteriorTechada, 96.91);
      expect(u.m2ExteriorTechada, 16.82);
      expect(u.m2JardinTerraza, 15.61);
      expect(u.m2Terreno, 160);
      expect(u.m2Construccion, 142.5);
      expect(u.frente, 8);
      expect(u.fondo, 20);
      expect(u.recamaras, 3);
      expect(u.banos, 2.5);
      expect(u.estacionamientos, 2);
      expect(u.niveles, 2);
      expect(u.amueblado, 'SI');
      expect(u.mantenimiento, 1800);
      expect(u.entregaEstimada, '2027-12-31');
      expect(u.precio, 3850000);
      expect(u.estatus, 'DISPONIBLE');
    });

    test('con SUPERFICIE y sin desglose, la superficie SÍ se guarda', () {
      final r = leerPegado('DEPTO\tSUPERFICIE\tPRECIO\n101\t158\t4797270');
      expect(r.unidades.single.m2Superficie, 158);
      expect(r.columnasIgnoradas, isEmpty);
    });

    test('si la fila trae las DOS y no cuadran, es error de esa línea', () {
      // No se elige por nadie: una de las dos está mal y adivinar cuál sería guardar un metraje
      // inventado, que es exactamente lo que un asesor le repetiría a un cliente.
      final r = leerPegado(
          'DEPTO\tM2 INTERIOR TECHADA\tM2 EXTERIOR TECHADA\tSUPERFICIE\tPRECIO\n'
          '101\t96.91\t16.82\t158\t100');
      expect(r.unidades, isEmpty);
      expect(r.errores.single.motivo, contains('158'));
      expect(r.errores.single.motivo, contains('113.73'));
      expect(r.errores.single.motivo, contains('Deja una de las dos'));
    });

    test('si traen las dos y SÍ cuadran, se conserva el desglose', () {
      // Es redundante pero no es un error: alguien escribió el total además de las partes.
      final r = leerPegado(
          'DEPTO\tM2 INTERIOR TECHADA\tM2 EXTERIOR TECHADA\tSUPERFICIE\tPRECIO\n'
          '101\t96.91\t16.82\t113.73\t100');
      expect(r.errores, isEmpty);
      final u = r.unidades.single;
      expect(u.m2InteriorTechada, 96.91);
      expect(u.m2Superficie, isNull, reason: 'el desglose dice más, y la base lo suma');
    });

    test('«M2 TOTAL» de AG117 sigue ignorándose: en su hoja es una suma', () {
      // Distinción que costó ver: «M2 TOTAL» es una suma de las tres columnas de la propia hoja,
      // mientras que «SUP. M2» de Vidamar es la superficie dada, la única que hay.
      final r = leerPegado('$encabezado\n$filaA01');
      expect(r.errores, isEmpty);
      expect(r.columnasIgnoradas, isEmpty, reason: 'ignorada a propósito, no desconocida');
      expect(r.unidades.single.m2Superficie, isNull);
      expect(r.unidades.single.m2InteriorTechada, 76);
    });

    test('«NIVEL» es el piso y «NIVELES» son los de la casa', () {
      // Lo único que las separa es el plural, y confundirlas pondría «2 pisos» donde va «planta 2».
      final r = leerPegado('DEPTO\tNIVEL\tNIVELES\tPRECIO\n101\tN2\t2\t100');
      expect(r.unidades.single.nivel, 'N2');
      expect(r.unidades.single.niveles, 2);
    });

    test('la columna NUMERO vacía no impide componer la clave', () {
      // La plantilla trae siempre NUMERO, para quien tenga clave interna propia. Casi nadie la
      // tiene, así que llega vacía. Mirando sólo el encabezado, la escalera no corría y la clave
      // se quedaba en el depto solo: los cuatro «101» de Vidamar habrían chocado.
      // El «A 101» de LORETO y el de PUNTA ARENA obligan a subir hasta el sector: sin él, la
      // escalera se quedaría en torre + depto y las dos filas serían la misma unidad.
      final r = leerPegado('NUMERO\tSECTOR\tTORRE\tDEPTO\tPRECIO\n'
          '\tLORETO\tA\t101\t100\n'
          '\tLORETO\tB\t101\t100\n'
          '\tPUNTA ARENA\tA\t101\t100');
      expect(r.errores, isEmpty, reason: 'ninguna debe salir como repetida');
      expect(r.claveCompuestaDe, 'sector + torre + depto');
      expect(r.unidades.map((u) => u.numero),
          ['LORETO A 101', 'LORETO B 101', 'PUNTA ARENA A 101']);
    });

    test('y se queda en torre + depto cuando con eso basta', () {
      // La escalera sube lo MÍNIMO: si el sector no hace falta, no se mete en la clave.
      final r = leerPegado('NUMERO\tSECTOR\tTORRE\tDEPTO\tPRECIO\n'
          '\tLORETO\tA\t101\t100\n'
          '\tLORETO\tB\t101\t100');
      expect(r.claveCompuestaDe, 'torre + depto');
      expect(r.unidades.map((u) => u.numero), ['A 101', 'B 101']);
    });

    test('si NUMERO viene llena, manda ella', () {
      final r = leerPegado('NUMERO\tSECTOR\tTORRE\tDEPTO\tPRECIO\n'
          'AG008\tLORETO\tA\t101\t100\n'
          'AG010\tLORETO\tB\t101\t100');
      expect(r.claveCompuestaDe, '', reason: 'no se compuso nada');
      expect(r.unidades.map((u) => u.numero), ['AG008', 'AG010']);
    });

    test('cada campo de la plantilla tiene columna en la base', () {
      // `aFila` es lo que se manda a Postgres: si un campo de la plantilla no aparece ahí, se
      // captura para nada.
      const generadas = {'m2_total', 'm2_total_interior', 'precio_m2'};
      final fila = const UnidadPegada(numero: 'X').aFila('id');
      for (final campo in encabezadoCanonico.keys) {
        final columna = columnaDeCampo[campo];
        expect(columna, isNotNull, reason: '«$campo» no tiene columna declarada');
        expect(fila.containsKey(columna) || generadas.contains(columna), isTrue,
            reason: '«$campo» -> «$columna» no se manda a la base: se capturaría para nada');
      }
    });
  });

  group('fechas', () {
    test('la entrega se acepta como se escribe de verdad', () {
      String? entrega(String v) =>
          leerPegado('DEPTO\tPRECIO\tENTREGA ESTIMADA\n101\t100\t$v')
              .unidades.single.entregaEstimada;

      // Día primero, que es como se escribe en México.
      expect(entrega('31/12/2027'), '2027-12-31');
      expect(entrega('1/6/2027'), '2027-06-01');
      expect(entrega('2027-12-31'), '2027-12-31');
      // Excel a veces la entrega ya con hora.
      expect(entrega('2027-12-31 00:00:00'), '2027-12-31');
    });

    test('una fecha que no se entiende queda vacía, no inventada', () {
      // «dic-2027» no dice el día, y elegirlo sería inventar un dato de entrega.
      String? entrega(String v) =>
          leerPegado('DEPTO\tPRECIO\tENTREGA ESTIMADA\n101\t100\t$v')
              .unidades.single.entregaEstimada;
      expect(entrega('dic-2027'), isNull);
      expect(entrega('por definir'), isNull);
      expect(entrega(''), isNull);
    });
  });

  group('estatusDe', () {
    test('lo que trae la lista se respeta', () {
      expect(estatusDe('DISPONIBLE'), 'DISPONIBLE');
      expect(estatusDe('Vendido'), 'VENDIDO');
      expect(estatusDe('VENDIDA'), 'VENDIDO');
      expect(estatusDe('Apartado'), 'APARTADO');
      expect(estatusDe('RESERVADO'), 'APARTADO');
      expect(estatusDe('No disponible'), 'NO_DISPONIBLE');
      expect(estatusDe('  disponible  '), 'DISPONIBLE');
    });

    test('sin columna de estatus se asume DISPONIBLE', () {
      expect(estatusDe(null), 'DISPONIBLE');
      expect(estatusDe(''), 'DISPONIBLE');
    });

    test('un valor que no se reconoce da null, no DISPONIBLE', () {
      // Suponer «disponible» ante un valor que no entendemos es el peor error del sistema: un
      // asesor ofreciendo a un cliente algo que ya se vendio.
      expect(estatusDe('EN PROCESO'), isNull);
      expect(estatusDe('bloqueado por legal'), isNull);
    });

    test('un estatus desconocido se reporta como error de esa línea', () {
      final r = leerPegado('DEPTO.\tPRECIO\tESTATUS\n'
          '101\t100\tDISPONIBLE\n'
          '102\t200\tEN PROCESO');
      expect(r.unidades, hasLength(1));
      expect(r.errores.single.motivo, contains('estatus que no reconozco'));
      expect(r.errores.single.motivo, contains('EN PROCESO'));
    });

    test('una lista con vendidas las carga como vendidas', () {
      final r = leerPegado('DEPTO.\tPRECIO\tESTATUS\n'
          '101\t100\tDISPONIBLE\n'
          '102\t200\tVENDIDO');
      expect(r.unidades.map((u) => u.estatus), ['DISPONIBLE', 'VENDIDO']);
      expect(r.unidades.last.aFila('x')['estatus'], 'VENDIDO');
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
