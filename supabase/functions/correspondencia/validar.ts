// Lo que decide si un comunicado se puede mandar, a quien, y como sale.
//
// Sin efectos, a proposito: asi el arnes lo ejercita tal cual. Solo importa `contenido.ts`, que
// tampoco tiene efectos.
//
// ─── Por que la validacion vive en el servidor ───────────────────────────────
//
// La pantalla tambien valida, pero SOLO para avisar pronto. La que manda es esta: la funcion es la
// unica puerta hacia el servidor de correo, y una validacion que vive solo en la aplicacion la salta
// cualquiera que llame a la funcion directamente. Las dos usan la misma expresion de correo y la misma
// tabla de casos en sus pruebas -ver `test/correspondencia_test.dart`- para que no se separen sin que
// nadie lo note.

import { deltaAHtml, imagenesDe } from "./contenido.ts";

/// Tope de destinatarios por COMUNICADO, contando los que salen de las listas.
///
/// Era 50 por mensaje, y con las listas de distribucion eso no alcanzaba: hay 74 empleados activos
/// con correo, asi que una lista de «todos» ya no se podia mandar. Ahora el tope es por comunicado y
/// el envio se parte en tandas de `TAMANO_LOTE` -ver `lotes`-. 500 deja margen de sobra sobre la
/// plantilla y sigue impidiendo que el modulo se use para envios masivos desde la cuenta de la
/// empresa, que es para lo que existia el tope.
export const MAX_DESTINATARIOS = 500;

/// Destinatarios por MENSAJE al servidor de correo.
///
/// Los servidores limitan cuantos destinatarios acepta un solo mensaje, y el limite varia -100, 250,
/// 500-. 50 cabe en casi todos, y un comunicado a toda la plantilla sale en dos tandas.
export const TAMANO_LOTE = 50;

/// Comunicados por usuario en la ultima hora. Cuenta comunicados, no tandas.
export const MAX_POR_HORA = 20;

export const MAX_ASUNTO = 200;
/// Tope del texto, sin formato.
export const MAX_CUERPO = 20000;
/// Tope del HTML ya convertido. Con estilos en linea -que es como hay que escribirlos para el correo-
/// el HTML ocupa varias veces el texto.
export const MAX_HTML = 200000;

/// Imagenes por comunicado, y lo que pueden pesar entre todas.
///
/// Las imagenes van INCRUSTADAS, asi que viajan dentro de cada mensaje. Los servidores de correo
/// suelen rechazar los mensajes de mas de 10 a 25 MB, y un comunicado pesado es lento de abrir en un
/// telefono. La pantalla ya reduce cada imagen a un ancho de correo antes de subirla -una foto de
/// 4 MB queda en unos cientos de KB-, asi que estos topes solo se alcanzan a proposito.
export const MAX_IMAGENES = 10;
export const MAX_BYTES_IMAGENES = 10 * 1024 * 1024;

/// Una direccion de correo razonable. No pretende cubrir todo el RFC 5322: pretende rechazar lo que
/// seguro esta mal -espacios, dos arrobas, sin dominio, caracteres que partirian una cabecera- y
/// dejar pasar todo lo que usa la gente de verdad.
///
/// La MISMA expresion esta en `lib/services/correspondencia.dart`.
const CORREO = /^[^\s@<>(),;:"\[\]\\]+@[^\s@<>(),;:"\[\]\\]+\.[A-Za-z]{2,}$/;

export function esCorreo(s: string): boolean {
  return CORREO.test(s);
}

export function esUuid(s: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);
}

/// De una lista de textos -cada uno puede traer varias direcciones separadas por coma, punto y coma,
/// espacio o salto de linea, que es como se pegan de otro lado- saca las direcciones, en minusculas y
/// sin repetir, separando las que no son validas.
export function normalizarDestinatarios(
  lista: unknown,
): { validos: string[]; rechazados: string[] } {
  const validos: string[] = [];
  const rechazados: string[] = [];
  if (!Array.isArray(lista)) return { validos, rechazados };

  for (const item of lista) {
    if (typeof item !== "string") continue;
    for (const trozo of item.split(/[\s,;]+/)) {
      const d = trozo.trim().toLowerCase();
      if (d === "") continue;
      if (!esCorreo(d)) {
        if (!rechazados.includes(d)) rechazados.push(d);
      } else if (!validos.includes(d)) {
        validos.push(d);
      }
    }
  }
  return { validos, rechazados };
}

