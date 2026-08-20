// Verifica el sistema de permisos del asistente leyendo los mapas del CODIGO REAL.
//
// Las dos funciones se reimplementan aqui (son cinco lineas cada una); lo que se lee del archivo
// son los DATOS, que es donde de verdad viven los errores: un mapa incompleto, una lista blanca
// separada del esquema, un campo peligroso colado.
//
// Correr con:  node supabase/functions/ai-assistant/verificar_permisos.mjs
import { readdirSync } from 'node:fs';
import { leer } from './leer.mjs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// Se leen LOS OCHO modulos, no `index.ts` solo.
//
// Antes todo vivia en un archivo. Al partirlo, el prompt quedo en prompt.ts, el catalogo en
// herramientas.ts y los permisos en permisos.ts, y este arnes cruza los tres. Leer el directorio
// completo tambien evita tener que volver aqui la proxima vez que algo se mueva de sitio.
const aqui = dirname(fileURLToPath(import.meta.url));

const src = readdirSync(aqui).filter((f) => f.endsWith('.ts')).sort()
  .map((f) => leer(join(aqui, f))).join('\n');

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
// buscar_cumpleanos: la pagina de Social ya los muestra a TODO el mundo, y con el mismo filtro
//   (`social_page.dart:39`). Pedir un permiso aqui daria una respuesta distinta a la de la pantalla
//   para la misma pregunta, que es peor que no tenerlo. Devuelve dia, nombre, puesto y ubicacion; ni
//   el año de nacimiento ni la edad, que es lo unico sensible de esa fecha.
// buscar_conocimiento: la pagina de Conocimientos esta abierta a TODO el mundo -no lleva `show_*`
//   en main_navigation-, asi que pedir un permiso aqui daria una respuesta distinta a la de la
//   pantalla para la misma pregunta. El control real es el `audience`: un usuario normal solo
//   alcanza los articulos de la pestaña Colaboradores, y eso lo filtra la herramienta A MANO,
//   porque la funcion consulta con la llave de servicio y se salta RLS. Ver la comprobacion 13.
const EXENTAS = new Set(['enviar_notificacion', 'buscar_colaborador', 'buscar_cumpleanos',
  'buscar_conocimiento',
//
// buscar_contacto_emergencia: las dos reglas son distintas segun DE QUIEN se pregunte, y un solo
//   permiso no las expresa. El propio lo pide cualquiera -es su contacto y su tipo de sangre-; el de
//   otra persona exige ser admin CON show_cssi, el mismo permiso que abre la pagina del expediente
//   donde vive ese dato. La comprobacion esta dentro de la herramienta; ver la comprobacion 15.
  'buscar_contacto_emergencia']);
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


// -- 10. La via servidor-a-servidor -------------------------------------------
//
// Es la puerta que abre el puente de WhatsApp, y la que mas dano hace si se afloja: por ahi se
// declara a nombre de QUIEN se actua, sin sesion. Las comprobaciones son estructurales porque el
// riesgo no esta en un calculo, esta en el ORDEN de las condiciones.
console.log('\n10. La via interna (WhatsApp) esta bien cerrada');

const bloqueIdentidad = src.slice(
  src.indexOf('const auth = req.headers.get("Authorization");'),
  src.indexOf('const { data: prof }'));

// El camino del JWT va PRIMERO. Si `actuar_como` se leyera antes, cualquier usuario de la app
// podria conversar como su jefe.
const iJwt = bloqueIdentidad.indexOf('if (auth)');
const iInterno = bloqueIdentidad.indexOf('INTERNAL_SECRET');
check(iJwt >= 0 && iInterno > iJwt, 'el camino del JWT se evalua antes que el interno');

// Y dentro de esa rama no se toca `actuar_como`.
const ramaJwt = bloqueIdentidad.slice(iJwt, bloqueIdentidad.indexOf('} else if'));
check(!ramaJwt.includes('actuar_como'), 'con Authorization presente, actuar_como se IGNORA');

// Un secreto sin configurar deja la via APAGADA, no abierta.
check(/INTERNAL_SECRET\.length\s*>\s*0/.test(bloqueIdentidad),
  'un SOLI_INTERNAL_SECRET vacio apaga la via interna');

// Comparacion en tiempo constante, no ===.
check(bloqueIdentidad.includes('igualesEnTiempoConstante'),
  'el secreto se compara en tiempo constante');
check(!/interno\s*===\s*INTERNAL_SECRET/.test(src), 'el secreto NO se compara con ===');

// El uuid se valida antes de usarse como id de perfil.
check(/\[0-9a-f\]\{8\}-/.test(bloqueIdentidad), 'actuar_como se valida como uuid');

