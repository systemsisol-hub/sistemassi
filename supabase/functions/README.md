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

### Alcance

**Sólo RH.** Todo lo de Power BI vive en `bi-assistant`. Esta función no conoce `pbi_context` ni
tiene herramientas de BI: se retiraron al separar los asistentes, restaurando el archivo desde la
v13 pristina. Un cliente viejo que mande `pbi_context` simplemente lo ve ignorado.

### Permisos

**Entrar:** `profiles.role == 'admin'` **o** `profiles.permissions->>'show_ai' == true`. En
cualquier otro caso, `403 Forbidden`.

**Qué puede hacer una vez dentro:** los **mismos accesos que se asignan en la página de Usuarios**.
Antes `show_ai` era llave maestra de lectura — quien lo tuviera podía pedirle el directorio
completo, 2488 personas con teléfono, aunque no pudiera abrir la página de Colaboradores.

Se conservan los dos ejes que ya usan las páginas de Flutter: **`show_*` decide leer, `role` decide
escribir.** Colgar las escrituras del `show_*` ampliaría permisos en vez de restringirlos:
cualquiera con `show_incidencias` podría aprobar su propia solicitud de vacaciones.

Son **12 herramientas** (`ALL_TOOLS`):

| Herramienta | Permiso | Además admin |
|---|---|:--:|
| `buscar_colaborador` | `show_cssi` | |
| `crear_colaborador` | `show_cssi` | ✓ |
| `actualizar_colaborador` | `show_cssi` | ✓ |
| `buscar_incidencias` | `show_incidencias` | |
| `crear_incidencia` | `show_incidencias` | |
| `actualizar_incidencia` | `show_incidencias` | ✓ |
| `calcular_vacaciones` | `show_incidencias` | |
| `buscar_inventario` | `show_issi` | |
| `actualizar_inventario` | `show_issi` | ✓ |
| `buscar_contactos` | `show_external_contacts` | |
| `gestionar_contacto` | `show_external_contacts` | ✓ |
| `enviar_notificacion` | — (no tiene página) | |

Se aplica **también a los administradores**, a propósito: la página de Usuarios es la única fuente
de verdad, y a un admin al que le falte un acceso se le concede ahí con un interruptor, sin volver
a desplegar.

Tres capas, y la segunda es la que cuenta:

1. La lista de herramientas que recibe el modelo se filtra: no sabe que existe lo que no puede usar.
2. `runTool` lo **vuelve a comprobar**. Si el modelo se inventa una llamada, se bloquea igual.
   Filtrar la lista es comodidad; esto es el control.
3. Columnas y filas: un usuario normal ve 15 campos del colaborador y no 22, y las lecturas de
   incidencias e inventario se fuerzan a `usuario_id = <el propio>`. `show_*` no dice «las tuyas» o
   «las de todos», así que ese alcance se decide por herramienta.

El system prompt se **arma con el acceso real** (`construirPrompt`). Los dos textos fijos anteriores
afirmaban cosas que podían ser falsas —el de admin decía «acceso completo»— y un modelo que cree
tener un acceso que no tiene se lo ofrece al usuario y luego falla.

### Los esquemas de las herramientas no son validación

Un esquema JSON es una indicación al modelo. Si el modelo emite una clave extra, un
`insert({ ...input })` la mandaba tal cual a la base — incluido `role`. Y como el asistente acepta
archivos adjuntos **cuyo contenido entra en la conversación**, un archivo de origen externo podía
intentar aprovecharlo.

`CAMPOS_ESCRITURA` + `soloCamposPermitidos()` filtran los seis caminos de escritura contra una
lista blanca por herramienta, y **registran lo descartado** con `console.warn`: un intento de
escribir `role` queda en los logs. El prompt además instruye a tratar los adjuntos como datos y
nunca como instrucciones.

`crear_incidencia` excluye a propósito `usuario_id` y `nombre_usuario` de su lista blanca: se
fuerzan aparte, después del spread, para que el modelo no pueda elegir a nombre de quién se crea.

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

### Qué columnas se exponen para agrupar, y por qué tan pocas

Sólo se ofrecen columnas que de verdad sirven para desglosar. Tres criterios:

1. **Nada numérico ni booleano** (por `DataType`): agrupar por `Saldo`, `Vencido`, `Pesos_*`,
   `Dias` o una bandera `Bit *` no tiene sentido — son magnitudes, no categorías.
2. **Sin las columnas de periodo** (`Año Slicer`, `Mes Slicer`): las administra el servidor por
   parámetro. Agrupar por ellas daría un solo renglón.
3. **Sin copias en la tabla de hechos de algo que ya existe como dimensión.** Se prefiere la
   dimensión.

El tercer criterio cierra una falla real: con un modelo pequeño, preguntar por proveedores
devolvía cifras donde **dos proveedores solos excedían el total de la empresa**. La causa fue que
agrupó por `Indicadores Proveedores[Proveedor]` —la copia en el hecho— en lugar de
`Cat Proveedores[Proveedor]`. Ambas estaban en la lista blanca y ambas sonaban correctas.

Que un modelo mejor acierte no era suficiente: cambiar `AI_MODEL` por algo más barato habría
reintroducido el problema en silencio. Ahora la copia **no se expone**, así que elegir mal deja
de ser posible.

Efecto secundario bienvenido: el catálogo era ~150 columnas y una cuarta parte de los tokens de
entrada de cada pregunta, así que el recorte también baja el consumo.

