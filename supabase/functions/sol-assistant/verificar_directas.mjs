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

// ── mencionaUbicacion: el filtro previo NO puede bloquear lo que el otro dejaria pasar ──────
//
// Es el error que se colo a produccion el 03/09/2026: `index.ts` usaba `preguntaUbicacion` con la
// lista vacia como filtro previo, asi que «la ubicacion de AG117» se descartaba antes de consultar
// el catalogo y la via directa nunca corria. Esta comprobacion es la que lo habria atrapado.
console.log('mencionaUbicacion (filtro previo)');
for (const q of [
  'me puedes dar la ubicacion de AG117',
  'cual es la direccion de AG117?',
  'donde esta el AG008',
  'ubicacion de la unidad AG035',
  'donde queda',
]) {
  comprobar(`deja pasar: «${q}»`, M.mencionaUbicacion(q), true);
}
for (const q of ['de cuanto es el enganche?', 'dame el brochure', 'cuantas hay disponibles']) {
  comprobar(`descarta: «${q}»`, M.mencionaUbicacion(q), false);
}

// La invariante, dicha como invariante: si `preguntaUbicacion` diria SI, el filtro previo tiene
// que dejarlo pasar. Al reves puede diferir -eso es lo que aporta el catalogo-.
for (const q of [
  'me puedes dar la ubicacion de AG117',
  'cual es su direccion?',
  'donde queda ZÉNESIS CLUB',
  'en que colonia esta',
]) {
  if (M.preguntaUbicacion(q, NOMBRES) && !M.mencionaUbicacion(q)) {
    comprobar(`el filtro previo bloquea «${q}»`, false, true);
  }
}

// ── campoUnico ──────────────────────────────────────────────────────────────
console.log('campoUnico');
const CASOS = [
  ['cual es su ubicacion?', 'ubicacion'],
  ['me das la direccion', 'ubicacion'],
  ['cuales son las amenidades de AG117?', 'amenidades'],
  ['que amenidades tiene', 'amenidades'],
  ['que areas comunes hay', 'amenidades'],
  ['de cuanto es el enganche?', 'enganche'],
  ['el enganche de zenesis', 'enganche'],
  ['cuantas mensualidades son', 'mensualidades'],
  ['a cuantos meses lo dan', 'mensualidades'],
  ['cual es el plazo', 'mensualidades'],
  ['en que etapa esta', 'etapa'],
];
for (const [q, esperado] of CASOS) {
  comprobar(`«${q}» -> ${esperado}`, M.campoUnico(q), esperado);
}

// Lo que NO debe atajar: preguntas de varios campos, y preguntas que no son de un solo campo.
for (const q of [
  // Dos campos: un atajo contestaria solo uno y dejaria el otro sin respuesta.
  'de cuanto es el enganche y cuantas mensualidades?',
  'cual es la ubicacion y en que etapa esta',
  // Ninguno: contesta el modelo, que puede ofrecer documentos.
  'que me puedes decir de AG117',
  'cuantas unidades hay disponibles',
  'dame el brochure',
  'de cuantos pisos es el edificio?',
  // A proposito fuera de amenidades: el modelo dice SI o NO, que es lo que se pregunta.
  'tiene alberca?',
  'que incluye el departamento',
]) {
  comprobar(`sin atajo: «${q}»`, M.campoUnico(q), null);
}

comprobar('los dos campos se listan', M.camposPreguntados('el enganche y el plazo').sort(),
  ['enganche', 'mensualidades']);

// ── Las exclusiones: preguntas por el IMPORTE, que no esta en la base ───────
//
// `mensualidades` guarda 26, un numero de pagos, no un importe. Contestar «se maneja a 26
// mensualidades» a quien pregunta cuanto paga al mes es responder otra cosa. Y el modelo ya lo
// hacia bien: «el monto exacto no esta capturado, consultalo en la Lista de precios».
console.log('exclusiones (preguntas por el importe)');
for (const q of [
  'cuanto es la mensualidad de ag117',
  'de cuanto es la mensualidad?',
  'la mensualidad de cuanto seria',
  'cuanto seria la mensualidad',
  'cual es el monto de la mensualidad',
  'la mensualidad en pesos',
  'cuanto es el enganche en pesos',
  'cual es el monto del enganche',
]) {
  comprobar(`sin atajo: «${q}»`, M.campoUnico(q), null);
}

// Pero el PLURAL sigue atajando: es el numero de pagos, que si esta en la base.
for (const [q, esperado] of [
  ['cuantas mensualidades son', 'mensualidades'],
  ['a cuantos meses lo dan', 'mensualidades'],
  ['cual es el plazo de AG117', 'mensualidades'],
  ['de cuanto es el enganche?', 'enganche'],
]) {
  comprobar(`si ataja: «${q}»`, M.campoUnico(q), esperado);
}

