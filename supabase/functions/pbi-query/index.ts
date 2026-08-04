// Ejecuta consultas DAX de lectura contra un dataset de Power BI.
//
// Por qué existe: los enlaces de powerbi_links son embeds públicos ("Publicar en la web").
// Ese token sólo sirve para renderizar el iframe — no da acceso a los datos. Para leer el
// modelo hay que autenticarse contra la API REST de Power BI con una entidad de servicio.
//
// Seguridad, en tres capas:
//   1. El cliente NUNCA manda workspace/dataset. Manda link_id y el servidor resuelve el
//      resto leyendo powerbi_links. Así no se puede consultar un dataset arbitrario.
//   2. Se verifica que el usuario tenga acceso a ese enlace (admin, dueño, o asignado).
//   3. executeQueries sólo acepta DAX y no puede modificar el modelo ni los datos. Aun así
//      se valida la forma de la consulta.
//
// El client secret vive únicamente como secreto de Edge Function, jamás en el cliente Flutter.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const AZ_TENANT    = Deno.env.get("AZURE_TENANT_ID") ?? "";
const AZ_CLIENT    = Deno.env.get("AZURE_CLIENT_ID") ?? "";
const AZ_SECRET    = Deno.env.get("AZURE_CLIENT_SECRET") ?? "";

const PBI_SCOPE = "https://analysis.windows.net/powerbi/api/.default";

/** Topes para no reventar el contexto del modelo con tablas enormes. */
const MAX_ROWS      = 500;
const MAX_CHARS     = 100_000;
const MAX_DAX_CHARS = 8_000;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

// ── Token de Azure ────────────────────────────────────────────────────────────
// Se cachea en el isolate. Los isolates se reciclan, así que esto ahorra llamadas
// dentro de una misma conversación pero no es un caché global fiable — no importa,
// pedir el token de nuevo es baratísimo.

let cachedToken: { token: string; expiresAt: number } | null = null;

async function getPbiToken(): Promise<string> {
  if (!AZ_TENANT || !AZ_CLIENT || !AZ_SECRET) {
    throw new HttpError(
      503,
      "Falta configurar las credenciales de Power BI (AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET).",
    );
  }

  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt > now + 60_000) return cachedToken.token;

  const res = await fetch(
    `https://login.microsoftonline.com/${AZ_TENANT}/oauth2/v2.0/token`,
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type:    "client_credentials",
        client_id:     AZ_CLIENT,
        client_secret: AZ_SECRET,
        scope:         PBI_SCOPE,
      }).toString(),
    },
  );

  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.access_token) {
    // No propagar el cuerpo crudo: puede traer detalles del tenant del proveedor.
    const detail = body.error_description ?? body.error ?? `HTTP ${res.status}`;
    throw new HttpError(502, `No se pudo autenticar contra Azure AD: ${detail}`);
  }

  cachedToken = {
    token:     body.access_token,
    expiresAt: now + (Number(body.expires_in) || 3600) * 1000,
  };
  return cachedToken.token;
}

// ── Validación de la consulta ────────────────────────────────────────────────

/**
 * Una consulta DAX válida arranca con EVALUATE o, si define medidas locales, con DEFINE.
 * executeQueries no puede escribir, así que esto no es una barrera de seguridad sino un
 * filtro temprano para dar un error claro en lugar de un 400 opaco de Power BI.
 */
function assertValidDax(dax: unknown): string {
  if (typeof dax !== "string" || dax.trim().length === 0) {
    throw new HttpError(400, "Falta la consulta DAX.");
  }
  const trimmed = dax.trim();
  if (trimmed.length > MAX_DAX_CHARS) {
    throw new HttpError(400, `La consulta excede ${MAX_DAX_CHARS} caracteres.`);
  }
  const head = trimmed.toUpperCase();
  if (!head.startsWith("EVALUATE") && !head.startsWith("DEFINE")) {
    throw new HttpError(400, "La consulta DAX debe iniciar con EVALUATE o DEFINE.");
  }
  return trimmed;
}

// ── Resolución del enlace y control de acceso ────────────────────────────────

interface LinkRow {
  id: string;
  title: string | null;
  pbi_workspace_id: string | null;
  pbi_dataset_id: string | null;
  ai_context: string | null;
  is_active: boolean | null;
  created_by: string | null;
}

