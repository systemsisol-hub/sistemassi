// copiar-fotos-appchecar: trae a nuestro almacenamiento las fotos de las checadas que vinieron de
// appchecar. Temporal: se usa una vez, después de la migración 20260929220000.
//
// Decisión del usuario el 29/09/2026: las fotos se COPIAN, porque el día que se cancele appchecar
// sus enlaces dejan de servir. Son ~3,150 de unos 6 KB cada una.
//
// Cada llamada copia un lote —descargar y subir es espera de red, no CPU— y, si quedan, se vuelve a
// llamar a sí misma en segundo plano, como `drive-sync`. Una foto que no se pudo copiar se queda con
// el motivo en `foto_error` y no se vuelve a intentar sola; llamar con `reintentar: true` las retoma.
//
// La pide un administrador (leído del TOKEN, como `is_admin()`) o ella misma con la llave de
// servicio.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const BUCKET = "checador-fotos";
const LOTE = 40;
const MAX_CADENA = 200;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const responde = (cuerpo: Record<string, unknown>, status = 200) =>
    new Response(JSON.stringify(cuerpo), { status, headers: { ...CORS, "Content-Type": "application/json" } });
  if (req.method !== "POST") return responde({ error: "Solo POST." }, 405);

  const svc = createClient(SUPABASE_URL, SERVICE_KEY);
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const interno = SERVICE_KEY !== "" && token === SERVICE_KEY;
  if (!interno) {
    const { data: { user } } = await svc.auth.getUser(token);
    if (!user) return responde({ error: "Sesion invalida." }, 401);
    if (user.app_metadata?.role !== "admin") return responde({ error: "Solo un administrador." }, 403);
  }

  let cuerpo: { cadena?: number; reintentar?: boolean } = {};
  try { cuerpo = await req.json(); } catch { /* sin cuerpo */ }
  const cadena = Number(cuerpo.cadena ?? 0) || 0;

  if (cuerpo.reintentar === true) {
    await (svc.from("checadas") as any).update({ foto_error: null })
      .eq("origen", "APPCHECAR").is("foto", null).not("foto_error", "is", null);
  }

  const { data: filas, error } = await (svc.from("checadas") as any)
    .select("id, profile_id, foto_origen")
    .eq("origen", "APPCHECAR").is("foto", null).is("foto_error", null)
    .not("foto_origen", "is", null)
    .limit(LOTE);
  if (error) return responde({ error: error.message }, 500);

  let copiadas = 0, fallidas = 0;
  for (const f of (filas ?? []) as Array<Record<string, string>>) {
    const ruta = `${f.profile_id}/appchecar/${f.id}.jpg`;
    const falla = async (motivo: string) => {
      fallidas++;
      await (svc.from("checadas") as any).update({ foto_error: motivo.slice(0, 300) }).eq("id", f.id);
    };
    try {
      const r = await fetch(f.foto_origen, { redirect: "follow", signal: AbortSignal.timeout(20_000) });
      const tipo = r.headers.get("Content-Type") ?? "";
      if (!r.ok || !tipo.startsWith("image/")) {
        await r.body?.cancel();
        await falla(`appchecar respondio ${r.status} ${tipo}`);
        continue;
      }
      const datos = new Uint8Array(await r.arrayBuffer());
      const { error: e } = await svc.storage.from(BUCKET)
        .upload(ruta, datos, { contentType: "image/jpeg", upsert: true });
      if (e) { await falla(`Al subir: ${e.message}`); continue; }
      await (svc.from("checadas") as any).update({ foto: ruta }).eq("id", f.id);
      copiadas++;
    } catch (e) {
      await falla(`No se pudo descargar: ${e}`);
    }
  }

  const { count } = await (svc.from("checadas") as any)
    .select("id", { count: "exact", head: true })
    .eq("origen", "APPCHECAR").is("foto", null).is("foto_error", null).not("foto_origen", "is", null);
  const pendientes = count ?? 0;

  if (pendientes > 0 && cadena < MAX_CADENA && (filas ?? []).length > 0) {
    EdgeRuntime.waitUntil((async () => {
      for (let vez = 0; vez < 2; vez++) {
        try {
          const r = await fetch(`${SUPABASE_URL}/functions/v1/copiar-fotos-appchecar`, {
            method: "POST",
            headers: { Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
            body: JSON.stringify({ cadena: cadena + 1 }),
          });
          await r.body?.cancel();
          if (r.ok) return;
        } catch (e) {
          console.log(`copiar-fotos-appchecar: paso ${cadena + 1} fallo: ${e}`);
        }
      }
    })());
  }

  return responde({ copiadas, fallidas, pendientes, cadena });
});
