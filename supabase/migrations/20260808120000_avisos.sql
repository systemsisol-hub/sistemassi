-- Avisos: anuncios que se redactan una vez y aparecen en el camino de la gente.
--
-- No se reusa `notifications` porque no es lo mismo: esa tabla guarda UNA FILA POR DESTINATARIO
-- —2 716 hoy— y nace de un evento concreto, una incidencia o un cambio de estatus. Un aviso es un
-- texto que alguien escribe una vez y que ven muchos, así que la tabla guarda el aviso, no las
-- copias. Difundir uno a los perfiles activos con el modelo de `notifications` serían 90 inserciones
-- por aviso, y editar el texto obligaría a reescribirlas todas.
--
-- ─── 1. El aviso ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS avisos (
  id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo text NOT NULL CHECK (btrim(titulo) <> ''),
  cuerpo text NOT NULL CHECK (btrim(cuerpo) <> ''),

  -- Verde, amarillo y rojo de la pantalla. Se guarda el significado, no el color: el color lo pone
  -- el tema, que además tiene una variante para modo oscuro.
  nivel  text NOT NULL DEFAULT 'INFO'
         CHECK (nivel IN ('INFO', 'ADVERTENCIA', 'CRITICO')),

  -- Canales: tres banderas y no un `tipo` exclusivo. Un aviso urgente casi siempre quiere las tres
  -- —emergente para que nadie se lo pierda, banner mientras dure, muro como registro— y con un tipo
  -- único habría que capturar el mismo texto tres veces y luego editarlo tres veces.
  en_modal  boolean NOT NULL DEFAULT false,
  en_banner boolean NOT NULL DEFAULT false,
  en_social boolean NOT NULL DEFAULT false,
  CONSTRAINT avisos_al_menos_un_canal CHECK (en_modal OR en_banner OR en_social),

  -- Vigencia. `activo` es el interruptor manual; `desde`/`hasta` la programación.
  activo boolean NOT NULL DEFAULT true,
  desde  timestamptz NOT NULL DEFAULT now(),
  hasta  timestamptz,
  CONSTRAINT avisos_vigencia_en_orden CHECK (hasta IS NULL OR hasta > desde),

  -- Destinatarios. Un arreglo vacío significa «esta dimensión no filtra».
  para_todos  boolean NOT NULL DEFAULT true,
  ubicaciones text[] NOT NULL DEFAULT '{}',
  areas       text[] NOT NULL DEFAULT '{}',
  empresas    text[] NOT NULL DEFAULT '{}',
  roles       text[] NOT NULL DEFAULT '{}',
  -- Dirigido pero sin ninguna dimensión marcada no alcanzaría a nadie, y eso siempre es un error de
  -- captura: quien redactó el aviso creía estar avisándole a alguien.
  CONSTRAINT avisos_dirigido_tiene_destino CHECK (
    para_todos
    OR cardinality(ubicaciones) > 0
    OR cardinality(areas) > 0
    OR cardinality(empresas) > 0
    OR cardinality(roles) > 0
  ),

  -- El emergente se muestra una vez y no vuelve. Con `insistir` reaparece cada sesión mientras esté
  -- vigente: es para lo grave, y por eso es una decisión por aviso y no una regla global.
  insistir boolean NOT NULL DEFAULT false,

  creado_por     uuid REFERENCES profiles(id) ON DELETE SET NULL,
  creado_en      timestamptz NOT NULL DEFAULT now(),
  actualizado_en timestamptz
);

COMMENT ON TABLE avisos IS
  'Anuncios del sistema. Un aviso puede salir en varios canales a la vez (en_modal, en_banner, en_social). SEGMENTACIÓN: las dimensiones se cruzan con AND y los valores dentro de una dimensión con OR, así que ubicaciones={Constituyentes} + areas={SISTEMAS} significa "Sistemas EN Constituyentes", no "Sistemas O Constituyentes".';

COMMENT ON COLUMN avisos.insistir IS
  'Si es true, el aviso emergente reaparece en cada sesión mientras esté vigente, aunque la persona ya lo haya cerrado.';

