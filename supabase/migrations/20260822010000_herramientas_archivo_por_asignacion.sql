-- El archivo de una herramienta se autoriza por ASIGNACIÓN, no por el permiso del JWT.
--
-- ─── Qué estaba roto ─────────────────────────────────────────────────────────
--
-- Un usuario veía la tarjeta de la herramienta y al abrirla recibía
-- `StorageException(Object not found, 404)`. El objeto existía y la fila apuntaba bien: era RLS
-- ocultándolo, y Storage responde «not found» en lugar de «prohibido».
--
-- La política anterior pedía `has_permission('show_herramientas')`, y esa función NO lee la tabla:
--
--   auth.jwt() -> 'app_metadata' -> 'permissions' ->> param_permission
--
-- Mientras que la aplicación decide el menú leyendo `profiles.permissions`. Así que un usuario con el
-- permiso puesto en la tabla ve la página y la tarjeta, pero la política le dice no. Medido: los tres
-- usuarios con `show_herramientas` en la tabla tenían CERO permisos en `app_metadata`. Al
-- administrador le funcionaba porque su rama es `is_admin()`, y ahí el JWT sí trae `role: admin` —
-- que es también por lo que no se detectó antes de publicarlo.
--
-- ─── Por qué esto es mejor y no sólo distinto ────────────────────────────────
--
-- La comprobación pasa a ser la asignación de la herramienta contra `auth.uid()`, que sale del token
-- de la petición y no puede estar desfasado respecto a nada.
--
-- Y de paso cierra lo que la migración anterior dejó abierto a conciencia: antes, cualquiera con el
-- permiso podía firmar el archivo de CUALQUIER herramienta si sabía su ruta. Ahora sólo el de las
-- suyas. La autorización del archivo queda igual que la de la fila.
--
-- El permiso `show_herramientas` sigue haciendo su trabajo: abre la página. Lo que ya no hace es
-- decidir el acceso al archivo.

CREATE OR REPLACE FUNCTION herramienta_asignada(p_ruta text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- La ruta es `<id de la herramienta>/v<n>.html`, así que el primer segmento es el identificador.
  SELECT EXISTS (
    SELECT 1
    FROM herramientas h
    JOIN herramientas_users hu ON hu.herramienta_id = h.id
    WHERE hu.user_id = auth.uid()
      AND h.is_active
      AND h.id::text = split_part(p_ruta, '/', 1)
  );
$$;

COMMENT ON FUNCTION herramienta_asignada(text) IS
  'Si a quien pregunta le está asignada la herramienta activa a la que pertenece esa ruta del bucket. SECURITY DEFINER para no arrastrar el RLS de herramientas dentro de la política de storage.objects.';

-- Igual que con el resto de funciones del proyecto: la usa una sesión autenticada, no `anon`.
REVOKE ALL ON FUNCTION herramienta_asignada(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION herramienta_asignada(text) FROM anon;
GRANT EXECUTE ON FUNCTION herramienta_asignada(text) TO authenticated;

DROP POLICY IF EXISTS herramientas_archivos_select ON storage.objects;
CREATE POLICY herramientas_archivos_select
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'herramientas'
         AND (is_admin() OR herramienta_asignada(name)));
