// Invitaciones del calendario por correo, para que los invitados agreguen el evento a su Outlook,
// Gmail o iPhone (07/10/2026).
//
// ─── Cómo está armado ────────────────────────────────────────────────────────
//
// La app la llama después de guardar un evento (`accion: "enviar"`) y antes de borrarlo
// (`accion: "cancelar"`). Solo quien creó el evento puede mandar sus invitaciones.
//
// Cada correo lleva un .ics con METHOD:REQUEST (o CANCEL). El ORGANIZADOR es quien creó el evento:
// cuando alguien acepta o rechaza desde su calendario, la respuesta le llega a su correo. El correo
// sale de la cuenta configurada en los secretos CALENDARIO_SMTP_* (hoy la de soporte), como
// «Calendario SI SOL».
//
// `calendario_envios` guarda a quién se le mandó cada invitación. Con eso: a quien se quita de un
// evento le llega la cancelación, al que ya la tenía le llega como actualización, y se cuenta el
// límite por hora. Los calendarios solo aplican un cambio si sube SEQUENCE: va en `events.ical_seq`.
//
// Un evento que se repite se manda UNA vez, como serie (RRULE), no un correo por fecha. Cambiar una
// sola fecha de la serie manda solo esa fecha (RECURRENCE-ID).

import { createClient } from "jsr:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";
import { construirIcs, esCorreo, type Persona, rruleDe } from "./ics.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
// Cuenta propia del calendario, aparte de la de Correspondencia («Comunicación SI SOL» es para
// avisos importantes; pedido del usuario el 07/10/2026). Hoy es la de soporte, la misma con la que
// Supabase Auth manda «recuperar contraseña»; Supabase no deja leer esa contraseña, así que los
// datos se pegan aquí como secretos. Cambiar de cuenta es cambiar estos secretos, sin desplegar.
const SMTP_HOST = (Deno.env.get("CALENDARIO_SMTP_HOST") ?? "").trim();
const SMTP_PORT = Number(Deno.env.get("CALENDARIO_SMTP_PORT") ?? "465");
const SMTP_USER = (Deno.env.get("CALENDARIO_SMTP_USER") ?? "").trim();
const SMTP_PASS = Deno.env.get("CALENDARIO_SMTP_PASS") ?? "";
const REMITENTE =
  ((Deno.env.get("CALENDARIO_SMTP_FROM") ?? "").trim() || SMTP_USER).toLowerCase();

/// Correos por persona y por hora (invitaciones + cancelaciones), para que un error o un abuso no
/// queme la cuenta del sistema.
const MAX_POR_HORA = 300;
/// Destinatarios por evento.
const MAX_POR_EVENTO = 100;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function limpio(e: unknown): string {
  let t = e instanceof Error ? e.message : String(e);
  if (SMTP_PASS) t = t.split(SMTP_PASS).join("***");
  return t.slice(0, 300);
}

