// Ejercita el que convierte «septiembre» o «esta semana» en dos fechas.
//
//   node --experimental-strip-types supabase/functions/ai-assistant/verificar_rango.mjs
//
// ─── Por que se prueba con un «hoy» fijo ─────────────────────────────────────
//
// Porque si no, la prueba cambia de resultado sola: «esta semana» depende del dia en que se corra y
// «enero» del mes. Una prueba que pasa hoy y falla el martes no dice nada de la funcion.
//
// El «hoy» de referencia es el LUNES 21 de septiembre de 2026, para que se vea el caso mas facil de
// equivocar: la semana que empieza justo hoy.
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { leer } from './leer.mjs';

const aqui = dirname(fileURLToPath(import.meta.url));

// Se copian los DOS modulos con su nombre, para que el `import './nombres.ts'` de rango.ts resuelva
// solo. Extraer la funcion a mano seria copiar `sinAcentos` a la prueba, y entonces la prueba
// verificaria su propia copia.
const destino = mkdtempSync(join(tmpdir(), 'rango_'));
for (const f of ['nombres.ts', 'rango.ts', 'respuestas.ts']) {
  writeFileSync(join(destino, f), leer(join(aqui, f)), 'utf8');
}
const { rangoDeFechas } = await import(
  `file://${join(destino, 'rango.ts').replace(/\\/g, '/')}`
);
// `preguntaQuienSeVa` llama a `rangoDeFechas`, asi que se prueba con el modulo de verdad detras y
// no con una copia: si un dia el rango deja de calcularse igual, estas pruebas lo notan tambien.
const { preguntaQuienSeVa, textoQuienSeVa } = await import(
  `file://${join(destino, 'respuestas.ts').replace(/\\/g, '/')}`
);

const HOY = new Date(2026, 8, 21); // lunes 21 de septiembre de 2026

let fallos = 0;
function ok(titulo, cond, detalle) {
  if (cond) return;
  fallos++;
  console.log(`  FALLA  ${titulo}`);
  if (detalle) console.log(`         ${detalle}`);
}

function igual(texto, desde, hasta, etiqueta) {
  const r = rangoDeFechas(texto, HOY);
  if (!r) {
    fallos++;
    console.log(`  FALLA  "${texto}" no devolvio nada`);
    return;
  }
  const bien = r.desde === desde && r.hasta === hasta
    && (etiqueta === undefined || r.etiqueta === etiqueta);
  ok(`"${texto}" -> ${desde} .. ${hasta}`, bien,
    `devolvio ${r.desde} .. ${r.hasta} (${r.etiqueta})`);
}

console.log('meses');
igual('quien se va de vacaciones en septiembre', '2026-09-01', '2026-09-30', 'septiembre de 2026');
igual('vacaciones de octubre', '2026-10-01', '2026-10-31');
// Febrero ya paso, asi que se entiende el del año que viene. Y 2027 no es bisiesto: 28 dias.
igual('quien sale en febrero', '2027-02-01', '2027-02-28');
// Con el año escrito, manda el año escrito aunque ya haya pasado.
igual('vacaciones de febrero de 2026', '2026-02-01', '2026-02-28');
// 2028 SI es bisiesto: si esto sale 28, el ultimo dia del mes esta mal calculado.
igual('febrero de 2028', '2028-02-01', '2028-02-29');
igual('este mes', '2026-09-01', '2026-09-30');
igual('el proximo mes', '2026-10-01', '2026-10-31');

console.log('semanas');
igual('quien se va de vacaciones esta semana', '2026-09-21', '2026-09-27', 'esta semana');
igual('quien sale la proxima semana', '2026-09-28', '2026-10-04', 'la proxima semana');
igual('la semana que viene', '2026-09-28', '2026-10-04');
// El domingo pertenece a la semana que EMPEZO el lunes anterior, no a la que empieza al dia
// siguiente. Es el caso que se equivoca solo si la semana se cuenta desde el domingo.
ok('el domingo cae en la semana que empezo el lunes anterior',
  rangoDeFechas('esta semana', new Date(2026, 8, 27)).desde === '2026-09-21',
  `devolvio ${rangoDeFechas('esta semana', new Date(2026, 8, 27)).desde}`);

console.log('quincenas');
igual('primera quincena de octubre', '2026-10-01', '2026-10-15');
igual('la segunda quincena de octubre', '2026-10-16', '2026-10-31');
// Sin mes, la del mes en curso. Y en febrero la segunda quincena NO termina en 30.
igual('segunda quincena', '2026-09-16', '2026-09-30');
igual('segunda quincena de febrero de 2026', '2026-02-16', '2026-02-28');

console.log('tramos y dias sueltos');
igual('del 5 al 12 de octubre', '2026-10-05', '2026-10-12');
// Al reves tambien: se ordena, no se devuelve un rango vacio.
igual('del 12 al 5 de octubre', '2026-10-05', '2026-10-12');
igual('quien se va del 1 al 15', '2026-09-01', '2026-09-15');
igual('hoy', '2026-09-21', '2026-09-21');
igual('manana', '2026-09-22', '2026-09-22');
igual('del 2026-11-02 al 2026-11-09', '2026-11-02', '2026-11-09');
igual('el 2026-12-25', '2026-12-25', '2026-12-25');

