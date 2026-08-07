-- La foto de cada checada, y limpieza de la zona.
--
-- El reporte de appchecar trae una columna Foto cuya celda contiene un enlace a la selfie que se
-- tomó al registrar: <a href="https://www.appchecar.com/.../abc.jpg">Ver foto</a>. Se guardaba nada
-- de eso, porque el parser sólo conservaba el texto de cada celda —«Ver foto»— y descartaba el
-- HTML. Verificado sobre el archivo real: las 936 filas traen enlace, ninguna sin él.

ALTER TABLE checador_registros ADD COLUMN IF NOT EXISTS foto_url text;

COMMENT ON COLUMN checador_registros.foto_url IS
  'Enlace a la foto que appchecar toma al registrar. Se extrae del href de la columna Foto; el texto de esa celda es siempre «Ver foto» y no sirve de nada.';

-- ─── Limpieza de la zona ─────────────────────────────────────────────────────
--
-- Los 936 registros se cargaron cuando el parser aún se comía la celda siguiente por el HTML mal
-- formado de appchecar —la celda de Sucursal abre con <td> y cierra con </th>—, así que la zona
-- quedó como «Constituyentes Ver foto». El parser ya está corregido, pero los datos ya cargados no
-- se arreglan solos.
--
-- Esto los deja bien de inmediato. La foto, en cambio, sí exige volver a subir el reporte: no se
-- puede inventar un enlace que nunca se guardó.
UPDATE checador_registros
SET sucursal = nullif(trim(regexp_replace(sucursal, '\s*Ver foto\s*$', '')), '')
WHERE sucursal LIKE '%Ver foto%';

-- ─── La vista expone la foto de la entrada ───────────────────────────────────
--
-- Es la que interesa en el detalle por persona: sirve para contrastar la hora de llegada de un
-- retardo, y para ver quién registró un día que quedó a medias.
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
  e.foto_url,
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
