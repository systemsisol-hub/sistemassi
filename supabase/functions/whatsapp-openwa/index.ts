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

/// Arma el texto de una respuesta de vacaciones con los datos de la herramienta.
///
/// Devuelve `null` si los datos no tienen la forma esperada, para caer al texto del modelo.
///
/// ─── Por que existe ──────────────────────────────────────────────────────────
///
/// La aplicacion nunca confio en la prosa del modelo para esto: pinta una tarjeta con los datos
/// crudos de `calcular_vacaciones` -ver `_VacationCard` en ai_page.dart, que lee `colaborador`,
/// `numero_empleado`, `total_disponible` y `periodos`-. El puente, en cambio, mandaba solo la prosa
/// y tiraba los datos, con un comentario mio que decia que por WhatsApp "solo cabe texto". Cierto,
/// pero la conclusion estaba mal: que solo quepa texto es una restriccion de FORMATO, no una razon
/// para tirar las cifras buenas.
///
/// El precio de esa decision, medido sobre cuatro consultas reales: 4 de 4 con cifras equivocadas,
/// una de ellas con numero de empleado y fecha de vencimiento inventados. Ninguna habria pasado con
/// esto puesto, porque aqui el modelo no escribe ni un numero.
function textoDeVacaciones(structured: unknown): string | null {
  const s = structured as { type?: string; data?: Record<string, unknown> } | null;
  if (!s || s.type !== "vacaciones" || !s.data) return null;

  const d = s.data;
  const quien = typeof d.colaborador === "string" ? d.colaborador : null;
  const total = typeof d.total_disponible === "number" ? d.total_disponible : null;
  const periodos = Array.isArray(d.periodos)
    ? d.periodos as Array<Record<string, unknown>>
    : null;
  if (!quien || total === null || !periodos) return null;

  const numero = typeof d.numero_empleado === "string" ? d.numero_empleado : null;
  const lineas = [
    `*${quien}*${numero ? ` — empleado ${numero}` : ""}`,
    `Dias disponibles: *${total}*`,
  ];

  const conSaldo = periodos.filter((pe) => (pe.dias_disponibles as number) > 0);
  if (conSaldo.length > 0) {
    lineas.push("", "Por periodo:");
    for (const pe of conSaldo) {
      lineas.push(`• ${pe.periodo}: ${pe.dias_disponibles} de ${pe.dias_proporcionales}`);
    }
  }
  // Los periodos agotados se cuentan pero no se listan: por WhatsApp una lista de trece renglones
  // en ceros esconde lo que si importa.
  const agotados = periodos.length - conSaldo.length;
  if (agotados > 0) {
    lineas.push("", `(${agotados} periodo${agotados === 1 ? "" : "s"} anterior${agotados === 1 ? "" : "es"} ya consumido${agotados === 1 ? "" : "s"})`);
  }
  return lineas.join("\n");
}