/// El asunto y el cuerpo, ya en los dos formatos en que sale el correo.
export interface Contenido {
  asunto: string;
  html: string;
  texto: string;
  /// Los nombres de las imagenes a adjuntar, ya validados. Ver `esRutaImagen` en contenido.ts.
  imagenes: string[];
}

/// Una imagen incrustada, en la forma que espera la libreria de correo.
export interface Adjunto {
  filename: string;
  content: unknown;
  cid: string;
  contentType: string;
}

/// Si el asunto y el cuerpo se pueden mandar.
///
/// El cuerpo llega como documento del editor en `contenido`, NUNCA como HTML: el HTML lo escribe
/// `deltaAHtml` con una lista cerrada de formatos. Ver `contenido.ts`.
export function validarContenido(
  entrada: unknown,
): { ok: true; contenido: Contenido } | { ok: false; error: string } {
  const e = (entrada ?? {}) as Record<string, unknown>;
  const asunto = typeof e.asunto === "string" ? e.asunto.trim() : "";

  if (asunto === "") return { ok: false, error: "Falta el asunto." };
  if (asunto.length > MAX_ASUNTO) {
    return { ok: false, error: `El asunto pasa de ${MAX_ASUNTO} caracteres.` };
  }
  // Un salto de linea en el asunto es la forma clasica de colar cabeceras en un correo -un «Bcc:»
  // metido a mano-. La libreria lo codifica, pero no hay ningun asunto legitimo que lo necesite, asi
  // que se rechaza aqui en vez de fiarse de que la libreria lo haga siempre bien.
  if (/[\r\n]/.test(asunto)) {
    return { ok: false, error: "El asunto no puede llevar saltos de linea." };
  }

  const convertido = deltaAHtml(e.contenido);
  if (convertido === null) {
    return { ok: false, error: "El mensaje no tiene un formato valido. Recarga la pagina e intenta de nuevo." };
  }
  if (convertido.texto.trim() === "") return { ok: false, error: "Falta el mensaje." };
  if (convertido.texto.length > MAX_CUERPO) {
    return { ok: false, error: `El mensaje pasa de ${MAX_CUERPO} caracteres.` };
  }
  if (convertido.html.length > MAX_HTML) {
    return { ok: false, error: "El mensaje tiene demasiado formato. Simplificalo un poco." };
  }
  const imagenes = imagenesDe(e.contenido);
  if (imagenes.length > MAX_IMAGENES) {
    return {
      ok: false,
      error: `El mensaje lleva ${imagenes.length} imagenes y el maximo es ${MAX_IMAGENES}.`,
    };
  }
  return {
    ok: true,
    contenido: { asunto, html: convertido.html, texto: convertido.texto, imagenes },
  };
}

/// Si la lista final de destinatarios -los escritos a mano MAS los de las listas- se puede mandar.
///
/// Se rechaza el envio ENTERO si alguna direccion esta mal, en lugar de mandar a las buenas y
/// callarse las malas: si no, alguien no recibe el correo y nadie se entera.
export function validarDestinatarios(
  lista: unknown,
): { ok: true; destinatarios: string[] } | { ok: false; error: string; rechazados?: string[] } {
  const { validos, rechazados } = normalizarDestinatarios(lista);
  if (rechazados.length > 0) {
    return {
      ok: false,
      error: rechazados.length === 1
        ? `«${rechazados[0]}» no es una direccion de correo valida.`
        : `${rechazados.length} direcciones no son validas.`,
      rechazados,
    };
  }
  if (validos.length === 0) return { ok: false, error: "Falta al menos un destinatario." };
  if (validos.length > MAX_DESTINATARIOS) {
    return {
      ok: false,
      error: `Son ${validos.length} destinatarios y el maximo por comunicado es ${MAX_DESTINATARIOS}.`,
    };
  }
  return { ok: true, destinatarios: validos };
}

