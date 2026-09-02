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
      return {
        resultados: [],
        count: 0,
        nota: "No hay ningun desarrollo capturado que coincida. Eso no quiere decir que no exista: "
          + "puede que todavia no este en el sistema. Se captura en la pagina de SOL, pestaña "
          + "Desarrollos.",
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
      nota: filas.length === 0
        ? "No hay documentos capturados con ese criterio. Puede que existan en el Drive y todavia "
          + "no esten dados de alta."
        : undefined,
    };
  }

  return { error: `Herramienta desconocida: ${nombre}` };
}
