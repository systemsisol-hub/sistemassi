// Convertir «septiembre», «esta semana» o «la segunda quincena de octubre» en dos fechas.
//
// ─── Por que esto no lo hace el modelo ───────────────────────────────────────
//
// Porque es aritmetica de calendario, y el modelo no sabe que dia es hoy salvo por lo que le diga
// el prompt. Pedirle que calcule «del lunes al domingo de esta semana» es pedirle que invente dos
// fechas que luego se usan para filtrar la base: si se equivoca, la lista sale mal y nada avisa.
//
// Aqui se calcula una vez, se comprueba con pruebas, y lo que se le entrega al modelo son las
// fechas ya resueltas junto con la etiqueta en palabras para que las pueda repetir.
import { sinAcentos } from "./nombres.ts";

/** Un rango de fechas, en el formato en que la base guarda `date`. */
export interface Rango {
  /** AAAA-MM-DD, incluido. */
  desde: string;
  /** AAAA-MM-DD, incluido. */
  hasta: string;
  /** Como se dice, para que la respuesta lo repita: «septiembre de 2026». */
  etiqueta: string;
}

const MESES: Record<string, number> = {
  enero: 1, febrero: 2, marzo: 3, abril: 4, mayo: 5, junio: 6,
  julio: 7, agosto: 8, septiembre: 9, setiembre: 9, octubre: 10,
  noviembre: 11, diciembre: 12,
};

const NOMBRE_MES = [
  "", "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
];

