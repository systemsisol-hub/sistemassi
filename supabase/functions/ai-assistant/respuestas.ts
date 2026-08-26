// Las preguntas que se contestan SIN pasar por el modelo, y el guardia de lo que si pasa.
//
// Las dos cosas juntas a proposito: son las dos caras de la misma decision. Una via directa es un
// dato que se entrega sin preguntarle al modelo; el guardia es lo que impide que el modelo entregue
// un dato que nadie consulto. Cada vez que una via directa cubre una pregunta, el guardia tiene una
// cosa menos que atrapar.

import { sinAcentos } from "./nombres.ts";

/** Si la persona pregunta por SUS PROPIAS vacaciones.
 *
 * ─── Por que esto no pasa por el modelo ──────────────────────────────────────
 *
 * Es la pregunta mas frecuente y la que mas importa, y depender del modelo para ella no funciono:
 *
 *   - unas veces no llamaba a la herramienta y se inventaba el saldo;
 *   - otras el guardia lo bloqueaba con razon, y la persona se quedaba sin respuesta;
 *   - y al bloquearlo, mi propio texto de rechazo quedaba en la memoria del hilo y el modelo lo
 *     repetia palabra por palabra en la pregunta siguiente, sin consultar nada. Dos respuestas
 *     identicas seguidas, las dos negandose, con los datos ahi al alcance.
 *
 * Aqui no hay nada que el modelo tenga que decidir: quien pregunta ya esta identificado, el permiso
 * ya esta comprobado y el calculo es determinista. Se consulta y se contesta. Sale mas rapido, no
 * cuesta una llamada al modelo, y no puede inventar porque el modelo no participa.
 *
 * Se exige que hable de SI MISMA. Si menciona a alguien —«las de Hector»— se deja pasar al modelo,
 * que es quien sabe resolver un nombre y pedir aclaraciones.
 */
export function preguntaSusVacaciones(texto: string): boolean {
  const t = sinAcentos(texto).toLowerCase();
  if (!/vacacion|dias disponibles|dias que me quedan|saldo de dias/.test(t)) return false;

  // «de <alguien>» quiere decir que pregunta por otra persona. `de` sola no basta: «cuantos dias de
  // vacaciones tengo» lleva un `de` que no introduce a nadie, y hay que dejarlo pasar.
  //
  // `mi` y `mis` NO se excluyen, a proposito: «las vacaciones de mi jefe» habla de otra persona, y
  // colarlo por esta via devolveria el saldo de quien pregunta como si fuera el de su jefe. A cambio,
  // «cuantos dias de mis vacaciones quedan» se va al modelo, que es un coste mucho menor que contestar
  // con los datos de alguien equivocado.
  if (/\bde\s+(?!vacacion|dias|antiguedad|la\s|los\s|las\s|el\s)[a-z]{2,}/.test(t)) {
    return false;
  }
  return /\bmis\b|\bmi\b|\btengo\b|me\s+quedan|me\s+toca|me\s+corresponden/.test(t);
}

/** Si la persona pide LAS FALTAS o la ASISTENCIA de alguien, y de quien.
 *
 * Misma forma que `preguntaIncidenciasDe`, y por el mismo motivo: las cifras de asistencia se
 * comparan con la pantalla, y una cifra que el modelo transcriba mal se convierte en una discusion
 * sobre el descuento de la nomina de alguien.
 */
export function preguntaFaltasDe(
  texto: string,
): { propio: true } | { quien: string } | null {
  const t = sinAcentos(texto).toLowerCase().trim();

  // «llego tarde» va aqui aunque no diga «retardo».
  //
  // Reportado: «que dias llego tarde brenda mondragon» se fue al modelo, que ademas pidio un rango de
  // fechas que no necesitaba. Es la forma NORMAL de preguntarlo; nadie dice «dame los retardos».
  if (!/\bfaltas?\b|asistencia|retardos?\b|tardanz|puntualidad|checad|checo\b/.test(t)
      && !/lleg(o|ue|aba|o\s+tarde)?\s*(tarde|a\s+destiempo)|a\s+que\s+hora\s+lleg/.test(t)) {
    return null;
  }

  // «falta» tambien es un verbo: «me falta un dia de vacaciones» no es una pregunta de asistencia.
  if (/falta\s+(un|una|el|la|mi|por)\b|hace\s+falta|me\s+falta/.test(t)) return null;

  // Del conjunto: eso lo contesta el modelo con la herramienta, o la pagina.
  if (/cuantas\s+faltas\s+hay|quien\s+(falto|tiene\s+mas)|toda\s+la\s+empresa|por\s+zona|el\s+equipo\b/
      .test(t)) {
    return null;
  }

  // `llegue` es primera persona y no necesita un «mi» al lado: «que dias llegue tarde» es suya.
  if (/\bmis\b|\bmi\b|\btengo\b|\btuve\b|me\s+pusieron|\bllegue\b/.test(t)) return { propio: true };

  // Dos formas de nombrar a la persona, y la segunda NO lleva preposicion.
  //
  // «retardos DE brenda» la trae el primer patron. «que dias llego tarde brenda mondragon» no: el
  // nombre va pegado al verbo. Es la forma en que se pregunto de verdad, asi que se atiende igual.
  const m = /\b(?:de|del|tiene|tuvo|lleva)\s+(.+)$/.exec(t)
    ?? /\b(?:llego|entro|checo|falto)\s+(?:tarde\s+|a\s+destiempo\s+)?(.+)$/.exec(t);
  if (!m) return null;

  let quien = m[1].trim().replace(/[?!.,;:]+$/, "");
  let antes;
  do {
    antes = quien;
    quien = quien.replace(/^(el|la|los|las|sr|sra|srta|senor|senora|don|dona|ing|lic|c)\s+/, "").trim();
  } while (quien !== antes);

  if (quien.length < 3) return null;
  if (/^(19|20)\d{2}$/.test(quien)) return null;
  if (/^(este|esta|ese|esa|hoy|ayer|manana|mes|ano|semana|quincena|periodo|enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)/
      .test(quien)) {
    return null;
  }
  // Sin preposicion, detras del verbo puede no venir una persona sino el resto de la pregunta:
  // «a que hora llego tarde», «llego tarde el lunes». Nada de esto es un nombre.
  if (/^(tarde|temprano|destiempo|a\s+tiempo|hora|dia|dias|veces|algo|alguien|nada|lunes|martes|miercoles|jueves|viernes|sabado|domingo)\b/
      .test(quien)) {
    return null;
  }
  return { quien };
}

