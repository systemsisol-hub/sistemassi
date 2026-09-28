-- Incidencias: la pestaña RH se abre con un permiso propio, sea o no administrador.
--
-- Pedido del usuario el 28/09/2026: un interruptor «Incidencias: pestaña RH» en Usuarios, debajo del
-- de Incidencias, y que SOLO quien lo tenga vea esa pestaña —las solicitudes de todos, aprobarlas,
-- la tabla por quincena—, «independiente si es administrador o no».
--
-- ─── Por qué va en el TOKEN y no sólo en `profiles.permissions` ─────────────
--
-- Porque hoy cada usuario puede escribir su propio `profiles.permissions`: la política
-- `profiles_update_self` se lo permite, y es el hueco que quedó apuntado el 23/09/2026. Una política
-- que leyera ese permiso de `profiles` dejaría a CUALQUIERA encenderse el interruptor y leer las
-- vacaciones de toda la empresa.
--
-- Así que el permiso se copia a `app_metadata` del usuario, que viaja en el token de sesión y que
-- el usuario NO puede cambiar —igual que el rol de administrador que lee `is_admin()`—. La copia la
-- hace `update_user_admin`, la función con que la página de Usuarios guarda, que sólo corre para un
-- administrador. Las políticas leen el token.
--
-- Queda la misma debilidad que ya tiene `is_admin()`: `update_user_admin` comprueba el rol en
-- `profiles`, que también se puede escribir. No es peor que hoy, y se cierra con la tarea aparte.
--
-- ─── Lo que un permiso nuevo tarda en llegar ────────────────────────────────
--
-- El token se renueva solo cada hora. La pantalla lo renueva al entrar si ve el permiso en el
-- perfil y todavía no en el token, así que en la práctica llega al abrir Incidencias.

-- ─── 1. Quién es de RH ─────────────────────────────────────────────────────
create or replace function public.es_rh_incidencias()
returns boolean language sql stable
set search_path = ''
as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'incidencias_rh')::boolean, false)
$$;

comment on function public.es_rh_incidencias() is
  'Si quien pregunta tiene la pestaña RH de Incidencias. Lee el TOKEN, no profiles: ver '
  '20260928120000_incidencias_rh.sql.';

-- ─── 2. Guardar un usuario copia el permiso al token ───────────────────────
--
-- La misma función de siempre y con la misma firma; lo único nuevo es `incidencias_rh` en
-- `raw_app_meta_data`. Si no llegan permisos nuevos se toma el que ya tenía el perfil, igual que
-- hace la función con el resto.
create or replace function public.update_user_admin(
  user_id_param uuid,
  new_email text,
  new_full_name text,
  new_role text,
  new_status_sys text default 'ACTIVO'::text,
  is_blocked_param boolean default false,
  new_permissions jsonb default null::jsonb,
  new_status_rh text default 'ACTIVO'::text,
  new_password text default null::text,
  new_schedule_id uuid default null::uuid
)
returns void
language plpgsql
security definer
set search_path to 'public', 'auth', 'extensions'
as $function$
declare
  permisos jsonb;
begin
  if not exists (
    select 1 from public.profiles where id = auth.uid() and role = 'admin'
  ) then
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

-- ─── 2b. Y dar de alta también ─────────────────────────────────────────────
--
-- Al crear un usuario, la página NO pasa por `update_user_admin`: crea la cuenta con
-- `create_user_admin` y luego escribe el perfil directo. Así el permiso no llegaba al token —y el
-- rol de administrador tampoco, que ya pasaba antes de esto—. La página llama a esta función justo
-- después, y el token queda igual que el perfil.
create or replace function public.sincronizar_token_de_usuario(user_id_param uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'auth'
as $function$
begin
  if not public.is_admin() then
    raise exception 'No tienes permisos de administrador para actualizar usuarios.';
  end if;

  update auth.users u
     set raw_app_meta_data = coalesce(u.raw_app_meta_data, '{}'::jsonb) ||
           jsonb_build_object(
             'role', case when p.role = 'admin' then 'admin' else 'user' end,
             'incidencias_rh', coalesce((p.permissions ->> 'show_incidencias_rh')::boolean, false)
           ),
         updated_at = now()
    from public.profiles p
   where p.id = u.id and u.id = user_id_param;
end;
$function$;

revoke all on function public.sincronizar_token_de_usuario(uuid) from public, anon;
grant execute on function public.sincronizar_token_de_usuario(uuid) to authenticated;

-- ─── 3. Lo que RH puede hacer con las incidencias de los demás ─────────────
--
-- Ver todas, crear para cualquiera y cambiarlas —aprobar, cancelar, editar—. NO borrar: eso sigue
-- siendo de administrador, porque pasa por la papelera y en `trash` sólo inserta un administrador.
drop policy if exists "RH ve todas las incidencias" on public.incidencias;
create policy "RH ve todas las incidencias" on public.incidencias
  for select to authenticated using (public.es_rh_incidencias());

drop policy if exists "RH crea incidencias" on public.incidencias;
create policy "RH crea incidencias" on public.incidencias
  for insert to authenticated with check (public.es_rh_incidencias());

drop policy if exists "RH actualiza incidencias" on public.incidencias;
create policy "RH actualiza incidencias" on public.incidencias
  for update to authenticated
  using (public.es_rh_incidencias())
  with check (public.es_rh_incidencias());

-- ─── 4. Quien ya la veía, la sigue viendo ──────────────────────────────────
--
-- Hasta hoy la veían los administradores. Se les enciende el interruptor para que el cambio no les
-- quite nada al desplegar; desde Usuarios se apaga a quien no deba tenerla.
update public.profiles
   set permissions = coalesce(permissions, '{}'::jsonb) || '{"show_incidencias_rh": true}'::jsonb
 where role = 'admin';

update auth.users u
   set raw_app_meta_data = coalesce(u.raw_app_meta_data, '{}'::jsonb) || '{"incidencias_rh": true}'::jsonb
  from public.profiles p
 where p.id = u.id and p.role = 'admin';