/// Saca remitente y texto del evento.
///
/// El sobre del webhook se lee de varias formas posibles a propósito. La documentación muestra el
/// del WebSocket —`{payload:{data:{from,body}}}`— y el de la entrega HTTP puede no ser idéntico;
/// aceptar las tres formas es más robusto que acertar la exacta, y `detalle` guarda las claves que
/// llegaron para poder confirmarlo con el primer mensaje real en lugar de adivinar.
function extraerMensaje(cuerpo: Record<string, unknown>): {
  id: string | null; chatId: string | null; telefono: string | null; texto: string | null;
  deMi: boolean; grupo: boolean; candidatos: string;
} {
  const p = (cuerpo.payload ?? cuerpo) as Record<string, unknown>;
  const d = (p.data ?? p) as Record<string, unknown>;

  // No se toma el primer campo que exista: se prueban TODOS y gana el primero del que sale un
  // telefono de diez digitos.
  //
  // Hace falta porque WhatsApp ya no siempre manda el numero. El primer mensaje real llego con
  // `from: "135231491317781@lid"` —el direccionamiento nuevo, un identificador opaco que sustituye
  // al telefono— mientras el mismo evento traia tambien `chatId`. Quedarse con `from` a secas dejaba
  // sin identificar a alguien que si era identificable por otro campo.
  const nombres = ["from", "chatId", "author", "participant", "sender", "senderId"];
  const vistos: string[] = [];
  let telefono: string | null = null;
  let deQuien: string | null = null;

  for (const n of nombres) {
    const v = d[n];
    if (typeof v !== "string" || v.length === 0) continue;
    vistos.push(`${n}=${v}`);
    const t = normalizarTelefono(v);
    if (t && !telefono) { telefono = t; deQuien = n; }
  }
  if (deQuien) vistos.push(`(sirvio ${deQuien})`);

  // Para responder se usa `chatId` si viene, y si no el `from`: es la direccion tal como la maneja
  // WhatsApp, valida aunque sea un @lid.
  const paraResponder = (d.chatId ?? d.from ?? null) as string | null;
  const texto = (d.body ?? d.text ?? d.message ?? null) as string | null;

  return {
    id: typeof d.id === "string" ? d.id : null,
    chatId: paraResponder,
    telefono,
    texto: typeof texto === "string" ? texto : null,
    deMi: d.fromMe === true,
    grupo: d.isGroup === true || esGrupo(paraResponder),
    candidatos: vistos.join(" | "),
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
  // Dos formas de acreditarse, y basta con una:
  //
  //   a) La firma HMAC del cuerpo, que es la buena: ata la credencial AL CONTENIDO, asi que ni
  //      siquiera sirve reenviar una peticion valida con el cuerpo cambiado.
  //   b) El mismo secreto en la cadena de consulta: `?k=<secreto>`.
  //
  // La (b) existe porque el panel de OpenWA NO expone el campo `secret` del webhook —comprobado en
  // los formularios de alta y de edicion— y sin llave de API no se puede registrar por API. La URL
  // si es editable, asi que es la unica via que queda con las herramientas disponibles.
  //
  // Es mas debil que la firma y conviene saber por que: no va atada al cuerpo, y una URL con secreto
  // acaba en los registros de quien la llama. Aqui eso es el propio servidor de OpenWA, y el trafico
  // va por TLS, asi que el riesgo real es acotado. En cuanto haya una llave de API conviene
  // registrar el `secret` de verdad y quitar el `?k=`.
  const cabeceraFirma = req.headers.get("X-OpenWA-Signature");
  const claveUrl = new URL(req.url).searchParams.get("k") ?? "";
  const porUrl = claveUrl.length > 0 && igualesEnTiempoConstante(claveUrl, WEBHOOK_SECRET);

  const recibida = (cabeceraFirma ?? "").replace(/^sha256=/i, "");
  const esperada = await hmacSha256Hex(WEBHOOK_SECRET, crudo);
  if (!porUrl && !igualesEnTiempoConstante(recibida.toLowerCase(), esperada)) {
    // Se distinguen los dos casos, porque se arreglan de formas distintas y el rechazo NO deja
    // rastro en la bitacora: sin telefono no hay a quien atribuirle el renglon, y registrar todo lo
    // que llame a la funcion la convertiria en un buzon de basura para cualquiera.
    //
    // Sin cabecera  -> al webhook de OpenWA le falta el campo `secret`.
    // Con cabecera  -> el secreto de los dos lados no es el mismo.
    console.log(cabeceraFirma
      ? "firma invalida: llego X-OpenWA-Signature pero no coincide. El `secret` del webhook en " +
        "OpenWA y OPENWA_WEBHOOK_SECRET no son iguales."
      : "sin credencial: ni cabecera X-OpenWA-Signature ni ?k= valido. Al webhook de OpenWA le " +
        "falta el `secret`, o la URL no lleva el ?k= correcto.");
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

  // ── Se responde YA, y el trabajo va en segundo plano ──────────────────────
  //
  // Aqui estuvo el fallo que se vio en la primera prueba real: una pregunta llego TRES veces en 32
  // segundos y otra DOS en 11. No eran webhooks duplicados —esos entregan en el mismo segundo— eran
  // REINTENTOS: la funcion contestaba de forma sincrona y una consulta con herramienta se lleva unos
  // 7 segundos, mas de lo que OpenWA espera. Cada reintento repetia todo el trabajo y mandaba otra
  // respuesta al telefono.
  //
  // `EdgeRuntime.waitUntil` mantiene vivo el proceso hasta que la promesa termina, aunque la
  // respuesta HTTP ya se haya ido. Es la forma correcta de atender un webhook lento.
  const trabajo = atender(svc, m);
  try {
    (globalThis as { EdgeRuntime?: { waitUntil(p: Promise<unknown>): void } })
      .EdgeRuntime?.waitUntil(trabajo);
  } catch {
    // Sin waitUntil disponible se espera: mejor tardar que cortar el trabajo a medias.
    await trabajo;
  }
  return new Response(JSON.stringify({ ok: true, recibido: true }), { status: 200 });
});

/// Todo lo que tarda: identificar, preguntarle a Soli y contestar.
async function atender(
  svc: ReturnType<typeof createClient>,
  m: ReturnType<typeof extraerMensaje>,
): Promise<void> {
  // Segunda linea de defensa contra reintentos: si este mensaje ya se atendio, no se contesta otra
  // vez. Con la respuesta inmediata de arriba no deberia hacer falta, pero un corte de red entre
  // OpenWA y la funcion volveria a entregarlo.
  if (m.id) {
    const { data: ya } = await svc
      .from("whatsapp_bitacora")
      .select("id").eq("mensaje_id", m.id).maybeSingle();
    if (ya) {
      console.log(`mensaje ${m.id} ya atendido; se ignora el reenvio`);
      return;
    }
  }

  // Si ningun campo del evento traia un telefono, se le pregunta a OpenWA por el identificador del
  // remitente. Es el caso normal con @lid, no la excepcion.
  let telefono = m.telefono;

  let resueltoPorOpenwa = false;
  if (!telefono && m.chatId) {
    telefono = await telefonoDeContacto(m.chatId);
    resueltoPorOpenwa = telefono !== null;
  }

  if (!telefono) {
    // Se guardan los VALORES de los candidatos, no solo los nombres: es la unica forma de saber si
    // el numero venia en otro campo o si de plano no viene, que se arregla de maneras distintas.
    await registrar(svc, String(m.chatId ?? "?").slice(0, 40), null, "SIN_REGISTRO",
      m.texto, null, `ni los campos del evento ni contacts/phone dieron un telefono de 10 digitos. ${m.candidatos}`);
    return;
  }

  // Para contestar se usa el `chatId` TAL COMO LLEGO, no uno reconstruido.
  //
  // El numero propio de la sesion aparece en el panel como `5215580180569`: con el `1` que WhatsApp
  // arrastra para Mexico. Yo construia `52` + diez digitos, sin ese `1`, y no hay forma de saber
  // desde aqui cual de las dos formas acepta `send-text`. Devolver la que vino elimina la duda: si
  // WhatsApp la uso para hablarnos, es valida para responder. El telefono normalizado se sigue
  // usando para identificar a la persona, que es otra cosa.
  const destino = String(m.chatId);

  try {
    // ── Puerta 2: el teléfono resuelve a UNA persona ─────────────────────────
    const { data: res } = await svc.rpc("whatsapp_resolver_telefono", { p_telefono: telefono });
    const fila = Array.isArray(res) ? res[0] : res;
    const profileId = (fila?.profile_id ?? null) as string | null;
    const coincidencias = Number(fila?.coincidencias ?? 0);

    if (coincidencias === 0) {
      await registrar(svc, telefono, null, "SIN_REGISTRO", m.texto, null,
        "el teléfono no está capturado en ningún colaborador vigente");
      return;
    }
    if (!profileId) {
      await registrar(svc, telefono, null, "AMBIGUO", m.texto, null,
        `el teléfono está en ${coincidencias} perfiles vigentes; no se puede saber a quién contestar`);
      return;
    }

    // ── Puerta 3: la lista blanca ────────────────────────────────────────────
    const { data: aut } = await svc
      .from("whatsapp_autorizados")
      .select("activo").eq("telefono", telefono).maybeSingle();
    if (!aut || aut.activo !== true) {
      await registrar(svc, telefono, profileId, "NO_AUTORIZADO", m.texto, null,
        aut ? "el número está en la lista pero apagado" : "el número no está en la lista");
      return;
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
      await enviar(destino, "Has hecho muchas consultas seguidas. Espera un momento y vuelve a intentarlo.");
      return;
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
      return;
    }
    if (!r.ok) {
      const detalle = (await r.text()).slice(0, 300);
      await registrar(svc, telefono, profileId, "ERROR", m.texto, null,
        `ai-assistant respondió ${r.status}: ${detalle}`);
      return;
    }

    // `text` es la clave real: `ai-assistant` responde `{ text, structured }`. Se comprobo leyendo
    // su codigo, no suponiendo; mi primera version buscaba `reply`/`message` y no habria encontrado
    // nada nunca.
    const datos = await r.json() as { text?: string; structured?: unknown };

    // Para vacaciones manda el dato, no la narracion.
    //
    // Se sustituye la prosa por completo en lugar de anadirla: si el modelo dijo "0 dias" y el dato
    // dice 102, dos cifras contradictorias en el mismo mensaje son peores que una sola correcta.
    const deVacaciones = textoDeVacaciones(datos.structured);
    const respuesta = (deVacaciones ?? datos.text ?? "").trim();
    if (!respuesta) {
      await registrar(svc, telefono, profileId, "ERROR", m.texto, null,
        `Soli respondio sin texto; claves recibidas: ${Object.keys(datos).join(",")}`);
      return;
    }

    await enviar(destino, respuesta);

    // El hilo se guarda DESPUÉS de enviar: si el envío falla, la pregunta no queda en la memoria
    // como si se hubiera contestado.
    await svc.from("whatsapp_conversaciones").upsert({
      telefono,
      mensajes: [...mensajes, { role: "assistant", content: respuesta }].slice(-TURNOS_MEMORIA * 2),
      actualizado_en: new Date().toISOString(),
    }, { onConflict: "telefono" });

    // El id va SIEMPRE en el ATENDIDO: es lo que hace que un reenvio no vuelva a contestar.
    await registrar(svc, telefono, profileId, "ATENDIDO", m.texto, respuesta,
      resueltoPorOpenwa ? `telefono resuelto por OpenWA desde ${m.chatId}` : null, m.id);
    return;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await registrar(svc, telefono, null, "ERROR", m.texto, null, msg.slice(0, 300));
    // 200 igual: un 500 haría que OpenWA reintentara, y si el fallo es nuestro el reintento sólo
    // multiplica el problema. El renglón de la bitácora es lo que hay que mirar.
    return;
  }
}

/// Le pregunta a OpenWA a qué teléfono corresponde un identificador de contacto.
///
/// Hace falta porque WhatsApp ya no siempre manda el número: el primer mensaje real llegó con
/// `from: "135231491317781@lid"`, el direccionamiento nuevo que sustituye el teléfono por un
/// identificador opaco. Sin esto, la lista blanca tendría que llevar @lid dados de alta a mano, sin
/// forma de saber a quién pertenecen; con esto se sigue usando el celular que ya está en el perfil.
///
/// La propia API lo llama «best-effort» y `phone` puede venir en null, así que quien llame tiene que
/// contemplar que no se resuelva. Devuelve null en vez de lanzar: un fallo aquí es «no se pudo
/// identificar», no una avería.
async function telefonoDeContacto(contactId: string): Promise<string | null> {
  if (!OPENWA_BASE || !OPENWA_KEY || !OPENWA_SESSION) return null;
  try {
    const r = await fetch(
      `${OPENWA_BASE}/api/sessions/${OPENWA_SESSION}/contacts/${encodeURIComponent(contactId)}/phone`,
      { headers: { "X-API-Key": OPENWA_KEY } });
    if (!r.ok) {
      console.log(`contacts/phone respondio ${r.status} para ${contactId}`);
      return null;
    }
    const d = await r.json() as { phone?: string | null };
    return normalizarTelefono(d.phone ?? null);
  } catch (e) {
    console.log("contacts/phone fallo:", e instanceof Error ? e.message : String(e));
    return null;
  }
}

/// Manda el texto por WhatsApp, al mismo chatId desde el que escribieron.
async function enviar(chatId: string, texto: string): Promise<void> {
  if (!OPENWA_BASE || !OPENWA_KEY || !OPENWA_SESSION) {
    throw new Error("falta configurar OPENWA_BASE_URL, OPENWA_API_KEY u OPENWA_SESSION_ID");
  }
  const r = await fetch(
    `${OPENWA_BASE}/api/sessions/${OPENWA_SESSION}/messages/send-text`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-API-Key": OPENWA_KEY },
      body: JSON.stringify({ chatId, text: texto }),
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
  mensajeId: string | null = null,
): Promise<void> {
  try {
    await svc.from("whatsapp_bitacora").insert({
      telefono, profile_id: profileId, resultado, mensaje_id: mensajeId,
      pregunta: pregunta?.slice(0, 500) ?? null,
      respuesta: respuesta?.slice(0, 2000) ?? null,
      detalle,
    });
  } catch (e) {
    console.error("whatsapp: no se pudo registrar en la bitácora:", e);
  }
}
