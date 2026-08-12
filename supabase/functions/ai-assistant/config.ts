// Lo que necesita todo el mundo: variables de entorno, CORS y la fecha de hoy.
//
// Vive aparte para que ningun modulo tenga que importar `index.ts` por una llave o por un tipo, que
// es como se forman los ciclos de importacion.

import { createClient } from "jsr:@supabase/supabase-js@2";

export const OLLAMA_KEY   = Deno.env.get("OLLAMA_API_KEY") ?? "";
export const OLLAMA_BASE  = Deno.env.get("OLLAMA_BASE_URL") ?? "https://ollama.com/api";
export const OLLAMA_MODEL = Deno.env.get("OLLAMA_MODEL") ?? "llama3.2";
export const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
export const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/// Secreto de la vía servidor-a-servidor, la que usa el puente de WhatsApp.
///
/// Si está vacío, esa vía queda APAGADA: no configurarlo no debe abrirla. Se compara en tiempo
/// constante porque un `===` sobre secretos filtra, por el tiempo de respuesta, cuántos caracteres
/// iniciales acertó quien lo está probando.
export const INTERNAL_SECRET = Deno.env.get("SOLI_INTERNAL_SECRET") ?? "";

export function igualesEnTiempoConstante(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let dif = 0;
  for (let i = 0; i < a.length; i++) dif |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return dif === 0;
}

export const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export const today = new Date().toLocaleDateString("es-MX", {
  timeZone: "America/Mexico_City",
  year: "numeric", month: "long", day: "numeric",
});
/// El cliente de Supabase ya construido.
///
/// Antes cada firma decia `ReturnType<typeof createClient>`, y eso obligaba a tres archivos a
/// importar supabase-js solo para nombrar un tipo.
export type Db = ReturnType<typeof createClient>;
