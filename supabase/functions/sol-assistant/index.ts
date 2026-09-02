import { createClient } from "jsr:@supabase/supabase-js@2";

import {
  CORS, hoy, OLLAMA_BASE, OLLAMA_KEY, SERVICE_KEY, SOL_MODEL, SOL_MODEL_RESPALDO, SUPABASE_URL,
} from "./config.ts";
import { ALL_TOOLS, AMBITO, construirPrompt, QUE_HACE } from "./herramientas.ts";
import { runTool } from "./ejecutar.ts";

// ─── SOL, el asistente comercial ─────────────────────────────────────────────
//
// Aparte de Soli a proposito: otro modelo, otro prompt, otras herramientas y otra pantalla. Comparte
// con ella la CUENTA de Ollama —misma llave, decision del 02/09/2026— y una sola cosa mas: quien es
// quien. `profiles` y los permisos siguen siendo la unica definicion, porque duplicarlos seria tener
// dos verdades sobre la misma persona.
//
// Lo que NO tiene, y es deliberado:
//
//   - No hay puente de WhatsApp. SOL vive dentro de la aplicacion. Si algun dia lo necesita, hara
//     falta un segundo numero: un solo numero no puede repartir entre dos asistentes sin que algo
//     adivine a cual va cada mensaje.
//   - No hay via servidor-a-servidor. Sin WhatsApp no hace falta, y un secreto que no se usa es un
//     secreto que se filtra sin que nadie lo note.
//   - No se puede configurar desde la aplicacion. Todo esta en variables de entorno y la pantalla
//     solo lo MUESTRA.

interface Mensaje { role: string; content: string }

