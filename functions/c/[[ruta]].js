// Sirve el HTML de un artículo de Conocimientos con el tipo de contenido correcto. Responde en
// `/c/<ruta>`.
//
// Es la hermana de `functions/h/[[ruta]].js`, la de las herramientas, y existe por las MISMAS
// razones —están explicadas allí y no se repiten—:
//
//   * Supabase no puede entregar HTML: lo devuelve como `text/plain` con un `sandbox` encima.
//   * Se sirve en `herramientas.sistemassi.com`, otro ORIGEN que el de la aplicación, para que el
//     HTML subido no pueda leer el `localStorage` donde vive el token de sesión.
//   * No comprueba sesiones ni permisos: sólo acepta el `token` de una URL firmada que la aplicación
//     obtuvo pasando por las políticas de Storage. Esas políticas son las que deciden quién lo ve.
//
// ─── Por qué un archivo aparte y no un parámetro en el otro ──────────────────
//
// El bucket va FIJO en cada función. Si viniera en la dirección, cualquiera con un token cualquiera
// podría usar esto de puente para pedir otro bucket del proyecto. Una función por bucket mantiene
// esa garantía sin tener que pensarla dos veces.
//
// Se copió en lugar de compartir un módulo para no tocar la función de las herramientas, que está en
// uso en producción, por un cambio que no es suyo.

// Público de todos modos: viaja en el JavaScript compilado de la aplicación.
const STORAGE = "https://zkmbebybyyefmqcxjqrg.supabase.co";

const BUCKET = "conocimientos-html";

// Las mismas 8 horas que dura la firma que genera la aplicación.
const CACHE = "private, max-age=28800";

// Lo único que compone la página al subir: `<id del artículo>/<milisegundos>.html`.
const RUTA = /^[0-9a-f-]{36}\/\d{13}\.html$/i;

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

  // Se compone la dirección de Storage en lugar de aceptar una URL entera.
  const origen = `${STORAGE}/storage/v1/object/sign/${BUCKET}/${ruta}` +
    `?token=${encodeURIComponent(token)}`;

  let r;
  try {
    r = await fetch(origen, { method: "GET" });
  } catch (e) {
    return texto("No se pudo leer el archivo.", 502);
  }

  if (!r.ok) {
    if (r.status === 400 || r.status === 401) {
      return texto(
        "El enlace del archivo caducó. Cierra el visor y vuelve a abrirlo.",
        403,
      );
    }
    return texto("No se encontró el archivo.", 404);
  }

  const headers = new Headers({
    // SIN `charset`, al contrario que en las herramientas: estos archivos los exporta cada quien con
    // lo que tenga a mano, y Word guarda sus páginas web en windows-1252 con su propio
    // `<meta charset>`. Un `charset` en la cabecera le gana al del documento y rompería las tildes;
    // sin él manda el del archivo, y si no trae ninguno el navegador lo detecta.
    "Content-Type": "text/html",
    "Content-Disposition": "inline",
    "Cache-Control": CACHE,
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
  });
  const largo = r.headers.get("Content-Length");
  if (largo) headers.set("Content-Length", largo);

  return new Response(request.method === "HEAD" ? null : r.body, {
    status: 200,
    headers,
  });
}
