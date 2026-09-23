// Ejercita la lectura de la vista publica del Drive.
//
//   node --experimental-strip-types supabase/functions/drive-sync/verificar_drive.mjs
//   node --experimental-strip-types supabase/functions/drive-sync/verificar_drive.mjs --en-vivo
//
// Sin bandera prueba con paginas armadas aqui. Con `--en-vivo` recorre ademas la carpeta REAL de
// AG117: es la forma de saber si Google cambio su pagina, que es el riesgo que se acepto al no usar
// llave (23/09/2026).
import { writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { leer } from '../ai-assistant/leer.mjs';

const aqui = dirname(fileURLToPath(import.meta.url));
const cargar = async (archivo, cambiar = (s) => s) => {
  const destino = join(tmpdir(), `drive_${archivo.replace('.ts', '')}_${Date.now()}.ts`);
  writeFileSync(destino, cambiar(leer(join(aqui, archivo))), 'utf8');
  return import(`file://${destino.replace(/\\/g, '/')}`);
};
const L = await cargar('listado.ts');
// El lector de PDF se prueba sin pdf.js: solo lo que arma el texto.
const R = await cargar('leer.ts', (s) => s.replace(/^import .*unpdf.*$/m, 'const getDocumentProxy = null;'));

let fallos = 0;
function comprobar(titulo, ok, detalle) {
  if (!ok) {
    fallos++;
    console.log(`  FALLA  ${titulo}`);
    if (detalle) console.log(`         ${detalle}`);
  }
}

const entrada = ({ id, titulo, carpeta = false, tipo = 'application/pdf', fecha = 'Sep 17' }) =>
  `<div class="flip-entry" id="entry-${id}" tabindex="0" role="link"><div class="flip-entry-info">`
  + `<a href="${carpeta ? `https://drive.google.com/drive/folders/${id}` : `https://drive.google.com/file/d/${id}/view?usp=drive_web`}" target="_blank">`
  + (carpeta
    ? '<div class="flip-entry-list-icon"><div aria-label="Folder" class="icon-color-1"></div></div>'
    : `<div class="flip-entry-list-icon"><img src="https://drive-thirdparty.googleusercontent.com/16/type/${tipo}" alt=""/></div>`)
  + `<div class="flip-entry-title">${titulo}</div></a></div>`
  + `<div class="flip-entry-last-modified"><div>${fecha}</div></div></div>`;
const pagina = (...e) => `<html><body><div class="flip-entries">${e.join('')}</div></body></html>`;

// ── La pagina ───────────────────────────────────────────────────────────────
console.log('la vista publica');

const r1 = L.leerListado(pagina(
  entrada({ id: 'CARPETA_1234567', titulo: '7. Planos', carpeta: true, fecha: 'Mar 19' }),
  entrada({ id: 'ARCHIVO_1234567', titulo: 'TIPOLOG&Iacute;AS SEP 2026.pdf' }),
  entrada({ id: 'IMAGEN_12345678', titulo: 'Render &amp; fachada.png', tipo: 'image/png', fecha: '7/25/25' }),
));
comprobar('lee las tres entradas', r1.ok && r1.entradas.length === 3, JSON.stringify(r1));
const [c, a, i] = r1.ok ? r1.entradas : [];
comprobar('la carpeta es carpeta y sin tipo', c?.esCarpeta === true && c?.tipo === null);
comprobar('el archivo trae su tipo', a?.tipo === 'application/pdf' && a?.esCarpeta === false);
comprobar('la fecha tal cual', c?.modificado === 'Mar 19' && i?.modificado === '7/25/25');
comprobar('decodifica &amp;', i?.nombre === 'Render & fachada.png', i?.nombre);
comprobar('un PDF es PDF', L.esPdf(a) === true);
comprobar('una imagen no es PDF', L.esPdf(i) === false);
comprobar('una carpeta no es PDF', L.esPdf(c) === false);
comprobar('sin tipo, decide la extension', L.esPdf({ nombre: 'x.PDF', tipo: null, esCarpeta: false }) === true);
comprobar('enlace de carpeta', L.enlaceDe(c) === 'https://drive.google.com/drive/folders/CARPETA_1234567');
comprobar('enlace de archivo', L.enlaceDe(a) === 'https://drive.google.com/file/d/ARCHIVO_1234567/view');
comprobar('entidades numericas', L.sinEntidades('dep&#243;sito &#x26; m&aacute;s') === 'depósito & m&aacute;s');

// Lo que NO puede pasar: confundir «la pagina cambio» con «la carpeta esta vacia». Lo segundo es
// legitimo; lo primero, tomado por vacio, borraria todo el indice.
const vacia = L.leerListado(pagina());
comprobar('una carpeta vacia es vacia, no error', vacia.ok && vacia.entradas.length === 0);
const otra = L.leerListado('<html><body><div class="nueva-vista">...</div></body></html>');
comprobar('una pagina distinta es ERROR', otra.ok === false);
const sesion = L.leerListado('<html><a href="https://accounts.google.com/ServiceLogin">Acceder</a></html>');
comprobar('la de iniciar sesion dice que ya no es publica', sesion.ok === false && /publica/.test(sesion.error));
const rota = L.leerListado(pagina('<div class="flip-entry" id="entry-SINTITULO1234"><a href="x">'));
comprobar('una entrada sin titulo es ERROR, no se salta', rota.ok === false);

// ── El texto de un PDF ──────────────────────────────────────────────────────
console.log('el texto de una pagina');
const t = R.textoDePagina([
  { str: 'RECÁMARA 01', hasEOL: true }, { str: '3.04', hasEOL: false }, { str: '  BAÑO', hasEOL: true },
  { str: '', hasEOL: true }, { str: '', hasEOL: true }, { str: '', hasEOL: true }, { str: 'COCINA', hasEOL: false },
]);
comprobar('cada renglon en su renglon', t === 'RECÁMARA 01\n3.04 BAÑO\n\nCOCINA', JSON.stringify(t));
comprobar('una pagina sin nada es cadena vacia', R.textoDePagina([]) === '');
comprobar('el presupuesto deja margen bajo los 2 s de CPU', R.PRESUPUESTO_MS <= 1200);
comprobar('el tope de texto es el de la columna', R.MAX_TEXTO === 400000);

// ── En vivo ─────────────────────────────────────────────────────────────────
if (process.argv.includes('--en-vivo')) {
  console.log('en vivo: la carpeta de AG117');
  let carpetas = 0, archivos = 0, pdfs = 0, tipologias = false;
  const cola = ['15qj0oVBgFrHec1GU-pgWdLG6F8SIPN63'];
  while (cola.length) {
    const id = cola.shift();
    const r = await fetch(L.URL_VISTA + id);
    const l = L.leerListado(await r.text());
    if (!l.ok) { comprobar(`la carpeta ${id} se lee`, false, l.error); break; }
    for (const e of l.entradas) {
      if (e.esCarpeta) { carpetas++; cola.push(e.id); } else { archivos++; if (L.esPdf(e)) pdfs++; }
      if (/^TIPOLOGIAS/i.test(e.nombre)) tipologias = true;
    }
  }
  console.log(`  ${carpetas} carpetas, ${archivos} archivos, ${pdfs} PDF`);
  comprobar('encuentra carpetas y archivos', carpetas > 10 && archivos > 50);
  comprobar('encuentra el archivo de tipologias', tipologias);
}

console.log('');
if (fallos > 0) {
  console.log(`${fallos} FALLAS`);
  process.exit(1);
}
console.log('TODO BIEN');
