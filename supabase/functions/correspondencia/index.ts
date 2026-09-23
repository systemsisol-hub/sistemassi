// Correspondencia: manda correos a compañeros -o a cualquier direccion- desde la cuenta del sistema.
//
// ─── Como esta armado ────────────────────────────────────────────────────────
//
// Sale por SMTP desde UNA cuenta compartida, no desde la de cada quien. El correo muestra el nombre
// de quien escribe -«Ana Lopez (via SISOL)»- y lleva su direccion en `Reply-To`, asi que al contestar
// la respuesta le llega a su propio buzon. La alternativa, mandar desde la cuenta de cada empleado,
// obligaria a usar sus contraseñas, y esas hoy estan en texto plano en `profiles.mail_pass`.
//
// La configuracion del servidor vive SOLO en los secretos de esta funcion -SMTP_HOST, SMTP_PORT,
// SMTP_USER, SMTP_PASS, SMTP_FROM-, que se pegan en el panel de Supabase. No hay ninguna pantalla para
// verla ni cambiarla, y la contraseña nunca sale de aqui: ni en respuestas ni en el registro.
//
// Todo intento queda en la tabla `correspondencia`, que SOLO escribe esta funcion. Por eso el limite
// por hora se cuenta ahi: si la aplicacion pudiera insertar, tambien podria no insertar.

import { createClient } from "jsr:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";
import {
  cuerpoHtml,
  cuerpoTexto,
  MAX_POR_HORA,
  nombreRemitente,
  puertoPermitido,
  validarMensaje,
} from "./validar.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const SMTP_HOST = (Deno.env.get("SMTP_HOST") ?? "").trim();
const SMTP_PORT = Number(Deno.env.get("SMTP_PORT") ?? "465");
const SMTP_USER = (Deno.env.get("SMTP_USER") ?? "").trim();
const SMTP_PASS = Deno.env.get("SMTP_PASS") ?? "";
/// La direccion que aparece como remitente. Si no se da, la del usuario SMTP, que es lo habitual.
const SMTP_FROM = (Deno.env.get("SMTP_FROM") ?? "").trim() || SMTP_USER;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

