// Lo que HACEN las herramientas de SOL.
//
// Todo lo que se devuelve sale de las tablas. El modelo no calcula ni completa: recibe renglones y
// los redacta. Es la misma separacion que en Soli, y por la misma razon.

import type { Db } from "./config.ts";
import { hoyISO } from "./config.ts";
import type { ToolInput } from "./herramientas.ts";

const CAMPOS_DESARROLLO =
  "id,nombre,ubicacion,etapa,descripcion,precio_desde,precio_hasta,moneda," +
  "enganche_pct,mensualidades,superficie_desde,superficie_hasta,amenidades," +
  "url_folleto,notas,is_active,actualizado_en";

/// Una promocion tal como se le entrega al modelo, con la vigencia ya resuelta.
///
/// `vigente` se calcula AQUI y no se deja al modelo comparando fechas: comparar fechas es
/// exactamente donde se equivoca, y equivocarse aqui significa citar una promocion muerta.
function formatoPromo(p: Record<string, unknown>, nombreDesarrollo: string | null) {
  const desde = String(p.vigente_desde ?? "");
  const hasta = String(p.vigente_hasta ?? "");
  const vigente = p.is_active === true && desde <= hoyISO && hoyISO <= hasta;
  return {
    titulo: p.titulo,
    detalle: p.detalle ?? null,
    desarrollo: nombreDesarrollo,
    vigente_desde: desde,
    vigente_hasta: hasta,
    vigente,
    // Se dice en palabras para que no haya que interpretar el booleano.
    estado: vigente ? "VIGENTE HOY" : (hoyISO > hasta ? "VENCIDA" : "AUN NO EMPIEZA"),
  };
}

