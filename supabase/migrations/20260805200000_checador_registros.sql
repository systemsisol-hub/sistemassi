-- Registros del checador externo (appchecar.com) y el cálculo de puntualidad.
--
-- El checador real es una aplicación de terceros. Exporta un reporte por periodo que hasta ahora
-- sólo se podía consultar abriendo el archivo. Estas tablas guardan ese reporte para poder
-- construir un dashboard sobre él.
--
-- Nada de esto reemplaza al checador: es sólo lectura del reporte que appchecar ya produjo.

CREATE TABLE IF NOT EXISTS checador_importaciones (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  archivo        text,
  fecha_inicio   date NOT NULL,
  fecha_fin      date NOT NULL,
  filas_leidas   int  NOT NULL DEFAULT 0,
  filas_nuevas   int  NOT NULL DEFAULT 0,
  importado_en   timestamptz NOT NULL DEFAULT now(),
  importado_por  uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  -- Lo que no se pudo resolver, tal como llegó. Es el dato que permite notar un empleado nuevo
  -- o un horario renombrado en appchecar; un import que sólo dijera "listo" lo escondería.
  sin_empatar    jsonb NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE checador_importaciones IS
  'Bitácora de cada carga del reporte de appchecar. El periodo se deriva de los datos, no del nombre del archivo.';

CREATE TABLE IF NOT EXISTS checador_registros (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Se guarda ya normalizado (sin ceros iniciales). En el reporte 42 de 43 números coinciden con
  -- profiles.numero_empleado tal cual, pero uno trae ceros al frente: sin normalizar, ese
  -- empleado quedaría fuera del dashboard en silencio.
  numero_empleado text NOT NULL,
  nombre_reporte  text,
  -- Nullable a propósito: si appchecar tiene un empleado que aún no está en profiles, el registro
  -- se guarda igual y aparece en `sin_empatar`. Perder la fila sería peor que no poder unirla.
  profile_id      uuid REFERENCES profiles(id) ON DELETE SET NULL,

  fecha           date NOT NULL,
  tipo            text NOT NULL CHECK (tipo IN ('Entrada', 'Salida')),
  hora            time NOT NULL,

  -- El texto crudo de la columna Diferencia, SIN interpretar. Es un valor absoluto: "4 min" se ve
  -- idéntico si la persona llegó 4 minutos antes o 4 minutos tarde. Se conserva como texto para
  -- que nadie lo confunda con un número con signo.
  diferencia_reportada text,
  -- El signo que le falta al texto sí viaja en el reporte, pero en el color de la celda: verde
  -- (#4fc725) a tiempo, rojo (#ee6082) fuera de tiempo, negro con "---" sin referencia. Se guarda
  -- para poder contrastar el veredicto de appchecar contra el nuestro, no para sustituirlo.
  retardo_reportado boolean,

  horario_nombre  text,
  horario_id      uuid REFERENCES schedules(id) ON DELETE SET NULL,

  departamento    text,
  puesto          text,
  direccion       text,
  sucursal        text,
  registro_con    text,

  importacion_id  uuid REFERENCES checador_importaciones(id) ON DELETE SET NULL,

  -- La identidad para efectos de la llave única. appchecar exporta al menos un empleado sin
  -- número (Moises Caldera Meza, 26 registros del periodo de julio), y con la llave puesta sobre
  -- `numero_empleado` dos personas distintas sin número que checaran a la misma hora se fundirían
  -- en una sola fila, en silencio. Cae al nombre cuando falta el número.
  clave text GENERATED ALWAYS AS (
    CASE
      WHEN COALESCE(numero_empleado, '') = ''
        THEN 'nombre:' || lower(regexp_replace(COALESCE(nombre_reporte, ''), '\s+', ' ', 'g'))
      ELSE 'num:' || numero_empleado
    END
  ) STORED,

  -- Volver a subir un periodo que se traslapa con otro debe actualizar, no duplicar. Incluye
  -- `hora` porque una misma persona sí checa dos veces el mismo día en algunos casos reales, y
  -- esas checadas son registros distintos, no un duplicado.
  CONSTRAINT checador_registros_identidad_key UNIQUE (clave, fecha, tipo, hora)
);

CREATE INDEX IF NOT EXISTS checador_registros_fecha_idx      ON checador_registros (fecha);
CREATE INDEX IF NOT EXISTS checador_registros_profile_idx    ON checador_registros (profile_id);
CREATE INDEX IF NOT EXISTS checador_registros_tipo_fecha_idx ON checador_registros (tipo, fecha);

-- Vista de puntualidad. El retardo se calcula aquí, contra nuestra tabla `schedules`, y no se lee
-- del reporte: la columna Diferencia de appchecar no distingue llegar antes de llegar tarde.
--
-- Vivir en una vista tiene una consecuencia deseable: corregir un horario recalcula el histórico
-- completo, sin volver a importar nada.
--
-- security_invoker hace que las RLS de las tablas de origen apliquen al usuario que consulta, en
-- lugar de a quien creó la vista.
CREATE OR REPLACE VIEW checador_entradas
WITH (security_invoker = true) AS
WITH primera_del_dia AS (
  -- La primera checada del día es la llegada. Con doble checada, las posteriores no dicen nada
  -- sobre puntualidad y contarlas inflaría los retardos.
  --
  -- Agrupa por `clave` y no por `numero_empleado` por la misma razón que la llave única: con el
  -- número vacío, dos personas sin número quedarían fundidas en una sola fila por día.
  SELECT DISTINCT ON (r.clave, r.fecha) r.*
  FROM checador_registros r
  WHERE r.tipo = 'Entrada'
  ORDER BY r.clave, r.fecha, r.hora
)
SELECT
  e.id,
  e.clave,
  e.numero_empleado,
  e.nombre_reporte,
  e.profile_id,
  e.departamento,
  e.sucursal,
  e.fecha,
  e.hora,
  e.horario_id,
  e.horario_nombre,
  e.diferencia_reportada,
  e.retardo_reportado,
  regla.hora_entrada,
  regla.tol                                                   AS tolerancia_min,
  regla.hora_entrada + make_interval(mins => regla.tol)       AS limite,
  -- NULL, no 0: sin regla para ese día no es que llegara a tiempo, es que no sabemos.
  CASE WHEN regla.hora_entrada IS NULL THEN NULL ELSE
    GREATEST(0, CEIL(EXTRACT(EPOCH FROM (
      e.hora - (regla.hora_entrada + make_interval(mins => regla.tol))
    )) / 60.0))::int
  END AS minutos_retardo,
  CASE WHEN regla.hora_entrada IS NULL THEN NULL ELSE
    e.hora > regla.hora_entrada + make_interval(mins => regla.tol)
  END AS es_retardo
FROM primera_del_dia e
LEFT JOIN schedules s ON s.id = e.horario_id
LEFT JOIN LATERAL (
  -- Conveniente: nuestro `day` en rules (0 = domingo) coincide exactamente con extract(dow).
  SELECT (regla_json->>'time')::time            AS hora_entrada,
         COALESCE((regla_json->>'tol')::int, 0) AS tol
  FROM jsonb_array_elements(s.rules) AS regla_json
  WHERE regla_json->>'type' = 'ENTRADA'
    AND (regla_json->>'day')::int = EXTRACT(DOW FROM e.fecha)::int
  ORDER BY (regla_json->>'time')::time
  LIMIT 1
) regla ON true;

COMMENT ON VIEW checador_entradas IS
  'Primera entrada de cada empleado por día, con el retardo calculado contra schedules. Puede diferir levemente del reporte de appchecar porque cada sistema tiene su propia configuración de horarios; retardo_reportado permite medir esa diferencia.';

-- RLS: consultar el dashboard es para cualquier usuario autenticado con acceso a la página; la
-- escritura queda sólo para la Edge Function, que corre con service_role. Ningún cliente inserta
-- aquí directamente, así que no hace falta una política de escritura para `authenticated`.
ALTER TABLE checador_registros     ENABLE ROW LEVEL SECURITY;
ALTER TABLE checador_importaciones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS checador_registros_select_auth ON checador_registros;
CREATE POLICY checador_registros_select_auth
  ON checador_registros FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS checador_importaciones_select_auth ON checador_importaciones;
CREATE POLICY checador_importaciones_select_auth
  ON checador_importaciones FOR SELECT TO authenticated USING (true);

-- Borrar un periodo mal cargado es una operación de administrador, y sí hace falta poder hacerla
-- desde la app: sin esto, un reporte equivocado sólo se podría limpiar desde el dashboard de
-- Supabase. Mismo criterio que usa `schedules`.
DROP POLICY IF EXISTS checador_registros_delete_admin ON checador_registros;
CREATE POLICY checador_registros_delete_admin
  ON checador_registros FOR DELETE TO authenticated
  USING (((auth.jwt() -> 'app_metadata') ->> 'role') IN ('admin', 'superadmin'));
