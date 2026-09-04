// Ejercita el PROMPT de SOL.
//
//   node --experimental-strip-types supabase/functions/sol-assistant/verificar_prompt.mjs
//
// ─── Por que el prompt necesita arnes ───────────────────────────────────────
//
// Porque de ahi han salido tres fallos, y ninguno se veia leyendo el archivo:
//
//   1. Backticks dentro de la plantilla de texto, que la CIERRAN. Rompio el despliegue dos veces.
//   2. Un ejemplo viejo -«Ej. CDMX, Tulum»- que el modelo repitio como si Tulum siguiera
//      existiendo, doce horas despues de borrar ese desarrollo.
//   3. Que no dijera cuantos desarrollos hay, asi que preguntaba «de que desarrollo?» habiendo uno
//      solo.
//
// Los tres son de la clase que una prueba atrapa y una lectura no.
import { writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { leer } from '../ai-assistant/leer.mjs';

const aqui = dirname(fileURLToPath(import.meta.url));
const src = leer(join(aqui, 'herramientas.ts'));
const destino = join(tmpdir(), `sol_prompt_${Date.now()}.ts`);
writeFileSync(destino, src, 'utf8');
const M = await import(`file://${destino.replace(/\\/g, '/')}`);

let fallos = 0;
function comprobar(titulo, ok, detalle) {
  if (!ok) {
    fallos++;
    console.log(`  FALLA  ${titulo}`);
    if (detalle) console.log(`         ${detalle}`);
  }
}

// ── El catalogo, que es lo que fallo ────────────────────────────────────────
console.log('el catalogo en el prompt');

const uno = M.construirPrompt('Ave', '4 de septiembre de 2026', ['AG117']);
comprobar('con UN desarrollo, lo nombra', uno.includes('AG117'));
comprobar('y prohibe preguntar cual', uno.includes('NUNCA preguntes de que desarrollo'));
comprobar('y prohibe mencionar otros', uno.includes('no menciones otros desarrollos'));

const tres = M.construirPrompt('Ave', 'hoy', ['AG117', 'KOOX', 'VIDAMAR']);
comprobar('con TRES, los lista', ['AG117', 'KOOX', 'VIDAMAR'].every((d) => tres.includes(d)));
comprobar('dice cuantos son', tres.includes('TIENE 3 DESARROLLOS'));
comprobar('con varios SI puede preguntar cual', tres.includes('pregunta cual'));
comprobar('con varios NO lleva la prohibicion de preguntar',
  !tres.includes('NUNCA preguntes de que desarrollo'));

const cero = M.construirPrompt('Ave', 'hoy', []);
comprobar('sin desarrollos lo dice', cero.includes('NO HAY NINGUN DESARROLLO CARGADO'));
comprobar('y no inventa nombres', !cero.includes('AG117'));

// La razon de ser de todo esto: el nombre sale del DATO, no escrito a mano. Si algun dia se
// escribe fijo, este caso lo delata.
const otro = M.construirPrompt('Ave', 'hoy', ['DESARROLLO NUEVO']);
comprobar('el nombre viene del dato, no fijo en el codigo',
  otro.includes('DESARROLLO NUEVO') && !otro.includes('AG117'),
  'el prompt trae AG117 escrito a mano en alguna parte');

// ── Los backticks, que rompieron el despliegue dos veces ───────────────────
console.log('backticks');
for (const [titulo, p] of [['uno', uno], ['tres', tres], ['cero', cero]]) {
  const n = (p.match(/`/g) ?? []).length;
  comprobar(`el prompto con ${titulo} desarrollo(s) no lleva backticks`, n === 0,
    `lleva ${n}`);
}

// ── Ejemplos que ya no existen ─────────────────────────────────────────────
//
// Ninguna ciudad ni desarrollo escritos a mano en el prompt ni en las herramientas: eso es lo que
// hizo que el modelo ofreciera Tulum despues de borrarlo.
console.log('nada viejo escrito a mano');
const catalogo = JSON.stringify(M.ALL_TOOLS);
for (const viejo of ['Tulum', 'Playa del Carmen', 'Acapulco', 'Ensenada', 'Puerto Morelos',
  'KOOX', 'VIDAMAR', 'ZENESIS', 'OLYMPIA', 'BONANZA']) {
  comprobar(`«${viejo}» no aparece en las herramientas`, !catalogo.includes(viejo));
  comprobar(`«${viejo}» no aparece en el prompt`, !uno.includes(viejo));
}

// ── Que el prompt siga diciendo lo que no se puede perder ──────────────────
console.log('las reglas que no se pueden perder');
for (const regla of [
  'NUNCA escribas una cifra que no venga de una herramienta',
  'LOS CAMPOS DE TEXTO SE CITAN COMPLETOS',
  'CADA DATO ES DEL DESARROLLO QUE LO TRAE',
  'LOS PRECIOS SE COPIAN',
  'NO dibujes tablas de unidades',
  'NINGUN extra se puede comprar sin departamento',
  'UNA UNIDAD PUEDE SER, ELLA MISMA, UN EXTRA',
  'ENTREGA SIEMPRE el enlace',
  'NUNCA nombres los campos con los que te llegan los datos',
]) {
  comprobar(`sigue diciendo «${regla}»`, uno.includes(regla));
}

console.log('');
if (fallos > 0) {
  console.log(`${fallos} FALLAS`);
  process.exit(1);
}
console.log('TODO BIEN');
