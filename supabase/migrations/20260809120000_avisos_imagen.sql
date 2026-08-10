-- Imagen opcional en el aviso, para la ventana emergente y el muro social.
--
-- El banner NO la muestra, y no por falta de ganas: es una franja de ~40px de alto bajo la barra de
-- navegación. Meterle una imagen la convierte en un bloque que empuja la página hacia abajo, que es
-- justo lo que se evitó al mostrar un solo banner con contador en lugar de apilarlos.
--
-- ─── Un bucket propio ────────────────────────────────────────────────────────
--
-- No se reusa `employee_photos` —905 objetos de fotos de gente— ni `knowledge-files`: mezclar cosas
-- con vidas distintas en un bucket hace imposible ponerle un límite razonable a cada una, y borrar un
-- aviso viejo obligaría a distinguir sus archivos de los ajenos.
--
-- Público en lectura porque la imagen se pinta con su URL directa; el control está en quién puede
-- ESCRIBIR. Consecuencia que hay que tener clara: quien tenga la URL puede abrirla sin sesión, así que
-- una imagen de aviso no es un lugar para poner nada confidencial.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avisos-imagenes',
  'avisos-imagenes',
  true,
  -- 5 MB. Un aviso con una imagen más grande que eso no es un aviso, y el tope lo impone el servidor
  -- y no la pantalla: validar sólo en el cliente deja la puerta abierta a subir por API.
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE
  SET public = true,
      file_size_limit = 5242880,
      allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

-- Escribir, sólo quien gestiona avisos. Leer lo permite el bucket público.
DROP POLICY IF EXISTS avisos_imagenes_insert_gestion ON storage.objects;
CREATE POLICY avisos_imagenes_insert_gestion
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avisos-imagenes'
              AND (is_admin() OR has_permission('show_avisos')));

DROP POLICY IF EXISTS avisos_imagenes_update_gestion ON storage.objects;
CREATE POLICY avisos_imagenes_update_gestion
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'avisos-imagenes'
         AND (is_admin() OR has_permission('show_avisos')));

DROP POLICY IF EXISTS avisos_imagenes_delete_gestion ON storage.objects;
CREATE POLICY avisos_imagenes_delete_gestion
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'avisos-imagenes'
         AND (is_admin() OR has_permission('show_avisos')));

-- ─── La columna ──────────────────────────────────────────────────────────────

ALTER TABLE avisos
  ADD COLUMN IF NOT EXISTS imagen_url text;

COMMENT ON COLUMN avisos.imagen_url IS
  'URL pública de la imagen del aviso, en el bucket avisos-imagenes. Se muestra en la ventana emergente y en el muro social; el banner no la usa porque es una franja. NULL = sin imagen.';

-- ─── La vista la expone ──────────────────────────────────────────────────────

DROP VIEW IF EXISTS avisos_para_mi;

CREATE VIEW avisos_para_mi
WITH (security_invoker = true) AS
SELECT
  a.id,
  a.titulo,
  a.cuerpo,
  a.nivel,
  a.imagen_url,
  a.en_modal,
  a.en_banner,
  a.en_social,
  a.insistir_modal,
  a.insistir_banner,
  a.desde,
  a.hasta,
  a.creado_en,
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
