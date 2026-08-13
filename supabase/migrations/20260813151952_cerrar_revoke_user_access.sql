-- `revoke_user_access` borraba cuentas sin preguntar quién llamaba.
--
-- Era SECURITY DEFINER, con EXECUTE para `anon`, y su cuerpo entero era:
--
--   DELETE FROM auth.users WHERE id = user_id_param;
--
-- Con la llave `anon` —que va incrustada en la aplicación web y por tanto es pública— cualquiera podía
-- borrar la cuenta de cualquiera, incluidas todas las de administrador. Destructivo e irreversible, y
-- en eso es peor que el agujero de la contraseña: de una toma de control se sale cambiando la clave.
--
-- Quien la usa de verdad es la página de Usuarios —`usuarios_page.dart:2303`— con la sesión de un
-- administrador, o sea el rol `authenticated`, que conserva su concesión explícita.

create or replace function public.revoke_user_access(user_id_param uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'auth'
as $function$
begin
  if not exists (
    select 1 from public.profiles
     where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'No tienes permisos de administrador para eliminar usuarios.';
  end if;

  delete from auth.users where id = user_id_param;
end;
$function$;

revoke execute on function public.revoke_user_access(uuid) from public;

-- Menor, pero gratis: subir el contador de vistas de un artículo no es para quien no ha entrado.
-- La llama `knowledge_page.dart:468` con sesión, así que `authenticated` basta.
revoke execute on function public.increment_knowledge_views(uuid) from public;

-- ─── Lo que NO se toca, y por qué ────────────────────────────────────────────
--
-- `get_active_users_count` la llama la PANTALLA DE LOGIN —`login_page.dart:47`—, antes de que haya
-- sesión, así que corre como `anon` y **necesita** el permiso. Revocar en bloque todo lo que el linter
-- marca habría roto el login. Expone una cuenta agregada a quien no ha entrado, y eso es por diseño.
--
-- Tampoco se tocan `is_admin`, `is_event_creator`, `is_event_invitee`, `has_permission`,
-- `get_user_role` ni `aviso_me_corresponde`: se usan DENTRO de políticas RLS, que se evalúan con el rol
-- que consulta, así que quitarles EXECUTE puede cerrar lecturas legítimas por caminos que hay que
-- revisar una por una.
--
-- Ni las de disparador —`handle_new_user`, `handle_profiles_status_sys_*`, `notify_event_invitation`,
-- `set_default_app_metadata`, `rls_auto_enable`, `log_event`—: el disparador se ejecuta con el dueño de
-- la tabla y no depende del EXECUTE del rol, pero varias son además invocables por RPC y hay que mirar
-- qué hacen si alguien las llama a mano. Van en otra pasada, no de arrastre con esto.
