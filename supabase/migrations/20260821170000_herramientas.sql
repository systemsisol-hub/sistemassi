-- Herramientas: catálogo de aplicaciones HTML alojadas dentro del sistema.
--
-- ─── Qué problema resuelve ───────────────────────────────────────────────────
--
-- Un proveedor externo mantiene el «Cotizador AG117» en su propia herramienta de diseño y nos
-- entrega un HTML autocontenido —6.4 MB, con las librerías, las fuentes y los 32 planos en SVG
-- dentro— cada vez que cambia algo. Nosotros sólo lo alojamos.
--
-- El archivo NO puede vivir en `web/` del repositorio. Ahí cada entrega costaría un
-- `flutter build web` y un `wrangler deploy` del sistema entero, y el ciclo de ellos es
-- «actualizo mis precios y te mando el HTML». Así que el archivo va a Storage y la fila a esta
-- tabla: un administrador sube la versión nueva desde la propia página y ya está arriba.
--
-- ─── Por qué copia la forma de BI y no la de Avisos ──────────────────────────
--
-- Es el mismo problema que `powerbi_links` + `powerbi_link_users`: un catálogo de cosas que se ven
-- embebidas y que no le tocan a todo el mundo. Se reusa esa forma —tabla + tabla de asignación por
-- usuario— para que quien ya sabe administrar BI sepa administrar esto sin aprender nada nuevo.
--
-- La diferencia está en el bucket: BI apunta a URLs de Microsoft y aquí el archivo es nuestro.

