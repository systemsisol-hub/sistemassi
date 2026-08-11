import { createClient } from "jsr:@supabase/supabase-js@2";

// ─── Puente entre WhatsApp y Soli ────────────────────────────────────────────
//
// Un colaborador escribe al número de la empresa y Soli le contesta con SUS datos. Esta función NO
// calcula nada: identifica a la persona por su teléfono y le pasa la conversación a `ai-assistant`,
// que ya tiene las herramientas y los permisos. El cálculo de vacaciones ya estaba escrito dos veces
// —en Dart y en TypeScript— y una tercera copia aquí habría sido la peor forma de resolver esto.
//
// ─── Lo que decide si alguien recibe respuesta ───────────────────────────────
//
// Cuatro puertas, en este orden. Ninguna se puede saltar:
//
//   1. La firma del webhook (HMAC-SHA256 con el secreto de la sesión).
//   2. El teléfono resuelve a UN colaborador vigente. Si empata con varios, no se contesta:
//      `0000000000` está capturado en 5 perfiles, y responder al primero sería entregarle a alguien
//      el saldo de vacaciones de otro.
//   3. El número está en la lista blanca y activo.
//   4. Esa persona tiene `show_ai` o es administrador — la puerta que Soli ya tenía.
//
// Un número que no pase alguna de las tres últimas **no recibe nada**: no se le confirma que del
// otro lado hay un sistema con datos de empleados. Queda en `whatsapp_bitacora`, que es lo único
// que permite explicar después por qué no hubo respuesta.

const SUPABASE_URL   = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY    = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const INTERNAL_SECRET = Deno.env.get("SOLI_INTERNAL_SECRET") ?? "";
const OPENWA_BASE    = Deno.env.get("OPENWA_BASE_URL") ?? "";
const OPENWA_KEY     = Deno.env.get("OPENWA_API_KEY") ?? "";
const OPENWA_SESSION = Deno.env.get("OPENWA_SESSION_ID") ?? "";
const WEBHOOK_SECRET = Deno.env.get("OPENWA_WEBHOOK_SECRET") ?? "";

/// Cuántos mensajes se atienden por número y por hora.
///
/// Cada mensaje es una llamada al modelo: cuesta y tarda. Sin tope, un teléfono en un bucle —o una
/// persona impaciente— gasta el presupuesto de todos.
const LIMITE_POR_HORA = Number(Deno.env.get("WHATSAPP_LIMITE_HORA") ?? "20");

/// Turnos que se conservan del hilo. El historial completo encarece cada llamada sin aportar.
const TURNOS_MEMORIA = 12;

type Resultado =
  | "ATENDIDO" | "NO_AUTORIZADO" | "SIN_REGISTRO" | "AMBIGUO"
  | "SIN_PERMISO" | "LIMITE" | "ERROR";

// ─── Utilidades ──────────────────────────────────────────────────────────────

/// Los 10 dígitos del número, o `null` si no se puede afirmar cuál es.
///
/// Misma regla que `lib/services/telefono_whatsapp.dart`, que es la que usa el panel al dar de alta.
/// Están escritas dos veces porque son dos lenguajes; las pruebas de Dart cubren los mismos casos y
/// cualquier cambio tiene que hacerse en los dos lados.
function normalizarTelefono(crudo: string | null | undefined): string | null {
  if (!crudo) return null;
  let d = String(crudo).split("@")[0].replace(/\D/g, "");
  if (!d) return null;
  if (d.length === 13 && d.startsWith("521")) d = d.slice(3);
  else if (d.length === 12 && d.startsWith("52")) d = d.slice(2);
  else if (d.length === 11 && d.startsWith("1")) d = d.slice(1);
  return d.length === 10 ? d : null;
}

function esGrupo(chatId: string | null | undefined): boolean {
  return String(chatId ?? "").includes("@g.us");
}

