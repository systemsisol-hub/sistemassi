# -*- coding: utf-8 -*-
"""
Sincroniza la carpeta comercial de SISOL en Google Drive descargando SOLO
los PDF en español relevantes para la base de conocimiento del agente
(brochures, listas de precios, sembrados). Omite fotos, videos, formatos,
carpetas legales y versiones en inglés/brokers.

Usa gdown solo para enumerar el árbol; la descarga va directo a
drive.usercontent.google.com (gdown es bloqueado por rate-limit de Google).

Uso:  python scripts/sync_drive.py
Luego: python scripts/build_knowledge.py
"""
import os
import re
import sys
import time

import gdown
import requests

FOLDER_URL = "https://drive.google.com/drive/folders/1N0HrBsbFbb8FQJkwejJGAZOCSf5sM-xb"
DEST = os.path.join(os.path.dirname(__file__), "..", "drive-data")
DOWNLOAD_URL = "https://drive.usercontent.google.com/download?id={id}&export=download&confirm=t"

EXTENSIONES = (".pdf",)

# Carpetas/archivos que no aportan a la conversación de ventas
EXCLUIR_SUBSTR = (
    "carpeta legal", "aviso de privacidad", "cuenta de dep", "checklist",
    "check list", "videos", "fotos", "renders", "cv desarrollador",
    "liga drive",
)
# Versiones en inglés o para brokers (la base se construye en español)
EXCLUIR_REGEX = re.compile(r"(^|[\\/ _.()-])(eng|en|ing|brokers)([\\/ _.()-]|$)", re.IGNORECASE)


def descargar(file_id: str, dest: str) -> bool:
    r = requests.get(DOWNLOAD_URL.format(id=file_id), timeout=120)
    if r.status_code != 200 or not r.content.startswith(b"%PDF"):
        print(f"    ERROR: status={r.status_code}, no es PDF (len={len(r.content)})")
        return False
    with open(dest, "wb") as f:
        f.write(r.content)
    return True


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print("Enumerando archivos de Drive (sin descargar)...")
    files = gdown.download_folder(FOLDER_URL, skip_download=True, quiet=True)
    if not files:
        print("No se pudo enumerar la carpeta. ¿Sigue siendo pública?")
        sys.exit(1)
    print(f"Enumerados: {len(files)} archivos. Filtrando PDFs en español...")

    descargados = errores = 0
    for f in files:
        rel = f.path  # ruta relativa dentro de la carpeta de Drive
        rel_lower = rel.lower()
        if not rel_lower.endswith(EXTENSIONES):
            continue
        if any(x in rel_lower for x in EXCLUIR_SUBSTR):
            continue
        if EXCLUIR_REGEX.search(rel):
            continue
        dest = os.path.join(DEST, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if os.path.exists(dest):
            print(f"  ya existe: {rel}")
            continue
        print(f"  descargando: {rel}")
        try:
            if descargar(f.id, dest):
                descargados += 1
            else:
                errores += 1
        except Exception as e:
            print(f"    ERROR: {e}")
            errores += 1
        time.sleep(1.5)  # no provocar el rate-limit de Google

    print(f"\nListo: {descargados} PDF descargados, {errores} errores, en {os.path.abspath(DEST)}")


if __name__ == "__main__":
    main()
