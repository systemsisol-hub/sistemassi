// Ejercita el guardia que impide entregar datos de la base que ninguna herramienta respaldo.
//
// Se EXTRAE del index.ts real en lugar de copiarlo, para que la prueba no pueda quedar verificando
// una version vieja. Node 22+ hace falta, por --experimental-strip-types:
//
//   node --experimental-strip-types supabase/functions/ai-assistant/verificar_invenciones.mjs
//
// Los casos «inventados» son textos REALES que produjo el modelo, y las cifras contra las que se
// comparan estan verificadas en SQL. Dos de ellos salieron en la aplicacion, no por WhatsApp: la
// pagina parecia acertar porque pinta una tarjeta con los datos crudos y la vista va a la tarjeta,
// pero su prosa tiene el mismo problema. De ahi que el guardia viva en la funcion y no en el puente.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { leer } from './verificar_permisos.mjs';

// Se leen LOS OCHO modulos, no `index.ts` solo: al partir el archivo estas funciones se fueron a
// nombres.ts y respuestas.ts. Leer el directorio completo evita volver aqui cada vez que algo se
// mueva de sitio.
const aqui = dirname(fileURLToPath(import.meta.url));
const src = readdirSync(aqui).filter((f) => f.endsWith('.ts')).sort()
  // `leer` normaliza CRLF; ver el porque en verificar_permisos.mjs.
  .map((f) => leer(join(aqui, f))).join('\n');

function extraerFuncion(nombre) {
  const i = src.indexOf(`function ${nombre}(`);
  if (i < 0) throw new Error(`no se encontro ${nombre}`);
  // La llave del CUERPO es la que cierra su linea; contar desde la primera que aparezca agarraria un
  // tipo de retorno con llaves.
  const abre = src.indexOf('{\n', i);
  if (abre < 0) throw new Error(`no se encontro el cuerpo de ${nombre}`);
  let prof = 0;
  for (let k = abre; k < src.length; k++) {
    if (src[k] === '{') prof++;
    else if (src[k] === '}') { prof--; if (prof === 0) return src.slice(i, k + 1); }
  }
  throw new Error(`llaves sin cerrar en ${nombre}`);
}

/// Extrae una constante que abre con `[` o `{`, contando delimitadores.
///
/// Sin expresiones regulares a proposito: mi primer intento las armaba con `new RegExp` desde una
/// cadena, y `[\\s\\S]` acabo significando «barra, s o S» en vez de «cualquier caracter». Contar
/// delimitadores no tiene ese problema.
function extraerConst(nombre) {
  const i = src.indexOf(`const ${nombre}`);
  if (i < 0) throw new Error(`no se encontro ${nombre}`);
  let k = src.indexOf('=', i);
  while (src[k] !== '[' && src[k] !== '{') k++;
  let prof = 0;
  for (; k < src.length; k++) {
    if (src[k] === '[' || src[k] === '{') prof++;
    else if (src[k] === ']' || src[k] === '}') {
      prof--;
      if (prof === 0) return src.slice(i, src.indexOf(';', k) + 1);
    }
  }
  throw new Error(`delimitadores sin cerrar en ${nombre}`);
}

const tmp = join(tmpdir(), 'ai-assistant-invenciones.ts');
writeFileSync(tmp, `${extraerConst('MESES')}\n\n`
  + `${extraerConst('NOMBRE_MES')}\n\n`
  + `${extraerConst('DATOS_QUE_NO_SE_INVENTAN')}\n\n`
  + `${extraerFuncion('sinAcentos')}\n\n`
  + `${extraerFuncion('afirmaDatoSinRespaldo')}\n\n`
  + `${extraerFuncion('preguntaSusVacaciones')}\n\n`
  + `${extraerFuncion('textoUltimaSolicitud')}\n\n`
  + `${extraerFuncion('textoVacacionesPropias')}\n\n`
  + `${extraerFuncion('preguntaContactoEmergencia')}

`
  + `${extraerFuncion('textoContactoEmergencia')}

`
  + `${extraerFuncion('preguntaSuHorario')}\n\n`
  + `${extraerFuncion('textoHorario')}\n\n`
  + `${extraerFuncion('soloUnIdentificador')}\n\n`
  + `${extraerFuncion('preguntaFaltasDe')}\n\n`
  + `${extraerFuncion('textoAsistencia')}\n\n`
  + `${extraerFuncion('preguntaIncidenciasDe')}\n\n`
  + `${extraerFuncion('textoIncidencias')}\n\n`
  + `${extraerFuncion('preguntaSuEquipo')}\n\n`
  + `${extraerFuncion('textoEquipoPropio')}\n\n`
  + `${extraerFuncion('alcanceDeLaConsulta')}\n\n`
  + `${extraerFuncion('preguntaCumpleanos')}\n\n`
  + `${extraerFuncion('textoCumpleanos')}\n`
  + 'export { afirmaDatoSinRespaldo, preguntaSusVacaciones, textoVacacionesPropias,\n'
  + '  preguntaCumpleanos, textoCumpleanos, textoUltimaSolicitud,\n'
  + '  preguntaSuEquipo, textoEquipoPropio, alcanceDeLaConsulta, soloUnIdentificador,\n'
  + '  preguntaIncidenciasDe, textoIncidencias, preguntaFaltasDe, textoAsistencia,\n'
  + '  preguntaSuHorario, textoHorario, preguntaContactoEmergencia, textoContactoEmergencia };\n', 'utf8');
