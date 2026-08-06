// Importa el reporte de checadas de appchecar.com a `checador_registros`.
//
// ─── Por qué el parser vive en el servidor ────────────────────────────────────
//
// Las reglas de normalización deciden si un registro se une o no a su empleado y a su horario.
// Equivocarse no produce un error visible: produce un dashboard que simplemente omite gente. Por
// eso viven en un solo lugar, del lado del servidor, y no repartidas en el cliente.
//
// ─── Lo que el archivo real enseñó ───────────────────────────────────────────
//
// 1. El ".xls" es HTML, no Excel: empieza con BOM UTF-8 y un <table>. Se parsea como HTML.
//
// 2. La columna `Diferencia` NO sirve para saber quién llegó tarde. Es un valor absoluto sin
//    signo: "4 min" se ve idéntico si la persona llegó 4 minutos antes o 4 minutos tarde. El
//    retardo se calcula en la vista `checador_entradas` contra nuestra tabla `schedules`.
//
// 3. El signo que le falta al texto sí viaja en el reporte, pero en el COLOR de la celda: verde
//    a tiempo, rojo fuera de tiempo. Se guarda en `retardo_reportado` para poder contrastar el
//    veredicto de appchecar contra el nuestro. En el periodo de julio appchecar marcó 105
//    entradas fuera de tiempo y nuestro cálculo dio 107: la diferencia es configuración de
//    horarios distinta entre los dos sistemas, y conviene que sea medible en lugar de invisible.
//
// 4. Los números de empleado traen ceros iniciales de forma inconsistente en AMBOS lados (el
//    reporte trae '0162' y '170'; profiles trae 1000 de 2488 con ceros). Se normalizan los dos.
//
// 5. Tres de los 18 nombres de horario traen espacios dobles ('Punta Pacifico  L-S'). Sin
//    normalizar espacios, esos tres horarios no se unen.
//
// 6. Hay al menos un empleado SIN número (Moises Caldera Meza, 26 registros). Por eso la
//    identidad cae al nombre — ver la columna generada `clave` en la migración.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

/// Tope de seguridad. El reporte de 15 días trae 877 filas; 50 mil cubre con holgura un año
/// entero y evita que un archivo equivocado agote la memoria de la función.
const MAX_FILAS = 50_000;

/// Debe quedar por debajo del tope de filas de PostgREST (`db_max_rows`, 1000 por omisión).
const CHUNK = 500;

/// Trae una tabla completa, paginando.
///
/// Existe por un error real: la primera versión hacía `select()` sin paginar sobre `profiles`.
/// PostgREST corta la respuesta en 1000 filas y **no devuelve error**, así que de los 2488
/// perfiles llegaron 1000 y los 16 empleados que vivían en las posiciones 1178 a 2482 quedaron
/// sin `profile_id`. Se vio porque el resumen del import los enumeró; sin ese resumen habrían
/// quedado desvinculados en silencio.
///
/// El orden por `id` no es cosmético: paginar por rangos sin un orden total estable puede repetir
/// u omitir filas entre páginas.
async function traerTodo(
  db: ReturnType<typeof createClient>,
  tabla: string,
  columnas: string,
): Promise<Record<string, unknown>[]> {
  const filas: Record<string, unknown>[] = [];
  for (let desde = 0; ; desde += CHUNK) {
    const { data, error } = await db
      .from(tabla)
      .select(columnas)
      .order("id")
      .range(desde, desde + CHUNK - 1);
    if (error) throw new Error(`No se pudo leer ${tabla}: ${error.message}`);
    filas.push(...(data ?? []) as Record<string, unknown>[]);
    if ((data?.length ?? 0) < CHUNK) return filas;
  }
}

// ── Normalización ────────────────────────────────────────────────────────────

/// Colapsa espacios repetidos y recorta. Es lo que hace empatar los nombres de horario con
/// espacios dobles.
const espacios = (s: string) => s.replace(/\s+/g, " ").trim();

