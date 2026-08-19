// Lo que hace cada herramienta cuando el modelo la llama: las consultas a la base.
//
// Aqui se vuelve a comprobar el permiso, aunque la lista que recibio el modelo ya venia filtrada.
// Esa segunda comprobacion es la que cuenta; filtrar la lista es comodidad.

import { ToolInput } from "./herramientas.ts";
import { ADMIN_COLABORADOR_FIELDS, ADMIN_ONLY_TOOLS, PERMISO_POR_HERRAMIENTA, Permisos, puedeUsarHerramienta, soloCamposPermitidos, USER_COLABORADOR_FIELDS } from "./permisos.ts";
import { calcYears, CANDIDATOS_APROXIMADO, CANDIDATOS_NOMBRE, conAlgunaPalabra, empataNombre, empataNombreAproximado, esUuid, esVigente, filtroPrefijos, getDaysByYear, numeroEmpleadoVariants, parseLocalDate, resolverPorNombre, sinAcentos, tokenGuia, tokensDeNombre, vigentesPrimero } from "./nombres.ts";
import type { Db } from "./config.ts";

/** De quien son los renglones que acaba de devolver una consulta, dicho para que lo lea el modelo.
 *
 * ─── El fallo que la hizo necesaria ──────────────────────────────────────────
 *
 * `buscar_inventario` y `buscar_incidencias` filtran por `usuario_id` SOLO a los usuarios normales. A
 * un administrador que no pase `usuario_id` le devuelven la tabla de TODA la empresa, y hasta ahora la
 * respuesta no decia en ninguna parte que fuera de todos. El 12/08/2026 un administrador pregunto que
 * equipo tenia asignado y recibio el LAP-TOP de otra persona: el modelo tenia veinte renglones ajenos
 * y ninguna señal de que no fueran suyos.
 *
 * El guardia de invenciones no puede cubrir esto -una herramienta SI trajo datos- asi que la señal
 * tiene que venir en los datos mismos. Va como texto y no como bandera porque el modelo lee texto.
 */
export function alcanceDeLaConsulta(deQuien: string, cosa: string): string {
  if (deQuien === "propio")        return `Solo los ${cosa} de quien pregunta.`;
  if (deQuien === "de un usuario") return `Solo los ${cosa} del usuario que se pidio.`;
  if (deQuien === "sin asignar")   return `Solo los ${cosa} que no tienen usuario asignado.`;
  return `ATENCION: estos son ${cosa} de TODA la empresa, NO de quien pregunta. `
    + "Cada renglon dice a quien pertenece; no atribuyas ninguno a quien pregunta sin comprobarlo. "
    + "Para los suyos hay que repetir la consulta pasando su usuario_id.";
}

/** Los horarios que usan estas filas, resueltos y legibles, indexados por su uuid.
 *
 * ─── El fallo que la hizo necesaria ──────────────────────────────────────────
 *
 * `profiles.horario` guarda el UUID de un renglon de `schedules`, no un texto. `buscar_colaborador` lo
 * devolvia crudo, asi que preguntar «cual es mi horario» contestaba con
 * «3ac244d0-bf7f-4cfa-99ce-b9f3bffd749d». Reportado tal cual.
 *
 * Se resuelven TODOS de una sola consulta y no uno por fila: una busqueda que devuelve veinte personas
 * haria veinte consultas para lo mismo.
 */
