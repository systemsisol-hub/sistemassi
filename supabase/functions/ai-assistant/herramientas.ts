// El catalogo de herramientas tal como lo ve el modelo.
//
// Son declaraciones, sin logica: 220 lineas de esquemas JSON que antes ocupaban la novena parte del
// archivo y estorbaban para leer todo lo demas. Lo que HACE cada herramienta esta en ejecutar.ts.

export const ALL_TOOLS = [
  {
    type: "function",
    function: {
      name: "buscar_colaborador",
      description: "Busca colaboradores por CUALQUIER dato que te den: nombre, número de empleado, correo o UUID. Si sólo conocen un apellido o el nombre a medias, búscalo igual y ofrece los candidatos que salgan. Si tienes el nombre de una persona con apellidos, usa SIEMPRE nombre_completo: los apellidos viven en campos aparte, así que el nombre entero en `nombre` no encuentra nada. Por defecto NO filtra por status_rh — devuelve todos los registros (activos y bajas). Solo aplica status_rh si el usuario lo pide explícitamente. Admin ve datos completos; usuarios solo ven datos básicos.",
      parameters: {
        type: "object",
        properties: {
          numero_empleado: { type: "string", description: "Número de empleado. Se prueban variantes con y sin ceros iniciales." },
          nombre_completo: { type: "string", description: "Nombre y apellidos juntos, en cualquier orden: \"Enrique Ortega Gomez\". Cada palabra se busca en el nombre y en los dos apellidos. Es la forma preferida de buscar a una persona." },
          correo: { type: "string", description: "Correo, completo o un trozo. Busca en el de trabajo y en el personal." },
          id: { type: "string", description: "UUID del colaborador, si el usuario te lo dio tal cual." },
          nombre: { type: "string", description: "SOLO el nombre de pila, sin apellidos." },
          paterno: { type: "string", description: "SOLO el apellido paterno." },
          materno: { type: "string", description: "SOLO el apellido materno." },
          area: { type: "string" }, puesto: { type: "string" }, ubicacion: { type: "string" },
          status_rh: { type: "string", enum: ["ACTIVO","BAJA","CAMBIO","REINGRESO"], description: "SOLO usar si el usuario lo pide explícitamente. NO incluir en búsquedas normales." },
          status_sys: { type: "string", description: "SOLO admin. SOLO si el usuario lo pide." },
          limit: { type: "number" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "calcular_vacaciones",
      description: "Vacaciones de un colaborador: devuelve la TABLA de periodos, el total disponible Y sus ÚLTIMAS SOLICITUDES en una sola llamada, así que NO hace falta buscar las incidencias aparte. Calcula los días según su antigüedad y las incidencias aprobadas/pendientes. Usa esta herramienta cuando el usuario pregunte cuántos días de vacaciones tiene, cuántos ha usado, cuál es su saldo o quiera ver el historial de periodos de vacaciones. Devuelve la lista de periodos y el total; si en cambio devuelve `error`, es un FALLO y no un saldo de cero.",
      parameters: {
        type: "object",
        properties: {
          nombre_completo: { type: "string", description: "[Solo admin] Nombre y apellidos de la persona: \"Enrique Ortega Gomez\". ÚSALO ASÍ, en UNA sola llamada. No busques antes a la persona con buscar_colaborador: esta herramienta la identifica sola." },
          numero_empleado: { type: "string", description: "[Solo admin] Número de empleado, si lo tienes." },
          usuario_id: { type: "string", description: "[Solo admin] UUID del colaborador. Si se omite y no pasas nombre ni número, calcula para el usuario actual." },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "buscar_cumpleanos",
      description: "Cumpleaños de los colaboradores. Si no se pasa mes, usa el mes actual. ÚSALA SIEMPRE que se pregunte por cumpleaños: no tienes esos datos por otra vía y no puedes deducirlos.",
      parameters: {
        type: "object",
        properties: {
          mes: { type: "number", description: "Mes del 1 al 12. Si se omite, el mes en curso." },
          solo_esta_semana: { type: "boolean", description: "true para acotar a los 7 dias que empiezan el lunes de esta semana." },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "buscar_incidencias",
      description: "Busca incidencias. Usuarios no-admin solo ven las propias.",
      parameters: {
        type: "object",
        properties: {
          status:     { type: "string", enum: ["PENDIENTE","APROBADA","CANCELADA"] },
          periodo:    { type: "string" }, limit: { type: "number" },
          usuario_id: { type: "string", description: "[Solo admin] UUID del colaborador" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "buscar_inventario",
      description: "Busca equipos. Usuarios no-admin solo ven el equipo asignado a sí mismos.",
      parameters: {
        type: "object",
        properties: {
          tipo: { type: "string" }, ubicacion: { type: "string" }, marca: { type: "string" },
          condicion: { type: "string", enum: ["NUEVO","USADO","DAÑADO"] },
          usuario_id: { type: "string", description: "[Solo admin]" },
          sin_asignar: { type: "boolean", description: "[Solo admin]" },
          limit: { type: "number" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "buscar_contactos",
      description: "Busca contactos externos por nombre, empresa o correo.",
      parameters: {
        type: "object",
        properties: {
          nombre: { type: "string" }, empresa: { type: "string" },
          correo: { type: "string" }, limit: { type: "number" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "crear_incidencia",
      description: "Crea una incidencia/solicitud de vacaciones. Usuarios no-admin solo pueden crearla para sí mismos. Solo tras confirmación.",
      parameters: {
        type: "object",
        required: ["periodo","dias","fecha_inicio","fecha_fin","fecha_regreso"],
        properties: {
          usuario_id: { type: "string", description: "[Solo admin]" },
          nombre_usuario: { type: "string", description: "[Solo admin]" },
          periodo: { type: "string" }, dias: { type: "number" },
          fecha_inicio: { type: "string" }, fecha_fin: { type: "string" }, fecha_regreso: { type: "string" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "enviar_notificacion",
      description: "Envía una notificación push a un usuario. Solo tras confirmación.",
      parameters: {
        type: "object",
        required: ["user_id","title","message"],
        properties: {
          user_id: { type: "string" }, title: { type: "string" },
          message: { type: "string" }, type: { type: "string" },
        },
      },
    },
  },
  // ─ SOLO ADMIN ──────────────────────────────────────────────────────────
  {
    type: "function",
    function: {
      name: "crear_colaborador",
      description: "[ADMIN] Inserta un nuevo colaborador. Solo tras confirmación.",
      parameters: {
        type: "object",
        required: ["nombre","paterno","numero_empleado"],
        properties: {
          nombre: { type: "string" }, paterno: { type: "string" }, materno: { type: "string" },
          numero_empleado: { type: "string" }, area: { type: "string" }, puesto: { type: "string" },
          ubicacion: { type: "string" }, empresa: { type: "string" }, empresa_tipo: { type: "string" },
          status_rh: { type: "string" }, status_sys: { type: "string" },
          fecha_ingreso: { type: "string" }, celular: { type: "string" },
          correo_personal: { type: "string" }, jefe_inmediato: { type: "string" }, horario: { type: "string" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "actualizar_colaborador",
      description: "[ADMIN] Actualiza campos de un colaborador por UUID. Solo tras confirmación.",
      parameters: {
        type: "object",
        required: ["id"],
        properties: {
          id: { type: "string" },
          nombre: { type: "string" }, paterno: { type: "string" }, materno: { type: "string" },
          area: { type: "string" }, puesto: { type: "string" }, ubicacion: { type: "string" },
          empresa: { type: "string" }, status_rh: { type: "string" }, status_sys: { type: "string" },
          fecha_ingreso: { type: "string" }, fecha_baja: { type: "string" },
          fecha_reingreso: { type: "string" }, celular: { type: "string" },
          correo_personal: { type: "string" }, jefe_inmediato: { type: "string" },
          lider: { type: "string" }, gerente_regional: { type: "string" },
          director: { type: "string" }, observaciones: { type: "string" }, horario: { type: "string" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "actualizar_incidencia",
      description: "[ADMIN] Cambia el estatus u otros datos de una incidencia. Solo tras confirmación.",
      parameters: {
        type: "object",
        required: ["id"],
        properties: {
          id: { type: "string" }, status: { type: "string", enum: ["PENDIENTE","APROBADA","CANCELADA"] },
          dias: { type: "number" }, periodo: { type: "string" },
          fecha_inicio: { type: "string" }, fecha_fin: { type: "string" }, fecha_regreso: { type: "string" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "actualizar_inventario",
      description: "[ADMIN] Asigna o libera un equipo. Solo tras confirmación.",
      parameters: {
        type: "object",
        required: ["id"],
        properties: {
          id: { type: "string" }, usuario_id: { type: "string" }, usuario_nombre: { type: "string" },
          ubicacion: { type: "string" }, condicion: { type: "string" }, observaciones: { type: "string" },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "gestionar_contacto",
      description: "[ADMIN] Crea o actualiza un contacto externo. Solo tras confirmación.",
      parameters: {
        type: "object",
        required: ["nombre"],
        properties: {
          id: { type: "string" }, nombre: { type: "string" }, empresa: { type: "string" },
          correo: { type: "string" }, telefono: { type: "string" }, otro: { type: "string" },
        },
      },
    },
  },
];

export type ToolInput = Record<string, unknown>;