/// AAAA-MM-DD a partir de numeros, sin pasar por `toISOString`.
///
/// `toISOString` convierte a UTC, y en Mexico eso resta horas: un 1 de septiembre a las 00:00 sale
/// como 31 de agosto. Todo un rango corrido un dia, y en una lista de vacaciones eso es alguien de
/// mas o de menos.
function iso(y: number, m: number, d: number): string {
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

/// El ultimo dia del mes. El dia 0 del siguiente es el ultimo de este, bisiestos incluidos.
function ultimoDia(y: number, m: number): number {
  return new Date(y, m, 0).getDate();
}

/// El año que corresponde a un mes dicho a secas.
///
/// Preguntar «quien se va en enero» en septiembre casi siempre mira hacia adelante, asi que un mes
/// ya pasado se entiende del año que viene. La etiqueta SIEMPRE lleva el año escrito, de modo que
/// si la suposicion no era la buena se ve en la respuesta en vez de quedar escondida.
function anioDe(mes: number, hoy: Date): number {
  const y = hoy.getFullYear();
  return mes < hoy.getMonth() + 1 ? y + 1 : y;
}

function delMes(y: number, m: number): Rango {
  return { desde: iso(y, m, 1), hasta: iso(y, m, ultimoDia(y, m)), etiqueta: `${NOMBRE_MES[m]} de ${y}` };
}

/// El lunes de la semana de una fecha. Lunes y no domingo: es como se cuenta la semana aqui.
function lunesDe(d: Date): Date {
  const x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  // getDay() da 0 el domingo; ese domingo pertenece a la semana que empezo seis dias antes.
  const desplazamiento = (x.getDay() + 6) % 7;
  x.setDate(x.getDate() - desplazamiento);
  return x;
}

function semanaDesde(lunes: Date, etiqueta: string): Rango {
  const domingo = new Date(lunes.getFullYear(), lunes.getMonth(), lunes.getDate() + 6);
  return {
    desde: iso(lunes.getFullYear(), lunes.getMonth() + 1, lunes.getDate()),
    hasta: iso(domingo.getFullYear(), domingo.getMonth() + 1, domingo.getDate()),
    etiqueta,
  };
}

/** Las dos fechas que se piden, o `null` si el texto no dice ninguna.
 *
 * El orden en que se prueban las formas importa: «la segunda quincena de octubre» tambien contiene
 * «octubre», y «del 5 al 12 de octubre» tambien. Lo mas especifico va primero.
 */
export function rangoDeFechas(texto: string, hoy: Date): Rango | null {
  const t = sinAcentos(texto).toLowerCase();

  // ── Fechas escritas enteras ───────────────────────────────────────────────
  const isos = t.match(/\d{4}-\d{2}-\d{2}/g);
  if (isos && isos.length >= 2) {
    const [a, b] = [isos[0], isos[1]].sort();
    return { desde: a, hasta: b, etiqueta: `del ${a} al ${b}` };
  }
  if (isos && isos.length === 1) {
    return { desde: isos[0], hasta: isos[0], etiqueta: `el ${isos[0]}` };
  }

  // ── «del 5 al 12 de octubre» ──────────────────────────────────────────────
  //
  // El mes se dice una vez y vale para los dos dias. Si no se dice, es el mes en curso.
  const tramo = t.match(
    /\bdel?\s+(\d{1,2})\s+al?\s+(\d{1,2})(?:\s+de\s+([a-z]+))?(?:\s+(?:de\s+)?(\d{4}))?/,
  );
  if (tramo) {
    const d1 = Number(tramo[1]);
    const d2 = Number(tramo[2]);
    const m = tramo[3] && MESES[tramo[3]] ? MESES[tramo[3]] : hoy.getMonth() + 1;
    const y = tramo[4] ? Number(tramo[4]) : (tramo[3] ? anioDe(m, hoy) : hoy.getFullYear());
    if (d1 >= 1 && d2 >= 1 && d1 <= ultimoDia(y, m) && d2 <= ultimoDia(y, m)) {
      const [a, b] = d1 <= d2 ? [d1, d2] : [d2, d1];
      return {
        desde: iso(y, m, a),
        hasta: iso(y, m, b),
        etiqueta: `del ${a} al ${b} de ${NOMBRE_MES[m]} de ${y}`,
      };
    }
  }

  // ── Quincenas ─────────────────────────────────────────────────────────────
  //
  // Del 1 al 15 y del 16 al fin de mes, que es como las parte la tabla de registros por quincena de
  // la pagina de Incidencias. Misma division en los dos sitios a proposito: si aqui se contara de
  // otra manera, la lista de Soli y la tabla dirian cosas distintas de la misma quincena.
  const quincena = t.match(
    /\b(primera|1a|1ra|segunda|2a|2da)\s+quincena(?:\s+de\s+([a-z]+))?(?:\s+(?:de\s+)?(\d{4}))?/,
  );
  if (quincena) {
    const primera = /^(primera|1a|1ra)$/.test(quincena[1]);
    const m = quincena[2] && MESES[quincena[2]] ? MESES[quincena[2]] : hoy.getMonth() + 1;
    const y = quincena[3]
      ? Number(quincena[3])
      : (quincena[2] ? anioDe(m, hoy) : hoy.getFullYear());
    return primera
      ? { desde: iso(y, m, 1), hasta: iso(y, m, 15),
          etiqueta: `la primera quincena de ${NOMBRE_MES[m]} de ${y}` }
      : { desde: iso(y, m, 16), hasta: iso(y, m, ultimoDia(y, m)),
          etiqueta: `la segunda quincena de ${NOMBRE_MES[m]} de ${y}` };
  }

  // ── Semanas ───────────────────────────────────────────────────────────────
  if (/\b(la\s+)?(proxima|siguiente)\s+semana\b|\bsemana\s+(que\s+(viene|entra)|entrante|proxima)\b/
      .test(t)) {
    const l = lunesDe(hoy);
    l.setDate(l.getDate() + 7);
    return semanaDesde(l, "la proxima semana");
  }
  if (/\besta\s+semana\b|\bde\s+la\s+semana\b|\bsemana\s+actual\b|\bpor\s+semana\b/.test(t)) {
    return semanaDesde(lunesDe(hoy), "esta semana");
  }

  // ── Dias sueltos ──────────────────────────────────────────────────────────
  if (/\bhoy\b/.test(t)) {
    const d = iso(hoy.getFullYear(), hoy.getMonth() + 1, hoy.getDate());
    return { desde: d, hasta: d, etiqueta: "hoy" };
  }
  if (/\bmanana\b/.test(t)) {
    const m = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate() + 1);
    const d = iso(m.getFullYear(), m.getMonth() + 1, m.getDate());
    return { desde: d, hasta: d, etiqueta: "manana" };
  }

  // ── Meses ─────────────────────────────────────────────────────────────────
  if (/\b(el\s+)?(proximo|siguiente)\s+mes\b|\bmes\s+(que\s+(viene|entra)|entrante|proximo)\b/
      .test(t)) {
    const m = hoy.getMonth() + 2;
    return m > 12 ? delMes(hoy.getFullYear() + 1, 1) : delMes(hoy.getFullYear(), m);
  }
  if (/\beste\s+mes\b|\bdel\s+mes\b|\bmes\s+actual\b/.test(t)) {
    return delMes(hoy.getFullYear(), hoy.getMonth() + 1);
  }
  for (const [nombre, num] of Object.entries(MESES)) {
    // Se exige que la palabra termine ahi: sin esto «marzo» coincidiria dentro de un apellido.
    if (new RegExp(`\\b${nombre}\\b`).test(t)) {
      const anio = t.match(new RegExp(`${nombre}\\s+(?:de\\s+)?(\\d{4})`));
      return delMes(anio ? Number(anio[1]) : anioDe(num, hoy), num);
    }
  }

  return null;
}
