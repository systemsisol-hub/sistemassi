// Consulta datos de un dataset de Power BI para el asistente IA. Sólo lectura.
//
// Por qué existe: los enlaces de powerbi_links son embeds públicos ("Publicar en la web").
// Ese token sólo sirve para renderizar el iframe — no da acceso a los datos. Para leer el
// modelo hay que autenticarse contra la API REST de Power BI con una entidad de servicio.
//
// ─── Por qué el asistente NO escribe DAX ──────────────────────────────────────
//
// La tabla de hechos es una FOTO PERIÓDICA: guarda el saldo por fecha. Una consulta sin
// contexto de fecha suma todas las fotos y cuenta el mismo saldo decenas de veces.
// Medido contra el panel de PROVEEDORES:
//
//     sin filtro de periodo  →  180,880,573.13
//     con filtro "Actual"    →   22,088,254.08   (coincide con el panel al centavo)
//
// Un error de 8x en cifras financieras, con dos decimales y tono de autoridad. Advertirle al
// modelo en el prompt no sirve: lo olvida cuando la conversación se alarga. Por eso el modelo
// manda PARÁMETROS y el servidor arma la consulta, inyectando el contexto de filtro por
// construcción. El modelo no puede omitirlo porque nunca toca la consulta.
//
// Todo nombre de medida o columna se valida contra el esquema real del modelo antes de
// interpolarse — nada llega crudo al DAX.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const AZ_TENANT    = Deno.env.get("AZURE_TENANT_ID") ?? "";
const AZ_CLIENT    = Deno.env.get("AZURE_CLIENT_ID") ?? "";
const AZ_SECRET    = Deno.env.get("AZURE_CLIENT_SECRET") ?? "";

const PBI_SCOPE = "https://analysis.windows.net/powerbi/api/.default";

const MAX_ROWS     = 500;
const MAX_CHARS    = 100_000;
const CACHE_TTL_MS = 24 * 60 * 60 * 1000;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const reply = (body: unknown, status = 200) =>
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

let cachedToken: { token: string; expiresAt: number } | null = null;

async function getPbiToken(): Promise<string> {
  if (!AZ_TENANT || !AZ_CLIENT || !AZ_SECRET) {
    throw new HttpError(
      503,
      "Power BI no está configurado todavía: faltan AZURE_TENANT_ID, AZURE_CLIENT_ID y " +
      "AZURE_CLIENT_SECRET. Se solicitan al administrador del tenant dueño del workspace.",
    );
  }

  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt > now + 60_000) return cachedToken.token;

  const res = await fetch(
    `https://login.microsoftonline.com/${AZ_TENANT}/oauth2/v2.0/token`,
    {
      method:  "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body:    new URLSearchParams({
        grant_type:    "client_credentials",
        client_id:     AZ_CLIENT,
        client_secret: AZ_SECRET,
        scope:         PBI_SCOPE,
      }).toString(),
    },
  );

  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.access_token) {
    // Sin volcar el cuerpo crudo: puede traer detalles del tenant ajeno.
    const detail = body.error_description ?? body.error ?? `HTTP ${res.status}`;
    throw new HttpError(502, `No se pudo autenticar contra Azure AD: ${detail}`);
  }

  cachedToken = {
    token:     body.access_token,
    expiresAt: now + (Number(body.expires_in) || 3600) * 1000,
  };
  return cachedToken.token;
}

// ── Ejecución cruda de DAX (interna: el cliente nunca la alcanza) ─────────────

interface LinkRow {
  id: string;
  title: string | null;
  pbi_workspace_id: string | null;
  pbi_dataset_id: string | null;
  ai_context: string | null;
  is_active: boolean | null;
  created_by: string | null;
}

async function runDax(link: LinkRow, dax: string): Promise<Record<string, unknown>[]> {
  const token = await getPbiToken();

  const res = await fetch(
    `https://api.powerbi.com/v1.0/myorg/groups/${link.pbi_workspace_id}` +
    `/datasets/${link.pbi_dataset_id}/executeQueries`,
    {
      method:  "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type":  "application/json",
      },
      body: JSON.stringify({ queries: [{ query: dax }] }),
    },
  );

  const body = await res.json().catch(() => ({}));

  if (!res.ok) {
    // Power BI anida el detalle útil en error.pbi.error.details[].detail.value
    const err    = body?.error ?? {};
    const nested = err?.pbi?.error?.details?.[0]?.detail?.value;
    const detail = nested ?? err?.details?.[0]?.message ?? err?.message ?? `HTTP ${res.status}`;
    // 401/403 son problema de nuestra credencial, no de la petición del usuario.
    const status = res.status === 401 || res.status === 403 ? 502 : 400;
    throw new HttpError(status, `Power BI: ${detail}`);
  }

  const rows = body?.results?.[0]?.tables?.[0]?.rows;
  return Array.isArray(rows) ? rows : [];
}

