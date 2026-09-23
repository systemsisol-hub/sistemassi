// Leer la VISTA PUBLICA de una carpeta del Drive. Sin efectos al importarlo, para que el arnes lo
// pueda ejercitar.
//
// ─── Por que asi y no con la API ─────────────────────────────────────────────
//
// La API oficial pide una llave aunque la carpeta sea publica: responde 403 a quien no se
// identifica. El usuario decidio no crear una (23/09/2026), sabiendo que esta vista es una PAGINA y
// no una API, y que Google la puede cambiar sin avisar.
//
// Por eso este archivo es el unico que sabe como es esa pagina, y por eso `leerListado` distingue
// «la carpeta esta vacia» de «la pagina ya no tiene la forma que esperamos». Lo segundo es un error
// que se registra y se ve en Configuracion; confundirlo con lo primero borraria todo el indice en
// silencio.

export interface Entrada {
  id: string;
  nombre: string;
  esCarpeta: boolean;
  /// El tipo que declara Google en el icono: «application/pdf», «image/png». Null en carpetas.
  tipo: string | null;
  /// La fecha tal como la muestra Google: «Sep 17», «7/25/25», «3:45 PM».
  modificado: string | null;
}

export const URL_VISTA = "https://drive.google.com/embeddedfolderview?id=";

export function enlaceDe(e: { id: string; esCarpeta: boolean }): string {
  return e.esCarpeta
    ? `https://drive.google.com/drive/folders/${e.id}`
    : `https://drive.google.com/file/d/${e.id}/view`;
}

export function esPdf(e: { nombre: string; tipo: string | null; esCarpeta: boolean }): boolean {
  if (e.esCarpeta) return false;
  if (e.tipo) return e.tipo === "application/pdf";
  return /\.pdf$/i.test(e.nombre.trim());
}

const ENTIDADES: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ",
};

export function sinEntidades(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (todo, cod: string) => {
    if (cod[0] === "#") {
      const n = cod[1] === "x" || cod[1] === "X" ? parseInt(cod.slice(2), 16) : parseInt(cod.slice(1), 10);
      return Number.isFinite(n) ? String.fromCodePoint(n) : todo;
    }
    return ENTIDADES[cod.toLowerCase()] ?? todo;
  });
}

export type Listado =
  | { ok: true; entradas: Entrada[] }
  | { ok: false; error: string };

/// Las entradas de la pagina. Cada una es un `<div class="flip-entry" id="entry-<id>">`.
export function leerListado(html: string): Listado {
  // Lo que tiene TODA vista de carpeta, este vacia o no. Si falta, la pagina es otra cosa: la de
  // «necesitas acceso», la de iniciar sesion, o una vista que Google cambio.
  if (!/class="flip-entries"/.test(html)) {
    if (/accounts\.google\.com|ServiceLogin|Necesitas acceso|You need access|request access/i.test(html)) {
      return { ok: false, error: "La carpeta ya no es publica: Google pide iniciar sesion." };
    }
    return {
      ok: false,
      error: "La vista publica del Drive ya no tiene la forma esperada. Google pudo haberla cambiado.",
    };
  }

  const entradas: Entrada[] = [];
  const bloques = html.split('<div class="flip-entry" id="entry-').slice(1);
  for (const b of bloques) {
    const id = b.match(/^([A-Za-z0-9_-]+)"/)?.[1];
    const titulo = b.match(/<div class="flip-entry-title">([\s\S]*?)<\/div>/)?.[1];
    const href = b.match(/<a href="([^"]+)"/)?.[1] ?? "";
    if (!id || titulo === undefined) {
      return { ok: false, error: "Una entrada de la carpeta no tiene la forma esperada." };
    }
    const esCarpeta = href.includes("/drive/folders/") || /aria-label="Folder"/.test(b);
    const tipo = esCarpeta ? null : (b.match(/\/type\/([a-z0-9.+-]+\/[a-z0-9.+-]+)"/i)?.[1] ?? null);
    const fecha = b.match(/<div class="flip-entry-last-modified"><div>([\s\S]*?)<\/div>/)?.[1];
    entradas.push({
      id,
      nombre: sinEntidades(titulo).trim(),
      esCarpeta,
      tipo,
      modificado: fecha === undefined ? null : sinEntidades(fecha).trim() || null,
    });
  }
  return { ok: true, entradas };
}
