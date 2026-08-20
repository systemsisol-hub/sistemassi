// Comprueba que los ocho modulos encajan entre si, antes de pegarlos en el panel.
//
//   node --experimental-strip-types supabase/functions/ai-assistant/verificar_modulos.mjs
//
// ─── Por que hace falta ──────────────────────────────────────────────────────
//
// `deno check` haria esto solo, pero no hay Deno en esta maquina y el CLI de Supabase falla con
// `TransportError`, asi que el primero en revisar el codigo es el panel, ya en produccion. Al partir
// el archivo el fallo tipico deja de ser un parentesis y pasa a ser un importe: mover una funcion y
// olvidar el `export`, o usar en un modulo algo que vive en otro sin traerlo. Node no lo detecta
// -`--check` mira un archivo a la vez, sin resolver nada entre ellos- y en el panel eso sale como un
// error de despliegue.
//
// Se comprueban cuatro cosas:
//
//   1. Todo lo que se importa existe y esta exportado en el archivo del que se dice que viene.
//   2. Nada que se importe queda sin usar (un importe muerto suele ser el rastro de un movimiento
//      a medias).
//   3. Nada se usa sin importarse, cuando vive en otro modulo.
//   4. No hay ciclos de importacion.
import { readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { leer } from './leer.mjs';

const aqui = dirname(fileURLToPath(import.meta.url));
const archivos = readdirSync(aqui).filter((f) => f.endsWith('.ts')).sort();

/// Quita comentarios y cadenas.
///
/// De una plantilla se conserva SOLO lo de dentro de `${...}`: ahi viven referencias de verdad
/// -`${today}`, `Bearer ${OLLAMA_KEY}`- y borrarlas enteras esconde importes que si hacen falta.
function soloCodigo(s) {
  return s
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/(^|[^:])\/\/.*$/gm, '$1')
    .replace(/`(?:[^`\\]|\\[\s\S])*`/g, (m) =>
      ' ' + (m.match(/\$\{[^}]*\}/g) || []).join(' ') + ' ')
    .replace(/"(?:[^"\\]|\\[\s\S])*"/g, ' ')
    .replace(/'(?:[^'\\]|\\[\s\S])*'/g, ' ');
}

const reDecl =
  /^(export\s+)?(?:async\s+)?(?:function|const|let|type|interface|class)\s+([A-Za-z_$][\w$]*)/;
const reImport = /^import\s+(?:type\s+)?\{([^}]*)\}\s+from\s+"\.\/([^"]+)"/gm;

const declara = {};   // archivo -> Set de nombres declarados
const exporta = {};   // archivo -> Set de nombres exportados
const importa = {};   // archivo -> { de: [nombres] }
const codigo = {};

for (const f of archivos) {
  // `leer` normaliza CRLF; ver el porque en verificar_permisos.mjs.
  const src = leer(join(aqui, f));
  declara[f] = new Set();
  exporta[f] = new Set();
  for (const linea of src.split('\n')) {
    const m = reDecl.exec(linea);
    if (!m) continue;
    declara[f].add(m[2]);
    if (m[1]) exporta[f].add(m[2]);
  }
  importa[f] = {};
  for (const m of src.matchAll(reImport)) {
    const nombres = m[1].split(',').map((n) => n.trim()).filter(Boolean);
    (importa[f][m[2]] ||= []).push(...nombres);
  }
  codigo[f] = soloCodigo(src.replace(reImport, ' '));
}

const dueno = {};
for (const f of archivos) for (const n of declara[f]) dueno[n] = f;

let fallos = 0;
const falla = (m) => { console.log(`  FALLA  ${m}`); fallos++; };

console.log('1. Lo que se importa existe y esta exportado');
for (const f of archivos) {
  for (const [de, nombres] of Object.entries(importa[f])) {
    if (!archivos.includes(de)) { falla(`${f} importa de "./${de}", que no existe`); continue; }
    for (const n of nombres) {
      if (!declara[de].has(n)) falla(`${f} importa ${n} de ${de}, que no lo declara`);
      else if (!exporta[de].has(n)) falla(`${f} importa ${n} de ${de}, que NO lo exporta`);
    }
  }
}

console.log('2. Ningun importe queda sin usar');
for (const f of archivos) {
  const usados = new Set(codigo[f].match(/[A-Za-z_$][\w$]*/g) || []);
  for (const [de, nombres] of Object.entries(importa[f]))
    for (const n of nombres)
      if (!usados.has(n)) falla(`${f} importa ${n} de ${de} y no lo usa`);
}

console.log('3. Nada se usa sin importarse');
for (const f of archivos) {
  const traidos = new Set(Object.values(importa[f]).flat());
  for (const n of new Set(codigo[f].match(/[A-Za-z_$][\w$]*/g) || [])) {
    if (declara[f].has(n) || traidos.has(n)) continue;
    if (dueno[n] && dueno[n] !== f) falla(`${f} usa ${n}, que vive en ${dueno[n]}, sin importarlo`);
  }
}

console.log('4. No hay ciclos de importacion');
// Basta con buscar un camino de vuelta desde cada dependencia: son ocho archivos.
for (const f of archivos) {
  const visto = new Set();
  const pila = [...Object.keys(importa[f])];
  while (pila.length) {
    const d = pila.pop();
    if (d === f) { falla(`ciclo: ${f} acaba dependiendo de si mismo`); break; }
    if (visto.has(d) || !importa[d]) continue;
    visto.add(d);
    pila.push(...Object.keys(importa[d]));
  }
}

console.log(`\n${archivos.length} archivos: ${archivos.join(', ')}`);
console.log(fallos === 0 ? 'TODO BIEN' : `${fallos} FALLAS`);
process.exit(fallos === 0 ? 0 : 1);
