/// Lee el inventario pegado desde Excel y lo compara contra lo que ya está en la base.
///
/// ─── Por qué esto vive aparte ───────────────────────────────────────────────
///
/// Es la única parte del inventario que se puede probar sin base de datos ni pantalla: entra texto,
/// sale una lista de unidades y una lista de errores. Aquí están las decisiones que más fácil se
/// rompen —el nombre de la columna del precio cambia cada mes— así que conviene que tengan pruebas
/// de verdad y no una revisión a ojo.
///
/// No importa nada de Flutter a propósito: así las pruebas corren sin levantar un widget.
library;

/// Una unidad tal como venía en el texto pegado. Sin id: todavía no se sabe si existe.
class UnidadPegada {
  final String numero;
  final String? depto;
  final String? torre;
  final String? nivel;
  final String? tipo;
  final String? tipologia;
  final String? vista;
  final double? m2InteriorTechada;
  final double? m2ExteriorTechada;
  final double? m2JardinTerraza;
  final double? precio;

  const UnidadPegada({
    required this.numero,
    this.depto,
    this.torre,
    this.nivel,
    this.tipo,
    this.tipologia,
    this.vista,
    this.m2InteriorTechada,
    this.m2ExteriorTechada,
    this.m2JardinTerraza,
    this.precio,
  });

  /// Lo que se manda a la base. `m2_total`, `m2_total_interior` y `precio_m2` NO van: son columnas
  /// generadas y Postgres las rechaza si se intentan escribir.
  Map<String, dynamic> aFila(String desarrolloId, {DateTime? listaAl}) => {
        'desarrollo_id': desarrolloId,
        'numero': numero,
        'depto': depto,
        'torre': torre,
        'nivel': nivel,
        'tipo': tipo,
        'tipologia': tipologia,
        'vista': vista,
        'm2_interior_techada': m2InteriorTechada,
        'm2_exterior_techada': m2ExteriorTechada,
        'm2_jardin_terraza': m2JardinTerraza,
        'precio': precio,
        'estatus': 'DISPONIBLE',
        if (listaAl != null)
          'lista_al':
              '${listaAl.year}-${listaAl.month.toString().padLeft(2, '0')}-${listaAl.day.toString().padLeft(2, '0')}',
      };
}

class ErrorDeLinea {
  final int linea;
  final String motivo;
  final String texto;
  const ErrorDeLinea(this.linea, this.motivo, this.texto);
}

class ResultadoPegado {
  final List<UnidadPegada> unidades;
  final List<ErrorDeLinea> errores;
  final bool traiaEncabezado;

  /// Columnas del encabezado que no se supieron mapear. No son un error —el Excel puede traer
  /// columnas de trabajo— pero conviene decirlas para que nadie crea que se guardaron.
  final List<String> columnasIgnoradas;

  const ResultadoPegado({
    required this.unidades,
    required this.errores,
    required this.traiaEncabezado,
    required this.columnasIgnoradas,
  });

  bool get vacio => unidades.isEmpty;
}

/// Quita acentos, mayúsculas y espacios de más para comparar nombres de columna.
String _normaliza(String s) {
  const de = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const a = 'aaaaaeeeeiiiiooooouuuunc';
  var t = s.toLowerCase().trim();
  for (var i = 0; i < de.length; i++) {
    t = t.replaceAll(de[i], a[i]);
  }
  return t.replaceAll(RegExp(r'\s+'), ' ');
}

/// El campo al que corresponde un encabezado, o `null` si se ignora.
///
/// El precio se reconoce por CONTENER «precio», no por el nombre completo: en el archivo la columna
/// se llama «Precio 2026 Redondeado Sept (Manual)» y ese nombre cambia cada mes. Amarrarse al texto
/// exacto habría hecho que la carga de octubre fallara sin razón aparente.
String? _campoDe(String encabezado) {
  final h = _normaliza(encabezado);
  if (h.isEmpty) return null;

  // Las dos columnas calculadas se ignoran a propósito: la base las recalcula. Si se guardaran,
  // una fila podría acabar con un total que no corresponde a sus partes.
  if (h == 'total interior m2' || h == 'm2 total') return null;

  if (h == 'torre') return 'torre';
  if (h == 'nivel') return 'nivel';
  if (h == 'tipo') return 'tipo';
  if (h == 'tipologia') return 'tipologia';
  if (h == 'vista') return 'vista';
  if (h == 'numero' || h == 'no' || h == 'clave') return 'numero';
  if (h == '# depto' || h == 'depto' || h == 'no depto' || h == 'numero depto') {
    return 'depto';
  }
  if (h.contains('interior techada')) return 'm2InteriorTechada';
  if (h.contains('exterior techada')) return 'm2ExteriorTechada';
  if (h.contains('jardin') || h.contains('terraza')) return 'm2JardinTerraza';
  if (h.contains('precio')) return 'precio';
  return null;
}

