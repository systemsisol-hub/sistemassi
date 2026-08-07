-- `checador_dias` pasa a describir el día completo: entrada, salida, fotos y los dos veredictos.
--
-- Hacía falta para el calendario, que muestra las dos horas por día. Hasta ahora ninguna vista
-- exponía la SALIDA: `checador_entradas` da la primera entrada y `checador_dias` sólo decía si
-- existía. Las reglas de tipo SALIDA de los horarios estaban capturadas y sin usar.
--
-- ─── Dos cambios de alcance ──────────────────────────────────────────────────
--
-- 1. La vista deja de limitarse a los días que el horario pide. Un calendario tiene que poder
--    pintar un sábado que alguien trabajó aunque su horario sea L-V. Se agrega `esperado` para
--    distinguirlos, y las métricas se calculan filtrando por esa bandera — con lo que las cifras
--    verificadas no cambian: 588 esperados, 57 faltas, 49 justificados, 135 incompletas.
--
-- 2. Se evalúa la salida contra su regla. Salir DESPUÉS de la hora no es una falta —se trabajó
--    más—; salir antes sí. Por eso `salida_temprano` sólo se marca en ese sentido.

DROP VIEW IF EXISTS checador_dias;

CREATE VIEW checador_dias
WITH (security_invoker = true) AS
WITH horario_por_persona AS (
  SELECT profile_id,
         (array_agg(horario_id ORDER BY veces DESC, horario_id))[1] AS horario_id,
         count(*) > 1 AS horario_ambiguo
  FROM (
    SELECT profile_id, horario_id, count(*) AS veces
    FROM checador_registros
    WHERE profile_id IS NOT NULL AND horario_id IS NOT NULL
    GROUP BY 1, 2
  ) t
  GROUP BY profile_id
),
rango AS (SELECT min(fecha) AS ini, max(fecha) AS fin FROM checador_registros),
-- Todos los días del rango para cada persona con horario conocido. Los que su horario no pide
-- quedan con `esperado = false` en lugar de desaparecer.
candidatos AS (
  SELECT h.profile_id, h.horario_id, h.horario_ambiguo, d::date AS fecha
  FROM horario_por_persona h
  CROSS JOIN rango r
  CROSS JOIN generate_series(r.ini, r.fin, '1 day') d
)
SELECT
  c.profile_id,
  c.fecha,
  COALESCE(reg.horario_registro, c.horario_id) AS horario_id,
  s.name AS horario_nombre,
  -- Sigue avisando de quien alterna horarios, pero ahora sólo afecta a sus días SIN registros: en
  -- los demás se usa el horario que traía la checada.
  c.horario_ambiguo,

  -- Qué dice el horario para ese día de la semana.
  ent.hora    AS entrada_esperada,
  ent.tol     AS tolerancia_min,
  ent.hora + make_interval(mins => ent.tol) AS limite_entrada,
  sal.hora    AS salida_esperada,
  (ent.hora IS NOT NULL) AS esperado,

  -- Qué pasó de verdad. La entrada es la primera del día y la salida la última: si alguien checa
  -- de más, lo que importa es cuándo llegó y cuándo se fue.
  reg.hora_entrada,
  reg.hora_salida,
  reg.foto_entrada,
  reg.foto_salida,
  (reg.hora_entrada IS NOT NULL) AS tiene_entrada,
  (reg.hora_salida IS NOT NULL)  AS tiene_salida,
  (reg.hora_entrada IS NOT NULL OR reg.hora_salida IS NOT NULL) AS checo,

  (j.id IS NOT NULL) AS justificado,
  j.motivo           AS justificacion_motivo,
  j.motivo_tipo      AS justificacion_tipo,

  (j.id IS NULL
     AND ent.hora IS NOT NULL
     AND (reg.hora_entrada IS NOT NULL OR reg.hora_salida IS NOT NULL)
     AND NOT (reg.hora_entrada IS NOT NULL AND reg.hora_salida IS NOT NULL)) AS incompleta,

  -- Retardo: sólo si el horario pedía ese día, hubo entrada y no está justificado.
  CASE WHEN j.id IS NULL AND ent.hora IS NOT NULL AND reg.hora_entrada IS NOT NULL
       THEN reg.hora_entrada > ent.hora + make_interval(mins => ent.tol) END AS es_retardo,
  CASE WHEN j.id IS NULL AND ent.hora IS NOT NULL AND reg.hora_entrada IS NOT NULL
       THEN GREATEST(0, CEIL(EXTRACT(EPOCH FROM (
              reg.hora_entrada - (ent.hora + make_interval(mins => ent.tol))
            )) / 60.0))::int END AS minutos_retardo,

  -- Salir después de la hora no se le reprocha a nadie; salir antes sí.
  CASE WHEN j.id IS NULL AND sal.hora IS NOT NULL AND reg.hora_salida IS NOT NULL
       THEN reg.hora_salida < sal.hora END AS salida_temprano,
  CASE WHEN j.id IS NULL AND sal.hora IS NOT NULL AND reg.hora_salida IS NOT NULL
       THEN GREATEST(0, CEIL(EXTRACT(EPOCH FROM (
              sal.hora - reg.hora_salida
            )) / 60.0))::int END AS minutos_antes,

  CASE
    WHEN j.id IS NOT NULL                                             THEN 'JUSTIFICADO'
    WHEN reg.hora_entrada IS NOT NULL OR reg.hora_salida IS NOT NULL  THEN 'CHECO'
    WHEN ent.hora IS NOT NULL                                         THEN 'FALTA'
    ELSE 'DESCANSO'
  END AS estado

