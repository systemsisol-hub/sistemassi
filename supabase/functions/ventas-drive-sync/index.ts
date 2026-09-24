// ventas-drive-sync: lo que Sisol, el agente de ventas publico, sabe del Drive comercial.
//
// El mismo mecanismo que `drive-sync` (el de SOL): recorre carpetas publicas por su vista publica,
// sin llave de Google, y lee el texto de los PDF por partes, encadenandose en segundo plano. Reusa
// `listado.ts` y `leer.ts` de alla; lo que cambia es QUE se recorre:
//
//   * Una sola carpeta raiz, el Drive comercial entero: region → desarrollo → carpetas numeradas.
//   * Cada carpeta de desarrollo se liga al catalogo de Ventas por su nombre (con los alias).
//   * Dentro de cada desarrollo SOLO se entra a Brochure, Lista de precios y Ubicacion. Decision del
//     usuario del 24/09/2026: Sisol le habla a clientes, y el Drive trae cuentas bancarias, formatos
//     de bancos, KYC y cartas oferta. Esas carpetas no se abren, ni para listar.
//
// Dos acciones: `sincronizar` (la pide alguien con edit_ventas desde la app) y `leer` (un paso de
// un PDF; se llama a si misma).

import { createClient } from "jsr:@supabase/supabase-js@2";

import { enlaceDe, esPdf, leerListado, URL_VISTA, type Entrada, type Listado } from "../drive-sync/listado.ts";
import { descargar, leerPaginas, MAX_INTENTOS, MAX_TEXTO } from "../drive-sync/leer.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/// El Drive comercial completo. El mismo que leia `scripts/sync_drive.py` del Worker.
const CARPETA_RAIZ = "1N0HrBsbFbb8FQJkwejJGAZOCSf5sM-xb";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_CARPETAS = 400;
const MAX_ENTRADAS = 3000;
const MAX_CADENA = 800;

type Categoria = "BROCHURE" | "PRECIOS" | "UBICACION";

/// La carpeta numerada que SI se lee. «1. Brochure», «2. Listas de precios», «8. Ubicación / Location».
export function categoriaDe(nombre: string): Categoria | null {
  const n = sinAcentos(nombre).toLowerCase();
  if (/brochure/.test(n)) return "BROCHURE";
  if (/precio|price list/.test(n)) return "PRECIOS";
  if (/ubicacion|location/.test(n)) return "UBICACION";
  return null;
}

/// Dentro de una carpeta que si se lee, lo que se salta: versiones en ingles, para brokers y las
/// «NO TEL». Son copias del mismo contenido; el script anterior tambien las omitia.
export function seOmite(nombre: string): boolean {
  const n = sinAcentos(nombre).toLowerCase();
  return /\b(eng|ing|english|ingles)\b|broker|no tel|\(en\)/.test(n);
}

export function sinAcentos(s: string): string {
  return s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

/// «🌃 AG117» → «AG117». Las carpetas llevan un emoji adelante.
export function sinEmoji(s: string): string {
  return s.replace(/^[^\p{L}\p{N}]+/u, "").trim();
}

export function regexDeNombres(nombres: string[]): RegExp {
  const vocal: Record<string, string> = { a: "[aá]", e: "[eé]", i: "[ií]", o: "[oó]", u: "[uúü]" };
  const partes = [...new Set(nombres.map((n) => sinAcentos(n.trim().toLowerCase())).filter(Boolean))].map((n) =>
    n.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/[\s-]+/g, "\\s*-?\\s*").replace(/[aeiou]/g, (v) => vocal[v])
  );
  return new RegExp(partes.join("|") || "(?!)", "i");
}