const { afirmaDatoSinRespaldo, preguntaSusVacaciones, textoVacacionesPropias,
  preguntaCumpleanos, textoCumpleanos, textoUltimaSolicitud,
  preguntaSuEquipo, textoEquipoPropio, alcanceDeLaConsulta, soloUnIdentificador,
  preguntaIncidenciasDe, textoIncidencias, preguntaFaltasDe, textoAsistencia,
  preguntaSuHorario, textoHorario, preguntaContactoEmergencia, textoContactoEmergencia } =
  await import('file://' + tmp.replace(/\\/g, '/'));

let fallos = 0;
function ok(desc, cond, extra = '') {
  if (cond) console.log(`  ok     ${desc}`);
  else { console.log(`  FALLA  ${desc}${extra ? '\n           ' + extra : ''}`); fallos++; }
}
const nada = new Set();

console.log('Se bloquea lo que el modelo se invento SIN llamar a ninguna herramienta');
const inventados = [
  ['0 dias de quien tiene 102 (WhatsApp, 11/08 18:20)', 'vacaciones de enrique ortega gomez',
   'El cálculo arroja **0 días disponibles**. No veo periodos registrados.'],
  ['numero de empleado falso, 1250 en vez de 0162 (11/08 18:32)', 'vacaciones de ana maria lopez vigil',
   'Ana María López Vigil, 1250:\n- Disponibles: **16 días**\n- Asignados: 20'],
  ['persona que no existe con el numero de otra (11/08 19:58)', 'vacaciones de claudia bravo lomeli',
   '*CLAUDIA PATRICIA BRAVO LOMELI* — empleado 2277\nDias disponibles: *8*'],
  ['imitando la nota del puente (12/08 08:41)', 'y las de bravo lomeli',
   '[el sistema entregó la ficha de vacaciones de BRAVO LOMELI: 0 días disponibles'],
  // Este se le escapo a la primera version del guardia: buscaba «dias disponibles» PEGADAS y aqui
  // hay dos palabras en medio. Son 40 dias, no 105 -verificado en SQL, empleado 2189-.
  ['105 en vez de 40, con palabras en medio (12/08)', 'vacaciones de ector figuera',
   'HECTOR FIGUEROA VALLEJO tiene 105 dias de vacaciones disponibles.'],
  ['en la APLICACION: empleado 4011, cuando el mas alto es 2487 (12/08)', 'bravo lomeli',
   'Aquí tienes las vacaciones de **JESUS BRAVO LOMELI** (empleado 4011), fecha base 14/03/2022:\n'
   + '| Periodo | Días de ley | Solicitados | Disponibles |\n| 2024 - 2025 (actual) | 16 | 14 | 1 |\n'
   + '**Total disponible: 1 día**'],
];
for (const [comoEra, , texto] of inventados) {
  ok(`se bloquea: ${comoEra}`, afirmaDatoSinRespaldo(texto, nada), texto.slice(0, 80));
}

console.log('\nCon la herramienta detras, los MISMOS datos pasan');
const conVacaciones = new Set(['calcular_vacaciones']);
const conColaborador = new Set(['buscar_colaborador']);
ok('la ficha real de Enrique, con calcular_vacaciones detras',
   !afirmaDatoSinRespaldo('*ENRIQUE ORTEGA GOMEZ* — empleado 0170\nDias disponibles: *102*', conVacaciones));
ok('un numero de empleado, con buscar_colaborador detras',
   !afirmaDatoSinRespaldo('Es el empleado 0186, Gerente TI.', conColaborador));
ok('un numero de empleado que salio de calcular_vacaciones',
   !afirmaDatoSinRespaldo('CLAUDIA ANDREA BRAVO GARCIA — empleado 2306, 15 días disponibles', conVacaciones));

console.log('\nUn cumpleaños con fecha tampoco se inventa');
// Reportado: preguntado por los cumpleaños de la semana, invento a una persona. La pantalla no
// muestra a NADIE entre el 10 y el 16 de agosto -comprobado con el filtro de social_page.dart- y el
// asistente no tenia acceso a `fecha_nacimiento` por ninguna via: la columna no aparecia ni una vez
// en la funcion.
ok('se bloquea una fecha de cumpleaños sin herramienta',
   afirmaDatoSinRespaldo('Esta semana cumple Paloma, el 14 de agosto.', nada));
ok('se bloquea una lista de cumpleaños',
   afirmaDatoSinRespaldo('Cumpleaños de agosto:\n- 3 Juan\n- 12 Ana', nada));
ok('con buscar_cumpleanos detras SI pasa',
   !afirmaDatoSinRespaldo('Cumpleaños de agosto: dia 1 Rogelio, dia 8 Jesus.',
     new Set(['buscar_cumpleanos'])));
ok('decir que no cumple nadie NO se bloquea: no lleva fecha',
   !afirmaDatoSinRespaldo('Esta semana no cumple años nadie.', nada));
// El falso positivo que tenia esta regla: «cumple» mas un digito la disparaba, y la antiguedad no
// es un cumpleaños. El modelo la calcula con la fecha de ingreso que ya trae la ficha, asi que no
// necesita buscar_cumpleanos detras.
ok('la antiguedad NO se confunde con un cumpleaños',
   !afirmaDatoSinRespaldo('En marzo cumple 5 años en la empresa.', nada));
ok('ni dicha al reves',
   !afirmaDatoSinRespaldo('Lleva 12 años de antigüedad, así que le tocan 22 días de ley.', nada));

