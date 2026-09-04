import { createClient } from "jsr:@supabase/supabase-js@2";

import {
  CORS, hoy, hoyISO, OLLAMA_BASE, OLLAMA_KEY, SERVICE_KEY, SOL_MODEL, SOL_MODEL_RESPALDO,
  SUPABASE_URL,
} from "./config.ts";
import { ALL_TOOLS, AMBITO, construirPrompt, QUE_HACE } from "./herramientas.ts";
import {
  AFECTADOS_POR_PROMOCION,
  campoUnico,
  desarrolloDelHilo,
  documentoMencionado,
  preguntaUbicacion,
  sinTablas,
  textoDe,
} from "./directas.ts";
import { runTool } from "./ejecutar.ts";

// ─── SOL, el asistente comercial ─────────────────────────────────────────────
//
// Aparte de Soli a proposito: otro modelo, otro prompt, otras herramientas y otra pantalla. Comparte
// con ella la CUENTA de Ollama —misma llave, decision del 02/09/2026— y una sola cosa mas: quien es
// quien. `profiles` y los permisos siguen siendo la unica definicion, porque duplicarlos seria tener
// dos verdades sobre la misma persona.
//
// Lo que NO tiene, y es deliberado:
//
//   - No hay puente de WhatsApp. SOL vive dentro de la aplicacion. Si algun dia lo necesita, hara
//     falta un segundo numero: un solo numero no puede repartir entre dos asistentes sin que algo
//     adivine a cual va cada mensaje.
//   - No hay via servidor-a-servidor. Sin WhatsApp no hace falta, y un secreto que no se usa es un
//     secreto que se filtra sin que nadie lo note.
//   - No se puede configurar desde la aplicacion. Todo esta en variables de entorno y la pantalla
//     solo lo MUESTRA.

interface Mensaje {
  role: string;
  content: string;
  /// Las llamadas a herramientas que pidió el modelo. Van de vuelta en la conversación.
  tool_calls?: unknown;
}

