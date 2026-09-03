/// Lee el inventario pegado desde Excel y lo compara contra lo que ya está en la base.
///
/// ─── Por qué esto vive aparte ───────────────────────────────────────────────
///
/// Es la única parte del inventario que se puede probar sin base de datos ni pantalla: entra texto,
/// sale una lista de unidades y una lista de errores. Aquí están las decisiones que más fácil se
/// rompen —el nombre de la columna del precio cambia cada mes— así que conviene que tengan pruebas
/// de verdad y no una revisión a ojo.
///
/// ─── Las listas NO tienen la misma forma ────────────────────────────────────
///
/// Dos listas reales, y no se parecen:
///
///   AG117    Torre · Nivel · Tipo · Tipología · # Depto · **Numero** · Vista ·
///            AREA INTERIOR TECHADA · AREA EXTERIOR TECHADA · JARDIN TERRAZA · precio
///   VIDAMAR  **CLUSTER** · EDIFICIO · DEPTO. · NIVEL · **SUP. M2** · PRECIO · **ESTATUS**
///
/// Tres diferencias de fondo, no de nombre:
///
///   1. AG117 trae una CLAVE ÚNICA propia («AG008»). Vidamar no: hay que componerla, y sólo
///      CLUSTER + EDIFICIO + DEPTO. es única —medido sobre las 17 filas reales: `DEPTO.` solo da 7
///      claves distintas de 17, y EDIFICIO + DEPTO. da 14—.
///   2. AG117 trae la superficie DESGLOSADA en tres y la base suma; Vidamar trae un solo número.
///   3. Vidamar trae el ESTATUS en la lista. Ignorarlo sería cargar como disponible algo vendido,
///      que es el peor error que puede cometer el asistente.
///
/// No importa nada de Flutter a propósito: así las pruebas corren sin levantar un widget.
library;

/// Los estatus que acepta la base. El mismo orden y los mismos nombres que la restricción.
const estatusValidos = ['DISPONIBLE', 'APARTADO', 'VENDIDO', 'NO_DISPONIBLE'];

/// De cómo se llama el campo aquí a cómo se llama la COLUMNA en la base.
///
/// Existe porque las etiquetas por desarrollo se guardan con el nombre de la columna, no con el de
/// aquí: la vista `v_campos_por_desarrollo` las busca con `etiquetas ->> campo`, y si aquí se
/// escribiera «m2Superficie» y allá se buscara «m2_superficie», el nombre no aparecería nunca y
/// nadie sabría por qué.
const columnaDeCampo = <String, String>{
  'numero': 'numero',
  'depto': 'depto',
  'sector': 'sector',
  'torre': 'torre',
  'nivel': 'nivel',
  'tipo': 'tipo',
  'tipologia': 'tipologia',
  'vista': 'vista',
  'm2InteriorTechada': 'm2_interior_techada',
  'm2ExteriorTechada': 'm2_exterior_techada',
  'm2JardinTerraza': 'm2_jardin_terraza',
  'm2Superficie': 'm2_superficie',
  'm2Terreno': 'm2_terreno',
  'm2Construccion': 'm2_construccion',
  'recamaras': 'recamaras',
  'banos': 'banos',
  'estacionamientos': 'estacionamientos',
  'precio': 'precio',
  'estatus': 'estatus',
};

/// Una unidad tal como venía en el texto pegado. Sin id: todavía no se sabe si existe.
class UnidadPegada {
  /// La clave. Es la de la lista si la trae, o una compuesta por el sector, la torre y el depto.
  final String numero;
  final String? depto;

  /// La agrupación POR ENCIMA del edificio: «CLUSTER III», «COTO 4», una sección, una manzana.
  ///
  /// Hace falta por dos razones y las dos son necesarias: sin ella el dato se perdería, y sin ella
  /// la clave de Vidamar no puede ser única.
  final String? sector;

  final String? torre;
  final String? nivel;
  final String? tipo;
  final String? tipologia;
  final String? vista;

  /// El desglose, cuando la lista lo trae.
  final double? m2InteriorTechada;
  final double? m2ExteriorTechada;
  final double? m2JardinTerraza;

  /// La superficie de un solo número, cuando la lista NO desglosa.
  ///
  /// La base calcula `m2_total` como esta si viene, y como la suma del desglose si no. Así el total
  /// sigue siendo derivado —nunca teclado— sea cual sea la forma de la lista.
  final double? m2Superficie;

  /// De una casa o un lote. NO se suman entre si ni entran en `m2_total`: una casa de 160 m2 de
  /// terreno y 142 de construccion no es una casa de 302.
  final double? m2Terreno;
  final double? m2Construccion;