// ── Esquema del modelo (con caché) ────────────────────────────────────────────

interface ModelItem {
  tabla: string;
  nombre: string;
  /**
   * FormatString de la medida. Importa más de lo que parece: los porcentajes se guardan como
   * fracción (0.9946 = 99.5%). Un modelo que lea el número crudo sin saber su formato reporta
   * "0.99%" en lugar de "99.5%" — un error de 100x que suena razonable.
   */
  formato?: string;
}

interface ModelSchema {
  medidas:  ModelItem[];
  columnas: ModelItem[];
  /** Columnas detectadas para fijar el periodo. Null si el modelo no sigue la convención. */
  periodo: { tabla: string; anio: string; mes: string } | null;
}

/**
 * Las medidas del patrón TopN sólo tienen sentido dentro de ese patrón: usadas como total
 * dan cifras incompletas. Un modelo que ve "Vencido Top" en la lista la elegiría sin dudar
 * al preguntarle por el vencido total, así que no se exponen.
 */
function esMedidaDePatronTopN(m: ModelItem): boolean {
  if (/^(TopN|Top & Other)$/i.test(m.tabla)) return true;
  return /\b(top|other)\b/i.test(m.nombre) || /^rank\b/i.test(m.nombre.trim());
}

/**
 * Detecta las columnas que fijan el periodo. Los datasets de este proveedor exponen un
 * miembro "Actual" mediante columnas `Año Slicer` / `Mes Slicer` separadas de `Año` / `Mes`.
 * Se prefiere la tabla de hechos: las dimensiones `Cat *` también las tienen, pero el filtro
 * verificado contra el panel es el del hecho.
 */
function detectarPeriodo(columnas: ModelItem[]): ModelSchema["periodo"] {
  const conAmbas = [...new Set(columnas.map((c) => c.tabla))].filter((t) => {
    const cols = columnas.filter((c) => c.tabla === t).map((c) => c.nombre);
    return cols.includes("Año Slicer") && cols.includes("Mes Slicer");
  });
  if (conAmbas.length === 0) return null;
  const tabla = conAmbas.find((t) => !/^cat\s/i.test(t)) ?? conAmbas[0];
  return { tabla, anio: "Año Slicer", mes: "Mes Slicer" };
}

const MEDIDAS_VISIBLES = "FILTER(INFO.VIEW.MEASURES(), [IsHidden]=FALSE())";

/**
 * Formato de una medida. Medido en el dataset de PROVEEDORES: la columna `FormatString`
 * existe pero viene **vacía en todas las medidas** — el formato se aplica en los visuales del
 * reporte, no en el modelo. Así que el prefijo `%` del nombre no es un respaldo para cuando
 * falta la columna: es la única señal disponible en la práctica, y hay que aplicarla siempre
 * que el FormatString venga en blanco.
 */
function formatoDeMedida(nombre: string, formatString: unknown): string | undefined {
  const declarado = formatString == null ? "" : String(formatString).trim();
  if (declarado) return declarado;
  return nombre.trimStart().startsWith("%") ? "0.0%" : undefined;
}

async function fetchMedidas(link: LinkRow): Promise<ModelItem[]> {
  const construir = (r: Record<string, unknown>): ModelItem => {
    const nombre = String(r["[nombre]"] ?? "");
    return {
      tabla:   String(r["[tabla]"] ?? ""),
      nombre,
      formato: formatoDeMedida(nombre, r["[formato]"]),
    };
  };

  try {
    const rows = await runDax(
      link,
      `EVALUATE SELECTCOLUMNS(${MEDIDAS_VISIBLES}, ` +
      '"tabla", [Table], "nombre", [Name], "formato", [FormatString])',
    );
    return rows.map(construir);
  } catch {
    // Modelos cuya versión de INFO.VIEW.MEASURES() no expone FormatString.
    const rows = await runDax(
      link,
      `EVALUATE SELECTCOLUMNS(${MEDIDAS_VISIBLES}, "tabla", [Table], "nombre", [Name])`,
    );
    return rows.map(construir);
  }
}

async function fetchColumnas(link: LinkRow): Promise<ModelItem[]> {
  const rows = await runDax(
    link,
    'EVALUATE SELECTCOLUMNS(FILTER(INFO.VIEW.COLUMNS(), [IsHidden]=FALSE()), ' +
    '"tabla", [Table], "nombre", [Name])',
  );
  return rows.map((r) => ({
    tabla:  String(r["[tabla]"] ?? ""),
    nombre: String(r["[nombre]"] ?? ""),
  }));
}