/// El orden de las columnas del archivo de AG117, para cuando se pegan las filas SIN encabezado.
const _ordenPorDefecto = <String?>[
  'torre',
  'nivel',
  'tipo',
  'tipologia',
  'depto',
  'numero',
  'vista',
  'm2InteriorTechada',
  'm2ExteriorTechada',
  'm2JardinTerraza',
  null, // TOTAL INTERIOR M2 — calculada
  null, // M2 TOTAL — calculada
  'precio',
];

double? _numero(String? s) {
  if (s == null) return null;
  // Se quita todo lo que no sea dígito, signo o punto decimal: los precios llegan como
  // «$7,460,000» y las superficies con espacios de por medio.
  final limpio = s.replaceAll(RegExp(r'[^0-9,.\-]'), '').replaceAll(',', '');
  if (limpio.isEmpty || limpio == '-') return null;
  final v = double.tryParse(limpio);
  if (v == null) return null;
  // Dos decimales: el Excel arrastra ruido de coma flotante —113.72999999999999 por 113.73— y sin
  // redondear ese ruido llega tal cual a la base.
  return (v * 100).round() / 100;
}

String? _texto(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// Lee el texto pegado desde Excel.
///
/// Acepta tabuladores —lo que produce copiar de Excel— y, si no hay ninguno, punto y coma o coma.
/// El encabezado es opcional: si la primera línea trae nombres de columna se usan para mapear, que
/// es más seguro que confiar en el orden; si no, se asume el orden del archivo de AG117.
ResultadoPegado leerPegado(String texto) {
  final lineas = texto
      .split(RegExp(r'\r\n|\r|\n'))
      .where((l) => l.trim().isNotEmpty)
      .toList();

  if (lineas.isEmpty) {
    return const ResultadoPegado(
        unidades: [], errores: [], traiaEncabezado: false, columnasIgnoradas: []);
  }

  // Tabulador o punto y coma, y NO la coma.
  //
  // Copiar de Excel produce tabuladores, que es el camino normal. La coma no se acepta como
  // separador porque en México los precios se escriben «7,460,000»: partir por coma convertiría un
  // precio en tres celdas y el resultado serían errores de «sin número de unidad» que no explican
  // nada. Mejor decirlo de frente.
  final primeraLinea = lineas.first;
  final separador =
      primeraLinea.contains('\t') ? '\t' : (primeraLinea.contains(';') ? ';' : null);
  if (separador == null) {
    return ResultadoPegado(
      unidades: const [],
      errores: [
        ErrorDeLinea(1, 'no se reconocen columnas: copia las filas desde Excel', primeraLinea),
      ],
      traiaEncabezado: false,
      columnasIgnoradas: const [],
    );
  }
  List<String> partir(String l) => l.split(separador).map((c) => c.trim()).toList();

  // ¿La primera línea es encabezado? Lo es si NINGUNA de sus celdas parece un código de unidad ni
  // un precio. Preguntarlo así evita el error de tragarse la primera unidad como si fuera título.
  final primera = partir(lineas.first);
  final pareceEncabezado = primera.any((c) => _campoDe(c) != null) &&
      !primera.any((c) => RegExp(r'^[A-Z]{2}\d{3,}$').hasMatch(c.toUpperCase()));

  var mapa = _ordenPorDefecto;
  final ignoradas = <String>[];
  if (pareceEncabezado) {
    mapa = primera.map(_campoDe).toList();
    for (var i = 0; i < primera.length; i++) {
      final h = _normaliza(primera[i]);
      if (mapa[i] == null && h.isNotEmpty && h != 'total interior m2' && h != 'm2 total') {
        ignoradas.add(primera[i]);
      }
    }
  }

  final unidades = <UnidadPegada>[];
  final errores = <ErrorDeLinea>[];
  final vistos = <String>{};

  for (var i = pareceEncabezado ? 1 : 0; i < lineas.length; i++) {
    final linea = lineas[i];
    final celdas = partir(linea);
    final valores = <String, String?>{};
    for (var j = 0; j < celdas.length && j < mapa.length; j++) {
      final campo = mapa[j];
      if (campo != null) valores[campo] = celdas[j];
    }

    // Si no hay columna de clave propia, el DEPARTAMENTO es la clave.
    //
    // AG117 trae las dos —AG008 y A-103— pero no toda lista tiene un código interno; muchas
    // identifican la unidad solo por su número de departamento. Dentro de un desarrollo eso
    // identifica igual de bien, y si se repitiera, el control de repetidos de abajo lo dice.
    final numero =
        (_texto(valores['numero']) ?? _texto(valores['depto']))?.toUpperCase();
    if (numero == null) {
      errores.add(ErrorDeLinea(i + 1, 'sin número de unidad', linea));
      continue;
    }
    if (!vistos.add(numero)) {
      // Repetido DENTRO del pegado. Si se dejara pasar, la base rechazaría el lote entero por la
      // restricción de unicidad y el mensaje no diría cuál fue.
      errores.add(ErrorDeLinea(i + 1, 'el número $numero viene repetido', linea));
      continue;
    }

    final precio = _numero(valores['precio']);
    if (precio == null) {
      errores.add(ErrorDeLinea(i + 1, '$numero no trae precio', linea));
      continue;
    }

    unidades.add(UnidadPegada(
      numero: numero,
      depto: _texto(valores['depto']),
      torre: _texto(valores['torre']),
      nivel: _texto(valores['nivel']),
      tipo: _texto(valores['tipo']),
      tipologia: _texto(valores['tipologia']),
      vista: _texto(valores['vista']),
      m2InteriorTechada: _numero(valores['m2InteriorTechada']),
      m2ExteriorTechada: _numero(valores['m2ExteriorTechada']),
      m2JardinTerraza: _numero(valores['m2JardinTerraza']),
      precio: precio,
    ));
  }

  return ResultadoPegado(
    unidades: unidades,
    errores: errores,
    traiaEncabezado: pareceEncabezado,
    columnasIgnoradas: ignoradas,
  );
}

// ── La comparación ───────────────────────────────────────────────────────────

class CambioDePrecio {
  final String numero;
  final double? anterior;
  final double nuevo;
  const CambioDePrecio(this.numero, this.anterior, this.nuevo);

  double? get diferencia => anterior == null ? null : nuevo - anterior!;
}

/// Qué va a pasar si se guarda el pegado. Se muestra ANTES de escribir nada.
///
/// La razón es la decisión que se tomó sobre las que desaparecen: la lista mensual sólo trae las
/// disponibles, así que una unidad ausente normalmente está vendida —pero también puede faltar
/// porque alguien copió mal el rango. Marcar sin preguntar convertiría un error de copiado en
/// inventario perdido.
class Comparacion {
  final List<UnidadPegada> nuevas;
  final List<CambioDePrecio> cambiosDePrecio;
  final List<UnidadPegada> cambiosDeDatos;
  final List<Map<String, dynamic>> desaparecidas;
  final int sinCambio;

  const Comparacion({
    required this.nuevas,
    required this.cambiosDePrecio,
    required this.cambiosDeDatos,
    required this.desaparecidas,
    required this.sinCambio,
  });

  bool get sinNovedades =>
      nuevas.isEmpty &&
      cambiosDePrecio.isEmpty &&
      cambiosDeDatos.isEmpty &&
      desaparecidas.isEmpty;
}

double? _comoDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return (v * 100).round() / 100;
  return _numero(v.toString());
}