  final int? recamaras;
  /// Con decimal: «2.5 baños» es como se anuncia de verdad.
  final double? banos;
  final int? estacionamientos;

  final double? precio;
  final String estatus;

  const UnidadPegada({
    required this.numero,
    this.depto,
    this.sector,
    this.torre,
    this.nivel,
    this.tipo,
    this.tipologia,
    this.vista,
    this.m2InteriorTechada,
    this.m2ExteriorTechada,
    this.m2JardinTerraza,
    this.m2Superficie,
    this.m2Terreno,
    this.m2Construccion,
    this.recamaras,
    this.banos,
    this.estacionamientos,
    this.precio,
    this.estatus = 'DISPONIBLE',
  });

  /// Lo que se manda a la base. `m2_total`, `m2_total_interior` y `precio_m2` NO van: son columnas
  /// generadas y Postgres las rechaza si se intentan escribir.
  Map<String, dynamic> aFila(String desarrolloId, {DateTime? listaAl}) => {
        'desarrollo_id': desarrolloId,
        'numero': numero,
        'depto': depto,
        'sector': sector,
        'torre': torre,
        'nivel': nivel,
        'tipo': tipo,
        'tipologia': tipologia,
        'vista': vista,
        'm2_interior_techada': m2InteriorTechada,
        'm2_exterior_techada': m2ExteriorTechada,
        'm2_jardin_terraza': m2JardinTerraza,
        'm2_superficie': m2Superficie,
        'm2_terreno': m2Terreno,
        'm2_construccion': m2Construccion,
        'recamaras': recamaras,
        'banos': banos,
        'estacionamientos': estacionamientos,
        'precio': precio,
        'estatus': estatus,
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

  /// Cómo se armó la clave, para poder decirlo en la vista previa. Si la lista no traía clave
  /// propia, conviene que se vea cuál se compuso antes de guardar 17 renglones con ella.
  final String claveCompuestaDe;

  /// El nombre que ESTA lista le dio a cada campo: `{'torre': 'EDIFICIO', 'sector': 'CLUSTER'}`.
  ///
  /// Es la respuesta a «en AG117 torre sería edificio en Vidamar»: el campo es uno y el nombre es
  /// un dato del desarrollo. Y no hay que teclearlo, porque ya viene escrito en el encabezado del
  /// Excel que se acaba de pegar.
  final Map<String, String> etiquetas;

  /// Las columnas sin campo, con un ejemplo de su valor.
  ///
  /// Se guardan en la base para poder decidir con datos qué campo crear después, en lugar de
  /// crear columnas a ciegas por si acaso.
  final Map<String, String> ejemplosIgnorados;

  const ResultadoPegado({
    required this.unidades,
    required this.errores,
    required this.traiaEncabezado,
    required this.columnasIgnoradas,
    this.claveCompuestaDe = '',
    this.etiquetas = const {},
    this.ejemplosIgnorados = const {},
  });

  bool get vacio => unidades.isEmpty;
}

/// Quita acentos, mayúsculas, puntos y espacios de más para comparar nombres de columna.
///
/// El punto final importa: la columna de Vidamar se llama «DEPTO.» y sin quitarlo no empataba con
/// «depto», así que la lista entera fallaba con «sin número de unidad».
String _normaliza(String s) {
  const de = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const a = 'aaaaaeeeeiiiiooooouuuunc';
  var t = s.toLowerCase().trim();
  for (var i = 0; i < de.length; i++) {
    t = t.replaceAll(de[i], a[i]);
  }
  return t.replaceAll('.', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// El campo al que corresponde un encabezado, o `null` si se ignora.
///
/// El precio se reconoce por CONTENER «precio», no por el nombre completo: en el archivo de AG117
/// la columna se llama «Precio 2026 Redondeado Sept (Manual)» y ese nombre cambia cada mes.
/// Amarrarse al texto exacto habría hecho que la carga de octubre fallara sin razón aparente.
String? _campoDe(String encabezado) {
  final h = _normaliza(encabezado);
  if (h.isEmpty) return null;

  // `TOTAL INTERIOR M2` se ignora SIEMPRE: es una suma parcial del desglose, nunca la superficie
  // completa, así que no sirve ni como total.
  if (h == 'total interior m2') return null;

  if (h == 'torre' || h == 'edificio' || h == 'bloque') return 'torre';
  if (h == 'cluster' || h == 'coto' || h == 'sector' || h == 'seccion' ||
      h == 'manzana' || h == 'condominio') {
    return 'sector';
  }
  if (h == 'nivel' || h == 'piso') return 'nivel';
  if (h == 'tipo') return 'tipo';
  if (h == 'tipologia' || h == 'modelo' || h == 'prototipo') return 'tipologia';
  if (h == 'vista') return 'vista';
  if (h == 'numero' || h == 'no' || h == 'clave') return 'numero';
  if (h == '# depto' || h == 'depto' || h == 'no depto' || h == 'numero depto' ||
      h == 'departamento' || h == 'unidad' || h == 'lote') {
    return 'depto';
  }
  if (h == 'estatus' || h == 'status' || h == 'estado' || h == 'disponibilidad') {
    return 'estatus';
  }
  if (h.contains('interior techada')) return 'm2InteriorTechada';
  if (h.contains('exterior techada')) return 'm2ExteriorTechada';
  if (h.contains('jardin') || h.contains('terraza')) return 'm2JardinTerraza';
  if (h.contains('terreno') || h.contains('lote m2')) return 'm2Terreno';
  if (h.contains('construccion') || h.contains('construida')) return 'm2Construccion';
  if (h.startsWith('recamara') || h == 'rec' || h == 'habitaciones' || h == 'dormitorios') {
    return 'recamaras';
  }
  if (h.startsWith('bano') || h == 'wc') return 'banos';
  if (h.contains('estacionamiento') || h.contains('cajon') || h == 'cochera') {
    return 'estacionamientos';
  }
  if (h.contains('precio')) return 'precio';

  // La superficie de un solo número, al final para que no le gane a las de desglose.
  if (h == 'm2 total' || h == 'sup m2' || h == 'sup' || h == 'superficie' ||
      h == 'superficie m2' || h == 'm2' || h == 'sup total' ||
      h == 'superficie total') {
    return 'm2Superficie';
  }
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

int? _entero(String? s) {
  final v = _numero(s);
  return v == null ? null : v.round();
}

String? _texto(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// El estatus de la lista, traducido al de la base, o `null` si no se reconoce.
///
/// Devolver `null` en lugar de suponer DISPONIBLE es a propósito: un valor que no entendemos se
/// reporta como error de esa línea. Cargar como disponible algo que la lista marcaba de otra forma
/// es el peor error del sistema —un asesor ofreciendo una unidad vendida—.
String? estatusDe(String? crudo) {
  final t = _normaliza(crudo ?? '');
  if (t.isEmpty) return 'DISPONIBLE';
  if (t.contains('no disponible') || t.contains('no_disponible')) return 'NO_DISPONIBLE';
  if (t.startsWith('disponible') || t == 'libre') return 'DISPONIBLE';
  if (t.startsWith('apartad') || t.startsWith('reservad')) return 'APARTADO';
  if (t.startsWith('vendid')) return 'VENDIDO';
  return null;
}

/// Cómo se mapea cada columna del encabezado, aplicando las reglas que necesitan verlo COMPLETO.
({
  List<String?> mapa,
  List<String> ignoradas,
  Map<String, String> etiquetas,
}) _mapearEncabezado(List<String> encabezado) {
  final mapa = encabezado.map(_campoDe).toList();

  // La regla que necesita el encabezado entero: si la lista DESGLOSA la superficie, una columna de
  // total es una suma de las otras y no se guarda —la base la recalcula—. Si no desglosa, esa
  // columna es la única superficie que hay y sí se guarda.
  //
  // Sin esto, `M2 TOTAL` de AG117 se guardaría además del desglose, y entonces el total estaría
  // escrito y calculado a la vez: dos verdades sobre el mismo hecho.
  final desglosa = mapa.any((m) =>
      m == 'm2InteriorTechada' || m == 'm2ExteriorTechada' || m == 'm2JardinTerraza');
  if (desglosa) {
    for (var i = 0; i < mapa.length; i++) {
      if (mapa[i] == 'm2Superficie') mapa[i] = null;
    }
  }

  final ignoradas = <String>[];
  final etiquetas = <String, String>{};
  for (var i = 0; i < encabezado.length; i++) {
    final campo = mapa[i];
    if (campo != null) {
      // El nombre TAL CUAL lo escribió el Excel, para poder mostrarlo así en el panel.
      final tal = encabezado[i].trim();
      // Con el nombre de la COLUMNA como llave, no el de aqui: es como lo busca la vista.
      final llave = columnaDeCampo[campo] ?? campo;
      if (tal.isNotEmpty) etiquetas.putIfAbsent(llave, () => tal);
      continue;
    }
    final h = _normaliza(encabezado[i]);
    // Las calculadas no son «desconocidas»: se ignoran a propósito y decirlo sólo haría ruido.
    if (h.isEmpty || h == 'total interior m2' || h == 'm2 total') continue;
    ignoradas.add(encabezado[i]);
  }
  return (mapa: mapa, ignoradas: ignoradas, etiquetas: etiquetas);
}

/// Lee el texto pegado desde Excel.
///
/// Acepta tabuladores —lo que produce copiar de Excel— y punto y coma. El encabezado es opcional:
/// si la primera línea trae nombres de columna se usan para mapear, que es más seguro que confiar
/// en el orden; si no, se asume el orden del archivo de AG117.
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

  // ¿La primera línea es encabezado? Lo es si alguna celda es un nombre de columna conocido y
  // ninguna parece un código de unidad. Preguntarlo así evita el error de tragarse la primera
  // unidad como si fuera título.
  final primera = partir(lineas.first);
  final pareceEncabezado = primera.any((c) => _campoDe(c) != null) &&
      !primera.any((c) => RegExp(r'^[A-Z]{2}\d{3,}$').hasMatch(c.toUpperCase()));

  var mapa = _ordenPorDefecto;
  var ignoradas = <String>[];
  var etiquetas = <String, String>{};
  if (pareceEncabezado) {
    final r = _mapearEncabezado(primera);
    mapa = r.mapa;
    ignoradas = r.ignoradas;
    etiquetas = r.etiquetas;
  }
  // Un ejemplo del valor de cada columna huérfana, de la primera fila que lo traiga. Sin ejemplo,
  // «apareció una columna llamada TIPO DE CAMBIO» no dice lo suficiente para decidir nada.
  final ejemplos = <String, String>{};
  if (pareceEncabezado && ignoradas.isNotEmpty) {
    final donde = <String, int>{};
    for (var i = 0; i < primera.length; i++) {
      if (ignoradas.contains(primera[i].trim())) donde[primera[i].trim()] = i;
    }
    for (final l in lineas.skip(1)) {
      final celdas = partir(l);
      for (final e in donde.entries) {
        if (ejemplos.containsKey(e.key)) continue;
        if (e.value < celdas.length && celdas[e.value].isNotEmpty) {
          ejemplos[e.key] = celdas[e.value];
        }
      }
      if (ejemplos.length == donde.length) break;
    }
  }

  // Primero se leen TODAS las celdas, y sólo después se decide la clave.
  //
  // Hace falta el conjunto completo porque la clave se elige MIDIENDO, no suponiendo: ver abajo.
  final crudas = <({int linea, String texto, Map<String, String?> valores})>[];
  for (var i = pareceEncabezado ? 1 : 0; i < lineas.length; i++) {
    final celdas = partir(lineas[i]);
    final valores = <String, String?>{};
    for (var j = 0; j < celdas.length && j < mapa.length; j++) {
      final campo = mapa[j];
      if (campo != null) valores[campo] = celdas[j];
    }
    crudas.add((linea: i + 1, texto: lineas[i], valores: valores));
  }

  // ─── La clave: la combinación MÁS CORTA que no repita ─────────────────────
  //
  // Si la lista trae una clave propia («Numero» en AG117) se usa y ya. Si no, hay que componerla,
  // y cuánto hace falta depende de la lista:
  //
  //   - AG117 sin la columna Numero: `# Depto` vale «A-103», que ya lleva la torre dentro.
  //     Anteponerle la torre daría «A A-103», redundante y feo.
  //   - VIDAMAR: `DEPTO.` vale «101», y hay un 101 en cada edificio de cada cluster. Medido sobre
  //     sus 17 filas reales: el depto solo da 7 claves distintas, EDIFICIO + DEPTO. da 14, y sólo
  //     CLUSTER + EDIFICIO + DEPTO. da 17.
  //
  // Así que se prueban las combinaciones de menos a más y se toma la primera que no repita. Es un
  // dato que está a la vista en el propio pegado; elegirlo a ojo habría acertado en una lista y
  // fallado en la otra.
  //
  // El `depto` es obligatorio en todas: es la unidad. El sector y la torre sólo dicen DÓNDE está,
  // y una clave hecha sólo con ellos —«A»— chocaría con todas las unidades de esa torre.
  final hayClavePropia = mapa.contains('numero');
  const escalera = [<String>[], ['torre'], ['sector', 'torre']];
  var calificadores = <String>[];

  if (!hayClavePropia) {
    String? componer(Map<String, String?> v, List<String> quals) {
      final d = _texto(v['depto']);
      if (d == null) return null;
      // Se emite de lo general a lo particular, como se nombra en voz alta: «Loreto, A, 101».
      final trozos = <String>[];
      for (final p in ['sector', 'torre']) {
        if (!quals.contains(p)) continue;
        final t = _texto(v[p]);
        if (t != null) trozos.add(t);
      }
      trozos.add(d);
      return trozos.join(' ').toUpperCase();
    }

    calificadores = escalera.last;
    for (final quals in escalera) {
      if (!quals.every(mapa.contains)) continue;
      final claves = crudas.map((c) => componer(c.valores, quals)).whereType<String>().toList();
      if (claves.isEmpty) continue;
      if (claves.toSet().length == claves.length) {
        calificadores = quals;
        break;
      }
    }
  }

  String? claveDe(Map<String, String?> v) {
    final propia = _texto(v['numero']);
    if (propia != null) return propia.toUpperCase();
    final d = _texto(v['depto']);
    if (d == null) return null;
    final trozos = <String>[];
    for (final p in ['sector', 'torre']) {
      if (!calificadores.contains(p)) continue;
      final t = _texto(v[p]);
      if (t != null) trozos.add(t);
    }
    trozos.add(d);
    return trozos.join(' ').toUpperCase();
  }

  final unidades = <UnidadPegada>[];
  final errores = <ErrorDeLinea>[];
  final vistos = <String>{};

  for (final cruda in crudas) {
    final i = cruda.linea - 1;
    final linea = cruda.texto;
    final valores = cruda.valores;

    final numero = claveDe(valores);

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

    final estatus = estatusDe(valores['estatus']);
    if (estatus == null) {
      errores.add(ErrorDeLinea(
          i + 1, '$numero trae un estatus que no reconozco: «${valores['estatus']}»', linea));
      continue;
    }

    unidades.add(UnidadPegada(
      numero: numero,
      depto: _texto(valores['depto']),
      sector: _texto(valores['sector']),
      torre: _texto(valores['torre']),
      nivel: _texto(valores['nivel']),
      tipo: _texto(valores['tipo']),
      tipologia: _texto(valores['tipologia']),
      vista: _texto(valores['vista']),
      m2InteriorTechada: _numero(valores['m2InteriorTechada']),
      m2ExteriorTechada: _numero(valores['m2ExteriorTechada']),
      m2JardinTerraza: _numero(valores['m2JardinTerraza']),
      m2Superficie: _numero(valores['m2Superficie']),
      m2Terreno: _numero(valores['m2Terreno']),
      m2Construccion: _numero(valores['m2Construccion']),
      recamaras: _entero(valores['recamaras']),
      banos: _numero(valores['banos']),
      estacionamientos: _entero(valores['estacionamientos']),
      precio: precio,
      estatus: estatus,
    ));
  }

  return ResultadoPegado(
    unidades: unidades,
    errores: errores,
    traiaEncabezado: pareceEncabezado,
    columnasIgnoradas: ignoradas,
    claveCompuestaDe:
        hayClavePropia ? '' : [...calificadores, 'depto'].join(' + '),
    etiquetas: etiquetas,
    ejemplosIgnorados: ejemplos,
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
    // reaparece disponible ES un cambio, y de los importantes.
    final mismos = _texto(actual['depto']?.toString()) == p.depto &&
        _texto(actual['sector']?.toString()) == p.sector &&
        _texto(actual['torre']?.toString()) == p.torre &&
        _texto(actual['nivel']?.toString()) == p.nivel &&
        _texto(actual['tipo']?.toString()) == p.tipo &&
        _texto(actual['tipologia']?.toString()) == p.tipologia &&
        _texto(actual['vista']?.toString()) == p.vista &&
        _comoDouble(actual['m2_interior_techada']) == p.m2InteriorTechada &&
        _comoDouble(actual['m2_exterior_techada']) == p.m2ExteriorTechada &&
        _comoDouble(actual['m2_jardin_terraza']) == p.m2JardinTerraza &&
        _comoDouble(actual['m2_superficie']) == p.m2Superficie &&
        _comoDouble(actual['m2_terreno']) == p.m2Terreno &&
        _comoDouble(actual['m2_construccion']) == p.m2Construccion &&
        _entero(actual['recamaras']?.toString()) == p.recamaras &&
        _comoDouble(actual['banos']) == p.banos &&
        _entero(actual['estacionamientos']?.toString()) == p.estacionamientos &&
        (actual['estatus'] ?? 'DISPONIBLE') == p.estatus;
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