console.log('\nSin haber consultado nada, no se entrega una lista de registros');
// La regla que NO depende de ninguna palabra. El caso real: «umpleaños en septiembre (4):» con cuatro
// viñetas. Una letra de menos basto para que /cumplea/ no coincidiera y pasaran cuatro nombres falsos.
const listaFalsa = 'umpleaños en septiembre (4):\n'
  + '• 6 — CLAUDIA IVETH RIVERA CRUZ, SUBDIRECTORA\n'
  + '• 11 — EDGAR ENRIQUE GONZALEZ RODRIGUEZ, AUXILIAR\n'
  + '• 23 — JOSE GUADALUPE CAZARES BACA, ANALISTA';
ok('se bloquea la lista inventada, aunque la palabra venga mal escrita',
   afirmaDatoSinRespaldo(listaFalsa, nada));
ok('una tabla con barras tambien',
   afirmaDatoSinRespaldo('| 1 | ROGELIO |\n| 8 | JESUS |', nada));
ok('con herramienta detras, la MISMA lista pasa',
   !afirmaDatoSinRespaldo(listaFalsa, new Set(['buscar_cumpleanos'])));
ok('una lista de lo que SI puede hacer no se bloquea: no lleva cifras',
   !afirmaDatoSinRespaldo('Puedo ayudarte con:\n• tus vacaciones\n• tu inventario', nada));
ok('un solo renglon con cifra no es una tabla',
   !afirmaDatoSinRespaldo('Te lo resumo:\n• 1 solicitud pendiente', nada));

// Reportado: «vacaciones de lopez» acabo en «No pude confirmar ese dato». La herramienta SI devolvia
// candidatos, pero dentro del campo `error`, asi que no contaba como consulta y el guardia bloqueaba
// la lista que yo mismo pedia mostrar. Una lista de candidatos es legitima aunque no se haya
// encontrado a la persona: preguntar «¿es alguno de estos?» es justo lo que debe hacer.
const tablaDeCandidatos = 'Hay 4 personas con esos apellidos:\n'
  + '| 1 | 0592 | JUDITH ANAHI HERNANDEZ GARCIA | RECEPCIONISTA |\n'
  + '| 2 | 0187 | MARIA DE JESUS GARCIA HERNANDEZ | RECEPCIONISTA |';
ok('una tabla de candidatos pasa si SE LLAMO a una herramienta, aunque no trajera datos',
   !afirmaDatoSinRespaldo(tablaDeCandidatos, nada, true));
ok('y sigue bloqueada si no se llamo a ninguna',
   afirmaDatoSinRespaldo(tablaDeCandidatos, nada, false));

console.log('\nY NO se bloquea lo que el modelo si puede contestar solo');
ok('conocimiento general de la ley, sin hablar de nadie',
   !afirmaDatoSinRespaldo('Con 5 años cumplidos la Ley Federal del Trabajo da 20 días.', nada),
   'esto es correcto y no afirma nada de ninguna persona');
ok('decir que no encontro a la persona',
   !afirmaDatoSinRespaldo('No encontré a ningún colaborador con "Bravo Lomeli" en su nombre. ¿Lo busco por número?', nada));
ok('pedir mas datos',
   !afirmaDatoSinRespaldo('"Bravo" corresponde a varias personas. ¿De cuál te refieres?', nada));
ok('un saludo', !afirmaDatoSinRespaldo('¡Hola, Angel! ¿En qué te ayudo?', nada));
ok('algo fuera de su ambito',
   !afirmaDatoSinRespaldo('Eso queda fuera de lo mío.', nada));
ok('hablar de vacaciones sin dar cifras',
   !afirmaDatoSinRespaldo('Lo autoriza tu jefe directo. Puedes crear la solicitud y queda pendiente.', nada));
ok('una pregunta que no es de vacaciones, con numeros que no son de empleado',
   !afirmaDatoSinRespaldo('Hay 14 equipos registrados en esa ubicación.', new Set(['buscar_inventario'])));

console.log('\nLa via directa reconoce «mis vacaciones» y NO se la queda cuando es de otro');
// El caso que rompi: «cuales son mis vacaciones?» quedaba bloqueado por el guardia, y a la segunda
// el modelo repetia mi propio texto de rechazo sin consultar nada. Esta via no pasa por el modelo.
for (const q of [
  'cuales son mis vacaciones?',
  'Cuantas vacaciones tengo',
  'cuantos dias de vacaciones tengo?',
  'cuantas vacaciones me quedan',
  'cuantos dias me corresponden de vacaciones',
  'mis dias disponibles',
  'cual es mi saldo de dias',
  'vacaciones que tengo',
]) {
  ok(`la atiende: "${q}"`, preguntaSusVacaciones(q));
}
for (const q of [
  // De otra persona: las resuelve el modelo, que sabe buscar el nombre y pedir aclaraciones.
  'vacaciones de enrique ortega gomez',
  'las de claudia andrea',
  'y las de bravo lomeli',
  'el de hector figeroa',
  // «de mi jefe» habla de OTRA persona. Colarlo aqui devolveria el saldo de quien pregunta.
  'cuales son las vacaciones de mi jefe',
  'las vacaciones de mi compañero',
  // No son preguntas de saldo.
  'quiero crear una solicitud de vacaciones',
  'puedo pedir vacaciones en diciembre?',
  'cuantas laptops tengo asignadas',
  'cual es mi numero de empleado',
  'Soli?',
]) {
  ok(`la deja pasar: "${q}"`, !preguntaSusVacaciones(q));
}

