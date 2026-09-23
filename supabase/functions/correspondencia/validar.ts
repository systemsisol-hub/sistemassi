// Lo que decide si un mensaje se puede mandar, y como se escribe.
//
// Sin imports y sin efectos, a proposito: asi el arnes lo ejercita tal cual, sin copiar nada.
//
// ─── Por que la validacion vive en el servidor ───────────────────────────────
//
// La pantalla tambien valida, pero SOLO para avisar pronto. La que manda es esta: la funcion es la
// unica puerta hacia el servidor de correo, y una validacion que vive solo en la aplicacion la salta
// cualquiera que llame a la funcion directamente. Las dos usan la misma expresion y la misma tabla de
// casos en sus pruebas -ver `test/correspondencia_test.dart`- para que no se separen sin que nadie lo
// note.

/// Tope de destinatarios por mensaje.
///
/// El modulo puede escribir a CUALQUIER direccion, tambien externa -decision del usuario el
/// 23/09/2026-, asi que esto y el limite por hora son lo que impide que una cuenta con el permiso se
/// convierta en una fuente de envios masivos desde la cuenta de la empresa.
export const MAX_DESTINATARIOS = 50;

/// Mensajes por usuario en la ultima hora.
export const MAX_POR_HORA = 20;

export const MAX_ASUNTO = 200;
export const MAX_CUERPO = 20000;

/// Una direccion de correo razonable. No pretende cubrir todo el RFC 5322: pretende rechazar lo que
/// seguro esta mal -espacios, dos arrobas, sin dominio, caracteres que partirian una cabecera- y
/// dejar pasar todo lo que usa la gente de verdad.
///
/// La MISMA expresion esta en `lib/services/correspondencia.dart`.
const CORREO = /^[^\s@<>(),;:"\[\]\\]+@[^\s@<>(),;:"\[\]\\]+\.[A-Za-z]{2,}$/;

export function esCorreo(s: string): boolean {
  return CORREO.test(s);
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

export interface Mensaje {
  asunto: string;
  cuerpo: string;
  destinatarios: string[];
}

export type Validacion =
  | { ok: true; mensaje: Mensaje }
  | { ok: false; error: string; rechazados?: string[] };

/** Si el mensaje se puede mandar tal como viene. */
export function validarMensaje(entrada: unknown): Validacion {
  const e = (entrada ?? {}) as Record<string, unknown>;
  const asunto = typeof e.asunto === "string" ? e.asunto.trim() : "";
  const cuerpo = typeof e.cuerpo === "string" ? e.cuerpo.trim() : "";

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
  if (cuerpo === "") return { ok: false, error: "Falta el mensaje." };
  if (cuerpo.length > MAX_CUERPO) {
    return { ok: false, error: `El mensaje pasa de ${MAX_CUERPO} caracteres.` };
  }

  const { validos, rechazados } = normalizarDestinatarios(e.destinatarios);

  // Se rechaza el envio ENTERO si alguna direccion esta mal, en lugar de mandar a las buenas y
  // callarse las malas. Si no, alguien no recibe el correo y nadie se entera: quien lo mando cree
  // que salio a todos.
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
      error: `Son ${validos.length} destinatarios y el maximo por mensaje es ${MAX_DESTINATARIOS}.`,
    };
  }

  return { ok: true, mensaje: { asunto, cuerpo, destinatarios: validos } };
}

/// El nombre que se muestra como remitente: «Ana Lopez (via SISOL)».
///
/// Se limpian comillas, angulos y saltos de linea: ese texto va dentro de la cabecera `From`, y un
/// nombre con `">` o un salto de linea la romperia o permitiria colar otra direccion.
export function nombreRemitente(nombre: string): string {
  const limpio = nombre.replace(/[\r\n"<>\\]/g, " ").replace(/\s+/g, " ").trim().slice(0, 80);
  return limpio === "" ? "Sistema SISOL" : `${limpio} (via SISOL)`;
}

export function escaparHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/// El pie que dice de donde salio el correo. Va en los dos formatos.
///
/// Importa por la cuenta compartida: el correo sale de una direccion que no es la de quien escribe,
/// y sin esto quien lo recibe no sabe a quien contestarle si su cliente de correo ignora el
/// `Reply-To`.
function pie(remitente: string, responderA: string | null): string {
  return responderA
    ? `Enviado por ${remitente} desde el Sistema SISOL. Para contestar, escribe a ${responderA}.`
    : `Enviado por ${remitente} desde el Sistema SISOL.`;
}

export function cuerpoTexto(cuerpo: string, remitente: string, responderA: string | null): string {
  return `${cuerpo}\n\n--\n${pie(remitente, responderA)}`;
}

/// El cuerpo en HTML. TODO lo que escribio el usuario se escapa: el mensaje se pinta como texto,
/// nunca como marcado. Si no, cualquiera con el permiso podria mandar, desde la cuenta de la
/// empresa, un correo con enlaces o formularios disfrazados.
export function cuerpoHtml(cuerpo: string, remitente: string, responderA: string | null): string {
  const texto = escaparHtml(cuerpo).replace(/\r?\n/g, "<br>");
  return `<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5;color:#1f2330">`
    + `${texto}`
    + `<hr style="border:none;border-top:1px solid #dde0e8;margin:24px 0 12px">`
    + `<div style="font-size:12px;color:#6b7080">${escaparHtml(pie(remitente, responderA))}</div>`
    + `</div>`;
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
