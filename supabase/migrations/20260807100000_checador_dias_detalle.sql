-- La vista de días gana el detalle que necesita la ficha por empleado.
--
-- Faltaba distinguir tres cosas que hasta ahora se confundían en una:
--
--   · SIN CHECAR   — el día no tiene ninguna checada.
--   · FALTA        — sin checar y sin justificación.
--   · INCOMPLETA   — sí checó, pero falta la entrada o falta la salida.
--
-- La tercera no se podía calcular porque la vista no sabía qué tipos de registro hubo cada día. Con
-- `tiene_entrada` y `tiene_salida` se resuelven las tres, y aparece una realidad que conviene ver:
-- hay quien nunca registra su salida.

-- DROP y no CREATE OR REPLACE: las columnas nuevas van en medio, y reemplazar una vista no permite
-- insertar ni reordenar columnas.
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
candidatos AS (
  SELECT h.profile_id, h.horario_id, h.horario_ambiguo, d::date AS fecha
  FROM horario_por_persona h
  CROSS JOIN rango r
  CROSS JOIN generate_series(r.ini, r.fin, '1 day') d
)
SELECT
  c.profile_id,
  c.fecha,
  c.horario_id,
  c.horario_ambiguo,
  reg.tiene_entrada,
  reg.tiene_salida,
  (reg.tiene_entrada OR reg.tiene_salida)                   AS checo,
  (j.id IS NOT NULL)                                        AS justificado,
  -- Sólo cuenta como incompleta si hubo algo que registrar: un día sin nada es SIN CHECAR, y un
  -- día justificado no se le reprocha a nadie.
  (j.id IS NULL
     AND (reg.tiene_entrada OR reg.tiene_salida)
     AND NOT (reg.tiene_entrada AND reg.tiene_salida))      AS incompleta,
  j.motivo                                                  AS justificacion_motivo,
  j.motivo_tipo                                             AS justificacion_tipo,
  CASE
    WHEN j.id IS NOT NULL                                  THEN 'JUSTIFICADO'
    WHEN reg.tiene_entrada OR reg.tiene_salida              THEN 'CHECO'
    ELSE 'FALTA'
  END AS estado
FROM candidatos c
JOIN schedules s ON s.id = c.horario_id
LEFT JOIN LATERAL (
  -- COALESCE obligatorio: bool_or sobre un conjunto vacío devuelve NULL, no false. Sin esto, en
  -- los días sin ningún registro `checo` quedaba NULL y un `WHERE NOT checo` no devolvía nada —las
  -- 57 faltas se contaban como cero—.
  SELECT COALESCE(bool_or(r.tipo = 'Entrada'), false) AS tiene_entrada,
         COALESCE(bool_or(r.tipo = 'Salida'), false)  AS tiene_salida
  FROM checador_registros r
  WHERE r.profile_id = c.profile_id AND r.fecha = c.fecha
) reg ON true
LEFT JOIN checador_justificaciones j
       ON j.profile_id IS NOT NULL
      AND j.profile_id = c.profile_id
      AND j.fecha = c.fecha
WHERE EXISTS (
  SELECT 1 FROM jsonb_array_elements(s.rules) e
   WHERE e->>'type' = 'ENTRADA'
     AND (e->>'day')::int = EXTRACT(DOW FROM c.fecha)::int
);

COMMENT ON VIEW checador_dias IS
  'Un renglón por persona y día que su horario pide trabajar. estado: CHECO, JUSTIFICADO o FALTA. `incompleta` marca los días con checada a medias —falta la entrada o falta la salida— que no son lo mismo que una falta.';
