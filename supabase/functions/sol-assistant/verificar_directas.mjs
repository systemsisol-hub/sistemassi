// Ejercita los reconocedores de SOL: la via directa de ubicacion y el filtro de botones.
//
//   node --experimental-strip-types supabase/functions/sol-assistant/verificar_directas.mjs
//
// Se EXTRAEN del directas.ts real en lugar de copiarlas, para que la prueba no pueda quedar
// verificando una version vieja de la logica. Es el mismo patron que los cuatro arneses de Soli, y
// existe por la misma razon: los reconocedores de Soli tenian cuatro fallos reales que nadie vio
// hasta que un arnes los ejercito.
//
// El caso que le dio origen: el 03/09/2026 SOL contesto «AG117 se encuentra en CDMX» teniendo la
// direccion completa capturada, y doce minutos antes «AG117 se ubica en Tulum», que es otro
// desarrollo.
import { writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { leer } from '../ai-assistant/leer.mjs';

const aqui = dirname(fileURLToPath(import.meta.url));
const src = leer(join(aqui, 'directas.ts'));

const destino = join(tmpdir(), `sol_directas_${Date.now()}.ts`);
writeFileSync(destino, src, 'utf8');
const M = await import(`file://${destino.replace(/\\/g, '/')}`);

const NOMBRES = ['AG117', 'BONANZA COTO 3 - JADE', 'BONANZA COTO 4 - ÁGATA', 'KOOX', 'OLYMPIA',
  'PUNTA PACÍFICO', 'SELVA NORTE', 'VIDAMAR', 'ZÉNESIS', 'ZÉNESIS CLUB'];

let fallos = 0;
function comprobar(titulo, real, esperado) {
  const iguales = JSON.stringify(real) === JSON.stringify(esperado);
  if (!iguales) {
    fallos++;
    console.log(`  FALLA  ${titulo}`);
    console.log(`         esperado ${JSON.stringify(esperado)}, obtuve ${JSON.stringify(real)}`);
  }
}

// ── preguntaUbicacion ───────────────────────────────────────────────────────
console.log('preguntaUbicacion');
for (const q of [
  'cual es su ubicacion?',
  'cual es su direccion?',
  'cual es su direccion o su ubicacion?',
  '¿dónde está AG117?',
  'donde queda',
  'en que colonia esta',
  'me das el domicilio',
  'cual es el codigo postal',
  'donde se ubica ZÉNESIS CLUB',
]) {
  comprobar(`SI: «${q}»`, M.preguntaUbicacion(q, NOMBRES), true);
}
for (const q of [
  'de cuanto es el enganche?',
  'cuantas unidades hay disponibles',
  'dame el brochure',
  'cuales son las amenidades',
  // Estas nombran una UNIDAD: «donde esta» se refiere al departamento, no al desarrollo.
  'donde esta el AG008',
  'en que nivel esta la A-103',
  'ubicacion de la unidad AG035',
]) {
  comprobar(`NO: «${q}»`, M.preguntaUbicacion(q, NOMBRES), false);
}

// El nombre del desarrollo NO debe confundirse con una unidad, aunque tenga la misma forma.
comprobar('AG117 es desarrollo, no unidad',
  M.preguntaUbicacion('cual es la ubicacion de AG117', NOMBRES), true);
// Y sin catalogo, AG117 se ve igual que una unidad: por eso la funcion recibe los nombres.
comprobar('sin catalogo no puede distinguir',
  M.preguntaUbicacion('cual es la ubicacion de AG117', []), false);

// ── desarrolloEnTexto ───────────────────────────────────────────────────────
console.log('desarrolloEnTexto');
comprobar('exacto', M.desarrolloEnTexto('que sabes de AG117', NOMBRES), 'AG117');
comprobar('sin acentos en la pregunta',
  M.desarrolloEnTexto('cuentame de zenesis club', NOMBRES), 'ZÉNESIS CLUB');
comprobar('gana el nombre MAS LARGO',
  M.desarrolloEnTexto('zenesis club', NOMBRES), 'ZÉNESIS CLUB');
comprobar('el corto sigue funcionando solo',
  M.desarrolloEnTexto('precios de zenesis', NOMBRES), 'ZÉNESIS');
comprobar('ninguno', M.desarrolloEnTexto('cuanto cuesta un cafe', NOMBRES), null);

// ── desarrolloDelHilo ───────────────────────────────────────────────────────
console.log('desarrolloDelHilo');
comprobar('lo toma de un mensaje anterior', M.desarrolloDelHilo([
  { role: 'user', content: 'cuales son las amenidades de AG117?' },
  { role: 'assistant', content: 'Gimnasio, lobby...' },
  { role: 'user', content: 'cual es su ubicacion?' },
], NOMBRES), 'AG117');

comprobar('gana el MAS RECIENTE', M.desarrolloDelHilo([
  { role: 'user', content: 'precios de AG117' },
  { role: 'assistant', content: 'desde...' },
  { role: 'user', content: 'y de KOOX?' },
  { role: 'assistant', content: 'no capturado' },
  { role: 'user', content: 'cual es su ubicacion?' },
], NOMBRES), 'KOOX');

comprobar('hilo sin ningun desarrollo', M.desarrolloDelHilo([
  { role: 'user', content: 'hola' },
], NOMBRES), null);

// ── documentoMencionado ────────────────────────────────────────────────────
console.log('documentoMencionado');
const listaEsp = { nombre: 'Lista de precios en español', categoria: 'Listas de precios' };
const brochure = { nombre: 'Brochure ESP', categoria: 'Brochure' };

comprobar('la respuesta que SI la nombra',
  M.documentoMencionado(
    'AG117 tiene 26 mensualidades. El monto exacto no está capturado, pero puedes consultarlo '
    + 'en la Lista de precios en español.', listaEsp), true);

comprobar('la respuesta del enganche NO nombra ningun documento',
  M.documentoMencionado('El enganche de AG117 es del 10%.', listaEsp), false);
comprobar('ni el brochure',
  M.documentoMencionado('El enganche de AG117 es del 10%.', brochure), false);

comprobar('empata por la CATEGORIA cuando no dice el nombre completo',
  M.documentoMencionado('te dejo las listas de precios', listaEsp), true);
comprobar('tolera el singular',
  M.documentoMencionado('revisa la lista de precios', listaEsp), true);
comprobar('acentos y mayusculas dan igual',
  M.documentoMencionado('Consulta el BROCHURE del proyecto', brochure), true);
comprobar('un documento distinto al nombrado NO sale',
  M.documentoMencionado('te dejo el brochure', listaEsp), false);
comprobar('documento sin nombre ni categoria', M.documentoMencionado('lo que sea', {}), false);

// ── textoUbicacion ─────────────────────────────────────────────────────────
console.log('textoUbicacion');
comprobar('cita el campo COMPLETO, sin recortar',
  M.textoUbicacion('AG117', 'Abraham González 117, Colonia Juárez, alcaldía Cuahutemoc, 06600, CDMX',
    'PREVENTA'),
  'AG117 está en Abraham González 117, Colonia Juárez, alcaldía Cuahutemoc, 06600, CDMX.'
  + '\n\nEtapa: PREVENTA.');
comprobar('sin etapa', M.textoUbicacion('KOOX', 'Puerto Morelos'), 'KOOX está en Puerto Morelos.');
comprobar('no duplica el punto final',
  M.textoUbicacion('KOOX', 'Puerto Morelos.'), 'KOOX está en Puerto Morelos.');

console.log('');
if (fallos > 0) {
  console.log(`${fallos} FALLAS`);
  process.exit(1);
}
console.log('TODO BIEN');