console.log('\nEl texto de la via directa sale de los datos, no del modelo');
const propias = { total_disponible: 74, periodos: [
  { periodo: '2023 - 2024', dias_disponibles: 20, es_periodo_actual: false },
  { periodo: '2026 - 2027', dias_disponibles: 6,  es_periodo_actual: true  },
] };
const txt = textoVacacionesPropias(propias);
console.log(`  -> "${txt}"`);
ok('dice el total', txt.includes('74'));
ok('dice el periodo actual y su saldo', txt.includes('2026 - 2027') && txt.includes('6'));
ok('un solo dia va en singular',
   textoVacacionesPropias({ total_disponible: 1, periodos: [] }).includes('1 dia de'),
   textoVacacionesPropias({ total_disponible: 1, periodos: [] }));
ok('sin periodo actual no deja la frase a medias',
   !textoVacacionesPropias({ total_disponible: 0, periodos: [] }).includes('periodo actual'));

console.log('\nLa ultima solicitud viene en la MISMA respuesta que la tabla');
// Pedido tal cual: «cuando pido vacaciones marco, la tabla de sus vacaciones Y su ultimo registro».
// Eran dos herramientas y el modelo tenia que encadenarlas, que es donde se rompe.
// Datos reales del 0186: su ultima solicitud empieza el 21/08 y hoy es el 12, o sea que esta POR VENIR.
const conSalida = { solicitudes: [
  { periodo: '2016 - 2017', dias: 6, status: 'APROBADA', fecha_inicio: '2026-08-21',
    fecha_fin: '2026-08-28', fecha_regreso: '2026-08-31', por_venir: true },
  { periodo: '2020 - 2021', dias: 1, status: 'APROBADA', fecha_inicio: '2026-04-06',
    fecha_fin: '2026-04-06', fecha_regreso: '2026-04-07', por_venir: false },
] };
const linea = textoUltimaSolicitud(conSalida, 'Su');
console.log(`  -> ${linea.trim()}`);
ok('dice que esta POR VENIR, no que ya paso', linea.includes('próxima salida'));
ok('trae las fechas de inicio y fin', linea.includes('2026-08-21') && linea.includes('2026-08-28'));
ok('trae los dias, el estatus y el periodo',
   linea.includes('6 días') && linea.includes('APROBADA') && linea.includes('2016 - 2017'));
ok('y la fecha de regreso, que es la que le sirve al jefe', linea.includes('2026-08-31'));
ok('una que ya paso se llama ultima, no proxima',
   textoUltimaSolicitud({ solicitudes: [{ ...conSalida.solicitudes[1] }] }, 'Su')
     .includes('última salida'));
ok('sin solicitudes lo dice, no deja la frase colgando',
   textoUltimaSolicitud({ solicitudes: [] }, 'Su').includes('No tiene solicitudes'));
ok('un solo dia va en singular',
   textoUltimaSolicitud({ solicitudes: [{ ...conSalida.solicitudes[1] }] }, 'Su')
     .includes('1 día'));

console.log('\nLas incidencias de alguien: la pregunta donde mas se invento');
// El caso real: pedido el historial de Marco, se invento una incidencia entera y la defendio con
// «No invento». De las 1167 incidencias de la base, cero coinciden en ningun campo.
for (const [q, esperado] of [
  ['incidencias de marco montoya', 'marco montoya'],
  ['las incidencias de hector figueroa vallejo', 'hector figueroa vallejo'],
  ['que incidencias tiene bravo lomeli', 'bravo lomeli'],
  ['dame las incidencias del 0186', '0186'],
  ['incidencias de la sra lopez vigil', 'lopez vigil'],
]) {
  const r = preguntaIncidenciasDe(q);
  ok(`"${q}" -> "${esperado}"`, r?.quien === esperado, JSON.stringify(r));
}
for (const q of ['mis incidencias', 'que incidencias tengo', 'mis incidencias pendientes?']) {
  const r = preguntaIncidenciasDe(q);
  ok(`"${q}" es propia`, r?.propio === true, JSON.stringify(r));
}
for (const q of [
  // Del conjunto, no de una persona: eso lo contesta el modelo con la herramienta.
  'cuantas incidencias hay',
  'todas las incidencias de la empresa',
  'incidencias pendientes',
  // Lo que va detras de «de» no siempre es una persona.
  'incidencias de agosto',
  'incidencias de este mes',
  'incidencias de vacaciones',
  'incidencias de 2026',
  // Y «vacaciones» a secas la atiende calcular_vacaciones, que ya da la tabla y la ultima salida.
  'vacaciones de marco montoya',
  'cuantas vacaciones tengo',
  'hola',
]) {
  ok(`no se la queda: "${q}"`, preguntaIncidenciasDe(q) === null);
}

// El texto sale de los renglones, con las fechas REALES de Marco.
const incMarco = { count: 3, results: [
  { periodo: '2020 - 2021', dias: 1, status: 'APROBADA', fecha_inicio: '2026-04-06',
    fecha_fin: '2026-04-06', fecha_regreso: '2026-04-07' },
  { periodo: '2016 - 2017', dias: 6, status: 'APROBADA', fecha_inicio: '2026-08-21',
    fecha_fin: '2026-08-28', fecha_regreso: '2026-08-31' },
  { periodo: '2020 - 2021', dias: 6, status: 'APROBADA', fecha_inicio: '2026-01-02',
    fecha_fin: '2026-01-09', fecha_regreso: '2026-01-12' },
] };
const txtInc = textoIncidencias(incMarco, 'MARCO ANTONIO MONTOYA LOPEZ (empleado 0186)');
console.log(`  -> ${txtInc.replace(/\n/g, ' | ')}`);
ok('dice cuantas son', txtInc.includes('3 incidencias'));
ok('la mas reciente va primero, por fecha de SALIDA y no de captura',
   txtInc.indexOf('21/08/2026') < txtInc.indexOf('06/04/2026'));
