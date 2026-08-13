-- Cambiar el rol en la página de Usuarios no surtía efecto para la base de datos.
--
-- ─── El fallo ────────────────────────────────────────────────────────────────
--
-- Reportado: a RODRIGO CAMACHO CANO (0351) se le puso rol de administrador en la página, y al entrar a
-- su cuenta no veía los teléfonos del directorio ni la asistencia de nadie más que la suya.
--
-- Medido, y es una discrepancia entre los DOS sitios donde vive el rol:
--
--   profiles.role                        = admin   ← lo que muestra la página
--   auth.users.raw_app_meta_data->>'role' = user    ← lo que leen las políticas
--
-- `is_admin()` y `get_user_role()` resuelven con `auth.jwt() -> 'app_metadata' ->> 'role'`, y eso es
-- lo correcto: `user_metadata` lo puede escribir el propio usuario con su sesión, así que colgar los
-- permisos de ahí sería dejar que cualquiera se hiciera administrador.
--
-- Pero `update_user_admin` escribía el rol en `profiles` y en `raw_user_meta_data`, y NUNCA en
-- `raw_app_meta_data`. O sea que la aplicación creía «admin» —el menú y las páginas salían— mientras
-- la base seguía diciendo «user» y negaba las filas. De ahí el síntoma exacto: la página de Asistencia
-- se abre, pero sólo con sus propios registros.
--
-- Los 5 administradores que sí funcionan tienen `admin` en `app_metadata`, puesto por otra vía. Este
-- camino —el de la página— no lo había puesto nunca.
--
-- ─── Alcance ─────────────────────────────────────────────────────────────────
--
-- Un solo caso real, el 0351. Los otros 77 perfiles que parecían discrepar son la equivalencia normal
-- entre vocabularios: `profiles` guarda `usuario` y el claim dice `user`. Ninguna política compara
-- contra `'user'` —comprobado sobre `pg_policies`—, todo pasa por `is_admin()`, que sólo pregunta si es
-- `admin`. Por eso el mapeo de abajo manda `admin` o `user` y no traduce nada más.

create or replace function public.sincronizar_rol_en_jwt(user_id_param uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'auth'
as $function$
declare
  rol_perfil text;
begin
  if not exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  ) then
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

revoke execute on function public.sincronizar_rol_en_jwt(uuid) from anon;

-- ─── Y que la edición de usuarios lo haga sola ───────────────────────────────
--
-- Se añade el bloque a `update_user_admin`. Sólo se toca la clave `role` de `app_metadata`: el resto
-- de ese objeto lo maneja Supabase -`provider`, `providers`- y sobrescribirlo entero rompería el
-- inicio de sesión.
create or replace function public.update_user_admin(
  user_id_param uuid, new_email text, new_full_name text, new_role text,
  new_status_sys text default 'ACTIVO'::text, is_blocked_param boolean default false,
  new_permissions jsonb default null::jsonb, new_status_rh text default 'ACTIVO'::text,
  new_password text default null::text, new_schedule_id uuid default null::uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'auth', 'extensions'
as $function$
begin
  if not exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'No tienes permisos de administrador para actualizar usuarios.';
  end if;

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
    -- LO QUE FALTABA. Sin esto el rol nuevo no llegaba nunca a las políticas.
    raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) ||
      jsonb_build_object('role', case when new_role = 'admin' then 'admin' else 'user' end),
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

revoke execute on function public.update_user_admin(
  uuid, text, text, text, text, boolean, jsonb, text, text, uuid
) from public;

revoke execute on function public.update_user_admin(
  uuid, text, text, text, text, boolean, jsonb, text, text, uuid
) from anon;

-- ─── Reparar el caso que ya existe ───────────────────────────────────────────
--
-- Sólo donde `profiles` dice `admin` y el claim no. No se toca a los 79 restantes, que son coherentes.
--
-- OJO: el token que la persona ya tiene en el navegador sigue llevando el claim VIEJO. Tiene que
-- cerrar sesión y volver a entrar; con esperar no basta hasta el siguiente refresco.
update auth.users u
   set raw_app_meta_data = coalesce(u.raw_app_meta_data, '{}'::jsonb)
                           || jsonb_build_object('role', 'admin')
  from public.profiles p
 where p.id = u.id
   and p.role = 'admin'
   and coalesce(u.raw_app_meta_data->>'role', '') <> 'admin';