/// La lista partida en tandas de `tamano`, en el mismo orden.
export function lotes<T>(lista: T[], tamano = TAMANO_LOTE): T[][] {
  const t = Math.max(1, Math.floor(tamano));
  const salida: T[][] = [];
  for (let i = 0; i < lista.length; i += t) salida.push(lista.slice(i, i + t));
  return salida;
}

/// Un miembro de una lista: un compañero O un correo tecleado. Nunca los dos.
export interface Miembro {
  profile_id: string | null;
  correo: string | null;
}

export interface PerfilCorreo {
  mail_user: string | null;
  email: string | null;
  status_sys: string | null;
}

/// Los correos a los que llega una lista HOY.
///
/// Los compañeros se guardan por PERSONA, no por correo, y el correo se busca en el momento de
/// enviar. Asi, si alguien cambia de correo la lista no se queda vieja, y quien se da de baja deja de
/// recibir sin que nadie tenga que acordarse de sacarlo. Esos casos no se callan: se cuentan en
/// `omitidos` para que quien envia sepa que la lista tiene gente que ya no alcanza.
///
/// El correo de un compañero es su buzon de trabajo si lo tiene, y si no el de su cuenta: el MISMO
/// criterio que el Directorio y que la pantalla.
export function resolverMiembros(
  miembros: Miembro[],
  perfiles: Map<string, PerfilCorreo>,
): { correos: string[]; omitidos: number } {
  const correos: string[] = [];
  let omitidos = 0;
  const agregar = (c: string) => {
    if (!correos.includes(c)) correos.push(c);
  };

  for (const m of miembros) {
    if (m.correo) {
      agregar(m.correo.trim().toLowerCase());
      continue;
    }
    const p = m.profile_id ? perfiles.get(m.profile_id) : undefined;
    if (!p || p.status_sys !== "ACTIVO") {
      omitidos++;
      continue;
    }
    const suyo = [p.mail_user, p.email]
      .map((x) => String(x ?? "").trim().toLowerCase())
      .find((x) => x !== "" && esCorreo(x));
    if (suyo) agregar(suyo);
    else omitidos++;
  }
  return { correos, omitidos };
}

/// El nombre con el que sale TODO comunicado, sea quien sea quien lo escribio.
///
/// Decision del usuario el 23/09/2026: el modulo lo usan tres personas para mandar comunicados a
/// los empleados, y quien recibe tiene que ver a la empresa, no a la persona. Quien lo mando SI
/// queda registrado, pero en la tabla `correspondencia`, no en el correo.
export const NOMBRE_REMITENTE = "Comunicación SI SOL";

/// Una tanda del comunicado, tal como sale, lista para la libreria.
///
/// ─── Por que es una funcion aparte ──────────────────────────────────────────
///
/// Para poder PROBAR lo que pidio el usuario, y no solo leerlo en el codigo:
///
///   * Que salga como «Comunicación SI SOL» y NO con el nombre de quien lo escribio. Esta funcion
///     ni siquiera recibe ese nombre, asi que no hay forma de que se cuele.
///   * Que NO lleve `Reply-To`. Llevaba el correo de quien lo mando, y eso descubria quien habia
///     sido en cuanto alguien pulsaba «Responder»: cambiar solo el nombre visible no bastaba.
///   * Que los destinatarios NO se vean entre si: van en copia oculta (`bcc`).
///
/// En `to` va la propia cuenta compartida. Un correo sin ningun destinatario visible es de los que
/// los filtros marcan como spam; poniendo la cuenta como destinataria es el patron clasico de
/// «destinatarios ocultos», y de paso la cuenta se queda con una copia.
export function armarCorreo(
  contenido: Contenido,
  cuenta: string,
  lote: string[],
  adjuntos: Adjunto[] = [],
): {
  from: { name: string; address: string };
  to: string;
  bcc: string[];
  subject: string;
  text: string;
  html: string;
  attachments: Adjunto[];
} {
  return {
    from: { name: NOMBRE_REMITENTE, address: cuenta },
    to: cuenta,
    bcc: lote,
    subject: contenido.asunto,
    text: contenido.texto,
    html: contenido.html,
    // Las imagenes incrustadas: el HTML las pide por `cid:` y aqui van con ese mismo identificador.
    attachments: adjuntos,
  };
}