function html(t: string): string {
  return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

const FORMATO = new Intl.DateTimeFormat("es-MX", {
  timeZone: "America/Mexico_City",
  weekday: "long",
  day: "numeric",
  month: "long",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});
const HORA = new Intl.DateTimeFormat("es-MX", {
  timeZone: "America/Mexico_City",
  hour: "2-digit",
  minute: "2-digit",
});

function cuando(inicio: Date, fin: Date): string {
  const mismoDia = inicio.toDateString() === fin.toDateString() &&
    fin.getTime() - inicio.getTime() < 24 * 3600 * 1000;
  return mismoDia
    ? `${FORMATO.format(inicio)} – ${HORA.format(fin)}`
    : `${FORMATO.format(inicio)} – ${FORMATO.format(fin)}`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const responde = (cuerpo: Record<string, unknown>, status = 200) =>
    new Response(JSON.stringify(cuerpo), {
      status,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  if (req.method !== "POST") return responde({ error: "Método no permitido." }, 405);

  const svc = createClient(SUPABASE_URL, SERVICE_KEY);

  const auth = req.headers.get("Authorization") ?? "";
  const { data: { user } } = await svc.auth.getUser(auth.replace("Bearer ", ""));
  if (!user) return responde({ error: "Sesión inválida." }, 401);

  let entrada: Record<string, unknown>;
  try {
    entrada = await req.json();
  } catch {
    return responde({ error: "Petición inválida." }, 400);
  }
  const eventoId = String(entrada.event_id ?? "");
  const accion = entrada.accion === "cancelar" ? "cancelar" : "enviar";
  const alcanceSerie = entrada.alcance === "serie";

  const { data: evento } = await svc.from("events").select("*").eq("id", eventoId).maybeSingle();
  if (!evento) return responde({ error: "No se encontró el evento." }, 404);
  // Quien creó el evento, o quien apartó esa cita (citas del Calendario, 08/10/2026): el evento es de
  // quien publicó la cita, pero lo dispara la persona al apartar o cancelar.
  let esCita = false;
  if (evento.creator_id !== user.id) {
    const { data: cita } = await svc.from("citas_reservas").select("event_id")
      .eq("event_id", evento.id).eq("apartado_por", user.id).maybeSingle();
    if (!cita) {
      return responde({ error: "Solo quien creó el evento puede mandar sus invitaciones." }, 403);
    }
    esCita = true;
  }

  if (!SMTP_HOST || !REMITENTE || !esCorreo(REMITENTE)) {
    return responde({ error: "El correo del calendario no está configurado (CALENDARIO_SMTP_*)." }, 500);
  }
  // Supabase no deja salir por el 25 ni por el 587 desde una función: se quedaría colgada.
  if (SMTP_PORT === 25 || SMTP_PORT === 587) {
    return responde({ error: `CALENDARIO_SMTP_PORT ${SMTP_PORT} no sirve desde Supabase: usa 465.` }, 500);
  }

  // El organizador es quien creó el evento (en una cita, el profesional).
  const { data: creador } = await svc.from("profiles")
    .select("full_name, nombre, paterno, email").eq("id", evento.creator_id).maybeSingle();
  const organizador: Persona = {
    nombre: creador?.full_name ?? [creador?.nombre, creador?.paterno].filter(Boolean).join(" "),
    email: String(creador?.email ?? user.email ?? "").toLowerCase(),
  };
  if (!esCorreo(organizador.email)) {
    return responde({ error: "El perfil de quien organiza no tiene un correo válido." }, 400);
  }

  // ── La serie, el identificador y la versión ──────────────────────────────────
  const esSerie = Boolean(evento.serie_id) && alcanceSerie;
  let filas = [evento];
  if (esSerie) {
    const { data } = await svc.from("events").select("*")
      .eq("serie_id", evento.serie_id).order("serie_inicio", { ascending: true });
    if (data?.length) filas = data;
  }
  const uid = evento.ical_uid ?? `${evento.serie_id ?? evento.id}@sistemassi.com`;
  const recurrenceId = evento.serie_id && !esSerie && evento.serie_inicio
    ? new Date(evento.serie_inicio)
    : null;

  const { data: mismasInv } = await svc.from("events").select("id, ical_seq")
    .eq(evento.serie_id ? "serie_id" : "id", evento.serie_id ?? evento.id);
  const secuencia = Math.max(0, ...(mismasInv ?? []).map((e: any) => e.ical_seq ?? 0)) + 1;
  await svc.from("events").update({ ical_uid: uid, ical_seq: secuencia })
    .eq(evento.serie_id ? "serie_id" : "id", evento.serie_id ?? evento.id);

  // ── A quién ──────────────────────────────────────────────────────────────────
  // Lo último que se le mandó a cada correo de esta invitación (o de esta fecha de la serie).
  let qPrevios = svc.from("calendario_envios").select("email, metodo, enviado_en")
    .eq("ical_uid", uid).is("error", null).order("enviado_en", { ascending: true });
  qPrevios = recurrenceId
    ? qPrevios.eq("recurrence_id", recurrenceId.toISOString())
    : qPrevios.is("recurrence_id", null);
  const { data: previos } = await qPrevios;
  const ultimo = new Map<string, string>();
  for (const p of previos ?? []) ultimo.set(p.email, p.metodo);
  const conInvitacion = new Set([...ultimo].filter(([, m]) => m === "REQUEST").map(([e]) => e));

  const destinatarios = new Map<string, Persona>();
  if (accion === "enviar") {
    const { data: inv } = await svc.from("event_invitations")
      .select("user_id").eq("event_id", evento.id);
    const ids = (inv ?? []).map((i: any) => i.user_id).filter(Boolean);
    if (ids.length) {
      const { data: perfiles } = await svc.from("profiles")
        .select("full_name, email").in("id", ids);
      for (const p of perfiles ?? []) {
        const email = String(p.email ?? "").trim().toLowerCase();
        if (esCorreo(email)) destinatarios.set(email, { nombre: p.full_name, email });
      }
    }
    const { data: externos } = await svc.from("event_external_invitees")
      .select("email, nombre").eq("event_id", evento.id);
    for (const x of externos ?? []) destinatarios.set(x.email, { nombre: x.nombre, email: x.email });
    destinatarios.delete(organizador.email);
  }
  // Copia para quien la manda, para que también la agende en su Outlook / Gmail (pedido el
  // 07/10/2026). Su calendario no acepta una invitación en la que él es el ORGANIZADOR, así que en
  // su copia organiza «Calendario SI SOL» y él va de invitado.
  const copiaCreador = accion === "enviar";

  // Cancelación a quien la tenía y ya no está (o a todos, si se cancela el evento).
  const quitados = [...conInvitacion].filter((e) =>
    !destinatarios.has(e) && !(copiaCreador && e === organizador.email)
  );

  const total = destinatarios.size + quitados.length + (copiaCreador ? 1 : 0);
  if (total === 0) return responde({ enviados: 0, cancelados: 0, errores: [] });
  if (destinatarios.size > MAX_POR_EVENTO) {
    return responde({ error: `Máximo ${MAX_POR_EVENTO} invitados por evento.` }, 400);
  }
  const haceUnaHora = new Date(Date.now() - 3600 * 1000).toISOString();
  const { count } = await svc.from("calendario_envios").select("id", { count: "exact", head: true })
    .eq("enviado_por", user.id).gte("enviado_en", haceUnaHora);
  if ((count ?? 0) + total > MAX_POR_HORA) {
    return responde({ error: "Llegaste al límite de invitaciones por hora. Intenta más tarde." }, 429);
  }

  // ── Armar y mandar ───────────────────────────────────────────────────────────
  const primera = filas[0];
  const ultima = filas[filas.length - 1];
  const inicio = new Date(primera.start_time);
  const fin = new Date(primera.end_time);
  const rrule = esSerie && filas.length > 1
    ? rruleDe(evento.recurrence, new Date(ultima.serie_inicio ?? ultima.start_time))
    : null;
  const asistentes = [...destinatarios.values()];

  const base = {
    uid,
    secuencia,
    inicio,
    fin,
    titulo: String(evento.title ?? "Evento"),
    descripcion: evento.description,
    lugar: evento.location,
    organizador,
    rrule,
    recurrenceId,
  };

  const transporte = nodemailer.createTransport({
    host: SMTP_HOST,
    port: SMTP_PORT,
    secure: SMTP_PORT === 465,
    auth: { user: SMTP_USER, pass: SMTP_PASS },
    connectionTimeout: 15000,
    greetingTimeout: 10000,
    socketTimeout: 20000,
  });

  const fechaTexto = cuando(inicio, fin) + (rrule ? ` (se repite ${String(evento.recurrence).toLowerCase()})` : "");
  const cuerpo = (encabezado: string) => {
    const filasHtml = [
      ["Cuándo", fechaTexto],
      ["Dónde", evento.location],
      ["Organiza", `${organizador.nombre ?? ""} <${organizador.email}>`],
    ].filter(([, v]) => v).map(([k, v]) =>
      `<tr><td style="color:#6b7280;padding:4px 16px 4px 0;vertical-align:top">${k}</td>` +
      `<td style="padding:4px 0">${html(String(v))}</td></tr>`
    ).join("");
    const desc = evento.description
      ? `<p style="white-space:pre-wrap;margin:16px 0 0">${html(String(evento.description))}</p>`
      : "";
    return {
      html: `<div style="font-family:Arial,sans-serif;font-size:14px;color:#111827">` +
        `<p style="color:#344092;font-weight:bold;margin:0 0 4px">${html(encabezado)}</p>` +
        `<h2 style="margin:0 0 12px">${html(base.titulo)}</h2>` +
        `<table style="border-collapse:collapse">${filasHtml}</table>${desc}` +
        `<p style="color:#6b7280;font-size:12px;margin-top:24px">Enviado desde SistemasSI · ` +
        `SI SOL Inmobiliarias. Usa los botones de tu calendario para aceptar o rechazar.</p></div>`,
      text: `${encabezado}\n\n${base.titulo}\nCuándo: ${fechaTexto}\n` +
        (evento.location ? `Dónde: ${evento.location}\n` : "") +
        `Organiza: ${organizador.nombre ?? ""} <${organizador.email}>\n` +
        (evento.description ? `\n${evento.description}\n` : ""),
    };
  };

  const errores: { email: string; error: string }[] = [];
  let enviados = 0;
  let cancelados = 0;
  let copia = false;
  const registro: Record<string, unknown>[] = [];

  const sistema: Persona = { nombre: "Calendario SI SOL", email: REMITENTE };
  const mandar = async (para: Persona, metodo: "REQUEST" | "CANCEL", asunto: string, encabezado: string,
    lista: Persona[]) => {
    const esCreador = para.email === organizador.email;
    const ics = construirIcs({
      ...base,
      metodo,
      asistentes: esCreador ? [...lista.filter((a) => a.email !== para.email), para] : lista,
      organizador: esCreador ? sistema : organizador,
    });
    let error: string | null = null;
    try {
      await transporte.sendMail({
        from: { name: "Calendario SI SOL", address: REMITENTE },
        to: para.nombre ? { name: para.nombre, address: para.email } : para.email,
        subject: asunto,
        ...cuerpo(encabezado),
        icalEvent: { method: metodo, filename: "invitacion.ics", content: ics },
      });
    } catch (e) {
      error = limpio(e);
      errores.push({ email: para.email, error });
    }
    registro.push({
      ical_uid: uid,
      recurrence_id: recurrenceId?.toISOString() ?? null,
      email: para.email,
      metodo,
      enviado_por: user.id,
      error,
    });
    return error === null;
  };

  const fechaCorta = new Intl.DateTimeFormat("es-MX", {
    timeZone: "America/Mexico_City", day: "numeric", month: "short",
  }).format(inicio);

  for (const p of asistentes) {
    const yaLaTenia = conInvitacion.has(p.email);
    const ok = await mandar(
      p,
      "REQUEST",
      esCita
        ? `Cita confirmada: ${base.titulo} (${fechaCorta})`
        : `${yaLaTenia ? "Actualización" : "Invitación"}: ${base.titulo} (${fechaCorta})`,
      esCita ? "Tu cita quedó confirmada" : yaLaTenia ? "Se actualizó este evento" : "Te invitaron a este evento",
      asistentes,
    );
    if (ok) enviados++;
  }
  if (copiaCreador) {
    const yaLaTenia = conInvitacion.has(organizador.email);
    const ok = await mandar(
      organizador,
      "REQUEST",
      esCita
        ? `Nueva cita: ${base.titulo} (${fechaCorta})`
        : `${yaLaTenia ? "Actualización" : "Tu evento"}: ${base.titulo} (${fechaCorta})`,
      esCita
        ? "Te apartaron una cita"
        : asistentes.length
        ? `Tu copia: enviaste la invitación a ${asistentes.length} persona${asistentes.length === 1 ? "" : "s"}`
        : "Tu copia del evento, para agregarlo a tu calendario",
      asistentes,
    );
    copia = ok;
  }
  for (const email of quitados) {
    const ok = await mandar(
      { email },
      "CANCEL",
      `Cancelado: ${base.titulo} (${fechaCorta})`,
      accion === "cancelar" ? "Se canceló este evento" : "Ya no estás invitado a este evento",
      [{ email }],
    );
    if (ok) cancelados++;
  }

  if (registro.length) await svc.from("calendario_envios").insert(registro);
  return responde({ enviados, cancelados, copia, errores });
});
