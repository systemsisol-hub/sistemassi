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

**Desplegada como v14** el 2026-08-04, con el modo analista. La v13 pristina —la que existía sólo
en el despliegue antes de versionarla— quedó en el commit `e4c6554`, que es el punto de rollback
si el modo analista causara una regresión.

`verify_jwt: true`.

### Contrato

Request: `{ messages: [{ role, content }, ...], pbi_context?: { link_id, titulo } }`
Response: `{ text: string, structured: unknown }`

`structured` se llena con el resultado de la última herramienta ejecutada para que Flutter pinte
tablas. Ojo: `bi_page.dart` actualmente **ignora** ese campo; `ai_page.dart:202` sí lo lee.

### ⚠️ Modo analista: código muerto pendiente de retirar

La v16 desplegada todavía contiene el modo analista (`PBI_TOOLS`, `buildAnalistaSystemPrompt`,
`runPbiTool` y el manejo de `pbi_context`). **Ya no se usa:** ese trabajo se movió a
`bi-assistant` y `bi_page.dart` apunta ahí. Queda inalcanzable porque nadie envía `pbi_context`.

No se retiró todavía para no divergir el repo del despliegue: limpiarlo exige redesplegar, y por
MCP eso significa transcribir el archivo completo a mano. **Retirarlo en cuanto haya CLI de
Supabase instalado**, en un solo paso limpieza + despliegue.

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

## `bi-assistant`

Analista de reportes de Power BI. **Independiente de `ai-assistant`** y con su propio modelo.
Consumido por el panel lateral de `lib/bi_page.dart`. `verify_jwt: true`.

### Por qué está separado

Son dos productos sin nada en común salvo la autenticación. Mientras compartían función, cada
despliegue del analista ponía en riesgo al asistente de RH y obligaba a probar ambos. Ahora cada
uno tiene su prompt, sus herramientas, su modelo y su radio de impacto.

`bi_page.dart` elige el destino según la configuración del enlace: con dataset capturado va a
`bi-assistant`; sin dataset va a `ai-assistant`, que al menos explica el panel desde su
conocimiento general en lugar de fallar en cada consulta.

### Contrato

Request: `{ messages: [{ role, content }], link_id, titulo }`
Response: `{ text, structured }`

`link_id` es obligatorio: este asistente siempre opera sobre un reporte. El `titulo` es
cosmético para el prompt — la autorización sale del `link_id` que resuelve `pbi-query`.

Herramientas: `pbi_modelo` y `pbi_consultar`, ambas delegan en `pbi-query` reenviando el JWT del
usuario. **Ninguna herramienta de RH.**

### Proveedor de modelo — intercambiable por configuración

Se habla el formato de OpenAI (`/chat/completions` con `tools`), compatible con Cloudflare
Workers AI, Ollama y OpenAI. Cambiar de proveedor no requiere tocar código:

| Secreto | Valor para Cloudflare Workers AI |
|---|---|
| `AI_BASE_URL` | `https://api.cloudflare.com/client/v4/accounts/<account_id>/ai/v1` |
| `AI_API_KEY` | Token de API de Cloudflare con permiso de Workers AI |
| `AI_MODEL` | `@cf/openai/gpt-oss-120b` (default si se omite) |

`@cf/openai/gpt-oss-120b`: soporta function calling, 128k de contexto, $0.35 / $0.75 por millón
de tokens de entrada / salida. Otros modelos con function calling en el catálogo de Workers AI:
`@cf/meta/llama-3.3-70b-instruct-fp8-fast`, `nemotron-3-120b-a12b`, `kimi-k2.6`, `glm-5.2`.
**Verificar en el catálogo que el modelo soporte function calling** — sin eso el analista no
opera, porque todo su acceso a datos pasa por herramientas.

Diferencias respecto al formato de Ollama que usa `ai-assistant`, ya manejadas aquí: los
argumentos de las herramientas llegan como **texto JSON** y no como objeto, y las respuestas de
herramienta exigen `tool_call_id` para emparejarse con su llamada.

### Verificación de consistencia en el prompt

El prompt incluye una instrucción que salió de una falla real: si la suma de un desglose excede
el total sin agrupar, el asistente debe **reportar la inconsistencia** en lugar de presentar el
desglose como confiable. Y si el usuario compara con el panel y no coincide, debe considerar que
el panel aplica filtros que él no (banderas de exclusión, intercompañía, moneda) en vez de
insistir en que su cifra es la correcta.

## `pbi-query`

Ejecuta consultas DAX **de sólo lectura** contra un dataset de Power BI, para que el asistente
analice los reportes con cifras reales en lugar de inventarlas. `verify_jwt: true`.

> **Estado: desplegada (v1), sin credenciales.** Falta el service principal del tenant de
> SFKontrol (ver abajo). Sin los tres secretos `AZURE_*` responde `503` con un mensaje explícito,
> así que está desplegada pero inerte hasta que lleguen.

### Por qué el asistente no escribe DAX

La tabla de hechos es una **foto periódica**: guarda el saldo por fecha. Una consulta sin
contexto de fecha suma todas las fotos y cuenta el mismo saldo decenas de veces. Medido contra
el panel de PROVEEDORES:

| Consulta | Resultado |
|---|---|
| `[Suma Vencido]` sin filtro de periodo | `180,880,573.13` |
| Con `Año Slicer = "Actual"` y `Mes Slicer = "Actual"` | `22,088,254.08` ← coincide con el panel |

Un error de **8x** en cifras financieras, con dos decimales y tono de autoridad. Advertirlo en el
prompt no sirve: el modelo lo olvida cuando la conversación se alarga. Por eso el modelo manda
**parámetros** y el servidor arma el DAX, inyectando el filtro por construcción — el modelo no
puede omitirlo porque nunca toca la consulta.

