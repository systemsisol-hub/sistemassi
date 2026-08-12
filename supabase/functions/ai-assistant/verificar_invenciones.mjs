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
import { readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(aqui, 'index.ts'), 'utf8');

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
  + `${extraerFuncion('sinAcentos')}\n\n`
  + `${extraerFuncion('afirmaDatoSinRespaldo')}\n\n`
  + `${extraerFuncion('preguntaSusVacaciones')}\n\n`
  + `${extraerFuncion('textoUltimaSolicitud')}\n\n`
  + `${extraerFuncion('textoVacacionesPropias')}\n\n`
  + `${extraerFuncion('preguntaCumpleanos')}\n\n`
  + `${extraerFuncion('textoCumpleanos')}\n`
  + 'export { afirmaDatoSinRespaldo, preguntaSusVacaciones, textoVacacionesPropias,\n'
  + '  preguntaCumpleanos, textoCumpleanos, textoUltimaSolicitud };\n', 'utf8');
const { afirmaDatoSinRespaldo, preguntaSusVacaciones, textoVacacionesPropias,
  preguntaCumpleanos, textoCumpleanos, textoUltimaSolicitud } =
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

console.log(fallos === 0 ? '\nTODO BIEN' : `\n${fallos} FALLAS`);
process.exit(fallos === 0 ? 0 : 1);
