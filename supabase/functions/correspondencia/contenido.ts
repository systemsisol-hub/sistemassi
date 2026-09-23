// Del documento del editor al HTML del correo.
//
// ─── Por que el HTML lo hace el servidor ────────────────────────────────────
//
// El editor de la pantalla -flutter_quill- no manda HTML: manda su documento, una lista de trozos de
// texto con sus formatos («Delta»). El HTML se escribe AQUI, a partir de una lista cerrada de
// formatos, y nada mas.
//
// Si la pantalla mandara HTML, la funcion tendria que fiarse de el o limpiarlo, y cualquiera con el
// permiso podria llamar a la funcion directamente y mandar desde la cuenta de la empresa un correo
// con formularios o enlaces disfrazados. Aqui no hay HTML de entrada: no hay nada que limpiar.
//
// Lo que se convierte, y solo esto (los mismos botones que enciende la pantalla):
//
//   en linea:  negrita, cursiva, subrayado, tachado, color, color de fondo, enlace
//   bloque:    titulos 1-3, lista con viñetas, lista numerada, cita, alineacion
//   imagenes:  SOLO las subidas desde el boton del editor al cubo `correspondencia-imagenes`
//
// Cualquier otro formato -tamaños de letra, codigo, sangrias, lo que venga al PEGAR desde Word o una
// pagina- se ignora y el texto sale sin el. Una imagen que no sea de ese cubo -una pegada, un enlace
// a otra pagina- se omite: ver `esRutaImagen`.
//
// Sin imports y sin efectos, a proposito: asi el arnes lo ejercita tal cual.

/// Tope de trozos del documento. Un comunicado normal usa decenas; esto solo evita que un documento
/// fabricado a mano haga trabajar a la funcion sin fin.
export const MAX_TROZOS = 5000;

const ESTILO_P = "margin:0 0 12px";
const ESTILO_TITULO: Record<number, string> = {
  1: "font-size:24px;font-weight:bold;margin:0 0 12px",
  2: "font-size:20px;font-weight:bold;margin:0 0 10px",
  3: "font-size:17px;font-weight:bold;margin:0 0 8px",
};
const ESTILO_CITA = "border-left:3px solid #c9ccd6;margin:0 0 12px;padding:0 0 0 12px;color:#555a66";
const ESTILO_LISTA = "margin:0 0 12px;padding:0 0 0 24px";

// ─── Imagenes ───────────────────────────────────────────────────────────────
//
// Van INCRUSTADAS en el correo -como adjunto con `Content-ID`, referenciado con `cid:`- y no como
// enlace a una direccion de internet. Con un enlace, Outlook y muchos servidores de empresa las
// bloquean por defecto y el comunicado llega con recuadros vacios hasta que alguien pulsa «mostrar
// imagenes». Incrustada viaja con el mensaje y se ve directamente.
//
// Por eso el documento no trae la imagen ni una URL: trae el NOMBRE del archivo que la pantalla
// subio al cubo privado. La funcion lo descarga con su llave y lo adjunta. Y solo acepta nombres con
// la forma exacta que genera la pantalla, asi que no hay manera de pedirle a la funcion que descargue
// otra cosa -otro cubo, una ruta con «../», una direccion de fuera-.

/// Si es el nombre de una imagen subida por el editor: 32 hexadecimales y una extension conocida.
export function esRutaImagen(v: unknown): v is string {
  return typeof v === "string" && /^[0-9a-f]{32}\.(png|jpg|gif)$/.test(v);
}

/// El `Content-ID` con que se referencia una imagen dentro del correo. Sale del nombre, que ya es
/// unico, para que el HTML y el adjunto no se puedan desencontrar.
export function cidDe(ruta: string): string {
  return `${ruta}@correspondencia.sisol`;
}

/// Las imagenes del documento que se van a adjuntar: validas, sin repetir, en orden de aparicion.
export function imagenesDe(ops: unknown): string[] {
  if (!Array.isArray(ops)) return [];
  const salida: string[] = [];
  for (const op of ops) {
    const ins = op && typeof op === "object" ? (op as Record<string, unknown>).insert : null;
    const ruta = ins && typeof ins === "object" ? (ins as Record<string, unknown>).image : null;
    if (esRutaImagen(ruta) && !salida.includes(ruta)) salida.push(ruta);
  }
  return salida;
}

/// Un trozo de texto con sus formatos EN LINEA ya revisados.
interface Trozo {
  texto: string;
  negrita: boolean;
  cursiva: boolean;
  subrayado: boolean;
  tachado: boolean;
  color: string | null;
  fondo: string | null;
  enlace: string | null;
}

/// Una imagen dentro de una linea.
interface Imagen {
  imagen: string;
}

