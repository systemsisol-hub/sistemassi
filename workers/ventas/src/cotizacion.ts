import { PDFDocument, StandardFonts, rgb, PDFImage } from "pdf-lib";

export type Lead = {
  id: string;
  nombre: string;
  email: string;
  telefono: string;
  presupuesto: string;
  desarrollo: string;
  resumen?: string;
  created_at?: string;
};

export type CotizacionAssets = {
  sisolLogo?: Uint8Array; // public/assets/logo.png
  devLogo?: Uint8Array;   // public/assets/firmcred/<dev>.png
};

// Paleta (tomada del logo SISOL)
const AZUL = rgb(0.17, 0.19, 0.45);
const NARANJA = rgb(0.94, 0.55, 0.11);
const TEXTO = rgb(0.13, 0.15, 0.22);
const MUTED = rgb(0.44, 0.47, 0.56);
const CARD_BG = rgb(1, 1, 1);
const BORDE = rgb(0.82, 0.85, 0.90);
const BLANCO = rgb(1, 1, 1);

// Devuelve el archivo de logo del desarrollo en public/assets/logos/, o null.
// Logos oficiales con fondo transparente (uno por desarrollo).
export function archivoLogoDesarrollo(desarrollo: string): string | null {
  const d = (desarrollo || "").toLowerCase();
  const mapa: { re: RegExp; file: string }[] = [
    { re: /ag\s*-?\s*117/, file: "ag117_ia.png" },
    { re: /bonanza|prisma/, file: "Bonanza_ia.png" },
    { re: /olympia|olimpia/, file: "olimpia_ia.png" },
    { re: /punta\s*pac/, file: "punta_ia.png" },
    { re: /selva\s*norte/, file: "Selva-Norte_ia.png" },
    { re: /vida\s*mar/, file: "VidaMar_ia.png" },
    { re: /koox/, file: "koox_ia.png" },
    { re: /z[eé]nesis/, file: "zenesis_ia.png" },
  ];
  return mapa.find((m) => m.re.test(d))?.file ?? null;
}

// Convierte un presupuesto en texto libre a formato moneda ("$5,450,000 MXN").
// Si no se puede interpretar, regresa el texto original.
export function formatearPresupuesto(raw: string): string {
  const txt = (raw || "").trim();
  if (!txt || /no\s+especificad/i.test(txt)) return "No especificado";
  const low = txt.toLowerCase();
  const esUSD = /usd|d[oó]lar|dls|\bus\b|\$?\s*u\.s/.test(low);
  const moneda = esUSD ? "USD" : "MXN";

  let monto: number | null = null;
  const mill = low.match(/(\d+(?:[.,]\d+)?)\s*(millones|mill[oó]n|mill|mdp)/);
  if (mill) {
    monto = parseFloat(mill[1].replace(",", ".")) * 1_000_000;
  } else {
    const mil = low.match(/(\d+(?:[.,]\d+)?)\s*(mil|k)\b/);
    if (mil) monto = parseFloat(mil[1].replace(",", ".")) * 1_000;
  }
  if (monto === null) {
    // Número explícito: "$5,450,000", "5450000", "341,714"
    const limpio = low.replace(/[^\d,.]/g, "").replace(/,/g, "");
    const v = parseFloat(limpio);
    if (!isNaN(v) && v >= 1000) monto = v;
  }
  if (monto === null || isNaN(monto)) return txt;
  const entero = Math.round(monto).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return `$${entero} ${moneda}`;
}