// La puerta de show_ai es UNA sola y se aplica despues de resolver la identidad: con dos
// comprobaciones, una se quedaria atras.
check((src.match(/!isAdmin && !hasAiPerm/g) || []).length === 1,
  'la puerta de show_ai es una sola y vale para los dos caminos');
check(src.indexOf('!isAdmin && !hasAiPerm') > src.indexOf('const { data: prof }'),
  'la puerta de show_ai se aplica DESPUES de resolver la identidad');

// Nada de `user.` despues de la identidad: por la via interna ese objeto no existe, y con el ahi la
// primera herramienta que pidiera WhatsApp habria reventado.
// Se quitan los comentarios antes de mirar: uno que EXPLIQUE por que ya no se usa `user.id` es
// justo lo que conviene conservar, y la primera version de esta comprobacion lo marcaba como falla.
const trasIdentidad = src.slice(src.indexOf('const { data: prof }'))
  .split('\n').map((l) => l.replace(/\/\/.*$/, '')).join('\n');
check(!/\buser\.(id|email)\b/.test(trasIdentidad),
  'no queda ningun user.id ni user.email en CODIGO despues de la identidad');

// ── 11. El prompt no lleva acentos graves sin escapar ────────────────────────
//
// El prompt se arma con una plantilla de texto delimitada por acentos graves. Un acento grave suelto
// dentro CIERRA la plantilla a media frase, y el resto se interpreta como codigo.
//
// Esto ya paso: tres reglas que escribi con `nombre_completo` entre acentos graves rompieron el
// despliegue desde el panel —«Expected ';', got 'nombre_completo'»— mientras que `node --check` las
// daba por buenas, porque un identificador seguido de otra plantilla es sintaxis valida en
// JavaScript (una tagged template). Parsea, pero significa otra cosa y reventaria al ejecutarse.
//
// Y algo peor: mis despliegues por la API SI las escapaban al meterlas en el JSON, asi que
// produccion funcionaba y el repositorio quedaba distinto. La solucion es no usar acentos graves ahi
// dentro: el prompt ya usa «» para citar nombres de campos.
console.log('\n11. El prompt no lleva acentos graves sin escapar');
const iniPrompt = src.indexOf('return `Te llamas Soli');
const finPrompt = src.indexOf('`;', iniPrompt);
check(iniPrompt > 0 && finPrompt > iniPrompt, 'se encuentra la plantilla del prompt');
if (iniPrompt > 0 && finPrompt > iniPrompt) {
  const cuerpo = src.slice(iniPrompt + 'return `'.length, finPrompt);
  const sueltos = [...cuerpo].filter((c, i) => c === '`' && cuerpo[i - 1] !== '\\').length;
  check(sueltos === 0,
    `ningun acento grave sin escapar dentro del prompt (hay ${sueltos})`);
}

// ── 12. Toda herramienta se explica en la pagina de configuracion ────────────
//
// `QUE_HACE` alimenta la pagina que ven los administradores. Si alguien agrega una herramienta y se
// olvida de la descripcion, la pagina la mostraria con la celda vacia: una capacidad del agente
// visible pero sin explicar, que es peor que no tener la pagina.
console.log('\n12. Toda herramienta tiene descripcion para la pagina');
const queHace = src.slice(src.indexOf('const QUE_HACE'), src.indexOf('const VIAS_DIRECTAS'));
for (const h of Object.keys(HERRAMIENTAS)) {
  check(new RegExp(`(^|\\s)${h}:`, 'm').test(queHace), `${h} se explica en QUE_HACE`);
}

console.log('\n13. La base de conocimiento filtra por audiencia A MANO');
// `knowledge_articles` YA tiene la politica correcta -SELECT si audience='all' o eres admin- pero esta
// funcion consulta con la LLAVE DE SERVICIO, que se salta RLS. Si estas dos lineas desaparecen,
// cualquiera con acceso al asistente lee los articulos de la pestaña de Administradores, y nada mas
// falla: la consulta seguiria funcionando y devolviendo MAS de lo que debe.
{
  const i = src.indexOf('name === "buscar_conocimiento"');
  check(i > 0, 'existe el bloque de buscar_conocimiento');
  if (i > 0) {
    const bloque = src.slice(i, i + 4000);
    const filtros = [...bloque.matchAll(/if \(!isAdmin\)[^\n]*eq\("audience", "all"\)/g)].length;
    check(filtros >= 2,
      `el filtro por audiencia aparece ${filtros} veces (hacen falta 2: la busqueda y el articulo suelto)`);
    check(!/audience[^\n]*input\./.test(bloque),
      'la audiencia NO se toma de lo que manda el modelo');
  }
}

const archivos = readdirSync(aqui).filter((f) => f.endsWith('.ts')).sort();

