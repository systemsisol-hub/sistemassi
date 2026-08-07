// Verifica el sistema de permisos del asistente leyendo los mapas del CODIGO REAL.
//
// Las dos funciones se reimplementan aqui (son cinco lineas cada una); lo que se lee del archivo
// son los DATOS, que es donde de verdad viven los errores: un mapa incompleto, una lista blanca
// separada del esquema, un campo peligroso colado.
//
// Correr con:  node supabase/functions/ai-assistant/verificar_permisos.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const RUTA = join(dirname(fileURLToPath(import.meta.url)), 'index.ts');
const src = readFileSync(RUTA, 'utf8');

const bloque = (nombre) => {
  const i = src.indexOf(nombre);
  if (i < 0) throw new Error('no se encontro ' + nombre);
  return src.slice(i, src.indexOf('\n};', i));
};

// ── Datos leidos del codigo ──────────────────────────────────────────────────
const PERMISO = Object.fromEntries(
  [...bloque('const PERMISO_POR_HERRAMIENTA').matchAll(/(\w+):\s*"([a-z_]+)"/g)]
    .map((m) => [m[1], m[2]]));

const ADMIN_ONLY = new Set(
  [...src.slice(src.indexOf('const ADMIN_ONLY_TOOLS'), src.indexOf(']);', src.indexOf('const ADMIN_ONLY_TOOLS')))
    .matchAll(/"(\w+)"/g)].map((m) => m[1]));

const CAMPOS = {};
{
  const b = bloque('const CAMPOS_ESCRITURA');
  for (const m of b.matchAll(/(\w+):\s*new Set\(\[([\s\S]*?)\]\)/g)) {
    CAMPOS[m[1]] = new Set([...m[2].matchAll(/"(\w+)"/g)].map((x) => x[1]));
  }
}

