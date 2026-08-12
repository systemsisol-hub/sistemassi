// Las preguntas que se contestan SIN pasar por el modelo, y el guardia de lo que si pasa.
//
// Las dos cosas juntas a proposito: son las dos caras de la misma decision. Una via directa es un
// dato que se entrega sin preguntarle al modelo; el guardia es lo que impide que el modelo entregue
// un dato que nadie consulto. Cada vez que una via directa cubre una pregunta, el guardia tiene una
// cosa menos que atrapar.

import { sinAcentos } from "./nombres.ts";

/** Si la persona pregunta por SUS PROPIAS vacaciones.
 *
 * ─── Por que esto no pasa por el modelo ──────────────────────────────────────
 *
 * Es la pregunta mas frecuente y la que mas importa, y depender del modelo para ella no funciono:
 *
 *   - unas veces no llamaba a la herramienta y se inventaba el saldo;
 *   - otras el guardia lo bloqueaba con razon, y la persona se quedaba sin respuesta;
 *   - y al bloquearlo, mi propio texto de rechazo quedaba en la memoria del hilo y el modelo lo
 *     repetia palabra por palabra en la pregunta siguiente, sin consultar nada. Dos respuestas
 *     identicas seguidas, las dos negandose, con los datos ahi al alcance.
 *
 * Aqui no hay nada que el modelo tenga que decidir: quien pregunta ya esta identificado, el permiso
 * ya esta comprobado y el calculo es determinista. Se consulta y se contesta. Sale mas rapido, no
 * cuesta una llamada al modelo, y no puede inventar porque el modelo no participa.
 *
 * Se exige que hable de SI MISMA. Si menciona a alguien —«las de Hector»— se deja pasar al modelo,
 * que es quien sabe resolver un nombre y pedir aclaraciones.
 */
export function preguntaSusVacaciones(texto: string): boolean {
  const t = sinAcentos(texto).toLowerCase();
  if (!/vacacion|dias disponibles|dias que me quedan|saldo de dias/.test(t)) return false;

  // «de <alguien>» quiere decir que pregunta por otra persona. `de` sola no basta: «cuantos dias de
  // vacaciones tengo» lleva un `de` que no introduce a nadie, y hay que dejarlo pasar.
  //
  // `mi` y `mis` NO se excluyen, a proposito: «las vacaciones de mi jefe» habla de otra persona, y
  // colarlo por esta via devolveria el saldo de quien pregunta como si fuera el de su jefe. A cambio,
  // «cuantos dias de mis vacaciones quedan» se va al modelo, que es un coste mucho menor que contestar
  // con los datos de alguien equivocado.
  if (/\bde\s+(?!vacacion|dias|antiguedad|la\s|los\s|las\s|el\s)[a-z]{2,}/.test(t)) {
    return false;
  }
  return /\bmis\b|\bmi\b|\btengo\b|me\s+quedan|me\s+toca|me\s+corresponden/.test(t);
}

/** El texto de una respuesta de vacaciones, armado con los datos de la herramienta.
 *
 * Corto a proposito: la aplicacion pinta la tarjeta con el detalle y el puente de WhatsApp arma su
 * propia ficha a partir de `structured`. Esto es lo que se lee en la burbuja.
 */
export function textoVacacionesPropias(datos: Record<string, unknown>): string {
  const total = datos.total_disponible as number;
  const periodos = (datos.periodos ?? []) as Array<Record<string, unknown>>;
  const actual = periodos.find((pe) => pe.es_periodo_actual === true);
  const cola = actual
    ? ` En el periodo actual (${actual.periodo}) te quedan ${actual.dias_disponibles}.`
    : "";
  return `Tienes ${total} ${total === 1 ? "dia" : "dias"} de vacaciones disponibles en total.${cola}`
    + textoUltimaSolicitud(datos, "Tu");
}

/** La ultima solicitud, en una linea. Vacio si no hay ninguna.
 *
 * Pedido tal cual: al preguntar por las vacaciones de alguien se quiere la tabla Y el ultimo registro.
 * Se distingue si esta POR VENIR porque es lo que de verdad se quiere saber: la ultima de Marco empieza
 * el 21/08 y hoy es el 12.
 */
export function textoUltimaSolicitud(datos: Record<string, unknown>, posesivo: string): string {
  const lista = (datos.solicitudes ?? []) as Array<Record<string, unknown>>;
  if (lista.length === 0) return " No tiene solicitudes registradas.";

  const u = lista[0];
  const cuando = u.por_venir === true ? "próxima salida" : "última salida";
  const dias = u.dias;
  return ` ${posesivo} ${cuando}: ${u.fecha_inicio} al ${u.fecha_fin}`
    + ` (${dias} ${dias === 1 ? "día" : "días"}, ${u.status}, periodo ${u.periodo})`
    + `, con regreso el ${u.fecha_regreso}.`;
}