-- ─── 1. El catálogo ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS herramientas (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  titulo        text NOT NULL,
  descripcion   text,

  -- Agrupador libre para la rejilla ('Ventas', 'Operación'…). Texto y no una tabla de grupos como
  -- `bi_grupos`: con un puñado de herramientas, una tabla aparte obliga a mantener una pantalla de
  -- gestión de grupos para no aportar nada. Si algún día son decenas, se normaliza.
  grupo         text,

  -- Ruta del archivo dentro del bucket `herramientas`. NULL mientras la herramienta existe pero
  -- todavía no se le ha subido ningún HTML.
  archivo       text,

  -- Sube de uno en cada entrega y forma parte de la RUTA del archivo, no sólo del registro.
  --
  -- Es deliberado: si la ruta fuera fija y se sobrescribiera, el navegador de cada asesor podría
  -- seguir sirviendo de su caché el HTML anterior, y nadie se enteraría de que está cotizando con
  -- precios viejos. Con una ruta nueva por versión, la actualización llega sí o sí.
  --
  -- Del bucket se conserva UNA SOLA versión: al subir una nueva, la página borra las anteriores. Los
  -- archivos pesan varios MB y acumularlos no aporta nada; si una entrega sale mal, el proveedor
  -- manda otra corregida. El contador, en cambio, sigue subiendo: es lo que hace que la ruta cambie.
  version       integer NOT NULL DEFAULT 0,

  -- Tamaño en bytes de la versión vigente. Se guarda para poder mostrarlo sin ir a Storage: son
  -- archivos de varios MB y quien sube quiere ver que subió lo que creía.
  archivo_bytes bigint,

  subido_por    uuid REFERENCES profiles(id) ON DELETE SET NULL,
  subido_en     timestamptz,

  is_active     boolean NOT NULL DEFAULT true,
  created_by    uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE herramientas IS
  'Catálogo de herramientas HTML alojadas y mostradas dentro del sistema. El archivo vive en el bucket herramientas; `version` forma parte de su ruta para que una entrega nueva no la sirva la caché del navegador.';

COMMENT ON COLUMN herramientas.version IS
  'Se incrementa en cada subida y va en la ruta del archivo (<id>/v<version>.html). Ruta nueva por versión = nadie se queda con el HTML anterior en caché.';

-- ─── 2. Quién ve cada herramienta ────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS herramientas_users (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  herramienta_id uuid NOT NULL REFERENCES herramientas(id) ON DELETE CASCADE,
  user_id        uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (herramienta_id, user_id)
);

CREATE INDEX IF NOT EXISTS herramientas_users_user_idx
  ON herramientas_users (user_id);

COMMENT ON TABLE herramientas_users IS
  'Asignación de herramientas por usuario, igual que powerbi_link_users. El permiso show_herramientas abre la página; esta tabla decide qué aparece dentro.';

-- ─── 3. Acceso ───────────────────────────────────────────────────────────────
--
-- Dos niveles, como en BI: el permiso `show_herramientas` deja entrar a la página, y la asignación
-- decide qué se ve. Administrar —crear, subir archivo, asignar— es sólo de administradores: subir el
-- HTML equivale a publicar la herramienta para todos los asignados.

ALTER TABLE herramientas       ENABLE ROW LEVEL SECURITY;
ALTER TABLE herramientas_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS herramientas_select_asignadas ON herramientas;
CREATE POLICY herramientas_select_asignadas
  ON herramientas FOR SELECT TO authenticated
  USING (
    is_admin()
    OR (
      is_active
      AND EXISTS (
        SELECT 1 FROM herramientas_users hu
        WHERE hu.herramienta_id = herramientas.id
          AND hu.user_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS herramientas_gestion_admin ON herramientas;
CREATE POLICY herramientas_gestion_admin
  ON herramientas FOR ALL TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

-- Cada quien puede leer sus propias asignaciones —la página las necesita para saber qué mostrar— y
-- sólo un administrador las cambia.
DROP POLICY IF EXISTS herramientas_users_select_propias ON herramientas_users;
CREATE POLICY herramientas_users_select_propias
  ON herramientas_users FOR SELECT TO authenticated
  USING (is_admin() OR user_id = auth.uid());

DROP POLICY IF EXISTS herramientas_users_gestion_admin ON herramientas_users;
CREATE POLICY herramientas_users_gestion_admin
  ON herramientas_users FOR ALL TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

-- ─── 4. El bucket ────────────────────────────────────────────────────────────
--
-- PRIVADO, al contrario que `avisos-imagenes`. Un cotizador lleva la lista de precios completa del
-- proyecto y los planos del cliente; con un bucket público bastaría con adivinar la URL. Se sirve
-- con URL firmada, que caduca.
--
-- Bucket propio y no reusar `knowledge-files` por lo mismo que se razonó con las imágenes de avisos:
-- cosas con vidas distintas no comparten bucket, o el límite de tamaño no puede ser razonable para
-- ninguna de las dos. Aquí el límite tiene que ser generoso —el HTML entregado hoy pesa 6.4 MB y la
-- versión anterior pesaba 13.6 MB porque los planos venían en JPEG en lugar de SVG—.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'herramientas',
  'herramientas',
  false,
  -- 50 MB. Deja margen de sobra sobre los 13.6 MB del peor caso visto, y el tope lo impone el
  -- servidor: validar sólo en el cliente deja la puerta abierta a subir por API.
  52428800,
  ARRAY['text/html']
)
ON CONFLICT (id) DO UPDATE
  SET public = false,
      file_size_limit = 52428800,
      allowed_mime_types = ARRAY['text/html'];

-- Leer: quien tiene la página. Es más grueso que la asignación por herramienta —con la ruta se
-- podría firmar el archivo de otra— y se acepta a conciencia: la asignación gobierna lo que se ve en
-- la interfaz, y las rutas no se publican. Si algún día hace falta cerrarlo por herramienta, la
-- política tendría que cruzar el primer segmento de `name` contra `herramientas_users`.
DROP POLICY IF EXISTS herramientas_archivos_select ON storage.objects;
CREATE POLICY herramientas_archivos_select
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'herramientas'
         AND (is_admin() OR has_permission('show_herramientas')));

DROP POLICY IF EXISTS herramientas_archivos_insert_admin ON storage.objects;
CREATE POLICY herramientas_archivos_insert_admin
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'herramientas' AND is_admin());

DROP POLICY IF EXISTS herramientas_archivos_update_admin ON storage.objects;
CREATE POLICY herramientas_archivos_update_admin
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'herramientas' AND is_admin());

DROP POLICY IF EXISTS herramientas_archivos_delete_admin ON storage.objects;
CREATE POLICY herramientas_archivos_delete_admin
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'herramientas' AND is_admin());
