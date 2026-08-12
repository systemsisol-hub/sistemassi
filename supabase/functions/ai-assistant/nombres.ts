// Encontrar a la persona de la que se esta hablando.
//
// Es la parte del asistente que mas veces se rompio, y por eso esta sola: nombres con acentos, con
// la N con virgulilla, con dedazos, con un apellido de menos, o con el numero de empleado en vez del
// uuid. Tambien las fechas de antiguedad, que deciden cuantos dias de ley le tocan a cada quien.

import type { Db } from "./config.ts";

/** Si una cadena tiene forma de uuid.
 *
 * Hace falta porque el modelo confunde el uuid con el número de empleado. Sin esto, un
 * `.eq("id","0170")` hace que Postgres falle con «invalid input syntax for type uuid» y el error
 * llega al modelo como un fallo genérico que puede acabar presentándole un cero al usuario.
 */
export function esUuid(s: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s.trim());
}

/** Cuántos candidatos se traen antes de cruzar las palabras en código. */
export const CANDIDATOS_NOMBRE = 500;

/** Quita acentos dejando la Ñ intacta.
 *
 * Medido sobre los 2488 perfiles: **ninguno** tiene vocales acentuadas, pero **122 llevan Ñ**. Hay
 * que normalizar lo que escribe la persona —"Gómez" no empata con "GOMEZ" usando ilike— sin tocar la
 * eñe, porque "Peñafiel" sí está guardado con ella y volverlo "Penafiel" rompería búsquedas que hoy
 * funcionan. Por eso el mapeo es explícito y no un normalize("NFD"), que descompone la ñ igual que
 * las vocales.
 */
export function sinAcentos(s: string): string {
  const mapa: Record<string, string> = {
    "á":"a","é":"e","í":"i","ó":"o","ú":"u","ü":"u",
    "Á":"A","É":"E","Í":"I","Ó":"O","Ú":"U","Ü":"U",
  };
  return s.replace(/[áéíóúüÁÉÍÓÚÜ]/g, (c) => mapa[c] ?? c);
}

/** Palabras que nunca son parte de un nombre.
 *
 * El modelo no siempre manda el nombre limpio: puede pasar la frase entera —«vacaciones de enrique
 * ortega gomez», «el de hector figeroa»—. Sin quitarlas, el cruce exige que «vacaciones» y «de»
 * aparezcan tambien en el nombre de la persona, y devuelve que no existe.
 *
 * Quitarlas solo puede AFLOJAR el cruce, nunca endurecerlo, asi que no puede provocar un fallo de
 * busqueda. Importa para «DE LA GARZA», que es un apellido real: al quitar «de» y «la» queda
 * «GARZA», que sigue empatando.
 */
const PALABRAS_VACIAS = new Set([
  "vacaciones", "vacacion", "dias", "dia", "saldo", "antiguedad",
  "de", "del", "la", "el", "los", "las", "lo",
  "mi", "mis", "su", "sus", "y", "e", "para", "con", "que",
  "empleado", "numero", "colaborador", "señor", "sr", "sra", "don", "doña",
]);

/** Parte un nombre completo en palabras aptas para un filtro.
 *
 * Se descarta todo lo que no sea letra: dentro de un `or=(...)` una coma, un punto o un paréntesis
 * cambian el significado del filtro, así que sanear no es cosmético. Y se quitan las palabras que
 * nunca son parte de un nombre; ver `PALABRAS_VACIAS`.
 */
export function tokensDeNombre(raw: string): string[] {
  return sinAcentos(raw)
    .split(/\s+/)
    .map((t) => t.replace(/[^A-Za-zÑñ]/g, ""))
    .filter((t) => t.length > 0 && !PALABRAS_VACIAS.has(t.toLowerCase()));
}

/** La palabra con la que conviene pedirle candidatos a la base.
 *
 * Cualquier palabra sirve —quien tenga que empatar con TODAS empata también con una— así que el
 * prefiltro es correcto sea cual sea. Se elige la más larga porque suele ser la más rara: medido,
 * "MONTOYA" trae 2 candidatos y "MARIA" 180.
 */
