// Lo que hace cada herramienta cuando el modelo la llama: las consultas a la base.
//
// Aqui se vuelve a comprobar el permiso, aunque la lista que recibio el modelo ya venia filtrada.
// Esa segunda comprobacion es la que cuenta; filtrar la lista es comodidad.

import { ToolInput } from "./herramientas.ts";
import { ADMIN_COLABORADOR_FIELDS, ADMIN_ONLY_TOOLS, PERMISO_POR_HERRAMIENTA, Permisos, puedeUsarHerramienta, soloCamposPermitidos, USER_COLABORADOR_FIELDS } from "./permisos.ts";
import { calcYears, CANDIDATOS_APROXIMADO, CANDIDATOS_NOMBRE, conAlgunaPalabra, empataNombre, empataNombreAproximado, esUuid, esVigente, filtroPrefijos, getDaysByYear, numeroEmpleadoVariants, parseLocalDate, resolverPorNombre, sinAcentos, tokenGuia, tokensDeNombre, vigentesPrimero } from "./nombres.ts";
import type { Db } from "./config.ts";

export async function runTool(
  name: string,
  input: ToolInput,
  db: Db,
  isAdmin: boolean,
  userId: string,
  userFullName: string,
  permisos: Permisos,
): Promise<unknown> {
  // Se vuelve a comprobar aquí aunque la lista que recibe el modelo ya venga filtrada. Ésta es la
  // verificación que cuenta: si el modelo se inventa una llamada —o si un archivo adjunto lo
  // convence de intentarlo— se bloquea igual. Filtrar la lista es comodidad; esto es el control.
  if (!puedeUsarHerramienta(name, isAdmin, permisos)) {
    if (ADMIN_ONLY_TOOLS.has(name) && !isAdmin) {
      return { error: "Acción no permitida: exclusiva del administrador." };
    }
    const requerido = PERMISO_POR_HERRAMIENTA[name];
    return {
      error: `Sin acceso a esa información. Requiere el permiso "${requerido}", ` +
        "que se concede en la página de Usuarios.",
    };
  }

  // ── COLABORADORES ────────────────────────────────────────────────────
  if (name === "buscar_colaborador") {
    const fields = isAdmin ? ADMIN_COLABORADOR_FIELDS : USER_COLABORADOR_FIELDS;
    let q = db.from("profiles").select(fields);
    if (input.numero_empleado) {
      const variants = numeroEmpleadoVariants(String(input.numero_empleado));
      if (variants.length === 1) {
        q = (q as any).eq("numero_empleado", variants[0]);
      } else {
        q = (q as any).or(variants.map(v => `numero_empleado.eq.${v}`).join(","));
      }
    }
    // Búsqueda por nombre completo.
    //
    // Aquí estaba el fallo: `nombre` guarda SOLO el nombre de pila. Cuando alguien preguntaba por
    // "las vacaciones de Enrique Ortega Gomez", el modelo pasaba el nombre entero como `nombre`, la
    // consulta quedaba en `nombre ILIKE '%ENRIQUE ORTEGA GOMEZ%'` y devolvía CERO aunque la persona
    // existe —empleado 0170—. Soli informaba de buena fe que no había registros.
    //
    // Se pide a la base por UNA palabra y el cruce completo se hace en código; ver `empataNombre`.
    const tokens = input.nombre_completo
      ? tokensDeNombre(String(input.nombre_completo))
      : [];
    if (tokens.length > 0) {
      const guia = tokenGuia(tokens);
      q = (q as any).or(
        `nombre.ilike.%${guia}%,paterno.ilike.%${guia}%,materno.ilike.%${guia}%`,
      );
    }

    // El UUID y el correo eran los dos huecos mas tontos: alguien te da un dato perfectamente valido
    // y no habia por donde entrarle. Reportado tal cual: «le di el uuid y no lo pudo buscar».
    if (input.id) {
      const dado = String(input.id).trim();
      if (!esUuid(dado)) {
        return { error: `"${dado}" no tiene forma de UUID. Si es un número de empleado usa numero_empleado.` };
      }
      q = (q as any).eq("id", dado);
    }

    // Se busca en los TRES campos de correo. `correo_personal` incluido a proposito: tiene mas
    // cobertura que el de trabajo -1430 perfiles contra 1145- y buscar POR un correo que la persona ya
    // conoce no revela nada que no tuviera, igual que buscar por numero de empleado. Lo que NO cambia
    // es que ese campo sigue fuera de lo que se DEVUELVE a un usuario normal.
    if (input.correo) {
      const c = String(input.correo).trim().replace(/[,()]/g, "");
      q = (q as any).or(
        `mail_user.ilike.%${c}%,email.ilike.%${c}%,correo_personal.ilike.%${c}%`,
      );
    }

    if (input.nombre)    q = (q as any).ilike("nombre",  `%${sinAcentos(String(input.nombre))}%`);
    if (input.paterno)   q = (q as any).ilike("paterno", `%${sinAcentos(String(input.paterno))}%`);
    if (input.materno)   q = (q as any).ilike("materno", `%${sinAcentos(String(input.materno))}%`);
    if (input.area)      q = (q as any).eq("area", input.area);
    if (input.puesto)    q = (q as any).ilike("puesto", `%${input.puesto}%`);
    if (input.ubicacion) q = (q as any).eq("ubicacion", input.ubicacion);
    if (input.status_rh)             q = (q as any).eq("status_rh", input.status_rh);
    if (isAdmin && input.status_sys) q = (q as any).eq("status_sys", input.status_sys);

    // Con nombre completo se traen candidatos de sobra, porque el recorte al límite que pidió el
    // usuario tiene que pasar DESPUÉS de cruzar las palabras. Recortar antes dejaría fuera a la
    // persona buscada entre gente que sólo empata con una palabra.
    const limiteUsuario = (input.limit as number) || 20;
    q = (q as any)
      .limit(tokens.length > 0 ? CANDIDATOS_NOMBRE : limiteUsuario)
      .order("nombre");

    const { data, error } = await q;
    if (error) return { error: error.message };

    let filas = (data || []) as unknown as Record<string, unknown>[];
    if (tokens.length > 0) {
      // Si el prefiltro llenó el cupo, pudo quedar gente fuera. Se dice, en lugar de devolver una
      // cuenta que parece completa: medido, la palabra más común de la base trae 180 candidatos, así
      // que con 500 esto no debería ocurrir nunca.
      const truncado = filas.length >= CANDIDATOS_NOMBRE;
      filas = filas.filter((f) => empataNombre(f, tokens)).slice(0, limiteUsuario);
      if (truncado) {
        return {
          results: filas,
          count: filas.length,
          aviso: "Había demasiados candidatos; el resultado puede estar incompleto. Acota la búsqueda.",
        };
      }

      // Nada exacto: se reintenta admitiendo dedazos. Ver `empataNombreAproximado`.
      //
      // Sólo cuando la exacta falla, porque la tolerante trae muchos más candidatos. Y sólo mira el
      // nombre: si además venían `area` o `puesto`, esos filtros no se reaplican aquí, así que el
      // resultado puede incluir a alguien que no los cumpla. Se acepta porque combinar nombre con
      // otros filtros es raro, y devolver a la persona con un aviso es mejor que decir que no existe.
      if (filas.length === 0) {
        const filtro = filtroPrefijos(tokens);
        if (filtro.length > 0) {
          const { data: cands } = await db.from("profiles").select(fields)
            .or(filtro).limit(CANDIDATOS_APROXIMADO);
          const todos = (cands || []) as unknown as Record<string, unknown>[];

          const aprox = vigentesPrimero(todos.filter((f) => empataNombreAproximado(f, tokens)))
            .slice(0, limiteUsuario);
          if (aprox.length > 0) {
            return {
              results: aprox,
              count: aprox.length,
              aviso: `No hay nadie escrito exactamente así. Esto es lo más parecido a `
                + `"${input.nombre_completo}"; confírmalo con el usuario antes de darlo por bueno.`,
            };
          }

          // Ultimo recurso antes de decir que no hay nadie: con ALGUNA de las palabras.
          const cerca = conAlgunaPalabra(todos, tokens).slice(0, limiteUsuario);
          if (cerca.length > 0) {
            return {
              results: cerca,
              count: cerca.length,
              aviso: `Nadie coincide con todo "${input.nombre_completo}". Estos coinciden en parte: `
                + `MUESTRALOS y pregunta si es alguno, o pide un apellido más, el correo o el número.`,
            };
          }
        }
      }
    }
    // Los vigentes arriba: con un apellido comun, la lista es en su mayoria gente que ya no esta.
    return { results: vigentesPrimero(filas), count: filas.length };
  }

  if (name === "crear_colaborador") {
    const campos = soloCamposPermitidos(name, input);
    const { data, error } = await db.from("profiles")
      .insert({ ...campos, status_rh: campos.status_rh || "ACTIVO", status_sys: campos.status_sys || "CAMBIO" })
      .select("id,numero_empleado,nombre,paterno").single();
    if (error) return { error: error.message };
    return { success: true, created: data };
  }

  if (name === "actualizar_colaborador") {
    const { id } = input;
    const fields = soloCamposPermitidos(name, input);
    const { data, error } = await db.from("profiles").update(fields).eq("id", id as string)
      .select("id,numero_empleado,nombre,paterno").single();
    if (error) return { error: error.message };
    return { success: true, updated: data };
  }

  // ── VACACIONES ────────────────────────────────────────────────────
  if (name === "calcular_vacaciones") {
    // A quién se le calcula.
    //
    // Se acepta el número de empleado además del uuid porque el modelo tiende a pasar el número —es
    // lo que ve en pantalla y lo que dice la gente— y `.eq("id","0170")` hace que Postgres falle. Y
    // se valida la forma del uuid ANTES de consultar, para que un error de identificación se
    // distinga de un saldo de cero: el fallo que dio origen a esto fue que Soli contestó «0 días
    // disponibles, sin periodos registrados» de una persona que tenía 102 días y 13 periodos.
    // Un usuario NO administrador que pasa el identificador de otra persona recibe un error, no los
    // datos de si mismo.
    //
    // Antes esos parametros se ignoraban en silencio -`isAdmin && input.x`- y el calculo salia con la
    // identidad de quien preguntaba. No filtraba nada de nadie, pero contestaba a «vacaciones de mi
    // jefe» con los dias del propio empleado y su nombre, que es de las cosas que peor se leen.
    if (!isAdmin && (input.nombre_completo || input.numero_empleado || input.usuario_id)) {
      return {
        error: "Solo un administrador puede consultar las vacaciones de otra persona. "
          + "Si son tus propios dias, vuelve a preguntar sin nombre ni numero.",
      };
    }

    let targetId = userId;
    /// Si el nombre se resolvio con tolerancia. Se devuelve para poder avisar de que es aproximado.
    let aproximadoDe: string | null = null;
    if (isAdmin && input.nombre_completo) {
      // Se identifica a la persona AQUÍ, en la misma llamada.
      //
      // Antes hacían falta dos llamadas encadenadas —buscar_colaborador para sacar el uuid y luego
      // ésta— y ahí se rompía todo: preguntar por las vacaciones PROPIAS funcionaba, porque es una
      // sola llamada, mientras que preguntar por otra persona devolvía cifras inventadas. Medido
      // sobre cuatro consultas reales: 4 de 4 mal, incluyendo un número de empleado y una fecha de
      // vencimiento que no existen. Quitar el encadenamiento quita la ocasión de inventar.
      const { fila, candidatos: empatan, aproximado, relajado } = await resolverPorNombre(
        db, String(input.nombre_completo),
        "id,nombre,paterno,materno,numero_empleado,status_rh,puesto,area",
      );
      if (aproximado && fila) {
        console.log(`nombre resuelto con tolerancia a dedazos: "${input.nombre_completo}" -> ${fila.numero_empleado}`);
      }
      // Ni «no existe» ni un «¿a cual?» sin datos: siempre se devuelve con quien se parece, para que
      // la respuesta sea «¿te refieres a alguno de estos?» y no una puerta cerrada.
      // Un nombre ambiguo NO es un error: es una lista de candidatos.
      //
      // Aqui estuvo el fallo. Estos casos devolvian los candidatos dentro del campo `error`, y como el
      // resultado llevaba `error` no contaba como «herramienta que devolvio datos». Con eso, el
      // guardia estructural veia «ninguna herramienta consulto» mas una lista con numeros y BLOQUEABA
      // la lista que yo mismo estaba pidiendo mostrar. Reportado: «vacaciones de lopez» acabo en «No
      // pude confirmar ese dato», mientras que «busca a garcia hernandez» -que va por
      // buscar_colaborador y devuelve `results` sin error- salio perfecto.
      //
      // Se devuelven las filas con las MISMAS claves que buscar_colaborador, para que la aplicacion
      // pueda pintar sus tarjetas de colaborador igual que en una busqueda normal.
      if (empatan.length === 0) {
        return {
          necesita_confirmacion: true,
          candidatos: [],
          buscado: input.nombre_completo,
          instruccion: `No hay nadie que se llame "${input.nombre_completo}". Dile que puede darte `
            + `un apellido, el correo o el número de empleado, y que tú lo buscas.`,
        };
      }
      if (empatan.length > 1 || relajado) {
        const vivos = empatan.filter(esVigente).length;
        return {
          necesita_confirmacion: true,
          buscado: input.nombre_completo,
          total_coincidencias: empatan.length,
          vigentes: vivos,
          candidatos: empatan.slice(0, 8),
          instruccion: relajado
            ? `Nadie se llama exactamente así, pero estos se parecen. MUÉSTRALOS en una tabla con `
              + `número de empleado, nombre y puesto, y pregunta a cuál se refiere.`
            : `Hay ${empatan.length} coincidencias (${vivos} siguen en la empresa). MUÉSTRALAS en una `
              + `tabla con número de empleado, nombre y puesto, y pregunta a cuál se refiere.`,
        };
      }
      targetId = String(fila!.id);
      if (aproximado) aproximadoDe = String(input.nombre_completo);
    } else if (isAdmin && input.numero_empleado) {
      const variants = numeroEmpleadoVariants(String(input.numero_empleado));
      const { data: encontrado } = await db.from("profiles").select("id")
        .or(variants.map((v) => `numero_empleado.eq.${v}`).join(",")).limit(2);
      if (!encontrado || encontrado.length === 0) {
        return { error: `No existe ningún colaborador con el número de empleado ${input.numero_empleado}. Esto es un fallo de identificación, NO un saldo de cero días.` };
      }
      if (encontrado.length > 1) {
        return { error: `El número de empleado ${input.numero_empleado} corresponde a más de una persona. Usa buscar_colaborador y pasa el campo id.` };
      }
      targetId = (encontrado[0] as { id: string }).id;
    } else if (isAdmin && input.usuario_id) {
      const dado = String(input.usuario_id);
      if (!esUuid(dado)) {
        return { error: `"${dado}" no es un UUID. Si es un número de empleado pásalo en numero_empleado, o busca a la persona con buscar_colaborador y usa su campo id. Esto es un fallo de identificación, NO un saldo de cero días.` };
      }
      targetId = dado;
    }

    const { data: prof, error: profErr } = await db
      .from("profiles")
      .select("nombre,paterno,materno,numero_empleado,fecha_ingreso,fecha_reingreso")
      .eq("id", targetId)
      .single();
    if (profErr || !prof) {
      return { error: `No se encontró ningún perfil con ese identificador${profErr ? ` (${profErr.message})` : ""}. Esto es un fallo de identificación, NO un saldo de cero días.` };
    }

    const fechaIngreso   = parseLocalDate(prof.fecha_ingreso);
    const fechaReingreso = parseLocalDate(prof.fecha_reingreso);
    const base = fechaReingreso ?? fechaIngreso;
    if (!base) return { error: "El colaborador no tiene fecha de ingreso registrada. No es posible calcular los días de vacaciones." };

    // Incidencias APROBADAS y PENDIENTES para el cálculo
    const { data: incs } = await db
      .from("incidencias")
      .select("periodo,dias,status")
      .eq("usuario_id", targetId)
      .in("status", ["APROBADA", "PENDIENTE"]);

    const normalize = (s: string | null) => (s || "").replace(/\D/g, "");
    const usedMap: Record<string, number> = {};
    for (const inc of (incs || [])) {
      const k = normalize(inc.periodo);
      if (k) usedMap[k] = (usedMap[k] || 0) + (inc.dias || 0);
    }

    const now = new Date();
    const completedYears = calcYears(base);
    const cutoff2017 = new Date(2017, 4, 2); // 2 Mayo 2017

    const calcProporcional = (days: number, start: Date, end: Date): number => {
      if (start > now) return days;
      if (end <= now)  return days;
      const elapsed = Math.floor((now.getTime() - start.getTime()) / 86400000) + 1;
      return (days / 365) * elapsed;
    };

    const periodos = [];
    for (let y = 1; y <= completedYears + 1; y++) {
      const periodStart = new Date(base.getFullYear() + y - 1, base.getMonth(), base.getDate());
      const periodEnd   = new Date(base.getFullYear() + y,     base.getMonth(), base.getDate());
      const label = `${periodStart.getFullYear()} - ${periodEnd.getFullYear()}`;

      let days: number;
      if (periodStart.getFullYear() >= 2023) {
        days = getDaysByYear(y);
      } else if (base < cutoff2017) {
        days = Math.min(6 + (y - 1) * 2, 14);
      } else {
        days = Math.min(8 + (y - 1) * 2, 16);
      }

      const prop      = calcProporcional(days, periodStart, periodEnd);
      const requested = usedMap[normalize(label)] || 0;
      const disponible = Math.floor(prop - requested);
      const esCurrent  = periodStart <= now && periodEnd > now;

      periodos.push({
        periodo: label,
        dias_ley: days,
        dias_proporcionales: Math.floor(prop),
        dias_solicitados: requested,
        dias_disponibles: disponible,
        es_periodo_actual: esCurrent,
      });
    }

    const totalDisponible = periodos.reduce((s, p) => s + Math.max(0, p.dias_disponibles), 0);
    const nombre = [prof.nombre, prof.paterno, prof.materno].filter(Boolean).join(" ");

    // Las ultimas solicitudes, en la MISMA llamada.
    //
    // Pedido tal cual: «cuando pido vacaciones marco, la tabla de sus vacaciones Y su ultimo registro
    // de vacaciones». Eran dos herramientas distintas y el modelo tenia que encadenarlas, que es
    // exactamente donde se rompe. Una llamada, las dos cosas.
    //
    // Se ordena por fecha de inicio descendente, asi que una salida POR VENIR queda arriba: la ultima
    // de Marco empieza el 21/08 y hoy es el 12, y eso es lo mas util que se puede decir de el.
    const { data: ultimas } = await db
      .from("incidencias")
      .select("periodo,dias,status,fecha_inicio,fecha_fin,fecha_regreso")
      .eq("usuario_id", targetId)
      .order("fecha_inicio", { ascending: false })
      .limit(6);

    const hoyIso = new Date().toLocaleDateString("en-CA", { timeZone: "America/Mexico_City" });
    const solicitudes = ((ultimas || []) as unknown as Record<string, unknown>[]).map((i) => ({
      periodo: i.periodo,
      dias: i.dias,
      status: i.status,
      fecha_inicio: i.fecha_inicio,
      fecha_fin: i.fecha_fin,
      fecha_regreso: i.fecha_regreso,
      // Que se sepa si ya paso o esta por venir sin tener que comparar fechas de cabeza.
      por_venir: typeof i.fecha_inicio === "string" && i.fecha_inicio > hoyIso,
    }));

    return {
      colaborador: nombre,
      numero_empleado: prof.numero_empleado,
      fecha_base: fechaReingreso ? prof.fecha_reingreso : prof.fecha_ingreso,
      usa_fecha_reingreso: !!fechaReingreso,
      periodos,
      total_disponible: totalDisponible,
      solicitudes,
      total_solicitudes: solicitudes.length,
      ...(aproximadoDe
        ? { aviso: `"${aproximadoDe}" no esta escrito asi en el sistema; esto es lo mas parecido. Confirmalo.` }
        : {}),
    };
  }

  // ── CUMPLEAÑOS ────────────────────────────────────────────────────
  //
  // Se usa el MISMO filtro que la pagina de Social -`social_page.dart:39`: status_rh distinto de BAJA
  // y status_sys ACTIVO- para que el asistente y la pantalla digan lo mismo. Dos criterios distintos
  // para la misma pregunta es la forma mas segura de que alguien acabe desconfiando de los dos.
  //
  // Ese filtro deja fuera, de paso, las razones sociales que viven en `profiles`: ECO DREAM SA DE CV
  // y otras traen `fecha_nacimiento` -que no es un cumpleaños- y `status_sys = 'NO APLICA'`.
  if (name === "buscar_cumpleanos") {
    // El mes se toma en hora de Mexico, no en UTC: el 1 de mes a medianoche son dos meses distintos.
    const hoyMx = new Date().toLocaleDateString("en-CA", { timeZone: "America/Mexico_City" });
    const [anioMx, mesMx, diaMx] = hoyMx.split("-").map((n) => parseInt(n, 10));

    const mes = typeof input.mes === "number" && input.mes >= 1 && input.mes <= 12
      ? input.mes
      : mesMx;

    const { data, error } = await db.from("profiles")
      .select("nombre,paterno,materno,fecha_nacimiento,ubicacion,puesto")
      .not("fecha_nacimiento", "is", null)
      .neq("status_rh", "BAJA")
      .eq("status_sys", "ACTIVO");
    if (error) return { error: error.message };

    let gente = ((data || []) as unknown as Record<string, unknown>[])
      .map((f) => {
        const fn = parseLocalDate(f.fecha_nacimiento as string);
        return { f, mes: fn ? fn.getMonth() + 1 : 0, dia: fn ? fn.getDate() : 0 };
      })
      .filter((x) => x.mes === mes);

    // «Esta semana» se cuenta de lunes a domingo, que es como la gente lo dice.
    let rango: string | null = null;
    if (input.solo_esta_semana === true) {
      const diaSemana = new Date(anioMx, mesMx - 1, diaMx).getDay(); // 0 = domingo
      const lunes = diaMx - ((diaSemana + 6) % 7);
      const domingo = lunes + 6;
      gente = gente.filter((x) => x.dia >= lunes && x.dia <= domingo);
      rango = `del ${lunes} al ${domingo}`;
    }

    gente.sort((a, b) => a.dia - b.dia);
    return {
      mes,
      rango,
      count: gente.length,
      results: gente.map((x) => ({
        dia: x.dia,
        nombre: [x.f.nombre, x.f.paterno, x.f.materno].filter(Boolean).join(" "),
        puesto: x.f.puesto ?? null,
        ubicacion: x.f.ubicacion ?? null,
      })),
    };
  }

  // ── INCIDENCIAS ────────────────────────────────────────────────────
  if (name === "buscar_incidencias") {
    let q = db.from("incidencias").select("*");
    if (!isAdmin) {
      q = (q as any).eq("usuario_id", userId);
    } else {
      if (input.usuario_id) q = (q as any).eq("usuario_id", input.usuario_id);
    }
    if (input.status)  q = (q as any).eq("status", input.status);
    if (input.periodo) q = (q as any).ilike("periodo", `%${input.periodo}%`);
    q = (q as any).limit((input.limit as number) || 20).order("created_at", { ascending: false });
    const { data, error } = await q;
    if (error) return { error: error.message };
    return { results: data, count: data?.length || 0 };
  }

  if (name === "crear_incidencia") {
    const effectiveUserId   = isAdmin ? ((input.usuario_id   as string) || userId) : userId;
    const effectiveUserName = isAdmin ? ((input.nombre_usuario as string) || userFullName) : userFullName;
    const { data, error } = await db.from("incidencias").insert({
      ...soloCamposPermitidos(name, input),
      usuario_id:     effectiveUserId,
      nombre_usuario: effectiveUserName,
      status:         "PENDIENTE",
      created_at:     new Date().toISOString(),
    }).select().single();
    if (error) return { error: error.message };
    return { success: true, incidencia: data };
  }

  if (name === "actualizar_incidencia") {
    const { id } = input;
    const fields = soloCamposPermitidos(name, input);
    const { data, error } = await db.from("incidencias").update(fields)
      .eq("id", id as string).select().single();
    if (error) return { error: error.message };
    return { success: true, updated: data };
  }

  // ── INVENTARIO ────────────────────────────────────────────────────
  if (name === "buscar_inventario") {
    let q = db.from("issi_inventory").select(
      "id,tipo,marca,modelo,n_s,condicion,ubicacion,usuario_id,usuario_nombre,observaciones,valor,cpu,ram,ssd"
    );
    if (!isAdmin) {
      q = (q as any).eq("usuario_id", userId);
    } else {
      if (input.usuario_id)           q = (q as any).eq("usuario_id", input.usuario_id);
      if (input.sin_asignar === true) q = (q as any).is("usuario_id", null);
    }
    if (input.tipo)      q = (q as any).eq("tipo", (input.tipo as string).toUpperCase());
    if (input.ubicacion) q = (q as any).ilike("ubicacion", `%${input.ubicacion}%`);
    if (input.marca)     q = (q as any).ilike("marca", `%${input.marca}%`);
    if (input.condicion) q = (q as any).eq("condicion", (input.condicion as string).toUpperCase());
    q = (q as any).limit((input.limit as number) || 20).order("tipo");
    const { data, error } = await q;
    if (error) return { error: error.message };
    return { results: data, count: data?.length || 0 };
  }

  if (name === "actualizar_inventario") {
    const { id } = input;
    const fields = soloCamposPermitidos(name, input);
    if (!fields.usuario_id || fields.usuario_id === "null") {
      fields.usuario_id = null; fields.usuario_nombre = null;
    }
    const { data, error } = await db.from("issi_inventory").update(fields)
      .eq("id", id as string).select().single();
    if (error) return { error: error.message };
    return { success: true, updated: data };
  }

  // ── CONTACTOS ────────────────────────────────────────────────────
  if (name === "buscar_contactos") {
    let q = db.from("external_contacts").select("*");
    if (input.nombre)  q = (q as any).ilike("nombre",  `%${input.nombre}%`);
    if (input.empresa) q = (q as any).ilike("empresa", `%${input.empresa}%`);
    if (input.correo)  q = (q as any).ilike("correo",  `%${input.correo}%`);
    q = (q as any).limit((input.limit as number) || 20).order("nombre");
    const { data, error } = await q;
    if (error) return { error: error.message };
    return { results: data, count: data?.length || 0 };
  }

  if (name === "gestionar_contacto") {
    const { id } = input;
    const fields = soloCamposPermitidos(name, input);
    if (id) {
      const { data, error } = await db.from("external_contacts").update(fields)
        .eq("id", id as string).select().single();
      if (error) return { error: error.message };
      return { success: true, action: "updated", contact: data };
    } else {
      const { data, error } = await db.from("external_contacts").insert(fields).select().single();
      if (error) return { error: error.message };
      return { success: true, action: "created", contact: data };
    }
  }


  // ── NOTIFICACIONES ────────────────────────────────────────────────────
  if (name === "enviar_notificacion") {
    const { data, error } = await db.from("notifications").insert({
      user_id: input.user_id, title: input.title, message: input.message,
      type: input.type || "admin_message", is_read: false, created_at: new Date().toISOString(),
    }).select().single();
    if (error) return { error: error.message };
    return { success: true, notification: data };
  }

  return { error: `Tool desconocida: ${name}` };
}
