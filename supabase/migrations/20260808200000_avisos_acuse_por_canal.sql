-- El acuse pasa a ser POR CANAL, y el banner gana su propio «insistir».
--
-- ─── El fallo ────────────────────────────────────────────────────────────────
--
-- `avisos_vistos` guardaba un renglón por (aviso, persona), sin decir en qué canal. Con un aviso
-- publicado en los tres lugares, apretar «Entendido» en la ventana emergente escribía ese único acuse
-- y el banner desaparecía con él —sin que nadie lo hubiera descartado— y no volvía nunca. Un acuse
-- para tres canales confundía tres decisiones distintas en un solo dato.
--
-- Ahora el canal es parte de la llave: cerrar el emergente no toca el banner.
--
-- ─── Los dos «insistir» ──────────────────────────────────────────────────────
--
-- `insistir` se renombra a `insistir_modal`, que es lo que siempre fue, y se agrega
-- `insistir_banner`. Dejarlo como uno solo obligaría a elegir entre un emergente que reaparece y un
-- banner que reaparece, y son cosas distintas: el emergente interrumpe, el banner acompaña.
--
-- El muro social sigue sin acusar: ahí no se descarta nada.

-- ─── 1. Canal en el acuse ────────────────────────────────────────────────────

ALTER TABLE avisos_vistos
  ADD COLUMN IF NOT EXISTS canal text;

-- Los acuses que ya existen vienen todos del botón «Entendido» del emergente: es el único que
-- escribía antes de este cambio. Se marcan como MODAL para no descartar banners que nadie descartó.
UPDATE avisos_vistos SET canal = 'MODAL' WHERE canal IS NULL;

ALTER TABLE avisos_vistos
  ALTER COLUMN canal SET NOT NULL;

ALTER TABLE avisos_vistos
  DROP CONSTRAINT IF EXISTS avisos_vistos_canal_valido;
ALTER TABLE avisos_vistos
  ADD CONSTRAINT avisos_vistos_canal_valido CHECK (canal IN ('MODAL', 'BANNER'));

-- La llave incluye el canal. Sigue siendo idempotente por canal, así que el cliente puede insertar
-- sin consultar antes.
ALTER TABLE avisos_vistos DROP CONSTRAINT IF EXISTS avisos_vistos_pkey;
ALTER TABLE avisos_vistos
  ADD CONSTRAINT avisos_vistos_pkey PRIMARY KEY (aviso_id, profile_id, canal);

COMMENT ON COLUMN avisos_vistos.canal IS
  'En qué canal se descartó: MODAL (botón Entendido) o BANNER (la ✕). El muro social no acusa. Cerrar uno no descarta el otro.';

-- ─── 2. Un «insistir» por canal ──────────────────────────────────────────────

ALTER TABLE avisos RENAME COLUMN insistir TO insistir_modal;

ALTER TABLE avisos
  ADD COLUMN IF NOT EXISTS insistir_banner boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN avisos.insistir_modal IS
  'El emergente reaparece en cada sesión aunque ya lo hayan cerrado, mientras el aviso esté vigente.';
COMMENT ON COLUMN avisos.insistir_banner IS
  'El banner reaparece al recargar la pantalla aunque ya lo hayan descartado, mientras el aviso esté vigente.';

-- ─── 3. La vista, con el acuse separado ──────────────────────────────────────

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
  a.insistir_modal,
  a.insistir_banner,
  a.desde,
  a.hasta,
  a.creado_en,
  -- Un booleano por canal. El cliente no tiene que saber cómo se guarda el acuse.
  EXISTS (SELECT 1 FROM avisos_vistos v
           WHERE v.aviso_id = a.id AND v.profile_id = auth.uid() AND v.canal = 'MODAL')
    AS visto_modal,
  EXISTS (SELECT 1 FROM avisos_vistos v
           WHERE v.aviso_id = a.id AND v.profile_id = auth.uid() AND v.canal = 'BANNER')
    AS visto_banner
FROM avisos a
WHERE a.activo
  AND now() >= a.desde
  AND (a.hasta IS NULL OR now() <= a.hasta)
  AND aviso_me_corresponde(a.para_todos, a.ubicaciones, a.areas, a.empresas, a.roles);

COMMENT ON VIEW avisos_para_mi IS
  'Los avisos vigentes que le corresponden a quien pregunta, con el acuse resuelto POR CANAL: visto_modal y visto_banner son independientes.';

-- ─── 4. El conteo cuenta personas, no acuses ─────────────────────────────────
--
-- Con el canal en la llave, una persona puede dejar dos renglones del mismo aviso —cerró el emergente
-- y descartó el banner— y el conteo diría 2 donde hay 1 persona.

DROP VIEW IF EXISTS avisos_conteo_vistos;

CREATE VIEW avisos_conteo_vistos
WITH (security_invoker = false) AS
SELECT a.id AS aviso_id, count(DISTINCT v.profile_id)::int AS vistos
FROM avisos a
LEFT JOIN avisos_vistos v ON v.aviso_id = a.id
WHERE is_admin() OR has_permission('show_avisos')
GROUP BY a.id;

COMMENT ON VIEW avisos_conteo_vistos IS
  'Cuántas PERSONAS acusaron cada aviso, sin decir quiénes y sin contar dos veces a quien descartó en dos canales. Sólo para quien gestiona avisos.';

REVOKE ALL ON avisos_conteo_vistos FROM authenticated;
GRANT SELECT ON avisos_conteo_vistos TO authenticated;
