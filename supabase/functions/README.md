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

## `pbi-query`

Ejecuta consultas DAX **de sólo lectura** contra un dataset de Power BI, para que el asistente
analice los reportes con cifras reales en lugar de inventarlas. `verify_jwt: true`.

> **Estado: escrita pero NO desplegada.** Falta la credencial de servicio del tenant de
> SFKontrol (ver abajo). Sin los tres secretos `AZURE_*` responde `503` con un mensaje explícito.

### Contrato

Request: `{ link_id: string, dax: string }`
Response: `{ rows, row_count, total_rows, truncated, report: { id, title } }`

El cliente **nunca** manda workspace ni dataset: manda `link_id` y el servidor resuelve el par
leyendo `powerbi_links`. Así no se puede apuntar a un dataset arbitrario.

### Control de acceso

Tres capas:

1. Puerta de entrada igual que `ai-assistant`: `role == 'admin'` o `permissions->>'show_ai'`.
2. Acceso al enlace concreto: admin, dueño (`created_by`), o asignación en `powerbi_link_users`.
3. `executeQueries` sólo acepta DAX y no puede modificar el modelo ni los datos. Además se
   valida que la consulta inicie con `EVALUATE` o `DEFINE`.

Topes de respuesta: 500 filas y 100 KB serializados, recortando siempre con `truncated: true`
para que un recorte nunca se lea como un resultado completo.

### Variables de entorno

| Secreto | Uso |
|---|---|
| `AZURE_TENANT_ID` | Tenant de SFKontrol (dueño del workspace) |
| `AZURE_CLIENT_ID` | App registrada en su Entra ID |
| `AZURE_CLIENT_SECRET` | Secreto de esa app — **sólo servidor** |

Flujo `client_credentials` contra `login.microsoftonline.com`, scope
`https://analysis.windows.net/powerbi/api/.default`. El token se cachea en el isolate.

### Configuración por reporte

Cada fila de `powerbi_links` necesita `pbi_workspace_id` y `pbi_dataset_id`
(ver `supabase/migrations/20260804120000_pbi_dataset_fields.sql`).

Workspace confirmado: `SISOL_KBI` = `9d6868a1-526c-4aaf-9da9-0647e6cccef7`.

La asignación reporte → dataset debe salir de `GET /groups/{groupId}/reports`. **No deducirla
del nombre:** hay dos datasets de proveedores (`PROVEEDORES` y `PROVEEDORES - SISOL`) y un mismo
modelo puede alimentar varios reportes.

## Desplegar

```bash
supabase functions deploy ai-assistant --project-ref zkmbebybyyefmqcxjqrg
```

Antes de desplegar un cambio, respalda la versión viva — sigue siendo la única copia de
cualquier edición hecha directo en el dashboard:

```bash
supabase functions download ai-assistant --project-ref zkmbebybyyefmqcxjqrg
```