export async function runTool(
  nombre: string,
  input: ToolInput,
  db: Db,
): Promise<Record<string, unknown>> {
  if (nombre === "buscar_desarrollo") {
    let q = db.from("desarrollos").select(CAMPOS_DESARROLLO).order("nombre");
    if (input.incluir_inactivos !== true) q = (q as any).eq("is_active", true);
    if (input.nombre) q = (q as any).ilike("nombre", `%${input.nombre}%`);
    if (input.plaza) q = (q as any).ilike("ubicacion", `%${input.plaza}%`);

    const { data, error } = await q;
    if (error) return { error: error.message };
    const filas = (data ?? []) as Record<string, unknown>[];

    if (filas.length === 0) {
      // NO es «no existe»: es «no esta capturado». La diferencia importa, porque lo primero manda
      // al asesor a decirle a un cliente que no lo tenemos.
      //
      // Y no se le deja con la negativa a secas: se le dice QUE SI hay. Un asesor que pregunta por
      // un desarrollo que no esta cargado sigue necesitando trabajar, y saber que existen otros
      // -o que de ese si tenemos documentos- es informacion util. Va en los DATOS y no confiado a
      // que el modelo se acuerde de hacer una segunda consulta.
      const { data: todos } = await db.from("desarrollos")
        .select("nombre").eq("is_active", true).order("nombre");
      const nombres = ((todos ?? []) as Record<string, unknown>[]).map((d) => String(d.nombre));

      // Puede que el desarrollo no este capturado pero SI tenga documentos cargados.
      let docs: string[] = [];
      if (input.nombre) {
        const { data: dd } = await db.from("documentos")
          .select("categoria,desarrollos!inner(nombre)")
          .ilike("desarrollos.nombre", `%${input.nombre}%`)
          .eq("is_active", true);
        docs = [...new Set(((dd ?? []) as Record<string, unknown>[])
          .map((r) => String(r.categoria)))];
      }

      return {
        resultados: [],
        count: 0,
        desarrollos_capturados: nombres,
        documentos_de_ese_desarrollo: docs.length > 0 ? docs : undefined,
        nota: "No hay ningun desarrollo capturado que coincida. Eso no quiere decir que no exista: "
          + "puede que todavia no este en el sistema. OFRECE lo que si hay: los desarrollos de "
          + "`desarrollos_capturados`, y si viene `documentos_de_ese_desarrollo`, esos documentos "
          + "-que pueden incluir su lista de precios- con la herramienta buscar_documento.",
      };
    }

    // Las promociones de cada uno, ya resueltas, para que el modelo no tenga que pedirlas aparte y
    // acabe respondiendo un precio sin la promocion que lo modifica.
    const ids = filas.map((f) => f.id);
    const { data: promos } = await db.from("promociones")
      .select("desarrollo_id,titulo,detalle,vigente_desde,vigente_hasta,is_active")
      .or(`desarrollo_id.in.(${ids.join(",")}),desarrollo_id.is.null`);

    const porId = new Map<string, Record<string, unknown>[]>();
    const generales: Record<string, unknown>[] = [];
    for (const p of (promos ?? []) as Record<string, unknown>[]) {
      if (p.desarrollo_id === null) generales.push(p);
      else {
        const k = String(p.desarrollo_id);
        (porId.get(k) ?? porId.set(k, []).get(k)!).push(p);
      }
    }

    // Que documentos tiene cada uno. Van JUNTO al desarrollo, por lo mismo que las promociones:
    // si el precio no esta capturado pero existe la lista de precios en el Drive, el modelo tiene
    // las dos cosas delante y puede ofrecer la segunda sin tener que acordarse de preguntar.
    const { data: docsTodos } = await db.from("documentos")
      .select("desarrollo_id,categoria").in("desarrollo_id", ids as string[]).eq("is_active", true);
    const catsPorId = new Map<string, Set<string>>();
    for (const r of (docsTodos ?? []) as Record<string, unknown>[]) {
      const k = String(r.desarrollo_id);
      (catsPorId.get(k) ?? catsPorId.set(k, new Set()).get(k)!).add(String(r.categoria));
    }

    return {
      resultados: filas.map((f) => {
        const nombreD = String(f.nombre ?? "");
        const mias = [
          ...(porId.get(String(f.id)) ?? []).map((p) => formatoPromo(p, nombreD)),
          ...generales.map((p) => formatoPromo(p, null)),
        ].filter((p) => p.vigente);
        return {
          ...f,
          id: undefined,
          promociones_vigentes: mias,
          documentos_disponibles: [...(catsPorId.get(String(f.id)) ?? [])].sort(),
          // Con que fecha se esta contestando. Sin esto, una respuesta correcta hoy parece correcta
          // para siempre.
          datos_al: f.actualizado_en,
        };
      }),
      count: filas.length,
    };
  }

  if (nombre === "buscar_promocion") {
    const { data: des } = await db.from("desarrollos").select("id,nombre");
    const nombrePorId = new Map(
      ((des ?? []) as Record<string, unknown>[]).map((d) => [String(d.id), String(d.nombre)]),
    );

    let q = db.from("promociones")
      .select("desarrollo_id,titulo,detalle,vigente_desde,vigente_hasta,is_active")
      .order("vigente_hasta", { ascending: false });
    const { data, error } = await q;
    if (error) return { error: error.message };

    let todas = ((data ?? []) as Record<string, unknown>[])
      .map((p) => formatoPromo(p, p.desarrollo_id === null
        ? null
        : nombrePorId.get(String(p.desarrollo_id)) ?? null));

    if (input.desarrollo) {
      const buscado = String(input.desarrollo).toLowerCase();
      // Las generales se conservan: aplican tambien a ese desarrollo.
      todas = todas.filter((p) =>
        p.desarrollo === null || p.desarrollo.toLowerCase().includes(buscado));
    }
    if (input.incluir_vencidas !== true) todas = todas.filter((p) => p.vigente);

    return {
      resultados: todas,
      count: todas.length,
      nota: todas.length === 0
        ? "No hay promociones vigentes hoy con ese criterio."
        : undefined,
    };
  }

  if (nombre === "buscar_documento") {
    // Se entra por el desarrollo para poder filtrar por su NOMBRE, que es como lo pide el asesor.
    let qd = db.from("desarrollos").select("id,nombre");
    if (input.desarrollo) qd = (qd as any).ilike("nombre", `%${input.desarrollo}%`);
    const { data: des } = await qd;
    const ids = ((des ?? []) as Record<string, unknown>[]).map((d) => d.id);
    if (ids.length === 0) {
      return {
        resultados: [], count: 0,
        nota: "No encontre ese desarrollo. Los documentos se dan de alta junto al desarrollo, en "
          + "la pagina de SOL.",
      };
    }
    const nombrePorId = new Map(
      ((des ?? []) as Record<string, unknown>[]).map((d) => [String(d.id), String(d.nombre)]),
    );

    let q = db.from("documentos")
      .select("desarrollo_id,categoria,idioma,variante,nombre,url,es_carpeta,visibilidad,notas")
      .in("desarrollo_id", ids as string[])
      .eq("is_active", true)
      .order("categoria");
    if (input.categoria) q = (q as any).ilike("categoria", `%${input.categoria}%`);
    if (input.idioma) q = (q as any).ilike("idioma", `%${input.idioma}%`);
    if (input.solo_compartibles === true) q = (q as any).eq("visibilidad", "COMPARTIBLE");

    const { data, error } = await q;
    if (error) return { error: error.message };
    const filas = (data ?? []) as Record<string, unknown>[];

    return {
      resultados: filas.map((f) => ({
        desarrollo: nombrePorId.get(String(f.desarrollo_id)) ?? null,
        categoria: f.categoria,
        idioma: f.idioma ?? null,
        variante: f.variante ?? null,
        nombre: f.nombre,
        enlace: f.url,
        es_carpeta: f.es_carpeta,
        visibilidad: f.visibilidad,
        notas: f.notas ?? null,
      })),
      count: filas.length,
      // Igual que arriba: si no hay lo que pidio, se le dice que categorias SI existen en lugar de
      // dejarlo con la negativa.
      categorias_disponibles: filas.length === 0 ? await categoriasDe(db, ids as string[]) : undefined,
      nota: filas.length === 0
        ? "No hay documentos con ESE criterio. Mira `categorias_disponibles` y ofrece lo que si "
          + "existe en lugar de dejarlo sin nada."
        : undefined,
    };
  }

  return { error: `Herramienta desconocida: ${nombre}` };
}

/// Las categorias de documentos que existen para esos desarrollos.
///
/// Sirve para no dejar al asesor con un «no hay»: si pidio el brochure y no esta, pero si estan los
/// planos y los prototipos, eso es lo que necesita saber.
async function categoriasDe(db: Db, ids: string[]): Promise<string[]> {
  if (ids.length === 0) return [];
  const { data } = await db.from("documentos")
    .select("categoria").in("desarrollo_id", ids).eq("is_active", true);
  return [...new Set(((data ?? []) as Record<string, unknown>[])
    .map((r) => String(r.categoria)))].sort();
}
