// Correspondencia: comunicados de la empresa a los empleados, desde la cuenta del sistema.
//
// ─── Como esta armado ────────────────────────────────────────────────────────
//
// Lo usan tres personas para mandar comunicados -decision del usuario el 23/09/2026-, asi que el
// correo sale como «Comunicación SI SOL» y no dice quien lo escribio: ni en el nombre, ni en un
// `Reply-To`, ni en un pie. Los destinatarios van en copia oculta. Quien lo mando SI queda
// registrado, en la tabla `correspondencia`. Ver `armarCorreo` en validar.ts, que es donde se
// prueba todo esto.
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
  armarCorreo,
  MAX_POR_HORA,
  puertoPermitido,
  revisarRemitente,
  validarMensaje,
} from "./validar.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const SMTP_HOST = (Deno.env.get("SMTP_HOST") ?? "").trim();
const SMTP_PORT = Number(Deno.env.get("SMTP_PORT") ?? "465");
const SMTP_USER = (Deno.env.get("SMTP_USER") ?? "").trim();
const SMTP_PASS = Deno.env.get("SMTP_PASS") ?? "";
/// La direccion que va de remitente. Si no se da, se intenta con SMTP_USER; ver `revisarRemitente`,
/// que dice claro cuando ninguna de las dos sirve en lugar de dejar que el servidor conteste
/// «501 Bad sender address syntax», que fue lo que paso en el primer envio real.
const remitente = revisarRemitente(Deno.env.get("SMTP_FROM") ?? "", SMTP_USER);

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
    .select("nombre,paterno,materno,permissions")
    .eq("id", user.id).maybeSingle();
  if (!prof) return responde({ error: "No se encontro tu perfil." }, 403);

  const permisos = (prof.permissions ?? {}) as Record<string, unknown>;

  // SOLO el permiso: ser administrador NO basta, a proposito. Pedido el 23/09/2026: «no todos los
  // administradores lo pueden ver». Es el MISMO criterio que abre la pagina, para que no haya quien
  // la vea y luego reciba «no tienes acceso».
  //
  // OJO: este control es tan fuerte como `profiles`, y hoy cada usuario puede escribirse sus propios
  // `permissions`. Cerrar eso es una tarea aparte, ya identificada el 23/09/2026.
  if (permisos.show_correspondencia !== true) {
    return responde({ error: "No tienes acceso a Correspondencia." }, 403);
  }

  let entrada: Record<string, unknown>;
  try {
    entrada = await req.json() as Record<string, unknown>;
  } catch {
    return responde({ error: "Cuerpo ilegible." }, 400);
  }

  // El remitente se revisa aparte: puede estar todo puesto y la direccion ser mala.
  const configurado = SMTP_HOST !== "" && SMTP_USER !== "" && SMTP_PASS !== "";
  const puerto = puertoPermitido(SMTP_PORT);

  // ── La configuracion, para que quien usa el modulo sepa si esta lista ──────
  //
  // Para quien tenga el permiso, que son quienes van a enviar: son ellos los que tienen que saber
  // si el correo esta listo antes de escribir un comunicado entero. Se contesta desde aqui y no
  // desde una copia en la aplicacion, y NUNCA incluye la contraseña, solo si esta puesta.
  if (entrada.configuracion === true) {
    return responde({
      configurado,
      servidor: SMTP_HOST || null,
      puerto: SMTP_PORT,
      puerto_ok: puerto.ok,
      motivo_puerto: puerto.ok === false ? puerto.motivo : null,
      remitente: remitente.ok === false ? null : remitente.direccion,
      remitente_ok: remitente.ok,
      motivo_remitente: remitente.ok === false ? remitente.motivo : null,
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
  // Antes de conectar, y antes de registrar: un remitente mal puesto es un error de configuracion,
  // no un envio fallido, y no tiene por que gastarle a nadie un intento del limite por hora.
  if (remitente.ok === false) return responde({ error: remitente.motivo }, 503);

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

  // El nombre se usa SOLO para el registro. El correo no lo lleva: ver `armarCorreo`.
  const nombre = [prof.nombre, prof.paterno, prof.materno]
    .map((x) => String(x ?? "").trim()).filter((x) => x !== "").join(" ");

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

    const info = await transporte.sendMail(armarCorreo(v.mensaje, remitente.direccion));

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