const MESES: Record<string, number> = {
  enero: 1, febrero: 2, marzo: 3, abril: 4, mayo: 5, junio: 6,
  julio: 7, agosto: 8, septiembre: 9, setiembre: 9, octubre: 10,
  noviembre: 11, diciembre: 12,
};

/** Si la persona pregunta por cumpleaños, y de que mes o rango.
 *
 * ─── Por que esto tampoco pasa por el modelo ─────────────────────────────────
 *
 * Con la herramienta ya puesta, «cumpleaños de este mes» y «quien cumple esta semana» salieron
 * perfectos, y «cumpleaños de septiembre» acabo en el guardia: el modelo no llamo a la herramienta y
 * el guardia bloqueo la respuesta para que no inventara los nueve nombres de ese mes.
 *
 * Callar es mejor que inventar, pero es la respuesta equivocada cuando el dato esta a mano. Es el
 * mismo caso que las vacaciones propias y las del jefe: no hay nada que el modelo tenga que decidir
 * —el mes se lee de la pregunta y la consulta es determinista— asi que se resuelve aqui.
 *
 * Se exige que hable de cumpleaños de verdad: «cumple 5 años en la empresa» habla de antiguedad y
 * tiene que seguir su camino.
 */
export function preguntaCumpleanos(
  texto: string,
  anterior: string,
): { mes: number | null; soloEstaSemana: boolean } | null {
  const t = sinAcentos(texto).toLowerCase();
  const esDeCumples = (x: string) => /cumplea|cumplen?\s+anos|quien(es)?\s+cumple/.test(x);

  // Una pregunta de seguimiento no repite el tema: «y de septiembre?» viene despues de «cumpleaños
  // de este mes» y no lleva la palabra. Reportado: por eso la via directa no se activo y el modelo
  // contesto de memoria, inventando cuatro personas.
  //
  // Se exige que sea CORTA y que solo aporte un mes o un rango: asi «y las vacaciones de septiembre?»
  // -que es otra cosa- no se cuela por aqui.
  const palabras = t.split(/\s+/).filter((w) => w.length > 0);
  const soloAportaFecha = palabras.length <= 5
    && !/vacacion|incidencia|inventario|empleado|telefono/.test(t);

  const seguimiento = !esDeCumples(t)
    && esDeCumples(sinAcentos(anterior).toLowerCase())
    && soloAportaFecha;

  if (!esDeCumples(t) && !seguimiento) return null;

  const soloEstaSemana = /esta semana|de la semana|semana actual/.test(t);
  for (const [nombre, num] of Object.entries(MESES)) {
    if (t.includes(nombre)) return { mes: num, soloEstaSemana };
  }
  // Un seguimiento que no nombra mes ni semana no aporta nada: mejor que lo lleve el modelo.
  if (seguimiento && !soloEstaSemana) return null;
  return { mes: null, soloEstaSemana };
}

