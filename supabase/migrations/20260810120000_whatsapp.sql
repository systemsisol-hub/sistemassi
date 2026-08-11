-- Soli por WhatsApp: lista blanca, memoria de conversación y bitácora.
--
-- Un colaborador escribe al número de la empresa y Soli le contesta con SUS datos. Lo que decide de
-- quién son «sus datos» es el teléfono desde el que escribe, y ahí está toda la dificultad.
--
-- ─── Por qué el teléfono no basta por sí solo ────────────────────────────────
--
-- Medido sobre los 233 colaboradores vigentes:
--
--   * Sólo 199 tienen un celular de 10 dígitos utilizable. Los otros 34 no se pueden identificar.
--   * `0000000000` está capturado en 5 perfiles vigentes, y hay 2 números más repetidos entre dos
--     personas cada uno.
--   * Las longitudes que hay en la base van de 1 a 11 dígitos.
--
-- Por eso la resolución exige coincidencia ÚNICA: si un teléfono empata con cero o con más de un
-- perfil vigente, el sistema no contesta. Contestar con los datos del primero que aparezca sería
-- entregarle a alguien el saldo de vacaciones de otra persona.

-- ─── 1. Quién puede preguntar ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS whatsapp_autorizados (
  -- 10 dígitos, sin lada de país. Es la forma normalizada con la que se compara todo.
  telefono   text PRIMARY KEY CHECK (telefono ~ '^[0-9]{10}$'),

  -- El perfil al que se resolvió al darlo de alta. Se guarda para que el panel muestre a quién
  -- pertenece el número, pero NO se confía en él al contestar: el webhook vuelve a resolver contra
  -- `profiles` en cada mensaje, porque un teléfono puede cambiar de dueño y este campo quedaría viejo.
  profile_id uuid REFERENCES profiles(id) ON DELETE SET NULL,

  activo     boolean NOT NULL DEFAULT true,
  notas      text,
  creado_por uuid REFERENCES profiles(id) ON DELETE SET NULL,
  creado_en  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE whatsapp_autorizados IS
  'Números de WhatsApp a los que Soli responde. El teléfono se guarda normalizado a 10 dígitos. profile_id es informativo: al contestar se vuelve a resolver contra profiles.';

-- ─── 2. Memoria de la conversación ───────────────────────────────────────────
--
-- En la aplicación esto lo resuelve `AsistenteStore` en memoria del navegador. WhatsApp no tiene
-- dónde guardarlo, así que el hilo vive aquí; sin esto cada mensaje sería una conversación nueva y
-- «¿y las del año pasado?» no tendría contexto.

CREATE TABLE IF NOT EXISTS whatsapp_conversaciones (
  telefono       text PRIMARY KEY CHECK (telefono ~ '^[0-9]{10}$'),
  -- [{rol, contenido}], recortado por el webhook a los últimos turnos: el historial completo
  -- encarecería cada llamada al modelo sin aportar nada.
  mensajes       jsonb NOT NULL DEFAULT '[]'::jsonb,
  actualizado_en timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE whatsapp_conversaciones IS
  'Hilo de conversación por número, para que Soli tenga memoria entre mensajes de WhatsApp.';

-- ─── 3. Bitácora ─────────────────────────────────────────────────────────────
--
-- Es lo que permite explicar por qué alguien NO recibió respuesta, que es la llamada que llega a
-- Sistemas. Un número desconocido no recibe nada por decisión de diseño, así que sin este registro
-- el rechazo sería invisible.

CREATE TABLE IF NOT EXISTS whatsapp_bitacora (
  id         bigserial PRIMARY KEY,
  telefono   text NOT NULL,
  profile_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  resultado  text NOT NULL CHECK (resultado IN (
               'ATENDIDO',       -- Soli contestó
               'NO_AUTORIZADO',  -- el número no está en la lista blanca
               'SIN_REGISTRO',   -- no empata con ningún perfil vigente
               'AMBIGUO',        -- empata con más de uno: no se contesta
               'SIN_PERMISO',    -- la persona existe pero no tiene show_ai ni es admin
               'LIMITE',         -- superó el límite de mensajes
               'ERROR'           -- falló Soli o el envío
             )),
  pregunta   text,
  respuesta  text,
  detalle    text,
  creado_en  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS whatsapp_bitacora_recientes_idx
  ON whatsapp_bitacora (creado_en DESC);
CREATE INDEX IF NOT EXISTS whatsapp_bitacora_telefono_idx
  ON whatsapp_bitacora (telefono, creado_en DESC);

COMMENT ON TABLE whatsapp_bitacora IS
  'Un renglón por mensaje entrante y en qué acabó. Los rechazos son invisibles para quien escribe —no se le contesta— así que esta tabla es la única forma de explicarlos.';

-- ─── 4. Teléfono → colaborador, con coincidencia única ───────────────────────
--
-- SECURITY DEFINER porque la usa el webhook, que no actúa como ninguna persona. Y devuelve `setof`
-- de una fila como máximo: si hay varias coincidencias no devuelve nada, para que quien la llame no
-- tenga que acordarse de comprobar el conteo. La regla queda en un solo lugar.

CREATE OR REPLACE FUNCTION whatsapp_resolver_telefono(p_telefono text)
RETURNS TABLE (profile_id uuid, coincidencias int)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH candidatos AS (
    SELECT p.id
    FROM profiles p
    WHERE p.status_rh IN ('ACTIVO', 'CAMBIO', 'REINGRESO')
      AND p.fecha_baja IS NULL
      AND (
        regexp_replace(COALESCE(p.celular, ''),  '\D', '', 'g') = p_telefono
        OR regexp_replace(COALESCE(p.telefono, ''), '\D', '', 'g') = p_telefono
      )
  )
  SELECT
    -- Sólo se devuelve el perfil si es el ÚNICO. Con 0000000000 en cinco perfiles, devolver el
    -- primero sería entregar los datos de una persona a otra.
    --
    -- `(array_agg(id))[1]` y no `min(id)`: en Postgres no existe min() para uuid, y con `min` esta
    -- función fallaba al crearse. Se descubrió probando la consulta antes de aplicar la migración.
    CASE WHEN count(*) = 1 THEN (array_agg(id))[1] END,
    count(*)::int
  FROM candidatos;
$$;

COMMENT ON FUNCTION whatsapp_resolver_telefono(text) IS
  'Resuelve un teléfono de 10 dígitos al colaborador vigente correspondiente. Devuelve profile_id sólo si la coincidencia es única; `coincidencias` dice cuántos empataron para poder registrar AMBIGUO.';

-- ─── 5. Acceso ───────────────────────────────────────────────────────────────
--
-- Las tres tablas las escribe únicamente el webhook, que usa la llave de servicio y se salta RLS. Lo
-- que se abre aquí es la LECTURA para quien gestione el panel, y la escritura de la lista blanca.

ALTER TABLE whatsapp_autorizados     ENABLE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_conversaciones  ENABLE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_bitacora        ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS whatsapp_autorizados_gestion ON whatsapp_autorizados;
CREATE POLICY whatsapp_autorizados_gestion
  ON whatsapp_autorizados FOR ALL TO authenticated
  USING (is_admin() OR has_permission('show_whatsapp'))
  WITH CHECK (is_admin() OR has_permission('show_whatsapp'));

DROP POLICY IF EXISTS whatsapp_bitacora_select_gestion ON whatsapp_bitacora;
CREATE POLICY whatsapp_bitacora_select_gestion
  ON whatsapp_bitacora FOR SELECT TO authenticated
  USING (is_admin() OR has_permission('show_whatsapp'));

-- Las conversaciones NO se exponen a nadie desde el cliente, ni a quien gestiona: son el contenido
-- de lo que la gente le escribió a Soli en privado. El panel muestra la bitácora, que ya dice quién
-- escribió y en qué acabó, sin abrir el hilo completo.
--
-- Sin políticas de SELECT, RLS niega todo: sólo la llave de servicio del webhook las lee.

COMMENT ON TABLE whatsapp_conversaciones IS
  'Hilo de conversación por número. Sin políticas RLS a propósito: sólo el webhook, con llave de servicio, puede leerlo. Es correspondencia privada, no material para el panel.';