/// Un error del servidor de correo, sin nada que no deba salir.
///
/// Los errores de la libreria no traen la contraseña, pero se quita igual por si algun dia alguno la
/// repite: este texto se guarda en la tabla y se le muestra a quien envio.
function errorLimpio(e: unknown): string {
  let t = e instanceof Error ? e.message : String(e);
  if (SMTP_PASS) t = t.split(SMTP_PASS).join("***");
  return t.slice(0, 500);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const responde = (cuerpo: Record<string, unknown>, status = 200) =>
    new Response(JSON.stringify(cuerpo),
      { status, headers: { ...CORS, "Content-Type": "application/json" } });

  if (req.method !== "POST") return responde({ error: "Metodo no permitido." }, 405);

  const svc = createClient(SUPABASE_URL, SERVICE_KEY);

  // ── Quien escribe ──────────────────────────────────────────────────────────
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth) return responde({ error: "Falta la sesion." }, 401);
  const { data: { user } } = await svc.auth.getUser(auth.replace("Bearer ", ""));
  if (!user) return responde({ error: "Sesion invalida." }, 401);

  // `mail_pass` NO se pide, a proposito: esta funcion no la necesita y no tiene por que tenerla.
  const { data: prof } = await svc.from("profiles")
    .select("nombre,paterno,materno,role,permissions,mail_user,email")
    .eq("id", user.id).maybeSingle();
  if (!prof) return responde({ error: "No se encontro tu perfil." }, 403);

  const esAdmin = prof.role === "admin";
  const permisos = (prof.permissions ?? {}) as Record<string, unknown>;

  // El MISMO permiso que abre la pagina. Si aqui bastara con tener sesion, la pagina seria una
  // sugerencia y no un control.
  //
  // OJO: este control es tan fuerte como `profiles`, y hoy cada usuario puede escribirse su propio
  // `role` y sus `permissions`. Cerrar eso es una tarea aparte, ya identificada el 23/09/2026.
  if (!esAdmin && permisos.show_correspondencia !== true) {
    return responde({ error: "No tienes acceso a Correspondencia." }, 403);
  }

  let entrada: Record<string, unknown>;
  try {
    entrada = await req.json() as Record<string, unknown>;
  } catch {
    return responde({ error: "Cuerpo ilegible." }, 400);
  }

  const configurado = SMTP_HOST !== "" && SMTP_USER !== "" && SMTP_PASS !== "" && SMTP_FROM !== "";
  const puerto = puertoPermitido(SMTP_PORT);

  // ── La configuracion, para que un administrador sepa si esta lista ─────────
  //
  // Se contesta desde aqui y no desde una copia en la aplicacion: la unica fuente es lo que de
  // verdad corre. Y NUNCA incluye la contraseña, solo si esta puesta.
  if (entrada.configuracion === true) {
    if (!esAdmin) return responde({ error: "Solo para administradores." }, 403);
    return responde({
      configurado,
      servidor: SMTP_HOST || null,
      puerto: SMTP_PORT,
      puerto_ok: puerto.ok,
      motivo_puerto: puerto.ok === false ? puerto.motivo : null,
      remitente: SMTP_FROM || null,
      contrasena_puesta: SMTP_PASS !== "",
      max_por_hora: MAX_POR_HORA,
    });
  }

  // Sin configurar se dice claro, en lugar de intentar conectar a un servidor vacio.
  if (!configurado) {
    return responde({
      error: "El envio de correo todavia no esta configurado. Un administrador tiene que poner "
        + "los datos del servidor en los secretos de la funcion.",
    }, 503);
  }
  // `=== false` y no `!puerto.ok`: con `strict` apagado la negacion no reduce la union. Ver
  // ../tsconfig.json y el mismo caso en ai-assistant/index.ts.
  if (puerto.ok === false) return responde({ error: puerto.motivo }, 503);

  const v = validarMensaje(entrada);
  if (v.ok === false) return responde({ error: v.error, rechazados: v.rechazados ?? [] }, 400);

  // ── El limite por hora ─────────────────────────────────────────────────────
  //
  // Cuentan los intentos, no solo los enviados: si contaran solo los buenos, un servidor que falla
  // dejaria reintentar sin tope contra el.
  const haceUnaHora = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { count } = await svc.from("correspondencia")
    .select("id", { count: "exact", head: true })
    .eq("remitente_id", user.id)
    .gte("creado_en", haceUnaHora);
  if ((count ?? 0) >= MAX_POR_HORA) {
    return responde({
      error: `Llegaste al limite de ${MAX_POR_HORA} mensajes por hora. Intenta mas tarde.`,
    }, 429);
  }

  const nombre = [prof.nombre, prof.paterno, prof.materno]
    .map((x) => String(x ?? "").trim()).filter((x) => x !== "").join(" ");
  // Como el Directorio: el buzon de trabajo si lo hay, y si no el correo de la cuenta.
  const suCorreo = String(prof.mail_user ?? "").trim() || String(prof.email ?? "").trim() || null;

  // Se registra ANTES de enviar. Si la funcion se cae a medio envio, queda un PENDIENTE que lo
  // delata, en vez de un correo que salio -o no- sin rastro.
  const { data: fila, error: errFila } = await svc.from("correspondencia").insert({
    remitente_id: user.id,
    remitente_nombre: nombre || "(sin nombre)",
    asunto: v.mensaje.asunto,
    cuerpo: v.mensaje.cuerpo,
    destinatarios: v.mensaje.destinatarios,
    estado: "PENDIENTE",
  }).select("id").single();
  if (errFila || !fila) {
    return responde({ error: `No se pudo registrar el mensaje: ${errFila?.message ?? "sin id"}` }, 500);
  }

  try {
    const transporte = nodemailer.createTransport({
      host: SMTP_HOST,
      port: SMTP_PORT,
      // 465 es TLS desde el primer byte. Cualquier otro puerto permitido se intenta con STARTTLS.
      secure: SMTP_PORT === 465,
      auth: { user: SMTP_USER, pass: SMTP_PASS },
      // Tiempos cortos a proposito: un puerto cerrado tiene que fallar con un error claro, no quedarse
      // colgado hasta que la plataforma corte la funcion sin decir nada.
      connectionTimeout: 15000,
      greetingTimeout: 10000,
      socketTimeout: 20000,
    });

    const info = await transporte.sendMail({
      from: { name: nombreRemitente(nombre), address: SMTP_FROM },
      to: v.mensaje.destinatarios,
      replyTo: suCorreo ?? undefined,
      subject: v.mensaje.asunto,
      text: cuerpoTexto(v.mensaje.cuerpo, nombre || "un colaborador", suCorreo),
      html: cuerpoHtml(v.mensaje.cuerpo, nombre || "un colaborador", suCorreo),
    });

    // Lo que el servidor NO acepto, aunque el envio en conjunto no fallara.
    const noAceptados = Array.isArray(info?.rejected) ? info.rejected.map(String) : [];

    await svc.from("correspondencia").update({
      estado: noAceptados.length === 0 ? "ENVIADO" : "FALLIDO",
      enviado_en: new Date().toISOString(),
      error: noAceptados.length === 0
        ? null
        : `El servidor no acepto: ${noAceptados.join(", ")}`,
    }).eq("id", fila.id);

    return responde({
      ok: noAceptados.length === 0,
      id: fila.id,
      enviados: v.mensaje.destinatarios.length - noAceptados.length,
      no_aceptados: noAceptados,
    });
  } catch (e) {
    const detalle = errorLimpio(e);
    console.error(`correspondencia ${fila.id}: ${detalle}`);
    await svc.from("correspondencia").update({ estado: "FALLIDO", error: detalle })
      .eq("id", fila.id);
    return responde({ error: `No se pudo enviar: ${detalle}`, id: fila.id }, 502);
  }
});