export function tokenGuia(tokens: string[]): string {
  return tokens.reduce((a, b) => (b.length > a.length ? b : a));
}

/** Si un perfil empata con TODAS las palabras, cada una en nombre, paterno o materno.
 *
 * El cruce se hace aquí y no en la consulta a propósito. Encadenar varios `.or()` en PostgREST
 * debería unirlos con AND, pero no hay forma de comprobarlo contra esta base sin una sesión, y una
 * búsqueda de personas que falle en silencio es justo lo que se está arreglando. Con un solo `or=`
 * no hay ambigüedad posible, y este cruce sí se puede probar.
 */
export function empataNombre(fila: Record<string, unknown>, tokens: string[]): boolean {
  const campos = [fila.nombre, fila.paterno, fila.materno]
    .map((v) => (typeof v === "string" ? v.toUpperCase() : ""));
  return tokens.every((t) => {
    const T = t.toUpperCase();
    return campos.some((c) => c.includes(T));
  });
}

/** Cuantos candidatos se traen en la pasada tolerante. Mas alta que la exacta porque el prefiltro es
 * mas ancho: medido, el peor caso realista -MAR|ANT|MON|LOP- trae 547 de los 2488 perfiles. */
export const CANDIDATOS_APROXIMADO = 1500;

/** Distancia de edicion (Levenshtein) entre dos palabras.
 *
 * Se escribe a mano porque `pg_trgm` no esta instalada en la base y activarla es una migracion. Con
 * la extension esto se haria en SQL con `similarity()`, que es mejor: aqui hay que traer candidatos y
 * filtrarlos en codigo. Si algun dia se instala, este camino se puede simplificar.
 */
function distancia(a: string, b: string): number {
  if (a === b) return 0;
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;
  let previa = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const fila = [i];
    for (let j = 1; j <= b.length; j++) {
      fila[j] = Math.min(
        previa[j] + 1,
        fila[j - 1] + 1,
        previa[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1),
      );
    }
    previa = fila;
  }
  return previa[b.length];
}

/** Cuantas letras puede fallar una palabra segun su largo.
 *
 * Escalonado a proposito: en una palabra corta, una letra distinta cambia el nombre -"ANA" y "ANO"-
 * mientras que en una larga es claramente un dedazo. Menos de cuatro letras exige exactitud.
 */
function tolerancia(palabra: string): number {
  if (palabra.length <= 3) return 0;
  if (palabra.length <= 7) return 1;
  return 2;
}

/** Si un perfil empata con TODAS las palabras, admitiendo dedazos.
 *
 * ─── Por que hace falta ──────────────────────────────────────────────────────
 *
 * Reportado al probar: "hector figeroa" no encontraba a nadie, y HECTOR FIGUEROA existe. El empate
 * exacto exige que cada palabra aparezca tal cual, asi que una letra de mas o de menos deja a la
 * persona fuera y Soli contesta que no existe. Omitir el segundo nombre si funcionaba -"Claudia
 * Bravo" encuentra a Claudia Andrea Bravo- porque eso no cambia las palabras que si se escribieron.
 *
 * Se compara palabra por palabra y no el campo completo: "figeroa" contra "FIGUEROA" son una letra;
 * contra "FIGUEROA MARTINEZ" entero serian nueve.
 */
export function empataNombreAproximado(fila: Record<string, unknown>, tokens: string[]): boolean {
  const palabras = [fila.nombre, fila.paterno, fila.materno]
    .flatMap((v) => (typeof v === "string" ? sinAcentos(v).toUpperCase().split(/\s+/) : []))
    .filter((w) => w.length > 0);

  return tokens.every((t) => {
    const T = sinAcentos(t).toUpperCase();
    const margen = tolerancia(T);
    return palabras.some((w) =>
      w.includes(T) || (margen > 0 && distancia(T, w) <= margen));
  });
}

/** El filtro con el que se piden candidatos en la pasada tolerante.
 *
 * Prefijo de tres letras de CADA palabra, unidas con OR: basta que una acierte para que la persona
 * entre en el conjunto. Los dedazos casi nunca caen en las tres primeras letras, y si caen -"ector"
 * por "hector"- esto no la encuentra. Es una limitacion conocida, no un descuido.
 */
