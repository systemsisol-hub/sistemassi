// Ejercita las reglas de extras: quien califica para bodega, estacionamiento y roof.
//
//   node --experimental-strip-types supabase/functions/sol-assistant/verificar_extras.mjs
//
// Se EXTRAE de extras.ts en lugar de copiarlo, para que la prueba no pueda quedar verificando una
// version vieja de la logica. Mismo patron que los otros arneses.
//
// Por que hay arnes para esto: es una comparacion numerica contra un umbral, y equivocarse
// significa prometerle una bodega a un cliente que no puede comprarla. Eso se descubre en la firma.
import { writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { leer } from '../ai-assistant/leer.mjs';

const aqui = dirname(fileURLToPath(import.meta.url));
const src = leer(join(aqui, 'extras.ts'));
const destino = join(tmpdir(), `sol_extras_${Date.now()}.ts`);
writeFileSync(destino, src, 'utf8');
const M = await import(`file://${destino.replace(/\\/g, '/')}`);

// Las TRES reglas de AG117, tal como quedan en la base.
const REGLAS = [
  { extra: 'ROOF', requiere_departamento: true, precio_minimo_departamento: null,
    minimo_inclusivo: false },
  { extra: 'BODEGA', requiere_departamento: true, precio_minimo_departamento: 8000000,
    minimo_inclusivo: false },
  { extra: 'ESTACIONAMIENTO', requiere_departamento: true, precio_minimo_departamento: 7000000,
    minimo_inclusivo: false },
];

let fallos = 0;
function comprobar(titulo, real, esperado) {
  if (JSON.stringify(real) !== JSON.stringify(esperado)) {
    fallos++;
    console.log(`  FALLA  ${titulo}`);
    console.log(`         esperado ${JSON.stringify(esperado)}, obtuve ${JSON.stringify(real)}`);
  }
}

const cal = (u) => M.extrasQueCalifica(u, REGLAS).sort();

// ── esDepartamento ──────────────────────────────────────────────────────────
console.log('esDepartamento');
for (const t of ['Depto', 'DEPTO', 'depto', 'Departamento', 'DEPTO.', 'Depa']) {
  comprobar(`SI: «${t}»`, M.esDepartamento(t), true);
}
for (const t of ['ROOF', 'Roof', 'Lote', 'Casa', 'Local', '', null, undefined]) {
  comprobar(`NO: «${t}»`, M.esDepartamento(t), false);
}

// ── Los tres tramos de precio ───────────────────────────────────────────────
console.log('los tramos de precio');
comprobar('depto de 9,310,000: los tres',
  cal({ tipo: 'Depto', precio: 9310000 }),
  ['BODEGA', 'ESTACIONAMIENTO', 'ROOF']);

comprobar('depto de 7,460,000: roof y estacionamiento, NO bodega',
  cal({ tipo: 'Depto', precio: 7460000 }),
  ['ESTACIONAMIENTO', 'ROOF']);

comprobar('depto de 4,950,000: solo roof',
  cal({ tipo: 'Depto', precio: 4950000 }),
  ['ROOF']);

// ── El borde exacto, que es de lo que se trata ─────────────────────────────
console.log('el borde exacto');
comprobar('EXACTAMENTE 8,000,000 no da bodega («arriba de»)',
  cal({ tipo: 'Depto', precio: 8000000 }),
  ['ESTACIONAMIENTO', 'ROOF']);
comprobar('8,000,001 SI da bodega',
  cal({ tipo: 'Depto', precio: 8000001 }),
  ['BODEGA', 'ESTACIONAMIENTO', 'ROOF']);
comprobar('EXACTAMENTE 7,000,000 no da estacionamiento',
  cal({ tipo: 'Depto', precio: 7000000 }), ['ROOF']);
comprobar('7,000,001 SI da estacionamiento',
  cal({ tipo: 'Depto', precio: 7000001 }), ['ESTACIONAMIENTO', 'ROOF']);

// Y que la columna `minimo_inclusivo` de verdad cambia el borde: es su unica razon de ser.
const inclusivas = REGLAS.map((r) => ({ ...r, minimo_inclusivo: true }));
comprobar('con minimo_inclusivo, 8,000,000 SI da bodega',
  M.extrasQueCalifica({ tipo: 'Depto', precio: 8000000 }, inclusivas).sort(),
  ['BODEGA', 'ESTACIONAMIENTO', 'ROOF']);

// ── Ningun extra sin departamento ──────────────────────────────────────────
console.log('ningun extra sin departamento');
comprobar('un ROOF no da derecho a nada, aunque sea caro',
  cal({ tipo: 'ROOF', precio: 99000000 }), []);
comprobar('un lote tampoco', cal({ tipo: 'Lote', precio: 9000000 }), []);
comprobar('sin tipo tampoco', cal({ precio: 9000000 }), []);

// ── Sin precio no se dice que si ───────────────────────────────────────────
console.log('sin precio');
comprobar('depto sin precio: solo lo que no pide minimo',
  cal({ tipo: 'Depto' }), ['ROOF']);
comprobar('depto con precio ilegible: igual',
  cal({ tipo: 'Depto', precio: 'n/a' }), ['ROOF']);

// ── reglaDelExtra: la unidad que ES un extra ───────────────────────────────
//
// El caso que fallo en produccion el 04/09/2026: preguntado «tengo 2 millones, que puedo comprar»,
// SOL listo los cuatro ROOF -1.76 a 1.77 millones- como si se pudieran comprar sueltos. La
// condicion de venta no viajaba con la unidad porque nada contestaba «esta unidad ES un extra».
console.log('reglaDelExtra');
comprobar('un ROOF cae bajo la regla ROOF',
  M.reglaDelExtra('ROOF', REGLAS)?.extra, 'ROOF');
comprobar('sin importar mayusculas ni espacios',
  M.reglaDelExtra(' roof ', REGLAS)?.extra, 'ROOF');
comprobar('una Bodega cae bajo BODEGA',
  M.reglaDelExtra('Bodega', REGLAS)?.extra, 'BODEGA');
comprobar('un Estacionamiento tambien',
  M.reglaDelExtra('Estacionamiento', REGLAS)?.extra, 'ESTACIONAMIENTO');

comprobar('un DEPTO no es un extra', M.reglaDelExtra('Depto', REGLAS), null);
comprobar('ni un Lote', M.reglaDelExtra('Lote', REGLAS), null);
comprobar('sin tipo, null', M.reglaDelExtra(null, REGLAS), null);
comprobar('vacio, null', M.reglaDelExtra('   ', REGLAS), null);
comprobar('sin reglas, null', M.reglaDelExtra('ROOF', []), null);

// Las dos preguntas son DISTINTAS y no hay que confundirlas: una es «a que da derecho» y la otra
// «que es». Un roof no da derecho a nada Y ademas es un extra.
const roof = { tipo: 'ROOF', precio: 1770000 };
comprobar('un roof no da derecho a nada', cal(roof), []);
comprobar('...y ademas ES un extra', M.reglaDelExtra(roof.tipo, REGLAS)?.extra, 'ROOF');

comprobar('su condicion de venta lo dice',
  M.reglaEnPalabras(M.reglaDelExtra('ROOF', REGLAS)),
  'El roof NO se puede comprar solo: hace falta comprar un departamento sin importar el precio '
  + 'del departamento.');

// ── calificaPara ───────────────────────────────────────────────────────────
console.log('calificaPara');
const caro = { tipo: 'Depto', precio: 9310000 };
const barato = { tipo: 'Depto', precio: 4950000 };
comprobar('caro para BODEGA', M.calificaPara(caro, 'BODEGA', REGLAS), true);
comprobar('barato para BODEGA', M.calificaPara(barato, 'BODEGA', REGLAS), false);
comprobar('barato para ROOF', M.calificaPara(barato, 'ROOF', REGLAS), true);
comprobar('en minusculas empata igual', M.calificaPara(caro, 'bodega', REGLAS), true);
comprobar('con espacios empata igual', M.calificaPara(caro, ' Bodega ', REGLAS), true);
comprobar('un extra que no existe', M.calificaPara(caro, 'JAULA', REGLAS), false);

// ── La regla en palabras ───────────────────────────────────────────────────
console.log('reglaEnPalabras');
comprobar('bodega', M.reglaEnPalabras(REGLAS[1]),
  'El bodega NO se puede comprar solo: hace falta comprar un departamento y ese departamento '
  + 'tiene que costar MAS de $8,000,000.');
comprobar('roof, sin minimo', M.reglaEnPalabras(REGLAS[0]),
  'El roof NO se puede comprar solo: hace falta comprar un departamento sin importar el precio '
  + 'del departamento.');
comprobar('inclusiva dice «o mas»', M.reglaEnPalabras(inclusivas[1]),
  'El bodega NO se puede comprar solo: hace falta comprar un departamento y ese departamento '
  + 'tiene que costar $8,000,000 o mas.');
comprobar('una que no exige departamento',
  M.reglaEnPalabras({ extra: 'JAULA', requiere_departamento: false,
    precio_minimo_departamento: null, minimo_inclusivo: false }),
  'El jaula se puede comprar sin departamento.');

console.log('');
if (fallos > 0) {
  console.log(`${fallos} FALLAS`);
  process.exit(1);
}
console.log('TODO BIEN');
