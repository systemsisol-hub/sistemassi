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