console.log('lo mas especifico gana');
// Las tres frases contienen «octubre»; si el orden de las comprobaciones se altera, estas fallan.
igual('la segunda quincena de octubre', '2026-10-16', '2026-10-31');
igual('del 3 al 8 de octubre', '2026-10-03', '2026-10-08');

console.log('cuando no dice ninguna fecha');
for (const t of ['quien se va de vacaciones', 'cuantos dias tengo', 'hola', '']) {
  ok(`"${t}" no inventa un rango`, rangoDeFechas(t, HOY) === null,
    'sin fecha en la pregunta es mejor preguntar que suponer');
}
// «marzo» dentro de una palabra no es el mes. Sin el limite de palabra, este apellido lo activaba.
ok('un apellido que contiene un mes no cuenta',
  rangoDeFechas('vacaciones de marzoquin', HOY) === null,
  'devolvio un rango de marzo por una coincidencia dentro de la palabra');

// ─── La pregunta que lo origino ─────────────────────────────────────────────
//
// «quien se va de vacaciones en septiembre o en esta semana». No se podia contestar porque
// `buscar_incidencias` no tenia filtro por fechas: el dato no se podia ni pedir.
console.log('\nquien se va de vacaciones');

for (const [t, desde, hasta] of [
  ['quien se va de vacaciones en septiembre', '2026-09-01', '2026-09-30'],
  ['quien se va de vacaciones esta semana', '2026-09-21', '2026-09-27'],
  ['quienes salen de vacaciones la proxima semana', '2026-09-28', '2026-10-04'],
  ['que personas tienen vacaciones en octubre', '2026-10-01', '2026-10-31'],
  ['lista de vacaciones de la segunda quincena de octubre', '2026-10-16', '2026-10-31'],
  ['quien esta de vacaciones hoy', '2026-09-21', '2026-09-21'],
]) {
  const r = preguntaQuienSeVa(t, HOY);
  ok(`la atiende: "${t}"`, r !== null && r.desde === desde && r.hasta === hasta,
    r ? `devolvio ${r.desde} .. ${r.hasta}` : 'devolvio null');
}

for (const t of [
  // Sin fechas no hay lista: es otra pregunta.
  'quien puede autorizar mis vacaciones',
  'quien es mi jefe',
  // Esta tiene su propia via -el saldo propio- y no habla de QUIEN.
  'cuantos dias de vacaciones tengo',
  'que periodos tengo disponibles en septiembre',
  // Habla de cumpleaños, que es otra herramienta y otra lista.
  'quien cumple anos en septiembre',
  // «lista» de adjetivo, no de listado. Lleva vacaciones y lleva fecha, asi que sin el «de» que se
  // exige despues, esta se colaria y devolveria la lista de toda la empresa.
  'ya esta lista mi solicitud de vacaciones de septiembre',
]) {
  ok(`la deja pasar: "${t}"`, preguntaQuienSeVa(t, HOY) === null,
    'se la esta quedando una via que no le toca');
}

// ─── El texto sale de los datos ─────────────────────────────────────────────
console.log('\nel listado se escribe desde las filas');

const rango = rangoDeFechas('septiembre', HOY);
const salida = textoQuienSeVa(rango, [
  { nombre_usuario: 'ANA LOPEZ', fecha_inicio: '2026-09-02', fecha_fin: '2026-09-04',
    dias: 3, status: 'APROBADA' },
  { nombre_usuario: 'ANA LOPEZ', fecha_inicio: '2026-09-20', fecha_fin: '2026-09-20',
    dias: 1, status: 'APROBADA' },
  { nombre_usuario: 'BETO RUIZ', fecha_inicio: '2026-09-10', fecha_fin: '2026-09-14',
    dias: 5, status: 'PENDIENTE' },
]);
console.log('  ->', salida.replace(/\n/g, ' | '));

ok('dice el rango en palabras', salida.includes('septiembre de 2026'));
ok('cuenta PERSONAS, no solicitudes', salida.includes('2 personas'),
  'Ana sale dos veces: si cuenta 3, esta contando solicitudes');
ok('junta los dos tramos de la misma persona',
  /ANA LOPEZ: 02\/09 al 04\/09 \(3 dias\) y 20\/09 al 20\/09 \(1 dia\)/.test(salida));
ok('marca la que NO esta aprobada', salida.includes('[PENDIENTE]'),
  'una pendiente colada entre aprobadas cambia lo que se puede planear');
ok('y no ensucia las aprobadas', !salida.includes('[APROBADA]'));
ok('singular y plural de dia', salida.includes('(1 dia)') && salida.includes('(3 dias)'));

const vacio = textoQuienSeVa(rango, []);
ok('sin nadie lo dice claro', /Nadie tiene vacaciones registradas en septiembre de 2026/.test(vacio),
  'una lista vacia sin explicacion se lee como un fallo');

console.log('');
if (fallos > 0) {
  console.log(`${fallos} FALLAS`);
  process.exit(1);
}
console.log('TODO BIEN');