/// Una linea con sus formatos de BLOQUE, que en Quill viajan en el salto de linea que la cierra.
interface Linea {
  trozos: (Trozo | Imagen)[];
  titulo: 1 | 2 | 3 | null;
  lista: "bullet" | "ordered" | null;
  cita: boolean;
  alinear: "center" | "right" | "justify" | null;
}

export function escaparHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/// Un color, SOLO si es un #rrggbb de verdad; si no, `null`.
///
/// Va dentro de un atributo `style`, y un texto libre ahi es una puerta: «red;background:url(...)»
/// cuela otra regla de estilo. Por eso no se deja pasar nada que no sea exactamente un color.
///
/// El editor escribe a veces el color con transparencia delante -«#FFE91E63», ARGB-: se quita la
/// transparencia y queda «#e91e63».
export function colorSeguro(v: unknown): string | null {
  if (typeof v !== "string") return null;
  let c = v.trim().toLowerCase();
  if (/^#[0-9a-f]{8}$/.test(c)) c = `#${c.slice(3)}`;
  if (/^#[0-9a-f]{3}$/.test(c)) c = `#${c[1]}${c[1]}${c[2]}${c[2]}${c[3]}${c[3]}`;
  return /^#[0-9a-f]{6}$/.test(c) ? c : null;
}

/// Un enlace, SOLO si es http, https o mailto; si no, `null` y el texto sale sin enlace.
///
/// «javascript:», «data:» y compañia se quedan fuera. Los clientes de correo serios ya los bloquean,
/// pero no todos, y un enlace asi desde la cuenta de la empresa es justo el tipo de correo que no
/// debe poder salir.
export function enlaceSeguro(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const u = v.trim();
  if (u === "" || u.length > 2000) return null;
  // Sin caracteres de control ni espacios de ningun tipo: «java\tscript:» engaña a algunos
  // analizadores. Se escribe con `\s` y no con un rango que acabe en el espacio (0x20): la primera
  // version escribia el espacio como escape unicode, y al guardarse quedo como un espacio literal
  // dentro de los corchetes, que funciona igual pero parece un error y cualquiera lo borraria.
  if (/[\u0000-\u001f\u007f\s]/.test(u)) return null;
  return /^(https?:\/\/|mailto:)/i.test(u) ? u : null;
}

function trozoDe(texto: string, attrs: Record<string, unknown>): Trozo {
  return {
    texto,
    negrita: attrs.bold === true,
    cursiva: attrs.italic === true,
    subrayado: attrs.underline === true,
    tachado: attrs.strike === true,
    color: colorSeguro(attrs.color),
    fondo: colorSeguro(attrs.background),
    enlace: enlaceSeguro(attrs.link),
  };
}

function lineaVacia(): Linea {
  return { trozos: [], titulo: null, lista: null, cita: false, alinear: null };
}

/// Los formatos de bloque que trae el salto de linea que cierra la linea.
function cerrarLinea(l: Linea, attrs: Record<string, unknown>): Linea {
  const h = attrs.header;
  l.titulo = h === 1 || h === 2 || h === 3 ? h : null;
  const lista = attrs.list;
  // «checked»/«unchecked» (casillas) no se enciende en la pantalla; si llega pegado, va como viñeta.
  l.lista = lista === "ordered" ? "ordered"
    : (lista === "bullet" || lista === "checked" || lista === "unchecked") ? "bullet" : null;
  l.cita = attrs.blockquote === true;
  const a = attrs.align;
  l.alinear = a === "center" || a === "right" || a === "justify" ? a : null;
  return l;
}

/// Del documento a lineas, o `null` si no tiene la forma de un documento del editor.
function aLineas(ops: unknown): Linea[] | null {
  if (!Array.isArray(ops) || ops.length > MAX_TROZOS) return null;
  const lineas: Linea[] = [];
  let actual = lineaVacia();

  for (const op of ops) {
    if (op === null || typeof op !== "object") return null;
    const o = op as Record<string, unknown>;
    const attrs = (o.attributes && typeof o.attributes === "object"
      ? o.attributes : {}) as Record<string, unknown>;

    // Elementos incrustados: la imagen subida desde el editor entra; cualquier otro -una imagen
    // pegada, un video, una formula- se omite sin romper el documento.
    if (typeof o.insert !== "string") {
      const ruta = o.insert && typeof o.insert === "object"
        ? (o.insert as Record<string, unknown>).image : null;
      if (esRutaImagen(ruta)) actual.trozos.push({ imagen: ruta });
      continue;
    }

    // Un mismo trozo puede traer varios saltos de linea: cada uno cierra una linea.
    const partes = o.insert.split("\n");
    for (let i = 0; i < partes.length; i++) {
      if (partes[i] !== "") actual.trozos.push(trozoDe(partes[i], attrs));
      if (i < partes.length - 1) {
        lineas.push(cerrarLinea(actual, attrs));
        actual = lineaVacia();
      }
    }
  }
  // Quill siempre termina el documento en un salto de linea; si no, la ultima linea sigue abierta.
  if (actual.trozos.length > 0) lineas.push(actual);
  return lineas;
}

/// Una imagen incrustada. `max-width:100%` para que no se salga en un telefono; la pantalla ya la
/// reduce a un ancho de correo antes de subirla, que es lo que la contiene en Outlook de escritorio,
/// que ignora `max-width`.
function imagenHtml(i: Imagen): string {
  return `<img src="cid:${escaparHtml(cidDe(i.imagen))}" alt="" `
    + `style="display:block;max-width:100%;height:auto;border:0;margin:0 0 12px">`;
}

function trozoHtml(t: Trozo | Imagen): string {
  if ("imagen" in t) return imagenHtml(t);
  let h = escaparHtml(t.texto);
  if (t.negrita) h = `<strong>${h}</strong>`;
  if (t.cursiva) h = `<em>${h}</em>`;
  if (t.subrayado) h = `<u>${h}</u>`;
  if (t.tachado) h = `<s>${h}</s>`;
  const estilo = [
    t.color ? `color:${t.color}` : "",
    t.fondo ? `background-color:${t.fondo}` : "",
  ].filter((x) => x !== "").join(";");
  if (estilo !== "") h = `<span style="${estilo}">${h}</span>`;
  if (t.enlace) h = `<a href="${escaparHtml(t.enlace)}" target="_blank">${h}</a>`;
  return h;
}

function contenidoLinea(l: Linea): string {
  const h = l.trozos.map(trozoHtml).join("");
  // Una linea vacia se conserva: en el editor es un renglon en blanco, y quien escribe lo pone para
  // separar. Sin el <br> el parrafo vacio se colapsa y el correo sale todo pegado.
  return h === "" ? "<br>" : h;
}

function conAlineacion(estilo: string, l: Linea): string {
  return l.alinear ? `${estilo};text-align:${l.alinear}` : estilo;
}

/// El texto plano del mismo documento, para la parte de texto del correo y para el registro.
function lineaTexto(l: Linea, numero: number): string {
  const t = l.trozos.map((x) => "imagen" in x
    ? "[imagen]"
    : x.enlace && x.enlace !== x.texto ? `${x.texto} (${x.enlace})` : x.texto).join("");
  if (l.lista === "bullet") return `• ${t}`;
  if (l.lista === "ordered") return `${numero}. ${t}`;
  return t;
}

/// El documento del editor convertido, o `null` si no es un documento valido.
export function deltaAHtml(ops: unknown): { html: string; texto: string } | null {
  const lineas = aLineas(ops);
  if (lineas === null) return null;

  const html: string[] = [];
  const texto: string[] = [];
  let i = 0;
  while (i < lineas.length) {
    const l = lineas[i];

    // Las lineas seguidas de la MISMA lista van en una sola <ul> u <ol>.
    if (l.lista !== null) {
      const tipo = l.lista;
      const etiqueta = tipo === "ordered" ? "ol" : "ul";
      const items: string[] = [];
      let n = 1;
      while (i < lineas.length && lineas[i].lista === tipo) {
        const li = lineas[i];
        items.push(`<li style="${conAlineacion("margin:0 0 4px", li)}">${contenidoLinea(li)}</li>`);
        texto.push(lineaTexto(li, n++));
        i++;
      }
      html.push(`<${etiqueta} style="${ESTILO_LISTA}">${items.join("")}</${etiqueta}>`);
      continue;
    }

    if (l.titulo !== null) {
      html.push(`<h${l.titulo} style="${conAlineacion(ESTILO_TITULO[l.titulo], l)}">`
        + `${contenidoLinea(l)}</h${l.titulo}>`);
    } else if (l.cita) {
      html.push(`<blockquote style="${conAlineacion(ESTILO_CITA, l)}">${contenidoLinea(l)}</blockquote>`);
    } else {
      html.push(`<p style="${conAlineacion(ESTILO_P, l)}">${contenidoLinea(l)}</p>`);
    }
    texto.push(lineaTexto(l, 0));
    i++;
  }

  return {
    html: `<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5;`
      + `color:#1f2330">${html.join("")}</div>`,
    // Los renglones en blanco del final no dicen nada y se quitan; los de en medio se quedan.
    texto: texto.join("\n").replace(/\s+$/, ""),
  };
}
