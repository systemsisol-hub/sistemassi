// Lo que HACEN las herramientas de SOL.
//
// Todo lo que se devuelve sale de las tablas. El modelo no calcula ni completa: recibe renglones y
// los redacta. Es la misma separacion que en Soli, y por la misma razon.

import type { Db } from "./config.ts";
import { hoyISO } from "./config.ts";
import type { ToolInput } from "./herramientas.ts";
import {
  calificaPara,
  extrasQueCalifica,
  reglaDelExtra,
  reglaEnPalabras,
  type ReglaExtra,
} from "./extras.ts";

const CAMPOS_REGLA =
  "extra,requiere_departamento,precio_minimo_departamento,minimo_inclusivo,notas";

/// Las reglas de extras de unos desarrollos.
async function reglasDe(db: Db, ids: string[]): Promise<Map<string, ReglaExtra[]>> {
  if (ids.length === 0) return new Map();
  const { data } = await db.from("reglas_extras")
    .select(`desarrollo_id,${CAMPOS_REGLA}`)
    .in("desarrollo_id", ids).eq("is_active", true).order("extra");
  const porId = new Map<string, ReglaExtra[]>();
  for (const r of (data ?? []) as Record<string, unknown>[]) {
    const k = String(r.desarrollo_id);
    (porId.get(k) ?? porId.set(k, []).get(k)!).push({
      extra: String(r.extra),
      requiere_departamento: r.requiere_departamento === true,
      precio_minimo_departamento: r.precio_minimo_departamento === null ||
          r.precio_minimo_departamento === undefined
        ? null
        : Number(r.precio_minimo_departamento),
      minimo_inclusivo: r.minimo_inclusivo === true,
      notas: (r.notas ?? null) as string | null,
    });
  }
  return porId;
}

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
    // Se devuelven los documentos COMPLETOS, con su enlace, no solo los nombres de categoria.
    //
    // Al principio devolvia solo los nombres, y eso creo el peor estado posible: el modelo sabia que
    // el brochure existia y no tenia como entregarlo. El 02/09/2026 contesto
    // «- Brochure: [Enlace al Brochure]» -un marcador de posicion- porque el prompt le prohibe
    // escribir direcciones y no tenia ninguna a mano. Saber de un documento que no puedes dar es
    // peor que no saber de el.
    const { data: docsTodos } = await db.from("documentos")
      .select("desarrollo_id,categoria,idioma,variante,nombre,url,es_carpeta,visibilidad")
      .in("desarrollo_id", ids as string[]).eq("is_active", true).order("categoria");
    const docsPorId = new Map<string, Record<string, unknown>[]>();
    for (const r of (docsTodos ?? []) as Record<string, unknown>[]) {
      const k = String(r.desarrollo_id);
      (docsPorId.get(k) ?? docsPorId.set(k, []).get(k)!).push({
        categoria: r.categoria,
        idioma: r.idioma ?? null,
        variante: r.variante ?? null,
        nombre: r.nombre,
        enlace: r.url,
        es_carpeta: r.es_carpeta,
        visibilidad: r.visibilidad,
      });
    }

    // El rango de precios sale del INVENTARIO cuando hay unidades cargadas.
    //
    // `desarrollos.precio_desde` y `precio_hasta` son dos numeros que alguien teclea, y los diez
    // desarrollos los tenian en NULL: por eso SOL no pudo contestar cuando le pidieron la lista de
    // precios de Zenesis Club. Con unidades, el rango se calcula, y un rango calculado no puede
    // contradecir a las unidades que lo produjeron.
    //
    // La cuenta vive en la vista `v_desarrollo_inventario` y no aqui, para que el panel y SOL usen
    // la MISMA definicion. Calcularla dos veces es como se acaba dando dos numeros distintos.
    const { data: invs } = await db.from("v_desarrollo_inventario")
      .select("desarrollo_id,unidades_totales,disponibles,apartadas,vendidas," +
              "precio_desde,precio_hasta,m2_desde,m2_hasta,lista_al")
      .in("desarrollo_id", ids as string[]);
    const invPorId = new Map(
      ((invs ?? []) as Record<string, unknown>[]).map((r) => [String(r.desarrollo_id), r]),
    );

    return {
      resultados: filas.map((f) => {
        const nombreD = String(f.nombre ?? "");
        const mias = [
          ...(porId.get(String(f.id)) ?? []).map((p) => formatoPromo(p, nombreD)),
          ...generales.map((p) => formatoPromo(p, null)),
        ].filter((p) => p.vigente);

        const inv = invPorId.get(String(f.id));
        const disponibles = Number(inv?.disponibles ?? 0);
        const hayInventario = disponibles > 0;

        return {
          ...f,
          id: undefined,
          // Si hay inventario, manda el inventario. Y se dice DE DONDE salio el numero, porque «no
          // esta capturado» y «lo calculamos de 38 unidades» piden respuestas muy distintas.
          precio_desde: hayInventario ? inv!.precio_desde : f.precio_desde,
          precio_hasta: hayInventario ? inv!.precio_hasta : f.precio_hasta,
          superficie_desde: hayInventario ? inv!.m2_desde : f.superficie_desde,
          superficie_hasta: hayInventario ? inv!.m2_hasta : f.superficie_hasta,
          precio_origen: hayInventario
            ? `calculado de ${disponibles} unidades disponibles`
            : (f.precio_desde === null ? null : "capturado a mano"),
          inventario: inv === undefined ? null : {
            unidades_totales: inv.unidades_totales,
            disponibles: inv.disponibles,
            apartadas: inv.apartadas,
            vendidas: inv.vendidas,
            lista_al: inv.lista_al,
          },
          promociones_vigentes: mias,
          documentos: docsPorId.get(String(f.id)) ?? [],
          // Con que fecha se esta contestando. Sin esto, una respuesta correcta hoy parece correcta
          // para siempre.
          datos_al: f.actualizado_en,
        };
      }),
      count: filas.length,
    };
  }

  if (nombre === "buscar_unidades") {
    const CAMPOS_UNIDAD =
      "desarrollo_id,numero,depto,torre,nivel,tipo,tipologia,vista," +
      "m2_interior_techada,m2_exterior_techada,m2_jardin_terraza," +
      "m2_total_interior,m2_total,precio,precio_m2,moneda,estatus,lista_al," +
      "desarrollos!inner(nombre)";

    const limite = Math.min(Math.max(Number(input.limite ?? 25) || 25, 1), 60);

    // Con `para_extra` hay que traer MAS y recortar despues: quien califica depende del precio
    // contra el umbral de la regla, y eso se decide en codigo. Aplicar el limite antes del filtro
    // devolveria menos unidades de las que hay.
    const filtrarPorExtra = typeof input.para_extra === "string" &&
      input.para_extra.trim().length > 0;
    const aTraer = filtrarPorExtra ? 300 : limite;

    let q = db.from("unidades").select(CAMPOS_UNIDAD)
      .order("precio", { ascending: true }).limit(aTraer);

    // Solo las disponibles, salvo que pidan lo contrario. Ofrecerle a un cliente una unidad ya
    // vendida es el peor error que puede cometer el asistente, asi que el valor por omision es el
    // seguro y hay que pedir expresamente lo demas.
    if (input.incluir_no_disponibles !== true) q = (q as any).eq("estatus", "DISPONIBLE");

    if (input.desarrollo) q = (q as any).ilike("desarrollos.nombre", `%${input.desarrollo}%`);
    if (input.torre)      q = (q as any).ilike("torre", `%${input.torre}%`);
    if (input.nivel)      q = (q as any).ilike("nivel", `%${input.nivel}%`);
    if (input.tipologia)  q = (q as any).ilike("tipologia", `%${input.tipologia}%`);
    if (input.vista)      q = (q as any).ilike("vista", `%${input.vista}%`);
    if (input.precio_max !== undefined) q = (q as any).lte("precio", input.precio_max);
    if (input.precio_min !== undefined) q = (q as any).gte("precio", input.precio_min);
    if (input.m2_min !== undefined)     q = (q as any).gte("m2_total", input.m2_min);

    // El numero puede ser el de la unidad -AG008- o el del departamento -A-103-. El asesor usa uno
    // o el otro segun de donde venga el dato, y obligarlo a acertar cual seria absurdo.
    if (input.numero) {
      const n = String(input.numero);
      q = (q as any).or(`numero.ilike.%${n}%,depto.ilike.%${n}%`);
    }

    const { data, error } = await q;
    if (error) return { error: error.message };

    // Las reglas de extras, para poder decir a QUE tiene derecho cada unidad.
    //
    // Va calculado y no explicado: si el modelo tuviera que comparar «este cuesta 9,310,000» contra
    // «arriba de 8,000,000» en cada respuesta, tarde o temprano prometeria una bodega a quien no
    // puede comprarla, y eso se descubre en la firma.
    const idsDes = [
      ...new Set(((data ?? []) as Record<string, unknown>[])
        .map((u) => String(u.desarrollo_id ?? ""))
        .filter((x) => x !== "")),
    ];
    const reglas = await reglasDe(db, idsDes);

    // El filtro se aplica ANTES de recortar, y con `calificaPara`, que es la función probada.
    // Escribirlo aquí con un `.some()` sería tener la misma comparación en dos sitios: el día que
    // el borde cambiara —«arriba de» a «desde»— una de las dos se quedaría vieja.
    const crudas = ((data ?? []) as Record<string, unknown>[]).filter((u) => {
      if (!filtrarPorExtra) return true;
      const misReglas = reglas.get(String(u.desarrollo_id ?? "")) ?? [];
      return calificaPara(u, String(input.para_extra), misReglas);
    }).slice(0, limite);

    const filas = crudas.map((u) => {
      const des = u.desarrollos as Record<string, unknown> | null;
      const misReglas = reglas.get(String(u.desarrollo_id ?? "")) ?? [];

      // Si la unidad MISMA es un extra, su condicion de venta viaja con ella.
      //
      // Sin esto, los cuatro ROOF de AG117 salian en cualquier busqueda por precio bajo como si se
      // pudieran comprar sueltos. Paso el 04/09/2026 con «tengo 2 millones, que puedo comprar».
      const propia = reglaDelExtra(u.tipo, misReglas);

      return {
        ...u,
        desarrollo_id: undefined,
        desarrollos: undefined,
        desarrollo: des?.nombre ?? null,
        extras_que_puede_comprar: extrasQueCalifica(u, misReglas),
        es_extra: propia === null ? undefined : true,
        condicion_de_venta: propia === null ? undefined : reglaEnPalabras(propia),
      };
    });

    // Y un aviso al NIVEL DEL RESULTADO cuando hay extras en la lista.
    //
    // Va aparte de la condicion de cada unidad a proposito: un campo por renglon es facil de pasar
    // por alto al redactar una tabla, y este aviso habla del conjunto. Es la diferencia entre que el
    // modelo lo mencione y que no.
    const cuantosExtras = filas.filter((u) => u.es_extra === true).length;
    const avisoExtras = cuantosExtras === 0 ? undefined
      : `OJO: ${cuantosExtras} de estas ${filas.length} unidades son EXTRAS y NO se pueden vender `
        + `solas. Cada una trae su condicion en condicion_de_venta y tienes que decirla junto al `
        + `precio, en la misma respuesta. Nunca las presentes como algo que se pueda comprar por si `
        + `mismo, ni las ofrezcas como opcion para un presupuesto.`;

    if (filas.length === 0) {
      // No se le deja con la negativa. Se le dice QUE SI hay, con datos, en la misma respuesta.
      //
      // Es la misma regla que ya rige a buscar_desarrollo y por la misma razon: un asesor con un
      // cliente enfrente necesita algo con lo que trabajar, no una negativa correcta.
      let dq = db.from("unidades")
        .select("precio,torre,tipologia,m2_total,desarrollos!inner(nombre)")
        .eq("estatus", "DISPONIBLE").order("precio", { ascending: true }).limit(200);
      if (input.desarrollo) dq = (dq as any).ilike("desarrollos.nombre", `%${input.desarrollo}%`);
      const { data: hay } = await dq;
      const otras = (hay ?? []) as Record<string, unknown>[];

      if (otras.length === 0) {
        const { data: conInv } = await db.from("v_desarrollo_inventario")
          .select("desarrollo,disponibles").gt("disponibles", 0);
        return {
          resultados: [],
          count: 0,
          desarrollos_con_inventario: ((conInv ?? []) as Record<string, unknown>[])
            .map((r) => `${r.desarrollo} (${r.disponibles} disponibles)`),
          nota: "Ese desarrollo no tiene inventario cargado. Eso NO quiere decir que no haya "
            + "unidades: quiere decir que todavia no estan en el sistema. Di eso, ofrece los "
            + "desarrollos que si tienen inventario, y ofrece la lista de precios del Drive con "
            + "buscar_documento si existe.",
        };
      }

      return {
        resultados: [],
        count: 0,
        // Lo que si hay, para poder reencauzar la busqueda.
        mas_barata_disponible: otras[0].precio,
        torres_con_disponibles: [...new Set(otras.map((u) => String(u.torre ?? "")))]
          .filter((t) => t !== "").sort(),
        tipologias_con_disponibles: [...new Set(otras.map((u) => String(u.tipologia ?? "")))]
          .filter((t) => t !== "").sort(),
        total_disponibles: otras.length,
        nota: "Ninguna unidad cumple ESOS filtros. Hay " + otras.length + " disponibles con otras "
          + "caracteristicas. Di cuantas hay, desde que precio, y en que torres y tipologias, para "
          + "que el asesor pueda reencauzar. No contestes solo que no hay.",
      };
    }

    const notas = [
      avisoExtras,
      filas.length === limite
        ? `Se devolvieron las ${limite} mas baratas y hay mas. Dilo asi y ofrece acotar la busqueda.`
        : undefined,
    ].filter((x) => x !== undefined);

    return {
      resultados: filas,
      count: filas.length,
      // Si se llego al tope hay que decirlo: «tengo 5» cuando hay 40 es una respuesta falsa.
      hay_mas: filas.length === limite,
      nota: notas.length === 0 ? undefined : notas.join(" "),
    };
  }

  if (nombre === "reglas_de_extras") {
    let dq = db.from("desarrollos").select("id,nombre").eq("is_active", true);
    if (input.desarrollo) dq = (dq as any).ilike("nombre", `%${input.desarrollo}%`);
    const { data: des } = await dq;
    const filas = (des ?? []) as Record<string, unknown>[];
    if (filas.length === 0) {
      return { resultados: [], count: 0, nota: "No hay ningun desarrollo con ese nombre." };
    }

    const reglas = await reglasDe(db, filas.map((d) => String(d.id)));

    return {
      resultados: filas.map((d) => {
        const mias = reglas.get(String(d.id)) ?? [];
        return {
          desarrollo: d.nombre,
          extras: mias.map((r) => ({
            extra: r.extra,
            requiere_departamento: r.requiere_departamento,
            precio_minimo_departamento: r.precio_minimo_departamento,
            // La regla YA REDACTADA. El modelo la repite; no la deduce del numero.
            regla: reglaEnPalabras(r),
            notas: r.notas ?? undefined,
          })),
          sin_reglas: mias.length === 0 ? true : undefined,
        };
      }),
      count: filas.length,
      nota: "Estas reglas son las que manda. Repite la frase de `regla` tal cual; NO deduzcas "
        + "quien califica comparando precios por tu cuenta. Para saber si UNA unidad concreta "
        + "califica, usa buscar_unidades: cada unidad viene con `extras_que_puede_comprar` ya "
        + "calculado.",
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