/// Los meses para escribirlos. Aparte de `MESES`, que sirve para LEERLOS y por eso acepta dos formas
/// de septiembre; aquí hace falta una sola por mes.
const NOMBRE_MES = ["", "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];

/** El texto de una respuesta de cumpleaños, armado con los datos de la herramienta. */
export function textoCumpleanos(datos: Record<string, unknown>): string {
  const gente = (datos.results ?? []) as Array<Record<string, unknown>>;
  const mes = typeof datos.mes === "number" ? datos.mes : 0;
  const nombreMes = NOMBRE_MES[mes] ?? "";
  const donde = datos.rango
    ? `esta semana (${datos.rango} de ${nombreMes})`
    : `en ${nombreMes}`;

  if (gente.length === 0) return `No hay cumpleaños ${donde}.`;

  const lineas = gente.map((g) => `• ${g.dia} — ${g.nombre}`
    + (g.puesto ? `, ${g.puesto}` : ""));
  return `Cumpleaños ${donde} (${gente.length}):\n${lineas.join("\n")}`;
}

/** Si la respuesta afirma un dato de la base que ninguna herramienta respaldo en este turno.
 *
 * ─── El fallo ────────────────────────────────────────────────────────────────
 *
 * El modelo contesta sin llamar a la herramienta y se inventa los datos, con aplomo y con formato de
 * tabla. Casos reales, todos comprobados contra la base:
 *
 *   - «ENRIQUE ORTEGA GOMEZ: 0 dias disponibles» — tiene 102.
 *   - «Ana Maria Lopez Vigil, 1250» — es la 0162.
 *   - «CLAUDIA PATRICIA BRAVO LOMELI — empleado 2277» — no existe; el 2277 es otra persona.
 *   - «JESUS BRAVO LOMELI (empleado 4011)» — no existe, y el numero mas alto de la base es 2487.
 *
 * Los dos ultimos salieron en la APLICACION, no por WhatsApp. Al principio parecia cosa del puente
 * -la pagina acertaba porque pinta una tarjeta con los datos crudos y la vista va a la tarjeta- pero
 * la prosa de la pagina tiene el mismo problema, solo que tapado. Por eso esto vive aqui, en lo unico
 * que comparten los dos canales, y no en el puente.
 *
 * ─── Que se considera un dato que no se puede inventar ───────────────────────
 *
 * Dos cosas, las dos reconocidas en el TEXTO y no en la pregunta:
 *
 *   - un numero de empleado, que es un hecho de la base y sin herramienta no tiene de donde salir;
 *   - un SALDO: «N dias disponibles», «Disponibles: N», «Total disponible».
 *
 * Mirar la pregunta fue mi primer intento y tenia un agujero por cada lado. Exigir que la pregunta
 * mencionara vacaciones dejaba pasar los seguimientos —«y las de bravo lomeli», que es justo el caso
 * real del 12/08— y a la vez bloqueaba el conocimiento general, porque «con 5 anos la ley da 20 dias»
 * viene de una pregunta sobre vacaciones y es correcto.
 *
 * Es la palabra «disponible» la que convierte una cifra en la afirmacion del saldo de alguien. Sin
 * ella, hablar de dias es hablar de la ley, y eso el modelo lo puede contestar solo.
 */
export function afirmaDatoSinRespaldo(
  texto: string,
  conDatos: Set<string>,
  huboLlamadas = conDatos.size > 0,
): boolean {
  const t = sinAcentos(texto).toLowerCase();

  // Un numero de empleado solo puede venir de la base.
  if (/empleado\s*#?\s*:?\s*\d{3,5}/.test(t)
      && !conDatos.has("buscar_colaborador")
      && !conDatos.has("calcular_vacaciones")) {
    return true;
  }

  // Un saldo solo puede venir de calcular_vacaciones.
  //
  // Se mira por separado que haya una CIFRA DE DIAS y que se hable de DISPONIBLES, sin exigir que
  // vayan pegadas. Mi primera version pedia «dias disponibles» juntas y se le escapo esto:
  //
  //   «HECTOR FIGUEROA VALLEJO tiene 105 dias de vacaciones disponibles.»
  //
  // Son 40, no 105. Dos palabras en medio bastaron para colar una cifra inventada, que es
  // exactamente el fallo que esto tenia que atrapar.
  //
  // Se exige que la cifra sea de DIAS: «hay 3 laptops disponibles» habla de inventario y no debe
  // bloquearse por no haber corrido calcular_vacaciones.
  const cifraDeDias = /\d+\s*dias?\b/.test(t);
  const hablaDeSaldo = /disponibl/.test(t) || /total\s+disponible/.test(t);
  if (cifraDeDias && hablaDeSaldo && !conDatos.has("calcular_vacaciones")) return true;
  if (/disponibles?\s*:?\s*\**\s*\d/.test(t) && !conDatos.has("calcular_vacaciones")) return true;

  // Un cumpleaños con fecha solo puede venir de buscar_cumpleanos.
  //
  // Se pide que haya un digito: «no tengo acceso a los cumpleaños» es una respuesta legitima y no
  // afirma la fecha de nadie. Reportado: preguntado por los cumpleaños de la semana, invento a una
  // persona; la pantalla no muestra a NADIE entre el 10 y el 16 de agosto.
  if (/cumplea|cumple\b/.test(t) && /\d/.test(t)
      && !conDatos.has("buscar_cumpleanos")) {
    return true;
  }

  // Y la regla que NO depende de ninguna palabra: sin haber consultado NADA, no se entrega una lista
  // de registros.
  //
  // Las reglas de arriba buscan palabras, y eso falla por los dos lados. El caso que lo demuestra:
  // preguntado «y de septiembre?» invento cuatro personas y empezo la respuesta con «umpleaños en
  // septiembre (4):» —sin la C inicial— asi que /cumplea/ no coincidio y paso. Una letra de menos
  // basto para colar cuatro nombres falsos.
  //
  // Dos renglones que empiezan por vinieta o barra Y llevan un numero son una tabla de datos, y el
  // modelo no tiene de donde sacarla si no llamo a ninguna herramienta. Se exige el numero para no
  // bloquear una lista de lo que SI puede hacer, que no lleva cifras.
  // Se mira si se LLAMO a alguna herramienta, no si alguna trajo datos. Una lista de candidatos es
  // legitima aunque la consulta no haya encontrado a la persona: preguntar «¿es alguno de estos?» es
  // justo lo que tiene que hacer.
  if (!huboLlamadas) {
    const renglonesDeDatos = (texto.match(/^\s*[•\-*|]\s*\**\s*\d/gm) || []).length;
    if (renglonesDeDatos >= 2) return true;
  }

  return false;
}
