# Edge Functions

Código fuente de las Edge Functions de Supabase del proyecto `zkmbebybyyefmqcxjqrg`.

> **Importante:** hasta ahora estas funciones existían **únicamente desplegadas** en Supabase —
> su código no estaba en el repositorio. Si se perdía el despliegue, se perdía la fuente. Esta
> carpeta corrige eso. Cualquier cambio se edita aquí, se commitea y **luego** se despliega.

## `ai-assistant`

Asistente conversacional del sistema. Consumido por dos pantallas:

| Pantalla | Archivo |
|---|---|
| Asistente general (con adjuntos) | `lib/ai_page.dart:31` |
| Panel IA junto a reportes BI | `lib/bi_page.dart:1677` |

**Rescatada de la versión 13 desplegada** (actualizada 2026-08-04). `verify_jwt: true`.

### Contrato

Request: `{ messages: [{ role, content }, ...] }`
Response: `{ text: string, structured: unknown }`

`structured` se llena con el resultado de la última herramienta ejecutada para que Flutter pinte
tablas. Ojo: `bi_page.dart` actualmente **ignora** ese campo; `ai_page.dart:202` sí lo lee.

### Permisos

Acceso permitido si `profiles.role == 'admin'` **o** `profiles.permissions->>'show_ai' == true`.
En cualquier otro caso responde `403 Forbidden`.

El conjunto de herramientas y el system prompt cambian según el rol:

- **admin** → las 13 herramientas (`ALL_TOOLS`) y `SYSTEM_ADMIN`.
- **usuario** → sólo `USER_ALLOWED_TOOLS`; las lecturas de incidencias e inventario se fuerzan a
  `usuario_id = <el propio>`, y las 5 de `ADMIN_ONLY_TOOLS` quedan bloqueadas por partida doble
  (filtrado de la lista + verificación dentro de `runTool`).

### Variables de entorno

Se configuran en el dashboard de Supabase (Edge Functions → Secrets). **No van en el repo ni en
el cliente Flutter.**

| Secreto | Uso | Default |
|---|---|---|
| `OLLAMA_API_KEY` | Auth contra Ollama | — |
| `OLLAMA_BASE_URL` | Endpoint de Ollama | `https://ollama.com/api` |
| `OLLAMA_MODEL` | Modelo a usar | `llama3.2` |
| `SUPABASE_URL` | Inyectado por la plataforma | — |
| `SUPABASE_SERVICE_ROLE_KEY` | Inyectado por la plataforma | — |

El modelo se invoca con `tools` y un bucle de hasta 15 iteraciones para resolver llamadas
encadenadas a herramientas.

## Desplegar

```bash
supabase functions deploy ai-assistant --project-ref zkmbebybyyefmqcxjqrg
```

Antes de desplegar un cambio, respalda la versión viva — sigue siendo la única copia de
cualquier edición hecha directo en el dashboard:

```bash
supabase functions download ai-assistant --project-ref zkmbebybyyefmqcxjqrg
```
