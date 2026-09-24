# Sisol — agente de ventas público (chat.sisol.red)

Chatbot de sisol.com.mx sobre Cloudflare Workers (Hono + Workers AI, Llama). Antes vivía aparte
como «AgenteIA» con su propia D1; desde el 24/09/2026 sus datos están en Supabase (tablas `ventas_*`)
y su panel es la sección **Ventas** de sistemassi.

```
sisol.com.mx ── widget.js ──► Worker chat.sisol.red ──► Supabase (llave de servicio)
                                 │                          ▲
                                 └─ Workers AI (Llama)      └── sistemassi › Ventas (sesión + RLS)
```

## Rutas

| Ruta | Quién | Qué |
|---|---|---|
| `POST /api/chat` | widget (origen permitido, 12/min por IP) | conversación, registro del lead, aviso por WhatsApp |
| `GET /api/cotizacion/:folio` | público | PDF de la cotización |
| `GET /brochures/:archivo` | público | brochure desde el bucket `ventas-brochures` |
| `GET /api/ventas/config-meta` | sesión de sistemassi con `show_ventas` (401 sin sesión válida, 403 sin permiso) | etiquetas y textos predeterminados de la configuración |
| `POST /api/ventas/leads/:folio/notificar` | sesión de sistemassi con `show_ventas` | re-envía el WhatsApp al asesor |

Lo demás (leads, conversaciones, desarrollos, inventario, conocimiento, configuración, «detener
chat») la app lo lee y escribe directo en Supabase.

## Desplegar

```powershell
npm install
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY   # una sola vez
npx wrangler secret put OPENWA_API_KEY              # ya existe en el Worker actual
npm run deploy
```

## Probar en local

Copia `.dev.vars.example` como `.dev.vars` y pon las llaves. Ojo: local escribe en la base de
producción; usa una `OPENWA_API_KEY` falsa para no mandarle WhatsApp al asesor y borra lo que crees.

```powershell
npx wrangler dev   # http://localhost:8787 (demo en /demo.html)
```

## Base de conocimiento de los PDF

`src/knowledge.ts` se genera de los PDF del Drive y va en el código:

```powershell
python scripts/sync_drive.py
python scripts/build_knowledge.py
npm run deploy
```