async function resolveLink(
  db: ReturnType<typeof createClient>,
  linkId: unknown,
  userId: string,
  isAdmin: boolean,
): Promise<LinkRow> {
  if (typeof linkId !== "string" || linkId.length === 0) {
    throw new HttpError(400, "Falta link_id.");
  }

  const { data, error } = await db
    .from("powerbi_links")
    .select("id, title, pbi_workspace_id, pbi_dataset_id, ai_context, is_active, created_by")
    .eq("id", linkId)
    .maybeSingle();

  if (error) throw new HttpError(500, error.message);
  if (!data)  throw new HttpError(404, "El reporte no existe.");

  const link = data as unknown as LinkRow;
  if (link.is_active === false) throw new HttpError(403, "El reporte está inactivo.");

  // Admin ve todo; el dueño ve el suyo; los demás requieren asignación explícita.
  if (!isAdmin && link.created_by !== userId) {
    const { data: granted } = await db
      .from("powerbi_link_users")
      .select("user_id")
      .eq("link_id", linkId)
      .eq("user_id", userId)
      .maybeSingle();
    if (!granted) throw new HttpError(403, "No tienes acceso a este reporte.");
  }

  if (!link.pbi_workspace_id || !link.pbi_dataset_id) {
    throw new HttpError(
      400,
      "Este reporte no tiene un dataset de Power BI configurado. " +
      "Un administrador debe capturarlo en el formulario del enlace.",
    );
  }

  return link;
}

// ── Ejecución ────────────────────────────────────────────────────────────────

async function executeDax(link: LinkRow, dax: string) {
  const token = await getPbiToken();

  const res = await fetch(
    `https://api.powerbi.com/v1.0/myorg/groups/${link.pbi_workspace_id}` +
    `/datasets/${link.pbi_dataset_id}/executeQueries`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type":  "application/json",
      },
      body: JSON.stringify({
        queries: [{ query: dax }],
        serializerSettings: { includeNulls: false },
      }),
    },
  );

  const body = await res.json().catch(() => ({}));

  if (!res.ok) {
    // Power BI anida el detalle útil en error.pbi.error.details[].detail.value
    const err = body?.error ?? {};
    const nested = err?.pbi?.error?.details?.[0]?.detail?.value;
    const detail = nested ?? err?.details?.[0]?.message ?? err?.message ?? `HTTP ${res.status}`;
    throw new HttpError(res.status === 401 || res.status === 403 ? 502 : 400, `Power BI: ${detail}`);
  }

  const allRows = body?.results?.[0]?.tables?.[0]?.rows ?? [];
  return truncate(Array.isArray(allRows) ? allRows : []);
}

/** Recorta por número de filas y por tamaño serializado, informando siempre el recorte. */
function truncate(rows: unknown[]) {
  const total = rows.length;
  let out = total > MAX_ROWS ? rows.slice(0, MAX_ROWS) : rows;

  while (out.length > 1 && JSON.stringify(out).length > MAX_CHARS) {
    out = out.slice(0, Math.floor(out.length / 2));
  }

  return {
    rows:       out,
    row_count:  out.length,
    total_rows: total,
    truncated:  out.length < total,
  };
}

// ── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const auth = req.headers.get("Authorization");
    if (!auth) throw new HttpError(401, "No authorization");

    const db = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data: { user }, error: authErr } = await db.auth.getUser(
      auth.replace("Bearer ", ""),
    );
    if (authErr || !user) throw new HttpError(401, "Unauthorized");

    const { data: prof } = await db
      .from("profiles")
      .select("role, permissions")
      .eq("id", user.id)
      .single();

    // Mismo criterio que ai-assistant: admin, o permiso show_ai explícito.
    const isAdmin   = prof?.role === "admin";
    const hasAiPerm = (prof?.permissions as Record<string, unknown>)?.show_ai === true;
    if (!isAdmin && !hasAiPerm) throw new HttpError(403, "Forbidden");

    const payload = await req.json().catch(() => ({}));
    const dax     = assertValidDax(payload.dax);
    const link    = await resolveLink(db, payload.link_id, user.id, isAdmin);

    const result = await executeDax(link, dax);

    return json({
      ...result,
      report: { id: link.id, title: link.title },
    });
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    const msg = e instanceof Error ? e.message : String(e);
    return json({ error: msg }, 500);
  }
});
