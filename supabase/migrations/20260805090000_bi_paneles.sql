-- Paneles guardados del asistente de BI.
--
-- Se guardan PARÁMETROS, no cifras. Eso es lo que hace que un panel siga sirviendo cuando el
-- modelo semántico se refresca cada periodo: al abrirlo se vuelve a consultar y sale el dato
-- vigente. Guardar cifras habría producido tableros que envejecen en silencio.

CREATE TABLE IF NOT EXISTS bi_paneles (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  link_id      uuid NOT NULL REFERENCES powerbi_links(id) ON DELETE CASCADE,
  titulo       text NOT NULL,
  medidas      text[] NOT NULL,
  agrupar_por  text[] NOT NULL DEFAULT '{}',
  -- null = periodo "Actual", el mismo que muestra el panel de Power BI.
  periodo      jsonb,
  limite       integer,
  presentacion text NOT NULL DEFAULT 'auto',
  orden        integer NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT bi_paneles_presentacion_valida
    CHECK (presentacion IN ('auto', 'grafica', 'tabla')),
  CONSTRAINT bi_paneles_con_medidas
    CHECK (cardinality(medidas) > 0)
);

CREATE INDEX IF NOT EXISTS bi_paneles_user_orden_idx
  ON bi_paneles (user_id, orden, created_at);

ALTER TABLE bi_paneles ENABLE ROW LEVEL SECURITY;

-- Privados de quien los crea. La restricción vive en la base y no sólo en la interfaz: un
-- panel lleva consigo qué medidas financieras mira su dueño, y eso no se filtra por un
-- descuido del cliente.
CREATE POLICY bi_paneles_propios_select ON bi_paneles
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE POLICY bi_paneles_propios_insert ON bi_paneles
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE POLICY bi_paneles_propios_update ON bi_paneles
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY bi_paneles_propios_delete ON bi_paneles
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

COMMENT ON TABLE bi_paneles IS
  'Paneles guardados del asistente BI. Guarda parametros de consulta, no cifras, para que se '
  'actualicen solos cuando el modelo semantico se refresca. Privados por RLS.';
COMMENT ON COLUMN bi_paneles.periodo IS
  'null = periodo Actual. Si trae valor: { "anio": "...", "mes": "..." }.';
