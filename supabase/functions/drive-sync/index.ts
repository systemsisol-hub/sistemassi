// drive-sync: lo que SOL sabe de la carpeta del Drive de cada desarrollo.
//
// Dos acciones:
//
//   * `sincronizar` — recorre la carpeta por su vista publica, pone al dia `drive_archivos` (lo
//     nuevo entra, lo cambiado se vuelve a leer, lo que ya no esta se quita) y arranca la lectura.
//     La pide un administrador desde la Configuracion de SOL.
//   * `leer` — lee UN paso de UN PDF pendiente (ver leer.ts) y, si quedan, se vuelve a llamar a si
//     misma en segundo plano. Asi se leen los 96 PDF de AG117 sin que nadie tenga la pantalla
//     abierta, y sin pasarse nunca de los 2 segundos de CPU de una llamada.
//
// ─── Quien puede ─────────────────────────────────────────────────────────────
//
// Un administrador, leido del TOKEN (`app_metadata.role`, lo mismo que `is_admin()`), no de
// `profiles`, que hoy cada quien puede escribirse. O la propia funcion, con la llave de servicio,
// para encadenar la lectura.

import { createClient } from "jsr:@supabase/supabase-js@2";

import { enlaceDe, esPdf, leerListado, URL_VISTA, type Entrada, type Listado } from "./listado.ts";
import { descargar, leerPaginas, MAX_INTENTOS, MAX_TEXTO } from "./leer.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/// Topes del recorrido. AG117 tiene 45 carpetas y 122 archivos; esto solo evita que una carpeta
/// equivocada —la raiz de todo un Drive— deje la funcion recorriendo hasta que la maten.
const MAX_CARPETAS = 400;
const MAX_ENTRADAS = 5000;

/// Cuantas llamadas seguidas puede encadenar la lectura. 96 PDF, los largos en dos o tres pasos:
/// sobra. Evita una cadena infinita si algo se tuerce.
const MAX_CADENA = 800;

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
    if (!user) return responde({ error: "Sesion invalida." }, 401);
    if (user.app_metadata?.role !== "admin") {
      return responde({ error: "Solo un administrador puede actualizar el Drive de SOL." }, 403);
    }
    usuarioId = user.id;
  }

  let cuerpo: { accion?: string; cadena?: number } = {};
  try { cuerpo = await req.json(); } catch { /* sin cuerpo */ }

  if (cuerpo.accion === "sincronizar") {
    const resultados = await sincronizarTodo(svc, usuarioId);
    const pendientes = await contarPendientes(svc);
    if (pendientes > 0) encadenar(0);
    return responde({ resultados, pendientes });
  }

  if (cuerpo.accion === "leer") {
    const cadena = Number(cuerpo.cadena ?? 0) || 0;
    const paso = await leerUnPaso(svc);
    if (paso.pendientes > 0 && cadena < MAX_CADENA) encadenar(cadena + 1);
    return responde(paso);
  }

  return responde({ error: "Accion desconocida. Usa «sincronizar» o «leer»." }, 400);
});

// ─── La cadena de lectura ────────────────────────────────────────────────────

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

/// Pide el siguiente paso sin esperar a que termine la respuesta de esta llamada.
///
/// Si esa llamada muere —la mata el limite de CPU en una pagina imposible— no alcanza a pedir la
/// siguiente, y la cadena se cortaria. Por eso quien la pidio lo nota y la vuelve a pedir una vez:
/// el PDF que la tumbo ya lleva un intento mas, y al tercero queda en ERROR y la cadena sigue.
function encadenar(cadena: number) {
  const pedir = () => fetch(`${SUPABASE_URL}/functions/v1/drive-sync`, {
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
        console.log(`drive-sync: el paso ${cadena} respondio ${r.status}; se pide otra vez`);
      } catch (e) {
        console.log(`drive-sync: el paso ${cadena} fallo: ${e}`);
      }
    }
  })());
}

async function contarPendientes(svc: Svc): Promise<number> {
  const { count } = await (svc.from("drive_archivos") as any)
    .select("id", { count: "exact", head: true })
    .in("estado", ["PENDIENTE", "LEYENDO"]);
  return count ?? 0;
}

// ─── Un paso de lectura ──────────────────────────────────────────────────────