type Svc = ReturnType<typeof createClient>;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const responde = (cuerpo: Record<string, unknown>, status = 200) =>
    new Response(JSON.stringify(cuerpo), { status, headers: { ...CORS, "Content-Type": "application/json" } });
  if (req.method !== "POST") return responde({ error: "Solo POST." }, 405);

  const svc = createClient(SUPABASE_URL, SERVICE_KEY);
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const interno = SERVICE_KEY !== "" && token === SERVICE_KEY;

  let usuarioId: string | null = null;
  if (!interno) {
    const { data: { user } } = await svc.auth.getUser(token);
    if (!user) return responde({ error: "Tu sesión ya no es válida. Cierra sesión y vuelve a entrar." }, 401);
    let puede = user.app_metadata?.role === "admin";
    if (!puede) {
      const { data: p } = await (svc.from("profiles") as any).select("role,permissions").eq("id", user.id).single();
      puede = p?.role === "admin" || p?.permissions?.edit_ventas === true;
    }
    if (!puede) return responde({ error: "Solo quien puede editar Ventas actualiza el Drive de Sisol." }, 403);
    usuarioId = user.id;
  }

  let cuerpo: { accion?: string; cadena?: number } = {};
  try { cuerpo = await req.json(); } catch { /* sin cuerpo */ }

  if (cuerpo.accion === "sincronizar") {
    const resultado = await sincronizar(svc, usuarioId);
    const pendientes = await contarPendientes(svc);
    if (pendientes > 0) encadenar(0);
    return responde({ ...resultado, pendientes });
  }

  if (cuerpo.accion === "leer") {
    const cadena = Number(cuerpo.cadena ?? 0) || 0;
    const paso = await leerUnPaso(svc);
    if (paso.pendientes > 0 && cadena < MAX_CADENA) encadenar(cadena + 1);
    return responde(paso);
  }

  return responde({ error: "Accion desconocida. Usa «sincronizar» o «leer»." }, 400);
});

// ─── La cadena de lectura (igual que en drive-sync) ─────────────────────────

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

function encadenar(cadena: number) {
  const pedir = () => fetch(`${SUPABASE_URL}/functions/v1/ventas-drive-sync`, {
    method: "POST",
    headers: { Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ accion: "leer", cadena }),
  });
  EdgeRuntime.waitUntil((async () => {
    for (let vez = 0; vez < 2; vez++) {
      try {
        const r = await pedir();
        await r.body?.cancel();
        if (r.ok) return;
        console.log(`ventas-drive-sync: el paso ${cadena} respondio ${r.status}; se pide otra vez`);
      } catch (e) {
        console.log(`ventas-drive-sync: el paso ${cadena} fallo: ${e}`);
      }
    }
  })());
}

async function contarPendientes(svc: Svc): Promise<number> {
  const { count } = await (svc.from("ventas_drive_archivos") as any)
    .select("id", { count: "exact", head: true })
    .in("estado", ["PENDIENTE", "LEYENDO"]);
  return count ?? 0;
}

