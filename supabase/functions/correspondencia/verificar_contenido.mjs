// Ejercita el paso del documento del editor al HTML del correo.
//
//   node --experimental-strip-types supabase/functions/correspondencia/verificar_contenido.mjs
//
// Es la pieza donde un fallo se convierte en un correo peligroso desde la cuenta de la empresa, asi
// que la mitad de estas pruebas son intentos de colar algo: codigo, enlaces «javascript:», reglas de
// estilo metidas en un color. Los documentos tienen la forma EXACTA que produce flutter_quill: los
// formatos de bloque viajan en el salto de linea que cierra la linea.
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const M = await import(`file://${join(aqui, 'contenido.ts').replace(/\\/g, '/')}`);

let fallos = 0;
function ok(titulo, cond, detalle) {
  if (cond) return;
  fallos++;
  console.log(`  FALLA  ${titulo}`);
  if (detalle) console.log(`         ${detalle}`);
}
const html = (ops) => M.deltaAHtml(ops)?.html ?? '(null)';
const texto = (ops) => M.deltaAHtml(ops)?.texto ?? '(null)';
// El CONTENIDO, sin el envoltorio del correo. El envoltorio lleva su propio `color:` y su
// `font-size`, y la primera version de estas pruebas los encontraba ahi y daba por colado un color
// que el conversor SI habia descartado: nueve fallos, todos de la prueba.
const interior = (ops) => html(ops).replace(/^<div[^>]*>/, '').replace(/<\/div>$/, '');

// ─── Lo basico ─────────────────────────────────────────────────────────────
console.log('lo basico');
{
  const d = [{ insert: 'Hola equipo\n' }];
  ok('un parrafo', html(d).includes('<p style="margin:0 0 12px">Hola equipo</p>'), html(d));
  ok('su texto plano', texto(d) === 'Hola equipo', texto(d));
  ok('envuelto en la fuente del correo', html(d).startsWith('<div style="font-family:Arial'));
}
{
  const d = [{ insert: 'Uno\n\nDos\n' }];
  ok('un renglon en blanco se conserva', html(d).includes('<p style="margin:0 0 12px"><br></p>'), html(d));
  ok('y en el texto tambien', texto(d) === 'Uno\n\nDos', JSON.stringify(texto(d)));
}

// ─── Formatos en linea ─────────────────────────────────────────────────────
console.log('\nformatos en linea');
{
  const d = [
    { insert: 'a', attributes: { bold: true } },
    { insert: 'b', attributes: { italic: true } },
    { insert: 'c', attributes: { underline: true } },
    { insert: 'd', attributes: { strike: true } },
    { insert: '\n' },
  ];
  const h = html(d);
  ok('negrita', h.includes('<strong>a</strong>'));
  ok('cursiva', h.includes('<em>b</em>'));
  ok('subrayado', h.includes('<u>c</u>'));
  ok('tachado', h.includes('<s>d</s>'));
}
{
  const d = [{ insert: 'rojo', attributes: { color: '#FFE91E63', background: '#ff0' } }, { insert: '\n' }];
  ok('color con transparencia ARGB queda en #rrggbb', html(d).includes('color:#e91e63'), html(d));
  ok('color corto #rgb se expande', html(d).includes('background-color:#ffff00'), html(d));
}
{
  const d = [{ insert: 'sitio', attributes: { link: 'https://sisol.com.mx/aviso' } }, { insert: '\n' }];
  ok('enlace https', html(d).includes('<a href="https://sisol.com.mx/aviso" target="_blank">sitio</a>'), html(d));
  ok('en texto plano va la direccion', texto(d) === 'sitio (https://sisol.com.mx/aviso)', texto(d));
}
ok('enlace mailto', html([{ insert: 'x', attributes: { link: 'mailto:rh@sisol.com.mx' } }, { insert: '\n' }])
  .includes('href="mailto:rh@sisol.com.mx"'));