export function filtroPrefijos(tokens: string[]): string {
  const partes: string[] = [];
  for (const t of tokens) {
    const pre = sinAcentos(t).slice(0, 3);
    if (pre.length < 3) continue;
    partes.push(`nombre.ilike.${pre}%`, `paterno.ilike.${pre}%`, `materno.ilike.${pre}%`);
  }
  return partes.join(",");
}

/** Si el perfil corresponde a alguien que sigue en la empresa.
 *
 * Mismo criterio que la pagina de Social: cualquier status distinto de BAJA. Importa mucho mas de lo
 * que parece, porque casi toda la base son bajas: medido, «lopez» empata con 106 perfiles y solo 10
 * son vigentes, y «maria» con 180 de los cuales 6. Sin preferir vigentes, buscar por un apellido comun
 * devuelve una lista inservible de gente que ya no esta.
 */
export function esVigente(fila: Record<string, unknown>): boolean {
  return fila.status_rh !== "BAJA";
}

/** Reordena poniendo primero a los vigentes, sin quitar a nadie.
 *
 * Se ORDENA en lugar de FILTRAR a proposito: el prompt dice explicitamente que no se añada un filtro
 * de status por cuenta propia, porque a veces se pregunta justamente por alguien que ya salio. Asi lo
 * util queda arriba y no se esconde nada.
 */
export function vigentesPrimero(filas: Record<string, unknown>[]): Record<string, unknown>[] {
  return [...filas].sort((a, b) => Number(esVigente(b)) - Number(esVigente(a)));
}

/** Candidatos con ALGUNA de las palabras, para cuando con todas no sale nadie.
 *
 * Es la diferencia entre «no existe» y «¿te refieres a alguno de estos?». Medido: «garcia hernandez»
 * no empata con ningun vigente exigiendo las dos palabras, y con cualquiera de las dos hay 17.
 */
export function conAlgunaPalabra(
  filas: Record<string, unknown>[],
  tokens: string[],
): Record<string, unknown>[] {
  const sueltos = filas.filter((f) => tokens.some((t) => empataNombreAproximado(f, [t])));
  return vigentesPrimero(sueltos);
}

/** Resuelve un nombre a UNA persona, primero exacto y luego con tolerancia a dedazos.
 *
 * Devuelve la fila, o `null` con los candidatos cuando hay varias o ninguna, para que quien llame
 * pueda explicarlo en lugar de elegir al azar.
 */
export async function resolverPorNombre(
  db: Db,
  texto: string,
  campos: string,
): Promise<{
  fila: Record<string, unknown> | null;
  candidatos: Record<string, unknown>[];
  aproximado: boolean;
  relajado?: boolean;
}> {
  const tokens = tokensDeNombre(texto);
  if (tokens.length === 0) return { fila: null, candidatos: [], aproximado: false };

  // Pasada exacta: la de siempre, con el prefiltro por la palabra mas larga.
  const guia = tokenGuia(tokens);
  const { data: exactos } = await db.from("profiles").select(campos)
    .or(`nombre.ilike.%${guia}%,paterno.ilike.%${guia}%,materno.ilike.%${guia}%`)
    .limit(CANDIDATOS_NOMBRE);
  let empatan = ((exactos || []) as unknown as Record<string, unknown>[])
    .filter((f) => empataNombre(f, tokens));

  // Sólo si la exacta no encuentra nada se paga la tolerante, que es mas ancha.
  let aproximado = false;
  if (empatan.length === 0) {
    const filtro = filtroPrefijos(tokens);
    if (filtro.length > 0) {
      const { data: cands } = await db.from("profiles").select(campos)
        .or(filtro).limit(CANDIDATOS_APROXIMADO);
      empatan = ((cands || []) as unknown as Record<string, unknown>[])
        .filter((f) => empataNombreAproximado(f, tokens));
      aproximado = empatan.length > 0;
    }
  }

  // Con varios que empatan, se intenta desempatar por vigencia antes de rendirse.
  //
  // Es lo que resuelve el caso reportado: «montoya» empata con dos perfiles y solo UNO sigue en la
  // empresa. Preguntar «¿a cual de los dos?» cuando uno es una baja de hace años es hacer trabajar al
  // usuario de balde.
  let desempatadoPorVigencia = false;
  if (empatan.length > 1) {
    const vivos = empatan.filter(esVigente);
    if (vivos.length === 1) {
      empatan = vivos;
      desempatadoPorVigencia = true;
    }
  }

  // Si con TODAS las palabras no sale nadie, se relaja a ALGUNA para poder ofrecer candidatos en lugar
  // de contestar que no existe.
  let relajado = false;
  if (empatan.length === 0 && tokens.length > 1) {
    const filtro = filtroPrefijos(tokens);
    if (filtro.length > 0) {
      const { data: sueltos } = await db.from("profiles").select(campos)
        .or(filtro).limit(CANDIDATOS_APROXIMADO);
      const cerca = conAlgunaPalabra(
        (sueltos || []) as unknown as Record<string, unknown>[], tokens);
      if (cerca.length > 0) {
        return { fila: null, candidatos: cerca.slice(0, 8), aproximado: true, relajado: true };
      }
    }
  }

  return {
    fila: empatan.length === 1 ? empatan[0] : null,
    candidatos: vigentesPrimero(empatan),
    aproximado: aproximado || desempatadoPorVigencia,
    relajado,
  };
}