async function leerUnPaso(svc: Svc): Promise<Record<string, unknown> & { pendientes: number }> {
  const tabla = () => svc.from("ventas_drive_archivos") as any;
  const { data } = await tabla()
    .select("id,nombre,estado,pagina_siguiente,intentos,texto")
    .in("estado", ["PENDIENTE", "LEYENDO"])
    .order("estado", { ascending: true })
    .order("tamano", { ascending: true, nullsFirst: false })
    .limit(1);
  const fila = (data ?? [])[0] as Record<string, any> | undefined;
  if (!fila) return { pendientes: 0 };

  const desde = Number(fila.pagina_siguiente ?? 1) || 1;

  if (Number(fila.intentos) >= MAX_INTENTOS) {
    await tabla().update({
      estado: "ERROR",
      error: `La pagina ${desde} no se pudo leer en ${MAX_INTENTOS} intentos: se pasa del tiempo de lectura.`,
      pagina_siguiente: null,
      intentos: 0,
    }).eq("id", fila.id);
    return { id: fila.id, nombre: fila.nombre, estado: "ERROR", pendientes: await contarPendientes(svc) };
  }

  const { data: tomada } = await tabla()
    .update({ estado: "LEYENDO", intentos: Number(fila.intentos) + 1 })
    .eq("id", fila.id).eq("intentos", fila.intentos)
    .select("id");
  if (!tomada || tomada.length === 0) return { ocupado: true, pendientes: await contarPendientes(svc) };

  const falla = async (error: string) => {
    await tabla().update({ estado: "ERROR", error, pagina_siguiente: null, intentos: 0 }).eq("id", fila.id);
    return { id: fila.id, nombre: fila.nombre, estado: "ERROR", error, pendientes: await contarPendientes(svc) };
  };

  const d = await descargar(fila.id);
  if (d.ok === false) return await falla(d.error);

  let avance;
  try {
    avance = await leerPaginas(d.datos, desde);
  } catch (e) {
    return await falla(`No se pudo leer como PDF: ${String(e).slice(0, 300)}`);
  }

  const previo = desde > 1 ? String(fila.texto ?? "") : "";
  let texto = previo + avance.texto;
  const recortado = texto.length > MAX_TEXTO;
  if (recortado) texto = texto.slice(0, MAX_TEXTO);

  if (avance.siguiente !== null && !recortado) {
    await tabla().update({ texto, paginas: avance.paginas, pagina_siguiente: avance.siguiente, intentos: 0 }).eq("id", fila.id);
    return {
      id: fila.id, nombre: fila.nombre, estado: "LEYENDO",
      pagina: avance.siguiente, paginas: avance.paginas, pendientes: await contarPendientes(svc),
    };
  }

  const sinTexto = texto.replace(/\[p\. \d+\]/g, "").trim().length < 20;
  await tabla().update({
    estado: sinTexto ? "SIN_TEXTO" : "LEIDO",
    texto: sinTexto ? null : texto,
    paginas: avance.paginas,
    pagina_siguiente: null,
    intentos: 0,
    leido_en: new Date().toISOString(),
    error: recortado ? `Tiene mas texto del que cabe: se guardaron los primeros ${MAX_TEXTO.toLocaleString("en-US")} caracteres.` : null,
  }).eq("id", fila.id);
  return {
    id: fila.id, nombre: fila.nombre, estado: sinTexto ? "SIN_TEXTO" : "LEIDO",
    paginas: avance.paginas, pendientes: await contarPendientes(svc),
  };
}

// ─── El recorrido ────────────────────────────────────────────────────────────

async function listarCarpeta(id: string): Promise<Listado> {
  let r: Response;
  try {
    r = await fetch(URL_VISTA + encodeURIComponent(id), { signal: AbortSignal.timeout(20_000) });
  } catch (e) {
    return { ok: false, error: `No se pudo abrir la carpeta: ${e}` };
  }
  if (r.status === 404) {
    await r.body?.cancel();
    return { ok: false, error: "Google respondio 404: la carpeta no existe o dejo de ser publica." };
  }
  if (!r.ok) {
    await r.body?.cancel();
    return { ok: false, error: `Google respondio ${r.status} al abrir la carpeta.` };
  }
  return leerListado(await r.text());
}

async function tamanoDe(id: string): Promise<number | null> {
  try {
    const r = await fetch(`https://drive.google.com/uc?export=download&id=${encodeURIComponent(id)}`, {
      headers: { Range: "bytes=0-0" }, redirect: "follow", signal: AbortSignal.timeout(20_000),
    });
    await r.body?.cancel();
    const n = Number((r.headers.get("Content-Range") ?? "").split("/")[1]);
    return Number.isFinite(n) && n > 0 ? n : null;
  } catch {
    return null;
  }
}

async function enParalelo<T, R>(items: T[], cuantos: number, f: (x: T) => Promise<R>): Promise<R[]> {
  const salida: R[] = new Array(items.length);
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(cuantos, items.length) }, async () => {
    while (i < items.length) {
      const mio = i++;
      salida[mio] = await f(items[mio]);
    }
  }));
  return salida;
}