export async function generarCotizacionPDF(
  lead: Lead,
  assets: CotizacionAssets = {}
): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  const page = doc.addPage([612, 792]); // Carta
  const { width, height } = page.getSize();
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const font = await doc.embedFont(StandardFonts.Helvetica);

  const M = 45; // margen
  const CW = width - M * 2; // ancho de contenido

  let sisolImg: PDFImage | undefined;
  let devImg: PDFImage | undefined;
  try { if (assets.sisolLogo) sisolImg = await doc.embedPng(assets.sisolLogo); } catch {}
  try { if (assets.devLogo) devImg = await doc.embedPng(assets.devLogo); } catch {}

  // Texto centrado auxiliar
  const drawCentered = (t: string, cx: number, y: number, size: number, f = font, color = TEXTO) => {
    const w = f.widthOfTextAtSize(t, size);
    page.drawText(t, { x: cx - w / 2, y, size, font: f, color });
  };
  const drawRight = (t: string, rx: number, y: number, size: number, f = font, color = TEXTO) => {
    const w = f.widthOfTextAtSize(t, size);
    page.drawText(t, { x: rx - w, y, size, font: f, color });
  };

  // ── ENCABEZADO (fondo blanco, logo SISOL) ──────────────────────────────────
  const headTop = height;
  const headH = 84;
  if (sisolImg) {
    const lw = 132, lh = (sisolImg.height / sisolImg.width) * lw;
    page.drawImage(sisolImg, { x: M, y: headTop - 26 - lh, width: lw, height: lh });
  } else {
    page.drawText("SI SOL", { x: M, y: headTop - 52, size: 22, font: bold, color: AZUL });
  }
  // Bloque derecho: título + folio + fecha
  const fecha = lead.created_at
    ? new Date(lead.created_at + "Z").toLocaleDateString("es-MX", {
        timeZone: "America/Mexico_City", year: "numeric", month: "long", day: "numeric",
      })
    : new Date().toLocaleDateString("es-MX", { timeZone: "America/Mexico_City" });
  drawRight("COTIZACIÓN PRELIMINAR", width - M, headTop - 40, 10, bold, AZUL);
  drawRight(`Folio  ${lead.id.toUpperCase()}`, width - M, headTop - 55, 8, font, MUTED);
  drawRight(`Fecha  ${fecha}`, width - M, headTop - 67, 8, font, MUTED);
  // Línea de acento
  page.drawRectangle({ x: M, y: headTop - headH, width: CW, height: 2.2, color: NARANJA });

  let y = headTop - headH - 18;

  // ── Helpers de tarjeta y sección ────────────────────────────────────────────
  const tituloSeccion = (t: string, yy: number) => {
    page.drawRectangle({ x: M, y: yy - 1, width: 3, height: 11, color: NARANJA });
    page.drawText(t.toUpperCase(), { x: M + 9, y: yy, size: 9, font: bold, color: AZUL });
  };
  // Tarjeta con lista de campos etiqueta/valor
  const tarjetaCampos = (titulo: string, campos: [string, string][]) => {
    tituloSeccion(titulo, y);
    y -= 16;
    const filaH = 20;
    const cardH = campos.length * filaH + 14;
    page.drawRectangle({
      x: M, y: y - cardH + 8, width: CW, height: cardH,
      color: CARD_BG, borderColor: BORDE, borderWidth: 1,
    });
    let cy = y - 6;
    for (const [et, val] of campos) {
      page.drawText(et.toUpperCase(), { x: M + 14, y: cy, size: 7.5, font: bold, color: MUTED });
      page.drawText(val || "—", { x: M + 150, y: cy - 1, size: 10, font, color: TEXTO });
      cy -= filaH;
    }
    y = y - cardH + 8 - 18;
  };

  // ── DATOS DEL CLIENTE ───────────────────────────────────────────────────────
  tarjetaCampos("Datos del cliente", [
    ["Nombre", lead.nombre],
    ["Correo", lead.email],
    ["Teléfono", lead.telefono],
  ]);

  // ── TU PROPUESTA ────────────────────────────────────────────────────────────
  tituloSeccion("Tu propuesta", y);
  y -= 16;
  // Tarjeta con: logo del desarrollo (centrado y ajustado) + caja de presupuesto.
  const propH = 132;
  const cardTop = y + 8;
  const cardBottom = cardTop - propH;
  page.drawRectangle({
    x: M, y: cardBottom, width: CW, height: propH,
    color: CARD_BG, borderColor: BORDE, borderWidth: 1,
  });
  page.drawText("DESARROLLO RECOMENDADO", { x: M + 14, y: cardTop - 18, size: 7.5, font: bold, color: MUTED });

  // Zona del logo (izquierda): contiene el PNG sin deformar, centrado.
  const zoneX = M + 14, zoneW = 258;
  const zoneTop = cardTop - 30, zoneBottom = cardBottom + 14;
  const zoneH = zoneTop - zoneBottom;
  if (devImg) {
    const s = Math.min(zoneW / devImg.width, zoneH / devImg.height);
    const w = devImg.width * s, h = devImg.height * s;
    page.drawImage(devImg, {
      x: zoneX + (zoneW - w) / 2,
      y: zoneBottom + (zoneH - h) / 2,
      width: w, height: h,
    });
  } else {
    const nombre = lead.desarrollo || "Por definir";
    page.drawText(nombre, { x: zoneX, y: zoneBottom + zoneH / 2 - 6, size: 16, font: bold, color: AZUL });
  }

  // Caja de presupuesto (destacada) a la derecha, centrada verticalmente.
  const boxW = 200, boxH = 58, boxX = width - M - 14 - boxW;
  const boxY = cardBottom + (propH - boxH) / 2;
  page.drawRectangle({
    x: boxX, y: boxY, width: boxW, height: boxH,
    color: rgb(1, 0.965, 0.91), borderColor: NARANJA, borderWidth: 1,
  });
  page.drawText("PRESUPUESTO CONSIDERADO", { x: boxX + 12, y: boxY + boxH - 17, size: 7, font: bold, color: NARANJA });
  const presu = formatearPresupuesto(lead.presupuesto);
  const presuSize = presu.length > 16 ? 15 : 18;
  page.drawText(presu, { x: boxX + 12, y: boxY + 15, size: presuSize, font: bold, color: AZUL });
  y = cardBottom - 18;

  // "Lo que buscas" (si hay resumen)
  if (lead.resumen) {
    tituloSeccion("Lo que buscas", y);
    y -= 16;
    const maxW = CW - 4;
    const palabras = lead.resumen.split(/\s+/);
    let linea = "";
    const lineas: string[] = [];
    for (const p of palabras) {
      const test = (linea + " " + p).trim();
      if (font.widthOfTextAtSize(test, 9.5) > maxW) { lineas.push(linea.trim()); linea = p; }
      else linea = test;
    }
    if (linea.trim()) lineas.push(linea.trim());
    for (const ln of lineas.slice(0, 4)) {
      page.drawText(ln, { x: M + 2, y, size: 9.5, font, color: TEXTO });
      y -= 14;
    }
    y -= 8;
  }

  // ── SIGUIENTES PASOS ────────────────────────────────────────────────────────
  tituloSeccion("Siguientes pasos", y);
  y -= 20;
  const pasos = [
    "Un asesor de SI SOL te contactará para afinar esta cotización.",
    "Agendamos una visita o videollamada para conocer el desarrollo.",
    "Te presentamos planes de pago y financiamiento a tu medida.",
  ];
  pasos.forEach((p, i) => {
    page.drawCircle({ x: M + 8, y: y + 3, size: 9, color: AZUL });
    drawCentered(String(i + 1), M + 8, y, 8.5, bold, BLANCO);
    page.drawText(p, { x: M + 26, y, size: 9.5, font, color: TEXTO });
    y -= 22;
  });

  // ── PIE DE PÁGINA ───────────────────────────────────────────────────────────
  page.drawRectangle({ x: 0, y: 0, width, height: 46, color: AZUL });
  page.drawRectangle({ x: 0, y: 46, width, height: 2, color: NARANJA });
  page.drawText(
    "Documento informativo. Precios y disponibilidad sujetos a cambio sin previo aviso.",
    { x: M, y: 27, size: 7.5, font, color: rgb(0.8, 0.83, 0.92) }
  );
  page.drawText("SI SOL INMOBILIARIAS", { x: M, y: 13, size: 8, font: bold, color: BLANCO });
  drawRight("sisol.com.mx", width - M, 13, 8, bold, NARANJA);

  return doc.save();
}
