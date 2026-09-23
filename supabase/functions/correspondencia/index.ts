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
// El cuerpo llega como documento del editor, no como HTML, y el HTML lo escribe `contenido.ts` con
// una lista cerrada de formatos. Las listas de distribucion se expanden AQUI, en el momento de enviar:
// asi una lista siempre llega a quien esta en ella hoy.
//
// La configuracion del servidor vive SOLO en los secretos de esta funcion -SMTP_HOST, SMTP_PORT,
// SMTP_USER, SMTP_PASS, SMTP_FROM-, que se pegan en el panel de Supabase. No hay ninguna pantalla para
// verla ni cambiarla, y la contraseña nunca sale de aqui: ni en respuestas ni en el registro.
//
// Todo intento queda en la tabla `correspondencia`, que SOLO escribe esta funcion. Por eso el limite
// por hora se cuenta ahi: si la aplicacion pudiera insertar, tambien podria no insertar.

import { Buffer } from "node:buffer";
import { createClient } from "jsr:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";
import { cidDe } from "./contenido.ts";
import {
  type Adjunto,
  armarCorreo,
  esUuid,
  lotes,
  MAX_BYTES_IMAGENES,
  MAX_POR_HORA,
  type Miembro,
  type PerfilCorreo,
  puertoPermitido,
  resolverMiembros,
  revisarRemitente,
  validarContenido,
  validarDestinatarios,
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

/// El cubo PRIVADO donde la pantalla sube las imagenes del editor. Privado porque nadie de fuera
/// necesita leerlas: esta funcion las descarga con su llave y las incrusta en el correo.
const CUBO_IMAGENES = "correspondencia-imagenes";

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

  const c = validarContenido(entrada);
  if (c.ok === false) return responde({ error: c.error }, 400);

  // ── Las imagenes incrustadas ───────────────────────────────────────────────
  //
  // Se descargan ANTES de registrar nada: una imagen que ya no esta es un problema del borrador, no un
  // envio fallido, y no tiene por que gastarle a nadie un intento del limite por hora.
  //
  // Solo se piden nombres que `validarContenido` ya dio por buenos -32 hexadecimales y una extension-,
  // y solo de este cubo. No hay manera de hacer que la funcion descargue otra cosa.
  const adjuntos: Adjunto[] = [];
  let pesoImagenes = 0;
  for (const ruta of c.contenido.imagenes) {
    const { data: archivo, error: errImg } = await svc.storage.from(CUBO_IMAGENES).download(ruta);
    if (errImg || !archivo) {
      return responde({
        error: "Una de las imagenes del mensaje ya no esta en el sistema. Quitala y vuelve a insertarla.",
      }, 400);
    }
    const bytes = new Uint8Array(await archivo.arrayBuffer());
    pesoImagenes += bytes.length;
    if (pesoImagenes > MAX_BYTES_IMAGENES) {
      return responde({
        error: `Las imagenes pesan mas de ${MAX_BYTES_IMAGENES / 1024 / 1024} MB entre todas. Quita `
          + `alguna: un correo tan pesado lo rechazan muchos servidores.`,
      }, 400);
    }
    adjuntos.push({
      filename: ruta,
      content: Buffer.from(bytes),
      cid: cidDe(ruta),
      contentType: ruta.endsWith(".png") ? "image/png"
        : ruta.endsWith(".gif") ? "image/gif" : "image/jpeg",
    });
  }

  // ── Las listas de distribucion ─────────────────────────────────────────────
  //
  // Se expanden aqui y no en la pantalla, en el momento de enviar: asi la lista llega a quien esta
  // en ella HOY -un compañero que cambio de correo, o que se dio de baja- y no a la foto que tenia la
  // pantalla cuando se cargo.
  const idsListas = Array.isArray(entrada.listas) ? entrada.listas : [];
  if (idsListas.some((x) => typeof x !== "string" || !esUuid(x))) {
    return responde({ error: "Una de las listas no es valida. Recarga la pagina." }, 400);
  }
  const ids = [...new Set(idsListas as string[])];

  let nombresListas: string[] = [];
  let deListas: string[] = [];
  let omitidos = 0;
  if (ids.length > 0) {
    const { data: listas } = await svc.from("listas_distribucion").select("id,nombre").in("id", ids);
    // Una lista que se borro mientras alguien redactaba: se dice, en vez de mandar sin ella.
    if (!listas || listas.length !== ids.length) {
      return responde({
        error: "Una de las listas elegidas ya no existe. Recarga la pagina y vuelve a elegirlas.",
      }, 400);
    }
    nombresListas = (listas as Record<string, unknown>[]).map((l) => String(l.nombre));

    const { data: miembros } = await svc.from("lista_miembros")
      .select("profile_id,correo").in("lista_id", ids);
    const lista = (miembros ?? []) as Miembro[];
    const pids = [...new Set(lista.map((m) => m.profile_id).filter((x): x is string => !!x))];
    const perfiles = new Map<string, PerfilCorreo>();
    if (pids.length > 0) {
      const { data: ps } = await svc.from("profiles")
        .select("id,mail_user,email,status_sys").in("id", pids);
      for (const p of (ps ?? []) as Record<string, unknown>[]) {
        perfiles.set(String(p.id), p as unknown as PerfilCorreo);
      }
    }
    const r = resolverMiembros(lista, perfiles);
    deListas = r.correos;
    omitidos = r.omitidos;
  }

  const sueltos = Array.isArray(entrada.destinatarios) ? entrada.destinatarios : [];
  const d = validarDestinatarios([...sueltos, ...deListas]);
  if (d.ok === false) return responde({ error: d.error, rechazados: d.rechazados ?? [] }, 400);

  // ── El limite por hora ─────────────────────────────────────────────────────
  //
  // Cuentan los intentos, no solo los enviados: si contaran solo los buenos, un servidor que falla
  // dejaria reintentar sin tope contra el. Y cuentan COMUNICADOS, no tandas.
  const haceUnaHora = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { count } = await svc.from("correspondencia")
    .select("id", { count: "exact", head: true })
    .eq("remitente_id", user.id)
    .gte("creado_en", haceUnaHora);
  if ((count ?? 0) >= MAX_POR_HORA) {
    return responde({
      error: `Llegaste al limite de ${MAX_POR_HORA} comunicados por hora. Intenta mas tarde.`,
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
    asunto: c.contenido.asunto,
    cuerpo: c.contenido.texto,
    cuerpo_html: c.contenido.html,
    destinatarios: d.destinatarios,
    listas: nombresListas,
    estado: "PENDIENTE",
  }).select("id").single();
  if (errFila || !fila) {
    return responde({ error: `No se pudo registrar el mensaje: ${errFila?.message ?? "sin id"}` }, 500);
  }

  let transporte;
  try {
    transporte = nodemailer.createTransport({
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
  } catch (e) {
    const detalle = errorLimpio(e);
    await svc.from("correspondencia").update({ estado: "FALLIDO", error: detalle }).eq("id", fila.id);
    return responde({ error: `No se pudo enviar: ${detalle}`, id: fila.id }, 502);
  }

  // ── El envio, por tandas ───────────────────────────────────────────────────
  //
  // Una tanda que falla no detiene las demas: si la segunda tanda de dos falla, la primera ya salio y
  // eso no se puede deshacer. Lo honesto es seguir, y registrar exactamente a cuantos llego. De ahi
  // el estado PARCIAL: ni ENVIADO -que diria que llego a todos- ni FALLIDO -que diria que a nadie-.
  const tandas = lotes(d.destinatarios);
  let enviados = 0;
  const noAceptados: string[] = [];
  const fallas: string[] = [];
  for (let i = 0; i < tandas.length; i++) {
    const lote = tandas[i];
    try {
      const info = await transporte.sendMail(
        armarCorreo(c.contenido, remitente.direccion, lote, adjuntos));
      // Lo que el servidor NO acepto de esta tanda, aunque la tanda en conjunto no fallara.
      const rechazados = Array.isArray(info?.rejected) ? info.rejected.map(String) : [];
      noAceptados.push(...rechazados);
      enviados += lote.length - rechazados.length;
    } catch (e) {
      const detalle = errorLimpio(e);
      console.error(`correspondencia ${fila.id}, tanda ${i + 1}/${tandas.length}: ${detalle}`);
      fallas.push(tandas.length > 1
        ? `Tanda ${i + 1} de ${tandas.length} (${lote.length} destinatarios): ${detalle}`
        : detalle);
    }
  }

  const total = d.destinatarios.length;
  const estado = enviados === total ? "ENVIADO" : enviados === 0 ? "FALLIDO" : "PARCIAL";
  const error = [
    ...fallas,
    ...(noAceptados.length > 0 ? [`El servidor no acepto: ${noAceptados.join(", ")}`] : []),
  ].join(" · ").slice(0, 2000) || null;

  await svc.from("correspondencia").update({
    estado,
    enviado_en: enviados > 0 ? new Date().toISOString() : null,
    error,
  }).eq("id", fila.id);

  if (estado === "FALLIDO") {
    return responde({ error: `No se pudo enviar: ${error ?? "sin detalle"}`, id: fila.id }, 502);
  }
  return responde({
    ok: estado === "ENVIADO",
    estado,
    id: fila.id,
    total,
    enviados,
    no_aceptados: noAceptados,
    error,
    // Gente de las listas que ya no alcanza: dados de baja o sin correo. Se dice para que se limpie
    // la lista, no para detener el envio.
    omitidos,
  });
});
