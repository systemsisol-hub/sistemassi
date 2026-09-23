// Sacar el texto de un PDF del Drive, POR PARTES.
//
// ─── Por que por partes ──────────────────────────────────────────────────────
//
// Una Edge Function tiene 2 segundos de CPU por llamada. Medido el 23/09/2026 en esta maquina: abrir
// un PDF cuesta casi nada y cada pagina hasta 220 ms —los planos, por las cotas—. El PDF de
// tipologias (18 paginas, 23 MB) salio en ~1 s de CPU, y el servidor puede ser mas lento. Leerlo de
// un tiron quedaria al borde; pasarse mata la funcion sin dejarle escribir nada.
//
// Asi que cada llamada lee paginas hasta agotar un PRESUPUESTO de tiempo, guarda lo que lleva y por
// donde va, y la siguiente sigue ahi. Descargar el archivo otra vez no cuesta CPU: es espera de red.

import { getDocumentProxy } from "npm:unpdf@1.8.1";

/// Tiempo de reloj que se permite leer paginas en una llamada. Mientras se leen no hay red, asi que
/// el reloj es CPU; se deja margen para abrir el documento y para todo lo demas.
export const PRESUPUESTO_MS = 900;

/// Lo que cabe en `drive_archivos.texto`. Un PDF con mas se guarda recortado y se dice.
export const MAX_TEXTO = 400_000;

/// Lo que se descarga como mucho. La funcion tiene 256 MB de memoria y el PDF mas pesado de AG117
/// son 29 MB; con el doble de margen de sobra.
export const MAX_BYTES = 60 * 1024 * 1024;

/// Si la misma pagina ya se intento tantas veces, se da por imposible.
export const MAX_INTENTOS = 3;

/// El texto de una pagina, legible: cada renglon del PDF en su renglon, sin espacios repetidos.
export function textoDePagina(items: Array<{ str?: string; hasEOL?: boolean }>): string {
  let t = "";
  for (const it of items) {
    t += it.str ?? "";
    t += it.hasEOL ? "\n" : " ";
  }
  return t.replace(/[ \t]+/g, " ").replace(/ *\n */g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}

export type Descarga =
  | { ok: true; datos: Uint8Array }
  | { ok: false; error: string };

export async function descargar(id: string): Promise<Descarga> {
  let r: Response;
  try {
    r = await fetch(`https://drive.google.com/uc?export=download&id=${encodeURIComponent(id)}`,
      { redirect: "follow" });
  } catch (e) {
    return { ok: false, error: `No se pudo descargar: ${e}` };
  }
  if (!r.ok) return { ok: false, error: `Google respondio ${r.status} al descargarlo.` };

  // Una pagina en lugar del archivo: la de «no se puede analizar en busca de virus» de los
  // archivos grandes, o la de pedir acceso si dejo de ser publico.
  const tipo = r.headers.get("Content-Type") ?? "";
  if (tipo.startsWith("text/html")) {
    await r.body?.cancel();
    return { ok: false, error: "Google entrego una pagina en lugar del archivo: pide confirmacion o ya no es publico." };
  }
  const largo = Number(r.headers.get("Content-Length") ?? "0");
  if (largo > MAX_BYTES) {
    await r.body?.cancel();
    return { ok: false, error: `Pesa ${Math.round(largo / 1048576)} MB; el tope para leerlo es ${MAX_BYTES / 1048576} MB.` };
  }
  const datos = new Uint8Array(await r.arrayBuffer());
  if (datos.length > MAX_BYTES) {
    return { ok: false, error: `Pesa ${Math.round(datos.length / 1048576)} MB; el tope para leerlo es ${MAX_BYTES / 1048576} MB.` };
  }
  return { ok: true, datos };
}

export interface Avance {
  paginas: number;
  /// La siguiente por leer; null si ya se leyeron todas.
  siguiente: number | null;
  /// Lo leido en ESTA llamada, con su marca de pagina.
  texto: string;
}

/// Lee desde `desde` hasta agotar el presupuesto. Siempre lee al menos una pagina, para avanzar.
export async function leerPaginas(datos: Uint8Array, desde: number): Promise<Avance> {
  const pdf = await getDocumentProxy(datos);
  try {
    const total: number = pdf.numPages;
    const inicio = performance.now();
    let n = Math.max(1, desde);
    let texto = "";
    while (n <= total) {
      const pagina = await pdf.getPage(n);
      const contenido = await pagina.getTextContent();
      const t = textoDePagina(contenido.items ?? []);
      if (t.length > 0) texto += `\n[p. ${n}]\n${t}\n`;
      pagina.cleanup?.();
      n++;
      if (performance.now() - inicio > PRESUPUESTO_MS) break;
    }
    return { paginas: total, siguiente: n <= total ? n : null, texto };
  } finally {
    await pdf.destroy?.();
  }
}
