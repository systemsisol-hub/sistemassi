-- Cierra `update_user_password`, que cualquiera podía llamar sin sesión.
--
-- ─── El agujero ──────────────────────────────────────────────────────────────
--
-- `public.update_user_password(uuid, text)` era SECURITY DEFINER, tenía EXECUTE concedido a `anon`, y
-- su cuerpo entero era:
--
--   UPDATE auth.users SET encrypted_password = crypt(new_password, gen_salt('bf'))
--    WHERE id = user_id_param;
--
-- Sin una sola comprobación de quién llama. La llave `anon` va incrustada en la aplicación web —es
-- pública por diseño—, así que con esa llave y el UUID de una persona se le podía poner la contraseña
-- que se quisiera y entrar como ella, incluida una cuenta de administrador.
--
-- Su hermana `update_user_admin` sí se defiende con el bloque de abajo. A ésta se le olvidó, y
-- sobrevivió a la pasada de endurecimiento del 05/08 (`endurece_funciones_admin`) — que es la razón de
-- comprobar el resultado con `has_function_privilege` en lugar de dar por bueno el REVOKE:
--
--   select proname,
--          has_function_privilege('anon', oid, 'EXECUTE') as puede_anon,
--          proacl
--     from pg_proc join pg_namespace n on n.oid = pronamespace
--    where nspname = 'public' and prosecdef;
--
-- ─── El arreglo, en dos capas ────────────────────────────────────────────────
--
-- 1. La función comprueba que quien llama sea administrador. Es la capa que cuenta: vale aunque
--    alguien vuelva a conceder EXECUTE por descuido.
-- 2. Se revoca EXECUTE a `anon` (en otra migración, porque el permiso entra por sitios distintos en
--    cada función).
--
-- Lo que NO cambia: quien la usa de verdad es la página de Usuarios —`usuarios_page.dart:2249`— con la
-- sesión de un administrador, o sea el rol `authenticated`, que conserva su concesión explícita.

create or replace function public.update_user_password(user_id_param uuid, new_password text)
returns void
language plpgsql
security definer
set search_path to 'extensions', 'public', 'auth'
as $function$
begin
  -- Mismo bloque que `update_user_admin`. Sin sesión, `auth.uid()` es NULL y esto falla, que es
  -- exactamente lo que tiene que pasar.
  if not exists (
    select 1 from public.profiles
     where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'No tienes permisos de administrador para cambiar contrasenas.';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(new_password, extensions.gen_salt('bf'))
   where id = user_id_param;
end;
$function$;

revoke execute on function public.update_user_password(uuid, text) from anon;

revoke execute on function public.update_user_admin(
  uuid, text, text, text, text, boolean, jsonb, text, text, uuid
) from anon;

revoke execute on function public.whatsapp_resolver_telefono(text) from anon;