CREATE INDEX IF NOT EXISTS avisos_vigentes_idx
  ON avisos (activo, desde, hasta)
  WHERE activo;

-- ─── 2. Quién ya lo vio ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS avisos_vistos (
  aviso_id   uuid NOT NULL REFERENCES avisos(id)   ON DELETE CASCADE,
  profile_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  visto_en   timestamptz NOT NULL DEFAULT now(),
  -- La llave compuesta hace el acuse idempotente: cerrar dos veces no duplica el renglón, así que el
  -- cliente puede insertar sin consultar antes.
  PRIMARY KEY (aviso_id, profile_id)
);

COMMENT ON TABLE avisos_vistos IS
  'Acuse por persona: se inserta cuando alguien cierra el emergente o descarta el banner. El muro social no acusa, ahí sólo se consulta.';

-- ─── 3. A quién le toca un aviso ─────────────────────────────────────────────
--
-- Va en SECURITY DEFINER a propósito. La alternativa —una subconsulta a `profiles` metida en la
-- política de `avisos`— dependería de que la RLS de `profiles` deje leer la propia fila, y eso ataría
-- el acceso a los avisos a una política de otra tabla: si mañana se endurece `profiles`, los avisos
-- dejarían de verse sin que nadie relacione una cosa con la otra.

CREATE OR REPLACE FUNCTION aviso_me_corresponde(
  p_para_todos  boolean,
  p_ubicaciones text[],
  p_areas       text[],
  p_empresas    text[],
  p_roles       text[]
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_para_todos OR EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid()
      -- Cada dimensión sólo restringe si trae valores. Se cruzan con AND: un aviso a una ubicación y
      -- un área es para quien cumple las dos cosas.
      AND (cardinality(p_ubicaciones) = 0 OR p.ubicacion    = ANY (p_ubicaciones))
      AND (cardinality(p_areas)       = 0 OR p.area         = ANY (p_areas))
      AND (cardinality(p_empresas)    = 0 OR p.empresa      = ANY (p_empresas))
      AND (cardinality(p_roles)       = 0 OR p.role::text   = ANY (p_roles))
  );
$$;

COMMENT ON FUNCTION aviso_me_corresponde(boolean, text[], text[], text[], text[]) IS
  'Si el aviso descrito por esos destinatarios le toca a auth.uid(). Dimensiones con AND, valores con OR.';

-- ─── 4. Lo que a mí me toca ver ──────────────────────────────────────────────
--
-- Vigencia, segmentación y acuse resueltos en un solo lugar. El cliente sólo pinta: si estas reglas
-- vivieran en Dart habría que repetirlas en el banner, en el emergente y en el muro, y bastaría con
-- que una de las tres se quedara atrás para mostrarle a alguien un aviso que no era para él.

DROP VIEW IF EXISTS avisos_para_mi;

CREATE VIEW avisos_para_mi
WITH (security_invoker = true) AS
SELECT
  a.id,
  a.titulo,
  a.cuerpo,
  a.nivel,
  a.en_modal,
  a.en_banner,
  a.en_social,
  a.insistir,
  a.desde,
  a.hasta,
  a.creado_en,
  (v.aviso_id IS NOT NULL) AS visto,
  v.visto_en
FROM avisos a
LEFT JOIN avisos_vistos v
       ON v.aviso_id = a.id
      AND v.profile_id = auth.uid()
WHERE a.activo
  AND now() >= a.desde
  AND (a.hasta IS NULL OR now() <= a.hasta)
  AND aviso_me_corresponde(a.para_todos, a.ubicaciones, a.areas, a.empresas, a.roles);

COMMENT ON VIEW avisos_para_mi IS
  'Los avisos vigentes que le corresponden a quien pregunta, con `visto` ya resuelto. Es lo que leen el banner, el emergente y el muro social.';

-- ─── 5. Acceso ───────────────────────────────────────────────────────────────

ALTER TABLE avisos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE avisos_vistos ENABLE ROW LEVEL SECURITY;