`SCHEMA_VERSION` invalida los esquemas ya cacheados al cambiar estos criterios — sin eso habría
que vaciar `pbi_model_cache` a mano en cada despliegue.

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

## `checador-import`

Importa el reporte de checadas que exporta **appchecar.com**, la aplicación externa que hace de
checador real. Consumido por `lib/checador_dashboard.dart`, dentro de la página de Asistencia.

`verify_jwt: true`.

### Contrato

Request: `{ archivo?: string, contenido_base64: string }`

Response:

```json
{
  "ok": true,
  "importacion_id": "...",
  "periodo": { "inicio": "2026-07-16", "fin": "2026-07-31", "dias": 15 },
  "filas": { "leidas": 877, "nuevas": 877, "actualizadas": 0, "omitidas": 0 },
  "registros": { "entradas": 509, "salidas": 368 },
  "empleados": 44,
  "sin_empatar": { "empleados": [], "horarios": [] }
}
```

`sin_empatar` es la parte que importa: un import que sólo dijera "listo" escondería a un empleado
nuevo o a un horario renombrado en appchecar, y esas filas quedan fuera del cálculo de
puntualidad. También se persiste en `checador_importaciones`.

### Permisos

**Sólo `profiles.role == 'admin'`.** Cargar un reporte reescribe el histórico de asistencia de
toda la empresa, así que se usa el mismo criterio que la escritura en `schedules`, no el permiso
de ver la página.

### Lo que el archivo real enseñó

Estas seis cosas están verificadas contra `Checador 07_16_2026 al 07_31_2026.xls` (877 filas) y
son la razón de que el parser sea como es:

1. **El `.xls` es HTML**, no Excel: BOM UTF-8 y un `<table>`. `Excel.decodeBytes` falla con él.

2. **La columna `Diferencia` no sirve para saber quién llegó tarde.** Es un valor absoluto sin
   signo: `"4 min"` se ve idéntico si la persona llegó 4 minutos antes o 4 minutos tarde. El
   retardo se calcula en la vista `checador_entradas` contra nuestra tabla `schedules`.

3. **El signo sí viaja en el reporte, pero en el color de la celda:** verde `#4fc725` a tiempo,
   rojo `#ee6082` fuera de tiempo, negro con `---` sin referencia. Se guarda en
   `retardo_reportado`. Se clasifica comparando rojo contra verde y no por el hex exacto, para
   que siga funcionando si appchecar ajusta su paleta.

4. **Los ceros iniciales del número de empleado son inconsistentes en ambos lados:** el reporte
   trae `0162` y `170`; `profiles` tiene 1000 de 2488 con ceros. Se normalizan los dos. Verificado
   que quitar ceros no crea colisiones: los 2488 perfiles siguen siendo distintos.

5. **Tres de los 18 nombres de horario traen espacios dobles** (`'Punta Pacifico  L-S'`). Sin
   normalizar espacios esos tres no se unen; normalizando empatan 18/18, cada uno a un solo
   horario.

6. **Hay un empleado sin número** (Moises Caldera Meza, 26 registros). Por eso la identidad de la
   llave única cae al nombre — ver la columna generada `clave` en la migración
   `20260805200000_checador_registros.sql`. Sin eso, dos personas sin número que checaran a la
   misma hora se fundirían en una sola fila, en silencio. El `profile_id` se resuelve por número
   y, si falta, por nombre completo exacto **sólo si es único**: `MOISES` aparece 5 veces en
   `profiles`, así que emparejar por nombre de pila asignaría checadas a otra persona.

Las columnas se mapean **por nombre de encabezado, no por posición**: un parser posicional leería
los datos corridos, sin fallar, si appchecar insertara una columna.

### Por qué las cifras no coinciden con appchecar

appchecar marcó **104** de las 506 primeras entradas del periodo de julio como fuera de tiempo; el
cálculo contra nuestros horarios da un número cercano pero no idéntico. La causa es que cada
sistema tiene su propia configuración de horarios y ya difieren en ~3% de los casos. El dashboard
muestra las dos cifras juntas para que la diferencia sea visible en lugar de parecer un error.

## Desplegar

Requiere `supabase login` una vez (es interactivo, abre el navegador). **Correr desde la raíz del
repo**: el CLI busca `supabase/functions/<slug>/index.ts` relativo al directorio actual, y desde
otro lugar falla con "Entrypoint path does not exist".

```bash
supabase functions deploy bi-assistant --project-ref zkmbebybyyefmqcxjqrg
```

El aviso "Docker is not running" es inofensivo: Docker sólo hace falta para desarrollo local.

### Verificar que se desplegó lo que se pretendía

Descargar a un directorio aparte y comparar. Vale la pena porque un despliegue puede quedar
desfasado del repo sin que nada lo advierta:

```bash
mkdir /tmp/verify && cd /tmp/verify
supabase functions download bi-assistant --project-ref zkmbebybyyefmqcxjqrg
diff supabase/functions/bi-assistant/index.ts <repo>/supabase/functions/bi-assistant/index.ts
```

Cuidado con descargar desde la raíz del repo: sobreescribe el archivo local.

### Sobre los números de versión

El contador de versión sube también al **guardar secretos**, no sólo al desplegar: guardar un
secreto reinicia las funciones. Por eso el `version` del dashboard puede ir muy por delante de la
cantidad de despliegues reales. Para saber qué código está corriendo, compara el `ezbr_sha256` o
descarga y haz diff — no te fíes del número.