ok('trae el regreso, que es lo que usa un jefe', txtInc.includes('regreso 31/08/2026'));
ok('las fechas van en dia/mes/año', txtInc.includes('21/08/2026 al 28/08/2026'));
// Lo que importa: que NO aparezca la incidencia inventada.
ok('NO aparece la incidencia inventada del 31/08 al 31/08',
   !txtInc.includes('31/08/2026 al 31/08/2026'));
ok('ni un periodo «2026» que no existe en la base', !/periodo 2026\b/.test(txtInc));
ok('sin incidencias lo dice, no deja la lista vacia',
   textoIncidencias({ count: 0, results: [] }, 'Enrique').includes('no tiene incidencias'));
ok('una sola va en singular',
   textoIncidencias({ count: 1, results: [incMarco.results[0]] }, 'X').includes('tiene 1 incidencia'));

console.log('\nFaltas y asistencia: la via directa, y lo que NO se queda');
for (const [q, esperado] of [
  ['faltas de marco montoya', 'marco montoya'],
  ['cuantas faltas tiene hector figueroa', 'hector figueroa'],
  ['la asistencia de lopez vigil', 'lopez vigil'],
  ['retardos del 0186', '0186'],
  ['puntualidad de la sra bravo garcia', 'bravo garcia'],
]) {
  const r = preguntaFaltasDe(q);
  ok(`"${q}" -> "${esperado}"`, r?.quien === esperado, JSON.stringify(r));
}
// Reportado: «que dias llego tarde brenda mondragon» se fue al modelo, que ademas pidio un rango de
// fechas que no necesitaba. Es la forma NORMAL de preguntarlo; nadie dice «dame los retardos».
for (const [q, esperado] of [
  ['que dias llego tarde brenda mondragon', 'brenda mondragon'],
  ['a que hora llego marco montoya', 'marco montoya'],
  ['dias que llego tarde hector figueroa', 'hector figueroa'],
]) {
  const r = preguntaFaltasDe(q);
  ok(`"${q}" -> "${esperado}"`, r?.quien === esperado, JSON.stringify(r));
}
for (const q of ['mis faltas', 'cuantos retardos tengo', 'mi asistencia de este mes', 'tuve faltas?',
                 'que dias llegue tarde']) {
  ok(`"${q}" es propia`, preguntaFaltasDe(q)?.propio === true, JSON.stringify(preguntaFaltasDe(q)));
}
for (const q of [
  // «falta» tambien es verbo, y esto no es una pregunta de asistencia.
  'me falta un dia de vacaciones',
  'hace falta que autorice mi jefe',
  'falta por aprobar mi solicitud',
  // Del conjunto: lo contesta el modelo con la herramienta, o la pagina.
  'cuantas faltas hay en total',
  'quien falto esta semana',
  'faltas por zona',
  'las faltas de toda la empresa',
  // Ni de asistencia.
  'cuantas vacaciones tengo',
  'incidencias de marco',
  'faltas de agosto',
  'hola',
]) {
  ok(`no se la queda: "${q}"`, preguntaFaltasDe(q) === null, JSON.stringify(preguntaFaltasDe(q)));
}

// El texto sale de las cifras. Datos con la forma real de la herramienta.
const asisReal = {
  colaborador: 'MARCO ANTONIO MONTOYA LOPEZ', numero_empleado: '0186',
  desde: '2026-07-16', hasta: '2026-07-31', dias_esperados: 12, asistio: 9,
  faltas_sin_justificar: 2, justificados: 1, checadas_evaluadas: 10, retardos: 4,
  minutos_de_retardo: 63, puntualidad_pct: 60, retardos_por_descuento: 3, dias_de_descuento: 3,
  dias_con_incidencia: [
    { fecha: '2026-07-20', estado: 'FALTA', motivo: null },
    { fecha: '2026-07-23', estado: 'JUSTIFICADO', motivo: 'permiso medico' },
    { fecha: '2026-07-29', estado: 'FALTA', motivo: null },
  ],
  // Datos REALES de Brenda Mondragon: los minutos se cuentan desde el LIMITE, no desde la entrada.
  // 08:29 contra un limite de 08:15 son 14 minutos, no 29.
  dias_de_retardo: [
    { fecha: '2026-07-16', llego: '08:29:00', entrada_de_su_horario: '08:00:00',
      limite_con_tolerancia: '08:15:00', minutos_tarde: 14 },
    { fecha: '2026-07-24', llego: '09:30:00', entrada_de_su_horario: '09:00:00',
      limite_con_tolerancia: '09:15:00', minutos_tarde: 15 },
  ],
};
const txtAsis = textoAsistencia(asisReal, 'MARCO ANTONIO MONTOYA LOPEZ (empleado 0186)');
console.log(`  -> ${txtAsis.replace(/\n/g, ' | ')}`);
ok('dice las faltas sin justificar', txtAsis.includes('Faltas sin justificar: 2'));
ok('y los justificados aparte', txtAsis.includes('Justificados: 1'));
ok('los retardos con sus minutos', txtAsis.includes('4') && txtAsis.includes('63 minutos'));
ok('los dias a descontar, que es lo que se busca', txtAsis.includes('Dias a descontar: 3'));
ok('lista los dias con su fecha', txtAsis.includes('20/07') && txtAsis.includes('29/07'));
ok('el motivo del justificado', txtAsis.includes('permiso medico'));

// Lo reportado: se pedia la HORA de cada retardo y se contestaba con el total de minutos.
ok('dice a que hora llego cada dia', txtAsis.includes('llego 08:29'));
ok('y a que hora entraba, que cambia segun el dia',
   txtAsis.includes('entraba 08:00') && txtAsis.includes('entraba 09:00'));