// Herramientas y los campos que declara el esquema de cada una.
const HERRAMIENTAS = {};
{
  const trozos = src.split(/name:\s*"/).slice(1);
  for (const t of trozos) {
    const nombre = t.slice(0, t.indexOf('"'));
    if (!/^[a-z_]+$/.test(nombre)) continue;
    const iProps = t.indexOf('properties:');
    if (iProps < 0) continue;
    const props = t.slice(iProps, t.indexOf('\n      },', iProps));
    HERRAMIENTAS[nombre] = new Set(
      [...props.matchAll(/(\w+):\s*\{\s*type:/g)].map((m) => m[1]));
  }
}

// ── Las dos funciones ────────────────────────────────────────────────────────
const puedeUsar = (nombre, esAdmin, permisos) => {
  if (ADMIN_ONLY.has(nombre) && !esAdmin) return false;
  const req = PERMISO[nombre];
  if (!req) return true;
  return permisos[req] === true;
};

// ── Comprobaciones ───────────────────────────────────────────────────────────
let fallas = 0;
const check = (ok, msg) => {
  if (!ok) { fallas++; console.log('  FALLA  ' + msg); } else { console.log('  ok     ' + msg); }
};

console.log(`Herramientas encontradas: ${Object.keys(HERRAMIENTAS).length}`);
console.log(`Con permiso mapeado: ${Object.keys(PERMISO).length} | solo-admin: ${ADMIN_ONLY.size}`);
console.log();

console.log('1. Toda herramienta tiene permiso, o esta exenta a proposito');
// enviar_notificacion: no corresponde a ninguna pagina.
// buscar_colaborador: consulta de directorio, menor privilegio que ver la pagina de Colaboradores.
//   Los campos siguen recortados por rol, asi que lo privado no se expone.
const EXENTAS = new Set(['enviar_notificacion', 'buscar_colaborador']);
for (const h of Object.keys(HERRAMIENTAS)) {
  check(h in PERMISO || EXENTAS.has(h),
    `${h} ${h in PERMISO ? '-> ' + PERMISO[h] : '(exenta)'}`);
}

console.log('\n2. Ninguna lista blanca deja escribir campos de privilegio');
for (const [h, campos] of Object.entries(CAMPOS)) {
  const malos = ['role', 'permissions', 'id', 'is_blocked'].filter((c) => campos.has(c));
  check(malos.length === 0, `${h} ${malos.length ? 'PERMITE ' + malos.join(',') : 'limpia'}`);
}

console.log('\n3. La lista blanca coincide con el esquema de la herramienta');
// Campos que el esquema declara pero que el codigo fuerza a mano DESPUES del spread, para que el
// modelo no pueda elegirlos. Excluirlos de la lista blanca es lo correcto, no una omision:
// crear_incidencia obliga usuario_id/nombre_usuario al usuario en sesion si no es admin.
const FORZADOS = { crear_incidencia: ['usuario_id', 'nombre_usuario'] };
for (const [h, campos] of Object.entries(CAMPOS)) {
  const forzados = new Set(FORZADOS[h] ?? []);
  const esquema = new Set(
    [...(HERRAMIENTAS[h] ?? [])].filter((c) => c !== 'id' && !forzados.has(c)));
  const faltan = [...esquema].filter((c) => !campos.has(c));
  const sobran = [...campos].filter((c) => !esquema.has(c));
  check(faltan.length === 0 && sobran.length === 0,
    `${h}${faltan.length ? ' | el esquema declara y la lista NO permite: ' + faltan.join(',') : ''}`
    + `${sobran.length ? ' | la lista permite y el esquema NO declara: ' + sobran.join(',') : ''}`);
}

console.log('\n4. Toda escritura tiene lista blanca');
for (const h of Object.keys(HERRAMIENTAS)) {
  if (/^(crear|actualizar|gestionar)_/.test(h) && h !== 'enviar_notificacion') {
    check(h in CAMPOS, `${h}`);
  }
}

console.log('\n5. Acceso resultante para los 9 usuarios reales del asistente');
const REALES = [
  ['ANGEL ANTONIO (admin)', true,  { show_cssi: true,  show_incidencias: true, show_issi: true,  show_external_contacts: true }],
  ['ENRIQUE (admin)',       true,  { show_cssi: false, show_incidencias: true, show_issi: false, show_external_contacts: true }],
  ['KANDI AMERICA (admin)', true,  { show_cssi: true,  show_incidencias: true, show_issi: false, show_external_contacts: false }],
  ['MARCO ANTONIO (admin)', true,  { show_cssi: true,  show_incidencias: true, show_issi: true,  show_external_contacts: true }],
  ['SISTEMAS (admin)',      true,  { show_cssi: true,  show_incidencias: true, show_issi: true,  show_external_contacts: true }],
  ['ANA MARIA (usuario)',   false, { show_cssi: false, show_incidencias: true, show_issi: false }],
  ['KAREN (usuario)',       false, { show_cssi: false, show_incidencias: true, show_issi: false }],
  ['ROCIO (usuario)',       false, { show_cssi: false, show_incidencias: true, show_issi: false }],
  ['RODRIGO (usuario)',     false, { show_cssi: false, show_incidencias: true, show_issi: false }],
];
for (const [quien, esAdmin, perms] of REALES) {
  const permitidas = Object.keys(HERRAMIENTAS).filter((h) => puedeUsar(h, esAdmin, perms));
  console.log(`  ${quien.padEnd(24)} ${String(permitidas.length).padStart(2)}/12  ${permitidas.join(' ')}`);
}

console.log('\n6. Un usuario normal nunca alcanza una escritura fuerte');
for (const [quien, esAdmin, perms] of REALES.filter((r) => !r[1])) {
  const fuertes = [...ADMIN_ONLY].filter((h) => puedeUsar(h, esAdmin, perms));
  check(fuertes.length === 0, `${quien}${fuertes.length ? ' ALCANZA ' + fuertes.join(',') : ''}`);
}

console.log('\n7. Sin permisos, no alcanza nada salvo lo exento');
// Se compara contra EXENTAS y no contra una lista escrita a mano: asi la comprobacion sigue
// significando algo cuando cambie el conjunto de exentas, en lugar de haber que editarla.
const nada = Object.keys(HERRAMIENTAS).filter((h) => puedeUsar(h, false, {}));
const sobran = nada.filter((h) => !EXENTAS.has(h));
check(sobran.length === 0,
  `alcanza sin permisos: ${nada.join(',') || '(nada)'}`
  + (sobran.length ? ` | NO deberia: ${sobran.join(',')}` : ''));

// Regresion real: el nombre se inyectaba solo para los usuarios normales, de modo que con los
// administradores -que son quienes mas lo usan- Soli no sabia con quien hablaba.
console.log('\n8. El prompt sabe quien es el usuario, y para TODOS');
const prompt = src.slice(src.indexOf('function construirPrompt'),
                         src.indexOf('\n}', src.indexOf('return `Te llamas Soli')));

const lineaNombre = prompt.split('\n').find((l) => l.includes('- Nombre:'));
check(!!lineaNombre, 'el prompt incluye el nombre');
check(!!lineaNombre && !/esAdmin/.test(lineaNombre),
  'la linea del nombre NO depende de esAdmin');
check(prompt.includes('${identidad.join'), 'el bloque de identidad se inyecta en la plantilla');
check(/nombrePila/.test(prompt), 'se le indica tratarlo por su nombre de pila');
check(/no pases el parámetro usuario_id|NO pases el parámetro usuario_id/i.test(prompt),
  'se le explica como resolver "mis datos" sin pasar usuario_id');

// Todo campo de identidad que se declare debe consultarse, o llegaria vacio en silencio.
console.log('\n9. Lo que la identidad declara, la consulta lo trae');
const campos = [...src.slice(src.indexOf('interface Identidad'), src.indexOf('\n}', src.indexOf('interface Identidad')))
  .matchAll(/^\s+(\w+):/gm)].map((m) => m[1]);
const consulta = src.slice(src.indexOf('.select("role, permissions'), src.indexOf('\n', src.indexOf('.select("role, permissions')));
const equivalencias = { nombreCompleto: 'nombre', nombrePila: 'nombre', numeroEmpleado: 'numero_empleado' };
for (const campo of campos) {
  const col = equivalencias[campo] ?? campo;
  check(consulta.includes(col), `${campo} -> columna ${col}`);
}

console.log(fallas === 0 ? '\nTODO BIEN' : `\n${fallas} FALLAS`);
process.exit(fallas === 0 ? 0 : 1);