### Contrato

Dos acciones. En ambas el cliente manda `link_id`, **nunca** el workspace ni el dataset: el
servidor los resuelve leyendo `powerbi_links`, así no se puede apuntar a un dataset arbitrario.

**`accion: "modelo"`** — qué se puede preguntar.
```jsonc
{ "link_id": "…", "accion": "modelo" }
// → { medidas: [...], columnas: ["Tabla[Columna]", ...], periodo_soportado: true }
```

**`accion: "consultar"`** — la consulta.
```jsonc
{
  "link_id":     "…",
  "medidas":     ["Suma Vencido", "Suma Por Vencer"],
  "agrupar_por": ["Cat Compañias[Compañia]"],   // opcional
  "periodo":     "actual",                      // o { "anio": "2025", "mes": "Jul" }
  "limite":      50
}
// → { rows, row_count, total_rows, truncated, report, consulta: { …, dax } }
```

Toda medida y columna se valida contra el esquema real del modelo antes de interpolarse. El
esquema se cachea 24 h en `pbi_model_cache`. Si el modelo no expone columnas de periodo, la
función responde `422` en lugar de devolver cifras infladas en silencio.

Se excluyen de la lista blanca las medidas del patrón TopN (`Vencido Top`, `Vencido Other`,
`TopN Selection`, `Rank`): sólo tienen sentido dentro de ese patrón y darían totales incompletos,
pero un modelo que las viera en la lista las elegiría sin dudar.

### Normalización de resultados

Dos correcciones sobre lo que devuelve Power BI:

- **Nulos omitidos.** La API omite los valores nulos, dejando renglones con llaves distintas —
  y una llave ausente se lee como cero. Se uniforman todas las llaves con `null` explícito.
- **Ruido de punto flotante.** `394238.77999999997` → `394238.78`. Redondeo a 6 decimales:
  limpia el ruido de IEEE-754 sin dañar porcentajes ni scores.
- **Porcentajes como fracción.** `% Vencido Critico` devuelve `0.9946…` donde el panel muestra
  `99.5%`. Un modelo que lea el número crudo reporta `0.99%` — error de **100x** que suena
  razonable. Por eso la respuesta incluye `formatos`, con el `FormatString` de cada medida
  **junto a las cifras**, no sólo en el prompt: una advertencia lejana se olvida, un campo
  adyacente al dato no. Si el modelo no expone `FormatString`, se deduce del prefijo `%` del
  nombre.

### Control de acceso

Tres capas:

1. Puerta de entrada igual que `ai-assistant`: `role == 'admin'` o `permissions->>'show_ai'`.
2. Acceso al enlace concreto: admin, dueño (`created_by`), o asignación en `powerbi_link_users`.
3. `executeQueries` sólo acepta DAX y no puede modificar el modelo ni los datos. Además se
   valida que la consulta inicie con `EVALUATE` o `DEFINE`.

Topes de respuesta: 500 filas y 100 KB serializados, recortando siempre con `truncated: true`
para que un recorte nunca se lea como un resultado completo.

### Variables de entorno

| Secreto | Valor / uso |
|---|---|
| `AZURE_TENANT_ID` | `9336ec0c-d302-4bdf-a668-c961ae49c541` — tenant de SFKontrol |
| `AZURE_CLIENT_ID` | `dc560542-a36e-4cd3-994e-c5d2a2ac5260` — app `SISOL Asistente BI` |
| `AZURE_CLIENT_SECRET` | Secreto de esa app — **sólo en Supabase, nunca en el repo** |

Tenant y client ID no son secretos: viajan en cada petición OAuth. Sólo el tercero lo es.

Flujo `client_credentials` contra `login.microsoftonline.com`, scope
`https://analysis.windows.net/powerbi/api/.default`. El token se cachea en el isolate.

### ⚠️ El client secret caduca: 3 de agosto de 2028

**Cuando caduque, el asistente dejará de leer cifras y el error dirá algo genérico de
autenticación contra Azure AD — no "tu secreto venció".** Es una falla que cuesta horas
diagnosticar si nadie sabe que existe una fecha. Por eso está aquí.

Rotación (también aplica si se sospecha que el secreto se filtró):

1. <https://entra.microsoft.com> → Registros de aplicaciones → `SISOL Asistente BI` →
   Certificados y secretos → **Nuevo secreto de cliente**, vigencia 24 meses.
2. Copiar el **Valor** en ese momento: sólo se muestra una vez.
3. Pegarlo en Supabase → Project Settings → Edge Functions → Secrets → `AZURE_CLIENT_SECRET`.
4. **Recién entonces** eliminar el secreto viejo en Entra.
5. Probar una consulta en el panel BI y actualizar la fecha en este archivo.

El orden de los pasos 3 y 4 importa: si se elimina el viejo antes de guardar el nuevo, el
asistente queda roto en la ventana intermedia. Guardar el secreto reinicia las Edge Functions,
así que su número de versión sube — eso es normal, no es un despliegue.

### Configuración del acceso en Power BI (ya hecha)

Workspace `SISOL_KBI` = `9d6868a1-526c-4aaf-9da9-0647e6cccef7`. La cuenta
`bisisol@enkontrolbi.com` es `Admin` del workspace y su único miembro humano, así que pudo
configurar todo sin intervención de SFKontrol:

- App registrada en Entra por esa misma cuenta, tipo "sólo este directorio".
- **Sin permisos de API en Entra.** Power BI no autoriza service principals por permisos de
  Entra sino por el rol en el workspace; agregarlos lleva a pedir consentimiento de
  administrador que no hace falta.
- App agregada al workspace como **Colaborador**. Visor no alcanza: `executeQueries` exige
  permiso Build sobre el dataset, y Colaborador lo incluye.

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