ok('con el limite de tolerancia, para que la resta se pueda seguir',
   txtAsis.includes('limite 08:15'));
ok('sin segundos: no dicen nada y ocupan media linea', !txtAsis.includes('08:29:00'));
ok('los minutos van por dia, no solo el total', txtAsis.includes('14 min tarde'));

// La distincion que mas importa de todo esto.
const txtVacio = textoAsistencia({ sin_datos: true }, 'PALOMA ILYANA DE LA TOBA');
ok('«sin datos» NO se dice como «cero faltas»',
   txtVacio.includes('no es lo mismo que no tenerlas'));
ok('y no afirma ninguna cifra', !/\b\d+\s*faltas/.test(txtVacio));

console.log('\nUn mensaje que es SOLO un identificador no pasa por el modelo');
// Los tres casos reales del historial de WhatsApp del 12/08/2026. «0170» acabo con el nombre de otra
// persona pegado al numero, y los dos uuid en «no tengo acceso por UUID», que es falso.
ok('«0170» es un numero de empleado',
   soloUnIdentificador('0170')?.numero_empleado === '0170');
ok('con espacios alrededor tambien',
   soloUnIdentificador('  0170 ')?.numero_empleado === '0170');
ok('un uuid pegado es un usuario_id',
   soloUnIdentificador('a1d4a9fb-9173-4690-aba8-da604eade495')?.usuario_id
     === 'a1d4a9fb-9173-4690-aba8-da604eade495');
ok('el otro uuid del historial, tambien',
   soloUnIdentificador('9cf3eb50-a410-4f89-8752-182c8b918583')?.usuario_id !== undefined);
ok('un uuid en mayusculas', soloUnIdentificador('9CF3EB50-A410-4F89-8752-182C8B918583') !== null);
for (const q of [
  // Con una intencion pegada, la resuelve el modelo: puede no ser una ficha lo que se pide.
  'vacaciones de 0170',
  'incidencias del 0170',
  'busca a 0170',
  // Un numero corto puede ser la respuesta a otra pregunta -«¿cuantos dias?» «5»-.
  '5',
  '26',
  // Y lo que no es un identificador.
  'hola',
  '',
  'a1d4a9fb-9173-4690',
  '2026-08-31',
]) {
  ok(`no se la queda: "${q}"`, soloUnIdentificador(q) === null);
}

console.log('\nLa via directa del equipo propio, y lo que NO se queda');
// El caso real del 12/08/2026: un administrador pregunto esto y recibio el LAP-TOP de otra persona,
// porque `buscar_inventario` le devuelve TODO el inventario si no se le pasa usuario_id.
for (const q of [
  'hola me puedes decir que equipo de computo tengo asignado?',
  'que equipo tengo asignado',
  'cual es mi equipo',
  'que laptop tengo',
  'mi celular de la empresa',
  'que tengo asignado del inventario',
  'que equipos me asignaron',
  'mi computadora',
]) {
  ok(`la atiende: "${q}"`, preguntaSuEquipo(q));
}
for (const q of [
  // De otra persona: lo resuelve el modelo, que sabe buscar el nombre.
  'que equipo tiene abraham acuña',
  'el equipo de hector figueroa',
  'que laptop trae marco montoya',
  // Del inventario entero, no de nadie en particular.
  'cuantas laptops hay',
  'equipos sin asignar',
  'que equipos hay en vidamar',
  'dame todo el inventario',
  'cuantos equipos hay en total',
  // No son preguntas de inventario.
  'cuantas vacaciones tengo',
  'mis incidencias',
  'Soli?',
]) {
  ok(`la deja pasar: "${q}"`, !preguntaSuEquipo(q));
}

const equipoReal = { count: 2, results: [
  { tipo: 'TEL. CELULAR', marca: 'XIAOMI', modelo: 'A10', n_s: '38905/62TB05473',
    condicion: 'NUEVO', ubicacion: 'CONSTITUYENTES' },
  { tipo: 'LAPTOP', marca: 'DELL', modelo: 'X15', n_s: 'DERTY5676',
    condicion: 'USADO', ubicacion: 'CONSTITUYENTES' },
] };
const txtEquipo = textoEquipoPropio(equipoReal);
console.log(`  -> ${txtEquipo.replace(/\n/g, ' | ')}`);
ok('dice cuantos son', txtEquipo.includes('2 equipos'));
ok('trae la serie, que es lo que sirve para un ticket', txtEquipo.includes('DERTY5676'));
ok('trae marca y modelo', txtEquipo.includes('DELL') && txtEquipo.includes('X15'));
// Lo que de verdad importa: que NO aparezca el equipo de Abraham, que es lo que se contesto.
ok('NO aparece el equipo de otra persona', !txtEquipo.includes('PF4ZDWD'));
ok('sin equipos lo dice, no deja la lista vacia',
   textoEquipoPropio({ count: 0, results: [] }).startsWith('No tienes ningun equipo'));
ok('un solo equipo va en singular',
   textoEquipoPropio({ count: 1, results: [equipoReal.results[1]] }).includes('1 equipo asignado'));

console.log('\nCada consulta dice DE QUIEN son los renglones que devuelve');
ok('sin usuario_id avisa de que son de toda la empresa',
   alcanceDeLaConsulta('', 'equipos').includes('TODA la empresa'));
ok('y avisa de que no hay que atribuirlos a quien pregunta',
   alcanceDeLaConsulta('', 'equipos').includes('no atribuyas ninguno a quien pregunta'));
ok('con el usuario_id propio lo dice claro',
   alcanceDeLaConsulta('propio', 'equipos') === 'Solo los equipos de quien pregunta.');