async function horariosDe(
  db: Db,
  filas: Array<Record<string, unknown>>,
): Promise<Record<string, unknown>> {
  const ids = [...new Set(filas
    .map((f) => f.horario)
    .filter((h): h is string => typeof h === "string" && esUuid(h)))];
  if (ids.length === 0) return {};

  const { data } = await db.from("schedules").select("id,name,zone,rules").in("id", ids);
  const DIAS = ["", "lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"];
  const hhmm = (v: unknown) => String(v ?? "").slice(0, 5);

  const mapa: Record<string, unknown> = {};
  for (const h of (data || []) as Array<Record<string, unknown>>) {
    const reglas = Array.isArray(h.rules) ? h.rules as Array<Record<string, unknown>> : [];
    // Una entrada y una salida por dia. La tolerancia va con la ENTRADA, que es la que decide un
    // retardo; en la salida siempre viene en cero.
    const porDia: Record<number, Record<string, unknown>> = {};
    for (const r of reglas) {
      const d = Number(r.day);
      if (!d) continue;
      porDia[d] ??= { dia: DIAS[d] ?? String(d) };
      if (r.type === "ENTRADA") {
        porDia[d].entrada = hhmm(r.time);
        porDia[d].tolerancia_min = Number(r.tol) || 0;
      } else if (r.type === "SALIDA") {
        porDia[d].salida = hhmm(r.time);
      }
    }
    mapa[String(h.id)] = {
      nombre: h.name ?? null,
      zona: h.zone ?? null,
      dias: Object.keys(porDia).map(Number).sort((a, b) => a - b).map((d) => porDia[d]),
    };
  }
  return mapa;
}

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
          horarios: await horariosDe(db, filas),
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
              horarios: await horariosDe(db, aprox),
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
              horarios: await horariosDe(db, cerca),
              aviso: `Nadie coincide con todo "${input.nombre_completo}". Estos coinciden en parte: `
                + `MUESTRALOS y pregunta si es alguno, o pide un apellido más, el correo o el número.`,
            };
          }
        }
      }
    }
    // Los vigentes arriba: con un apellido comun, la lista es en su mayoria gente que ya no esta.
    // `horarios` traduce el uuid de `horario` a nombre, zona y las horas de cada dia. Sin esto,
    // «cual es mi horario» contestaba con el uuid.
    const ordenadas = vigentesPrimero(filas);
    return {
      results: ordenadas,
      count: filas.length,
      horarios: await horariosDe(db, ordenadas),
    };
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
          // Se dice si cada uno sigue en la empresa, en una palabra y ya interpretada.
          //
          // Sin esto la lista no sirve para elegir: los candidatos traen `status_rh`, pero dejar que
          // el modelo lo traduzca es dejarle decidir qué cuenta como baja. Se manda resuelto con el
          // mismo criterio que usa la página de Social —cualquier status distinto de BAJA— para que
          // la tabla y la pantalla no puedan discrepar.
          candidatos: empatan.slice(0, 8).map((f) => ({
            ...f,
            estatus: esVigente(f) ? "VIGENTE" : "BAJA",
          })),
          instruccion: (relajado
            ? `Nadie se llama exactamente así, pero estos se parecen. `
            : `Hay ${empatan.length} coincidencias (${vivos} siguen en la empresa). `)
            + `MUÉSTRALOS TODOS en una tabla con número de empleado, nombre, puesto y la columna `
            + `«estatus» (VIGENTE o BAJA), y pregunta a cuál se refiere. NO descartes a los de BAJA `
            + `ni los omitas de la tabla: de una baja también se consultan su equipo por devolver, `
            + `sus vacaciones y su expediente.`,
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

    // Sólo las APROBADAS descuentan del saldo.
    //
    // Decidido el 18/08/2026, al revés de como estaba: antes contaban también las PENDIENTES, porque
    // una solicitud pendiente reservaba los días. Con este cambio, los días de una solicitud sin
    // autorizar siguen apareciendo disponibles.
    //
    // Tiene que coincidir con la tabla del Historial y con el formulario —ver el comentario en
    // `_buildHistorialTable` de incidencias_page.dart—. Si estos tres se separan, Soli y la pantalla
    // dan saldos distintos para la misma persona, y ya pasó una vez.
    const { data: incs } = await db
      .from("incidencias")
      .select("periodo,dias,status")
      .eq("usuario_id", targetId)
      .eq("status", "APROBADA");

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
    let deQuien = "";
    if (!isAdmin) {
      q = (q as any).eq("usuario_id", userId);
      deQuien = "propio";
    } else if (input.usuario_id) {
      q = (q as any).eq("usuario_id", input.usuario_id);
      deQuien = input.usuario_id === userId ? "propio" : "de un usuario";
    }
    if (input.status)  q = (q as any).eq("status", input.status);
    if (input.periodo) q = (q as any).ilike("periodo", `%${input.periodo}%`);
    q = (q as any).limit((input.limit as number) || 20).order("created_at", { ascending: false });
    const { data, error } = await q;
    if (error) return { error: error.message };
    return { results: data, count: data?.length || 0, alcance: alcanceDeLaConsulta(deQuien, "incidencias") };
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
    // De quien son los renglones que se devuelven. Va en la respuesta, no solo aqui: ver `alcance`.
    let deQuien = "";
    if (!isAdmin) {
      q = (q as any).eq("usuario_id", userId);
      deQuien = "propio";
    } else {
      if (input.usuario_id) {
        q = (q as any).eq("usuario_id", input.usuario_id);
        deQuien = input.usuario_id === userId ? "propio" : "de un usuario";
      }
      if (input.sin_asignar === true) { q = (q as any).is("usuario_id", null); deQuien = "sin asignar"; }
    }
    if (input.tipo)      q = (q as any).eq("tipo", (input.tipo as string).toUpperCase());
    if (input.ubicacion) q = (q as any).ilike("ubicacion", `%${input.ubicacion}%`);
    if (input.marca)     q = (q as any).ilike("marca", `%${input.marca}%`);
    if (input.condicion) q = (q as any).eq("condicion", (input.condicion as string).toUpperCase());
    q = (q as any).limit((input.limit as number) || 20).order("tipo");
    const { data, error } = await q;
    if (error) return { error: error.message };
    return { results: data, count: data?.length || 0, alcance: alcanceDeLaConsulta(deQuien, "equipos") };
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

  // ── CONTACTO DE EMERGENCIA ────────────────────────────────────────
  //
  // Nombre, telefono y relacion de la referencia, mas el tipo de sangre. Es la informacion que se
  // busca cuando alguien esta en un hospital, asi que la respuesta tiene que ser corta y sin adornos.
  //
  // ─── Quien puede pedir el de quien ──────────────────────────────────────────
  //
  // Lo PROPIO lo pide cualquiera: es su contacto y su tipo de sangre. Para eso esta herramienta NO
  // exige permiso de pagina, y por eso figura en EXENTAS del arnes.
  //
  // El de OTRA PERSONA exige ser administrador Y tener `show_cssi`, que es exactamente lo que abre la
  // pagina del expediente donde vive este dato -ver `main_navigation.dart`-. La comprobacion esta aqui
  // dentro y no en el mapa de permisos porque las dos reglas son distintas segun de quien se pregunte;
  // un solo permiso para las dos habria dejado a un usuario normal sin poder ver el suyo.
  if (name === "buscar_contacto_emergencia") {
    const CAMPOS_EMERGENCIA = "id,numero_empleado,nombre,paterno,materno,puesto,area," +
      "referencia_nombre,referencia_telefono,referencia_relacion,tipo_sangre";

    const pideDeOtro = Boolean(input.nombre_completo || input.numero_empleado
      || (input.usuario_id && String(input.usuario_id) !== userId));

    if (pideDeOtro && !(isAdmin && permisos.show_cssi === true)) {
      return {
        error: "El contacto de emergencia de otra persona solo lo ve un administrador con el permiso "
          + "«show_cssi», el mismo que abre la pagina de Colaborador. Si es el tuyo, vuelve a "
          + "preguntar sin nombre ni numero.",
      };
    }

    let objetivo = userId;
    if (pideDeOtro && input.nombre_completo) {
      const { fila, candidatos, relajado } = await resolverPorNombre(
        db, String(input.nombre_completo),
        "id,nombre,paterno,materno,numero_empleado,status_rh,puesto,area",
      );
      if (candidatos.length === 0) {
        return {
          necesita_confirmacion: true, candidatos: [], buscado: input.nombre_completo,
          instruccion: `No hay nadie que se llame "${input.nombre_completo}". Pide un apellido, `
            + `el correo o el numero de empleado.`,
        };
      }
      if (candidatos.length > 1 || relajado || !fila) {
        return {
          necesita_confirmacion: true,
          buscado: input.nombre_completo,
          total_coincidencias: candidatos.length,
          candidatos: candidatos.slice(0, 8).map((f) => ({
            ...f, estatus: esVigente(f) ? "VIGENTE" : "BAJA",
          })),
          instruccion: "MUESTRALOS TODOS en una tabla con numero de empleado, nombre, puesto y la "
            + "columna «estatus», y pregunta a cual se refiere. NO omitas a los de BAJA.",
        };
      }
      objetivo = String(fila.id);
    } else if (pideDeOtro && input.numero_empleado) {
      const variants = numeroEmpleadoVariants(String(input.numero_empleado));
      const { data: enc } = await db.from("profiles").select("id")
        .or(variants.map((v) => `numero_empleado.eq.${v}`).join(",")).limit(2);
      if (!enc || enc.length === 0) {
        return { error: `No existe ningun colaborador con el numero de empleado ${input.numero_empleado}.` };
      }
      objetivo = (enc[0] as { id: string }).id;
    } else if (pideDeOtro && input.usuario_id) {
      const dado = String(input.usuario_id);
      if (!esUuid(dado)) {
        return { error: `"${dado}" no es un UUID. Si es un numero de empleado pasalo en numero_empleado.` };
      }
      objetivo = dado;
    }

    const { data, error } = await db.from("profiles")
      .select(CAMPOS_EMERGENCIA).eq("id", objetivo).maybeSingle();
    if (error) return { error: error.message };
    if (!data) return { error: "No se encontro ese perfil." };

    const p = data as Record<string, unknown>;
    const tieneAlgo = Boolean(p.referencia_nombre || p.referencia_telefono
      || p.referencia_relacion || p.tipo_sangre);

    return {
      colaborador: [p.nombre, p.paterno, p.materno].filter(Boolean).join(" "),
      numero_empleado: p.numero_empleado ?? null,
      puesto: p.puesto ?? null,
      referencia_nombre: p.referencia_nombre ?? null,
      referencia_telefono: p.referencia_telefono ?? null,
      referencia_relacion: p.referencia_relacion ?? null,
      tipo_sangre: p.tipo_sangre ?? null,
      alcance: objetivo === userId
        ? "El contacto de emergencia de quien pregunta."
        : "El contacto de emergencia del colaborador que se pidio.",
      // Un hueco NO es un hecho sobre la persona: es un hecho sobre el expediente.
      //
      // Medido el 18/08/2026: de 244 vigentes solo 23 tienen la referencia capturada y NINGUNO el
      // tipo de sangre. Decir «no tiene contacto de emergencia» seria afirmar algo que nadie sabe,
      // y en una urgencia mandaria a no seguir buscando.
      instruccion: tieneAlgo
        ? "Da los datos que vengan y NO rellenes los que salgan vacios."
        : "Este expediente NO tiene capturado ningun dato de emergencia. Dilo asi: que no esta "
          + "REGISTRADO, no que la persona no tenga contacto. Sugiere capturarlo en la pagina de "
          + "Colaborador, y si es una urgencia, preguntar a Desarrollo Humano.",
    };
  }

  // ── ASISTENCIA ────────────────────────────────────────────────────
  //
  // Las cifras salen de las MISMAS dos vistas que pinta la pagina de Asistencia, y se agregan con las
  // mismas reglas. No es un detalle de estilo: si aqui se contara distinto, habria dos verdades sobre
  // las faltas de una persona y la discusion la ganaria quien tuviera la pantalla abierta.
  //
  // Copiado de `checador_panel.dart`, que es la fuente:
  //
  //   - Faltas y justificados salen de `checador_dias`, y SOLO de los dias con `esperado = true`. La
  //     vista tambien trae los que alguien trabajo fuera de su horario -un sabado en una jornada L-V-
  //     y esos no entran en ninguna metrica.
  //   - Retardos y puntualidad salen de `checador_entradas`, que va por checada y no por dia. Se
  //     cuentan solo las evaluadas, o sea las que traen `es_retardo` no nulo.
  //   - Dias de descuento = retardos ÷ `retardos_por_descuento` + faltas sin justificar.
  if (name === "buscar_asistencia") {
    // A quien. Un usuario normal solo puede verse a si mismo, igual que en inventario e incidencias.
    let objetivo = userId;
    let deQuien = "propio";
    if (!isAdmin && (input.nombre_completo || input.numero_empleado || input.usuario_id)) {
      return {
        error: "Solo un administrador puede consultar la asistencia de otra persona. "
          + "Si es la tuya, vuelve a preguntar sin nombre ni numero.",
      };
    }
    if (isAdmin && input.nombre_completo) {
      const { fila, candidatos, relajado } = await resolverPorNombre(
        db, String(input.nombre_completo),
        "id,nombre,paterno,materno,numero_empleado,status_rh,puesto,area",
      );
      if (candidatos.length === 0) {
        return {
          necesita_confirmacion: true, candidatos: [], buscado: input.nombre_completo,
          instruccion: `No hay nadie que se llame "${input.nombre_completo}". Pide un apellido, `
            + `el correo o el numero de empleado.`,
        };
      }
      if (candidatos.length > 1 || relajado || !fila) {
        return {
          necesita_confirmacion: true,
          buscado: input.nombre_completo,
          total_coincidencias: candidatos.length,
          candidatos: candidatos.slice(0, 8).map((f) => ({
            ...f, estatus: esVigente(f) ? "VIGENTE" : "BAJA",
          })),
          instruccion: "MUESTRALOS TODOS en una tabla con numero de empleado, nombre, puesto y la "
            + "columna «estatus», y pregunta a cual se refiere. NO omitas a los de BAJA.",
        };
      }
      objetivo = String(fila.id);
      deQuien = "de un usuario";
    } else if (isAdmin && input.numero_empleado) {
      const variants = numeroEmpleadoVariants(String(input.numero_empleado));
      const { data: enc } = await db.from("profiles").select("id")
        .or(variants.map((v) => `numero_empleado.eq.${v}`).join(",")).limit(2);
      if (!enc || enc.length === 0) {
        return { error: `No existe ningun colaborador con el numero de empleado ${input.numero_empleado}. Esto es un fallo de identificacion, NO una asistencia perfecta.` };
      }
      objetivo = (enc[0] as { id: string }).id;
      deQuien = "de un usuario";
    } else if (isAdmin && input.usuario_id) {
      const dado = String(input.usuario_id);
      if (!esUuid(dado)) {
        return { error: `"${dado}" no es un UUID. Si es un numero de empleado pasalo en numero_empleado.` };
      }
      objetivo = dado;
      deQuien = objetivo === userId ? "propio" : "de un usuario";
    }

    const { data: quienEs } = await db.from("profiles")
      .select("nombre,paterno,materno,numero_empleado,area,puesto")
      .eq("id", objetivo).single();

    let qDias = db.from("checador_dias")
      .select("fecha,estado,esperado,checo,incompleta,justificado,justificacion_motivo," +
        "justificacion_tipo,es_retardo,minutos_retardo,hora_entrada,entrada_esperada,horario_nombre")
      .eq("profile_id", objetivo).eq("esperado", true);
    // `hora` es a la que LLEGO; `hora_entrada` la que pedia su horario ese dia, y `limite` la misma
    // mas la tolerancia. Los minutos se cuentan desde el LIMITE, no desde la entrada: 08:29 contra un
    // limite de 08:15 son 14 minutos, no 29. Se devuelven las tres para que la respuesta se pueda
    // leer sin tener que fiarse de la resta.
    let qEnt = db.from("checador_entradas")
      .select("fecha,es_retardo,minutos_retardo,hora,hora_entrada,limite,horario_nombre")
      .eq("profile_id", objetivo);
    if (input.desde) {
      qDias = (qDias as any).gte("fecha", input.desde);
      qEnt  = (qEnt  as any).gte("fecha", input.desde);
    }
    if (input.hasta) {
      qDias = (qDias as any).lte("fecha", input.hasta);
      qEnt  = (qEnt  as any).lte("fecha", input.hasta);
    }
    const { data: dias, error: errDias } = await (qDias as any).order("fecha");
    if (errDias) return { error: errDias.message };
    const { data: entradas, error: errEnt } = await (qEnt as any).order("fecha");
    if (errEnt) return { error: errEnt.message };

    const filasDias = (dias || []) as Array<Record<string, unknown>>;
    const filasEnt  = (entradas || []) as Array<Record<string, unknown>>;

    // Sin un solo dia esperado no hay nada que medir, y decirlo es MUY distinto de decir cero faltas.
    if (filasDias.length === 0) {
      const { data: rango } = await db.from("checador_dias")
        .select("fecha").order("fecha", { ascending: false }).limit(1);
      const ultima = (rango || [])[0] as Record<string, unknown> | undefined;
      return {
        sin_datos: true,
        colaborador: quienEs
          ? [quienEs.nombre, quienEs.paterno, quienEs.materno].filter(Boolean).join(" ")
          : null,
        numero_empleado: quienEs?.numero_empleado ?? null,
        instruccion: "No hay dias de checador cargados para esa persona en ese rango. Eso NO significa "
          + "que no tenga faltas: significa que no hay datos. Puede que no use checador, que su horario "
          + "no este capturado, o que el reporte de esas fechas no se haya importado."
          + (ultima ? ` El ultimo dia con datos en el sistema es ${ultima.fecha}.` : ""),
      };
    }

    const evaluadas = filasEnt.filter((e) => e.es_retardo !== null && e.es_retardo !== undefined);
    const retardos  = evaluadas.filter((e) => e.es_retardo === true);
    const faltas       = filasDias.filter((d) => d.estado === "FALTA");
    const justificados = filasDias.filter((d) => d.estado === "JUSTIFICADO");

    const { data: umb } = await db.from("checador_umbrales")
      .select("retardos_por_descuento").limit(1);
    const porDescuento = Number(((umb || [])[0] as Record<string, unknown>)?.retardos_por_descuento ?? 3);

    return {
      colaborador: quienEs
        ? [quienEs.nombre, quienEs.paterno, quienEs.materno].filter(Boolean).join(" ")
        : null,
      numero_empleado: quienEs?.numero_empleado ?? null,
      area: quienEs?.area ?? null,
      desde: filasDias[0]?.fecha ?? null,
      hasta: filasDias[filasDias.length - 1]?.fecha ?? null,
      dias_esperados: filasDias.length,
      asistio: filasDias.filter((d) => d.checo === true).length,
      faltas_sin_justificar: faltas.length,
      justificados: justificados.length,
      checadas_incompletas: filasDias.filter((d) => d.incompleta === true).length,
      checadas_evaluadas: evaluadas.length,
      retardos: retardos.length,
      minutos_de_retardo: retardos.reduce((a, e) => a + (Number(e.minutos_retardo) || 0), 0),
      puntualidad_pct: evaluadas.length === 0
        ? null
        : Math.round(((evaluadas.length - retardos.length) / evaluadas.length) * 1000) / 10,
      retardos_por_descuento: porDescuento,
      dias_de_descuento: Math.floor(retardos.length / porDescuento) + faltas.length,
      alcance: alcanceDeLaConsulta(deQuien, "dias de asistencia"),
      // QUE DIA llego tarde y A QUE HORA, no solo cuantas veces.
      //
      // Reportado el 13/08/2026: preguntado por «el horario de los 7 retardos» se contesto con el
      // total de minutos, porque era lo unico que habia aqui. La consulta ya traia `hora_entrada` y
      // no se devolvia: un descuido mio, no una limitacion.
      //
      // Sale de `checador_entradas`, la MISMA fuente con la que se cuentan los retardos, asi que la
      // lista tiene por construccion tantos renglones como dice el contador. Sacarla de
      // `checador_dias` habria sido mas facil y podria discrepar, porque esa va por dia y esta por
      // checada.
      dias_de_retardo: retardos
        .slice()
        .sort((a, b) => String(a.fecha).localeCompare(String(b.fecha)))
        .map((e) => ({
          fecha: e.fecha,
          llego: e.hora ?? null,
          entrada_de_su_horario: e.hora_entrada ?? null,
          limite_con_tolerancia: e.limite ?? null,
          minutos_tarde: e.minutos_retardo ?? null,
        })),
      // Los dias que importan, con su fecha. Los que se checaron bien no se listan: son la mayoria y
      // por WhatsApp una lista de 20 renglones correctos esconde los 3 que no lo son.
      dias_con_incidencia: [...faltas, ...justificados]
        .sort((a, b) => String(a.fecha).localeCompare(String(b.fecha)))
        .map((d) => ({
          fecha: d.fecha,
          estado: d.estado,
          motivo: d.justificacion_motivo ?? null,
          tipo: d.justificacion_tipo ?? null,
        })),
    };
  }

  // ── BASE DE CONOCIMIENTO ──────────────────────────────────────────
  //
  // La misma regla que la pagina de Conocimientos: los articulos de `audience = 'all'` los ve
  // cualquiera, y los de `audience = 'admin'` solo un administrador. Son sus dos pestañas.
  //
  // ─── El filtro se escribe A MANO, y no es opcional ──────────────────────────
  //
  // `knowledge_articles` YA tiene la politica correcta -SELECT si `audience = 'all'` o eres admin- pero
  // esta funcion consulta con la LLAVE DE SERVICIO, que se salta RLS por completo. Confiar en la
  // politica aqui seria entregarle a cualquiera con `show_ai` los articulos internos de
  // administracion. La politica sigue siendo la red para la aplicacion; esta linea es la que cuenta
  // para Soli.
  if (name === "buscar_conocimiento") {
    const CAMPOS_KB = "id,title,description,content,category,audience,tags," +
      "file_name,file_url,pinned,updated_at";

    // Un articulo concreto, con su contenido COMPLETO.
    if (input.articulo_id) {
      const dado = String(input.articulo_id).trim();
      if (!esUuid(dado)) {
        return { error: `"${dado}" no es un UUID de articulo. Busca primero por texto y usa el id que venga.` };
      }
      let q1 = db.from("knowledge_articles").select(CAMPOS_KB).eq("id", dado);
      if (!isAdmin) q1 = (q1 as any).eq("audience", "all");
      const { data, error } = await (q1 as any).maybeSingle();
      if (error) return { error: error.message };
      if (!data) {
        return {
          error: "No existe ese articulo, o es de la pestaña de Administradores y no tienes acceso.",
        };
      }
      return { articulo: data, contenido_completo: true };
    }

    let q = db.from("knowledge_articles").select(CAMPOS_KB);
    if (!isAdmin) q = (q as any).eq("audience", "all");
    if (input.categoria) q = (q as any).eq("category", input.categoria);

    if (input.texto) {
      // Se limpian los caracteres que rompen el filtro `or=()` de PostgREST: la coma separa
      // condiciones, y el parentesis las delimita. Es el mismo cuidado que en `tokensDeNombre`, donde
      // una coma en un nombre dejaba la consulta sin sentido.
      const t = String(input.texto).replace(/[,()%*]/g, " ").trim();
      if (t.length > 0) {
        q = (q as any).or(
          `title.ilike.%${t}%,description.ilike.%${t}%,content.ilike.%${t}%`,
        );
      }
    }

    const tope = Math.min(Number(input.limit) || 6, 15);
    const { data, error } = await (q as any)
      .order("pinned", { ascending: false })
      .order("updated_at", { ascending: false })
      .limit(tope);
    if (error) return { error: error.message };

    const filas = (data || []) as Array<Record<string, unknown>>;

    // El contenido se RECORTA en la busqueda.
    //
    // Siete articulos completos son varias decenas de miles de caracteres: llenan la ventana del
    // modelo y encarecen cada pregunta para nada. Se manda un trozo, y si hace falta el resto se pide
    // ese articulo por su id.
    const TOPE_TEXTO = 1200;
    return {
      results: filas.map((a) => {
        const texto = typeof a.content === "string" ? a.content : "";
        const recortado = texto.length > TOPE_TEXTO;
        return {
          ...a,
          content: recortado ? texto.slice(0, TOPE_TEXTO) : texto,
          contenido_recortado: recortado,
        };
      }),
      count: filas.length,
      instruccion: filas.some((a) => (typeof a.content === "string" ? a.content.length : 0) > TOPE_TEXTO)
        ? "Algun contenido viene RECORTADO. Si la respuesta esta en la parte que falta, vuelve a "
          + "llamar con `articulo_id` para leerlo completo, y NO completes lo que no viste."
        : undefined,
      alcance: isAdmin
        ? "Articulos de las dos pestañas: Colaboradores y Administradores."
        : "Solo los articulos de la pestaña Colaboradores.",
    };
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