FROM candidatos c
LEFT JOIN LATERAL (
  SELECT
    (array_agg(r.hora     ORDER BY r.hora)      FILTER (WHERE r.tipo = 'Entrada'))[1] AS hora_entrada,
    (array_agg(r.foto_url ORDER BY r.hora)      FILTER (WHERE r.tipo = 'Entrada'))[1] AS foto_entrada,
    (array_agg(r.hora     ORDER BY r.hora DESC) FILTER (WHERE r.tipo = 'Salida'))[1]  AS hora_salida,
    (array_agg(r.foto_url ORDER BY r.hora DESC) FILTER (WHERE r.tipo = 'Salida'))[1]  AS foto_salida,
    -- El horario que appchecar puso en la checada de ese día. Manda sobre el inferido: es un dato,
    -- no una deducción. Guillermo Gallardo alterna entre 'Obra' y 'Posventa Vidamar', y usar el
    -- inferido daba un veredicto distinto en 7 de sus días.
    (array_agg(r.horario_id ORDER BY r.hora)     FILTER (WHERE r.horario_id IS NOT NULL))[1] AS horario_registro
  FROM checador_registros r
  WHERE r.profile_id = c.profile_id AND r.fecha = c.fecha
) reg ON true
-- El inferido queda como respaldo, y sólo hace falta en los días sin ningún registro: ahí no hay
-- checada de la que sacar el horario, y sin él no se podría saber si la persona debía trabajar.
JOIN schedules s ON s.id = COALESCE(reg.horario_registro, c.horario_id)
LEFT JOIN checador_justificaciones j
       ON j.profile_id IS NOT NULL
      AND j.profile_id = c.profile_id
      AND j.fecha = c.fecha
LEFT JOIN LATERAL (
  SELECT (e->>'time')::time AS hora, COALESCE((e->>'tol')::int, 0) AS tol
  FROM jsonb_array_elements(s.rules) e
  WHERE e->>'type' = 'ENTRADA' AND (e->>'day')::int = EXTRACT(DOW FROM c.fecha)::int
  ORDER BY (e->>'time')::time
  LIMIT 1
) ent ON true
LEFT JOIN LATERAL (
  SELECT (e->>'time')::time AS hora
  FROM jsonb_array_elements(s.rules) e
  WHERE e->>'type' = 'SALIDA' AND (e->>'day')::int = EXTRACT(DOW FROM c.fecha)::int
  ORDER BY (e->>'time')::time DESC
  LIMIT 1
) sal ON true
-- Se descartan sólo los días que ni el horario pide ni tuvieron actividad: rellenar el calendario
-- con celdas de descanso vacías no aporta nada y multiplica las filas.
WHERE ent.hora IS NOT NULL
   OR reg.hora_entrada IS NOT NULL
   OR reg.hora_salida IS NOT NULL;

COMMENT ON VIEW checador_dias IS
  'Un renglón por persona y día con actividad o expectativa. `esperado` dice si su horario pedía ese día: las métricas se calculan filtrando por esa bandera. Trae entrada y salida reales con sus fotos, y los dos veredictos: es_retardo para la llegada y salida_temprano para la salida.';
