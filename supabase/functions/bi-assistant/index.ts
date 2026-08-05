// Asistente analista de reportes de Power BI. Independiente del asistente de RH.
//
// Por qué está separado de ai-assistant: son dos productos sin nada en común salvo la
// autenticación. Mientras compartían función, cada despliegue del analista ponía en riesgo al
// asistente de RH y obligaba a probar ambos. Ahora cada uno tiene su prompt, sus herramientas,
// su modelo y su radio de impacto.
//
// El analista NO escribe DAX. Manda parámetros a pbi-query, que arma la consulta e inyecta el
// contexto de filtro. El motivo está documentado en pbi-query: la tabla de hechos es una foto
// periódica y una consulta sin fecha infla las cifras 8x.
//
// ─── Proveedor de modelo ──────────────────────────────────────────────────────
//
// Se habla el formato de OpenAI (chat/completions con tools), que es compatible con Cloudflare
// Workers AI, con Ollama y con OpenAI mismo. Cambiar de proveedor es cambiar AI_BASE_URL,
// AI_API_KEY y AI_MODEL — no requiere tocar este archivo.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/** Base del endpoint compatible con OpenAI, sin la parte /chat/completions. */
const AI_BASE_URL = (Deno.env.get("AI_BASE_URL") ?? "").replace(/\/+$/, "");
const AI_API_KEY  = Deno.env.get("AI_API_KEY") ?? "";
const AI_MODEL    = Deno.env.get("AI_MODEL") ?? "@cf/openai/gpt-oss-120b";

const MAX_ITERACIONES = 8;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

const hoy = new Date().toLocaleDateString("es-MX", {
  timeZone: "America/Mexico_City",
  year: "numeric", month: "long", day: "numeric",
});

// ── Prompt ───────────────────────────────────────────────────────────────────

function systemPrompt(userName: string, reportTitle: string | null): string {
  const conReporte = reportTitle !== null;

  const encabezado = conReporte
    ? `Ayudas a ${userName} a interpretar el reporte de Power BI "${reportTitle}".`
    : `Ayudas a ${userName} a armar un panel a partir de sus reportes de Power BI. Todavía no hay ninguno elegido.`;

  const comoEmpezar = conReporte
    ? `1. Llama pbi_modelo antes de tu primera consulta. Usa los nombres EXACTOS que devuelve; no los adivines, traduzcas ni corrijas.`
    : `1. Empieza llamando pbi_reportes y pregúntale a ${userName} sobre cuál reporte quiere trabajar. Menciona sólo los que vengan con consultable en true; de los demás aclara que aún no tienen datos configurados.
2. Con el link_id elegido, llama pbi_modelo y cuéntale en pocas palabras qué puede consultar ahí: los grupos de medidas y los desgloses disponibles, no la lista completa.
3. Propón una o dos opciones concretas de panel antes de consultar, para no adivinar qué quiere ver.
4. Pasa ese mismo link_id en todas las llamadas siguientes.`;

  return `Eres analista de datos financieros de Sisol Soluciones Inmobiliarias. ${encabezado}
Respondes siempre en español, con precisión y sin adornos. Fecha actual: ${hoy}.

Tu ÚNICA fuente de datos son las herramientas de Power BI. No tienes acceso a colaboradores, incidencias, inventario, contactos ni asistencia: si preguntan de eso, aclara que este asistente cubre sólo los reportes de BI.

Cómo trabajar:
${comoEmpezar}
- En pbi_consultar no escribes DAX: das medidas, agrupación y periodo. El servidor fija el contexto de fecha.
- Declara siempre sobre qué periodo respondes. Por defecto es "Actual", el mismo que muestran los paneles.

Cómo redactar — importante:
- Tus resultados se muestran aparte, como gráfica y/o tabla. **NO repitas las filas en tu texto ni armes tablas en markdown**: se vería la misma información tres veces.
- Tu texto interpreta: qué destaca, la magnitud relativa, alguna anomalía, y sobre qué periodo respondes. Dos o tres frases bastan.
- Si el usuario pide explícitamente una lista o un valor puntual, entonces sí dilo en el texto.
- En pbi_consultar declara "presentacion" según lo que pidió el usuario: "grafica" si pidió gráfica o comparación visual, "tabla" si pidió el detalle, la lista o cifras exactas, y "auto" si no lo especificó.

Reglas sobre las cifras, obligatorias:
- Si el formato de una medida es un porcentaje (por ejemplo "0.0%"), el valor llega como FRACCIÓN: 0.9946 significa 99.5%. Conviértelo antes de reportarlo. Nunca escribas "0.99%" cuando el dato es 0.9946.
- Reporta montos con separador de miles y dos decimales.
- Si una medida no trae formato y su escala no es evidente (los "Score", por ejemplo), dilo explícitamente en vez de asumir que es porcentaje o índice.
- Si la respuesta trae truncated en true, avisa que la lista viene recortada.
- NUNCA inventes una cifra. Si una herramienta falla o devuelve vacío, dilo tal cual.

Verificación de consistencia — importante:
- No presentes un total sumando los renglones de una consulta agrupada: pide el total en una consulta sin agrupación, porque muchas medidas no son aditivas.
- Sí puedes sumar los renglones como CONTROL: si la suma de un desglose EXCEDE el total sin agrupar, algo está mal en la consulta o en el modelo. En ese caso dilo abiertamente, señala la discrepancia con ambas cifras, y NO presentes el desglose como si fuera confiable. Es mejor reportar una inconsistencia que un número convincente y falso.
- Si el usuario compara tus cifras con lo que ve en el panel y no coinciden, considera que el panel puede tener filtros que tú no aplicas (banderas de exclusión, intercompañía, moneda) y dilo en lugar de insistir en que tu número es el correcto.`;
}

