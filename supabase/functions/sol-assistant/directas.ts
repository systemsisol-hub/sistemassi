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
