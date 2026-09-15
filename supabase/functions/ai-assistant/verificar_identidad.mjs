// Que una solicitud no pueda quedar a nombre de una persona y a cuenta de otra.
//
//   node --experimental-strip-types supabase/functions/ai-assistant/verificar_identidad.mjs
//
// ─── El fallo que lo origina ────────────────────────────────────────────────
//
// El 15/09/2026 Marco Montoya, que es administrador, pidio por WhatsApp unas vacaciones PARA Dulce
// Camacho. La incidencia se creo con:
//
//     nombre_usuario = «Dulce Marisela Camacho Vargas»
//     usuario_id     = el de MARCO
//
// En el panel se leia a nombre de Dulce y los dias se le descontaban a Marco. La causa eran dos
// lineas que resolvian lo mismo por separado, cada una con su propio respaldo:
//
//     const effectiveUserId   = isAdmin ? (input.usuario_id    || userId)       : userId;
//     const effectiveUserName = isAdmin ? (input.nombre_usuario || userFullName) : userFullName;
//
// Bastaba con que el modelo mandara el nombre y omitiera el id. Y no es una posibilidad teorica:
// es lo que el modelo hace por omision, porque el nombre lo tiene en la conversacion y el id no.
//
// ─── Que se comprueba ──────────────────────────────────────────────────────
//
// Se lee el CODIGO FUENTE, como el arnes de permisos: la regla es «estos dos campos salen de UNA
// resolucion», y eso se ve en el codigo, no ejecutando una consulta. Ejecutarlo pedirla base.
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { leer } from './leer.mjs';

const aqui = dirname(fileURLToPath(import.meta.url));
const src = leer(join(aqui, 'ejecutar.ts'));

let fallos = 0;
function comprobar(titulo, ok, detalle) {
  if (!ok) {
    fallos++;
    console.log(`  FALLA  ${titulo}`);
    if (detalle) console.log(`         ${detalle}`);
  }
}

/// El cuerpo de un bloque `if (name === "…") { … }`, por conteo de llaves.
function bloqueDe(herramienta) {
  const marca = `if (name === "${herramienta}")`;
  const i = src.indexOf(marca);
  if (i < 0) throw new Error(`no se encontro el bloque de ${herramienta}`);
  let prof = 0;
  const j = src.indexOf('{', i);
  for (let k = j; k < src.length; k++) {
    if (src[k] === '{') prof++;
    else if (src[k] === '}') { prof--; if (prof === 0) return src.slice(i, k + 1); }
  }
  throw new Error(`llaves sin cerrar en ${herramienta}`);
}

const crear = bloqueDe('crear_incidencia');

// ── Lo que NO puede volver ──────────────────────────────────────────────────
console.log('crear_incidencia: el nombre NO sale del modelo');

comprobar('no se asigna `nombre_usuario` desde `input`',
  !/nombre_usuario\s*:\s*[^,\n]*input\./.test(crear),
  'el nombre se esta tomando del texto del modelo en vez del perfil');

comprobar('no se asigna `usuario_id` desde `input` sin resolver',
  !/usuario_id\s*:\s*[^,\n]*input\.usuario_id/.test(crear),
  'el id entra directo del modelo, sin comprobar que exista');

comprobar('no vuelve el respaldo doble de `userFullName`',
  !/input\.nombre_usuario[^\n]*\|\|[^\n]*userFullName/.test(crear),
  'los dos campos vuelven a tener respaldos independientes');

// ── Lo que TIENE que estar ──────────────────────────────────────────────────
console.log('crear_incidencia: el nombre sale del perfil');

comprobar('el nombre se deriva con `nombreCompletoDe`',
  crear.includes('nombreCompletoDe('),
  'sin eso, el nombre guardado no viene del perfil resuelto');

comprobar('un nombre suelto se resuelve con `resolverPorNombre`',
  crear.includes('resolverPorNombre('),
  'sin eso, nombrar a alguien no lo convierte en su id');

comprobar('un id recibido se comprueba contra `profiles`',
  /from\("profiles"\)[\s\S]{0,160}\.eq\("id", idPedido\)/.test(crear),
  'un id inventado por el modelo entraria sin existir');

// Se mira el FLUJO y no la prosa del mensaje: la primera version de esta comprobacion buscaba la
// frase «NO cree la solicitud» y fallo porque en el codigo queda partida en dos lineas. Un arnes
// que depende de como esta cortado un texto avisa de cosas que no pasan.
comprobar('si el nombre no resuelve, se vuelve ANTES de insertar',
  /r\.fila === null\)\s*\{[\s\S]{0,200}return \{/.test(crear),
  'sin esto, nombrar a alguien que no existe crea la solicitud para quien pregunta');

comprobar('si el id no existe, tambien se vuelve antes',
  /if \(!perfil\)\s*\{[\s\S]{0,120}return \{[\s\S]{0,160}error:/.test(crear),
  'un id inventado crearia la solicitud igualmente');

comprobar('los dos regresos llevan los candidatos para poder preguntar',
  crear.includes('candidatos:'),
  'sin candidatos, el modelo no puede ofrecer a cual se referia');

comprobar('la respuesta dice a nombre de quien quedo',
  crear.includes('a_nombre_de'),
  'quien pidio no puede desmentirlo si no se le dice');

// ── Y que el mismo descuido no este en la de al lado ────────────────────────
//
// `actualizar_incidencia` no toca ni el id ni el nombre —solo estatus, dias y fechas— y asi tiene
// que seguir: cambiar de persona una solicitud ya creada no es «actualizar», es otra cosa.
console.log('actualizar_incidencia no cambia de persona');
const actualizar = bloqueDe('actualizar_incidencia');
comprobar('no escribe `usuario_id`', !/usuario_id\s*:/.test(actualizar));
comprobar('no escribe `nombre_usuario`', !/nombre_usuario\s*:/.test(actualizar));

console.log('');
if (fallos > 0) {
  console.log(`${fallos} FALLAS`);
  process.exit(1);
}
console.log('TODO BIEN');
