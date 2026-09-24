import 'package:flutter_test/flutter_test.dart';

import 'package:sistemassi/services/ventas_datos.dart';

void main() {
  group('dinero', () {
    test('agrupa en miles y redondea', () {
      expect(dinero(5950000), r'$5,950,000');
      expect(dinero('282857.4'), r'$282,857');
      expect(dinero(null), '—');
      expect(dinero('abc'), '—');
    });
  });

  group('regexDeNombres', () {
    test('reconoce el desarrollo con o sin acentos, espacios o guiones', () {
      final re = regexDeNombres(['Punta Pacifico', 'punta pacífico']);
      expect(re.hasMatch('me interesa Punta Pacífico'), isTrue);
      expect(re.hasMatch('PUNTA-PACIFICO'), isTrue);
      expect(re.hasMatch('puntapacifico'), isTrue);
      expect(re.hasMatch('Pacífico nada más'), isFalse);
    });

    test('sin nombres no reconoce nada', () {
      expect(regexDeNombres([]).hasMatch('lo que sea'), isFalse);
    });
  });

  test('slugDe', () {
    expect(slugDe('Punta Pacífico'), 'punta-pacifico');
    expect(slugDe('  Zénesis '), 'zenesis');
  });

  group('datosDeConversacion', () {
    test('saca nombre, correo, teléfono y presupuesto de lo que escribió el cliente', () {
      final hilo = [
        const Mensaje('user', 'Hola, busco algo en AG117'),
        const Mensaje('assistant', '¡Claro! ¿Me compartes tu nombre?'),
        const Mensaje('user', 'Ana López'),
        const Mensaje('user', 'mi correo ana@correo.com y mi cel 55 1234 5678, tengo 6 millones'),
      ];
      final d = datosDeConversacion(hilo);
      expect(d.nombre, 'Ana López');
      expect(d.email, 'ana@correo.com');
      expect(d.telefono, '5512345678');
      expect(d.presupuesto, '6 millones');
    });

    test('no toma los dígitos del correo como teléfono ni un saludo como nombre', () {
      final d = datosDeConversacion([
        const Mensaje('assistant', '¿Cuál es tu nombre?'),
        const Mensaje('user', 'Hola buenas'),
        const Mensaje('user', 'juan1234567890@x.com'),
      ]);
      expect(d.telefono, isEmpty);
      expect(d.nombre, isEmpty);
    });

    test('una frase no es un nombre aunque empiece con una palabra cualquiera', () {
      expect(pareceNombre('lockoff quiero saber mas'), isFalse);
      expect(pareceNombre('María de la Luz'), isTrue);
    });

    test('lo que escribió Sisol no cuenta', () {
      final d = datosDeConversacion([
        const Mensaje('assistant', 'Escríbenos a contacto@sisol.com.mx o al 5580701197'),
      ]);
      expect(d.vacio, isTrue);
    });
  });

  test('ultimoDesarrollo es el último que nombró el cliente', () {
    final devs = {
      'AG117': regexDeNombres(['AG117', 'ag 117']),
      'Koox': regexDeNombres(['Koox']),
    };
    final hilo = [
      const Mensaje('user', 'Quiero ver AG117'),
      const Mensaje('assistant', 'También tenemos Koox'),
      const Mensaje('user', 'mejor Koox, o no, ag 117'),
    ];
    expect(ultimoDesarrollo(hilo, devs), 'AG117');
    expect(ultimoDesarrollo([const Mensaje('user', 'hola')], devs), '');
  });

  test('repetidos cuenta correos sin mayúsculas y teléfonos sin formato', () {
    final r = repetidos([
      {'email': 'A@x.com', 'telefono': '55 1234 5678'},
      {'email': 'a@x.com', 'telefono': '5512345678'},
      {'email': 'b@x.com', 'telefono': ''},
    ]);
    expect(r.emails['a@x.com'], 2);
    expect(r.telefonos['5512345678'], 2);
    expect(r.telefonos.containsKey(''), isFalse);
  });

  test('leadsCsv escapa comas y comillas y lleva BOM', () {
    final csv = leadsCsv([
      {
        'created_at': '2026-09-24T18:00:00Z',
        'nombre': 'Ana, "la de AG"',
        'email': 'a@x.com',
        'telefono': '5512345678',
        'presupuesto': '6 millones',
        'desarrollo': 'AG117',
        'resumen': null,
        'notificado': true,
        'folio': 'abc',
      }
    ], urlCotizacion: (f) => 'https://chat.sisol.red/api/cotizacion/$f');
    expect(csv.startsWith('﻿'), isTrue);
    expect(csv, contains('24/09/2026 12:00'));
    expect(csv, contains('"Ana, ""la de AG"""'));
    expect(csv, contains(',si,https://chat.sisol.red/api/cotizacion/abc'));
  });

  group('leerPegadoVentas', () {
    test('lee lo pegado de Excel con los encabezados del panel anterior', () {
      const texto = 'Tipo\tNivel\tNúmero\tÁrea total\tPrecio MXN\tPrecio DLS\tEstatus\tColor\n'
          'C\t1\tA-105\t73.7\t\$5,950,000\t\tDisponible\tazul\n'
          'B\t2\tB-203\t70.8\t\t\tVendido\t\n';
      final r = leerPegadoVentas(texto);
      expect(r.errores, isEmpty);
      expect(r.ignoradas, ['Color']);
      expect(r.filas, hasLength(2));
      expect(r.filas.first['numero'], 'A-105');
      expect(r.filas.first['area_total'], 73.7);
      expect(r.filas.first['precio_mxn'], 5950000);
      expect(r.filas.first['precio_usd'], isNull);
      expect(r.filas.last['estatus'], 'VENDIDO');
    });

    test('lee CSV con comillas', () {
      final r = leerPegadoVentas('tipo,numero,precio_mxn,estatus\n"Depa 2R",502,"3,500,000",Apartado\n');
      expect(r.filas.single['precio_mxn'], 3500000);
      expect(r.filas.single['estatus'], 'APARTADO');
    });

    test('un estatus desconocido se reporta y la fila no entra', () {
      final r = leerPegadoVentas('Tipo\tEstatus\nA\tQuién sabe\n');
      expect(r.filas, isEmpty);
      expect(r.errores.single, contains('Quién sabe'));
    });

    test('sin encabezado no adivina', () {
      final r = leerPegadoVentas('A\t1\tA-102\t56.9\n');
      expect(r.filas, isEmpty);
      expect(r.errores.single, contains('encabezado'));
    });
  });
}