-- Dos políticas de lectura, que RLS combina con OR. Hacen falta las dos:
--
-- * Sólo con la pública, quien gestiona no podría abrir un aviso apagado ni uno programado para la
--   semana que entra, que es justo lo que necesita editar.
-- * Sólo con la de gestión, nadie más vería un aviso.
--
-- Y la pública lleva la vigencia dentro a propósito: sin eso, cualquiera podría leer por API un
-- aviso todavía no publicado —«cierre de sucursal el lunes»— antes de que se publique. Que la
-- pantalla no lo muestre no es control de acceso.
DROP POLICY IF EXISTS avisos_select_gestion ON avisos;
CREATE POLICY avisos_select_gestion
  ON avisos FOR SELECT TO authenticated
  USING (is_admin() OR has_permission('show_avisos'));

DROP POLICY IF EXISTS avisos_select_publico ON avisos;
CREATE POLICY avisos_select_publico
  ON avisos FOR SELECT TO authenticated
  USING (
    activo
    AND now() >= desde
    AND (hasta IS NULL OR now() <= hasta)
    AND aviso_me_corresponde(para_todos, ubicaciones, areas, empresas, roles)
  );

DROP POLICY IF EXISTS avisos_insert_gestion ON avisos;
CREATE POLICY avisos_insert_gestion
  ON avisos FOR INSERT TO authenticated
  WITH CHECK (is_admin() OR has_permission('show_avisos'));

DROP POLICY IF EXISTS avisos_update_gestion ON avisos;
CREATE POLICY avisos_update_gestion
  ON avisos FOR UPDATE TO authenticated
  USING (is_admin() OR has_permission('show_avisos'))
  WITH CHECK (is_admin() OR has_permission('show_avisos'));

DROP POLICY IF EXISTS avisos_delete_gestion ON avisos;
CREATE POLICY avisos_delete_gestion
  ON avisos FOR DELETE TO authenticated
  USING (is_admin() OR has_permission('show_avisos'));

-- El acuse es personal: nadie marca por otro, y nadie audita lo que otro leyó desde el cliente. El
-- conteo de vistos que muestra la página de gestión sale de una vista aparte, no de leer estas filas.
DROP POLICY IF EXISTS avisos_vistos_select_propio ON avisos_vistos;
CREATE POLICY avisos_vistos_select_propio
  ON avisos_vistos FOR SELECT TO authenticated
  USING (profile_id = auth.uid());

DROP POLICY IF EXISTS avisos_vistos_insert_propio ON avisos_vistos;
CREATE POLICY avisos_vistos_insert_propio
  ON avisos_vistos FOR INSERT TO authenticated
  WITH CHECK (profile_id = auth.uid());

-- ─── 6. Cuántos lo vieron ────────────────────────────────────────────────────
--
-- La página de gestión necesita el conteo, pero `avisos_vistos` sólo deja ver la propia fila. Esta
-- vista da el número sin exponer quién: para saber si un aviso llegó basta el cuántos, y el quién
-- convertiría el tablero de avisos en un registro de lectura por persona.

DROP VIEW IF EXISTS avisos_conteo_vistos;

CREATE VIEW avisos_conteo_vistos
WITH (security_invoker = false) AS
SELECT a.id AS aviso_id, count(v.profile_id)::int AS vistos
FROM avisos a
LEFT JOIN avisos_vistos v ON v.aviso_id = a.id
-- El filtro tiene que ir aquí dentro. Con security_invoker = false la vista corre como su dueño, así
-- que se salta la RLS de las DOS tablas: sin esta condición cualquiera podría enumerar por API los
-- ids de los avisos no publicados y ver cuánta gente los acusó. is_admin() y has_permission() siguen
-- funcionando porque leen del JWT de quien pregunta, no del rol con el que corre la vista.
WHERE is_admin() OR has_permission('show_avisos')
GROUP BY a.id;

COMMENT ON VIEW avisos_conteo_vistos IS
  'Cuántas personas acusaron cada aviso, sin decir quiénes. Sólo para quien gestiona avisos. security_invoker = false a propósito: avisos_vistos sólo deja leer la propia fila, y el conteo no revela identidades.';

REVOKE ALL ON avisos_conteo_vistos FROM authenticated;
GRANT SELECT ON avisos_conteo_vistos TO authenticated;
