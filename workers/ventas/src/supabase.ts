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
//
// Distingue «sin sesion» de «sin permiso» porque piden cosas distintas a quien lo ve: una sesion
// cerrada en otro lado (p. ej. al cambiar la contraseña) sigue sirviendo para leer tablas hasta que
// caduca el token, pero Auth ya no la reconoce; decir «sin permiso» ahi manda a buscar un problema
// de permisos que no existe.
export type Acceso = "ok" | "sin_sesion" | "sin_permiso";

export async function accesoVentas(
  env: EnvSupabase,
  authorization: string | undefined,
  permiso: "show_ventas" | "edit_ventas"
): Promise<Acceso> {
  if (!authorization?.startsWith("Bearer ")) return "sin_sesion";
  const res = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, authorization },
  });
  if (!res.ok) return "sin_sesion";
  const user = (await res.json()) as { id?: string; app_metadata?: { role?: string } };
  if (!user.id) return "sin_sesion";
  if (user.app_metadata?.role === "admin") return "ok";
  const perfiles = await sb<{ role: string | null; permissions: Record<string, unknown> | null }[]>(
    env,
    `profiles?select=role,permissions&id=${eq(user.id)}`
  );
  const p = perfiles[0];
  return p?.role === "admin" || p?.permissions?.[permiso] === true ? "ok" : "sin_permiso";
}

// 401 = hay que volver a iniciar sesion; 403 = la sesion es buena pero le falta el permiso.
export function respuestaSinAcceso(acceso: Exclude<Acceso, "ok">): Response {
  return acceso === "sin_sesion"
    ? Response.json({ ok: false, error: "Tu sesión ya no es válida. Cierra sesión y vuelve a entrar." }, { status: 401 })
    : Response.json({ ok: false, error: "No tienes permiso para Ventas." }, { status: 403 });
}
