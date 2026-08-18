// Quien puede usar que. El control de acceso del asistente, completo y en un solo archivo.
//
// Se lee junto con la pagina de Usuarios: los permisos que se asignan ahi son los que se exigen
// aqui. `QUE_HACE` es lo que muestra la pagina de Config. IA, y por eso esta al lado de los
// permisos y no en el catalogo de herramientas: quien cambie un permiso ve la descripcion al lado.

import { ToolInput } from "./herramientas.ts";

// Lo que ve un usuario normal: datos de directorio. Incluye teléfono fijo, celular y el correo de
// trabajo (`mail_user` y `email` guardan el mismo valor; se piden los dos porque la cobertura de
// cada uno difiere en una docena de perfiles). NO incluye `correo_personal`, ni fecha de ingreso,
// status, foto ni horario, que sí ve un administrador.
export const USER_COLABORADOR_FIELDS =
  "numero_empleado,nombre,paterno,materno,telefono,celular,mail_user,email," +
  "empresa_tipo,area,puesto,ubicacion,empresa,jefe_inmediato,lider,gerente_regional,director";

export const ADMIN_COLABORADOR_FIELDS =
  "id,numero_empleado,nombre,paterno,materno,area,puesto,ubicacion,empresa,empresa_tipo," +
  "status_rh,status_sys,celular,telefono,correo_personal,mail_user,fecha_ingreso," +
  "jefe_inmediato,lider,gerente_regional,director,foto_url,horario";

// Sólo escritura fuerte. La lista blanca de lo que puede usar un usuario normal ya no existe:
// la resuelve `puedeUsarHerramienta` a partir de los permisos de la página de Usuarios. Tener las
// dos reglas a la vez era garantía de que se separaran con el tiempo.
export const ADMIN_ONLY_TOOLS = new Set([
  "crear_colaborador", "actualizar_colaborador", "actualizar_incidencia",
  "actualizar_inventario", "gestionar_contacto",
]);

// ─── Permisos por herramienta ────────────────────────────────────────────────
//
// El asistente respeta los mismos accesos que se asignan en la página de Usuarios. Antes
// `show_ai` era llave maestra de lectura: quien lo tuviera podía pedirle el directorio completo
// —2488 personas con teléfono— aunque no pudiera abrir la página de Colaboradores.
//
// Se mantienen los dos ejes que ya usan las páginas (ver issi_page.dart y colaborador_page.dart):
// el permiso `show_*` decide si se PUEDE VER, y `role == 'admin'` decide si se PUEDE ESCRIBIR.
// Colgar las escrituras del `show_*` ampliaría permisos en lugar de restringirlos: cualquiera con
// `show_incidencias` podría aprobar su propia solicitud de vacaciones.
//
// Dos herramientas no aparecen aquí, y por razones distintas:
//
// - `enviar_notificacion` no corresponde a ninguna página.
// - `buscar_colaborador` es consulta de DIRECTORIO, que es una operación de menor privilegio que
//   ver la página de Colaboradores. Atarla a `show_cssi` dejó a un gerente sin poder preguntar
//   quién lleva Recursos Humanos, y concederle el permiso le habría abierto los expedientes
//   completos: mucho más de lo que necesitaba. Los campos siguen recortados por rol —un usuario
//   normal ve 15 y un administrador 22— así que lo privado queda fuera igual.
//
// Crear y actualizar colaboradores SÍ siguen pidiendo `show_cssi` y administrador.
export const PERMISO_POR_HERRAMIENTA: Record<string, string> = {
  crear_colaborador:      "show_cssi",
  actualizar_colaborador: "show_cssi",
  buscar_incidencias:     "show_incidencias",
  crear_incidencia:       "show_incidencias",
  actualizar_incidencia:  "show_incidencias",
  calcular_vacaciones:    "show_incidencias",
  buscar_inventario:      "show_issi",
  actualizar_inventario:  "show_issi",
  buscar_contactos:       "show_external_contacts",
  gestionar_contacto:     "show_external_contacts",
  // Mismo permiso que abre la pagina de Asistencia. Un usuario normal solo ve lo suyo; el filtro por
  // `profile_id` lo pone la herramienta, no el modelo.
  buscar_asistencia:      "show_asistencia",
};

/// Qué hace cada herramienta, en una frase y en español.
///
/// Sirve para la página de configuración: la descripción que lleva cada herramienta en `ALL_TOOLS`
/// está escrita PARA EL MODELO —con mayúsculas, advertencias y detalles de parámetros— y no se lee
/// bien en pantalla. Estas son para una persona.
export const QUE_HACE: Record<string, string> = {
  buscar_colaborador:     "Buscar personas por nombre, número de empleado, correo o UUID",
  calcular_vacaciones:    "Días de vacaciones disponibles, la tabla de periodos y las últimas solicitudes",
  buscar_cumpleanos:      "Cumpleaños del mes o de la semana",
  buscar_incidencias:     "Consultar solicitudes de vacaciones e incidencias",
  buscar_inventario:      "Consultar equipo del inventario",
  buscar_contactos:       "Consultar contactos externos",
  crear_incidencia:       "Crear una solicitud de vacaciones",
  enviar_notificacion:    "Enviar una notificación a un usuario",
  crear_colaborador:      "Dar de alta un colaborador",
  actualizar_colaborador: "Modificar los datos de un colaborador",
  actualizar_incidencia:  "Cambiar el estatus u otros datos de una incidencia",
  actualizar_inventario:  "Asignar o liberar un equipo",
  gestionar_contacto:     "Crear o modificar un contacto externo",
  buscar_conocimiento:    "Leer politicas, manuales y articulos de la base de Conocimientos",
  buscar_asistencia:      "Faltas, retardos y puntualidad, con las mismas cifras que la pagina de Asistencia",
};

