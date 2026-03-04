-- =============================================================================
-- FIX: type "user_role" does not exist (Error 42704)
-- =============================================================================
-- Al vaciar el search_path por temas de seguridad estricta, PostgreSQL ya no
-- encuentra el tipo personalizado "user_role" porque no está buscando en el
-- esquema "public" automáticamente.
-- Solución: Añadir el prefijo "public." a todas las referencias de user_role.

-- A. Función: handle_new_user (Trigger)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  is_admin_user boolean;
BEGIN
  is_admin_user := (COALESCE(new.raw_user_meta_data->>'role', 'usuario') = 'admin');

  INSERT INTO public.profiles (id, full_name, role, is_blocked, permissions)
  VALUES (
    new.id, 
    COALESCE(new.raw_user_meta_data->>'full_name', 'Nuevo Usuario'), 
    (COALESCE(new.raw_user_meta_data->>'role', 'usuario'))::public.user_role,
    (new.banned_until IS NOT NULL AND new.banned_until > now()),
    CASE 
      WHEN is_admin_user THEN '{"show_users": true, "show_issi": true, "show_cssi": true, "show_logs": true}'::jsonb
      ELSE '{"show_users": false, "show_issi": false, "show_cssi": false, "show_logs": false}'::jsonb
    END
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    role = EXCLUDED.role,
    is_blocked = EXCLUDED.is_blocked;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- B. Función de Actualización (Admin RPC)
CREATE OR REPLACE FUNCTION public.update_user_admin(
  user_id_param uuid,
  new_email text,
  new_full_name text,
  new_role text,
  new_status_sys text DEFAULT 'ACTIVO',
  is_blocked_param boolean DEFAULT false,
  new_permissions jsonb DEFAULT NULL,
  new_status_rh text DEFAULT 'ACTIVO',
  new_password text DEFAULT NULL
)
RETURNS void AS $$
BEGIN
  -- 0. Verificar permisos de administrador
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'No tienes permisos de administrador para actualizar usuarios.';
  END IF;

  -- A. Actualizar auth.users
  UPDATE auth.users
  SET 
    email = LOWER(new_email),
    encrypted_password = CASE 
      WHEN new_password IS NOT NULL AND new_password <> '' 
      THEN extensions.crypt(new_password, extensions.gen_salt('bf', 10)) 
      ELSE encrypted_password 
    END,
    raw_user_meta_data = raw_user_meta_data || 
      jsonb_build_object(
        'full_name', new_full_name,
        'role', new_role,
        'permissions', COALESCE(new_permissions, raw_user_meta_data->'permissions')
      ),
    updated_at = now(),
    banned_until = CASE WHEN is_blocked_param THEN '3000-01-01 00:00:00+00'::timestamptz ELSE NULL END
  WHERE id = user_id_param;

  -- B. Actualizar public.profiles (AQUÍ ESTÁ EL ARREGLO ESTRELLA -> ::public.user_role)
  UPDATE public.profiles
  SET
    email = LOWER(new_email),
    full_name = new_full_name,
    role = new_role::public.user_role,
    status_sys = new_status_sys,
    status_rh = new_status_rh,
    is_blocked = is_blocked_param,
    permissions = COALESCE(new_permissions, permissions),
    updated_at = now()
  WHERE id = user_id_param;

  -- C. Actualizar identidades
  UPDATE auth.identities
  SET identity_data = identity_data || jsonb_build_object('email', LOWER(new_email))
  WHERE user_id = user_id_param AND provider = 'email';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

NOTIFY pgrst, 'reload schema';