console.log('14. Ningun caracter de control suelto en el codigo');
// El fallo que lo motivo: al inyectar codigo con un heredoc, `\b` se convirtio en el CARACTER de
// retroceso (0x08) once veces. Deno rechazo el despliegue por sintaxis, pero
// `node --experimental-strip-types --check` habia dado OK -tercer falso «OK» del dia- y los arneses
// tambien pasaban, porque un `\b` perdido no rompe una expresion regular: solo cambia lo que empata.
//
// Un `\b` que se vuelve 0x08 deja de ser un limite de palabra, asi que «de» empieza a coincidir dentro
// de «tarde». Es un cambio de comportamiento invisible, y de los peores de encontrar.
{
  const nombres = { 8: 'retroceso (era \b)', 12: 'form feed (era \f)', 11: 'tab vertical (era \v)', 0: 'nulo (era \0)', 13: 'CR' };
  let sucios = 0;
  for (const f of archivos) {
    const src = leer(join(aqui, f));
    const malos = new Set();
    for (const ch of src) {
      const c = ch.codePointAt(0);
      if (c < 32 && ch !== '\n' && ch !== '\t') malos.add(c);
    }
    if (malos.size > 0) {
      sucios++;
      check(false, `${f} lleva ${[...malos].map((c) => nombres[c] ?? c).join(', ')}`);
    }
  }
  check(sucios === 0, `los ${archivos.length} archivos sin controles sueltos`);
}

console.log('\n15. El contacto de emergencia de OTRA persona exige admin con show_cssi');
// Es la unica linea que separa «mi contacto» de «el contacto de cualquiera». Si desaparece, un usuario
// normal con acceso al asistente puede pedir el telefono de la referencia y el tipo de sangre de los
// 244 vigentes, y nada mas falla: la consulta seguiria funcionando.
//
// La herramienta esta EXENTA del mapa de permisos a proposito -el propio lo pide cualquiera- asi que
// la comprobacion 1 no la cubre. Esta es la que la cubre.
{
  const i = src.indexOf('name === "buscar_contacto_emergencia"');
  check(i > 0, 'existe el bloque de buscar_contacto_emergencia');
  if (i > 0) {
    const bloque = src.slice(i, i + 5000);
    check(/pideDeOtro\s*&&\s*!\(isAdmin\s*&&\s*permisos\.show_cssi\s*===\s*true\)/.test(bloque),
      'pedir el de otra persona exige isAdmin Y show_cssi');
    check(/pideDeOtro\s*=\s*Boolean\(/.test(bloque),
      'se decide si es de otro ANTES de consultar');
    // Que el propio NO exija permiso: si alguien "arregla" esto metiendo la herramienta en el mapa,
    // un usuario normal dejaria de poder ver su propio contacto de emergencia.
    check(!/buscar_contacto_emergencia:\s*"show_/.test(src),
      'el propio NO pide permiso de pagina (no esta en PERMISO_POR_HERRAMIENTA)');
  }
}

console.log('\n16. Toda herramienta esta MENCIONADA en el prompt');
// El fallo que la motivo, del 19/08/2026: se añadieron tres herramientas -asistencia, conocimiento y
// contacto de emergencia- y ninguna se menciono en el prompt. El modelo no sabia que existian, asi que
// contestaba «Eso queda fuera de lo mio... no tengo acceso al contacto de emergencia» teniendo la
// herramienta disponible y el permiso puesto.
//
// Es un fallo que las vias directas TAPAN: la de asistencia funcionaba, asi que nadie noto que por el
// modelo no habia forma de llegar. Solo salio cuando se pregunto algo que la via directa no reconocia.
//
// El prompt es lo unico que le dice al modelo lo que puede hacer. Estar en `ALL_TOOLS` no basta.
{
  const prompt = leer(join(aqui, 'prompt.ts'));
  // `enviar_notificacion` se menciona como «Puedes enviar notificaciones», sin el nombre tecnico, y
  // esta bien asi: se comprueba aparte para no exigir una cadena que no aporta.
  const porFrase = { enviar_notificacion: /enviar notificaciones/i };
  for (const h of Object.keys(HERRAMIENTAS)) {
    // Las escrituras se enumeran en bloque -`const escrituras = [...]`- asi que basta con que su
    // nombre aparezca en el archivo.
    const mencionada = prompt.includes(h) || (porFrase[h]?.test(prompt) ?? false);
    check(mencionada, `${h} ${mencionada ? 'aparece en el prompt' : 'NO se le dice al modelo que existe'}`);
  }
}

console.log(fallas === 0 ? '\nTODO BIEN' : `\n${fallas} FALLAS`);
process.exit(fallas === 0 ? 0 : 1);
