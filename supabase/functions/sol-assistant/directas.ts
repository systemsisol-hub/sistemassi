// Lo que se contesta SIN pasar por el modelo, y lo que decide si un documento se convierte en boton.
//
// ─── Por que existe este archivo ────────────────────────────────────────────
//
// El 03/09/2026, con la direccion completa ya capturada -«Abraham Gonzalez 117, Colonia Juarez,
// alcaldia Cuahutemoc, 06600, CDMX»-, SOL contesto dos veces «AG117 se encuentra en CDMX». Y doce
// minutos antes, a la misma pregunta, habia contestado «AG117 se ubica en Tulum», que es donde
// estan Zenesis y Selva Norte. El dato estaba bien las dos veces: el modelo lo recorto una vez y lo
// confundio con otro desarrollo la otra.
//
// Un dato que ya esta en la base no tiene por que pasar por un modelo para salir. Es la misma
// leccion de Soli y sus vias directas: no le pidas al modelo lo que el codigo puede hacer sin
// equivocarse.
//
// Sin efectos al importarlo, a proposito, para que el arnes pueda ejercitarlo.

export function sinAcentos(s: string): string {
  // El rango se escribe con escapes y no con los caracteres combinantes literales: escritos tal
  // cual son invisibles en el editor y cualquier reformateo los puede perder sin que se note.
  return s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

/// Solo si el texto pregunta por un DONDE, sin mirar de que.
///
/// Es el filtro previo barato, para no consultar el catalogo en cada mensaje. Va aparte de
/// `preguntaUbicacion` por un error que costo una prueba real: el filtro previo la llamaba con la
/// lista de nombres VACIA, y sin catalogo «AG117» se ve igual que la unidad «AG008», asi que la via
/// directa NUNCA se disparaba cuando la pregunta nombraba al desarrollo. El 03/09/2026 a las
/// 19:32, «me puedes dar la ubicacion de AG117» se fue al modelo y gasto 6693 tokens en un dato que
/// estaba a una consulta de distancia. Habia hasta una prueba afirmando ese `false`: la prueba
/// estaba bien y el uso mal.
export function mencionaUbicacion(texto: string): boolean {
  const t = sinAcentos(texto);
  return /\b(ubicacion|ubicado|ubica|direccion|domicilio|codigo postal)\b/.test(t)
    || /\bdonde\s+(esta|queda|se\s+encuentra|se\s+ubica)\b/.test(t)
    || /\ben\s+que\s+(zona|colonia|calle|alcaldia|ciudad)\b/.test(t);
}

/// Si la pregunta es por DONDE esta un DESARROLLO.
///
/// Se excluye cuando la pregunta nombra una UNIDAD -AG008, A-103-: ahi «donde esta» se refiere a
/// la unidad dentro del edificio, y eso lo contesta el inventario, no este atajo.
///
/// Distinguir unidad de desarrollo obliga a recibir los nombres: el desarrollo se llama «AG117» y
/// sus unidades «AG004»..«AG168», o sea que la MISMA forma es una cosa o la otra segun el catalogo.
/// Llamarla con `nombres` vacio es un uso valido solo para preguntar «¿esto podria ser de una
/// unidad?»; para decidir la via directa hay que pasarle el catalogo.
export function preguntaUbicacion(texto: string, nombres: string[] = []): boolean {
  if (!mencionaUbicacion(texto)) return false;
  let t = sinAcentos(texto);
  for (const n of nombres) t = t.split(sinAcentos(n)).join(" ");
  return !(/\bag\s?\d{3}\b/.test(t) || /\b[a-e]-\d{2,3}\b/.test(t));
}

// ── Que campo se esta preguntando ───────────────────────────────────────────

export type CampoDirecto =
  | "ubicacion"
  | "amenidades"
  | "enganche"
  | "mensualidades"
  | "etapa";

/// Los campos que una PROMOCION vigente puede cambiar.
///
/// Un atajo que lea `enganche_pct` y conteste «10%» seria PEOR que el modelo si hay una promocion
/// viva que ofrece 5%: daria un dato correcto en la tabla y equivocado en la realidad. Asi que
/// cuando el desarrollo tiene promocion vigente, estos campos NO se contestan directo y pasan al
/// modelo, que tiene las dos cosas delante y puede decir cual manda.
///
/// Hoy no hay ninguna promocion capturada, pero eso es un accidente del momento: la primera que se
/// capture activaria el problema sin que nadie lo relacionara con esto.
export const AFECTADOS_POR_PROMOCION: CampoDirecto[] = ["enganche", "mensualidades"];

/// Los reconocedores, con sus EXCLUSIONES.
///
/// Las exclusiones no son un detalle: sin ellas el atajo contesta otra pregunta.
///
/// El caso que las obligo: `mensualidades` guarda un NUMERO DE PAGOS -26-, no un importe.
/// «¿Cuantas mensualidades?» se contesta con 26; «¿cuanto es la mensualidad?» pregunta cuanto paga
/// al mes, y eso NO esta en la base -depende del precio de la unidad y del plan-. Contestar «se
/// maneja a 26 mensualidades» a la segunda seria responder otra cosa. Peor: el modelo ya contestaba
/// bien esa pregunta -«el monto exacto no esta capturado, consultalo en la Lista de precios»- y el
/// atajo se habria llevado por delante esa ayuda.
///
/// El plural distingue las dos: «cuantas mensualidadES» frente a «cuanto es la mensualidAD».
const RECONOCEDORES: Array<{
  campo: CampoDirecto;
  pruebas: RegExp[];
  excluye?: RegExp[];
}> = [
  // La ubicacion tiene su propia funcion por la trampa de las unidades; aqui solo se detecta.
  { campo: "ubicacion", pruebas: [] },
  {
    campo: "amenidades",
    // A proposito NO incluye «tiene alberca?» ni «que incluye?»: ahi el modelo contesta mejor,
    // porque puede decir si eso concreto esta o no en la lista.
    pruebas: [/\bamenidad(es)?\b/, /\bareas\s+comunes\b/],
  },
  {
    campo: "enganche",
    pruebas: [/\benganche\b/],
    // El campo es un PORCENTAJE. Preguntado en dinero, el importe depende de la unidad y no esta
    // capturado: que lo conteste el modelo, que sabe ofrecer la lista de precios.
    excluye: [/\ben\s+(pesos|dinero|efectivo)\b/, /\bcuant[oa]s?\s+(pesos|dinero)\b/, /\bmonto\b/],
  },
  {
    campo: "mensualidades",
    pruebas: [/\bmensualidad(es)?\b/, /\bcuantos\s+meses\b/, /\bplazo\b/],
    // «mensualidad» en SINGULAR junto a «cuanto» es una pregunta por el importe, no por el numero
    // de pagos. `\b` impide que esto empate con «mensualidades».
    excluye: [/\bcuanto\b[\s\S]{0,30}\bmensualidad\b/, /\bmensualidad\b[\s\S]{0,20}\bcuanto\b/,
      /\ben\s+(pesos|dinero)\b/, /\bmonto\b/],
  },
  { campo: "etapa", pruebas: [/\betapa\b/] },
];

/// TODOS los campos que menciona un texto.
export function camposPreguntados(texto: string): CampoDirecto[] {
  const t = sinAcentos(texto);
  const encontrados: CampoDirecto[] = [];
  if (mencionaUbicacion(texto)) encontrados.push("ubicacion");
  for (const { campo, pruebas, excluye } of RECONOCEDORES) {
    if (pruebas.length === 0) continue;
    if (!pruebas.some((r) => r.test(t))) continue;
    if (excluye?.some((r) => r.test(t))) continue;
    encontrados.push(campo);
  }
  return encontrados;
}

/// El campo preguntado, SOLO si es exactamente uno.
///
/// Con dos o mas se devuelve `null` y contesta el modelo. «De cuanto es el enganche y cuantas
/// mensualidades?» son dos preguntas, y un atajo que contestara solo la primera dejaria la segunda
/// sin respuesta sin que nadie lo notara: el asesor leeria una respuesta completa a medias.
export function campoUnico(texto: string): CampoDirecto | null {
  const campos = camposPreguntados(texto);
  return campos.length === 1 ? campos[0] : null;
}

/// Un numero de la base, sin los ceros de relleno: «10.00» -> «10», «7.50» -> «7.5».
export function numeroBonito(v: unknown): string {
  const n = Number(v);
  if (!Number.isFinite(n)) return String(v ?? "");
  return String(Math.round(n * 100) / 100);
}

/// Un importe como se escribe: «$4,797,270 MXN».
///
/// ─── Por que se formatea AQUI ──────────────────────────────────────────────
///
/// Porque el modelo no lo hace igual dos veces. El 04/09/2026 escribio «1 763 100 MXN» —con
/// espacios— en la misma respuesta en que otro precio salio con comas. Un precio mal escrito no es
/// solo feo: «1 763 100» se lee mal en voz alta y se copia peor a una cotizacion.
///
/// Sin centavos a proposito: un precio de lista no los tiene, y arrastrar «.00» en cada cifra de
/// una tabla de treinta y ocho renglones solo estorba.
export function dinero(v: unknown, moneda?: unknown): string | null {
  // `Number(null)` y `Number("")` valen CERO en JavaScript, y los dos son finitos. Sin este
  // guardia, una unidad sin precio salia como «$0» —diciendole al asesor que cuesta cero— en lugar
  // de dejar claro que no esta capturado. Lo atrapo el arnes.
  if (v === null || v === undefined) return null;
  if (typeof v === "string" && v.trim() === "") return null;

  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  const entero = Math.round(n).toString();
  // Los miles se agrupan a mano: `toLocaleString` con un locale depende de que el entorno tenga
  // los datos de ese idioma, y en Deno desplegado eso no esta garantizado.
  let conComas = "";
  for (let i = 0; i < entero.length; i++) {
    if (i > 0 && (entero.length - i) % 3 === 0) conComas += ",";
    conComas += entero[i];
  }
  const cual = String(moneda ?? "").trim();
  return cual === "" ? `$${conComas}` : `$${conComas} ${cual}`;
}

/// Quita del texto las tablas de markdown.
///
/// ─── Por que ───────────────────────────────────────────────────────────────
///
/// El chat pinta TEXTO PLANO, asi que una tabla de markdown se ve como una reja de barras y
/// guiones. Decision del usuario del 04/09/2026: la tabla la pinta la APLICACION, con las unidades
/// que la funcion manda aparte. Es lo mismo que ya se hizo con los enlaces del Drive, y por la
/// misma razon: lo que el modelo dibuja, el modelo lo puede romper.
///
/// Solo se llama cuando de verdad se van a mandar unidades. Si no, una tabla de otra cosa
/// desapareceria sin que nada la sustituyera.
///
/// Una linea es de tabla si empieza por barra. Se cuenta como tabla un tramo de DOS o mas seguidas:
/// una sola barra suelta puede ser parte de una frase -«PB | 1 | 2»- y borrarla se llevaria texto
/// que si dice algo.
export function sinTablas(texto: string): string {
  const lineas = texto.split("\n");
  const fuera = new Set<number>();

  let i = 0;
  while (i < lineas.length) {
    if (!lineas[i].trim().startsWith("|")) {
      i++;
      continue;
    }
    let j = i;
    while (j < lineas.length && lineas[j].trim().startsWith("|")) j++;
    if (j - i >= 2) {
      for (let k = i; k < j; k++) fuera.add(k);
    }
    i = j;
  }

  const salida: string[] = [];
  for (let n = 0; n < lineas.length; n++) {
    if (fuera.has(n)) continue;
    const l = lineas[n];
    // Los renglones vacios seguidos se colapsan: al quitar la tabla queda un hueco donde estaba.
    if (l.trim() === "" && (salida.length === 0 || salida[salida.length - 1].trim() === "")) {
      continue;
    }
    salida.push(l);
  }
  while (salida.length > 0 && salida[salida.length - 1].trim() === "") salida.pop();
  return salida.join("\n").trim();
}

/// La respuesta directa de un campo, o `null` si el dato no esta capturado.
///
/// Devolver `null` es a proposito: se deja pasar al modelo, que sabe ofrecer el brochure o la lista
/// de precios en su lugar. Un «no esta capturado» dicho aqui perderia esa ayuda.
export function textoDe(
  campo: CampoDirecto,
  nombre: string,
  fila: Record<string, unknown>,
): string | null {
  const vacio = (v: unknown) => v === null || v === undefined || String(v).trim() === "";

  switch (campo) {
    case "ubicacion":
      return vacio(fila.ubicacion)
        ? null
        : textoUbicacion(nombre, String(fila.ubicacion), fila.etapa);

    case "amenidades":
      // Entero y tal cual. Es el campo que mas invita a resumir y el que menos lo tolera: el
      // asesor lo esta leyendo para decirselo a un cliente.
      return vacio(fila.amenidades)
        ? null
        : `Amenidades de ${nombre}:\n\n${String(fila.amenidades).trim()}`;

    case "enganche":
      return vacio(fila.enganche_pct)
        ? null
        : `El enganche de ${nombre} es del ${numeroBonito(fila.enganche_pct)}%.`;

    case "mensualidades":
      return vacio(fila.mensualidades)
        ? null
        : `${nombre} se maneja a ${numeroBonito(fila.mensualidades)} mensualidades.`;

    case "etapa":
      return vacio(fila.etapa) ? null : `${nombre} está en etapa ${fila.etapa}.`;
  }
}

/// Cual de los desarrollos nombra un texto, o `null`.
///
/// Devuelve el nombre MAS LARGO que empate: «ZENESIS CLUB» y «ZENESIS» son dos desarrollos
/// distintos, y con el corto ganando, preguntar por el club contestaria del otro.
export function desarrolloEnTexto(texto: string, nombres: string[]): string | null {
  const t = sinAcentos(texto);
  let mejor: string | null = null;
  for (const n of nombres) {
    if (t.includes(sinAcentos(n)) && (mejor === null || n.length > mejor.length)) mejor = n;
  }
  return mejor;
}

/// El desarrollo del que se esta hablando: el ultimo nombrado en la conversacion.
///
/// Se recorre de atras hacia adelante porque la pregunta suele ser «cual es su ubicacion?», con el
/// nombre dos mensajes antes. Es lo mismo que hace Soli con `ultimoUsuario`.
export function desarrolloDelHilo(
  mensajes: Array<{ role: string; content: string }>,
  nombres: string[],
): string | null {
  for (let i = mensajes.length - 1; i >= 0; i--) {
    const encontrado = desarrolloEnTexto(mensajes[i].content ?? "", nombres);
    if (encontrado !== null) return encontrado;
  }
  return null;
}

/// Si la respuesta MENCIONA un documento, para decidir si se pinta su boton.
///
/// El problema que resuelve: `buscar_desarrollo` devuelve todos los documentos del desarrollo junto
/// con sus datos -a proposito, para que el modelo pueda ofrecer la lista de precios cuando el
/// precio no esta capturado-. Pero la funcion los convertia TODOS en botones, asi que preguntar
/// «de cuanto es el enganche?» contestaba bien y ademas pintaba las carpetas del Drive, que ahi no
/// tienen nada que hacer.
///
/// La regla: un documento que se pidio expresamente -por `buscar_documento`- siempre sale. Uno que
/// vino de rebote con los datos del desarrollo sale SOLO si la respuesta lo nombra.
///
/// Se empata por palabras y no por la cadena completa para tolerar el plural y el orden: si el
/// documento se llama «Lista de precios en español» y la respuesta dice «la lista de precios en
/// español», empata; si dice «el brochure», no.
// ─── Como lo pide el asesor y como se llama en el catalogo ──────────────────
//
// El 21/09/2026 un asesor pidio tres veces «el archivo de tipologias de AG117» y SOL contesto «No
// existe un documento de tipologias para AG117 en el Drive», enumerando a continuacion las
// categorias que si hay, entre ellas PLANOS y PROTOTIPOS, que es donde estan. El asesor insistio
// -«Claro que si esta en la carpeta de 7. Planos»- y SOL volvio a decir que no.
//
// No era cosa del modelo. `buscar_documento` filtra con `ilike categoria`, y no hay ninguna
// categoria que se llame «tipologias»: el catalogo las llama «Planos» y «Prototipos», mientras que
// «tipologia» es como se llama en el INVENTARIO -«Tipologia C1 PG 01»-. La misma cosa con dos
// nombres, y nada que los uniera.
//
// La tabla va aqui y no en el prompt por lo de siempre: una equivalencia escrita en el prompt es
// una sugerencia y esta es una regla. Y de paso se aceptan los dedazos que se escriben de verdad
// -«topologias» salio dos veces en ese mismo hilo-.
const EQUIVALENCIAS: Array<{ pide: RegExp; busca: string[]; comoSeLlama: string }> = [
  // Lo que origino esto. Se buscan las DOS: el asesor dijo que estaban en Planos, y la carpeta de
  // Prototipos se llama «Prototipos en espanol: A, B, C, C1, CE y variantes», que son justamente
  // los nombres de las tipologias.
  // «tipografias» no es un dedazo mio: es como se llama el ARCHIVO dentro de la carpeta de Planos
  // -«Tipografias septiembre 2026»-. Tipografia es el diseno de las letras y tipologia es el tipo
  // de vivienda, asi que el nombre del archivo dice una cosa y quiere decir la otra. Se aceptan las
  // dos formas y las dos con dedazo, porque las dos se escriben de verdad.
  { pide: /\bt[io]polog[ií]as?\b|\bt[io]pograf[ií]as?\b/, busca: ["plano", "prototipo"],
    comoSeLlama: "Planos y Prototipos" },
  { pide: /\bprototipos?\b/, busca: ["prototipo"], comoSeLlama: "Prototipos" },
  { pide: /\bplanos?\b|\bplantas?\b|\blayouts?\b|\bdistribucion\b|\barquitectonico\b/,
    busca: ["plano"], comoSeLlama: "Planos" },
  { pide: /\bfolletos?\b|\bbrochure\b|\bcatalogos?\b/, busca: ["brochure"],
    comoSeLlama: "Brochure" },
  { pide: /\brenders?\b|\bfotos?\b|\bimagenes\b|\bimagen\b/, busca: ["render", "foto"],
    comoSeLlama: "Fotos / Renders" },
  { pide: /\bprecios?\b|\btarifas?\b|\bcostos?\b/, busca: ["precio"],
    comoSeLlama: "Lista de precios" },
  { pide: /\bubicacion\b|\bmapa\b|\bdireccion\b|\bcomo llegar\b/, busca: ["ubicacion"],
    comoSeLlama: "Ubicacion" },
  { pide: /\bvideos?\b/, busca: ["video"], comoSeLlama: "Videos" },
  { pide: /\binfonavit\b|\bcredito\b/, busca: ["infonavit"], comoSeLlama: "Infonavit" },
  { pide: /\bdeposito\b|\btransferencia\b|\bcuenta\b/, busca: ["deposito"],
    comoSeLlama: "Cuenta deposito" },
  { pide: /\bcarta\b|\boferta\b/, busca: ["carta oferta"], comoSeLlama: "Carta oferta" },
  { pide: /\bestudio\b|\bmercado\b/, busca: ["estudio"], comoSeLlama: "Estudio de Mercado" },
  { pide: /\bairdna\b|\brentabilidad\b/, busca: ["airdna"], comoSeLlama: "Reporte AirDNA" },
  { pide: /\bcv\b|\bcurriculum\b|\bdesarrollador\b/, busca: ["desarrollador"],
    comoSeLlama: "CV Desarrollador" },
  { pide: /\bchecklist\b|\brequisitos?\b/, busca: ["checklist"], comoSeLlama: "Checklist cliente" },
];

/** Con que se busca en el catalogo lo que pidio el asesor.
 *
 * `patrones` son los fragmentos con los que consultar -siempre incluye lo que pidio tal cual, para
 * que una categoria nueva que nadie ha traducido aqui siga encontrandose-. `comoSeLlama` es para
 * decirselo: «las tipologias estan en Planos y Prototipos».
 *
 * Fragmentos y no nombres completos a proposito: si alguien renombra una categoria en el panel,
 * «plano» sigue coincidiendo con «Planos AG117» y la equivalencia no se rompe en silencio.
 */
export function comoSeBusca(pedido: string): { patrones: string[]; comoSeLlama: string | null } {
  const p = sinAcentos(pedido).toLowerCase().trim();
  if (p === "") return { patrones: [], comoSeLlama: null };

  const patrones = [p];
  const nombres: string[] = [];
  for (const e of EQUIVALENCIAS) {
    if (!e.pide.test(p)) continue;
    for (const b of e.busca) if (!patrones.includes(b)) patrones.push(b);
    nombres.push(e.comoSeLlama);
  }
  return {
    patrones,
    // Solo se avisa cuando lo que pidio NO es ya el nombre de la categoria: decirle que «los planos
    // estan en Planos» es ruido.
    comoSeLlama: nombres.length > 0 && !patrones.slice(1).some((b) => p.includes(b))
      ? nombres.join(" y ")
      : null,
  };
}

const MESES_EN_NOMBRE: Record<string, number> = {
  enero: 1, febrero: 2, marzo: 3, abril: 4, mayo: 5, junio: 6,
  julio: 7, agosto: 8, septiembre: 9, setiembre: 9, octubre: 10,
  noviembre: 11, diciembre: 12,
};

/** El mes y año que lleva el nombre de un documento, como numero comparable. 0 si no lleva.
 *
 * ─── Para que ────────────────────────────────────────────────────────────────
 *
 * Los archivos que se renuevan llevan la fecha en el nombre: «Tipografias septiembre 2026»,
 * «Brochure PC - AG117 - 1 Sept». Preguntado «mandame el ULTIMO archivo de tipologias» -se pregunto
 * tal cual el 08/09/2026- hay que saber cual es el ultimo, y el orden alfabetico no sirve: octubre
 * va antes que septiembre en el alfabeto y despues en el calendario.
 *
 * Devuelve `anio * 100 + mes` para poder ordenar con una resta. Sin año pero con mes, se usa el año
 * en curso; asi «Tipografias octubre» sigue quedando despues de «Tipografias septiembre».
 */
/// Abreviaturas, que es como vienen los brochures: «1 Sept», «15 dic».
///
/// Sin `[a-z]*` detras a proposito. Escrito `\b(mar)[a-z]*\b` -mi primera version- «marca» se leia
/// como marzo y «mayor» como mayo. Exigiendo el limite de palabra justo despues, «mar» solo coincide
/// cuando esta suelto. Por eso «sept» va aparte y antes: con «sep» a secas no coincidiria, porque
/// detras lleva una «t».
const ABREVIATURAS: Record<string, number> = {
  ene: 1, feb: 2, mar: 3, abr: 4, may: 5, jun: 6,
  jul: 7, ago: 8, sep: 9, sept: 9, oct: 10, nov: 11, dic: 12,
};

export function fechaEnNombre(nombre: string, anioActual: number): number {
  const n = sinAcentos(nombre).toLowerCase();

  // Una fecha numerica entera -«01.09.26», «15/12/2026»- se lee DD-MM-AA, que es como se escribe
  // aqui. Va primero porque trae el mes Y el año, sin tener que adivinar ninguno.
  const numerica = n.match(/\b(\d{1,2})[.\/-](\d{1,2})[.\/-](\d{2,4})\b/);
  if (numerica) {
    const m = Number(numerica[2]);
    const a = Number(numerica[3]);
    if (m >= 1 && m <= 12) return (a < 100 ? 2000 + a : a) * 100 + m;
  }

  // Con limite de palabra, no con `includes`: «mayo» es subcadena de «mayor» y de «mayoreo», asi que
  // «Plano mayor detalle» se leia como mayo de 2026. Lo atrapo la prueba.
  let mes = 0;
  for (const [palabra, num] of Object.entries(MESES_EN_NOMBRE)) {
    if (new RegExp(`\\b${palabra}\\b`).test(n)) { mes = num; break; }
  }
  if (mes === 0) {
    const corto = n.match(/\b(sept|ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic)\.?\b/);
    if (corto) mes = ABREVIATURAS[corto[1]] ?? 0;
  }

  const cuatro = n.match(/\b(20\d{2})\b/);
  // Sin año pero con mes, el año en curso: asi «Tipografias octubre» sigue quedando despues de
  // «Tipografias septiembre».
  const anio = cuatro ? Number(cuatro[1]) : anioActual;

  if (mes === 0 && !cuatro) return 0;
  return anio * 100 + mes;
}

const NOMBRE_DEL_MES = [
  "", "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
];

/** Si el nombre de un documento apunta a un mes ya pasado, la frase que lo dice. `null` si no.
 *
 * ─── Por que hace falta ──────────────────────────────────────────────────────
 *
 * El archivo de tipologias lo SUSTITUYE un tercero dentro de la carpeta de Planos, y al subir el
 * nuevo el identificador de Drive cambia: el enlace guardado deja de servir. Como quien lo sustituye
 * no es de la casa, puede pasar tiempo antes de que alguien lo note y nos pase el enlace nuevo.
 *
 * Mientras tanto, SOL entregaria un enlace muerto con toda la seguridad del mundo, y eso es peor que
 * no tener enlace: el asesor abre un archivo borrado delante de un cliente y no sabe por que.
 *
 * Esto no impide que caduque —sin acceso a la API de Drive no hay manera— pero deja de ser
 * silencioso: el nombre lleva el mes, asi que se compara con hoy y se dice. Vale para cualquier
 * documento que se renueve, no solo para este: las listas de precios y los brochures tambien llevan
 * la fecha en el nombre.
 */
export function avisoDeVigencia(nombre: string, hoy: string): string | null {
  const anioActual = Number(hoy.slice(0, 4));
  const suya = fechaEnNombre(nombre, anioActual);
  if (suya === 0) return null;

  const mes = suya % 100;
  // Con año pero sin mes no se compara: «Lista 2026» no dice nada de si esta al dia.
  if (mes < 1 || mes > 12) return null;

  const ahora = anioActual * 100 + Number(hoy.slice(5, 7));
  if (suya >= ahora) return null;

  return `El nombre dice ${NOMBRE_DEL_MES[mes]} de ${Math.floor(suya / 100)} y hoy estamos en `
    + `${NOMBRE_DEL_MES[Number(hoy.slice(5, 7))]} de ${anioActual}. Puede que lo hayan sustituido `
    + `por uno mas nuevo y que este enlace ya no abra. Dilo al entregarlo y ofrece la carpeta.`;
}

export function documentoMencionado(
  respuesta: string,
  doc: { nombre?: unknown; categoria?: unknown },
): boolean {
  const r = sinAcentos(respuesta);
  for (const candidato of [doc.nombre, doc.categoria]) {
    if (typeof candidato !== "string" || candidato.length === 0) continue;
    const palabras = sinAcentos(candidato)
      .split(/[^a-z0-9]+/)
      .filter((p) => p.length >= 4);
    if (palabras.length === 0) continue;
    // La «s» final se prueba tambien sin ella: la categoria se llama «Listas de precios» y el
    // modelo escribe «la lista de precios». Al reves no hace falta, porque «lista» ya es subcadena
    // de «listas». El arnes atrapo esto: el comentario decia que toleraba el plural y no era cierto.
    const esta = (p: string) =>
      r.includes(p) || (p.endsWith("s") && r.includes(p.slice(0, -1)));
    if (palabras.every(esta)) return true;
  }
  return false;
}

/// La respuesta de la via directa de ubicacion.
///
/// Cita el campo COMPLETO y tal cual. Recortarlo es justo lo que hacia el modelo.
export function textoUbicacion(nombre: string, ubicacion: string, etapa?: unknown): string {
  const donde = `${nombre} está en ${ubicacion.trim().replace(/\.$/, "")}.`;
  return typeof etapa === "string" && etapa.length > 0
    ? `${donde}\n\nEtapa: ${etapa}.`
    : donde;
}
