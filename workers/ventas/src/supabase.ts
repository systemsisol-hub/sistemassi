// Acceso a las tablas ventas_* de Supabase por PostgREST.
//
// El Worker entra con la llave de servicio, que se salta RLS: es la unica puerta por la que un
// visitante anonimo llega a la base, y solo por las consultas de este archivo. La app de
// sistemassi lee las mismas tablas con la sesion de cada usuario y sus permisos.

export type EnvSupabase = {
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
};

export class ErrorSupabase extends Error {}

export async function sb<T = any>(
  env: EnvSupabase,
  ruta: string,
  init: RequestInit & { prefer?: string } = {}
): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("apikey", env.SUPABASE_SERVICE_ROLE_KEY);
  headers.set("authorization", `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`);
  if (init.body) headers.set("content-type", "application/json");
  if (init.prefer) headers.set("prefer", init.prefer);
  const res = await fetch(`${env.SUPABASE_URL}/rest/v1/${ruta}`, { ...init, headers });
  if (!res.ok) throw new ErrorSupabase(`Supabase ${res.status} en ${ruta}: ${await res.text()}`);
  const texto = await res.text();
  return (texto ? JSON.parse(texto) : null) as T;
}

// Filtro eq de PostgREST con el valor escapado.
export const eq = (v: string) => `eq.${encodeURIComponent(v)}`;

export type Desarrollo = {
  id: string;
  nombre: string;
  slug: string;
  url_pagina: string | null;
  alias: string[];
  brochure_es: string | null;
  brochure_en: string | null;
  re: RegExp;
};

// «Punta Pacífico» → /punta\s*pac[ií]fico/i. Los espacios y guiones se vuelven opcionales y cada
// vocal acepta su acento, para reconocerlo como lo escriba el cliente.
export function regexDeNombres(nombres: string[]): RegExp {
  const vocal: Record<string, string> = { a: "[aá]", e: "[eé]", i: "[ií]", o: "[oó]", u: "[uúü]" };
  const partes = [...new Set(nombres.map((n) => n.trim().toLowerCase()).filter(Boolean))].map((n) =>
    n
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
      .replace(/[\s-]+/g, "\\s*-?\\s*")
      .replace(/[aeiou]/g, (v) => vocal[v])
  );
  return new RegExp(partes.join("|") || "(?!)", "i");
}

export async function cargarDesarrollos(env: EnvSupabase): Promise<Desarrollo[]> {
  const filas = await sb<Omit<Desarrollo, "re">[]>(
    env,
    "ventas_desarrollos?select=id,nombre,slug,url_pagina,alias,brochure_es,brochure_en&is_active=eq.true&order=nombre"
  );
  return filas.map((d) => ({ ...d, re: regexDeNombres([d.nombre, ...(d.alias ?? [])]) }));
}

// Quien pide algo del panel: se valida su sesion de sistemassi contra Supabase Auth y se revisa
// su permiso en profiles, igual que has_permission() en la base.
export async function usuarioConPermiso(
  env: EnvSupabase,
  authorization: string | undefined,
  permiso: "show_ventas" | "edit_ventas"
): Promise<boolean> {
  if (!authorization?.startsWith("Bearer ")) return false;
  const res = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, authorization },
  });
  if (!res.ok) return false;
  const user = (await res.json()) as { id?: string; app_metadata?: { role?: string } };
  if (!user.id) return false;
  if (user.app_metadata?.role === "admin") return true;
  const perfiles = await sb<{ role: string | null; permissions: Record<string, unknown> | null }[]>(
    env,
    `profiles?select=role,permissions&id=${eq(user.id)}`
  );
  const p = perfiles[0];
  return p?.role === "admin" || p?.permissions?.[permiso] === true;
}