interface Cuerpo {
  messages?: Mensaje[];
  /// Pide la configuracion en lugar de una conversacion.
  configuracion?: boolean;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { ...CORS, "Content-Type": "application/json" } });
  }

  const responde = (cuerpo: Record<string, unknown>, status = 200) =>
    new Response(JSON.stringify(cuerpo),
      { status, headers: { ...CORS, "Content-Type": "application/json" } });

  const svc = createClient(SUPABASE_URL, SERVICE_KEY);

  // ── Quien pregunta ─────────────────────────────────────────────────────────
  //
  // Siempre con sesion: SOL no tiene via interna. Sin `Authorization` no se atiende.
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth) return responde({ error: "Falta la sesion." }, 401);

  const { data: { user } } = await svc.auth.getUser(auth.replace("Bearer ", ""));
  if (!user) return responde({ error: "Sesion invalida." }, 401);

  const { data: prof } = await svc.from("profiles")
    .select("nombre,paterno,role,permissions").eq("id", user.id).maybeSingle();

  const esAdmin = prof?.role === "admin";
  const permisos = (prof?.permissions ?? {}) as Record<string, unknown>;

  // El MISMO permiso que abre la pagina. Si aqui se aceptara a cualquiera con sesion, la pagina
  // seria una sugerencia y no un control.
  if (!esAdmin && permisos.show_sol !== true) {
    return responde({ error: "No tienes acceso a SOL." }, 403);
  }

  let cuerpo: Cuerpo;
  try {
    cuerpo = await req.json() as Cuerpo;
  } catch {
    return responde({ error: "Cuerpo ilegible." }, 400);
  }

  // ── La configuracion, para la pestaña que la muestra ───────────────────────
  //
  // La pantalla pregunta AQUI en lugar de tener una copia en Dart, por lo mismo que en Soli: la
  // unica fuente es el codigo que de verdad corre. Una copia en la aplicacion se queda vieja en
  // cuanto alguien toque esta funcion, y entonces la pantalla miente.
  if (cuerpo.configuracion === true) {
    if (!esAdmin) return responde({ error: "Solo para administradores." }, 403);
    return responde({
      modelo: SOL_MODEL,
      modelo_respaldo: SOL_MODEL_RESPALDO,
      proveedor: OLLAMA_BASE,
      // Se dice si la cuenta esta puesta, NUNCA la llave. Que este configurada es informacion de
      // diagnostico; su valor es un secreto.
      cuenta_configurada: OLLAMA_KEY.length > 0,
      cuenta_compartida_con: "Soli (misma cuenta de Ollama, modelo distinto)",
      editable_desde_la_app: false,
      herramientas: ALL_TOOLS.map((t) => ({
        nombre: t.function.name,
        que_hace: QUE_HACE[t.function.name] ?? "",
      })),
      ambito: AMBITO,
    });
  }

  // ── Sin modelo configurado no se llama a nadie ─────────────────────────────
  //
  // Se dice claro en lugar de intentarlo y devolver el error del proveedor: «modelo no encontrado»
  // manda a diagnosticar la cuenta cuando lo que falta es una variable.
  if (SOL_MODEL.length === 0) {
    return responde({
      text: "SOL todavia no tiene modelo configurado. Se pone en la variable SOL_MODEL de "
        + "Supabase; la pestaña de Configuracion muestra lo que hay puesto ahora.",
      sin_configurar: true,
    });
  }
  if (OLLAMA_KEY.length === 0) {
    return responde({
      text: "Falta la llave del proveedor de IA (OLLAMA_API_KEY). SOL no puede responder sin ella.",
      sin_configurar: true,
    });
  }

  const mensajes = Array.isArray(cuerpo.messages) ? cuerpo.messages : [];
  if (mensajes.length === 0) return responde({ error: "Sin mensajes." }, 400);

  const nombrePila = (prof?.nombre ?? "").toString().split(/\s+/)[0] || "asesor";

  const conversacion: Mensaje[] = [
    { role: "system", content: construirPrompt(nombrePila, hoy) },
    ...mensajes.map((m) => ({ role: m.role, content: m.content })),
  ];

  // Cuantas llamadas al modelo se permiten por pregunta. Dos vueltas alcanzan para «consulta y
  // redacta»; sin tope, una herramienta que devuelve vacio puede dejarlo en bucle.
  const MAX_VUELTAS = 4;
  let modeloEnUso = SOL_MODEL;
  let usoTotal = { prompt: 0, respuesta: 0 };

  for (let vuelta = 0; vuelta < MAX_VUELTAS; vuelta++) {
    let r: Response;
    try {
      r = await fetch(`${OLLAMA_BASE}/chat`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${OLLAMA_KEY}`,
        },
        body: JSON.stringify({
          model: modeloEnUso,
          messages: conversacion,
          tools: ALL_TOOLS,
          stream: false,
        }),
      });
    } catch (e) {
      return responde({ error: `No se pudo hablar con el proveedor: ${e}` }, 502);
    }

    if (!r.ok) {
      const detalle = (await r.text()).slice(0, 300);
      console.error(`SOL: ${modeloEnUso} respondio ${r.status}: ${detalle}`);
      // Un 400 es NUESTRO —herramientas mal formadas— y cambiar de modelo no lo arregla.
      if (r.status !== 400 && SOL_MODEL_RESPALDO && modeloEnUso !== SOL_MODEL_RESPALDO) {
        console.log(`SOL: se cambia al respaldo ${SOL_MODEL_RESPALDO}`);
        modeloEnUso = SOL_MODEL_RESPALDO;
        continue;
      }
      return responde({ error: `El proveedor respondio ${r.status}.` }, 502);
    }

    const datos = await r.json() as {
      message?: { content?: string; tool_calls?: Array<{ function: { name: string; arguments: unknown } }> };
      prompt_eval_count?: number;
      eval_count?: number;
    };
    usoTotal.prompt += datos.prompt_eval_count ?? 0;
    usoTotal.respuesta += datos.eval_count ?? 0;

    const msg = datos.message;
    const llamadas = msg?.tool_calls ?? [];

    if (llamadas.length === 0) {
      const texto = (msg?.content ?? "").trim();
      await bitacora(svc, user.id, modeloEnUso, usoTotal, mensajes.at(-1)?.content ?? "", texto);
      return responde({
        text: texto || "No pude armar una respuesta. Vuelve a preguntarme de otra forma.",
        modelo: modeloEnUso,
      });
    }

    conversacion.push({ role: "assistant", content: msg?.content ?? "" });
    for (const c of llamadas) {
      const args = typeof c.function.arguments === "string"
        ? JSON.parse(c.function.arguments || "{}")
        : (c.function.arguments ?? {});
      const resultado = await runTool(c.function.name, args as Record<string, unknown>, svc);
      console.log(`SOL: ${c.function.name} -> ${JSON.stringify(resultado).slice(0, 160)}`);
      conversacion.push({ role: "tool", content: JSON.stringify(resultado) });
    }
  }

  return responde({
    text: "Me quede dando vueltas sin llegar a una respuesta. Preguntame algo mas concreto: el "
      + "nombre del desarrollo, o «que promociones hay».",
  });
});

/// Deja constancia de cada consulta, con el modelo y los tokens.
///
/// ─── Por que existe ─────────────────────────────────────────────────────────
///
/// SOL y Soli comparten la cuenta de Ollama, asi que la FACTURA es una sola y no se puede separar
/// por facturacion. Contando aqui las llamadas y los tokens de SOL, el gasto se puede atribuir de
/// todos modos: es la unica forma de saber cuanto cuesta cada asistente sin abrir dos cuentas.
///
/// Nunca lanza: un fallo al registrar no debe tumbar la respuesta a la persona.
async function bitacora(
  svc: ReturnType<typeof createClient>,
  usuario: string,
  modelo: string,
  uso: { prompt: number; respuesta: number },
  pregunta: string,
  respuesta: string,
): Promise<void> {
  try {
    await svc.from("sol_bitacora").insert({
      profile_id: usuario,
      modelo,
      tokens_prompt: uso.prompt,
      tokens_respuesta: uso.respuesta,
      pregunta: pregunta.slice(0, 500),
      respuesta: respuesta.slice(0, 2000),
    });
  } catch (e) {
    console.error("SOL: no se pudo registrar en la bitacora:", e);
  }
}
