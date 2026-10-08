# App Store · ficha de SistemasSI

Lo que va en App Store Connect para `com.sistemassi.app` (Apple ID 6820619261, equipo WF9U5S27H7).
Preparado el 08/10/2026 a partir de la ficha de Google Play (`docs/google-play/ficha.md`). Los textos,
la categoría, la clasificación por edad y los datos de contacto se cargaron con la API.

## Información de la app

| Campo | Valor |
|---|---|
| Nombre (máx. 30) | SistemasSI |
| Subtítulo (máx. 30) | Colaboradores de SI SOL |
| Idioma principal | Español (México) |
| Categoría principal | Negocios |
| Categoría secundaria | Productividad |
| Política de privacidad | https://sistemassi.com/privacidad |
| Derechos de contenido | No usa contenido de terceros |
| Clasificación por edad | Todo «No» / «Ninguno» (sin chat entre usuarios, sin contenido generado, sin web abierta) |

## Versión 1.0

| Campo | Valor |
|---|---|
| Texto promocional (máx. 170) | Checa tu asistencia, pide vacaciones, aparta citas y consulta el calendario de la empresa desde tu teléfono. |
| Palabras clave (máx. 100) | checador,asistencia,vacaciones,incidencias,colaboradores,calendario,directorio,inmobiliaria,empresa |
| URL de soporte | https://sistemassi.com/privacidad (trae domicilio y horario de atención) |
| URL de marketing | https://sistemassi.com |
| Copyright | 2026 SI SOL Inmobiliarias, S.A. de C.V. |
| Compilación | 2.4.5 (7) |
| Capturas iPhone 6.9" (1320 × 2868) | `capturas/iphone/`: menú, calendario, incidencias |
| Capturas iPad 13" (2064 × 2752) | `capturas/ipad/`: calendario, incidencias |

Las capturas se tomaron en el simulador con la cuenta de prueba, sin nombres de otros colaboradores
ni números de serie (por eso no van «Mi Perfil» ni el panel del día con organizador). El checador no
sirve en simulador: no hay cámara.

### Descripción (máx. 4000)

SistemasSI es la aplicación interna de SI SOL Inmobiliarias para sus colaboradores. El acceso es solo
con la cuenta que entrega la empresa.

Con SistemasSI puedes:

• Checar tu entrada y salida con foto y ubicación.
• Solicitar vacaciones e incidencias y consultar tu saldo de días.
• Ver tu perfil, tu equipo asignado y los accesos a los sistemas de trabajo.
• Leer los avisos y comunicados de la empresa.
• Consultar el directorio, el calendario y los documentos de Conocimientos.
• Apartar citas y recibir las invitaciones a eventos en tu calendario.
• Abrir las herramientas y los reportes de BI de tu área.
• Preguntar a Soli, el asistente de la empresa, sobre tus datos y procesos.

Las secciones que ves dependen de tu puesto y de los permisos que te asigne tu administrador.

## Información para la revisión de la app

Notas:

> La app es de uso interno de SI SOL Inmobiliarias: no permite crear cuentas, las da de alta la
> empresa. Inicia sesión con el usuario de prueba (rol de colaborador, sin permisos de
> administrador). El checador pide cámara y ubicación; se puede negar y el resto de la app sigue
> funcionando.

Usuario: `system.sisol@gmail.com`. **La contraseña la escribe el usuario directamente en App Store
Connect.** También hay que poner nombre, teléfono y correo de contacto.

## Privacidad de la app (no se puede con la API: va a mano en App Store Connect)

¿Recopila datos? **Sí.** Ningún dato se usa para rastrear (tracking) ni para publicidad. Todos van
**vinculados a la identidad** del usuario y con el propósito **Funcionalidad de la app** (la bitácora
de accesos además **Otros fines / seguridad**).

| Tipo (Apple) | Equivale a |
|---|---|
| Información de contacto → Nombre, Correo, Teléfono, Dirección física | Perfil del colaborador |
| Salud y ejercicio → Salud | Tipo de sangre, alergias, padecimientos (opcional) |
| Información financiera → Otra información financiera | Banco, cuenta, CLABE |
| Ubicación → Ubicación precisa y aproximada | Checador |
| Información confidencial | No (CURP, RFC y NSS van en «Otros tipos de datos») |
| Contenido del usuario → Fotos o videos | Foto del checador y de perfil |
| Contenido del usuario → Otro contenido del usuario | Preguntas a Soli, documentos que se suben |
| Identificadores → ID de usuario | Cuenta de Supabase |
| Uso → Interacción con el producto | Bitácora de accesos |
| Otros datos → Otros tipos de datos | CURP, RFC, NSS, fecha de nacimiento |

No se recopilan: contactos, historial de navegación o búsqueda, identificadores del dispositivo,
datos de compras, audio, diagnósticos de terceros.

## Distribución

Apple suele rechazar en la tienda pública las apps que solo sirven a los empleados de una empresa
(guía 3.2). Si la rechaza por eso, las salidas son: **distribución no listada** (la app no sale en
búsquedas y se instala con un enlace; se pide con un formulario a Apple) o **apps personalizadas**
por Apple Business Manager.

## Cuenta de prueba

El 08/10/2026 se le quitaron a `system.sisol@gmail.com` los permisos `show_avisos` y
`show_passwords` (podía crear y borrar avisos reales y entrar a la bóveda). Por eso las capturas ya no
muestran Avisos ni Contraseñas.
