// El manejador HTTP del asistente: identidad, permisos, vias directas y la vuelta con el modelo.
//
// ─── Por que esta partido en modulos ─────────────────────────────────────────
//
// Este archivo llego a 2005 lineas y 93 KB. El CLI de Supabase falla con `TransportError` en esta
// maquina, asi que cada despliegue es un pegado a mano en el panel, y a esa medida un pegado se
// corta sin avisar: uno se dio por bueno estando incompleto y costo tres rondas de re-pegado
// perseguir un fallo que no existia.
//
// El orden de los importes es el orden en que se lee el flujo: quien habla, que puede, con que
// instrucciones, que se contesta sin modelo, y que se ejecuta cuando el modelo pide algo.
//
// AL DESPLEGAR: hacen falta LOS OCHO archivos, no solo este.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { ALL_TOOLS, ToolInput } from "./herramientas.ts";
import { CORS, igualesEnTiempoConstante, INTERNAL_SECRET, OLLAMA_BASE, OLLAMA_KEY, OLLAMA_MODEL, OLLAMA_MODEL_RESPALDO, SERVICE_KEY, SUPABASE_URL } from "./config.ts";
import { ADMIN_ONLY_TOOLS, Identidad, PERMISO_POR_HERRAMIENTA, Permisos, puedeUsarHerramienta, QUE_HACE, VIAS_DIRECTAS } from "./permisos.ts";
import { construirPrompt } from "./prompt.ts";
import { afirmaDatoSinRespaldo, preguntaContactoEmergencia, preguntaCumpleanos, preguntaFaltasDe, preguntaIncidenciasDe, preguntaSuEquipo, preguntaSuHorario, preguntaSusVacaciones, soloUnIdentificador, textoAsistencia, textoContactoEmergencia, textoCumpleanos, textoIncidencias, textoEquipoPropio, textoHorario, textoUltimaSolicitud, textoVacacionesPropias } from "./respuestas.ts";
import { runTool } from "./ejecutar.ts";
import { jefeAlQueSeRefiere } from "./nombres.ts";

