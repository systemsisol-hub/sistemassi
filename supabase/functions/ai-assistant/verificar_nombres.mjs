// Ejercita los ayudantes de busqueda por nombre.
//
// Se EXTRAEN del index.ts real en lugar de copiarlos, para que la prueba no pueda quedar verificando
// una version vieja de la logica. Node 22+ hace falta, por --experimental-strip-types:
//
//   node --experimental-strip-types supabase/functions/ai-assistant/verificar_nombres.mjs
//
// El caso que dio origen a esto: preguntar por "las vacaciones de Enrique Ortega Gomez" devolvia
// cero registros, porque el nombre entero se buscaba en la columna `nombre`, que guarda solo el
// nombre de pila.
import { readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(aqui, 'index.ts'), 'utf8');

function extraer(nombre) {
  const i = src.indexOf(`function ${nombre}(`);
  if (i < 0) throw new Error(`no se encontro ${nombre}`);
  let prof = 0, j = src.indexOf('{', i);
  for (let k = j; k < src.length; k++) {
    if (src[k] === '{') prof++;
    else if (src[k] === '}') { prof--; if (prof === 0) return src.slice(i, k + 1); }
  }
  throw new Error(`llaves sin cerrar en ${nombre}`);
}

const vacias = src.match(/^const PALABRAS_VACIAS = new Set\(\[[\s\S]*?\]\);$/m);
if (!vacias) throw new Error('no se encontro PALABRAS_VACIAS');

const modulo = vacias[0] + '\n\n' + ['sinAcentos', 'tokensDeNombre', 'tokenGuia', 'empataNombre',
  'distancia', 'tolerancia', 'empataNombreAproximado', 'filtroPrefijos', 'jefeAlQueSeRefiere']
  .map(extraer).join('\n\n') + `
export { sinAcentos, tokensDeNombre, tokenGuia, empataNombre,
  distancia, tolerancia, empataNombreAproximado, filtroPrefijos, jefeAlQueSeRefiere };
`;

const tmp = join(tmpdir(), 'ai-assistant-nombres.ts');
writeFileSync(tmp, modulo, 'utf8');
const m = await import('file://' + tmp.replace(/\\/g, '/'));

let fallos = 0;
// `esperado` por omision es `true`, para poder escribir `ok(desc, condicion)` en las comprobaciones
// que ya son booleanas. Sin ese valor por omision, omitirlo comparaba contra `undefined` y TODAS
// fallaban con `real=true esperado=undefined`, que parece un fallo del codigo y es del ayudante.
function ok(desc, real, esperado = true) {
  const a = JSON.stringify(real), b = JSON.stringify(esperado);
  if (a !== b) { console.log(`  FALLA  ${desc}\n           real=${a}  esperado=${b}`); fallos++; }
  else console.log(`  ok     ${desc}`);
}

console.log('sinAcentos: normaliza vocales, respeta la N con tilde');
ok('Gomez con acento', m.sinAcentos('Gómez'), 'Gomez');
ok('Peñafiel conserva la enie', m.sinAcentos('Peñafiel'), 'Peñafiel');
ok('Ortuño conserva la enie', m.sinAcentos('Ortuño'), 'Ortuño');
ok('varias juntas', m.sinAcentos('Jesús Ángel Muñóz'), 'Jesus Angel Muñoz');

console.log('\ntokensDeNombre: parte y sanea');
ok('nombre normal', m.tokensDeNombre('Enrique Ortega Gomez'), ['Enrique','Ortega','Gomez']);
ok('espacios de sobra', m.tokensDeNombre('  Enrique   Ortega '), ['Enrique','Ortega']);
ok('acentos fuera, enie dentro', m.tokensDeNombre('José Peñafiel'), ['Jose','Peñafiel']);
ok('la coma se cae: rompe el filtro or=()', m.tokensDeNombre('Ortega, Enrique'), ['Ortega','Enrique']);
ok('parentesis y puntos se caen', m.tokensDeNombre('Enrique (a.k.a) Ortega'), ['Enrique','aka','Ortega']);
ok('solo basura no deja tokens', m.tokensDeNombre('...,,,'), []);
ok('cadena vacia', m.tokensDeNombre(''), []);

// El modelo no siempre manda el nombre limpio. Reportado: "vacaciones de enrique ortega gomez"
// devolvia que la persona no existe, porque exigia que "vacaciones" y "de" estuvieran en el nombre.
ok('la frase entera se limpia',
   m.tokensDeNombre('vacaciones de enrique ortega gomez'), ['enrique','ortega','gomez']);
ok('"el de hector figeroa"', m.tokensDeNombre('el de hector figeroa'), ['hector','figeroa']);
ok('"los dias de mi jefe"', m.tokensDeNombre('los dias de mi jefe'), ['jefe']);
ok('un apellido real con DE LA sigue teniendo palabras utiles',
   m.tokensDeNombre('Nieto de la Garza'), ['Nieto','Garza']);
ok('solo palabras vacias no deja nada', m.tokensDeNombre('de la vacaciones'), []);

console.log('\ntokenGuia: la palabra mas larga');
ok('de tres', m.tokenGuia(['ENRIQUE','ORTEGA','GOMEZ']), 'ENRIQUE');
ok('MONTOYA gana a MARCO', m.tokenGuia(['MARCO','MONTOYA']), 'MONTOYA');
ok('una sola', m.tokenGuia(['ORTEGA']), 'ORTEGA');