async function getModel(
  db: ReturnType<typeof createClient>,
  link: LinkRow,
): Promise<ModelSchema> {
  const datasetId = link.pbi_dataset_id!;

  const { data: cached } = await db
    .from("pbi_model_cache")
    .select("schema_json, updated_at")
    .eq("dataset_id", datasetId)
    .maybeSingle();

  if (cached?.schema_json) {
    const age = Date.now() - new Date(cached.updated_at as string).getTime();
    if (age < CACHE_TTL_MS) return cached.schema_json as unknown as ModelSchema;
  }

  // Un ] o " en el nombre rompería la interpolación al armar el DAX.
  const usable = (i: ModelItem) =>
    i.tabla && i.nombre && !/[\]"]/.test(i.nombre) && !/['"]/.test(i.tabla);

  const medidas  = (await fetchMedidas(link)).filter(usable).filter((m) => !esMedidaDePatronTopN(m));
  const columnas = (await fetchColumnas(link)).filter(usable);

  const schema: ModelSchema = {
    medidas,
    columnas,
    periodo: detectarPeriodo(columnas),
  };

  await db.from("pbi_model_cache").upsert({
    dataset_id:  datasetId,
    schema_json: schema,
    updated_at:  new Date().toISOString(),
  });

  return schema;
}

// ── Construcción validada de la consulta ─────────────────────────────────────

interface QueryParams {
  medidas?: unknown;
  agrupar_por?: unknown;
  periodo?: unknown;
  limite?: unknown;
}

function asStringArray(v: unknown, campo: string): string[] {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v)) throw new HttpError(400, `${campo} debe ser una lista.`);
  return v.map((x) => {
    if (typeof x !== "string") throw new HttpError(400, `${campo} sólo acepta texto.`);
    return x.trim();
  }).filter((x) => x.length > 0);
}