async function hmacSha256Hex(clave: string, cuerpo: string): Promise<string> {
  const k = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(clave),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const firma = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(cuerpo));
  return [...new Uint8Array(firma)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function igualesEnTiempoConstante(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let dif = 0;
  for (let i = 0; i < a.length; i++) dif |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return dif === 0;
}

/// Saca remitente y texto del evento.
///
/// El sobre del webhook se lee de varias formas posibles a propósito. La documentación muestra el
/// del WebSocket —`{payload:{data:{from,body}}}`— y el de la entrega HTTP puede no ser idéntico;
/// aceptar las tres formas es más robusto que acertar la exacta, y `detalle` guarda las claves que
/// llegaron para poder confirmarlo con el primer mensaje real en lugar de adivinar.
function extraerMensaje(cuerpo: Record<string, unknown>): {
  chatId: string | null; texto: string | null; deMi: boolean; grupo: boolean; claves: string;
} {
  const p = (cuerpo.payload ?? cuerpo) as Record<string, unknown>;
  const d = (p.data ?? p) as Record<string, unknown>;
  const chatId = (d.from ?? d.sender ?? d.chatId ?? d.author ?? null) as string | null;
  const texto = (d.body ?? d.text ?? d.message ?? null) as string | null;
  return {
    chatId,
    texto: typeof texto === "string" ? texto : null,
    deMi: d.fromMe === true,
    grupo: d.isGroup === true || esGrupo(chatId),
    claves: Object.keys(d).join(","),
  };
}

// ─── La función ──────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const svc = createClient(SUPABASE_URL, SERVICE_KEY);
  const crudo = await req.text();

  // ── Puerta 1: la firma ─────────────────────────────────────────────────────
  //
  // Se verifica ANTES de mirar el contenido. Sin esto, cualquiera que conociera la URL de la función
  // podría mandar un mensaje diciendo que viene del teléfono de otra persona.
  if (WEBHOOK_SECRET.length === 0) {
    // Un secreto sin configurar cierra la puerta, no la abre.
    return new Response(JSON.stringify({ error: "sin secreto de webhook" }), { status: 503 });
  }
  const recibida = (req.headers.get("X-OpenWA-Signature") ?? "").replace(/^sha256=/i, "");
  const esperada = await hmacSha256Hex(WEBHOOK_SECRET, crudo);
  if (!igualesEnTiempoConstante(recibida.toLowerCase(), esperada)) {
    return new Response(JSON.stringify({ error: "firma inválida" }), { status: 401 });
  }

  let cuerpo: Record<string, unknown>;
  try {
    cuerpo = JSON.parse(crudo) as Record<string, unknown>;
  } catch {
    return new Response(JSON.stringify({ error: "cuerpo ilegible" }), { status: 400 });
  }

  const m = extraerMensaje(cuerpo);

  // Se responde 200 a todo lo que no sea una pregunta atendible, para que OpenWA no reintente algo
  // que nunca va a cambiar: los reintentos son para caídas, no para mensajes que se ignoran.
  if (m.deMi || m.grupo || !m.texto || !m.texto.trim()) {
    return new Response(JSON.stringify({ ok: true, ignorado: true }), { status: 200 });
  }

  const telefono = normalizarTelefono(m.chatId);
  if (!telefono) {
    await registrar(svc, String(m.chatId ?? "?").slice(0, 32), null, "SIN_REGISTRO",
      m.texto, null, `no se pudo normalizar; claves del evento: ${m.claves}`);
    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  }

  try {
    // ── Puerta 2: el teléfono resuelve a UNA persona ─────────────────────────
    const { data: res } = await svc.rpc("whatsapp_resolver_telefono", { p_telefono: telefono });
    const fila = Array.isArray(res) ? res[0] : res;
    const profileId = (fila?.profile_id ?? null) as string | null;
    const coincidencias = Number(fila?.coincidencias ?? 0);

    if (coincidencias === 0) {
      await registrar(svc, telefono, null, "SIN_REGISTRO", m.texto, null,
        "el teléfono no está capturado en ningún colaborador vigente");
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }
    if (!profileId) {
      await registrar(svc, telefono, null, "AMBIGUO", m.texto, null,
        `el teléfono está en ${coincidencias} perfiles vigentes; no se puede saber a quién contestar`);
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }

    // ── Puerta 3: la lista blanca ────────────────────────────────────────────
    const { data: aut } = await svc
      .from("whatsapp_autorizados")
      .select("activo").eq("telefono", telefono).maybeSingle();
    if (!aut || aut.activo !== true) {
      await registrar(svc, telefono, profileId, "NO_AUTORIZADO", m.texto, null,
        aut ? "el número está en la lista pero apagado" : "el número no está en la lista");
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }

    // ── Límite por hora ──────────────────────────────────────────────────────
    const desde = new Date(Date.now() - 3600_000).toISOString();
    const { count } = await svc
      .from("whatsapp_bitacora")
      .select("id", { count: "exact", head: true })
      .eq("telefono", telefono).eq("resultado", "ATENDIDO").gte("creado_en", desde);
    if ((count ?? 0) >= LIMITE_POR_HORA) {
      await registrar(svc, telefono, profileId, "LIMITE", m.texto, null,
        `${count} mensajes atendidos en la última hora`);
      // Aquí SÍ se avisa: es alguien autorizado, y el silencio parecería una avería.
      await enviar(telefono, "Has hecho muchas consultas seguidas. Espera un momento y vuelve a intentarlo.");
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }

    // ── El hilo ──────────────────────────────────────────────────────────────
    const { data: conv } = await svc
      .from("whatsapp_conversaciones")
      .select("mensajes").eq("telefono", telefono).maybeSingle();
    const previos = Array.isArray(conv?.mensajes) ? conv!.mensajes as Array<{ role: string; content: string }> : [];
    const mensajes = [...previos.slice(-TURNOS_MEMORIA), { role: "user", content: m.texto }];

    // ── Puerta 4 y la respuesta: la pone Soli ────────────────────────────────
    //
    // `actuar_como` sólo se acepta con el secreto interno, y `ai-assistant` aplica ahí el mismo 403
    // de `show_ai` que aplica a la aplicación. Por eso SIN_PERMISO se detecta por su respuesta y no
    // se reimplementa aquí.
    const r = await fetch(`${SUPABASE_URL}/functions/v1/ai-assistant`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Interno": INTERNAL_SECRET,
      },
      body: JSON.stringify({ messages: mensajes, actuar_como: profileId }),
    });

    if (r.status === 403) {
      await registrar(svc, telefono, profileId, "SIN_PERMISO", m.texto, null,
        "la persona no tiene el permiso de Asistente IA");
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }
    if (!r.ok) {
      const detalle = (await r.text()).slice(0, 300);
      await registrar(svc, telefono, profileId, "ERROR", m.texto, null,
        `ai-assistant respondió ${r.status}: ${detalle}`);
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }

    // `text` es la clave real: `ai-assistant` responde `{ text, structured }`. Se comprobo leyendo
    // su codigo, no suponiendo; mi primera version buscaba `reply`/`message` y no habria encontrado
    // nada nunca. `structured` se ignora a proposito: son datos para pintar tarjetas en la
    // aplicacion, y por WhatsApp solo cabe texto.
    const datos = await r.json() as { text?: string; structured?: unknown };
    const respuesta = (datos.text ?? "").trim();
    if (!respuesta) {
      await registrar(svc, telefono, profileId, "ERROR", m.texto, null,
        `Soli respondio sin texto; claves recibidas: ${Object.keys(datos).join(",")}`);
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }

    await enviar(telefono, respuesta);

    // El hilo se guarda DESPUÉS de enviar: si el envío falla, la pregunta no queda en la memoria
    // como si se hubiera contestado.
    await svc.from("whatsapp_conversaciones").upsert({
      telefono,
      mensajes: [...mensajes, { role: "assistant", content: respuesta }].slice(-TURNOS_MEMORIA * 2),
      actualizado_en: new Date().toISOString(),
    }, { onConflict: "telefono" });

    await registrar(svc, telefono, profileId, "ATENDIDO", m.texto, respuesta, null);
    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await registrar(svc, telefono, null, "ERROR", m.texto, null, msg.slice(0, 300));
    // 200 igual: un 500 haría que OpenWA reintentara, y si el fallo es nuestro el reintento sólo
    // multiplica el problema. El renglón de la bitácora es lo que hay que mirar.
    return new Response(JSON.stringify({ ok: false }), { status: 200 });
  }
});