/** La asistencia de alguien, escrita desde las cifras de la herramienta.
 *
 * Las cifras son las MISMAS que la pagina de Asistencia porque salen de la misma consulta; ver
 * `buscar_asistencia` en ejecutar.ts.
 */
export function textoAsistencia(
  datos: Record<string, unknown>,
  deQuien: string,
): string {
  const dia = (v: unknown) => {
    const p = String(v ?? "").slice(0, 10).split("-");
    return p.length === 3 ? `${p[2]}/${p[1]}` : String(v ?? "—");
  };

  // «No hay datos» y «no tiene faltas» son cosas distintas, y confundirlas es lo peor que puede
  // hacer esto: una persona sin checador saldria con asistencia perfecta.
  if (datos.sin_datos === true) {
    return `No hay dias de checador cargados para ${deQuien} en ese rango, asi que no puedo decir `
      + `cuantas faltas tiene: no es lo mismo que no tenerlas. Puede que no use checador, que su `
      + `horario no este capturado, o que ese reporte no se haya importado.`;
  }

  const faltas = Number(datos.faltas_sin_justificar ?? 0);
  const just = Number(datos.justificados ?? 0);
  const ret = Number(datos.retardos ?? 0);
  const pct = datos.puntualidad_pct;

  const lineas = [
    `${deQuien}, del ${dia(datos.desde)} al ${dia(datos.hasta)} `
      + `(${datos.dias_esperados} dias de horario):`,
    `• Faltas sin justificar: ${faltas}`,
    `• Justificados: ${just}`,
    `• Retardos: ${ret}`
      + (ret > 0 ? `, ${datos.minutos_de_retardo} minutos en total` : ""),
  ];
  if (pct !== null && pct !== undefined) lineas.push(`• Puntualidad: ${pct}%`);
  // El dato que de verdad se busca cuando se pregunta por faltas.
  lineas.push(`• Dias a descontar: ${datos.dias_de_descuento}`
    + ` (${ret} retardos entre ${datos.retardos_por_descuento}, mas las faltas)`);

  // QUE DIA llego tarde y A QUE HORA.
  //
  // Reportado: pedido «el horario de los 7 retardos», la respuesta fue el total de minutos. Es lo
  // unico que se puede hacer con un total, y lo que se queria era la hora de cada dia.
  //
  // `hh:mm` y no `hh:mm:ss`: los segundos del checador no dicen nada y ocupan la mitad del renglon.
  const hora = (v: unknown) => String(v ?? "").slice(0, 5) || "—";
  const tarde = (datos.dias_de_retardo ?? []) as Array<Record<string, unknown>>;
  if (tarde.length > 0) {
    lineas.push("", "Los dias que llego tarde:");
    for (const d of tarde.slice(0, 15)) {
      lineas.push(`• ${dia(d.fecha)}: llego ${hora(d.llego)}`
        + `, entraba ${hora(d.entrada_de_su_horario)}`
        + ` (limite ${hora(d.limite_con_tolerancia)})`
        + ` — ${d.minutos_tarde} min tarde`);
    }
    if (tarde.length > 15) lineas.push(`(y ${tarde.length - 15} mas)`);
  }

  const conIncidencia = (datos.dias_con_incidencia ?? []) as Array<Record<string, unknown>>;
  if (conIncidencia.length > 0) {
    lineas.push("", "Faltas y justificados:");
    for (const d of conIncidencia.slice(0, 15)) {
      lineas.push(`• ${dia(d.fecha)} — ${d.estado}`
        + (d.motivo ? `: ${d.motivo}` : ""));
    }
    if (conIncidencia.length > 15) {
      lineas.push(`(y ${conIncidencia.length - 15} mas)`);
    }
  }
  return lineas.join("\n");
}

/** Si la persona pide UN CONTACTO DE EMERGENCIA, y de quien.
 *
 * Se pidio que Soli lo diera por la aplicacion y por WhatsApp: nombre, telefono y relacion de la
 * referencia, mas el tipo de sangre.
 *
 * El propio no exige permiso de pagina -es su contacto-; el de otra persona si, y eso lo comprueba
 * `buscar_contacto_emergencia`. Aqui solo se decide DE QUIEN se esta hablando.
 */