/** A quien se refiere cuando dice "mi jefe", "mi gerente" o "mi director".
 *
 * Devuelve el NOMBRE que trae el perfil de quien pregunta, o `null` si no es ese caso. En la base
 * estos campos guardan el nombre completo en texto -el de Angel es "MARCO ANTONIO MONTOYA LOPEZ"-,
 * asi que se resuelve con la misma busqueda por nombre que todo lo demas.
 *
 * `lider` no se contempla: solo 14 perfiles de 2488 lo tienen, asi que preguntar por el lider casi
 * siempre acabaria en un "no lo tengo registrado" y el modelo lo explica mejor.
 */
export function jefeAlQueSeRefiere(texto: string, prof: Record<string, unknown>): string | null {
  const t = sinAcentos(texto).toLowerCase();
  if (!/vacacion|dias disponibles|saldo/.test(t)) return null;

  const campo = /\bmi\s+jefe|\bde\s+mi\s+jefe/.test(t) ? "jefe_inmediato"
    : /\bmi\s+gerente/.test(t) ? "gerente_regional"
    : /\bmi\s+director/.test(t) ? "director"
    : null;
  if (!campo) return null;

  const v = prof[campo];
  return typeof v === "string" && v.trim().length > 0 ? v.trim() : null;
}

export function numeroEmpleadoVariants(raw: string): string[] {
  const trimmed = raw.trim();
  const numInt  = parseInt(trimmed, 10);
  if (isNaN(numInt)) return [trimmed];
  const variants = new Set<string>();
  variants.add(trimmed);
  variants.add(String(numInt));
  variants.add(String(numInt).padStart(4, '0'));
  variants.add(String(numInt).padStart(5, '0'));
  return Array.from(variants);
}

/** Parsea una fecha "YYYY-MM-DD" en hora local (evita desfase UTC). */
export function parseLocalDate(s: string | null | undefined): Date | null {
  if (!s) return null;
  const parts = s.split("-");
  if (parts.length < 3) return null;
  return new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
}

/** Años completos entre base y hoy (misma lógica que Flutter _calcYears). */
export function calcYears(base: Date): number {
  const now = new Date();
  let years = now.getFullYear() - base.getFullYear();
  const nowMD  = now.getMonth()  * 100 + now.getDate();
  const baseMD = base.getMonth() * 100 + base.getDate();
  if (nowMD < baseMD) years--;
  return Math.max(0, Math.min(years, 50));
}

/** Días de vacaciones según años de servicio (LFT 2023). */
export function getDaysByYear(y: number): number {
  if (y === 1) return 12;
  if (y === 2) return 14;
  if (y === 3) return 16;
  if (y === 4) return 18;
  if (y === 5) return 20;
  if (y <= 10) return 22;
  if (y <= 15) return 24;
  if (y <= 20) return 26;
  if (y <= 25) return 28;
  if (y <= 30) return 30;
  return 32;
}
