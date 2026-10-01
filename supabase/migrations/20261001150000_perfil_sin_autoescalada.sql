-- Nadie que no sea administrador puede cambiar su propio rol, sus permisos ni sus datos de RH.
--
-- Revision de seguridad del 01/10/2026 (docs/revision-seguridad-credenciales.md):
--
--   * `profiles_update_self` deja a cada quien actualizar SU renglon sin limite de columnas. Una cuenta
--     `usuario` se podia poner `role = 'admin'` y cualquier permiso (`has_permission()` lee
--     `profiles.permissions`, y con el protege 22 tablas).
--   * Cuatro funciones de administracion (`update_user_admin`, `update_user_password`,
--     `revoke_user_access`, `sincronizar_rol_en_jwt`) decidian quien es administrador leyendo
--     `profiles.role`. Con el rol que uno mismo se ponia, cambiaban la contraseña de cualquiera,
--     borraban cuentas o escribian el rol de administrador en el token.
--
-- Comprobado antes de aplicar: los 5 administradores tienen el rol tambien en el token
-- (`raw_app_meta_data.role = 'admin'`), asi que pasar a `is_admin()` no deja fuera a ninguno.

-- ── 1. El trigger ────────────────────────────────────────────────────────────────────────────────
--
-- Lo unico que la app actualiza sobre el perfil propio es la foto (`user_dashboard.dart`). Todo lo
-- demas lo cambian administradores (`profiles_all_admin`) o funciones con la llave de servicio, que no
-- traen sesion: con `auth.uid()` en NULL no se restringe nada.
--
-- Se llama `tr_0_…` para correr antes que `tr_sync_profile_names`, que puede reescribir `full_name`:
-- aqui se compara lo que mando el cliente, no lo que calcula ese trigger.
create or replace function public.proteger_columnas_de_perfil()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  cambiadas text[];
begin
  if auth.uid() is null or coalesce(public.is_admin(), false) then
    return new;
  end if;

  select array_agg(n.key order by n.key)
    into cambiadas
    from jsonb_each(to_jsonb(new)) as n(key, value)
   where n.key not in ('foto_url', 'updated_at')
     and (to_jsonb(old) -> n.key) is distinct from n.value;

  if cambiadas is not null then
    raise exception 'Solo un administrador puede cambiar: %', array_to_string(cambiadas, ', ')
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists tr_0_proteger_perfil on public.profiles;
create trigger tr_0_proteger_perfil
  before update on public.profiles
  for each row execute function public.proteger_columnas_de_perfil();

-- ── 2. Las funciones de administracion miran el token, no el perfil ────────────────────────────────
--
-- Igual que antes, salvo la comprobacion: `is_admin()` lee `app_metadata` del token, que el usuario no
-- puede escribir. Sin sesion sigue fallando, que es lo que tiene que pasar.

CREATE OR REPLACE FUNCTION public.revoke_user_access(user_id_param uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'No tienes permisos de administrador para eliminar usuarios.';
  end if;

  delete from auth.users where id = user_id_param;
end;
$function$;

CREATE OR REPLACE FUNCTION public.sincronizar_rol_en_jwt(user_id_param uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare
  rol_perfil text;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'No tienes permisos de administrador.';
  end if;

  select role::text into rol_perfil from public.profiles where id = user_id_param;
  if rol_perfil is null then
    raise exception 'No existe el perfil %', user_id_param;
  end if;

  update auth.users
     set raw_app_meta_data =
           coalesce(raw_app_meta_data, '{}'::jsonb)
           || jsonb_build_object('role',
                case when rol_perfil = 'admin' then 'admin' else 'user' end)
   where id = user_id_param;
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_user_admin(user_id_param uuid, new_email text, new_full_name text, new_role text, new_status_sys text DEFAULT 'ACTIVO'::text, is_blocked_param boolean DEFAULT false, new_permissions jsonb DEFAULT NULL::jsonb, new_status_rh text DEFAULT 'ACTIVO'::text, new_password text DEFAULT NULL::text, new_schedule_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare
  permisos jsonb;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'No tienes permisos de administrador para actualizar usuarios.';
  end if;

  permisos := coalesce(new_permissions,
                       (select p.permissions from public.profiles p where p.id = user_id_param),
                       '{}'::jsonb);

  update auth.users
  set
    email = lower(new_email),
    encrypted_password = case
      when new_password is not null and new_password <> ''
      then extensions.crypt(new_password, extensions.gen_salt('bf', 10))
      else encrypted_password
    end,
    raw_user_meta_data = raw_user_meta_data ||
      jsonb_build_object(
        'full_name', new_full_name,
        'role', new_role,
        'permissions', coalesce(new_permissions, raw_user_meta_data->'permissions'),
        'schedule_id', new_schedule_id
      ),
    raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) ||
      jsonb_build_object(
        'role', case when new_role = 'admin' then 'admin' else 'user' end,
        'incidencias_rh', coalesce((permisos ->> 'show_incidencias_rh')::boolean, false)
      ),
    updated_at = now(),
    banned_until = case when is_blocked_param
      then '3000-01-01 00:00:00+00'::timestamptz else null end
  where id = user_id_param;

  update public.profiles
  set
    email = lower(new_email),
    full_name = new_full_name,
    role = new_role::public.user_role,
    status_sys = new_status_sys,
    status_rh = new_status_rh,
    permissions = coalesce(new_permissions, permissions),
    is_blocked = is_blocked_param,
    schedule_id = coalesce(new_schedule_id, schedule_id)
  where id = user_id_param;
end;
$function$;

CREATE OR REPLACE FUNCTION public.update_user_password(user_id_param uuid, new_password text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'extensions', 'public', 'auth'
AS $function$
begin
  -- Sin sesion, `is_admin()` no es verdadero y esto falla, que es exactamente lo que tiene que pasar.
  if not coalesce(public.is_admin(), false) then
    raise exception 'No tienes permisos de administrador para cambiar contrasenas.';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(new_password, extensions.gen_salt('bf'))
   where id = user_id_param;
end;
$function$;