/// Sin ceros iniciales. '0162' y '162' son el mismo empleado, y cada lado los escribe distinto.
/// Se verificó que quitar ceros no crea colisiones: los 2488 perfiles siguen siendo distintos.
const numEmpleado = (s: string) => espacios(s).replace(/^0+/, "");

/// Sin acentos además de sin mayúsculas: el reporte de incidencias escribe «DIAZ SANCHEZ» donde
/// profiles tiene «DÍAZ SÁNCHEZ», y sin esto esa persona no empataría. Se verificó que quitarlos no
/// crea ambigüedades: los nombres de los 2488 perfiles siguen siendo únicos con y sin acentos.
const claveNombre = (s: string) =>
  espacios(s).toLowerCase().replace(/[áàäâ]/g, "a").replace(/[éèëê]/g, "e")
    .replace(/[íìïî]/g, "i").replace(/[óòöô]/g, "o").replace(/[úùüû]/g, "u")
    .replace(/ñ/g, "n");
const claveHorario = (s: string) => espacios(s).toLowerCase();

const MESES: Record<string, number> = {
  // El reporte de julio trae los meses en inglés abreviado, aunque el resto esté en español.
  // Se aceptan ambos idiomas porque appchecar podría cambiar de locale sin avisar.
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
  jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
  ene: 1, abr: 4, ago: 8, set: 9, dic: 12,
};

/// '16-Jul-2026' → '2026-07-16'. Devuelve null si no reconoce el formato, para que la fila se
/// cuente como omitida en lugar de entrar con una fecha inventada.
function parseFecha(raw: string): string | null {
  const m = espacios(raw).match(/^(\d{1,2})[-/\s]([A-Za-zÁ-úá-ú]{3,})[-/\s](\d{4})$/);
  if (m) {
    const mes = MESES[m[2].slice(0, 3).toLowerCase()];
    if (!mes) return null;
    return `${m[3]}-${String(mes).padStart(2, "0")}-${m[1].padStart(2, "0")}`;
  }
  // Respaldo por si algún día exporta ISO o dd/mm/yyyy numérico.
  const iso = espacios(raw).match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (iso) return iso[0];
  const dmy = espacios(raw).match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$/);
  if (dmy) {
    return `${dmy[3]}-${dmy[2].padStart(2, "0")}-${dmy[1].padStart(2, "0")}`;
  }
  return null;
}

