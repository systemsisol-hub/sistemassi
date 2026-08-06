-- Faltas justificadas del reporte de incidencias de appchecar.
--
-- ─── Qué es este archivo y por qué hace falta ────────────────────────────────
--
-- appchecar exporta un segundo reporte, «Incidencias», con los días que se justificaron. Trae seis
-- columnas, pero sólo tres significan algo: Fecha, Trabajador y Motivo.
--
-- Las columnas Hora, Registro y Dirección son informativas: muestran la hora del HORARIO, no una
-- checada. En esos días la persona **no checó**. Y sin embargo el reporte de checadas sí incluye
-- registros para ellos, a la hora exacta del horario.
--
-- Medido en el periodo del 16 al 31 de julio de 2026: de las 91 filas del archivo —54 persona-día
-- de 19 personas— **33 entradas estaban contando como llegadas perfectamente puntuales** en días
-- en que la persona no fue a trabajar. El caso que lo hizo evidente: Angel Antonio Vargas, 30 de
-- julio, «Permiso ya que su papá está hospitalizado», y en checador_registros una Entrada 08:00 y
-- una Salida 18:00. Aparecía como el ejemplo de puntualidad.
--
-- ─── Por qué una tabla y no una columna en checador_registros ────────────────
--
-- La justificación es de un DÍA, no de una checada: hay dos registros por día (entrada y salida) y
-- una sola justificación. Colgarla de un registro que además NO es una checada perpetuaría la
-- confusión que este archivo vino a corregir.
--
-- Las checadas falsas no se borran: vienen del reporte de appchecar y volverían a aparecer al
-- reimportar. Se quedan, y la vista las excluye del cálculo al ver que el día está justificado.

CREATE TABLE IF NOT EXISTS checador_justificaciones (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- El archivo de incidencias NO trae número de empleado, sólo el nombre. Se resuelve contra
  -- profiles y sólo cuando el nombre es inequívoco; si no, se guarda sin resolver y el resumen del
  -- import lo reporta, en lugar de adivinar. Ya costó una vez confundir a dos personas.
  profile_id      uuid REFERENCES profiles(id) ON DELETE SET NULL,
  nombre_reporte  text NOT NULL,

  fecha           date NOT NULL,

  -- El texto tal cual lo escribieron. Se conserva completo porque varios son explicaciones de una
  -- sola vez («ACUDIÓ A FIRMA DE ESCRITURA Y LLEGÓ A LA OFICINA A LAS 11:00 AM») que ninguna
  -- categoría resume sin perder información.
  motivo          text,
  -- Clasificación por palabra clave, para poder agrupar. Los motivos vienen escritos de forma
  -- inconsistente: 'Falla APP', 'Falla App', 'falla App' y 'PROBLEMA CON LA APP' son el mismo.
  motivo_tipo     text CHECK (motivo_tipo IN
                    ('INCAPACIDAD', 'VACACIONES', 'FALLA_APP', 'PERMISO', 'OTRO')),

  importacion_id  uuid REFERENCES checador_importaciones(id) ON DELETE SET NULL,

  -- Misma convención que checador_registros: la identidad cae al nombre cuando no hay perfil, para
  -- que dos personas sin resolver no se fundan en una sola fila.
  clave_persona   text GENERATED ALWAYS AS (
    CASE
      WHEN profile_id IS NOT NULL THEN 'id:' || profile_id::text
      ELSE 'nombre:' || lower(regexp_replace(nombre_reporte, '\s+', ' ', 'g'))
    END
  ) STORED,

  -- Una justificación por persona y día. El archivo repite el motivo en la fila de entrada y en la
  -- de salida, y a veces con diferencias de dedo: el 30 de julio venía «hospilizado» en una y
  -- «hospitalizado» en la otra. Con esta llave, la segunda actualiza a la primera en lugar de
  -- duplicar el día.
  CONSTRAINT checador_justificaciones_persona_dia UNIQUE (clave_persona, fecha)
);

CREATE INDEX IF NOT EXISTS checador_justificaciones_fecha_idx
  ON checador_justificaciones (fecha);
CREATE INDEX IF NOT EXISTS checador_justificaciones_profile_idx
  ON checador_justificaciones (profile_id);

COMMENT ON TABLE checador_justificaciones IS
  'Días justificados del reporte de Incidencias de appchecar. Una fila por persona y día. En esos días la persona no checó, aunque el reporte de checadas traiga registros a la hora del horario.';

-- ─── La vista deja de contar los días justificados ──────────────────────────
--
-- `es_retardo` y `minutos_retardo` pasan a NULL cuando el día está justificado, con lo que el día
-- sale del cálculo de puntualidad por el mismo camino que ya usaban los días sin regla de horario.
-- Se agrega `justificado` para poder distinguirlos: no es lo mismo «no sabemos» que «no vino, y
-- está justificado», y contarlos juntos en la pantalla sería engañoso.
DROP VIEW IF EXISTS checador_entradas;

CREATE VIEW checador_entradas
WITH (security_invoker = true) AS
WITH primera_del_dia AS (
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
  regla.tol                                             AS tolerancia_min,
  regla.hora_entrada + make_interval(mins => regla.tol) AS limite,

  (j.id IS NOT NULL)  AS justificado,
  j.motivo            AS justificacion_motivo,
  j.motivo_tipo       AS justificacion_tipo,

  CASE WHEN j.id IS NOT NULL OR regla.hora_entrada IS NULL THEN NULL ELSE
    GREATEST(0, CEIL(EXTRACT(EPOCH FROM (
      e.hora - (regla.hora_entrada + make_interval(mins => regla.tol))
    )) / 60.0))::int
  END AS minutos_retardo,
  CASE WHEN j.id IS NOT NULL OR regla.hora_entrada IS NULL THEN NULL ELSE
    e.hora > regla.hora_entrada + make_interval(mins => regla.tol)
  END AS es_retardo
FROM primera_del_dia e
LEFT JOIN schedules s ON s.id = e.horario_id
-- Se une por `profile_id` y no por `clave`: los dos lados usan namespaces distintos —el registro
-- trae 'num:2467' y la justificación 'id:<uuid>'— y profile_id está resuelto al 100% en registros.
LEFT JOIN checador_justificaciones j
       ON j.profile_id IS NOT NULL
      AND j.profile_id = e.profile_id
      AND j.fecha = e.fecha
LEFT JOIN LATERAL (
  SELECT (regla_json->>'time')::time            AS hora_entrada,
         COALESCE((regla_json->>'tol')::int, 0) AS tol
  FROM jsonb_array_elements(s.rules) AS regla_json
  WHERE regla_json->>'type' = 'ENTRADA'
    AND (regla_json->>'day')::int = EXTRACT(DOW FROM e.fecha)::int
  ORDER BY (regla_json->>'time')::time
  LIMIT 1
) regla ON true;

COMMENT ON VIEW checador_entradas IS
  'Primera entrada de cada empleado por día, con el retardo calculado contra schedules. Los días con justificación quedan con es_retardo NULL y justificado = true: la persona no checó, así que su hora no dice nada sobre puntualidad.';

ALTER TABLE checador_justificaciones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS checador_justificaciones_select_auth ON checador_justificaciones;
CREATE POLICY checador_justificaciones_select_auth
  ON checador_justificaciones FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS checador_justificaciones_delete_admin ON checador_justificaciones;
CREATE POLICY checador_justificaciones_delete_admin
  ON checador_justificaciones FOR DELETE TO authenticated
  USING (((auth.jwt() -> 'app_metadata') ->> 'role') IN ('admin', 'superadmin'));
