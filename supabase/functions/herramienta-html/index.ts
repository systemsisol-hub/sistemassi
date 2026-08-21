// Sirve el HTML de una herramienta con el tipo de contenido correcto.
//
// ─── Por qué hace falta ──────────────────────────────────────────────────────
//
// Storage guarda el archivo con `mimetype: text/html` —se comprobó en `storage.objects`— pero al
// entregarlo neutraliza el tipo. Es una protección de la plataforma: si `*.supabase.co` sirviera
// HTML ejecutable subido por cualquiera, se podría alojar ahí una página para atacar a otros
// proyectos del mismo dominio. No es un ajuste del bucket, así que no se puede desactivar.
//
// El efecto en la aplicación era que el visor mostraba el CÓDIGO del cotizador en lugar de la
// herramienta. Un iframe pinta lo que dice la cabecera, así que el iframe no tenía nada que ver.
//
// ─── Por qué no se resolvió sin función ──────────────────────────────────────
//
// Las dos alternativas fáciles —meter el archivo en un blob dentro de la aplicación, o proxearlo por
// un Worker en el dominio propio— hacen que el HTML corra en el ORIGEN de sistemassi. Y ahí es donde
// `supabase_flutter` guarda el token de sesión en `localStorage`: sería darle a código que mantiene
// un tercero la capacidad de leerlo. Sirviéndolo desde `*.supabase.co` queda en otro origen, aislado.
//
// ─── Qué autoriza y qué no ───────────────────────────────────────────────────
//
// Esta función NO comprueba sesiones ni permisos, y es deliberado: no tiene llave de servicio y no
// puede leer nada por su cuenta. Lo único que acepta es el `token` de una URL firmada que la
// aplicación ya generó, y las URL firmadas sólo se pueden generar pasando por las políticas del
// bucket. La autorización queda en un solo lugar —RLS y las políticas de Storage— en lugar de
// reimplementarse aquí.
//
// Consecuencia buscada: el token que va en la dirección es inofensivo si la propia herramienta lo
// lee con `location.search`. Sólo sirve para volver a pedir el archivo que ya tiene delante, durante
// las horas que dure la firma. Un JWT de sesión en la dirección sí habría sido un problema, y por eso
// no se usa.
//
// El bucket va fijo en el código. Si viniera por parámetro, esto sería un proxy abierto a cualquier
// bucket del proyecto para quien tuviese un token cualquiera.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";

const BUCKET = "herramientas";

// Ocho horas, las mismas que dura la firma que genera la aplicación. Sin esto Storage manda su
// `max-age=3600` por omisión y el navegador revalida varios MB cada hora sin necesidad.
const CACHE = "private, max-age=28800";

/// Rutas admitidas: `<uuid>/v<n>.html`, que es lo que compone la página al subir una versión.
///
/// Se valida con una expresión y no sólo descartando `..` porque el objetivo no es filtrar lo que se
/// nos ocurra que puede venir mal, sino aceptar únicamente lo que sabemos que es correcto.
const RUTA = /^[0-9a-f-]{36}\/v[0-9]+\.html$/i;

function texto(mensaje: string, status: number): Response {
  return new Response(mensaje, {
    status,
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return texto("Sólo GET.", 405);
  }
  if (!SUPABASE_URL) {
    return texto("Falta SUPABASE_URL en el entorno de la función.", 503);
  }

  const params = new URL(req.url).searchParams;
  const path = params.get("path") ?? "";
  const token = params.get("token") ?? "";

  if (!RUTA.test(path)) return texto("Ruta no válida.", 400);
  if (!token) return texto("Falta el token de la URL firmada.", 400);

  // Se reconstruye la dirección de Storage en lugar de aceptar una URL completa: recibir la URL
  // convertiría esto en un puente para pedirle cualquier cosa a cualquier servidor desde dentro de
  // la infraestructura.
  const origen = `${SUPABASE_URL}/storage/v1/object/sign/${BUCKET}/${path}` +
    `?token=${encodeURIComponent(token)}`;

  let r: Response;
  try {
    r = await fetch(origen, { method: "GET" });
  } catch (e) {
    console.error("No se pudo leer el objeto:", e instanceof Error ? e.message : String(e));
    return texto("No se pudo leer el archivo de la herramienta.", 502);
  }

  // Una firma caducada o de otro objeto la rechaza Storage, no esta función. Se reenvía el código
  // para que en la aplicación se distinga «caducó» de «no existe».
  if (!r.ok) {
    console.warn(`Storage respondió ${r.status} para ${path}`);
    return texto(
      r.status === 400 || r.status === 401
        ? "El enlace de la herramienta caducó. Cierra el visor y vuelve a abrirla."
        : "No se encontró el archivo de la herramienta.",
      r.status === 404 ? 404 : 403,
    );
  }

  const headers = new Headers({
    // El punto de todo el ejercicio.
    "Content-Type": "text/html; charset=utf-8",
    "Content-Disposition": "inline",
    "Cache-Control": CACHE,
    // Con el tipo ya declarado bien, esto evita que el navegador intente adivinar otro.
    "X-Content-Type-Options": "nosniff",
  });
  const largo = r.headers.get("Content-Length");
  if (largo) headers.set("Content-Length", largo);

  // Se devuelve el cuerpo tal cual, sin juntarlo en memoria: son archivos de varios MB y la versión
  // anterior de este cotizador pesaba 13 MB.
  return new Response(req.method === "HEAD" ? null : r.body, { status: 200, headers });
});