/// Una carpeta en la cola del recorrido. Antes de ubicar su desarrollo solo se buscan carpetas; ya
/// dentro de una categoria se toma todo lo que no se omita.
type Pendiente =
  | { tipo: "buscar"; id: string; nombre: string; profundidad: number }
  | { tipo: "desarrollo"; id: string; carpeta: string; desarrolloId: string | null }
  | { tipo: "categoria"; id: string; carpeta: string; desarrolloId: string | null; categoria: Categoria; ruta: string };

type Hallado = Entrada & { carpeta: string; desarrolloId: string | null; categoria: Categoria; ruta: string };

async function sincronizar(svc: Svc, usuarioId: string | null) {
  const { data: reg } = await (svc.from("ventas_drive_sincronizaciones") as any)
    .insert({ pedida_por: usuarioId }).select("id").single();
  const cierra = (campos: Record<string, unknown>) => (svc.from("ventas_drive_sincronizaciones") as any)
    .update({ ...campos, terminada_en: new Date().toISOString() }).eq("id", reg?.id);

  try {
    const { data: des } = await (svc.from("ventas_desarrollos") as any).select("id,nombre,alias");
    const catalogo = ((des ?? []) as Record<string, any>[]).map((d) => ({
      id: String(d.id), nombre: String(d.nombre), re: regexDeNombres([d.nombre, ...(d.alias ?? [])]),
    }));

    // ── 1. Recorrer. Si UNA carpeta falla se para todo y no se quita nada: con el recorrido a medias,
    //    lo que no se vio no es «lo que ya no esta».
    const hallados: Hallado[] = [];
    const sinCatalogo: string[] = [];
    let cola: Pendiente[] = [{ tipo: "buscar", id: CARPETA_RAIZ, nombre: "", profundidad: 0 }];
    let carpetas = 0;
    while (cola.length > 0) {
      const lote = cola.splice(0, 4);
      const listados = await Promise.all(lote.map((c) => listarCarpeta(c.id)));
      listados.forEach((l, k) => {
        const c = lote[k];
        if (l.ok === false) throw new Error(`${"carpeta" in c ? c.carpeta : c.nombre || "la carpeta raiz"}: ${l.error}`);
        for (const e of l.entradas) {
          if (c.tipo === "buscar") {
            if (!e.esCarpeta) continue;
            carpetas++;
            const limpio = sinEmoji(e.nombre);
            // El material general de SI SOL: solo su brochure.
            if (c.profundidad === 0 && /^si\s*sol$/i.test(limpio)) {
              cola.push({ tipo: "desarrollo", id: e.id, carpeta: "SI SOL", desarrolloId: null });
              continue;
            }
            const d = catalogo.find((x) => x.re.test(sinAcentos(limpio)));
            if (d) {
              cola.push({ tipo: "desarrollo", id: e.id, carpeta: limpio, desarrolloId: d.id });
            } else if (c.profundidad === 0) {
              // En la raiz, lo que no es un desarrollo es una region: «🌆 CDMX».
              cola.push({ tipo: "buscar", id: e.id, nombre: limpio, profundidad: 1 });
            } else {
              // Dentro de una region, cada carpeta es un desarrollo. Si no esta en el catalogo se lee
              // igual, sin ligar, y se reporta para darlo de alta.
              sinCatalogo.push(limpio);
              cola.push({ tipo: "desarrollo", id: e.id, carpeta: limpio, desarrolloId: null });
            }
          } else if (c.tipo === "desarrollo") {
            if (!e.esCarpeta) continue;
            const cat = categoriaDe(sinEmoji(e.nombre));
            if (!cat) continue;
            carpetas++;
            cola.push({ tipo: "categoria", id: e.id, carpeta: c.carpeta, desarrolloId: c.desarrolloId, categoria: cat, ruta: e.nombre });
          } else {
            if (seOmite(e.nombre)) continue;
            if (e.esCarpeta) {
              carpetas++;
              cola.push({ ...c, id: e.id, ruta: `${c.ruta}/${e.nombre}` });
            } else {
              hallados.push({ ...e, carpeta: c.carpeta, desarrolloId: c.desarrolloId, categoria: c.categoria, ruta: c.ruta });
            }
          }
        }
      });
      if (carpetas > MAX_CARPETAS || hallados.length > MAX_ENTRADAS) {
        throw new Error(`El Drive tiene mas de ${MAX_CARPETAS} carpetas o ${MAX_ENTRADAS} archivos por leer: ¿es la carpeta correcta?`);
      }
    }

    // Una carpeta de region que no llevo a ningun desarrollo se queda en `buscar` y no deja rastro;
    // las que si importan son las de desarrollo sin catalogo, que ya se anotaron.
    const vistos = new Map<string, Hallado>();
    for (const e of hallados) if (!vistos.has(e.id)) vistos.set(e.id, e);

    // ── 2. Lo que ya habia.
    const { data: antes } = await (svc.from("ventas_drive_archivos") as any)
      .select("id,modificado,tamano,estado").range(0, MAX_ENTRADAS);
    const previos = new Map<string, Record<string, any>>();
    for (const p of (antes ?? []) as Record<string, any>[]) previos.set(p.id, p);

    // ── 3. El tamaño, solo de lo nuevo o de lo que cambio de fecha.
    const aMedir = [...vistos.values()].filter((e) => {
      const p = previos.get(e.id);
      return !p || p.modificado !== e.modificado || p.tamano == null;
    });
    const medidas = await enParalelo(aMedir, 8, (e) => tamanoDe(e.id));
    const tamanos = new Map<string, number | null>();
    aMedir.forEach((e, k) => tamanos.set(e.id, medidas[k]));

    // ── 4. Guardar.
    const ahora = new Date().toISOString();
    const aReiniciar: Record<string, unknown>[] = [];
    const aTocar: Record<string, unknown>[] = [];
    let nuevos = 0, cambiados = 0;
    for (const e of vistos.values()) {
      const p = previos.get(e.id);
      const tamano = tamanos.has(e.id) ? tamanos.get(e.id) : (p?.tamano ?? null);
      const base = {
        id: e.id, desarrollo_id: e.desarrolloId, carpeta: e.carpeta, categoria: e.categoria, ruta: e.ruta,
        nombre: e.nombre, enlace: enlaceDe(e), modificado: e.modificado, tamano, visto_en: ahora,
      };
      const cambio = !!p && (p.modificado !== e.modificado
        || (tamanos.has(e.id) && tamano !== null && Number(p.tamano) !== tamano));
      const reintento = !!p && p.estado === "ERROR";
      if (!p) nuevos++;
      if (cambio) cambiados++;
      if (!p || cambio || reintento) {
        aReiniciar.push({
          ...base,
          estado: esPdf(e) ? "PENDIENTE" : "NO_SE_LEE",
          error: null, paginas: null, pagina_siguiente: null, intentos: 0, texto: null, leido_en: null,
        });
      } else {
        // `estado` va aunque no cambie: el upsert de PostgREST exige las mismas columnas en todo el lote.
        aTocar.push({ ...base, estado: p.estado });
      }
    }
    for (const lote of [aReiniciar, aTocar]) {
      for (let k = 0; k < lote.length; k += 200) {
        const { error } = await (svc.from("ventas_drive_archivos") as any).upsert(lote.slice(k, k + 200));
        if (error) throw new Error(`Al guardar: ${error.message}`);
      }
    }

    // ── 5. Lo que ya no esta. Solo se llega aqui con el recorrido COMPLETO.
    const quitar = [...previos.keys()].filter((id) => !vistos.has(id));
    for (let k = 0; k < quitar.length; k += 200) {
      await (svc.from("ventas_drive_archivos") as any).delete().in("id", quitar.slice(k, k + 200));
    }

    const resumen = { carpetas, archivos: vistos.size, nuevos, cambiados, quitados: quitar.length, sin_catalogo: sinCatalogo };
    await cierra(resumen);
    return resumen;
  } catch (e) {
    const error = e instanceof Error ? e.message : String(e);
    await cierra({ error });
    return { error };
  }
}