/// Manda el texto por WhatsApp.
async function enviar(telefono: string, texto: string): Promise<void> {
  if (!OPENWA_BASE || !OPENWA_KEY || !OPENWA_SESSION) {
    throw new Error("falta configurar OPENWA_BASE_URL, OPENWA_API_KEY u OPENWA_SESSION_ID");
  }
  const r = await fetch(
    `${OPENWA_BASE}/api/sessions/${OPENWA_SESSION}/messages/send-text`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-API-Key": OPENWA_KEY },
      // `52` sin el `1`: es la forma que WhatsApp acepta hoy para México.
      body: JSON.stringify({ chatId: `52${telefono}@c.us`, text: texto }),
    });
  if (!r.ok) {
    throw new Error(`send-text respondió ${r.status}: ${(await r.text()).slice(0, 200)}`);
  }
}

/// Deja constancia. Nunca lanza: un fallo al registrar no debe tumbar la respuesta a la persona.
async function registrar(
  svc: ReturnType<typeof createClient>,
  telefono: string,
  profileId: string | null,
  resultado: Resultado,
  pregunta: string | null,
  respuesta: string | null,
  detalle: string | null,
): Promise<void> {
  try {
    await svc.from("whatsapp_bitacora").insert({
      telefono, profile_id: profileId, resultado,
      pregunta: pregunta?.slice(0, 500) ?? null,
      respuesta: respuesta?.slice(0, 2000) ?? null,
      detalle,
    });
  } catch (e) {
    console.error("whatsapp: no se pudo registrar en la bitácora:", e);
  }
}