ok('con el de otro, tambien',
   alcanceDeLaConsulta('de un usuario', 'incidencias').includes('del usuario que se pidio'));
ok('los que no tienen dueño se distinguen',
   alcanceDeLaConsulta('sin asignar', 'equipos').includes('no tienen usuario asignado'));

console.log('\nLa via directa de cumpleaños lee el mes de la pregunta');
// «cumpleaños de septiembre» acabo en el guardia porque el modelo no llamo a la herramienta, aunque
// septiembre tiene nueve cumpleaños. Callar es mejor que inventar, pero es la respuesta equivocada
// cuando el dato esta a mano.
for (const [q, mes, semana] of [
  ['cumpleaños de septiembre', 9, false],
  ['cumpleaños de este mes', null, false],
  ['quién cumple esta semana', null, true],
  ['quienes cumplen años en diciembre', 12, false],
  ['cumpleaños de setiembre', 9, false],
  ['cumpleaños de la semana', null, true],
]) {
  const r = preguntaCumpleanos(q, '');
  ok(`"${q}" -> mes ${mes}, semana ${semana}`,
     r !== null && r.mes === mes && r.soloEstaSemana === semana, JSON.stringify(r));
}
ok('«cumple 5 años en la empresa» NO es un cumpleaños: es antiguedad',
   preguntaCumpleanos('cuando cumple 5 años en la empresa', '') === null);
ok('una pregunta de vacaciones no se la queda',
   preguntaCumpleanos('cuales son mis vacaciones', '') === null);

console.log('\nUn seguimiento como «y de septiembre?» tambien se atiende');
// Reportado: tras «cumpleaños de este mes», la pregunta «y de septiembre?» no llevaba la palabra, la
// via directa no se activo, y el modelo invento CUATRO personas. Septiembre tiene nueve, y se ven en
// la pantalla. Empezo con «umpleaños en septiembre (4):», imitando el formato de la respuesta buena.
const previa = 'cumpleaños de este mes?';
ok('«y de septiembre?» despues de una de cumpleaños',
   preguntaCumpleanos('y de septiembre?', previa)?.mes === 9);
ok('«y de octubre?»', preguntaCumpleanos('y de octubre?', previa)?.mes === 10);
ok('«y esta semana?»', preguntaCumpleanos('y esta semana?', previa)?.soloEstaSemana === true);
ok('«y de septiembre?» SIN una pregunta previa de cumpleaños no se la queda',
   preguntaCumpleanos('y de septiembre?', 'vacaciones de enrique') === null);
ok('«y las vacaciones de septiembre?» no se la queda, aunque venga despues',
   preguntaCumpleanos('y las vacaciones de septiembre?', previa) === null);
ok('un seguimiento que no nombra fecha se deja al modelo',
   preguntaCumpleanos('y del otro?', previa) === null);

console.log('\nEl texto de cumpleaños sale de los datos');
const sept = { mes: 9, rango: null, count: 2, results: [
  { dia: 8, nombre: 'MARIA NATIVIDAD CHACON', puesto: null },
  { dia: 13, nombre: 'YOLANDA ITZEL MARQUEZ', puesto: 'ANALISTA' },
] };
const txtSept = textoCumpleanos(sept);
console.log(`  -> ${txtSept.replace(/\n/g, ' | ')}`);
ok('dice el mes por su nombre', txtSept.includes('septiembre'));
ok('lista a las dos personas con su dia',
   txtSept.includes('8 — MARIA NATIVIDAD CHACON') && txtSept.includes('13 — YOLANDA'));
ok('sin nadie lo dice, no deja la lista vacia',
   textoCumpleanos({ mes: 8, rango: '10 al 16', count: 0, results: [] })
     .startsWith('No hay cumpleaños esta semana'),
   textoCumpleanos({ mes: 8, rango: '10 al 16', count: 0, results: [] }));

console.log('\nEl horario propio: se pedia y salia el uuid');
// Reportado: «quiero mi horario» contestaba «3ac244d0-bf7f-4cfa-99ce-b9f3bffd749d», porque
// `profiles.horario` guarda el uuid de un renglon de `schedules` y se devolvia crudo.
for (const q of ['quiero mi horario', 'cual es mi horario', 'a que hora entro',
                 'a que hora salgo', 'mi jornada', 'que horario tengo']) {
  ok(`la atiende: "${q}"`, preguntaSuHorario(q));
}
for (const q of [
  'el horario de brenda mondragon',
  'que horario tiene marco montoya',
  'cuantos horarios hay',
  'lista de horarios',
  'horarios por zona',
  'cuantas vacaciones tengo',
  'hola',
]) {
  ok(`no se la queda: "${q}"`, !preguntaSuHorario(q));
}

// El horario REAL de Angel: lunes a jueves 08:00-18:00 y VIERNES 09:00-15:00. Ese viernes distinto es
// lo que explica el retardo del 24/07 con entrada a las 09:00, y por eso se listan los dias uno a uno
// en vez de resumir «L-V de 8 a 18», que seria falso.
const horarioReal = {
  nombre: 'Horario Oficina L-V ( Consti )', zona: 'Constituyentes',
  dias: [
    { dia: 'lunes', entrada: '08:00', salida: '18:00', tolerancia_min: 15 },
    { dia: 'viernes', entrada: '09:00', salida: '15:00', tolerancia_min: 15 },
  ],
};
const txtHor = textoHorario(horarioReal);
console.log(`  -> ${txtHor.replace(/\n/g, ' | ')}`);
ok('dice el nombre del horario', txtHor.includes('Horario Oficina L-V'));
ok('y la zona', txtHor.includes('Constituyentes'));
ok('la entrada y la salida de cada dia',
   txtHor.includes('lunes: 08:00 a 18:00') && txtHor.includes('viernes: 09:00 a 15:00'));