/// Compara el pegado con las unidades que ya están en la base.
///
/// `desaparecidas` sólo incluye las que hoy figuran DISPONIBLE: una que ya estaba marcada vendida no
/// es novedad y repetirla cada mes sólo taparía lo que sí cambió.
Comparacion compararInventario(
  List<UnidadPegada> pegadas,
  List<Map<String, dynamic>> enBase,
) {
  final porNumero = <String, Map<String, dynamic>>{};
  for (final u in enBase) {
    final n = (u['numero'] ?? '').toString().toUpperCase();
    if (n.isNotEmpty) porNumero[n] = u;
  }

  final nuevas = <UnidadPegada>[];
  final cambiosPrecio = <CambioDePrecio>[];
  final cambiosDatos = <UnidadPegada>[];
  var iguales = 0;

  for (final p in pegadas) {
    final actual = porNumero[p.numero];
    if (actual == null) {
      nuevas.add(p);
      continue;
    }

    var cambio = false;

    final precioActual = _comoDouble(actual['precio']);
    if (precioActual != p.precio) {
      cambiosPrecio.add(CambioDePrecio(p.numero, precioActual, p.precio!));
      cambio = true;
    }

    // Cualquier otra diferencia, incluido el estatus: una unidad que estaba marcada vendida y
    // reaparece en la lista de disponibles ES un cambio, y de los importantes.
    final mismos = _texto(actual['depto']?.toString()) == p.depto &&
        _texto(actual['torre']?.toString()) == p.torre &&
        _texto(actual['nivel']?.toString()) == p.nivel &&
        _texto(actual['tipo']?.toString()) == p.tipo &&
        _texto(actual['tipologia']?.toString()) == p.tipologia &&
        _texto(actual['vista']?.toString()) == p.vista &&
        _comoDouble(actual['m2_interior_techada']) == p.m2InteriorTechada &&
        _comoDouble(actual['m2_exterior_techada']) == p.m2ExteriorTechada &&
        _comoDouble(actual['m2_jardin_terraza']) == p.m2JardinTerraza &&
        (actual['estatus'] ?? 'DISPONIBLE') == 'DISPONIBLE';
    if (!mismos) {
      cambiosDatos.add(p);
      cambio = true;
    }

    if (!cambio) iguales++;
  }

  final pegados = pegadas.map((p) => p.numero).toSet();
  final desaparecidas = enBase.where((u) {
    final n = (u['numero'] ?? '').toString().toUpperCase();
    return !pegados.contains(n) && (u['estatus'] ?? 'DISPONIBLE') == 'DISPONIBLE';
  }).toList();

  return Comparacion(
    nuevas: nuevas,
    cambiosDePrecio: cambiosPrecio,
    cambiosDeDatos: cambiosDatos,
    desaparecidas: desaparecidas,
    sinCambio: iguales,
  );
}