/// Las preguntas que se resuelven SIN pasar por el modelo, para mostrarlas en la página.
///
/// Importan porque explican por qué algunas respuestas son instantáneas y por qué siguen funcionando
/// cuando el proveedor del modelo está caído.
export const VIAS_DIRECTAS = [
  { pregunta: "«cuántas vacaciones tengo»", resuelve: "Tus días, con la tabla de periodos y tu última solicitud" },
  { pregunta: "«las vacaciones de mi jefe»", resuelve: "Toma el nombre de `jefe_inmediato` de tu perfil. Solo administradores" },
  { pregunta: "«cumpleaños de este mes» / «quién cumple esta semana»", resuelve: "La lista, con el mismo filtro que la página de Social" },
  { pregunta: "«qué equipo tengo asignado»", resuelve: "Los equipos que están a tu nombre en el inventario, con su serie" },
  { pregunta: "«incidencias de <persona>» / «mis incidencias»", resuelve: "El historial con sus fechas de salida, regreso, días y periodo" },
  { pregunta: "un número de empleado o un UUID a secas", resuelve: "La ficha de esa persona, con su nombre y su número del mismo registro" },
  { pregunta: "«faltas de <persona>» / «mis faltas»", resuelve: "Faltas, justificados, retardos y días de descuento, con los días listados" },
];

export type Permisos = Record<string, unknown>;

/// Quién está usando el asistente. Se inyecta en el prompt para que pueda tratarlo por su nombre y
/// entender a quién se refiere cuando dice «mis vacaciones».
export interface Identidad {
  nombreCompleto: string;
  nombrePila: string;
  puesto: string | null;
  area: string | null;
  numeroEmpleado: string | null;
}

/// Se aplica también a los administradores, a propósito: el objetivo es que la página de Usuarios
/// sea la única fuente de verdad. Si a un admin le falta un acceso, se le concede ahí con un
/// interruptor, sin volver a desplegar nada.
export function puedeUsarHerramienta(
  nombre: string,
  esAdmin: boolean,
  permisos: Permisos,
): boolean {
  if (ADMIN_ONLY_TOOLS.has(nombre) && !esAdmin) return false;
  const requerido = PERMISO_POR_HERRAMIENTA[nombre];
  if (!requerido) return true;
  return permisos[requerido] === true;
}

// ─── Campos que cada herramienta puede escribir ──────────────────────────────
//
// Los esquemas JSON de las herramientas son una INDICACIÓN al modelo, no una validación: si el
// modelo emite una clave extra, un `insert({ ...input })` la mandaba tal cual a la base. Y como el
// asistente acepta archivos adjuntos cuyo contenido entra en la conversación, un archivo de origen
// externo podía intentar que escribiera campos fuera del esquema — `role: "admin"`, por ejemplo.
//
// Con esto el esquema pasa de sugerencia a validación. Las listas replican las `properties` de
// cada herramienta; `id` va aparte porque se usa en el WHERE, no en el SET.
const CAMPOS_ESCRITURA: Record<string, Set<string>> = {
  crear_colaborador: new Set([
    "nombre", "paterno", "materno", "numero_empleado", "area", "puesto", "ubicacion",
    "empresa", "empresa_tipo", "status_rh", "status_sys", "fecha_ingreso", "celular",
    "correo_personal", "jefe_inmediato", "horario",
  ]),
  actualizar_colaborador: new Set([
    "nombre", "paterno", "materno", "area", "puesto", "ubicacion", "empresa",
    "status_rh", "status_sys", "fecha_ingreso", "fecha_baja", "fecha_reingreso",
    "celular", "correo_personal", "jefe_inmediato", "lider", "gerente_regional",
    "director", "observaciones", "horario",
  ]),
  crear_incidencia: new Set([
    "periodo", "dias", "fecha_inicio", "fecha_fin", "fecha_regreso",
  ]),
  actualizar_incidencia: new Set([
    "status", "dias", "periodo", "fecha_inicio", "fecha_fin", "fecha_regreso",
  ]),
  actualizar_inventario: new Set([
    "usuario_id", "usuario_nombre", "ubicacion", "condicion", "observaciones",
  ]),
  gestionar_contacto: new Set([
    "nombre", "empresa", "correo", "telefono", "otro",
  ]),
};

/// Deja pasar sólo los campos declarados. Lo descartado se registra: un intento de escribir
/// `role` o `permissions` es justo lo que conviene poder encontrar después en los logs.
export function soloCamposPermitidos(nombre: string, entrada: ToolInput): ToolInput {
  const permitidos = CAMPOS_ESCRITURA[nombre];
  if (!permitidos) return entrada;
  const salida: ToolInput = {};
  const descartados: string[] = [];
  for (const [clave, valor] of Object.entries(entrada)) {
    if (permitidos.has(clave)) {
      salida[clave] = valor;
    } else if (clave !== "id") {
      descartados.push(clave);
    }
  }
  if (descartados.length > 0) {
    console.warn(
      `ai-assistant: ${nombre} intentó escribir campos no declarados: ${descartados.join(", ")}`,
    );
  }
  return salida;
}