interface Cuerpo {
  messages?: Mensaje[];
  /// Pide la configuracion en lugar de una conversacion.
  configuracion?: boolean;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { ...CORS, "Content-Type": "application/json" } });
  }

  const responde = (cuerpo: Record<string, unknown>, status = 200) =>
    new Response(JSON.stringify(cuerpo),
      { status, headers: { ...CORS, "Content-Type": "application/json" } });

  const svc = createClient(SUPABASE_URL, SERVICE_KEY);

  // ── Quien pregunta ─────────────────────────────────────────────────────────
  //
  // Siempre con sesion: SOL no tiene via interna. Sin `Authorization` no se atiende.
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth) return responde({ error: "Falta la sesion." }, 401);

  const { data: { user } } = await svc.auth.getUser(auth.replace("Bearer ", ""));
  if (!user) return responde({ error: "Sesion invalida." }, 401);

  const { data: prof } = await svc.from("profiles")
    .select("nombre,paterno,role,permissions").eq("id", user.id).maybeSingle();

  const esAdmin = prof?.role === "admin";
  const permisos = (prof?.permissions ?? {}) as Record<string, unknown>;

  // El MISMO permiso que abre la pagina. Si aqui se aceptara a cualquiera con sesion, la pagina
  // seria una sugerencia y no un control.
  if (!esAdmin && permisos.show_sol !== true) {
    return responde({ error: "No tienes acceso a SOL." }, 403);
  }

  let cuerpo: Cuerpo;
  try {
    cuerpo = await req.json() as Cuerpo;
  } catch {
    return responde({ error: "Cuerpo ilegible." }, 400);
  }

  // ── La configuracion, para la pestaña que la muestra ───────────────────────
  //
  // La pantalla pregunta AQUI en lugar de tener una copia en Dart, por lo mismo que en Soli: la
  // unica fuente es el codigo que de verdad corre. Una copia en la aplicacion se queda vieja en
  // cuanto alguien toque esta funcion, y entonces la pantalla miente.
  if (cuerpo.configuracion === true) {
    if (!esAdmin) return responde({ error: "Solo para administradores." }, 403);
    return responde({
      modelo: SOL_MODEL,
      modelo_respaldo: SOL_MODEL_RESPALDO,
      proveedor: OLLAMA_BASE,
      // Se dice si la cuenta esta puesta, NUNCA la llave. Que este configurada es informacion de
      // diagnostico; su valor es un secreto.
      cuenta_configurada: OLLAMA_KEY.length > 0,
      cuenta_compartida_con: "Soli (misma cuenta de Ollama, modelo distinto)",
      editable_desde_la_app: false,
      herramientas: ALL_TOOLS.map((t) => ({
        nombre: t.function.name,
        que_hace: QUE_HACE[t.function.name] ?? "",
      })),
      ambito: AMBITO,
    });
  }

  // ── Sin modelo configurado no se llama a nadie ─────────────────────────────
  //
  // Se dice claro en lugar de intentarlo y devolver el error del proveedor: «modelo no encontrado»
  // manda a diagnosticar la cuenta cuando lo que falta es una variable.
  if (SOL_MODEL.length === 0) {
    return responde({
      text: "SOL todavia no tiene modelo configurado. Se pone en la variable SOL_MODEL de "
        + "Supabase; la pestaña de Configuracion muestra lo que hay puesto ahora.",
      sin_configurar: true,
    });
  }
  if (OLLAMA_KEY.length === 0) {
    return responde({
      text: "Falta la llave del proveedor de IA (OLLAMA_API_KEY). SOL no puede responder sin ella.",
      sin_configurar: true,
    });
  }

  const mensajes = Array.isArray(cuerpo.messages) ? cuerpo.messages : [];
  if (mensajes.length === 0) return responde({ error: "Sin mensajes." }, 400);

  const nombrePila = (prof?.nombre ?? "").toString().split(/\s+/)[0] || "asesor";

  // ── Vias directas: un solo campo, contestado SIN modelo ───────────────────
  //
  // Por que existen: el 03/09/2026, con la direccion completa ya capturada, SOL contesto dos veces
  // «AG117 se encuentra en CDMX» -recortando el campo- y doce minutos antes «AG117 se ubica en
  // Tulum», que es otro desarrollo. El dato estaba bien las dos veces.
  //
  // Y de paso cuestan cero. Una pregunta por el modelo son ~8,700 tokens de promedio, de los que
  // ~4,800 son el prompt y las herramientas reenviados en cada vuelta; un campo que ya esta en la
  // base no necesita nada de eso.
  //
  // Hay TRES puertas que hay que pasar, y las tres son para no dar una respuesta peor que la del
  // modelo:
  //
  //   1. Un solo campo preguntado. Con dos, contesta el modelo: un atajo contestaria uno y
  //      dejaria el otro sin respuesta, sin que nadie lo notara.
  //   2. El dato capturado. Si esta vacio pasa al modelo, que sabe ofrecer el brochure o la lista
  //      de precios en su lugar; un «no esta capturado» dicho aqui perderia esa ayuda.
  //   3. Sin promocion vigente que lo cambie, para el enganche y las mensualidades.
  const ultimoMensaje = mensajes.at(-1)?.content ?? "";
  const campo = campoUnico(ultimoMensaje);
  if (campo !== null) {
    const { data: catalogo } = await svc.from("desarrollos")
      .select("id,nombre,ubicacion,etapa,amenidades,enganche_pct,mensualidades")
      .eq("is_active", true);
    const filas = (catalogo ?? []) as Array<Record<string, unknown>>;
    const nombres = filas.map((d) => String(d.nombre));

    // La ubicacion tiene una trampa propia: el desarrollo «AG117» y la unidad «AG008» tienen la
    // misma forma, y «donde esta el AG008» lo contesta el inventario, no esto. Distinguirlas
    // necesita el catalogo, que es justo lo que se acaba de consultar.
    const esDeVerdad = campo !== "ubicacion" || preguntaUbicacion(ultimoMensaje, nombres);

    if (esDeVerdad) {
      const cual = desarrolloDelHilo(mensajes, nombres);
      const fila = filas.find((d) => String(d.nombre) === cual);

      if (fila !== undefined) {
        // Una promocion viva puede cambiar el enganche o el plazo. Si la hay, el dato de la tabla
        // ya no es toda la verdad, asi que contesta el modelo, que tiene las dos cosas delante.
        let hayPromoViva = false;
        if (AFECTADOS_POR_PROMOCION.includes(campo)) {
          const { data: promos } = await svc.from("promociones")
            .select("id")
            .or(`desarrollo_id.eq.${fila.id},desarrollo_id.is.null`)
            .eq("is_active", true)
            .lte("vigente_desde", hoyISO)
            .gte("vigente_hasta", hoyISO);
          hayPromoViva = ((promos ?? []) as unknown[]).length > 0;
        }

        const texto = hayPromoViva ? null : textoDe(campo, String(fila.nombre), fila);
        if (texto !== null) {
          await bitacora(svc, user.id, "via-directa", { prompt: 0, respuesta: 0 },
            ultimoMensaje, texto);
          return responde({ text: texto, modelo: "via-directa", documentos: [] });
        }
      }
    }
  }

  const conversacion: Mensaje[] = [
    { role: "system", content: construirPrompt(nombrePila, hoy) },
    ...mensajes.map((m) => ({ role: m.role, content: m.content })),
  ];

  // Cuantas llamadas al modelo se permiten por pregunta. Dos vueltas alcanzan para «consulta y
  // redacta»; sin tope, una herramienta que devuelve vacio puede dejarlo en bucle.
  const MAX_VUELTAS = 4;
  let modeloEnUso = SOL_MODEL;

  // Con que modelo se esta trabajando. No es un secreto y hace falta: `SOL_MODEL` vive en las
  // variables del proyecto, no en el repositorio, asi que desde el codigo solo se ve el respaldo del
  // `??` —que es cadena vacia y no es lo que corre—. Sin esto, diagnosticar por que SOL se salta las
  // herramientas es adivinar. Es la misma linea que tiene Soli, y por el mismo motivo.
  console.log(`SOL: modelo ${modeloEnUso} en ${OLLAMA_BASE}, ${ALL_TOOLS.length} herramientas`
    + (SOL_MODEL_RESPALDO ? `, respaldo ${SOL_MODEL_RESPALDO}` : `, SIN respaldo`));
  let usoTotal = { prompt: 0, respuesta: 0 };
  /// Cada intento fallido, para poder informarlos todos y no solo el ultimo.
  const fallos: Array<{ modelo: string; status: number; detalle: string }> = [];

  /// Los documentos que devolvieron las herramientas, para que los pinte la APLICACION.
  ///
  /// El modelo no escribe las URL: las manda la funcion aparte y la pantalla las convierte en
  /// botones con el nombre del documento. Dos razones, y la segunda es la que importa:
  ///
  ///   1. Una URL de Drive tiene setenta caracteres y en un telefono es imposible atinarle con el
  ///      dedo. Un boton que dice «Brochure» si.
  ///   2. Si el enlace sale de los DATOS y no del texto, el modelo no puede inventarlo. Es la misma
  ///      razon por la que la aplicacion pinta las vacaciones de Soli desde los datos crudos en vez
  ///      de confiar en su prosa.
  const documentos: Array<Record<string, unknown>> = [];
  const vistos = new Set<string>();

  /// Las unidades que devolvio el inventario, para que la APLICACION pinte la tabla.
  ///
  /// Misma idea que los documentos: el chat pinta texto plano, asi que una tabla de markdown se ve
  /// como una reja de barras. Mandando las filas, la tabla la dibuja la pantalla —alineada, con los
  /// precios ya formateados— y el modelo no la puede romper.
  const unidades: Array<Record<string, unknown>> = [];
  const unidadesVistas = new Set<string>();

  /// Los enlaces que DE VERDAD salieron de una herramienta.
  ///
  /// Es la lista blanca del guardia de abajo. Se llena con lo que devuelven las herramientas y con
  /// nada mas: un enlace que no este aqui es un enlace que el modelo se invento.
  const enlacesLegitimos = new Set<string>();

  for (let vuelta = 0; vuelta < MAX_VUELTAS; vuelta++) {
    let r: Response;
    try {
      r = await fetch(`${OLLAMA_BASE}/chat`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${OLLAMA_KEY}`,
        },
        body: JSON.stringify({
          model: modeloEnUso,
          messages: conversacion,
          tools: ALL_TOOLS,
          stream: false,
        }),
      });
    } catch (e) {
      return responde({ error: `No se pudo hablar con el proveedor: ${e}` }, 502);
    }

    if (!r.ok) {
      const detalle = (await r.text()).slice(0, 300);
      console.error(`SOL: ${modeloEnUso} respondio ${r.status}: ${detalle}`);
      fallos.push({ modelo: modeloEnUso, status: r.status, detalle });
      // Un 400 es NUESTRO —herramientas mal formadas— y cambiar de modelo no lo arregla.
      if (r.status !== 400 && SOL_MODEL_RESPALDO && modeloEnUso !== SOL_MODEL_RESPALDO) {
        console.log(`SOL: se cambia al respaldo ${SOL_MODEL_RESPALDO}`);
        modeloEnUso = SOL_MODEL_RESPALDO;
        continue;
      }
      // Se informan TODOS los fallos, no solo el ultimo.
      //
      // El 02/09/2026 el mensaje que llego a la pantalla fue «el proveedor respondio 404», que era
      // el error del RESPALDO: un nombre de modelo inexistente. El del principal era un 402 -el
      // modelo no esta incluido en el plan de la cuenta-, que es el problema de verdad y el unico
      // accionable. El respaldo tapo la causa y mando a diagnosticar lo que no era.
      //
      // Y se traduce el codigo a algo que se pueda hacer: un 402 se arregla en la cuenta y un 404
      // en el nombre de la variable. Son dos sitios distintos.
      const explica = (f: { modelo: string; status: number }) => {
        const que = f.status === 402
          ? "no esta incluido en el plan de la cuenta de Ollama"
          : f.status === 404
          ? "no existe con ese nombre; revisa la etiqueta exacta en ollama.com"
          : f.status === 401 || f.status === 403
          ? "la llave del proveedor no lo autoriza"
          : `el proveedor respondio ${f.status}`;
        return `${f.modelo}: ${que}`;
      };
      return responde({ error: fallos.map(explica).join(" | "), fallos }, 502);
    }

    const datos = await r.json() as {
      message?: { content?: string; tool_calls?: Array<{ function: { name: string; arguments: unknown } }> };
      prompt_eval_count?: number;
      eval_count?: number;
    };
    usoTotal.prompt += datos.prompt_eval_count ?? 0;
    usoTotal.respuesta += datos.eval_count ?? 0;

    const msg = datos.message;
    const llamadas = msg?.tool_calls ?? [];

    if (llamadas.length === 0) {
      const texto = (msg?.content ?? "").trim();

      // ── Ningun enlace que no venga de una herramienta ──────────────────────
      //
      // El 02/09/2026, preguntado por los documentos de BONANZA COTO 4, SOL contesto con cuatro
      // enlaces cuyos identificadores terminaban en «_example1», «_example2», «_example3» y
      // «_example4», y con nombres de documento que no existen -«Planta Arquitectonica», «Formato
      // de Reserva»-. El registro lo delato: en esa vuelta NO llamo a buscar_documento ni una vez.
      // Contesto de memoria.
      //
      // Un precio inventado se nota. Un enlace inventado se REENVIA: el asesor lo manda al cliente
      // y el error aparece del otro lado. Por eso esto no es un aviso, es un bloqueo.
      //
      // La comprobacion es exacta y no una heuristica: se sabe con certeza que enlaces devolvieron
      // las herramientas en esta conversacion. Cualquier otro esta inventado.
      const enlacesDichos = (texto.match(/https?:\/\/[^\s"'<>)\]]+/g) ?? [])
        .map((u) => u.replace(/[.,;:!?)\]]+$/, ""));

      // Los que no salieron de una herramienta EN ESTA VUELTA se comprueban contra la BASE.
      //
      // El modelo recuerda enlaces de turnos anteriores de la conversacion, y esos son legitimos:
      // salieron de una herramienta, solo que antes. Validando contra la tabla en lugar de contra
      // la vuelta actual, un enlace real recordado se convierte en boton en vez de desaparecer al
      // recortar el texto -que es lo que paso el 02/09/2026 a las 17:09-.
      const dudosos = enlacesDichos.filter((u) => !enlacesLegitimos.has(u));
      if (dudosos.length > 0) {
        const { data: enBase } = await svc.from("documentos")
          .select("categoria,idioma,variante,nombre,url,es_carpeta,visibilidad")
          .in("url", dudosos);
        for (const d of (enBase ?? []) as Array<Record<string, unknown>>) {
          const url = String(d.url);
          enlacesLegitimos.add(url);
          if (vistos.has(url)) continue;
          vistos.add(url);
          documentos.push({
            desarrollo: null,
            categoria: d.categoria ?? null,
            nombre: d.nombre ?? d.categoria ?? "Documento",
            idioma: d.idioma ?? null,
            variante: d.variante ?? null,
            url,
            es_carpeta: d.es_carpeta === true,
            visibilidad: d.visibilidad ?? null,
          });
        }
      }

      const inventados = enlacesDichos.filter((u) => !enlacesLegitimos.has(u));

      if (inventados.length > 0) {
        console.error(`SOL: ${modeloEnUso} invento ${inventados.length} enlaces: `
          + inventados.slice(0, 3).join(" | "));
        const aviso = "No pude confirmar esos documentos con el sistema, asi que prefiero no "
          + "darte enlaces que podrian no existir. Preguntame otra vez nombrando el desarrollo "
          + "-por ejemplo «documentos de Bonanza Coto 4»- y los consulto.";
        await bitacora(svc, user.id, modeloEnUso, usoTotal, mensajes.at(-1)?.content ?? "",
          `[ENLACES INVENTADOS: ${inventados.join(" ")}] ${texto}`);
        return responde({ text: aviso, enlaces_invalidos: inventados.length, documentos });
      }

      // Las URL se quitan del TEXTO: ya van como botones, y repetirlas es lo que el usuario
      // pidio eliminar. Se hace aqui y no con el prompt porque el prompt ya se lo dice y las
      // escribe igual; confiar en que obedezca es lo que se lleva fallando toda la tarde.
      //
      // Va DESPUES del guardia, a proposito: primero se comprueba que no haya enlaces inventados
      // -para eso hay que verlos- y solo despues se recortan.
      // Se quitan las URL y, si hay unidades que pintar, tambien la tabla que el modelo haya
      // escrito: la de verdad la dibuja la aplicacion. Solo cuando hay unidades, para que una tabla
      // de otra cosa no desaparezca sin sustituto.
      let limpio = sinEnlaces(texto);
      if (unidades.length > 0) limpio = sinTablas(limpio);

      // Los botones que vienen A CUENTO, no todos los que se consultaron.
      //
      // `buscar_desarrollo` devuelve los documentos del desarrollo junto con sus datos, a proposito:
      // asi el modelo puede ofrecer la lista de precios cuando el precio no esta capturado. Pero
      // todos acababan de botones, asi que preguntar «de cuanto es el enganche?» contestaba bien y
      // ademas pintaba las carpetas del Drive, que ahi no hacen falta.
      //
      // La regla: lo que se pidio expresamente -`buscar_documento`- siempre sale; lo que vino de
      // rebote sale solo si la respuesta lo nombra. Se mira el texto SIN recortar, que son las
      // palabras del modelo.
      const paraLaApp = documentos
        .filter((d) => d.origen === "buscar_documento" || documentoMencionado(texto, d))
        .map(({ origen: _origen, ...resto }) => resto);

      await bitacora(svc, user.id, modeloEnUso, usoTotal, mensajes.at(-1)?.content ?? "", texto);
      return responde({
        text: limpio || "No pude armar una respuesta. Vuelve a preguntarme de otra forma.",
        modelo: modeloEnUso,
        // Los botones que va a pintar la aplicacion. Vienen de las herramientas, no del texto.
        documentos: paraLaApp,
        // Y la tabla, por lo mismo.
        unidades,
      });
    }

    // Las llamadas van DE VUELTA en el mensaje del asistente. Sin ellas, el modelo no ve que ya
    // consultó: la conversación le muestra el resultado de una herramienta sin la petición que lo
    // provocó, así que vuelve a pedirla.
    //
    // Es lo que pasó el 02/09/2026 con la primera pregunta real: cuatro llamadas a
    // `buscar_desarrollo` seguidas hasta agotar el tope de vueltas, y el usuario recibió el mensaje
    // de «me quedé dando vueltas» creyendo que era la respuesta buena. Soli lo hacía bien desde el
    // principio -`msgs.push({ role: "assistant", content, tool_calls })`- y yo lo omití al escribir
    // esta función.
    conversacion.push({
      role: "assistant",
      content: msg?.content ?? "",
      tool_calls: msg?.tool_calls,
    });
    for (const c of llamadas) {
      const args = typeof c.function.arguments === "string"
        ? JSON.parse(c.function.arguments || "{}")
        : (c.function.arguments ?? {});
      const resultado = await runTool(c.function.name, args as Record<string, unknown>, svc);
      const crudo = JSON.stringify(resultado);
      for (const u of crudo.match(/https?:\/\/[^\s"'<>\\]+/g) ?? []) {
        enlacesLegitimos.add(u);
      }
      // Las unidades del inventario, tal como salieron.
      if (c.function.name === "buscar_unidades") {
        for (const u of (resultado.resultados ?? []) as Array<Record<string, unknown>>) {
          const clave = `${u.desarrollo ?? ""}|${u.numero ?? ""}`;
          if (u.numero === undefined || unidadesVistas.has(clave)) continue;
          unidadesVistas.add(clave);
          unidades.push(u);
        }
      }

      // Los documentos se guardan tal como salieron, sin pasar por el modelo.
      for (const r of (resultado.resultados ?? []) as Array<Record<string, unknown>>) {
        // El folleto viaja en la fila del desarrollo y no como documento. Se recoge igual: si no
        // fuera boton, el recorte de URL del texto lo perderia sin dejar rastro.
        if (typeof r.url_folleto === "string" && r.url_folleto.length > 0
            && !vistos.has(r.url_folleto)) {
          vistos.add(r.url_folleto);
          documentos.push({
            desarrollo: r.nombre ?? null,
            categoria: "Folleto",
            nombre: "Folleto del desarrollo",
            idioma: null, variante: null,
            url: r.url_folleto,
            es_carpeta: false,
            visibilidad: "COMPARTIBLE",
            // De que herramienta vino. Ver el filtro de botones mas abajo.
            origen: c.function.name,
          });
        }
        // Los documentos vienen sueltos -de `buscar_documento`- o anidados dentro de cada
        // desarrollo -de `buscar_desarrollo`-. Se recogen de las dos formas.
        const anidados = Array.isArray(r.documentos)
          ? r.documentos as Array<Record<string, unknown>>
          : [];
        for (const dd of [r, ...anidados]) {
          const url = typeof dd.enlace === "string" ? dd.enlace : null;
          if (!url || vistos.has(url)) continue;
          vistos.add(url);
          documentos.push({
            desarrollo: dd.desarrollo ?? r.nombre ?? null,
            categoria: dd.categoria ?? null,
            nombre: dd.nombre ?? dd.categoria ?? "Documento",
            idioma: dd.idioma ?? null,
            variante: dd.variante ?? null,
            url,
            es_carpeta: dd.es_carpeta === true,
            visibilidad: dd.visibilidad ?? null,
            origen: c.function.name,
          });
        }
      }
      console.log(`SOL: ${c.function.name} -> ${crudo.slice(0, 160)}`);
      conversacion.push({ role: "tool", content: JSON.stringify(resultado) });
    }
  }

  // Se registra igual, y es lo que importa: son las conversaciones MAS caras -cuatro llamadas al
  // modelo- y eran justo las que no se contaban. Un fallo invisible en la bitacora es un fallo que
  // no se arregla.
  const sinSalida = "Me quede dando vueltas sin llegar a una respuesta. Preguntame algo mas "
    + "concreto: el nombre del desarrollo, o «que promociones hay».";
  await bitacora(svc, user.id, modeloEnUso, usoTotal,
    mensajes.at(-1)?.content ?? "", `[SIN SALIDA tras ${MAX_VUELTAS} vueltas] ${sinSalida}`);
  console.error(`SOL: ${modeloEnUso} agoto las ${MAX_VUELTAS} vueltas sin contestar`);
  return responde({ text: sinSalida, sin_salida: true });
});

/// Deja constancia de cada consulta, con el modelo y los tokens.
///
/// ─── Por que existe ─────────────────────────────────────────────────────────
///
/// SOL y Soli comparten la cuenta de Ollama, asi que la FACTURA es una sola y no se puede separar
/// por facturacion. Contando aqui las llamadas y los tokens de SOL, el gasto se puede atribuir de
/// todos modos: es la unica forma de saber cuanto cuesta cada asistente sin abrir dos cuentas.
///
/// Nunca lanza: un fallo al registrar no debe tumbar la respuesta a la persona.
async function bitacora(
  svc: ReturnType<typeof createClient>,
  usuario: string,
  modelo: string,
  uso: { prompt: number; respuesta: number },
  pregunta: string,
  respuesta: string,
): Promise<void> {
  try {
    await svc.from("sol_bitacora").insert({
      profile_id: usuario,
      modelo,
      tokens_prompt: uso.prompt,
      tokens_respuesta: uso.respuesta,
      pregunta: pregunta.slice(0, 500),
      respuesta: respuesta.slice(0, 2000),
    });
  } catch (e) {
    console.error("SOL: no se pudo registrar en la bitacora:", e);
  }
}

/// Quita las direcciones web del texto, dejando la frase legible.
///
/// Los enlaces se entregan como BOTONES, asi que en la prosa son ruido: una direccion de Drive mide
/// setenta caracteres y aparecia dos veces, en el texto y en el boton.
///
/// No basta con borrar la URL: hay que dejar el renglon presentable.
///
///   «- Version Espanol: https://...»  ->  «- Version Espanol»   (el nombre SI sirve: dice que es
///                                                                 cada boton)
///   «https://...»                     ->  se borra el renglon entero
///
/// Y si al quitar los enlaces no queda nada, se devuelve cadena vacia para que quien llama ponga su
/// propio texto en lugar de mandar un mensaje en blanco.
function sinEnlaces(texto: string): string {
  const renglones = texto.split("\n").map((linea) => {
    const sin = linea.replace(/https?:\/\/[^\s"'<>)\]]+/g, "").trim();
    // Lo que queda puede ser solo adornos: un guion, un asterisco, dos puntos, un parentesis.
    if (/^[-*•\d.)\]\s:—–]*$/.test(sin)) return "";
    // Los dos puntos o el guion que quedaron colgando al final ya no anuncian nada.
    return sin.replace(/[\s:—–-]+$/, "").replace(/\(\s*\)/g, "").trim();
  });

  // Los renglones vacios seguidos se colapsan en uno: al borrar una lista de enlaces quedan huecos.
  const salida: string[] = [];
  for (const r of renglones) {
    if (r === "" && (salida.length === 0 || salida[salida.length - 1] === "")) continue;
    salida.push(r);
  }
  return salida.join("\n").trim();
}