console.log('\nempataNombre: el cruce que antes fallaba');
const enrique = { nombre:'ENRIQUE', paterno:'ORTEGA', materno:'GOMEZ' };
const roberto = { nombre:'ROBERTO', paterno:'GARCIA', materno:null };
ok('el caso reportado', m.empataNombre(enrique, ['Enrique','Ortega','Gomez']), true);
ok('en cualquier orden', m.empataNombre(enrique, ['Gomez','Enrique','Ortega']), true);
ok('minusculas', m.empataNombre(enrique, ['enrique','ortega']), true);
ok('falta una palabra -> no empata', m.empataNombre(enrique, ['Enrique','Ortega','Perez']), false);
ok('apellido materno nulo no revienta', m.empataNombre(roberto, ['Roberto','Garcia']), true);
ok('materno nulo no empata de a gratis', m.empataNombre(roberto, ['Roberto','Gomez']), false);
ok('sin tokens empata con todo (no se usa asi)', m.empataNombre(enrique, []), true);

console.log('\nempataNombreAproximado: dedazos SI, personas distintas NO');
// Reportado al probar: "hector figeroa" no encontraba a nadie, y HECTOR FIGUEROA existe.
const hector = { nombre: 'HECTOR', paterno: 'FIGUEROA', materno: 'RAMIREZ' };
const ortega = { nombre: 'ENRIQUE', paterno: 'ORTEGA', materno: 'GOMEZ' };
ok('el caso reportado: "hector figeroa"',
   m.empataNombreAproximado(hector, ['hector', 'figeroa']));
ok('una letra cambiada: "gomes" por GOMEZ',
   m.empataNombreAproximado(ortega, ['enrique', 'gomes']));
ok('una letra de mas: "enrrique"',
   m.empataNombreAproximado(ortega, ['enrrique', 'ortega']));
ok('acento y dedazo a la vez: "Goméz"',
   m.empataNombreAproximado(ortega, ['Goméz']));
ok('compara palabra por palabra, no el campo entero',
   m.empataNombreAproximado(
     { nombre: 'JOSE LUIS', paterno: 'GARCIA HERNANDEZ', materno: null }, ['garcia']));
ok('otra persona NO empata', !m.empataNombreAproximado(hector, ['hector', 'martinez']));
ok('tres letras exigen exactitud: ANA no es ANO',
   !m.empataNombreAproximado({ nombre: 'ANA', paterno: 'LOPEZ', materno: null }, ['ano']));
ok('dos letras cambiadas en palabra corta NO empatan',
   !m.empataNombreAproximado(hector, ['hictar']));
ok('materno nulo no revienta', m.empataNombreAproximado(
   { nombre: 'ROBERTO', paterno: 'GARCIA', materno: null }, ['roberto', 'garcia']));

console.log('\ndistancia y tolerancia');
ok('figeroa -> figueroa es 1', m.distancia('FIGEROA', 'FIGUEROA') === 1);
ok('iguales es 0', m.distancia('GOMEZ', 'GOMEZ') === 0);
ok('menos de 4 letras no admite fallos', m.tolerancia('ANA') === 0);
ok('de 4 a 7 admite una', m.tolerancia('HECTOR') === 1);
ok('de 8 en adelante admite dos', m.tolerancia('FIGUEROA') === 2);

console.log('\nfiltroPrefijos: el prefiltro de la pasada tolerante');
const f3 = m.filtroPrefijos(['hector', 'figeroa']);
console.log(`  -> ${f3}`);
ok('lleva las tres primeras letras de cada palabra',
   f3.includes('nombre.ilike.hec%') && f3.includes('paterno.ilike.fig%'));
ok('cubre los tres campos por palabra', (f3.match(/ilike/g) || []).length === 6);
ok('una palabra de menos de tres letras se ignora',
   !m.filtroPrefijos(['de']).includes('ilike'));

console.log('\njefeAlQueSeRefiere: sale del perfil, no se le pregunta a la persona');
const perfil = {
  jefe_inmediato: 'MARCO ANTONIO MONTOYA LOPEZ',
  director: 'ALGUIEN MAS',
  gerente_regional: '',
};
ok('«las vacaciones de mi jefe»',
   m.jefeAlQueSeRefiere('cuales son las vacaciones de mi jefe', perfil)
     === 'MARCO ANTONIO MONTOYA LOPEZ');
ok('«vacaciones de mi director»',
   m.jefeAlQueSeRefiere('vacaciones de mi director', perfil) === 'ALGUIEN MAS');
ok('un campo vacio en el perfil devuelve null',
   m.jefeAlQueSeRefiere('vacaciones de mi gerente', perfil) === null);
ok('sin campo en el perfil devuelve null',
   m.jefeAlQueSeRefiere('vacaciones de mi jefe', {}) === null);
ok('«quien es mi jefe» NO es de vacaciones: lo contesta el modelo',
   m.jefeAlQueSeRefiere('quien es mi jefe', perfil) === null);
ok('«mis vacaciones» no es del jefe',
   m.jefeAlQueSeRefiere('cuales son mis vacaciones', perfil) === null);

console.log(fallos === 0 ? '\nTODO BIEN' : `\n${fallos} FALLAS`);
process.exit(fallos === 0 ? 0 : 1);