/** Filtros de periodo. Sin esto las cifras salen infladas por acumulación de fotos. */
function construirFiltrosPeriodo(schema: ModelSchema, periodo: unknown): string[] {
  if (!schema.periodo) {
    // El modelo no sigue la convención: mejor fallar que devolver cifras infladas en silencio.
    throw new HttpError(
      422,
      "No se detectaron columnas de periodo ('Año Slicer' / 'Mes Slicer') en este modelo. " +
      "Sin fijar periodo las cifras se inflan por acumulación, así que no se consulta.",
    );
  }

  const { tabla, anio, mes } = schema.periodo;
  const ref = (col: string) => `'${tabla}'[${col}]`;

  if (periodo === undefined || periodo === null || periodo === "actual") {
    return [`${ref(anio)} = "Actual"`, `${ref(mes)} = "Actual"`];
  }

  if (typeof periodo !== "object") {
    throw new HttpError(400, 'periodo debe ser "actual" o un objeto { anio, mes }.');
  }

  const p = periodo as Record<string, unknown>;
  const valores = { anio: p.anio, mes: p.mes };
  const filtros: string[] = [];

  for (const [clave, col] of [["anio", anio], ["mes", mes]] as const) {
    const v = valores[clave];
    if (v === undefined || v === null) continue;
    if (typeof v !== "string" || /["\]]/.test(v)) {
      throw new HttpError(400, `Valor inválido para ${clave}.`);
    }
    filtros.push(`${ref(col)} = "${v}"`);
  }

  if (filtros.length === 0) {
    throw new HttpError(400, "El periodo debe especificar al menos anio o mes.");
  }
  return filtros;
}

interface BuiltQuery { dax: string; medidas: string[]; columnas: string[] }

function construirConsulta(schema: ModelSchema, params: QueryParams): BuiltQuery {
  const medidas    = asStringArray(params.medidas, "medidas");
  const agruparPor = asStringArray(params.agrupar_por, "agrupar_por");

  if (medidas.length === 0 && agruparPor.length === 0) {
    throw new HttpError(400, "Indica al menos una medida o una columna de agrupación.");
  }

  // Lista blanca: toda medida debe existir en el modelo.
  const validas = new Set(schema.medidas.map((m) => m.nombre));
  for (const m of medidas) {
    if (!validas.has(m)) {
      throw new HttpError(
        400,
        `La medida "${m}" no existe en el modelo o no es válida para totales. ` +
        `Consulta las disponibles con la acción "modelo".`,
      );
    }
  }

  // Las columnas llegan como "Tabla[Columna]" y deben existir tal cual.
  const refsValidas = new Map(
    schema.columnas.map((c) => [`${c.tabla}[${c.nombre}]`, c]),
  );
  const colsDax: string[] = [];
  for (const ref of agruparPor) {
    const col = refsValidas.get(ref);
    if (!col) {
      throw new HttpError(
        400,
        `La columna "${ref}" no existe en el modelo. Usa el formato Tabla[Columna] ` +
        `con los nombres que devuelve la acción "modelo".`,
      );
    }
    colsDax.push(`'${col.tabla}'[${col.nombre}]`);
  }

  const pares   = medidas.map((m) => `"${m}", [${m}]`);
  const filtros = construirFiltrosPeriodo(schema, params.periodo);

  let tabla: string;
  if (colsDax.length > 0) {
    tabla = `SUMMARIZECOLUMNS(${[...colsDax, ...pares].join(", ")})`;
  } else {
    tabla = `ROW(${pares.join(", ")})`;
  }

  let dax = `EVALUATE\nCALCULATETABLE(\n  ${tabla},\n  ${filtros.join(",\n  ")}\n)`;

  // Ordenar y recortar sólo tiene sentido al agrupar por alguna dimensión.
  if (colsDax.length > 0 && medidas.length > 0) {
    const orden  = `[${medidas[0]}]`;
    const limite = Math.min(Math.max(Number(params.limite) || MAX_ROWS, 1), MAX_ROWS);
    dax = `EVALUATE\nTOPN(\n  ${limite},\n  CALCULATETABLE(\n    ${tabla},\n    ` +
          `${filtros.join(",\n    ")}\n  ),\n  ${orden}, DESC\n)\nORDER BY ${orden} DESC`;
  }

  return { dax, medidas, columnas: agruparPor };
}

// ── Normalización de resultados ──────────────────────────────────────────────

/**
 * Power BI omite los valores nulos, dejando renglones con llaves distintas: una llave ausente
 * se lee como cero. Aquí se uniforman todas las llaves y se limpia el ruido de punto flotante
 * (394238.77999999997 → 394238.78) sin dañar porcentajes ni scores.
 */
function normalizar(rows: Record<string, unknown>[]) {
  const total = rows.length;
  let out = total > MAX_ROWS ? rows.slice(0, MAX_ROWS) : rows;

  while (out.length > 1 && JSON.stringify(out).length > MAX_CHARS) {
    out = out.slice(0, Math.floor(out.length / 2));
  }

  const llaves = [...new Set(out.flatMap((r) => Object.keys(r)))];

  const limpio = out.map((r) => {
    const fila: Record<string, unknown> = {};
    for (const k of llaves) {
      const v = r[k];
      // El nombre viene como "[Alias]" o "Tabla[Columna]"; se deja tal cual para no perder origen.
      fila[k] = typeof v === "number" && Number.isFinite(v)
        ? Math.round(v * 1e6) / 1e6
        : (v ?? null);
    }
    return fila;
  });

  return {
    rows:       limpio,
    row_count:  limpio.length,
    total_rows: total,
    truncated:  limpio.length < total,
  };
}

// ── Resolución del enlace y control de acceso ────────────────────────────────

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
      422,
      "Este reporte no tiene un dataset de Power BI configurado. Un administrador debe " +
      "capturar el workspace y el dataset en el formulario del enlace.",
    );
  }

  return link;
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

    const payload = await req.json().catch(() => ({})) as QueryParams & {
      link_id?: unknown; accion?: unknown;
    };

    const link   = await resolveLink(db, payload.link_id, user.id, isAdmin);
    const schema = await getModel(db, link);
    const accion = payload.accion ?? "consultar";

    if (accion === "modelo") {
      return reply({
        report:   { id: link.id, title: link.title, contexto: link.ai_context },
        medidas:  schema.medidas.map((m) => ({ nombre: m.nombre, formato: m.formato ?? null })),
        columnas: schema.columnas.map((c) => `${c.tabla}[${c.nombre}]`),
        periodo_soportado: schema.periodo !== null,
      });
    }

    if (accion !== "consultar") {
      throw new HttpError(400, 'accion debe ser "modelo" o "consultar".');
    }

    const built  = construirConsulta(schema, payload);
    const result = normalizar(await runDax(link, built.dax));

    // El formato viaja junto a las cifras, no sólo en el prompt: los porcentajes vienen como
    // fracción y sin esta pista el modelo reportaría 0.99% donde el panel dice 99.5%.
    const formatos = Object.fromEntries(
      built.medidas.map((m) => [
        m,
        schema.medidas.find((x) => x.nombre === m)?.formato ?? null,
      ]),
    );

    return reply({
      ...result,
      report:   { id: link.id, title: link.title },
      consulta: { medidas: built.medidas, agrupar_por: built.columnas, dax: built.dax },
      formatos,
    });
  } catch (e) {
    if (e instanceof HttpError) return reply({ error: e.message }, e.status);
    const msg = e instanceof Error ? e.message : String(e);
    return reply({ error: msg }, 500);
  }
});