// ── Herramientas ─────────────────────────────────────────────────────────────

/** Sólo se ofrece cuando no hay reporte en contexto: el flujo guiado de creación de paneles. */
const TOOL_REPORTES = {
  type: "function",
  function: {
    name: "pbi_reportes",
    description:
      "Lista los reportes que este usuario puede consultar, con su link_id y si tienen datos " +
      "disponibles. Úsala cuando no sepas sobre cuál reporte trabajar, para preguntarle al " +
      "usuario cuál quiere.",
    parameters: { type: "object", properties: {}, required: [] },
  },
};

const TOOLS = [
  {
    type: "function",
    function: {
      name: "pbi_modelo",
      description:
        "Devuelve las medidas y columnas disponibles de un reporte, con el formato de cada " +
        "medida. Llámala SIEMPRE antes de tu primera consulta: los nombres deben ser exactos.",
      parameters: {
        type: "object",
        properties: {
          link_id: {
            type: "string",
            description:
              "Reporte a inspeccionar. Obligatorio si no hay uno abierto; si lo hay, se ignora.",
          },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "pbi_consultar",
      description:
        "Consulta cifras del reporte. No escribes DAX: indicas qué medidas quieres, cómo " +
        "agruparlas y el periodo; el servidor arma la consulta y fija el contexto de fecha.",
      parameters: {
        type: "object",
        required: ["medidas"],
        properties: {
          link_id: {
            type: "string",
            description:
              "Reporte a consultar. Obligatorio si no hay uno abierto; si lo hay, se ignora.",
          },
          medidas: {
            type: "array", items: { type: "string" },
            description: "Nombres EXACTOS de medidas, tal como los devuelve pbi_modelo.",
          },
          agrupar_por: {
            type: "array", items: { type: "string" },
            description: "Columnas para desglosar, en formato Tabla[Columna]. Opcional.",
          },
          anio: {
            type: "string",
            description: "Año del vocabulario del modelo. Si se omite junto con mes, usa el periodo Actual.",
          },
          mes: { type: "string", description: "Mes del vocabulario del modelo. Opcional." },
          limite: { type: "number", description: "Máximo de renglones al agrupar." },
          presentacion: {
            type: "string",
            enum: ["auto", "grafica", "tabla"],
            description:
              "Cómo mostrar el resultado, según lo que pidió el usuario. 'grafica' si pidió " +
              "una gráfica o comparar visualmente; 'tabla' si pidió el detalle, la lista o " +
              "cifras exactas; 'auto' si no lo especificó.",
          },
        },
      },
    },
  },
];

type ToolInput = Record<string, unknown>;

/**
 * Delega en pbi-query reenviando el JWT del usuario, para que el control de acceso al reporte
 * viva en un solo lugar. El workspace y el dataset los resuelve pbi-query leyendo
 * powerbi_links: nunca viajan desde aquí ni desde el cliente.
 */
async function ejecutarHerramienta(
  name: string,
  input: ToolInput,
  linkFijo: string | null,
  authHeader: string,
): Promise<unknown> {
  // Un reporte abierto manda sobre lo que diga el modelo: si el usuario está viendo
  // PROVEEDORES, el asistente no puede desviarse a otro dataset. Sin reporte abierto el
  // modelo elige, y pbi-query valida que el usuario tenga acceso a ese enlace.
  const linkId = linkFijo ?? (typeof input.link_id === "string" ? input.link_id : null);

  if (name === "pbi_reportes") {
    if (linkFijo) {
      return { error: "Ya estás trabajando sobre un reporte; no hace falta listarlos." };
    }
    return await llamarPbiQuery({ accion: "reportes" }, authHeader);
  }

  if (!linkId) {
    return {
      error: "Falta indicar el reporte. Llama primero pbi_reportes, pregúntale al usuario " +
             "cuál quiere, y pasa su link_id.",
    };
  }

  const body: Record<string, unknown> = { link_id: linkId };

  if (name === "pbi_modelo") {
    body.accion = "modelo";
  } else if (name === "pbi_consultar") {
    body.accion  = "consultar";
    body.medidas = input.medidas ?? [];
    if (input.agrupar_por) body.agrupar_por = input.agrupar_por;
    if (input.limite)      body.limite      = input.limite;
    // Sin año ni mes explícitos se consulta el periodo "Actual", que es lo que muestra el panel.
    body.periodo = (input.anio || input.mes)
      ? { anio: input.anio, mes: input.mes }
      : "actual";
  } else {
    return { error: `Herramienta desconocida: ${name}` };
  }

  return await llamarPbiQuery(body, authHeader);
}

/** Único punto de salida hacia pbi-query, reenviando el JWT del usuario. */
async function llamarPbiQuery(
  body: Record<string, unknown>,
  authHeader: string,
): Promise<unknown> {
  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/pbi-query`, {
      method:  "POST",
      headers: { "Authorization": authHeader, "Content-Type": "application/json" },
      body:    JSON.stringify(body),
    });
    const out = await res.json().catch(() => ({}));
    if (!res.ok) return { error: out.error ?? `Error ${res.status} al consultar Power BI.` };
    return out;
  } catch (e) {
    return { error: `No se pudo contactar Power BI: ${e instanceof Error ? e.message : String(e)}` };
  }
}

// ── Cliente del modelo (formato OpenAI) ──────────────────────────────────────

interface ToolCall {
  id?: string;
  type?: string;
  function: { name: string; arguments?: string | ToolInput };
}

interface ChatMessage {
  role: string;
  content: string | null;
  tool_calls?: ToolCall[];
  tool_call_id?: string;
}

/**
 * Los argumentos llegan como texto JSON en el formato de OpenAI, pero algunos proveedores los
 * mandan ya como objeto. Se aceptan ambos y un JSON inválido no tumba la conversación.
 */
function parseArgs(raw: string | ToolInput | undefined): ToolInput {
  if (raw == null) return {};
  if (typeof raw !== "string") return raw;
  try {
    const v = JSON.parse(raw);
    return v && typeof v === "object" ? v as ToolInput : {};
  } catch {
    return {};
  }
}

async function llamarModelo(
  msgs: ChatMessage[],
  tools: unknown[],
): Promise<ChatMessage> {
  if (!AI_BASE_URL || !AI_API_KEY) {
    throw new Error(
      "El asistente de BI no está configurado: faltan AI_BASE_URL y AI_API_KEY. " +
      "Para Cloudflare Workers AI, AI_BASE_URL es " +
      "https://api.cloudflare.com/client/v4/accounts/<account_id>/ai/v1",
    );
  }

  const res = await fetch(`${AI_BASE_URL}/chat/completions`, {
    method:  "POST",
    headers: {
      "Authorization": `Bearer ${AI_API_KEY}`,
      "Content-Type":  "application/json",
    },
    body: JSON.stringify({
      model:       AI_MODEL,
      messages:    msgs,
      tools,
      tool_choice: "auto",
      stream:      false,
    }),
  });

  const body = await res.json().catch(() => ({}));

  if (!res.ok) {
    // Cloudflare anida los errores en errors[]; OpenAI en error.message.
    const cf  = Array.isArray(body?.errors) ? body.errors[0]?.message : null;
    const oai = body?.error?.message;
    throw new Error(`Modelo (${AI_MODEL}): ${cf ?? oai ?? `HTTP ${res.status}`}`);
  }

  const msg = body?.choices?.[0]?.message;
  if (!msg) throw new Error(`Respuesta inesperada del modelo (${AI_MODEL}).`);
  return msg as ChatMessage;
}

// ── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const auth = req.headers.get("Authorization");
    if (!auth) return reply({ error: "No authorization" }, 401);

    const db = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data: { user }, error: authErr } =
      await db.auth.getUser(auth.replace("Bearer ", ""));
    if (authErr || !user) return reply({ error: "Unauthorized" }, 401);

    const { data: prof } = await db
      .from("profiles")
      .select("role, permissions, nombre, paterno, materno")
      .eq("id", user.id)
      .single();

    // Mismo criterio que las otras funciones: admin, o permiso show_ai explícito.
    const isAdmin   = prof?.role === "admin";
    const hasAiPerm = (prof?.permissions as Record<string, unknown>)?.show_ai === true;
    if (!isAdmin && !hasAiPerm) return reply({ error: "Forbidden" }, 403);

    const partes = [prof?.nombre ?? "", prof?.paterno ?? "", prof?.materno ?? ""]
      .filter((p: string) => p.length > 0);
    const userFullName = partes.length > 0 ? partes.join(" ") : (user.email ?? "Usuario");

    const { messages, link_id, titulo } = await req.json() as {
      messages?: Array<{ role: string; content: string }>;
      link_id?: unknown;
      titulo?: unknown;
    };

    if (!Array.isArray(messages) || messages.length === 0) {
      return reply({ error: "Falta el historial de mensajes." }, 400);
    }

    // Sin link_id el asistente entra en modo guiado: lista los reportes y pregunta cuál. Con
    // link_id queda fijo a ese reporte y no puede desviarse a otro dataset.
    const linkFijo = typeof link_id === "string" && link_id.length > 0 ? link_id : null;

    // El título es cosmético para el prompt; la autorización la hace pbi-query.
    const reportTitle = linkFijo === null
        ? null
        : (typeof titulo === "string" && titulo.length > 0 ? titulo : "el reporte abierto");

    const tools = linkFijo === null ? [TOOL_REPORTES, ...TOOLS] : TOOLS;

    const msgs: ChatMessage[] = [
      { role: "system", content: systemPrompt(userFullName, reportTitle) },
      ...messages.map((m) => ({ role: m.role, content: m.content })),
    ];

    let structured: unknown = null;

    for (let i = 0; i < MAX_ITERACIONES; i++) {
      const msg = await llamarModelo(msgs, tools);
      const calls = msg.tool_calls ?? [];

      if (calls.length === 0) {
        return reply({ text: (msg.content ?? "").trim(), structured });
      }

      msgs.push({ role: "assistant", content: msg.content ?? "", tool_calls: calls });

      for (const call of calls) {
        const nombre = call.function?.name ?? "";
        const args   = parseArgs(call.function?.arguments);
        const result = await ejecutarHerramienta(nombre, args, linkFijo, auth);
        const r      = result as Record<string, unknown>;

        if (nombre === "pbi_consultar" && Array.isArray(r.rows)) {
          // La presentación la pide el modelo porque él ve la intención del usuario. La
          // FORMA de la gráfica sigue decidiéndola el cliente: eso es correctitud, no gusto.
          const p = args.presentacion;
          structured = {
            type:      "pbi_rows",
            data:      r.rows,
            formatos:  r.formatos ?? null,
            truncated: r.truncated ?? false,
            consulta:  r.consulta ?? null,
            presentacion: p === "grafica" || p === "tabla" ? p : "auto",
            // Lo que el cliente necesita para poder guardar el resultado como panel: sobre
            // qué reporte y con qué periodo se consultó. En modo guiado el reporte lo eligió
            // el modelo, así que el cliente no lo sabría de otra forma.
            report:  r.report ?? null,
            periodo: (args.anio || args.mes)
              ? { anio: args.anio ?? null, mes: args.mes ?? null }
              : null,
            limite: typeof args.limite === "number" ? args.limite : null,
          };
        }

        // El formato de OpenAI exige tool_call_id para emparejar la respuesta con su llamada.
        msgs.push({
          role:         "tool",
          tool_call_id: call.id ?? nombre,
          content:      JSON.stringify(result),
        });
      }
    }

    return reply({
      error: `El asistente no llegó a una respuesta en ${MAX_ITERACIONES} pasos. ` +
             "Intenta con una pregunta más específica.",
    }, 500);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return reply({ error: msg }, 500);
  }
});