// ── textoDe ────────────────────────────────────────────────────────────────
console.log('textoDe');
const AG117 = {
  ubicacion: 'Abraham González 117, Colonia Juárez, alcaldía Cuahutemoc, 06600, CDMX',
  etapa: 'PREVENTA',
  amenidades: 'Gimnasio, Lobby, Baños, Coworking, Salón de usos múltiples, Áreas comunes, Roof garden compartido.',
  enganche_pct: '10.00',
  mensualidades: 26,
};

comprobar('amenidades enteras, sin resumir',
  M.textoDe('amenidades', 'AG117', AG117),
  'Amenidades de AG117:\n\n'
  + 'Gimnasio, Lobby, Baños, Coworking, Salón de usos múltiples, Áreas comunes, Roof garden compartido.');
comprobar('enganche sin los ceros de relleno',
  M.textoDe('enganche', 'AG117', AG117), 'El enganche de AG117 es del 10%.');
comprobar('mensualidades',
  M.textoDe('mensualidades', 'AG117', AG117), 'AG117 se maneja a 26 mensualidades.');
comprobar('etapa', M.textoDe('etapa', 'AG117', AG117), 'AG117 está en etapa PREVENTA.');

// Un campo sin capturar devuelve null: pasa al modelo, que sabe ofrecer el brochure.
for (const campo of ['ubicacion', 'amenidades', 'enganche', 'mensualidades', 'etapa']) {
  comprobar(`«${campo}» vacio -> null`, M.textoDe(campo, 'KOOX', {}), null);
  comprobar(`«${campo}» en blanco -> null`,
    M.textoDe(campo, 'KOOX', { [campo === 'enganche' ? 'enganche_pct' : campo]: '   ' }), null);
}

// ── numeroBonito ───────────────────────────────────────────────────────────
console.log('numeroBonito');
comprobar('10.00 -> 10', M.numeroBonito('10.00'), '10');
comprobar('7.50 -> 7.5', M.numeroBonito('7.50'), '7.5');
comprobar('26 -> 26', M.numeroBonito(26), '26');
comprobar('12.345 -> 12.35', M.numeroBonito('12.345'), '12.35');
comprobar('basura se devuelve tal cual', M.numeroBonito('n/a'), 'n/a');

// ── dinero ─────────────────────────────────────────────────────────────────
//
// Existe porque el modelo no lo escribe igual dos veces: el 04/09/2026 saco «1 763 100 MXN» con
// espacios en la misma respuesta en que otro precio salio con comas.
console.log('dinero');
comprobar('con moneda', M.dinero(4797270, 'MXN'), '$4,797,270 MXN');
comprobar('sin moneda', M.dinero(4797270), '$4,797,270');
comprobar('los centavos se van', M.dinero('9310000.00', 'MXN'), '$9,310,000 MXN');
comprobar('redondea', M.dinero(30362.47), '$30,362');
comprobar('cifra de tres', M.dinero(500), '$500');
comprobar('cifra de cuatro', M.dinero(1500), '$1,500');
comprobar('siete cifras', M.dinero(1763100), '$1,763,100');
comprobar('ocho cifras', M.dinero(11200000), '$11,200,000');
comprobar('cero', M.dinero(0), '$0');
comprobar('moneda con espacios se limpia', M.dinero(100, '  MXN  '), '$100 MXN');
comprobar('moneda vacia no deja el hueco', M.dinero(100, '   '), '$100');

// Y lo que NO es un numero da null, para que quien lo use pueda decir «no capturado» en lugar de
// pintar «$NaN».
comprobar('null', M.dinero(null), null);
comprobar('vacio', M.dinero(''), null);
comprobar('texto', M.dinero('por definir'), null);
comprobar('indefinido', M.dinero(undefined), null);

// ── La lista de campos sensibles a promociones ─────────────────────────────
console.log('AFECTADOS_POR_PROMOCION');
comprobar('el enganche lo puede cambiar una promocion',
  M.AFECTADOS_POR_PROMOCION.includes('enganche'), true);
comprobar('las mensualidades tambien',
  M.AFECTADOS_POR_PROMOCION.includes('mensualidades'), true);
comprobar('las amenidades NO',
  M.AFECTADOS_POR_PROMOCION.includes('amenidades'), false);
comprobar('la ubicacion NO',
  M.AFECTADOS_POR_PROMOCION.includes('ubicacion'), false);
comprobar('la etapa NO', M.AFECTADOS_POR_PROMOCION.includes('etapa'), false);

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
