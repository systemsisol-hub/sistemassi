# Google Play · ficha y formularios de SistemasSI

Lo que va en cada sección de Play Console para `com.sistemassi.app`. Preparado el 01/10/2026.
Las imágenes están en esta misma carpeta.

## Ficha de la tienda (Presencia en la tienda → Ficha principal)

| Campo | Valor |
|---|---|
| Nombre de la app (máx. 30) | SistemasSI |
| Descripción breve (máx. 80) | La herramienta interna de los colaboradores de SI SOL Inmobiliarias. |
| Ícono (512 × 512) | `icono-512.png` |
| Imagen destacada (1024 × 500) | `imagen-destacada-1024x500.png` |
| Capturas de teléfono (2 a 8) | `capturas/01-checador.png`, `capturas/02-herramientas.png` (Moto G6, 1080 × 2160, sin datos personales) |
| Categoría | Empresa |
| Correo de contacto | ave@sisol.com.mx |
| Sitio web | https://sistemassi.com |
| Política de privacidad | https://sistemassi.com/privacidad |

### Descripción completa (máx. 4000)

SistemasSI es la aplicación interna de SI SOL Inmobiliarias
para sus colaboradores. El acceso es solo con la cuenta que entrega la empresa.

Con SistemasSI puedes:

• Checar tu entrada y salida con foto y ubicación.
• Solicitar vacaciones e incidencias y consultar tu saldo de días.
• Ver tu perfil, tu equipo asignado y los accesos a los sistemas de trabajo.
• Leer los avisos y comunicados de la empresa.
• Consultar el directorio, el calendario y los documentos de Conocimientos.
• Abrir las herramientas y los reportes de BI de tu área.
• Preguntar a Soli, el asistente de la empresa, sobre tus datos y procesos.

Las secciones que ves dependen de tu puesto y de los permisos que te asigne tu administrador.

## Acceso a la app (Contenido de la app → Acceso a la app)

«Todas o algunas funciones están restringidas». Instrucciones para el revisor:

> La app es de uso interno: no permite crear cuentas. Inicia sesión con el usuario de prueba. El
> checador pide cámara y ubicación; puede negarse y el resto de la app sigue funcionando.

Usuario y contraseña: **los escribe el usuario directamente en Play Console** (cuenta de prueba sin
datos reales, p. ej. `revision.play@sisol.com.mx`).

## Seguridad de los datos (Contenido de la app → Seguridad de los datos)

- ¿Recopila o comparte datos? **Sí recopila.** No se comparten con terceros: los proveedores que
  procesan por cuenta de SI SOL (Supabase, Cloudflare, modelos de IA, Microsoft, Google, WhatsApp)
  no cuentan como «compartir» en la definición de Play.
- ¿Los datos se cifran en tránsito? **Sí.**
- ¿Se puede pedir que se borren? **Sí**, por el procedimiento de la sección 7 del aviso de privacidad.

| Tipo de dato (Play) | Recopilado | Para qué | ¿Obligatorio? |
|---|---|---|---|
| Ubicación aproximada y precisa | Sí | Funcionalidad de la app (checador) | Sí, para checar |
| Nombre, correo, ID de usuario, dirección, teléfono | Sí | Funcionalidad, administración de la cuenta | Sí |
| Otra información personal (CURP, RFC, NSS, fecha de nacimiento) | Sí | Funcionalidad | Sí |
| Otra información financiera (banco, cuenta, CLABE) | Sí | Funcionalidad | Sí |
| Información de salud (tipo de sangre, alergias, padecimientos) | Sí | Funcionalidad | No |
| Fotos | Sí | Funcionalidad (checador, foto de perfil) | Sí, para checar |
| Otros mensajes en la app (asistentes, comunicados) | Sí | Funcionalidad | No |
| Archivos y documentos | Sí | Funcionalidad | No |
| Actividad en la app (otras acciones: bitácora de accesos) | Sí | Seguridad, prevención de fraude | Sí |

No se recopilan: contactos del teléfono, historial web, identificadores del dispositivo para
publicidad, audio, calendario del teléfono.

## Otras declaraciones (Contenido de la app)

| Sección | Respuesta |
|---|---|
| Anuncios | No contiene anuncios |
| Público objetivo | 18 años o más |
| Clasificación de contenido | Cuestionario: categoría «Utilidad, productividad, comunicación u otra»; todo «No» |
| App gubernamental | No |
| Funciones financieras | No |
| App de salud | No |
| Noticias | No |
| Permiso de ubicación en segundo plano | No se usa |

## Versión

Paquete: `build/app/outputs/bundle/release/app-release.aab`, versión 2.4.2 (código 4), firmado con
la llave de subida de SI SOL. Al subir el primero, aceptar «Firma de apps de Play»: Google guarda la
llave con la que firma para los teléfonos y la nuestra queda como llave de subida.