async function leerUnPaso(svc: Svc): Promise<Record<string, unknown> & { pendientes: number }> {
  // Primero el que va a medias, y de los nuevos el mas ligero: asi los folletos y las listas estan
  // listos pronto, y los planos pesados despues.
  const { data } = await (svc.from("drive_archivos") as any)
    .select("id,nombre,estado,pagina_siguiente,intentos,texto")
    .in("estado", ["PENDIENTE", "LEYENDO"])
    .order("estado", { ascending: true })
    .order("tamano", { ascending: true, nullsFirst: false })
    .limit(1);
  const fila = (data ?? [])[0] as Record<string, any> | undefined;
  if (!fila) return { pendientes: 0 };

  const desde = Number(fila.pagina_siguiente ?? 1) || 1;

  if (Number(fila.intentos) >= MAX_INTENTOS) {
    await (svc.from("drive_archivos") as any).update({
      estado: "ERROR",
      error: `La pagina ${desde} no se pudo leer en ${MAX_INTENTOS} intentos: se pasa del tiempo de lectura.`,
      pagina_siguiente: null,
      intentos: 0,
    }).eq("id", fila.id);
    return { id: fila.id, nombre: fila.nombre, estado: "ERROR", pendientes: await contarPendientes(svc) };
  }

  // Se aparta ANTES de leer, sumando el intento. Si otra cadena ya lo tomo —se pidio actualizar dos
  // veces— el `eq` de intentos no coincide y esta lo deja.
  const { data: tomada } = await (svc.from("drive_archivos") as any)
    .update({ estado: "LEYENDO", intentos: Number(fila.intentos) + 1 })
    .eq("id", fila.id).eq("intentos", fila.intentos)
    .select("id");
  if (!tomada || tomada.length === 0) return { ocupado: true, pendientes: await contarPendientes(svc) };

  const falla = async (error: string) => {
    await (svc.from("drive_archivos") as any)
      .update({ estado: "ERROR", error, pagina_siguiente: null, intentos: 0 }).eq("id", fila.id);
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

  // Lo de pasos anteriores solo cuenta si se esta continuando. Un PDF que vuelve a empezar —porque
  // cambio— arranca sin nada.
  const previo = desde > 1 ? String(fila.texto ?? "") : "";
  let texto = previo + avance.texto;
  const recortado = texto.length > MAX_TEXTO;
  if (recortado) texto = texto.slice(0, MAX_TEXTO);

  if (avance.siguiente !== null && !recortado) {
    await (svc.from("drive_archivos") as any).update({
      texto, paginas: avance.paginas, pagina_siguiente: avance.siguiente, intentos: 0,
    }).eq("id", fila.id);
    return {
      id: fila.id, nombre: fila.nombre, estado: "LEYENDO",
      pagina: avance.siguiente, paginas: avance.paginas, pendientes: await contarPendientes(svc),
    };
  }

  // Menos de un renglon en todo el documento: es un escaneo o un plano sin texto. No es un error,
  // pero SOL no tiene nada que leer ahi, y se dice asi.
  const sinTexto = texto.replace(/\[p\. \d+\]/g, "").trim().length < 20;
  await (svc.from("drive_archivos") as any).update({
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

/// El tamaño sin descargar el archivo: se pide UN byte y se lee el total de `Content-Range`.
async function tamanoDe(id: string): Promise<number | null> {
  try {
    const r = await fetch(`https://drive.google.com/uc?export=download&id=${encodeURIComponent(id)}`, {
      headers: { Range: "bytes=0-0" }, redirect: "follow", signal: AbortSignal.timeout(20_000),
    });
    await r.body?.cancel();
    const total = (r.headers.get("Content-Range") ?? "").split("/")[1];
    const n = Number(total);
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

async function sincronizarTodo(svc: Svc, usuarioId: string | null) {
  const { data: des } = await (svc.from("desarrollos") as any)
    .select("id,nombre,drive_carpeta_id").not("drive_carpeta_id", "is", null);
  const salida: Record<string, unknown>[] = [];
  for (const d of (des ?? []) as Record<string, any>[]) {
    salida.push(await sincronizarDesarrollo(svc, d, usuarioId));
  }
  return salida;
}

async function sincronizarDesarrollo(svc: Svc, d: Record<string, any>, usuarioId: string | null) {
  const { data: reg } = await (svc.from("drive_sincronizaciones") as any)
    .insert({ desarrollo_id: d.id, pedida_por: usuarioId }).select("id").single();
  const cierra = (campos: Record<string, unknown>) => (svc.from("drive_sincronizaciones") as any)
    .update({ ...campos, terminada_en: new Date().toISOString() }).eq("id", reg?.id);

  try {
    // ── 1. Recorrer, por niveles y de cuatro en cuatro carpetas.
    //
    // Si UNA carpeta falla se para todo y no se quita nada. Con el recorrido a medias, lo que no se
    // vio no es «lo que ya no esta», y quitarlo borraria el texto ya leido de medio Drive.
    const encontrados: Array<Entrada & { ruta: string }> = [];
    let cola: Array<{ id: string; ruta: string }> = [{ id: d.drive_carpeta_id, ruta: "" }];
    let carpetas = 0;
    while (cola.length > 0) {
      const lote = cola.splice(0, 4);
      const listados = await Promise.all(lote.map((c) => listarCarpeta(c.id)));
      listados.forEach((l, k) => {
        const donde = lote[k].ruta || "la carpeta principal";
        if (l.ok === false) throw new Error(`${donde}: ${l.error}`);
        for (const e of l.entradas) {
          encontrados.push({ ...e, ruta: lote[k].ruta });
          if (e.esCarpeta) {
            carpetas++;
            cola.push({ id: e.id, ruta: lote[k].ruta ? `${lote[k].ruta}/${e.nombre}` : e.nombre });
          }
        }
      });
      if (carpetas > MAX_CARPETAS || encontrados.length > MAX_ENTRADAS) {
        throw new Error(`La carpeta tiene mas de ${MAX_CARPETAS} carpetas o ${MAX_ENTRADAS} archivos: ¿es la correcta?`);
      }
    }

    // Un mismo archivo puede aparecer dos veces —un acceso directo—: cuenta la primera.
    const vistos = new Map<string, Entrada & { ruta: string }>();
    for (const e of encontrados) if (!vistos.has(e.id)) vistos.set(e.id, e);

    // ── 2. Lo que ya habia.
    const { data: antes } = await (svc.from("drive_archivos") as any)
      .select("id,nombre,modificado,tamano,estado").eq("desarrollo_id", d.id).range(0, MAX_ENTRADAS);
    const previos = new Map<string, Record<string, any>>();
    for (const p of (antes ?? []) as Record<string, any>[]) previos.set(p.id, p);

    // ── 3. El tamaño, solo de lo nuevo o de lo que cambio de fecha. Es lo que dice si un archivo que
    //    se sustituyo en su lugar trae otro contenido.
    const aMedir = [...vistos.values()].filter((e) => {
      if (e.esCarpeta) return false;
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
        id: e.id, desarrollo_id: d.id, ruta: e.ruta, nombre: e.nombre, es_carpeta: e.esCarpeta,
        enlace: enlaceDe(e), modificado: e.modificado, tamano, visto_en: ahora,
      };
      const cambio = !!p && !e.esCarpeta && (p.modificado !== e.modificado
        || (tamanos.has(e.id) && tamano !== null && Number(p.tamano) !== tamano));
      // Un ERROR se reintenta en cada actualizacion: casi siempre fue la red o Google.
      const reintento = !!p && p.estado === "ERROR";
      if (!p) nuevos++;
      if (cambio) cambiados++;
      if (!p || cambio || reintento) {
        aReiniciar.push({
          ...base,
          estado: e.esCarpeta ? null : (esPdf(e) ? "PENDIENTE" : "NO_SE_LEE"),
          error: null, paginas: null, pagina_siguiente: null, intentos: 0, texto: null, leido_en: null,
        });
      } else {
        aTocar.push(base);
      }
    }
    for (let k = 0; k < aReiniciar.length; k += 200) {
      const { error } = await (svc.from("drive_archivos") as any).upsert(aReiniciar.slice(k, k + 200));
      if (error) throw new Error(`Al guardar: ${error.message}`);
    }
    for (let k = 0; k < aTocar.length; k += 200) {
      const { error } = await (svc.from("drive_archivos") as any).upsert(aTocar.slice(k, k + 200));
      if (error) throw new Error(`Al guardar: ${error.message}`);
    }

    // ── 5. Lo que ya no esta. Solo se llega aqui con el recorrido COMPLETO.
    const quitar = [...previos.keys()].filter((id) => !vistos.has(id));
    for (let k = 0; k < quitar.length; k += 200) {
      await (svc.from("drive_archivos") as any).delete().in("id", quitar.slice(k, k + 200));
    }

    const archivos = [...vistos.values()].filter((e) => !e.esCarpeta).length;
    await cierra({ carpetas, archivos, nuevos, cambiados, quitados: quitar.length });
    return { desarrollo: d.nombre, carpetas, archivos, nuevos, cambiados, quitados: quitar.length };
  } catch (e) {
    const error = e instanceof Error ? e.message : String(e);
    await cierra({ error });
    return { desarrollo: d.nombre, error };
  }
}