interface OllamaToolCall { function: { name: string; arguments: ToolInput }; }
interface OllamaMessage  { role: string; content: string; tool_calls?: OllamaToolCall[]; }
interface OllamaResponse { message: OllamaMessage; done: boolean; error?: string; }

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const svc = createClient(SUPABASE_URL, SERVICE_KEY);

    // El cuerpo se lee ANTES de decidir la identidad, porque `actuar_como` viaja en él.
    const cuerpo = await req.json() as {
      messages: Array<{ role: string; content: string }>;
      actuar_como?: string;
      // Pide la configuracion del agente en lugar de una conversacion; ver mas abajo.
      configuracion?: boolean;
    };

    // ── Quién habla ────────────────────────────────────────────────────────────
    //
    // Dos caminos, y el orden importa:
    //
    // 1. Con `Authorization` —la aplicación— la identidad sale del JWT y `actuar_como` se IGNORA.
    //    Sin esto, cualquier usuario de la app podría mandar `actuar_como` y conversar como su jefe.
    //
    // 2. Sin `Authorization`, se acepta una llamada de servidor a servidor que declara a nombre de
    //    quién actúa. Es lo que usa el puente de WhatsApp: el webhook ya identificó a la persona por
    //    su teléfono, pero no tiene su sesión. Va cerrado con un secreto compartido.
    //
    // Lo que NO cambia en ninguno de los dos: el rol, los permisos y la identidad se leen de
    // `profiles`, y el 403 de abajo es el mismo. Ni un permiso se reimplementa por este camino.
    const auth = req.headers.get("Authorization");
    const interno = req.headers.get("X-Interno");

    let actorId: string | null = null;
    let correoActor: string | null = null;

    if (auth) {
      const { data: { user }, error: authErr } = await svc.auth.getUser(auth.replace("Bearer ", ""));
      if (authErr || !user) return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: CORS });
      actorId = user.id;
      correoActor = user.email ?? null;
    } else if (INTERNAL_SECRET.length > 0 && interno && igualesEnTiempoConstante(interno, INTERNAL_SECRET)) {
      const id = (cuerpo.actuar_como ?? "").trim();
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) {
        return new Response(JSON.stringify({ error: "actuar_como debe ser el uuid de un perfil" }), { status: 400, headers: CORS });
      }
      actorId = id;
    } else {
      // Un secreto vacío en el entorno deja la vía interna APAGADA. Si no, no configurarlo la
      // abriría para cualquiera que mandara la cabecera vacía.
      return new Response(JSON.stringify({ error: "No authorization" }), { status: 401, headers: CORS });
    }

    const { data: prof } = await svc.from("profiles")
      .select("role, permissions, nombre, paterno, materno, full_name, puesto, area, numero_empleado, " +
        "jefe_inmediato, gerente_regional, director")
      .eq("id", actorId).single();
    if (!prof) return new Response(JSON.stringify({ error: "Perfil no encontrado" }), { status: 404, headers: CORS });

    const isAdmin    = prof?.role === "admin";
    const hasAiPerm  = (prof?.permissions as Record<string, unknown>)?.show_ai === true;
    if (!isAdmin && !hasAiPerm) {
      return new Response(JSON.stringify({ error: "Forbidden" }), { status: 403, headers: CORS });
    }

    // ── ¿Qué puede hacer el agente? ────────────────────────────────────────
    //
    // La página de configuración pregunta AQUÍ en lugar de tener una copia de la lista en Dart. Es la
    // diferencia entre una pantalla que dice la verdad y una que se queda vieja en cuanto alguien toque
    // esta función: la única fuente es el código que de verdad corre.
    //
    // Solo administradores: no expone datos de nadie, pero sí el mapa completo de accesos del sistema,
    // y eso es información de configuración.
    if (cuerpo.configuracion === true) {
      if (prof?.role !== "admin") {
        return new Response(JSON.stringify({ error: "Solo para administradores." }),
          { status: 403, headers: CORS });
      }
      const permisosDelActor = (prof?.permissions ?? {}) as Permisos;
      return new Response(JSON.stringify({
        modelo: OLLAMA_MODEL,
        // Cadena vacia si no hay ninguno, y la pagina lo dice: es un aviso, no un hueco.
        modelo_respaldo: OLLAMA_MODEL_RESPALDO,
        proveedor: OLLAMA_BASE,
        herramientas: ALL_TOOLS.map((t) => {
          const n = t.function.name;
          return {
            nombre: n,
            que_hace: QUE_HACE[n] ?? "",
            permiso: PERMISO_POR_HERRAMIENTA[n] ?? null,
            solo_admin: ADMIN_ONLY_TOOLS.has(n),
            // Si TU la alcanzas o no, con los permisos que tienes puestos ahora mismo.
            disponible_para_ti: puedeUsarHerramienta(n, prof?.role === "admin", permisosDelActor),
          };
        }),
        vias_directas: VIAS_DIRECTAS,
        ambito: "Solo asuntos de Sisol: colaboradores, incidencias y vacaciones, inventario, "
          + "contactos, asistencia y horarios. Cualquier otra cosa la rechaza.",
      }), { headers: { ...CORS, "Content-Type": "application/json" } });
    }

    const nameParts  = [prof?.nombre || "", prof?.paterno || "", prof?.materno || ""]
      .filter((p: string) => p.length > 0);
    // Por la vía interna no hay correo al que caerse, así que el respaldo es el full_name del perfil
    // y, en último caso, «Usuario». Antes esto usaba `user.email`, que sólo existe con JWT.
    const userFullName = nameParts.length > 0
      ? nameParts.join(" ")
      : (correoActor || (prof?.full_name as string | undefined) || "Usuario");

    const limpio = (v: unknown): string | null => {
      const s = typeof v === "string" ? v.trim() : "";
      return s.length > 0 ? s : null;
    };
    const quien: Identidad = {
      nombreCompleto: userFullName,
      // Sólo el primer nombre: «MARIA GUADALUPE» se saluda mejor como «Maria». Si no hay nombre en
      // el perfil se cae al correo, que al menos identifica a alguien.
      nombrePila: limpio(prof?.nombre)?.split(/\s+/)[0] ?? userFullName.split(/\s+/)[0],
      puesto: limpio(prof?.puesto),
      area: limpio(prof?.area),
      numeroEmpleado: limpio(prof?.numero_empleado),
    };

    const { messages } = cuerpo;

    const permisos = (prof?.permissions ?? {}) as Permisos;

    const tools = ALL_TOOLS.filter(
      (t) => puedeUsarHerramienta(t.function.name, isAdmin, permisos),
    );
    const systemPrompt = construirPrompt(isAdmin, quien, permisos);

    let msgs: OllamaMessage[] = [
      { role: "system", content: systemPrompt },
      ...messages.map(m => ({ role: m.role, content: m.content })),
    ];

    // Qué modelo y con cuántas herramientas se está trabajando.
    //
    // No es un secreto y hace falta: `OLLAMA_MODEL` vive en las variables del proyecto, no en el
    // repositorio, así que desde el código sólo se ve el respaldo del `??` —que no es lo que corre si
    // la variable está configurada, y lo está—. Sin esto, diagnosticar por qué el modelo se salta las
    // herramientas es adivinar. El número de herramientas va aquí porque mandarle quince de golpe es
    // una de las causas candidatas.
    console.log(`modelo ${OLLAMA_MODEL} en ${OLLAMA_BASE}, ${tools.length} herramientas`
      + (OLLAMA_MODEL_RESPALDO ? `, respaldo ${OLLAMA_MODEL_RESPALDO}` : ", SIN respaldo"));

    // ── Via directa: sus propias vacaciones ────────────────────────────────
    //
    // Se resuelve sin pasar por el modelo; ver `preguntaSusVacaciones`. El permiso se comprueba con
    // la misma funcion que usa todo lo demas, asi que esta via no abre nada.
    const ultimoUsuario = [...messages].reverse()
      .find((mm) => mm.role === "user")?.content ?? "";

    if (preguntaSusVacaciones(ultimoUsuario)
        && puedeUsarHerramienta("calcular_vacaciones", isAdmin, permisos)) {
      const propio = await runTool(
        "calcular_vacaciones", {}, svc, isAdmin, actorId, userFullName, permisos,
      ) as Record<string, unknown>;
      if (!propio.error) {
        console.log(`via directa: vacaciones propias de ${actorId}, total ${propio.total_disponible}`);
        return new Response(
          JSON.stringify({
            text: textoVacacionesPropias(propio),
            structured: { type: "vacaciones", data: propio },
          }),
          { headers: { ...CORS, "Content-Type": "application/json" } },
        );
      }
      // Si falla se deja seguir al modelo, que al menos puede explicarlo. El guardia de abajo evita
      // que convierta el fallo en un cero.
      console.log(`via directa fallo, sigue el modelo: ${propio.error}`);
    }

    // ── Via directa: el contacto de emergencia ─────────────────────────────
    //
    // Pedido para la aplicacion Y para WhatsApp. Es informacion que se busca cuando alguien esta en un
    // hospital, asi que no puede depender de que el modelo acierte a llamar la herramienta.
    const emergencia = preguntaContactoEmergencia(ultimoUsuario);
    if (emergencia) {
      // Un numero de empleado va como numero, no como nombre: `resolverPorNombre` buscaria «0163»
      // dentro de los nombres y no encontraria a nadie.
      const entrada = "propio" in emergencia
        ? {}
        : (/^\d{1,4}$/.test(emergencia.quien)
            ? { numero_empleado: emergencia.quien }
            : { nombre_completo: emergencia.quien });
      const datos = await runTool(
        "buscar_contacto_emergencia", entrada, svc, isAdmin, actorId, userFullName, permisos,
      ) as Record<string, unknown>;
      if (!datos.error && datos.necesita_confirmacion !== true) {
        console.log(`via directa: contacto de emergencia de ${datos.numero_empleado ?? actorId}`);
        return new Response(
          JSON.stringify({
            text: textoContactoEmergencia(datos, "propio" in emergencia),
            structured: null,
          }),
          { headers: { ...CORS, "Content-Type": "application/json" } },
        );
      }
      // Un nombre ambiguo, o sin permiso para el de otra persona: lo explica el modelo, que puede
      // mostrar los candidatos o el motivo del rechazo.
      console.log(`via directa de emergencia no resolvio: ${datos.error ?? "ambiguo"}`);
    }

    // ── Via directa: su propio horario ─────────────────────────────────────
    //
    // `profiles.horario` guarda el UUID de un renglon de `schedules`, y preguntar «quiero mi horario»
    // contestaba con ese uuid. Reportado tal cual.
    //
    // Se consulta aqui y no por `buscar_colaborador` porque `USER_COLABORADOR_FIELDS` no incluye
    // `horario`: a un usuario normal esa herramienta no le devuelve el suyo, y anadirlo a esa lista
    // expondria el horario de CUALQUIERA en una busqueda de directorio. Por aqui cada quien ve el suyo.
    if (preguntaSuHorario(ultimoUsuario)) {
      const { data: perfilHorario } = await svc.from("profiles")
        .select("horario").eq("id", actorId).maybeSingle();
      const idHorario = (perfilHorario as Record<string, unknown> | null)?.horario;

      if (typeof idHorario === "string" && idHorario.length > 0) {
        const { data: h } = await svc.from("schedules")
          .select("name,zone,rules").eq("id", idHorario).maybeSingle();
        if (h) {
          const DIAS = ["", "lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"];
          const hhmm = (v: unknown) => String(v ?? "").slice(0, 5);
          const reglas = Array.isArray((h as Record<string, unknown>).rules)
            ? (h as Record<string, unknown>).rules as Array<Record<string, unknown>>
            : [];
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
          const datos = {
            nombre: (h as Record<string, unknown>).name ?? null,
            zona: (h as Record<string, unknown>).zone ?? null,
            dias: Object.keys(porDia).map(Number).sort((a, b) => a - b).map((d) => porDia[d]),
          };
          console.log(`via directa: horario propio de ${actorId}, ${datos.dias.length} dias`);
          return new Response(
            JSON.stringify({ text: textoHorario(datos), structured: null }),
            { headers: { ...CORS, "Content-Type": "application/json" } },
          );
        }
      }
      // Sin horario asignado se dice, y se dice lo que implica: sin el no se pueden calcular faltas.
      console.log(`via directa: ${actorId} sin horario asignado`);
      return new Response(
        JSON.stringify({ text: textoHorario({ dias: [] }), structured: null }),
        { headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }

    // ── Via directa: las faltas o la asistencia de alguien ─────────────────
    //
    // Aqui no hace falta encadenar: `buscar_asistencia` resuelve el nombre por su cuenta y devuelve
    // `necesita_confirmacion` con los candidatos cuando empata con varios, igual que
    // `calcular_vacaciones`. Se le pasa el nombre tal cual y se mira que contesto.
    const faltas = preguntaFaltasDe(ultimoUsuario);
    if (faltas && puedeUsarHerramienta("buscar_asistencia", isAdmin, permisos)) {
      const entrada = "propio" in faltas
        ? {}
        : (isAdmin ? { nombre_completo: faltas.quien } : null);
      // Un usuario normal preguntando por otra persona cae al modelo, que le explica el permiso.
      if (entrada) {
        const asis = await runTool(
          "buscar_asistencia", entrada, svc, isAdmin, actorId, userFullName, permisos,
        ) as Record<string, unknown>;
        if (!asis.error && asis.necesita_confirmacion !== true) {
          const deQuien = "propio" in faltas
            ? "Tu"
            : `${asis.colaborador} (empleado ${asis.numero_empleado})`;
          console.log(`via directa: asistencia de ${asis.numero_empleado ?? actorId}, `
            + `${asis.faltas_sin_justificar ?? "sin datos"} faltas`);
          return new Response(
            JSON.stringify({ text: textoAsistencia(asis, deQuien), structured: null }),
            { headers: { ...CORS, "Content-Type": "application/json" } },
          );
        }
        console.log(`via directa de asistencia no resolvio, sigue el modelo: `
          + `${asis.error ?? "ambiguo"}`);
      }
    }

    // ── Via directa: las incidencias de alguien ────────────────────────────
    //
    // La pregunta donde mas se invento; ver `preguntaIncidenciasDe`. La persona se resuelve AQUI, en
    // codigo, con dos llamadas: buscar_colaborador y luego buscar_incidencias. El encadenamiento no
    // es el problema —lo era que lo hiciera el MODELO— y hacerlo aqui evita tocar la resolucion de
    // nombres de `calcular_vacaciones`, que no tiene pruebas y es el camino mas usado de todos.
    //
    // Si no se resuelve a UNA persona no se contesta: se deja al modelo, que sabe mostrar los
    // candidatos con su estatus y preguntar a cual se refiere.
    const incid = preguntaIncidenciasDe(ultimoUsuario);
    if (incid && puedeUsarHerramienta("buscar_incidencias", isAdmin, permisos)) {
      let objetivo: string | null = null;
      let deQuien = "Tienes";

      if ("propio" in incid) {
        objetivo = actorId;
      } else if (isAdmin) {
        // Un usuario normal preguntando por otra persona cae al modelo, que le explica el permiso.
        const busca = await runTool(
          "buscar_colaborador",
          /^\d{1,4}$/.test(incid.quien)
            ? { numero_empleado: incid.quien }
            : { nombre_completo: incid.quien },
          svc, isAdmin, actorId, userFullName, permisos,
        ) as Record<string, unknown>;
        const filas = (busca.results ?? []) as Array<Record<string, unknown>>;
        if (filas.length === 1) {
          objetivo = String(filas[0].id);
          // El nombre se arma con el MISMO renglon del que salio el id, que es lo que impide repetir
          // el «0170 = MARCO ANTONIO MONTOYA LOPEZ» del historial: el 0170 es Enrique.
          const partes = [filas[0].nombre, filas[0].paterno, filas[0].materno]
            .filter((p) => typeof p === "string" && p.length > 0).join(" ");
          deQuien = `${partes} (empleado ${filas[0].numero_empleado})`;
        } else {
          console.log(`via directa de incidencias: "${incid.quien}" dio `
            + `${filas.length} coincidencias, la resuelve el modelo`);
        }
      }

      if (objetivo) {
        const res = await runTool(
          "buscar_incidencias", { usuario_id: objetivo, limit: 50 },
          svc, isAdmin, actorId, userFullName, permisos,
        ) as Record<string, unknown>;
        if (!res.error) {
          console.log(`via directa: incidencias de ${objetivo}, ${res.count} registros`);
          return new Response(
            JSON.stringify({ text: textoIncidencias(res, deQuien), structured: null }),
            { headers: { ...CORS, "Content-Type": "application/json" } },
          );
        }
        console.log(`via directa de incidencias fallo, sigue el modelo: ${res.error}`);
      }
    }

    // ── Via directa: el mensaje es SOLO un identificador ───────────────────
    //
    // «0170», o un uuid pegado. Ver `soloUnIdentificador` para los tres casos reales que lo motivan.
    // Solo administradores: es la ficha de otra persona.
    const ident = soloUnIdentificador(ultimoUsuario);
    if (ident && isAdmin && puedeUsarHerramienta("calcular_vacaciones", isAdmin, permisos)) {
      const ficha = await runTool(
        "calcular_vacaciones", ident, svc, isAdmin, actorId, userFullName, permisos,
      ) as Record<string, unknown>;
      if (!ficha.error && ficha.necesita_confirmacion !== true) {
        console.log(`via directa: ficha por identificador ${JSON.stringify(ident)} `
          + `-> ${ficha.colaborador}, total ${ficha.total_disponible}`);
        return new Response(
          JSON.stringify({
            // El nombre y el numero salen del MISMO renglon de la base, que es lo que impide volver
            // a juntar «0170» con el nombre de otra persona.
            text: `${ficha.colaborador} (empleado ${ficha.numero_empleado}) tiene `
              + `${ficha.total_disponible} dias de vacaciones disponibles.`
              + textoUltimaSolicitud(ficha, "Su"),
            structured: { type: "vacaciones", data: ficha },
          }),
          { headers: { ...CORS, "Content-Type": "application/json" } },
        );
      }
      console.log(`via directa por identificador no resolvio, sigue el modelo: ${ficha.error ?? "ambiguo"}`);
    }

    // ── Via directa: el equipo que tiene asignado ──────────────────────────
    //
    // Se pasa `usuario_id` explicitamente, y ahi esta el arreglo: a un administrador que no lo pase,
    // `buscar_inventario` le devuelve el inventario de TODA la empresa, y de ahi salio contestarle a
    // Angel con el LAP-TOP de Abraham. Ver `preguntaSuEquipo`.
    if (preguntaSuEquipo(ultimoUsuario)
        && puedeUsarHerramienta("buscar_inventario", isAdmin, permisos)) {
      const mio = await runTool(
        "buscar_inventario", { usuario_id: actorId }, svc, isAdmin, actorId, userFullName, permisos,
      ) as Record<string, unknown>;
      if (!mio.error) {
        console.log(`via directa: equipo propio de ${actorId}, ${mio.count} equipos`);
        return new Response(
          JSON.stringify({
            text: textoEquipoPropio(mio),
            structured: null,
          }),
          { headers: { ...CORS, "Content-Type": "application/json" } },
        );
      }
      console.log(`via directa de equipo fallo, sigue el modelo: ${mio.error}`);
    }

    // «las vacaciones de mi jefe»: el perfil ya dice quien es.
    //
    // Antes preguntaba «¿cómo se llama tu jefe?», que es correcto pero innecesario: `jefe_inmediato`
    // trae el nombre completo y lo tienen 1738 de los 2488 perfiles. Solo para administradores,
    // porque son datos de otra persona; a un usuario normal la herramienta le dara el error de
    // permiso y el modelo lo explicara.
    const jefe = jefeAlQueSeRefiere(ultimoUsuario, prof as Record<string, unknown>);
    if (jefe && isAdmin && puedeUsarHerramienta("calcular_vacaciones", isAdmin, permisos)) {
      const deJefe = await runTool(
        "calcular_vacaciones", { nombre_completo: jefe }, svc, isAdmin, actorId, userFullName, permisos,
      ) as Record<string, unknown>;
      // `necesita_confirmacion` no es un error, y por eso no basta con mirar `error`.
      //
      // Si el nombre del jefe empata con varias personas, la herramienta devuelve la lista de
      // candidatos SIN campo `error`. Esta via daba entonces «undefined tiene undefined dias»: un
      // fallo que ya existia y que se volvio probable al dejar de descartar a las bajas, porque
      // ahora un nombre que empata con una baja y un vigente pide confirmacion en lugar de elegir.
      // Se deja seguir al modelo, que es quien sabe presentar la tabla y preguntar a cual se refiere.
      if (deJefe.necesita_confirmacion === true) {
        console.log(`via directa de jefe: "${jefe}" empata con `
          + `${deJefe.total_coincidencias ?? 0}, la resuelve el modelo`);
      } else if (!deJefe.error) {
        console.log(`via directa: vacaciones de "${jefe}", total ${deJefe.total_disponible}`);
        return new Response(
          JSON.stringify({
            text: `${deJefe.colaborador} tiene ${deJefe.total_disponible} dias de vacaciones `
              + `disponibles. Lo tomo de tu perfil, donde figura como tu jefe.`
              + textoUltimaSolicitud(deJefe, "Su"),
            structured: { type: "vacaciones", data: deJefe },
          }),
          { headers: { ...CORS, "Content-Type": "application/json" } },
        );
      } else {
        console.log(`via directa de jefe fallo, sigue el modelo: ${deJefe.error}`);
      }
    }

    // Cumpleaños: el mes se lee de la pregunta y la consulta es determinista.
    // La penultima pregunta de la persona, para entender un seguimiento como «y de septiembre?».
    const preguntasUsuario = messages.filter((mm) => mm.role === "user").map((mm) => mm.content);
    const anteriorUsuario = preguntasUsuario[preguntasUsuario.length - 2] ?? "";

    const cumples = preguntaCumpleanos(ultimoUsuario, anteriorUsuario);
    if (cumples) {
      const datos = await runTool(
        "buscar_cumpleanos",
        { ...(cumples.mes ? { mes: cumples.mes } : {}), solo_esta_semana: cumples.soloEstaSemana },
        svc, isAdmin, actorId, userFullName, permisos,
      ) as Record<string, unknown>;
      if (!datos.error) {
        console.log(`via directa: cumpleaños mes ${datos.mes}, ${datos.count} personas`);
        return new Response(
          JSON.stringify({ text: textoCumpleanos(datos), structured: null }),
          { headers: { ...CORS, "Content-Type": "application/json" } },
        );
      }
      console.log(`via directa de cumpleaños fallo, sigue el modelo: ${datos.error}`);
    }

    let structuredData: unknown = null;
    let iterations = 0;

    /// Herramientas que devolvieron datos en este turno, sin error. Es lo que permite distinguir un
    /// dato consultado de uno inventado; ver `afirmaDatoSinRespaldo`.
    const conDatos = new Set<string>();

    /// Cuantas herramientas se llamaron, con o sin exito. Ver `afirmaDatoSinRespaldo`.
    let llamadas = 0;

    /// El modelo con el que se esta trabajando en ESTE turno.
    ///
    /// Si se cambia al respaldo, se queda cambiado para el resto del turno: en medio de una vuelta de
    /// herramientas, alternar de modelo entre una llamada y la siguiente es pedirle a uno que continue
    /// una conversacion que empezo otro.
    let modeloEnUso = OLLAMA_MODEL;

    /// Pide una respuesta al modelo, con respaldo si el PROVEEDOR falla.
    ///
    /// Devuelve la respuesta de Ollama, o la respuesta HTTP ya armada para el usuario cuando no hay
    /// nada que hacer.
    ///
    /// Se reintenta con el respaldo SOLO ante un fallo del proveedor: 5xx, 429, o un cuerpo que no es
    /// JSON. Un 400 es nuestro —herramientas mal formadas, por ejemplo— y cambiar de modelo no lo
    /// arregla; reintentarlo solo gasta tiempo y esconde el error.
    const pedirAlModelo = async (): Promise<
      { ok: true; ollama: OllamaResponse } | { ok: false; respuesta: Response }
    > => {
      const intentos = [modeloEnUso];
      if (OLLAMA_MODEL_RESPALDO && OLLAMA_MODEL_RESPALDO !== modeloEnUso) {
        intentos.push(OLLAMA_MODEL_RESPALDO);
      }

      let ultimoEstado = 0;
      let ultimoDetalle = "";
      let ultimoModelo = modeloEnUso;

      for (const modelo of intentos) {
        const apiRes = await fetch(`${OLLAMA_BASE}/chat`, {
          method: "POST",
          headers: { "Content-Type": "application/json", "Authorization": `Bearer ${OLLAMA_KEY}` },
          body: JSON.stringify({ model: modelo, messages: msgs, tools, stream: false }),
        });

        // Un fallo DEL PROVEEDOR se dice que es del proveedor.
        //
        // Antes se reenviaba su mensaje tal cual y en pantalla salia «Internal Server Error
        // (ref: ...)», que parece un fallo del sistema. Costo veinte minutos de buscar el error en
        // nuestro codigo: ese «ref:» con un uuid es de Ollama, no de Supabase, y lo delataba el tiempo
        // -432 ms, muy poco para que el modelo hubiera contestado- y que fallara incluso con un «hola».
        let ollama: OllamaResponse | null = null;
        try {
          ollama = await apiRes.json() as OllamaResponse;
        } catch {
          ultimoDetalle = (await apiRes.text().catch(() => "")).slice(0, 200)
            || "cuerpo no-JSON, vacio";
        }

        if (ollama && apiRes.ok) {
          if (modelo !== modeloEnUso) {
            console.log(`RESPALDO: ${modeloEnUso} fallo (${ultimoEstado}), contesto ${modelo}`);
            modeloEnUso = modelo;
          }
          return { ok: true, ollama };
        }

        ultimoEstado = apiRes.status;
        ultimoModelo = modelo;
        if (ollama) ultimoDetalle = ollama.error || JSON.stringify(ollama).slice(0, 300);
        console.error(`Ollama respondio ${apiRes.status} con ${modelo}: ${ultimoDetalle}`);

        // Un fallo que no es del proveedor no se reintenta con otro modelo.
        const delProveedor = apiRes.status >= 500 || apiRes.status === 429 || !ollama;
        if (!delProveedor) break;
      }

      // El estado se registra porque es lo que distingue una cuota agotada (429) de una caida (5xx)
      // sin tener que adivinar.
      const porCuota = ultimoEstado === 429 || /quota|rate|limit/i.test(ultimoDetalle);
      const conRespaldo = intentos.length > 1
        ? ` Tambien se intento con el respaldo (${OLLAMA_MODEL_RESPALDO}).`
        : ` No hay modelo de respaldo configurado.`;
      return {
        ok: false,
        respuesta: new Response(JSON.stringify({
          error: porCuota
            ? `El servicio del modelo alcanzó su límite de uso. No es un problema de tus datos: `
              + `hay que revisar la cuota de la cuenta. (${ultimoEstado}: ${ultimoDetalle})`
              + conRespaldo
            : `El servicio del modelo (${ultimoModelo}) falló con ${ultimoEstado}. `
              + `No es un problema de tus datos ni del sistema.${conRespaldo} `
              + `Detalle: ${ultimoDetalle}`,
        }), { status: 502, headers: CORS }),
      };
    };

    while (iterations++ < 15) {
      const intento = await pedirAlModelo();
      if (!intento.ok) return intento.respuesta;
      const ollama = intento.ollama;

      const msg = ollama.message;
      if (!msg.tool_calls || msg.tool_calls.length === 0) {
        let texto = (msg.content || "").trim();

        // Un dato de la base que ninguna herramienta respaldo NO sale de aqui.
        //
        // Se sustituye el texto en lugar de dejarlo pasar con una advertencia: una tabla de periodos
        // con cifras inventadas es mas creible que cualquier aviso que se le ponga al lado, y quien
        // la lea no va a dudar de ella.
        if (afirmaDatoSinRespaldo(texto, conDatos, llamadas > 0)) {
          console.log(
            `respuesta BLOQUEADA, afirmaba datos sin herramienta ` +
            `(herramientas con datos: ${[...conDatos].join(",") || "ninguna"}): ` +
            texto.slice(0, 300),
          );
          // El mensaje no menciona nombres ni números de empleado: se disparaba también con
          // cumpleaños, y ahí pedir «el nombre con apellidos» no tenía ningún sentido.
          texto = "No pude confirmar ese dato con el sistema, así que prefiero no dártelo. "
            + "Vuelve a preguntármelo y lo consulto de nuevo.";
          structuredData = null;
        }

        return new Response(
          JSON.stringify({ text: texto, structured: structuredData }),
          { headers: { ...CORS, "Content-Type": "application/json" } }
        );
      }

      msgs.push({ role: "assistant", content: msg.content || "", tool_calls: msg.tool_calls });
      for (const tc of msg.tool_calls) {
        const { name, arguments: args } = tc.function;
        // Queda registro de QUÉ pidió el modelo, no sólo de lo que acabó contestando.
        //
        // Sin esto no hay forma de saber si una respuesta rara viene de la herramienta o del modelo.
        // Costó un diagnóstico a ciegas: Soli afirmó «0 días disponibles» de alguien con 102, y no
        // había manera de ver con qué argumentos había llamado a calcular_vacaciones.
        console.log(`herramienta ${name} ${JSON.stringify(args)}`);
        const result =
          // `actorId` y no `user.id`: por la vía interna no hay objeto `user`, y con él aquí la
          // primera herramienta que pidiera WhatsApp habría reventado con `user is not defined`.
          await runTool(name, args, svc, isAdmin, actorId, userFullName, permisos);
        const r = result as Record<string, unknown>;
        llamadas++;
        // «Trajo datos» NO es lo mismo que «no fallo». Un resultado con `necesita_confirmacion` trae
        // candidatos, que sirven para mostrar una lista pero NO para afirmar el saldo de nadie. Si
        // contara como datos, el modelo podria colar una cifra inventada en ese mismo turno.
        const trajoDatos = !r.error
          && (Array.isArray(r.results) || Array.isArray(r.periodos) || r.success === true);
        if (trajoDatos) conDatos.add(name);
        console.log(
          `resultado ${name}: ` +
          (r.error ? `ERROR ${r.error}` :
            Array.isArray(r.results) ? `${r.results.length} filas` :
            Array.isArray(r.periodos) ? `${(r.periodos as unknown[]).length} periodos, total ${r.total_disponible}` :
            "ok"),
        );

        // Capturar datos estructurados para el UI de Flutter
        if (name === "buscar_colaborador" && r.results) {
          structuredData = { type: "collaborators", data: r.results };
        } else if (["buscar_incidencias","buscar_inventario","buscar_contactos"].includes(name) && r.results) {
          structuredData = { type: name.replace("buscar_","").replace("ver_",""), data: r.results };
        } else if (name === "calcular_vacaciones" && Array.isArray(r.periodos)) {
          structuredData = { type: "vacaciones", data: result };
        } else if (name === "calcular_vacaciones" && Array.isArray(r.candidatos)
                   && (r.candidatos as unknown[]).length > 0) {
          // Un nombre ambiguo pinta las tarjetas de colaborador, no una ficha de vacaciones a medias.
          // Es lo que hace que la persona VEA a los candidatos con su foto, número y puesto, en lugar
          // de leer «dime a cuál te refieres» sin más.
          structuredData = { type: "collaborators", data: r.candidatos };
        } else if (r.success) {
          structuredData = { type: "success", tool: name, data: result };
        }

        msgs.push({ role: "tool", content: JSON.stringify(result) });
      }
    }

    return new Response(JSON.stringify({ error: "Máximo de iteraciones alcanzado" }), { status: 500, headers: CORS });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return new Response(JSON.stringify({ error: msg }), { status: 500, headers: CORS });
  }
});