ok('la tolerancia, que es la que decide un retardo', txtHor.includes('tolerancia 15 min'));
// Lo reportado: que NO salga el uuid.
ok('NO aparece ningun uuid', !/[0-9a-f]{8}-[0-9a-f]{4}/.test(txtHor));
ok('sin horario asignado se dice, y que sin el no hay faltas que calcular',
   textoHorario({ dias: [] }).includes('no se pueden calcular'));
ok('con nombre pero sin dias se distingue',
   textoHorario({ nombre: 'Turno X', dias: [] }).includes('no tiene dias capturados'));

console.log('\nContacto de emergencia: lo propio sin permiso, lo de otro con');
for (const q of ['mi contacto de emergencia', 'a quien le aviso si me pasa algo',
                 'cual es mi tipo de sangre', 'mi referencia', 'mis datos de emergencia']) {
  ok(`propio: "${q}"`, preguntaContactoEmergencia(q)?.propio === true,
     JSON.stringify(preguntaContactoEmergencia(q)));
}
for (const [q, esperado] of [
  ['contacto de emergencia de marco montoya', 'marco montoya'],
  ['tipo de sangre de brenda mondragon', 'brenda mondragon'],
  ['la referencia de hector figueroa', 'hector figueroa'],
]) {
  const r = preguntaContactoEmergencia(q);
  ok(`"${q}" -> "${esperado}"`, r?.quien === esperado, JSON.stringify(r));
}
for (const q of [
  // «de emergencia» y «de sangre» no nombran a nadie: son parte de la pregunta.
  'contacto de emergencia',
  'tipo de sangre',
  'datos de referencia',
  // Otra pagina y otra herramienta.
  'contactos externos de la empresa',
  'el contacto del proveedor',
  // Y lo que no es esto.
  'cuantas vacaciones tengo',
  'hola',
]) {
  const r = preguntaContactoEmergencia(q);
  ok(`no se la queda como «de otro»: "${q}"`, r === null || r.propio === true, JSON.stringify(r));
}

// Con datos: se dan los que hay y se dice cual falta.
const conDatosEm = {
  colaborador: 'MARCO ANTONIO MONTOYA LOPEZ', numero_empleado: '0186',
  referencia_nombre: 'MARIA LOPEZ', referencia_telefono: '5551234567',
  referencia_relacion: 'ESPOSA', tipo_sangre: 'O+',
};
const txtEm = textoContactoEmergencia(conDatosEm, false);
console.log(`  -> ${txtEm.replace(/\n/g, ' | ')}`);
ok('dice de quien es', txtEm.includes('MARCO ANTONIO MONTOYA LOPEZ'));
ok('el nombre y la relacion juntos', txtEm.includes('MARIA LOPEZ') && txtEm.includes('ESPOSA'));
ok('el telefono', txtEm.includes('5551234567'));
ok('y el tipo de sangre', txtEm.includes('O+'));

// Un dato a medias: se dice que falta, NO se omite el renglon.
const aMedias = textoContactoEmergencia(
  { colaborador: 'X', referencia_nombre: 'ANA', referencia_telefono: null,
    referencia_relacion: null, tipo_sangre: null }, false);
ok('un dato ausente se dice, no se calla', aMedias.includes('sin registrar'));
ok('y sigue apareciendo el renglon del telefono', aMedias.includes('Telefono'));

// LA distincion que importa: de 244 vigentes solo 23 tienen referencia y NINGUNO tipo de sangre.
const vacio = textoContactoEmergencia(
  { colaborador: 'Y', referencia_nombre: null, referencia_telefono: null,
    referencia_relacion: null, tipo_sangre: null }, true);
ok('vacio se dice como NO REGISTRADO', vacio.includes('REGISTRADO'));
ok('y NO como «no tiene contacto»', !/no tiene contacto/i.test(vacio));
ok('dice donde se captura', vacio.includes('Colaborador'));


// El caso reportado el 19/08/2026: no se atendia por WhatsApp.
//
// «contacto DE emergencia» ya lleva un «de», y la expresion agarraba el PRIMERO: se quedaba con
// «emergencia de 0163» y lo descartaba por no ser una persona. El «de 0163» nunca se miraba.
for (const [q, esperado] of [
  ['cual es el contacto de emergencia de 0163', '0163'],
  ['cual es el contacto de emergencia del colaborador 0163', '0163'],
  ['contacto de emergencia de marco montoya', 'marco montoya'],
  ['datos de emergencia del empleado 0186', '0186'],
  ['tipo de sangre de brenda mondragon', 'brenda mondragon'],
  ['a quien le aviso de hector figueroa', 'hector figueroa'],
]) {
  const r = preguntaContactoEmergencia(q);
  ok(`"${q}" -> "${esperado}"`, r?.quien === esperado, JSON.stringify(r));
}
// Y sin nadie detras sigue siendo la propia, no la de un fantasma llamado «emergencia».
for (const q of ['contacto de emergencia', 'datos de emergencia', 'tipo de sangre',
                 'cual es mi contacto de emergencia']) {
  const r = preguntaContactoEmergencia(q);
  ok(`sin persona detras: "${q}"`, r === null || r.propio === true, JSON.stringify(r));
}

console.log(fallos === 0 ? '\nTODO BIEN' : `\n${fallos} FALLAS`);
process.exit(fallos === 0 ? 0 : 1);
