-- Base del panel de asistencia: acceso por rol, umbrales configurables y faltas no justificadas.

-- ─── 1. Acceso por rol ───────────────────────────────────────────────────────
--
-- La política de lectura era literalmente `true`: cualquier usuario autenticado podía leer los 936
-- registros de todos consultando la API, aunque la pantalla le mostrara sólo lo suyo. Esconderlo en
-- la interfaz no es control de acceso.
--
-- `checador_entradas` y las vistas nuevas usan security_invoker, así que heredan esto sin cambios.

DROP POLICY IF EXISTS checador_registros_select_auth ON checador_registros;
CREATE POLICY checador_registros_select_propio_o_admin
  ON checador_registros FOR SELECT TO authenticated
  USING (is_admin() OR profile_id = auth.uid());

DROP POLICY IF EXISTS checador_justificaciones_select_auth ON checador_justificaciones;
CREATE POLICY checador_justificaciones_select_propio_o_admin
  ON checador_justificaciones FOR SELECT TO authenticated
  USING (is_admin() OR profile_id = auth.uid());

-- La bitácora de importaciones queda sólo para administradores: su columna `sin_empatar` lleva
-- nombres de otros colaboradores. Un usuario normal deriva su periodo de sus propios registros.
DROP POLICY IF EXISTS checador_importaciones_select_auth ON checador_importaciones;
CREATE POLICY checador_importaciones_select_admin
  ON checador_importaciones FOR SELECT TO authenticated
  USING (is_admin());

-- ─── 2. Umbrales del semáforo ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS checador_umbrales (
  -- Una sola fila, forzada por la llave: son los umbrales de la empresa, no de cada quien.
  id              boolean PRIMARY KEY DEFAULT true CHECK (id),
  critico_max     numeric NOT NULL DEFAULT 70,
  atencion_max    numeric NOT NULL DEFAULT 90,
  actualizado_en  timestamptz NOT NULL DEFAULT now(),
  actualizado_por uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT umbrales_en_orden CHECK (critico_max < atencion_max),
  CONSTRAINT umbrales_en_rango CHECK (critico_max >= 0 AND atencion_max <= 100)
);

INSERT INTO checador_umbrales (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

COMMENT ON TABLE checador_umbrales IS
  'Cortes del semáforo: por debajo de critico_max es Crítico, hasta atencion_max es Atención, arriba Puntual. Se editan desde la pestaña de Configuración.';

ALTER TABLE checador_umbrales ENABLE ROW LEVEL SECURITY;

-- Los lee cualquiera —hacen falta para pintar el propio estatus— pero sólo un administrador los
-- cambia: mover el corte cambia el estatus de todos a la vez.
DROP POLICY IF EXISTS checador_umbrales_select_auth ON checador_umbrales;
CREATE POLICY checador_umbrales_select_auth
  ON checador_umbrales FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS checador_umbrales_update_admin ON checador_umbrales;
CREATE POLICY checador_umbrales_update_admin
  ON checador_umbrales FOR UPDATE TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());

-- ─── 3. Días esperados: checó, justificado o falta ───────────────────────────
--
-- ⚠️ El horario se INFIERE de los registros de cada persona, porque `profiles` no lo tiene: de los
-- 45 empleados del checador, 0 tienen `schedule_id` y sólo 3 tienen `horario` como texto, que
-- además no empata con ningún horario. El único lugar donde aparece es en los propios registros.
--
-- Se verificó que 44 de los 45 usan un solo horario en todo el periodo. El restante —Guillermo
-- Gallardo, entre 'Obra' y 'Posventa Vidamar'— queda marcado con `horario_ambiguo` para que la
-- pantalla lo advierta, en lugar de elegirle uno en silencio.
--
-- Capturar `profiles.schedule_id` volvería esto un hecho y no una inferencia.
CREATE OR REPLACE VIEW checador_dias
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
  EXISTS (SELECT 1 FROM checador_registros r
           WHERE r.profile_id = c.profile_id AND r.fecha = c.fecha)      AS checo,
  EXISTS (SELECT 1 FROM checador_justificaciones j
           WHERE j.profile_id = c.profile_id AND j.fecha = c.fecha)      AS justificado,
  CASE
    WHEN EXISTS (SELECT 1 FROM checador_justificaciones j
                  WHERE j.profile_id = c.profile_id AND j.fecha = c.fecha) THEN 'JUSTIFICADO'
    WHEN EXISTS (SELECT 1 FROM checador_registros r
                  WHERE r.profile_id = c.profile_id AND r.fecha = c.fecha) THEN 'CHECO'
    ELSE 'FALTA'
  END AS estado
FROM candidatos c
JOIN schedules s ON s.id = c.horario_id
-- Sólo los días que el horario de la persona pide. Un domingo en un horario L-V no es una falta.
WHERE EXISTS (
  SELECT 1 FROM jsonb_array_elements(s.rules) e
   WHERE e->>'type' = 'ENTRADA'
     AND (e->>'day')::int = EXTRACT(DOW FROM c.fecha)::int
);

COMMENT ON VIEW checador_dias IS
  'Un renglón por persona y día que su horario pide trabajar, con el estado: CHECO, JUSTIFICADO o FALTA. El orden importa: un día con justificación es JUSTIFICADO aunque appchecar haya creado registros a la hora del horario.';