/// La direccion que va en el `MAIL FROM`, o por que no sirve.
///
/// ─── Por que se revisa aqui ─────────────────────────────────────────────────
///
/// El primer envio real, el 23/09/2026, fallo con «501 5.1.7 Bad sender address syntax». El servidor
/// no dice QUE esta mal, y hay tres causas tipicas que se ven igual desde fuera:
///
///   1. No se puso SMTP_FROM y SMTP_USER es un nombre de usuario, no un correo. Muchos servidores
///      autentican con el usuario a secas, pero el remitente tiene que ser una direccion completa.
///   2. SMTP_FROM lleva un nombre o signos: «Sistema <correo@...>», o entre comillas.
///   3. Un caracter invisible pegado de un documento. `trim()` no quita todos: un espacio de ancho cero
///      (U+200B) sobrevive, y `\s` tampoco lo reconoce, asi que `esCorreo` lo dejaria pasar.
///
/// Por eso ademas de `esCorreo` se exige ASCII visible. Un remitente con acentos existe en teoria
/// (SMTPUTF8), pero ningun servidor corriente lo acepta y no vale la pena el riesgo.
///
/// No se repite el valor de SMTP_USER en el motivo: es parte de las credenciales.
export function revisarRemitente(
  desde: string,
  usuario: string,
): { ok: true; direccion: string } | { ok: false; motivo: string } {
  const deFrom = desde.trim() !== "";
  const d = (deFrom ? desde : usuario).trim();
  const origen = deFrom ? "SMTP_FROM" : "SMTP_USER (porque SMTP_FROM no esta puesto)";

  if (d === "") return { ok: false, motivo: "Falta la direccion del remitente: pon SMTP_FROM." };

  if (/[<>"]/.test(d)) {
    return {
      ok: false,
      motivo: `${origen} lleva un nombre o signos (< > o comillas). Pon SOLO la direccion, del tipo `
        + `nombre@dominio.com: el nombre que ve quien recibe ya lo pone el sistema.`,
    };
  }
  if (!/^[\x21-\x7E]+$/.test(d)) {
    return {
      ok: false,
      motivo: `${origen} lleva espacios, acentos o caracteres invisibles, casi siempre por haberla `
        + `pegado de un documento. Borrala y escribela a mano.`,
    };
  }
  if (!esCorreo(d.toLowerCase())) {
    return {
      ok: false,
      motivo: deFrom
        ? `SMTP_FROM no es una direccion de correo valida: tiene que ser del tipo nombre@dominio.com.`
        : `SMTP_FROM no esta puesto, y SMTP_USER no es una direccion de correo (es un nombre de `
          + `usuario). Agrega SMTP_FROM con la direccion completa de la cuenta.`,
    };
  }
  return { ok: true, direccion: d };
}

/// Si el puerto sirve desde una Edge Function de Supabase.
///
/// Supabase NO deja salir por el 25 ni por el 587 -«Outgoing connections to ports 25 and 587 are not
/// allowed», en sus limites de Edge Functions-. Sin esta comprobacion, configurar el 587, que es el
/// puerto habitual de envio, acabaria en una conexion que se queda colgada hasta el tiempo limite y un
/// error que no dice por que.
export function puertoPermitido(puerto: number): { ok: true } | { ok: false; motivo: string } {
  if (!Number.isInteger(puerto) || puerto < 1 || puerto > 65535) {
    return { ok: false, motivo: `El puerto «${puerto}» no es valido.` };
  }
  if (puerto === 25 || puerto === 587) {
    return {
      ok: false,
      motivo: `Supabase no permite salir por el puerto ${puerto}. Usa el 465 (SSL/TLS), que tu `
        + `servidor de correo deberia ofrecer para el envio.`,
    };
  }
  return { ok: true };
}
