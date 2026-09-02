// Lo que necesita SOL del entorno.
//
// ─── Comparte la CUENTA con Soli, no el modelo ───────────────────────────────
//
// Decision del usuario el 02/09/2026: la misma cuenta de Ollama, otro modelo. Asi que `OLLAMA_API_KEY`
// y `OLLAMA_BASE_URL` son las MISMAS variables que usa Soli —no se duplican con otro nombre, porque
// dos nombres para la misma llave es garantia de que un dia se roten a medias— y solo el modelo es
// propio: `SOL_MODEL`.
//
// Consecuencia que conviene tener presente: con una sola cuenta la factura es una sola, asi que los
// costos de Soli y de SOL no se separan por facturacion. Lo que si permite separarlos es contar las
// llamadas de cada uno; ver `bitacora` en index.ts.
//
// TODA la configuracion vive aqui, en variables de entorno, y la pantalla solo la MUESTRA. No hay
// forma de cambiarla desde la aplicacion, tambien por decision del usuario.

import { createClient } from "jsr:@supabase/supabase-js@2";

export const OLLAMA_KEY  = Deno.env.get("OLLAMA_API_KEY") ?? "";
export const OLLAMA_BASE = Deno.env.get("OLLAMA_BASE_URL") ?? "https://ollama.com/api";

/// El modelo de SOL. VACIO por omision, a proposito.
///
/// Sin modelo configurado la funcion contesta que SOL no esta conectado, en lugar de caerse contra
/// el proveedor con un nombre inventado. Un valor por omision aqui seria peor: haria creer que esta
/// configurado cuando nadie lo eligio.
export const SOL_MODEL = Deno.env.get("SOL_MODEL") ?? "";

/// Al que se cambia si el principal falla. Vacio = sin respaldo, igual que en Soli.
///
/// Conviene que sea de otra familia que el principal: si los dos son del mismo modelo base, la
/// caida que tumbe a uno tumbara al otro. Lo aprendimos el 12/08/2026, cuando el modelo de Soli
/// empezo a devolver 500 a todo.
export const SOL_MODEL_RESPALDO = Deno.env.get("SOL_MODEL_RESPALDO") ?? "";

export const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
export const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

export const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export const hoy = new Date().toLocaleDateString("es-MX", {
  timeZone: "America/Mexico_City",
  year: "numeric", month: "long", day: "numeric",
});

/// La fecha de hoy en ISO, para comparar vigencias sin depender de la zona del servidor.
export const hoyISO = new Date().toLocaleDateString("en-CA", {
  timeZone: "America/Mexico_City",
});

export type Db = ReturnType<typeof createClient>;