/// '7:02' → '07:02:00'. El reporte omite el cero inicial en 477 de 877 filas.
function parseHora(raw: string): string | null {
  const m = espacios(raw).match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/);
  if (!m) return null;
  const h = Number(m[1]), min = Number(m[2]), s = Number(m[3] ?? "0");
  if (h > 23 || min > 59 || s > 59) return null;
  return `${String(h).padStart(2, "0")}:${String(min).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

/// El signo del retardo, leído del color de la celda `Diferencia`.
///
/// Se compara rojo contra verde en lugar de buscar los hex exactos (#ee6082 / #4fc725): así
/// sigue funcionando si appchecar ajusta su paleta. Sin color, o con el negro que acompaña a
/// "---", devuelve null: no sabemos, y eso es distinto de llegar a tiempo.
function retardoPorColor(estilo: string, texto: string): boolean | null {
  if (espacios(texto).replace(/-/g, "") === "") return null;
  const m = estilo.match(/color:\s*#([0-9a-fA-F]{6})/);
  if (!m) return null;
  const r = parseInt(m[1].slice(0, 2), 16);
  const v = parseInt(m[1].slice(2, 4), 16);
  if (r === v) return null;
  return r > v;
}

// ── Parseo del HTML ──────────────────────────────────────────────────────────

const ENTIDADES: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ",
};

function textoDeCelda(html: string): string {
  return espacios(
    html
      .replace(/<[^>]*>/g, "")
      .replace(/&#(\d+);/g, (_, d) => String.fromCharCode(Number(d)))
      .replace(/&([a-zA-Z]+);/g, (todo, name) => ENTIDADES[name.toLowerCase()] ?? todo),
  );
}

interface Celda {
  estilo: string;
  texto: string;
}

function filasDelHtml(html: string): Celda[][] {
  const filas: Celda[][] = [];
  const trRe = /<tr\b[^>]*>([\s\S]*?)<\/tr>/gi;
  const tdRe = /<(t[dh])\b([^>]*)>([\s\S]*?)<\/\1>/gi;
  for (const tr of html.matchAll(trRe)) {
    const celdas: Celda[] = [];
    for (const td of tr[1].matchAll(tdRe)) {
      celdas.push({ estilo: td[2], texto: textoDeCelda(td[3]) });
    }
    if (celdas.length > 0) filas.push(celdas);
  }
  return filas;
}

/// Columnas esperadas, mapeadas por NOMBRE de encabezado y no por posición: si appchecar
/// reordena o inserta una columna, un parser posicional leería los datos corridos sin fallar.
const COLUMNAS = {
  departamento: "departamento",
  numero: "no. empleado",
  puesto: "puesto",
  nombre: "nombre completo",
  fecha: "fecha",
  tipo: "registro",
  hora: "hora",
  diferencia: "diferencia",
  horario: "horario",
  direccion: "dirección",
  sucursal: "sucursal",
  registroCon: "registro con",
} as const;

type MapaCols = Partial<Record<keyof typeof COLUMNAS, number>>;

function buscarEncabezado(filas: Celda[][]): { indice: number; cols: MapaCols } | null {
  for (let i = 0; i < filas.length; i++) {
    const etiquetas = filas[i].map((c) => c.texto.toLowerCase());
    if (!etiquetas.includes(COLUMNAS.fecha) || !etiquetas.includes(COLUMNAS.hora)) continue;
    const cols: MapaCols = {};
    for (const [clave, etiqueta] of Object.entries(COLUMNAS)) {
      const idx = etiquetas.indexOf(etiqueta);
      if (idx >= 0) cols[clave as keyof typeof COLUMNAS] = idx;
    }
    // Sin estas cuatro no hay registro que valga la pena guardar.
    if (cols.fecha === undefined || cols.hora === undefined ||
        cols.tipo === undefined || cols.nombre === undefined) continue;
    return { indice: i, cols };
  }
  return null;
}

// ── Reporte de Incidencias: faltas justificadas ──────────────────────────────
//
// appchecar exporta un segundo reporte con los días justificados. Trae seis columnas, pero sólo
// tres significan algo: Fecha, Trabajador y Motivo. Hora, Registro y Dirección son informativas
// —muestran la hora del horario, no una checada— porque en esos días la persona NO checó.

const COLUMNAS_INC = {
  fecha: "fecha",
  trabajador: "trabajador",
  motivo: "motivo",
} as const;

type MapaInc = Partial<Record<keyof typeof COLUMNAS_INC, number>>;

/// Se busca antes que el de checadas porque es más específico: si aparecen «trabajador» y
/// «motivo», no hay duda de qué reporte es.
function buscarEncabezadoIncidencias(
  filas: Celda[][],
): { indice: number; cols: MapaInc } | null {
  for (let i = 0; i < filas.length; i++) {
    const etiquetas = filas[i].map((c) => c.texto.toLowerCase());
    const cols: MapaInc = {};
    for (const [clave, etiqueta] of Object.entries(COLUMNAS_INC)) {
      const idx = etiquetas.indexOf(etiqueta);
      if (idx >= 0) cols[clave as keyof typeof COLUMNAS_INC] = idx;
    }
    if (cols.fecha === undefined || cols.trabajador === undefined ||
        cols.motivo === undefined) continue;
    return { indice: i, cols };
  }
  return null;
}

/// Los motivos vienen escritos a mano y sin criterio: 'Falla APP', 'Falla App', 'falla App' y
/// 'PROBLEMA CON LA APP' son el mismo. Se clasifica por palabra clave y **se conserva el texto
/// original**, porque varios son explicaciones de una sola vez que ninguna categoría resume sin
/// perder información.
function clasificarMotivo(motivo: string): string {
  const m = motivo.toUpperCase();
  if (m.includes("INCAPACID")) return "INCAPACIDAD";
  if (m.includes("VACACION")) return "VACACIONES";
  if (m.includes("APP")) return "FALLA_APP";
  if (m.includes("PERMISO")) return "PERMISO";
  return "OTRO";
}

/// Carga las faltas justificadas. Una fila por persona y día, no por checada: el archivo repite el
/// motivo en el renglón de entrada y en el de salida.
async function importarIncidencias(
  db: ReturnType<typeof createClient>,
  filas: Celda[][],
  enc: { indice: number; cols: MapaInc },
  porNombre: Map<string, string | null>,
  perfilesLeidos: number,
  archivo: string | null,
  usuarioId: string,
): Promise<Response> {
  const { indice, cols } = enc;
  const txt = (f: Celda[], k: keyof typeof COLUMNAS_INC) =>
    espacios((cols[k] !== undefined ? f[cols[k]!]?.texto : "") ?? "");

  // Clave persona-día → fila. El motivo se guarda una vez; si el archivo lo trae escrito distinto
  // en las dos filas del mismo día —el 30 de julio venía «hospilizado» y «hospitalizado»— se
  // conserva el texto más largo, que es el más completo.
  const porDia = new Map<string, Record<string, unknown>>();
  const sinPerfil = new Map<string, string>();
  const ambiguos = new Set<string>();
  const motivosVistos = new Map<string, number>();
  let omitidas = 0;
  let minFecha: string | null = null;
  let maxFecha: string | null = null;

  for (let i = indice + 1; i < filas.length; i++) {
    const f = filas[i];
    const fecha = parseFecha(txt(f, "fecha"));
    const nombre = txt(f, "trabajador");
    const motivo = txt(f, "motivo");

    // Las filas de relleno del reporte no cuentan como omitidas: sólo lo que parecía una
    // justificación y no se pudo leer.
    if (!fecha && !nombre) continue;
    if (!fecha || !nombre) {
      omitidas++;
      continue;
    }

    const tipo = clasificarMotivo(motivo);
    motivosVistos.set(tipo, (motivosVistos.get(tipo) ?? 0) + 1);

    // El archivo NO trae número de empleado. Se resuelve por nombre completo exacto y sólo si es
    // único: `porNombre` guarda null cuando dos perfiles comparten nombre, así que un nombre
    // ambiguo se reporta en lugar de justificarle el día a la persona equivocada.
    const clave = claveNombre(nombre);
    const perfil = porNombre.get(clave) ?? null;
    if (perfil === null) {
      if (porNombre.has(clave)) ambiguos.add(nombre);
      else sinPerfil.set(clave, nombre);
    }

    if (!minFecha || fecha < minFecha) minFecha = fecha;
    if (!maxFecha || fecha > maxFecha) maxFecha = fecha;

    const llave = `${perfil ?? `n:${clave}`}|${fecha}`;
    const previo = porDia.get(llave);
    if (previo && String(previo.motivo ?? "").length >= motivo.length) continue;
    porDia.set(llave, {
      profile_id: perfil,
      nombre_reporte: nombre,
      fecha,
      motivo: motivo || null,
      motivo_tipo: tipo,
    });
  }

  const justificaciones = [...porDia.values()];
  if (justificaciones.length === 0 || !minFecha || !maxFecha) {
    return reply({
      error: "Se reconoció el reporte de incidencias, pero ninguna fila tenía fecha y trabajador " +
        "legibles. No se guardó nada.",
      filas_omitidas: omitidas,
    }, 422);
  }

  // Cuántas son nuevas, calculado ANTES del upsert, igual que en el reporte de checadas: es lo que
  // permite comprobar la idempotencia.
  const yaExisten = new Set<string>();
  for (let desde = 0; ; desde += CHUNK) {
    const { data, error } = await db
      .from("checador_justificaciones")
      .select("clave_persona, fecha")
      .gte("fecha", minFecha)
      .lte("fecha", maxFecha)
      .order("id")
      .range(desde, desde + CHUNK - 1);
    if (error) throw new Error(`No se pudo leer lo ya justificado: ${error.message}`);
    for (const r of data ?? []) yaExisten.add(`${r.clave_persona}|${r.fecha}`);
    if ((data?.length ?? 0) < CHUNK) break;
  }
  const nuevas = justificaciones.filter((j) => {
    const cp = j.profile_id
      ? `id:${j.profile_id}`
      : `nombre:${claveNombre(String(j.nombre_reporte ?? ""))}`;
    return !yaExisten.has(`${cp}|${j.fecha}`);
  }).length;

  const sinEmpatar = {
    empleados: [...sinPerfil.values()].map((n) => ({ numero: "sin número", nombre: n })),
    horarios: [] as string[],
    ambiguos: [...ambiguos],
  };

  const { data: imp, error: impErr } = await db
    .from("checador_importaciones")
    .insert({
      archivo,
      fecha_inicio: minFecha,
      fecha_fin: maxFecha,
      filas_leidas: justificaciones.length,
      filas_nuevas: nuevas,
      importado_por: usuarioId,
      sin_empatar: sinEmpatar,
    })
    .select("id")
    .single();
  if (impErr) throw new Error(`No se pudo registrar la importación: ${impErr.message}`);

  for (let i = 0; i < justificaciones.length; i += CHUNK) {
    const lote = justificaciones.slice(i, i + CHUNK)
      .map((j) => ({ ...j, importacion_id: imp.id }));
    const { error } = await db
      .from("checador_justificaciones")
      .upsert(lote, { onConflict: "clave_persona,fecha" });
    if (error) {
      throw new Error(
        `Falló al guardar el lote ${i / CHUNK + 1}: ${error.message}. ` +
          `Se guardaron ${i} de ${justificaciones.length} justificaciones.`,
      );
    }
  }

  return reply({
    ok: true,
    tipo: "incidencias",
    importacion_id: imp.id,
    archivo,
    periodo: {
      inicio: minFecha,
      fin: maxFecha,
      dias: new Set(justificaciones.map((j) => j.fecha)).size,
    },
    filas: {
      leidas: justificaciones.length,
      nuevas,
      actualizadas: justificaciones.length - nuevas,
      omitidas,
    },
    personas: new Set(justificaciones.map((j) => j.nombre_reporte)).size,
    motivos: Object.fromEntries(motivosVistos),
    sin_empatar: sinEmpatar,
    catalogos: { perfiles: perfilesLeidos, horarios: 0 },
  });
}

// ── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const auth = req.headers.get("Authorization");
    if (!auth) return reply({ error: "No authorization" }, 401);

    const db = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data: { user }, error: authErr } =
      await db.auth.getUser(auth.replace("Bearer ", ""));
    if (authErr || !user) return reply({ error: "Unauthorized" }, 401);

    // Sólo administradores. Mismo criterio que la escritura en `schedules`: cargar un reporte
    // reescribe el histórico de asistencia de toda la empresa.
    const { data: prof } = await db
      .from("profiles").select("role").eq("id", user.id).single();
    if (prof?.role !== "admin") {
      return reply({ error: "Sólo un administrador puede cargar el reporte del checador." }, 403);
    }

    const body = await req.json() as { archivo?: unknown; contenido_base64?: unknown };
    if (typeof body.contenido_base64 !== "string" || body.contenido_base64.length === 0) {
      return reply({ error: "Falta contenido_base64 con el archivo del reporte." }, 400);
    }
    const archivo = typeof body.archivo === "string" ? body.archivo : null;

    let html: string;
    try {
      const bytes = Uint8Array.from(atob(body.contenido_base64), (ch) => ch.charCodeAt(0));
      // fatal:false y no true: un acento mal codificado no debe tumbar el import completo.
      html = new TextDecoder("utf-8").decode(bytes).replace(/^﻿/, "");
    } catch {
      return reply({ error: "El contenido no es base64 válido." }, 400);
    }

    const filas = filasDelHtml(html);

    // El reporte de Incidencias se detecta primero porque su encabezado es más específico: con
    // «Trabajador» y «Motivo» presentes no hay ambigüedad sobre cuál de los dos archivos es. Así
    // el usuario sube los dos por el mismo botón sin tener que elegir el tipo.
    const encIncidencias = buscarEncabezadoIncidencias(filas);

    const encabezado = encIncidencias ? null : buscarEncabezado(filas);
    if (!encIncidencias && !encabezado) {
      return reply({
        error: "No se reconoció el reporte. Se esperaba el de checadas (columnas 'Fecha', " +
          "'Hora', 'Registro', 'Nombre Completo') o el de incidencias (columnas 'Fecha', " +
          "'Trabajador', 'Motivo'), exportados como .xls desde appchecar.",
      }, 422);
    }

    // ── Catálogos para resolver las uniones ──────────────────────────────────

    const horarios = encIncidencias ? [] : await traerTodo(db, "schedules", "id, name");
    const porHorario = new Map<string, string>();
    for (const h of horarios) {
      porHorario.set(claveHorario(String(h.name)), String(h.id));
    }

    const perfiles = await traerTodo(
      db, "profiles", "id, numero_empleado, nombre, paterno, materno, full_name");
    const porNumero = new Map<string, string>();
    // El respaldo por nombre sólo se usa si el nombre es ÚNICO. 'MOISES' aparece 5 veces en
    // profiles, así que emparejar por nombre de pila sería asignarle checadas a otra persona.
    const porNombre = new Map<string, string | null>();

    /// Sólo marca ambiguo cuando la misma clave apunta a otra PERSONA. Marcarlo al primer repetido
    /// anularía casi todo, porque cada perfil registra dos claves que suelen ser idénticas.
    const registrarNombre = (clave: string, id: string) => {
      if (!clave) return;
      const previo = porNombre.get(clave);
      if (previo === undefined) porNombre.set(clave, id);
      else if (previo !== id) porNombre.set(clave, null);
    };

    for (const p of perfiles) {
      const n = numEmpleado(String(p.numero_empleado ?? ""));
      if (n) porNumero.set(n, String(p.id));

      const id = String(p.id);
      registrarNombre(claveNombre(String(p.full_name ?? "")), id);
      // También el nombre armado con los componentes: 24 de los 2488 perfiles tienen `full_name`
      // desfasado de nombre+paterno+materno. El caso que lo destapó: el perfil 0163 guarda
      // materno 'ESCOBAR' pero su full_name dice sólo «ANGEL ANTONIO VARGAS», así que su
      // justificación del 30 de julio no se podía pegar y ese día seguía contando como puntual.
      registrarNombre(
        claveNombre([p.nombre, p.paterno, p.materno]
          .map((x) => String(x ?? "").trim()).filter((x) => x.length > 0).join(" ")),
        id,
      );
    }

    // ── Reporte de Incidencias ───────────────────────────────────────────────

    if (encIncidencias) {
      return await importarIncidencias(
        db, filas, encIncidencias, porNombre, perfiles.length, archivo, user.id);
    }

    const { indice, cols } = encabezado!;

    // ── Recorrido de las filas ───────────────────────────────────────────────

    const cel = (f: Celda[], k: keyof typeof COLUMNAS): Celda =>
      (cols[k] !== undefined ? f[cols[k]!] : undefined) ?? { estilo: "", texto: "" };

    const registros: Record<string, unknown>[] = [];
    const empleadosSinEmpatar = new Map<string, string>();
    const horariosSinEmpatar = new Set<string>();
    const claves = new Set<string>();
    let omitidas = 0;
    let entradas = 0;
    let salidas = 0;
    let minFecha: string | null = null;
    let maxFecha: string | null = null;

    for (let i = indice + 1; i < filas.length; i++) {
      const f = filas[i];
      if (registros.length >= MAX_FILAS) break;

      const fecha = parseFecha(cel(f, "fecha").texto);
      const hora = parseHora(cel(f, "hora").texto);
      const tipoRaw = cel(f, "tipo").texto.toLowerCase();
      const tipo = tipoRaw.startsWith("entrada")
        ? "Entrada"
        : tipoRaw.startsWith("salida")
        ? "Salida"
        : null;

      // Las filas de encabezado del reporte (empresa, dirección, celdas vacías) caen aquí sin
      // contarse como omitidas: sólo cuenta lo que parecía un registro y no se pudo leer.
      if (!fecha && !hora && !tipo) continue;
      if (!fecha || !hora || !tipo) {
        omitidas++;
        continue;
      }

      const numero = numEmpleado(cel(f, "numero").texto);
      const nombre = espacios(cel(f, "nombre").texto);
      const horarioNombre = espacios(cel(f, "horario").texto);
      const diferencia = cel(f, "diferencia");

      let profileId = numero ? porNumero.get(numero) ?? null : null;
      if (!profileId && nombre) {
        // Respaldo por nombre exacto y único. Recupera al empleado que appchecar exporta sin
        // número; si el nombre fuera ambiguo, `porNombre` guarda null y no se asigna nada.
        profileId = porNombre.get(claveNombre(nombre)) ?? null;
      }
      if (!profileId) {
        empleadosSinEmpatar.set(numero || `sin número: ${nombre}`, nombre);
      }

      const horarioId = horarioNombre ? porHorario.get(claveHorario(horarioNombre)) ?? null : null;
      if (horarioNombre && !horarioId) horariosSinEmpatar.add(horarioNombre);

      // El archivo trae duplicados exactos en algunos casos; con la misma llave, el upsert los
      // colapsaría, pero Postgres rechaza un ON CONFLICT con la fila repetida dentro del mismo
      // comando. Se descartan aquí.
      const clave = `${numero ? `num:${numero}` : `nombre:${claveNombre(nombre)}`}|${fecha}|${tipo}|${hora}`;
      if (claves.has(clave)) {
        omitidas++;
        continue;
      }
      claves.add(clave);

      if (tipo === "Entrada") entradas++;
      else salidas++;
      if (!minFecha || fecha < minFecha) minFecha = fecha;
      if (!maxFecha || fecha > maxFecha) maxFecha = fecha;

      registros.push({
        numero_empleado: numero,
        nombre_reporte: nombre || null,
        profile_id: profileId,
        fecha,
        tipo,
        hora,
        diferencia_reportada: diferencia.texto || null,
        retardo_reportado: retardoPorColor(diferencia.estilo, diferencia.texto),
        horario_nombre: horarioNombre || null,
        horario_id: horarioId,
        departamento: cel(f, "departamento").texto || null,
        puesto: cel(f, "puesto").texto || null,
        direccion: cel(f, "direccion").texto || null,
        sucursal: cel(f, "sucursal").texto || null,
        registro_con: cel(f, "registroCon").texto || null,
      });
    }

    if (registros.length === 0 || !minFecha || !maxFecha) {
      return reply({
        error: "Se encontró la tabla pero ninguna fila tenía fecha, hora y tipo de registro " +
          "legibles. No se guardó nada.",
        filas_omitidas: omitidas,
      }, 422);
    }

    // ── Cuántas son realmente nuevas ─────────────────────────────────────────
    //
    // Se calcula ANTES del upsert. Es lo que permite verificar la idempotencia: volver a subir el
    // mismo archivo debe reportar 0 nuevas.
    const yaExisten = new Set<string>();
    // Se pagina hasta agotar lo que ya hay en el rango de fechas, que no tiene relación con
    // cuántas filas trae el archivo.
    for (let desde = 0; ; desde += CHUNK) {
      const { data, error } = await db
        .from("checador_registros")
        .select("clave, fecha, tipo, hora")
        .gte("fecha", minFecha)
        .lte("fecha", maxFecha)
        // Orden por `id` y no por `clave`: la paginación por rangos necesita un orden total
        // estable, y `clave` se repite entre días.
        .order("id")
        .range(desde, desde + CHUNK - 1);
      if (error) throw new Error(`No se pudo leer lo ya importado: ${error.message}`);
      for (const r of data ?? []) {
        yaExisten.add(`${r.clave}|${r.fecha}|${r.tipo}|${String(r.hora).slice(0, 8)}`);
      }
      if ((data?.length ?? 0) < CHUNK) break;
    }
    const nuevas = registros.filter((r) => {
      const num = String(r.numero_empleado ?? "");
      const id = num ? `num:${num}` : `nombre:${claveNombre(String(r.nombre_reporte ?? ""))}`;
      return !yaExisten.has(`${id}|${r.fecha}|${r.tipo}|${r.hora}`);
    }).length;

    // ── Bitácora y upsert ────────────────────────────────────────────────────

    const sinEmpatar = {
      empleados: [...empleadosSinEmpatar.entries()].map(([k, v]) => ({ numero: k, nombre: v })),
      horarios: [...horariosSinEmpatar],
    };

    const { data: imp, error: impErr } = await db
      .from("checador_importaciones")
      .insert({
        archivo,
        fecha_inicio: minFecha,
        fecha_fin: maxFecha,
        filas_leidas: registros.length,
        filas_nuevas: nuevas,
        importado_por: user.id,
        sin_empatar: sinEmpatar,
      })
      .select("id")
      .single();
    if (impErr) throw new Error(`No se pudo registrar la importación: ${impErr.message}`);

    for (let i = 0; i < registros.length; i += CHUNK) {
      const lote = registros.slice(i, i + CHUNK)
        .map((r) => ({ ...r, importacion_id: imp.id }));
      const { error } = await db
        .from("checador_registros")
        .upsert(lote, { onConflict: "clave,fecha,tipo,hora" });
      if (error) {
        throw new Error(
          `Falló al guardar el lote ${i / CHUNK + 1}: ${error.message}. ` +
            `Se guardaron ${i} de ${registros.length} filas.`,
        );
      }
    }

    const dias = new Set(registros.map((r) => r.fecha)).size;

    return reply({
      ok: true,
      tipo: "checadas",
      importacion_id: imp.id,
      archivo,
      periodo: { inicio: minFecha, fin: maxFecha, dias },
      filas: {
        leidas: registros.length,
        nuevas,
        actualizadas: registros.length - nuevas,
        omitidas,
      },
      registros: { entradas, salidas },
      empleados: new Set(registros.map((r) =>
        r.numero_empleado || `n:${r.nombre_reporte}`
      )).size,
      sin_empatar: sinEmpatar,
      // Cuántos catálogos se leyeron para resolver las uniones. Se reporta porque el bug del
      // truncamiento a 1000 filas era invisible: un número redondo aquí delata que la paginación
      // dejó de funcionar.
      catalogos: { perfiles: perfiles.length, horarios: horarios.length },
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("checador-import:", msg);
    return reply({ error: msg }, 500);
  }
});
