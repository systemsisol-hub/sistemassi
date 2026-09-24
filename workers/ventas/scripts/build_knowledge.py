# -*- coding: utf-8 -*-
"""
Extrae el texto de los PDF descargados de Drive (drive-data/) y genera
src/knowledge.ts con la base de conocimiento que usa el agente.

Uso: python scripts/build_knowledge.py
"""
import os
import re
import sys
from pypdf import PdfReader

ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC_DIR = os.path.join(ROOT, "drive-data")
OUT = os.path.join(ROOT, "src", "knowledge.ts")

# Límite de caracteres por PDF para no saturar el contexto del modelo
MAX_POR_PDF = 6000
# SOLO se incluye contenido útil para la conversación de ventas: brochures,
# listas de precios y ubicación de cada desarrollo. Todo lo demás (planos,
# prototipos, infonavit, estudios de mercado, sembrados, cuentas, legales,
# CV/ética/políticas, etc.) se omite para no inflar el contexto del modelo.
INCLUIR = ("brochure", "lista de precios", "listas de precios", "ubicaci")

# Dentro de lo incluido, omite versiones en inglés/brokers.
OMITIR = (
    "\\eng\\", "/eng/", "\\ing\\", "/ing/", "brokers", "(ingles", "inglés", "ingles",
    " en\\", " en/", "no tel",
)


def limpiar(texto: str) -> str:
    texto = texto.replace("\x00", " ")
    texto = re.sub(r"[ \t]+", " ", texto)
    # Elimina correos y teléfonos de los brochures: el modelo NO debe dar
    # contactos de desarrollos, solo el contacto oficial del prompt.
    texto = re.sub(r"\S+@\S+\.\S+", " ", texto)                       # correos
    texto = re.sub(r"\b\d{2,4}[ \-]\d{3,4}[ \-]\d{3,4}\b", " ", texto)  # tel. 10 díg. con separadores
    texto = re.sub(r"\n{3,}", "\n\n", texto)
    # quita líneas basura muy cortas repetidas (números de página, etc.)
    lineas = [l.strip() for l in texto.split("\n")]
    return "\n".join(l for l in lineas if l)


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if not os.path.isdir(SRC_DIR):
        print("No existe drive-data/. Corre primero: python scripts/sync_drive.py")
        sys.exit(1)

    secciones = []
    for dirpath, _, filenames in os.walk(SRC_DIR):
        for fn in sorted(filenames):
            if not fn.lower().endswith(".pdf"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, fn), SRC_DIR)
            rel_l = rel.lower()
            if not any(x in rel_l for x in INCLUIR):
                continue  # no es brochure/precios/ubicación → fuera
            if any(x in rel_l for x in OMITIR):
                print(f"  omitido (EN/brokers): {rel}")
                continue
            ruta = os.path.join(dirpath, fn)
            try:
                reader = PdfReader(ruta)
                texto = "\n".join((p.extract_text() or "") for p in reader.pages)
            except Exception as e:
                print(f"  ERROR leyendo {rel}: {e}")
                continue
            texto = limpiar(texto)
            if len(texto) < 100:
                print(f"  sin texto util (escaneado/imagenes): {rel}")
                continue
            if len(texto) > MAX_POR_PDF:
                texto = texto[:MAX_POR_PDF] + "\n[...documento truncado...]"
            # El nombre de carpeta de primer nivel es la zona (quita emojis)
            partes = rel.replace("\\", "/").split("/")
            zona = re.sub(r"[^\w\sÁÉÍÓÚÑáéíóúñ]", "", partes[0]).strip()
            desarrollo = re.sub(r"[^\w\sÁÉÍÓÚÑáéíóúñ]", "", partes[1]).strip() if len(partes) > 2 else zona
            doc = os.path.splitext(fn)[0]
            secciones.append(f"## ZONA: {zona} | DESARROLLO: {desarrollo} | DOC: {doc}\n{texto}")
            print(f"  ok: {rel} ({len(texto)} chars)")

    contenido = "\n\n".join(secciones)
    print(f"\nTotal: {len(secciones)} documentos, {len(contenido)} caracteres")
    if len(contenido) > 100_000:
        print("ADVERTENCIA: la base es muy grande para el contexto del modelo;")
        print("considera bajar MAX_POR_PDF o curar los documentos.")

    ts = (
        "// GENERADO AUTOMATICAMENTE por scripts/build_knowledge.py - NO EDITAR A MANO\n"
        "// Fuente: carpeta de Drive 'DRIVE COMERCIAL SISOL'\n"
        "export const KNOWLEDGE = "
        + repr_ts(contenido)
        + ";\n"
    )
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(ts)
    print(f"Escrito: {os.path.abspath(OUT)}")


def repr_ts(s: str) -> str:
    """Serializa como template literal seguro de TS."""
    s = s.replace("\\", "\\\\").replace("`", "\\`").replace("${", "\\${")
    return "`" + s + "`"


if __name__ == "__main__":
    main()
