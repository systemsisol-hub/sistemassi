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

const modulo = ['sinAcentos', 'tokensDeNombre', 'tokenGuia', 'empataNombre']
  .map(extraer).join('\n\n') + `
export { sinAcentos, tokensDeNombre, tokenGuia, empataNombre };
`;

const tmp = join(tmpdir(), 'ai-assistant-nombres.ts');
writeFileSync(tmp, modulo, 'utf8');
const m = await import('file://' + tmp.replace(/\\/g, '/'));

let fallos = 0;
function ok(desc, real, esperado) {
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

console.log(fallos === 0 ? '\nTODO BIEN' : `\n${fallos} FALLAS`);
process.exit(fallos === 0 ? 0 : 1);
