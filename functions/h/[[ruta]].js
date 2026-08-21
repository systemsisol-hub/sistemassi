// Sirve el HTML de una herramienta con el tipo de contenido correcto.
//
// Vive en `functions/` de la raíz porque es una Pages Function: Cloudflare la recoge y la despliega
// con el mismo `git push` que compila la aplicación, sin un paso aparte. Responde en `/h/<ruta>`.
//
// ─── Por qué existe ──────────────────────────────────────────────────────────
//
// El archivo se guarda en Storage, pero Supabase no lo puede ENTREGAR. Se comprobó pidiéndolo:
// devuelve `Content-Type: text/plain` —sobrescribiendo el que se declare— y añade una
// `Content-Security-Policy: default-src 'none'; sandbox`. Es una protección de la plataforma para
// que nadie aloje HTML ejecutable en `*.supabase.co`, y vale igual para Storage y para las Edge
// Functions. El primer intento fue una Edge Function que declaraba `text/html`; no sirvió, la
// pasarela la sobrescribe. Por eso esto está en Cloudflare y no allí.
//
// El síntoma era que el visor mostraba el CÓDIGO del cotizador. Un iframe pinta lo que dice la
// cabecera, así que el iframe nunca tuvo nada que ver.
//
// ─── Por qué en otro nombre de host ──────────────────────────────────────────
//
// Se sirve en `herramientas.sistemassi.com`, no en `sistemassi.com`. Un host distinto es un ORIGEN
// distinto, y eso es lo que impide que el HTML del proveedor lea el `localStorage` de sistemassi,
// donde `supabase_flutter` guarda el token de sesión. Hoy ese archivo no hace ninguna llamada de
// red, pero se sustituye en cada entrega y nadie audita cada una.
//
// Se intentó antes la vía sin subdominio: mismo host y un iframe con
// `sandbox="allow-scripts allow-downloads allow-popups"` sin `allow-same-origin`, que en teoría da
// un origen opaco con las descargas y las ventanas nuevas intactas. Medido en Chromium, el iframe
// sandboxeado NI SIQUIERA PIDIÓ el documento; el mismo iframe sin `sandbox` lo cargó y el cotizador
// funcionó. Así que el aislamiento viene del origen y no de un atributo.
//
// ─── Qué autoriza y qué no ───────────────────────────────────────────────────
//
// Esto NO comprueba sesiones ni permisos, y es deliberado: no tiene ninguna llave, así que no puede
// leer nada por su cuenta. Lo único que acepta es el `token` de una URL firmada que la aplicación ya
// generó, y ésas sólo se obtienen pasando por RLS y por las políticas de Storage. La autorización se
// queda en un solo sitio en lugar de reimplementarse aquí.
//
// Consecuencia buscada: el token que va en la dirección es inofensivo si la propia herramienta lo
// lee. Sólo sirve para volver a pedir el archivo que ya tiene delante, y caduca con la firma. Un JWT
// de sesión ahí sí habría sido un problema, y por eso no se usa.

// El origen de Storage va fijo. Ya es público —viaja en el JavaScript compilado de la aplicación— y
// tenerlo aquí evita una variable de entorno más que alguien tenga que acordarse de configurar en el
// proyecto de Pages para que esto no se caiga en silencio.
const STORAGE = "https://zkmbebybyyefmqcxjqrg.supabase.co";

// El bucket va fijo por seguridad: si viniera por parámetro, esto sería un puente para pedir
// cualquier bucket del proyecto a quien tuviera un token cualquiera.
const BUCKET = "herramientas";

// Las mismas 8 horas que dura la firma que genera la aplicación. Sin esto llegaría el `max-age` de
// Storage y el navegador revalidaría varios MB antes de tiempo.
const CACHE = "private, max-age=28800";

// Lo único que compone la página al subir una versión: `<uuid>/v<n>.html`. Se acepta sólo esa forma
// en lugar de intentar filtrar lo que se nos ocurra que puede venir mal.
const RUTA = /^[0-9a-f-]{36}\/v\d+\.html$/i;

function texto(mensaje, status) {
  return new Response(mensaje, {
    status,
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}

export async function onRequest({ request, params }) {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return texto("Sólo GET.", 405);
  }

  const ruta = Array.isArray(params.ruta)
    ? params.ruta.join("/")
    : String(params.ruta ?? "");
  if (!RUTA.test(ruta)) return texto("Ruta no válida.", 400);

  const token = new URL(request.url).searchParams.get("token");
  if (!token) return texto("Falta el token de la URL firmada.", 400);

  // Se compone la dirección de Storage en lugar de aceptar una URL entera: recibirla convertiría
  // esto en un puente para pedirle cualquier cosa a cualquier servidor.
  const origen = `${STORAGE}/storage/v1/object/sign/${BUCKET}/${ruta}` +
    `?token=${encodeURIComponent(token)}`;

  let r;
  try {
    r = await fetch(origen, { method: "GET" });
  } catch (e) {
    return texto("No se pudo leer el archivo de la herramienta.", 502);
  }

  // Una firma caducada o de otro objeto la rechaza Storage, no esto. Se distingue para que en la
  // aplicación se lea «caducó» y no «no existe», que llevan a acciones distintas.
  if (!r.ok) {
    if (r.status === 400 || r.status === 401) {
      return texto(
        "El enlace de la herramienta caducó. Cierra el visor y vuelve a abrirla.",
        403,
      );
    }
    return texto("No se encontró el archivo de la herramienta.", 404);
  }

  const headers = new Headers({
    // El punto de todo el ejercicio.
    "Content-Type": "text/html; charset=utf-8",
    "Content-Disposition": "inline",
    "Cache-Control": CACHE,
    "X-Content-Type-Options": "nosniff",
    // No se hereda de este host nada que sirva para navegar a otra parte del sistema.
    "Referrer-Policy": "no-referrer",
  });
  const largo = r.headers.get("Content-Length");
  if (largo) headers.set("Content-Length", largo);

  // Se devuelve el cuerpo tal cual, sin juntarlo en memoria: son archivos de varios MB —la primera
  // versión de este cotizador pesaba 13 MB, la actual 6.4—.
  return new Response(request.method === "HEAD" ? null : r.body, {
    status: 200,
    headers,
  });
}