export function preguntaContactoEmergencia(
  texto: string,
): { propio: true } | { quien: string } | null {
  const t0 = sinAcentos(texto).toLowerCase().trim();

  // «tipo de sangre» entra sola: es la otra mitad de lo mismo y se pregunta suelta. Y con ella
  // entran los otros datos del mismo bloque del expediente -alergias, padecimientos y el NSS-,
  // porque se preguntan igual de sueltos: «soy alergico a algo?», «cual es mi NSS».
  if (!/emergencia|referencia|tipo de sangre|grupo sanguineo|a quien avisar|a quien le aviso/
      .test(t0)
      && !/alergi|enfermedad(es)? cronica|padecimiento|\bnss\b|seguro social/.test(t0)) {
    return null;
  }
  // «contactos externos» es otra pagina y otra herramienta.
  if (/contactos? externos?|proveedor|cliente/.test(t0)) return null;

  // «a quien le aviso si me pasa algo» no lleva «mi» en ningun lado y es la propia, claramente.
  if (/\bmi\b|\bmis\b|\btengo\b|\bmio\b|me\s+registraron|soy\s+alergic|me\s+pas(a|ara)\b|me\s+ocurre/
      .test(t0)) {
    return { propio: true };
  }

  // Se BORRAN las frases fijas antes de buscar a la persona.
  //
  // Reportado el 19/08/2026: «cual es el contacto de emergencia de 0163» no se atendia. La causa es
  // que «contacto DE emergencia» ya lleva un «de», y la expresion agarraba el PRIMERO: se quedaba con
  // «emergencia de 0163», que luego caia en el descarte de palabras que no son personas. El «de 0163»
  // nunca se miraba.
  //
  // Quitando primero la frase fija, lo que sobra es la persona -o nada-.
  const t = t0
    .replace(/contactos? de emergencia|datos de emergencia|contacto de urgencia/g, " ")
    .replace(/tipo de sangre|grupo sanguineo/g, " ")
    .replace(/datos de referencia|la referencia/g, " ")
    // «numero de seguro social» lleva su propio «de», el mismo tropiezo que «contacto DE
    // emergencia»: sin borrarlo, la persona que se buscaba era «seguro social de 0163».
    .replace(/numero de seguro social|num(?:ero)? de seguridad social|seguro social/g, " ")
    .replace(/enfermedad(?:es)? cronica(?:s)?|padecimientos?|alergias?|\bnss\b/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  const m = /\b(?:de|del|tiene|registro)\s+(.+)$/.exec(t);
  if (!m) return null;

  let quien = m[1].trim().replace(/[?!.,;:]+$/, "");
  let antes;
  do {
    antes = quien;
    quien = quien.replace(/^(el|la|los|las|sr|sra|srta|senor|senora|don|dona|ing|lic|c|colaborador|empleado)\s+/, "").trim();
  } while (quien !== antes);

  // Lo que queda detras de «de» todavia puede no ser una persona.
  if (quien.length < 3) return null;
  if (/^(emergencia|sangre|referencia|urgencia|contacto|quien|social|alergi|padecimiento)/.test(quien)) return null;
  if (/^(19|20)\d{2}$/.test(quien)) return null;
  return { quien };
}

/** El contacto de emergencia, escrito desde el expediente. */
export function textoContactoEmergencia(
  datos: Record<string, unknown>,
  esPropio: boolean,
): string {
  const quien = esPropio
    ? "Tus datos de emergencia"
    : `Datos de emergencia de ${datos.colaborador}`
      + (datos.numero_empleado ? ` (empleado ${datos.numero_empleado})` : "");

  const nombre = datos.referencia_nombre as string | null;
  const tel = datos.referencia_telefono as string | null;
  const rel = datos.referencia_relacion as string | null;
  const sangre = datos.tipo_sangre as string | null;
  const alergias = datos.alergias as string | null;
  const padecimientos = datos.padecimientos as string | null;
  const nss = datos.nss as string | null;

  // Un hueco NO es un hecho sobre la persona: es un hecho sobre el expediente.
  //
  // Medido: de 244 vigentes solo 23 tienen la referencia capturada. Decir «no tiene contacto de
  // emergencia» seria afirmar algo que nadie sabe, y en una urgencia mandaria a dejar de buscar. Se
  // dice que no esta REGISTRADO, que es lo unico comprobable.
  if (!nombre && !tel && !rel && !sangre && !alergias && !padecimientos && !nss) {
    return `${quien}: no hay ninguno REGISTRADO en el expediente. `
      + `Eso no significa que no exista, solo que no esta capturado. `
      + `Se captura en la pagina de Colaborador; si es una urgencia, pregunta a Desarrollo Humano.`;
  }

  const lineas = [`${quien}:`];
  lineas.push(`• Contacto: ${nombre ?? "sin registrar"}` + (rel ? ` (${rel})` : ""));
  lineas.push(`• Telefono: ${tel ?? "sin registrar"}`);
  lineas.push(`• Tipo de sangre: ${sangre ?? "sin registrar"}`);

  // Las alergias van ANTES de los padecimientos y del NSS, a proposito: en una urgencia es el dato que
  // cambia lo que se le puede administrar a alguien, asi que va lo mas arriba posible de los tres.
  //
  // Y «sin registrar» NO es «ninguna». El campo del formulario lo dice tambien: si no se sabe, se deja
  // vacio. Un «ninguna» capturado por costumbre afirma algo que nadie comprobo.
  lineas.push(`• Alergias: ${alergias ?? "sin registrar (NO quiere decir que no tenga)"}`);
  lineas.push(`• Enfermedades cronicas: ${padecimientos ?? "sin registrar"}`);
  // El NSS es lo que piden en la clinica. Son 11 digitos; `imss` es la columna donde vive.
  lineas.push(`• NSS: ${nss ?? "sin registrar"}`);

  return lineas.join("\n");
}

/** Si la persona pregunta por SU HORARIO.
 *
 * Reportado: «quiero mi horario» contestaba con «3ac244d0-bf7f-4cfa-99ce-b9f3bffd749d», porque
 * `profiles.horario` guarda el uuid de un renglon de `schedules` y se devolvia crudo.
 *
 * Hace falta como via directa y no solo arreglando la herramienta: `USER_COLABORADOR_FIELDS` no
 * incluye `horario`, asi que a un usuario normal `buscar_colaborador` no le devuelve el suyo. Y
 * anadirlo a esa lista expondria el horario de CUALQUIERA en una busqueda de directorio. Por aqui cada
 * quien ve el suyo, sin ampliar nada.
 */
export function preguntaSuHorario(texto: string): boolean {
  const t = sinAcentos(texto).toLowerCase();
  if (!/horario|jornada|a que hora (entro|salgo)|mi turno/.test(t)) return false;
  // De otra persona lo resuelve el modelo, que sabe buscar el nombre.
  if (/\bde\s+(?!trabajo|oficina|la\s|los\s|las\s|el\s|mi\s|mis\s)[a-z]{2,}/.test(t)) return false;
  // Y del checador o de una zona no es «mi horario».
  if (/todos|zona|sucursal|cuantos horarios|lista de horarios/.test(t)) return false;
  return /\bmi\b|\bmis\b|\btengo\b|\bentro\b|\bsalgo\b|me toca/.test(t);
}

/** El horario propio, escrito desde las reglas de `schedules`. */
export function textoHorario(datos: Record<string, unknown>): string {
  const nombre = datos.nombre ? String(datos.nombre) : null;
  const zona = datos.zona ? String(datos.zona) : null;
  const dias = (datos.dias ?? []) as Array<Record<string, unknown>>;

  if (dias.length === 0) {
    return nombre
      ? `Tu horario es «${nombre}»${zona ? ` (${zona})` : ""}, pero no tiene dias capturados. `
        + `Avisa a Sistemas para que lo revisen.`
      : "No tienes horario asignado en el sistema. Sin el, tus faltas y retardos no se pueden calcular; "
        + "avisa a Sistemas o a Desarrollo Humano.";
  }

  const lineas = dias.map((d) => {
    const tol = Number(d.tolerancia_min) || 0;
    return `• ${d.dia}: ${d.entrada ?? "—"} a ${d.salida ?? "—"}`
      + (tol > 0 ? ` (tolerancia ${tol} min)` : "");
  });
  return `Tu horario${nombre ? ` es «${nombre}»` : ""}${zona ? `, zona ${zona}` : ""}:\n`
    + lineas.join("\n");
}

/** Si el mensaje es SOLO un identificador: un uuid, o un numero de empleado.
 *
 * ─── El fallo que la hizo necesaria ──────────────────────────────────────────
 *
 * Del historial real de WhatsApp del 12/08/2026, tres mensajes seguidos:
 *
 *   - «0170» -> «Incidencias — MARCO ANTONIO MONTOYA LOPEZ (0170)». El 0170 es ENRIQUE ORTEGA GOMEZ;
 *     Marco es el 0186. Junto el numero que le dieron con el nombre de otro.
 *   - «a1d4a9fb-...» -> «No tengo acceso a incidencias por UUID».
 *   - «9cf3eb50-...» -> «No me deja entrar por UUID».
 *
 * Las dos negativas son falsas: `calcular_vacaciones` acepta `usuario_id` y `numero_empleado` para
 * administradores. Se nego pudiendo hacerlo, y en el otro caso acerto la consulta y erro el nombre.
 *
 * Un mensaje que es SOLO un identificador no tiene ninguna ambiguedad que el modelo tenga que
 * resolver, asi que no pasa por el. Se contesta con la ficha de esa persona, con su nombre y su
 * numero tomados del mismo renglon de la base, que es lo que impide volver a cruzarlos mal.
 *
 * Se exige que el mensaje sea SOLO eso. «vacaciones de 0170» lleva una intencion que puede no ser
 * esta, y se deja al modelo.
 */
export function soloUnIdentificador(
  texto: string,
): { usuario_id: string } | { numero_empleado: string } | null {
  // Se quitan signos de puntuacion y adornos de los extremos, no de dentro: un uuid lleva guiones.
  const t = texto.trim().replace(/^[¿¡"'*(.\s]+|[?!"'*).,\s]+$/g, "");
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(t)) {
    return { usuario_id: t };
  }
  // Los numeros de empleado de la base van de 1 a 4 cifras, con ceros por delante -«0170»-. Se pide
  // un minimo de tres para no quedarse con un «5» que puede ser la respuesta a otra pregunta.
  if (/^\d{3,4}$/.test(t)) return { numero_empleado: t };
  return null;
}

/** Si la persona pregunta por EL EQUIPO QUE TIENE ASIGNADO.
 *
 * ─── El fallo que la hizo necesaria ──────────────────────────────────────────
 *
 * Reportado el 12/08/2026. Un administrador pregunto «¿que equipo de computo tengo asignado?» y Soli
 * le contesto con un LAP-TOP LENOVO IdeaPad 3, serie PF4ZDWD0. Ese equipo es de otra persona
 * -ABRAHAM GUADALUPE ACUÑA AGUILAR, en MISIONES STA ESPERANZA- y encima la respuesta traia la
 * ubicacion cambiada a la de quien preguntaba.
 *
 * No fue una invencion: `buscar_inventario` filtra por `usuario_id` SOLO a los usuarios normales. A un
 * administrador que no pase `usuario_id` le devuelve el inventario de TODA la empresa, y el modelo
 * cogio un renglon de los veinte. El guardia no podia atraparlo, porque una herramienta si habia
 * traido datos: el problema no era que faltara el dato, era que sobraban 19 que no le tocaban.
 *
 * Esta via lo resuelve donde no hay nada que decidir: quien pregunta ya esta identificado, asi que se
 * consulta por su `usuario_id` y se contesta. El modelo no participa, asi que no puede equivocarse
 * de renglon.
 *
 * Se exige que hable de SI MISMA, igual que en las vacaciones: «el equipo de Hector» se deja pasar al
 * modelo, que sabe resolver un nombre.
 */
export function preguntaSuEquipo(texto: string): boolean {
  const t = sinAcentos(texto).toLowerCase();

  // Que hable de un equipo. «asignado» a secas no basta: tambien se asignan incidencias y permisos.
  if (!/equipo|laptop|lap-top|computadora|compu\b|celular|telefono|monitor|impresora|inventario/
      .test(t)) {
    return false;
  }

  // Una pregunta por el inventario de la empresa NO es una pregunta por lo propio, aunque lleve un
  // «tengo» dentro: «cuantas laptops tengo en Vidamar» habla de una ubicacion.
  if (/sin asignar|sin usuario|cuantos hay|cuantas hay|todo el inventario|inventario completo|en total/
      .test(t)) {
    return false;
  }
  if (/\ben\s+(vidamar|constituyentes|tulum|guerrero|selva|bonanza|zenesis|ensenada|misiones)/
      .test(t)) {
    return false;
  }

  // «de <alguien>» es otra persona. Mismo criterio y misma lista de excepciones que en vacaciones:
  // «que equipo de computo tengo» lleva un `de` que no introduce a nadie.
  if (/\bde\s+(?!computo|computadora|trabajo|oficina|la\s|los\s|las\s|el\s|mi\s|mis\s)[a-z]{2,}/
      .test(t)) {
    return false;
  }

  return /\bmis\b|\bmi\b|\btengo\b|me\s+asignaron|tengo\s+asignad|me\s+toca/.test(t);
}

/** Si la persona pide LAS INCIDENCIAS de alguien, y de quien.
 *
 * ─── El fallo que la hizo necesaria ──────────────────────────────────────────
 *
 * Es la pregunta donde Soli se invento mas: el 12/08/2026 a las 13:00, pedido el historial de Marco,
 * devolvio una incidencia entera que no existe -«#200, periodo 2026, 1 dia, del 31/08/2026 al
 * 31/08/2026, regreso 01/09/2026, PENDIENTE»- y al reclamarselo contesto «No invento». De las 1167
 * incidencias de la base, cero coinciden con eso en NINGUN campo.
 *
 * Los guardias no pueden cubrirlo: una herramienta si trajo datos, y una tabla de un solo renglon
 * queda por debajo del umbral estructural. La unica forma de que no se invente una fecha es que no la
 * escriba el modelo.
 *
 * Devuelve `{propio}` cuando habla de si misma, o `{quien}` con el nombre o el numero que dijo, para
 * que quien llame lo resuelva. Si no se resuelve a UNA persona, se deja al modelo, que sabe mostrar
 * los candidatos y preguntar.
 */
export function preguntaIncidenciasDe(
  texto: string,
): { propio: true } | { quien: string } | null {
  const t = sinAcentos(texto).toLowerCase().trim();

  // Solo «incidencia». «Vacaciones» a secas ya la atiende `calcular_vacaciones`, que devuelve la
  // tabla de periodos Y la ultima salida; colarla aqui daria una respuesta peor.
  if (!/incidencia/.test(t)) return null;

  // Lo propio se mira ANTES que nada.
  //
  // Iba despues del descarte de «pendientes» y por eso «mis incidencias pendientes?» se escapaba al
  // modelo: la palabra que indica un conjunto tapaba al posesivo que indica de quien.
  if (/\bmis\b|\bmias\b|\bmi\b|\btengo\b|me\s+quedan/.test(t)) return { propio: true };

  // Del conjunto, no de una persona: eso lo contesta el modelo con la herramienta.
  if (/cuantas|todas las|en total|de la empresa|pendientes\b|aprobadas\b|por autorizar/.test(t)) {
    return null;
  }

  // «de X» o «tiene X». Se toma hasta el final: los nombres traen espacios y a veces cuatro palabras.
  const m = /\b(?:de|del|tiene|tuvo|lleva)\s+(.+)$/.exec(t);
  if (!m) return null;

  let quien = m[1].trim().replace(/[?!.,;:]+$/, "");
  // Los articulos y tratamientos del principio no son parte del nombre, y pueden venir VARIOS: «de la
  // sra lopez vigil» dejaba «sra lopez vigil» cuando solo se quitaba uno.
  let antes;
  do {
    antes = quien;
    quien = quien.replace(/^(el|la|los|las|sr|sra|srta|senor|senora|don|dona|ing|lic|c)\s+/, "").trim();
  } while (quien !== antes);

  // Lo que va detras de «de» no siempre es una persona.
  if (quien.length < 3) return null;
  // Un año se descarta; un numero de empleado NO.
  //
  // Escribi `\d{4}$` y con eso «las incidencias del 0186» se iba al modelo, que es justo el caso que
  // esto viene a cubrir. Solo parece un año lo que empieza por 19 o 20. Queda una ambiguedad real —el
  // empleado 2026 existiria y se leeria como año— y se acepta: es un caso contra el resto.
  if (/^(19|20)\d{2}$/.test(quien)) return null;
  if (/^(vacacion|este|esta|ese|esa|hoy|ayer|manana|mes|ano|semana|periodo|enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)/
      .test(quien)) {
    return null;
  }
  return { quien };
}

/** Las incidencias de alguien, escritas desde los renglones de la base.
 *
 * Las fechas van en dia/mes/año porque es como se leen aqui, y el REGRESO aparte porque es el dato
 * que de verdad usa un jefe para saber cuando vuelve la persona.
 */
export function textoIncidencias(
  datos: Record<string, unknown>,
  deQuien: string,
): string {
  const filas = ((datos.results ?? []) as Array<Record<string, unknown>>)
    .slice()
    // Por fecha de salida, la mas reciente primero. La herramienta las ordena por fecha de captura,
    // que no es lo mismo: un registro capturado ayer puede ser de una salida de 2019.
    .sort((a, b) => String(b.fecha_inicio ?? "").localeCompare(String(a.fecha_inicio ?? "")));

  if (filas.length === 0) return `${deQuien} no tiene incidencias registradas.`;

  const dia = (v: unknown) => {
    const p = String(v ?? "").slice(0, 10).split("-");
    return p.length === 3 ? `${p[2]}/${p[1]}/${p[0]}` : String(v ?? "—");
  };
  const TOPE = 12;
  const lineas = filas.slice(0, TOPE).map((f) => {
    const d = typeof f.dias === "number" ? f.dias : null;
    return `• ${dia(f.fecha_inicio)} al ${dia(f.fecha_fin)}`
      + (d !== null ? ` — ${d} ${d === 1 ? "dia" : "dias"}` : "")
      + `, ${f.status}, periodo ${f.periodo}`
      + (f.fecha_regreso ? ` (regreso ${dia(f.fecha_regreso)})` : "");
  });
  const cola = filas.length > TOPE
    ? `\n(y ${filas.length - TOPE} mas, de las mas antiguas)`
    : "";
  return `${deQuien} ${filas.length === 1 ? "tiene 1 incidencia" : `tiene ${filas.length} incidencias`} `
    + `registradas:\n${lineas.join("\n")}${cola}`;
}

/** El texto del equipo propio, armado con los renglones de la herramienta.
 *
 * Lleva la serie porque es lo que se necesita para levantar un ticket o comprobar una etiqueta, y el
 * nombre de quien lo tiene NO, porque por definicion es quien pregunta.
 */
export function textoEquipoPropio(datos: Record<string, unknown>): string {
  const filas = (datos.results ?? []) as Array<Record<string, unknown>>;
  if (filas.length === 0) {
    return "No tienes ningun equipo asignado en el inventario. Si deberias tenerlo, avisa a Sistemas "
      + "para que lo registren a tu nombre.";
  }
  const lineas = filas.map((f) => {
    const partes = [f.tipo, f.marca, f.modelo].filter(Boolean).join(" ");
    const serie = f.n_s ? ` — serie ${f.n_s}` : "";
    const cond = f.condicion ? `, ${f.condicion}` : "";
    const donde = f.ubicacion ? `, en ${f.ubicacion}` : "";
    return `• ${partes}${serie}${cond}${donde}`;
  });
  const cabeza = filas.length === 1
    ? "Tienes 1 equipo asignado:"
    : `Tienes ${filas.length} equipos asignados:`;
  return `${cabeza}\n${lineas.join("\n")}`;
}

/** El texto de una respuesta de vacaciones, armado con los datos de la herramienta.
 *
 * Corto a proposito: la aplicacion pinta la tarjeta con el detalle y el puente de WhatsApp arma su
 * propia ficha a partir de `structured`. Esto es lo que se lee en la burbuja.
 */
export function textoVacacionesPropias(datos: Record<string, unknown>): string {
  const total = datos.total_disponible as number;
  const periodos = (datos.periodos ?? []) as Array<Record<string, unknown>>;
  const actual = periodos.find((pe) => pe.es_periodo_actual === true);
  const cola = actual
    ? ` En el periodo actual (${actual.periodo}) te quedan ${actual.dias_disponibles}.`
    : "";
  return `Tienes ${total} ${total === 1 ? "dia" : "dias"} de vacaciones disponibles en total.${cola}`
    + textoUltimaSolicitud(datos, "Tu");
}

/** La ultima solicitud, en una linea. Vacio si no hay ninguna.
 *
 * Pedido tal cual: al preguntar por las vacaciones de alguien se quiere la tabla Y el ultimo registro.
 * Se distingue si esta POR VENIR porque es lo que de verdad se quiere saber: la ultima de Marco empieza
 * el 21/08 y hoy es el 12.
 */
export function textoUltimaSolicitud(datos: Record<string, unknown>, posesivo: string): string {
  const lista = (datos.solicitudes ?? []) as Array<Record<string, unknown>>;
  if (lista.length === 0) return " No tiene solicitudes registradas.";

  const u = lista[0];
  const cuando = u.por_venir === true ? "próxima salida" : "última salida";
  const dias = u.dias;
  return ` ${posesivo} ${cuando}: ${u.fecha_inicio} al ${u.fecha_fin}`
    + ` (${dias} ${dias === 1 ? "día" : "días"}, ${u.status}, periodo ${u.periodo})`
    + `, con regreso el ${u.fecha_regreso}.`;
}

const MESES: Record<string, number> = {
  enero: 1, febrero: 2, marzo: 3, abril: 4, mayo: 5, junio: 6,
  julio: 7, agosto: 8, septiembre: 9, setiembre: 9, octubre: 10,
  noviembre: 11, diciembre: 12,
};

/** Si la persona pregunta por cumpleaños, y de que mes o rango.
 *
 * ─── Por que esto tampoco pasa por el modelo ─────────────────────────────────
 *
 * Con la herramienta ya puesta, «cumpleaños de este mes» y «quien cumple esta semana» salieron
 * perfectos, y «cumpleaños de septiembre» acabo en el guardia: el modelo no llamo a la herramienta y
 * el guardia bloqueo la respuesta para que no inventara los nueve nombres de ese mes.
 *
 * Callar es mejor que inventar, pero es la respuesta equivocada cuando el dato esta a mano. Es el
 * mismo caso que las vacaciones propias y las del jefe: no hay nada que el modelo tenga que decidir
 * —el mes se lee de la pregunta y la consulta es determinista— asi que se resuelve aqui.
 *
 * Se exige que hable de cumpleaños de verdad: «cumple 5 años en la empresa» habla de antiguedad y
 * tiene que seguir su camino.
 */
export function preguntaCumpleanos(
  texto: string,
  anterior: string,
): { mes: number | null; soloEstaSemana: boolean } | null {
  const t = sinAcentos(texto).toLowerCase();
  const esDeCumples = (x: string) => /cumplea|cumplen?\s+anos|quien(es)?\s+cumple/.test(x);

  // Una pregunta de seguimiento no repite el tema: «y de septiembre?» viene despues de «cumpleaños
  // de este mes» y no lleva la palabra. Reportado: por eso la via directa no se activo y el modelo
  // contesto de memoria, inventando cuatro personas.
  //
  // Se exige que sea CORTA y que solo aporte un mes o un rango: asi «y las vacaciones de septiembre?»
  // -que es otra cosa- no se cuela por aqui.
  const palabras = t.split(/\s+/).filter((w) => w.length > 0);
  const soloAportaFecha = palabras.length <= 5
    && !/vacacion|incidencia|inventario|empleado|telefono/.test(t);

  const seguimiento = !esDeCumples(t)
    && esDeCumples(sinAcentos(anterior).toLowerCase())
    && soloAportaFecha;

  if (!esDeCumples(t) && !seguimiento) return null;

  const soloEstaSemana = /esta semana|de la semana|semana actual/.test(t);
  for (const [nombre, num] of Object.entries(MESES)) {
    if (t.includes(nombre)) return { mes: num, soloEstaSemana };
  }
  // Un seguimiento que no nombra mes ni semana no aporta nada: mejor que lo lleve el modelo.
  if (seguimiento && !soloEstaSemana) return null;
  return { mes: null, soloEstaSemana };
}

/// Los meses para escribirlos. Aparte de `MESES`, que sirve para LEERLOS y por eso acepta dos formas
/// de septiembre; aquí hace falta una sola por mes.
const NOMBRE_MES = ["", "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];

/** El texto de una respuesta de cumpleaños, armado con los datos de la herramienta. */
export function textoCumpleanos(datos: Record<string, unknown>): string {
  const gente = (datos.results ?? []) as Array<Record<string, unknown>>;
  const mes = typeof datos.mes === "number" ? datos.mes : 0;
  const nombreMes = NOMBRE_MES[mes] ?? "";
  const donde = datos.rango
    ? `esta semana (${datos.rango} de ${nombreMes})`
    : `en ${nombreMes}`;

  if (gente.length === 0) return `No hay cumpleaños ${donde}.`;

  const lineas = gente.map((g) => `• ${g.dia} — ${g.nombre}`
    + (g.puesto ? `, ${g.puesto}` : ""));
  return `Cumpleaños ${donde} (${gente.length}):\n${lineas.join("\n")}`;
}

/** Si la respuesta afirma un dato de la base que ninguna herramienta respaldo en este turno.
 *
 * ─── El fallo ────────────────────────────────────────────────────────────────
 *
 * El modelo contesta sin llamar a la herramienta y se inventa los datos, con aplomo y con formato de
 * tabla. Casos reales, todos comprobados contra la base:
 *
 *   - «ENRIQUE ORTEGA GOMEZ: 0 dias disponibles» — tiene 102.
 *   - «Ana Maria Lopez Vigil, 1250» — es la 0162.
 *   - «CLAUDIA PATRICIA BRAVO LOMELI — empleado 2277» — no existe; el 2277 es otra persona.
 *   - «JESUS BRAVO LOMELI (empleado 4011)» — no existe, y el numero mas alto de la base es 2487.
 *
 * Los dos ultimos salieron en la APLICACION, no por WhatsApp. Al principio parecia cosa del puente
 * -la pagina acertaba porque pinta una tarjeta con los datos crudos y la vista va a la tarjeta- pero
 * la prosa de la pagina tiene el mismo problema, solo que tapado. Por eso esto vive aqui, en lo unico
 * que comparten los dos canales, y no en el puente.
 *
 * ─── Que se considera un dato que no se puede inventar ───────────────────────
 *
 * Lo dice la tabla de aqui abajo, y siempre mirando el TEXTO y no la pregunta.
 *
 * Mirar la pregunta fue mi primer intento y tenia un agujero por cada lado. Exigir que la pregunta
 * mencionara vacaciones dejaba pasar los seguimientos —«y las de bravo lomeli», que es justo el caso
 * real del 12/08— y a la vez bloqueaba el conocimiento general, porque «con 5 anos la ley da 20 dias»
 * viene de una pregunta sobre vacaciones y es correcto.
 */
const DATOS_QUE_NO_SE_INVENTAN: Array<{
  /// Como se llama, para poder decir en la bitacora QUE regla salto.
  que: string;
  /// Tienen que coincidir TODAS. Van separadas a proposito, no pegadas en una sola expresion:
  /// mi primera version pedia «dias disponibles» juntas y se le escapo «105 dias de vacaciones
  /// disponibles» —son 40—, porque dos palabras en medio bastaron para colar una cifra inventada.
  exige: RegExp[];
  /// Cualquiera de estas herramientas basta para que el dato tenga de donde venir.
  respaldan: string[];
  /// Y si esto coincide, la regla no aplica.
  salvo?: RegExp;
}> = [
  {
    // Un hecho de la base: sin herramienta no tiene de donde salir.
    que: "un numero de empleado",
    exige: [/empleado\s*#?\s*:?\s*\d{3,5}/],
    respaldan: ["buscar_colaborador", "calcular_vacaciones"],
  },
  {
    // Es la palabra «disponible» la que convierte una cifra en el saldo de alguien. Sin ella, hablar
    // de dias es hablar de la ley, y eso el modelo lo puede contestar solo. Y se exige que la cifra
    // sea de DIAS: «hay 3 laptops disponibles» habla de inventario y no debe bloquearse.
    que: "un saldo de dias, con la cifra delante",
    exige: [/\d+\s*dias?\b/, /disponibl/],
    respaldan: ["calcular_vacaciones"],
  },
  {
    // «Dias disponibles: 8» no lleva la cifra delante de «dias», asi que la regla anterior no lo ve.
    que: "un saldo de dias, con la cifra detras",
    exige: [/disponibles?\s*:?\s*\**\s*\d/],
    respaldan: ["calcular_vacaciones"],
  },
  {
    // Se pide que haya un digito: «no tengo acceso a los cumpleaños» es una respuesta legitima y no
    // afirma la fecha de nadie. Reportado: preguntado por los cumpleaños de la semana, invento a una
    // persona; la pantalla no muestra a NADIE entre el 10 y el 16 de agosto.
    que: "un cumpleanos con fecha",
    exige: [/cumplea|cumple\b/, /\d/],
    respaldan: ["buscar_cumpleanos"],
    // «cumple 5 años en la empresa» es antiguedad, no un cumpleaños, y el modelo la calcula con la
    // fecha de ingreso que ya trae la ficha. Sin esta salvedad quedaba bloqueada una respuesta buena.
    //
    // Va `a[nñ]os` y no `anos`: `sinAcentos` conserva la Ñ a proposito -«Peñafiel» tiene que quedar
    // igual para poder buscarlo en la base- asi que «años» llega aqui con su ñ puesta. Escribi
    // `anos?` y esta salvedad no coincidio con nada.
    salvo: /a[nñ]os? (cumplidos )?en (la |el )?(empresa|puesto|compa[nñ]ia)|antiguedad/,
  },
];

export function afirmaDatoSinRespaldo(
  texto: string,
  conDatos: Set<string>,
  huboLlamadas = conDatos.size > 0,
): boolean {
  const t = sinAcentos(texto).toLowerCase();

  for (const dato of DATOS_QUE_NO_SE_INVENTAN) {
    if (dato.salvo?.test(t)) continue;
    if (!dato.exige.every((r) => r.test(t))) continue;
    if (dato.respaldan.some((h) => conDatos.has(h))) continue;
    // Se registra CUAL salto. Las tres veces que este guardia bloqueo una respuesta correcta no
    // habia manera de saber que regla habia sido, y se fueron en adivinar.
    console.log(`ai-assistant: bloqueado, el texto afirma ${dato.que} sin herramienta detras`);
    return true;
  }

  // Y la regla que NO depende de ninguna palabra: sin haber consultado NADA, no se entrega una lista
  // de registros.
  //
  // Las reglas de arriba buscan palabras, y eso falla por los dos lados. El caso que lo demuestra:
  // preguntado «y de septiembre?» invento cuatro personas y empezo la respuesta con «umpleaños en
  // septiembre (4):» —sin la C inicial— asi que /cumplea/ no coincidio y paso. Una letra de menos
  // basto para colar cuatro nombres falsos.
  //
  // Dos renglones que empiezan por vinieta o barra Y llevan un numero son una tabla de datos, y el
  // modelo no tiene de donde sacarla si no llamo a ninguna herramienta. Se exige el numero para no
  // bloquear una lista de lo que SI puede hacer, que no lleva cifras.
  // Se mira si se LLAMO a alguna herramienta, no si alguna trajo datos. Una lista de candidatos es
  // legitima aunque la consulta no haya encontrado a la persona: preguntar «¿es alguno de estos?» es
  // justo lo que tiene que hacer.
  if (!huboLlamadas) {
    const renglonesDeDatos = (texto.match(/^\s*[•\-*|]\s*\**\s*\d/gm) || []).length;
    if (renglonesDeDatos >= 2) {
      console.log("ai-assistant: bloqueado, una tabla de datos sin haber consultado nada");
      return true;
    }
  }

  return false;
}


// ─── «Autorizo» ──────────────────────────────────────────────────────────────
//
// El caso que la hizo falta, el 26/08/2026. A HECTOR FIGUEROA se le crearon dos solicitudes de
// vacaciones a las 08:27 y 08:28. El aviso llego a RODRIGO CAMACHO, su jefe, con el texto «te toca
// autorizarla». Rodrigo contesto «Autorizo» a las 08:33 y Soli le pidio fechas para CREAR una
// solicitud nueva: en su hilo, el turno anterior era de trece dias antes -sobre las vacaciones de
// otra persona- y terminaba preguntando «¿deseas gestionar una solicitud de vacaciones?».
//
// Nada se aprobo. El aviso invitaba a contestar ahi mismo y el sistema no sabia recibir la respuesta.
//
// Esto lo resuelve SIN pasar por el modelo, y a proposito: es una escritura, y dejar que el modelo
// decida cuando algo cuenta como «autorizo» es exactamente como se aprueba lo que no era.

/// Qué se está decidiendo y sobre cuál solicitud.
///
/// `cual` es null cuando no se dijo: con una sola pendiente eso alcanza, con varias no.
export interface Decision {
  decision: "APROBADA" | "RECHAZADA";
  todas: boolean;
  numero: number | null;
  quien: string | null;
}

export function preguntaAutorizacion(texto: string): Decision | null {
  const t = sinAcentos(texto).toLowerCase().trim().replace(/[.!]+$/, "");

  // Se exige un mensaje CORTO. «Autorizo» dentro de un párrafo largo casi nunca es una decisión:
  // es alguien contando algo. Aprobar por una palabra suelta en medio de un relato sería peor que
  // no hacer nada.
  if (t.length > 90) return null;

  // El rechazo se prueba PRIMERO, porque «no autorizo» contiene «autorizo». Al revés, un «no» se
  // convertiría en un sí, que es el único error inaceptable de los dos.
  const rechaza = /\bno\s+(?:lo\s+|la\s+|las\s+|los\s+)?(?:autoriz|aprueb|apruebo)|rechaz|denieg|no\s+aprobad/
    .test(t);
  const aprueba = /\bautoriz(?:o|ada?|ado|adas|ados)\b|\bapruebo\b|\baprueba\b|\baprobad[oa]s?\b|\bvisto\s+bueno\b|\bde\s+acuerdo\b/
    .test(t);
  if (!rechaza && !aprueba) return null;

  const todas = /\btodas?\b|\blas\s+dos\b|\bambas\b|\blos\s+dos\b/.test(t);

  // «la 1», «numero 2», «#2». NO «la del 28»: ahí «la» va seguido de «del», y el 28 es una fecha.
  // Sin esta distinción, «autorizo la del 1 de septiembre» elegiría la solicitud número 1.
  const mNum = /\b(?:la|el|numero|numero|opcion|#)\s*([1-9])\b/.exec(t);

  // El nombre, si lo dijo. Se borran primero las frases fijas, igual que en el contacto de
  // emergencia: «autorizo las vacaciones DE hector» lleva un «de» que no es el del nombre.
  const limpio = t
    .replace(/las?\s+vacaciones|la\s+solicitud|la\s+incidencia|el\s+permiso|los\s+dias/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  let quien: string | null = null;
  const mQuien = /\b(?:de|del)\s+(.+)$/.exec(limpio);
  if (mQuien) {
    let cand = mQuien[1].trim().replace(/[?!.,;:]+$/, "");
    let antes;
    do {
      antes = cand;
      cand = cand.replace(/^(el|la|los|las|sr|sra|srta|senor|senora|don|dona|ing|lic|c|colaborador|empleado)\s+/, "").trim();
    } while (cand !== antes);
    // Detrás de «de» puede venir una fecha o el resto de la frase, no una persona.
    const noEsPersona = /^(\d|enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre|hoy|manana|ayer|una|un|todo|todas)/;
    if (cand.length >= 3 && !noEsPersona.test(cand)) quien = cand;
  }

  return {
    decision: rechaza ? "RECHAZADA" : "APROBADA",
    todas,
    numero: mNum ? Number(mNum[1]) : null,
    quien,
  };
}

/// Cómo se lee una solicitud en una línea: quién, cuándo y cuántos días.
function unaLinea(f: Record<string, unknown>): string {
  const dias = f.dias ?? "?";
  return `${f.colaborador ?? "?"} — ${f.fecha_inicio ?? "?"} a ${f.fecha_fin ?? "?"} (${dias} `
    + `${dias === 1 ? "dia" : "dias"})`;
}

/// El texto de la decisión. Dice SIEMPRE qué se tocó, con nombre y fechas.
///
/// Aprobar directo fue una decisión del usuario, sin paso de confirmación. Por eso la respuesta
/// tiene que ser un acuse completo y no un «listo»: si se aprobó lo que no era, hay que poder verlo
/// en el mismo mensaje y no descubrirlo en la nómina.
export interface ResultadoAutorizacion {
  estado: string;
  decision?: string;
  hechas?: Record<string, unknown>[];
  pendientes?: Record<string, unknown>[];
}

export function textoAutorizacion(r: ResultadoAutorizacion): string {
  if (r.estado === "sin_pendientes") {
    return "No tienes solicitudes PENDIENTES de tu gente. Si esperabas alguna, puede que ya este "
      + "resuelta o que la persona no te tenga como jefe inmediato en su expediente.";
  }

  if (r.estado === "ambiguo") {
    const lista = (r.pendientes ?? []).map((f, i) => `${i + 1}. ${unaLinea(f)}`).join("\n");
    // NO se elige por su cuenta. Hoy mismo Rodrigo tenía DOS pendientes, las dos de Héctor: con un
    // «Autorizo» a secas, cualquier regla automática -la primera, la más próxima- acertaría la
    // mitad de las veces.
    return `Tienes ${(r.pendientes ?? []).length} solicitudes pendientes:\n${lista}\n\n`
      + `Dime cual: «autorizo la 1», «autorizo la de ${primerNombreDe(r.pendientes?.[0])}» o `
      + `«autorizo todas».`;
  }

  if (r.estado === "no_encontrada") {
    const lista = (r.pendientes ?? []).map((f, i) => `${i + 1}. ${unaLinea(f)}`).join("\n");
    return `No encontre esa solicitud entre tus pendientes. Las que tienes son:\n${lista}`;
  }

  const hechas = r.hechas ?? [];
  const verbo = r.decision === "RECHAZADA" ? "Rechazada" : "Aprobada";
  const plural = hechas.length === 1 ? verbo : `${verbo}s ${hechas.length}`;
  const detalle = hechas.map((f) => `• ${unaLinea(f)}`).join("\n");
  return `${plural}:\n${detalle}`;
}

/// El primer nombre, para el ejemplo del mensaje. Con el nombre completo la frase se hace ilegible.
function primerNombreDe(f: Record<string, unknown> | undefined): string {
  const n = String(f?.colaborador ?? "").trim();
  return n ? n.split(/\s+/)[0].toLowerCase() : "esa persona";
}