// ─── Formatos de bloque ────────────────────────────────────────────────────
console.log('\nformatos de bloque');
{
  const d = [{ insert: 'Aviso' }, { insert: '\n', attributes: { header: 1 } }, { insert: 'Texto\n' }];
  ok('titulo 1', /<h1 style="[^"]*font-size:24px[^"]*">Aviso<\/h1>/.test(html(d)), html(d));
  ok('y el texto siguiente en parrafo', html(d).includes('<p style="margin:0 0 12px">Texto</p>'));
}
ok('titulo 2', html([{ insert: 'x' }, { insert: '\n', attributes: { header: 2 } }]).includes('<h2 '));
ok('titulo 3', html([{ insert: 'x' }, { insert: '\n', attributes: { header: 3 } }]).includes('<h3 '));
ok('un «titulo 4» no existe: sale como parrafo',
  html([{ insert: 'x' }, { insert: '\n', attributes: { header: 4 } }]).includes('<p '));
{
  const d = [
    { insert: 'uno' }, { insert: '\n', attributes: { list: 'bullet' } },
    { insert: 'dos' }, { insert: '\n', attributes: { list: 'bullet' } },
    { insert: 'primero' }, { insert: '\n', attributes: { list: 'ordered' } },
    { insert: 'segundo' }, { insert: '\n', attributes: { list: 'ordered' } },
  ];
  const h = html(d);
  ok('las viñetas seguidas van en UNA lista', (h.match(/<ul /g) ?? []).length === 1, h);
  ok('con sus dos elementos', (h.match(/<li /g) ?? []).length === 4, h);
  ok('la numerada es otra lista', (h.match(/<ol /g) ?? []).length === 1, h);
  ok('en texto plano con viñeta y numero',
    texto(d) === '• uno\n• dos\n1. primero\n2. segundo', JSON.stringify(texto(d)));
}
{
  const d = [{ insert: 'cita' }, { insert: '\n', attributes: { blockquote: true } }];
  ok('cita', /<blockquote style="[^"]*border-left[^"]*">cita<\/blockquote>/.test(html(d)), html(d));
}
ok('alineacion centrada',
  html([{ insert: 'x' }, { insert: '\n', attributes: { align: 'center' } }]).includes('text-align:center'));

// ─── Lo que se tiene que quedar fuera ──────────────────────────────────────
console.log('\nlo que se tiene que quedar fuera');
{
  const d = [{ insert: '<script>alert(1)</script><form action="x"><input></form>\n' }];
  ok('el codigo escrito sale como TEXTO', !html(d).includes('<script') && !html(d).includes('<form'),
    html(d));
  ok('escapado', html(d).includes('&lt;script&gt;'));
}
for (const malo of ['javascript:alert(1)', 'JavaScript:alert(1)', 'data:text/html;base64,xx',
  'vbscript:x', 'java\tscript:alert(1)', ' javascript:alert(1)', 'ftp://x.com', '//evil.com']) {
  const h = html([{ insert: 'clic', attributes: { link: malo } }, { insert: '\n' }]);
  ok(`un enlace «${malo.replace(/\t/g, '\\t')}» NO se convierte en enlace`, !h.includes('<a '), h);
  ok(`  pero el texto se conserva`, h.includes('clic'));
}
{
  // Una comilla en la direccion intentando cerrar el atributo y abrir otro.
  const h = html([{ insert: 'x', attributes: { link: 'https://x.com/"onmouseover="alert(1)' } }, { insert: '\n' }]);
  ok('una comilla en el enlace no cierra el atributo', !h.includes('" onmouseover') && !h.includes('"onmouseover'), h);
}
for (const malo of ['red;background:url(javascript:x)', 'red', 'expression(alert(1))', '#12345',
  '#gggggg', 'rgb(1,2,3)', 123, null]) {
  const h = interior([{ insert: 'x', attributes: { color: malo } }, { insert: '\n' }]);
  ok(`un color «${String(malo)}» no entra en el estilo`, !h.includes('color:'), h);
}
{
  // Lo que llega al PEGAR desde Word o una pagina: formatos que la pantalla no ofrece.
  const d = [
    { insert: 'grande', attributes: { size: 'huge', font: 'Comic Sans', script: 'super' } },
    { insert: 'codigo', attributes: { code: true } },
    { insert: '\n', attributes: { 'code-block': true, indent: 3, direction: 'rtl' } },
  ];
  const h = interior(d);
  ok('formatos desconocidos se ignoran sin perder el texto',
    h.includes('grande') && h.includes('codigo') && !/size|font-family:Comic|<code|<pre|indent|rtl/.test(h), h);
}
{
  const d = [{ insert: 'antes' }, { insert: { image: 'https://x.com/a.png' } }, { insert: 'despues\n' }];
  ok('una imagen incrustada se omite sin romper', html(d).includes('antesdespues') && !html(d).includes('<img'),
    html(d));
}

// ─── Documentos que no son documentos ──────────────────────────────────────
console.log('\ndocumentos que no son documentos');
ok('algo que no es lista', M.deltaAHtml('hola') === null);
ok('un trozo que no es objeto', M.deltaAHtml([{ insert: 'a\n' }, 'b']) === null);
ok('un null', M.deltaAHtml([null]) === null);
ok('demasiados trozos', M.deltaAHtml(Array.from({ length: M.MAX_TROZOS + 1 }, () => ({ insert: 'a' }))) === null);
ok('un documento vacio da texto vacio (lo rechaza la validacion, no esto)',
  M.deltaAHtml([{ insert: '\n' }])?.texto === '');
ok('atributos que no son objeto no revientan',
  M.deltaAHtml([{ insert: 'a', attributes: 'bold' }, { insert: '\n' }])?.texto === 'a');

console.log('');
if (fallos > 0) {
  console.log(`${fallos} FALLAS`);
  process.exit(1);
}
console.log('TODO BIEN');
