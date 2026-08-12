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

const tmp = join(tmpdir(), 'ai-assistant-invenciones.ts');
writeFileSync(tmp, `${extraerFuncion('sinAcentos')}\n\n`
  + `${extraerFuncion('afirmaDatoSinRespaldo')}\n\n`
  + `${extraerFuncion('preguntaSusVacaciones')}\n\n`
  + `${extraerFuncion('textoVacacionesPropias')}\n`
  + 'export { afirmaDatoSinRespaldo, preguntaSusVacaciones, textoVacacionesPropias };\n', 'utf8');
const { afirmaDatoSinRespaldo, preguntaSusVacaciones, textoVacacionesPropias } =
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

console.log(fallos === 0 ? '\nTODO BIEN' : `\n${fallos} FALLAS`);
process.exit(fallos === 0 ? 0 : 1);
