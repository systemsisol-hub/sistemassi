-- `has_permission()` devolvia FALSE para todo el mundo, siempre.
--
-- Leia los permisos de `auth.jwt() -> app_metadata -> permissions`, y ahi no los escribe nadie:
-- `update_user_admin` los guarda en `raw_user_meta_data`. Medido el 28/08/2026 sobre 73 cuentas:
-- 0 con permisos en `app_metadata`, 49 en `user_metadata`. La funcion buscaba donde no estaban.
--
-- Consecuencia real, no teorica: las politicas del bucket de avisos son
-- `is_admin() OR has_permission('show_avisos')`, asi que GISELA ESTEVEZ -que tiene `show_avisos`
-- sin ser administradora- podia crear avisos pero no subirles imagen ni borrarla, y fallaba sin
-- decir que era un problema de permisos. Nadie lo reporto.
--
-- Salio a la luz al preparar el permiso de edicion de Herramientas: iba a construirlo encima de
-- esta funcion. Ver `20260828120000_herramientas_editor_por_asignacion.sql`, que acabo resolviendose
-- por asignacion y no por permiso, en parte por esto.
--
-- ─── Por que leer de `profiles` y no arreglar el escritor ─────────────────────
--
-- La otra salida era que `update_user_admin` escribiera tambien en `app_metadata`. Se descarto por
-- dos razones. Los permisos viajan en el token, asi que un cambio no surte efecto hasta que la
-- persona vuelve a iniciar sesion -y nadie le va a decir que lo haga-. Y quedarian DOS copias del
-- mismo dato, la del token y la de `profiles`, que es la forma segura de que se separen.
--
-- Leyendo de `profiles` el permiso vale desde el instante en que se concede. Cuesta una consulta
-- por comprobacion; a cambio, `is_admin()` sigue resolviendose contra el token -que si esta
-- poblado- y es la que se evalua en casi todas las politicas.
--
-- NO se toca `user_metadata`: es escribible por el propio usuario, asi que jamas debe decidir un
-- permiso. Esta funcion ya no lo mira.
create or replace function public.has_permission(param_permission text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(
    (select (p.permissions ->> param_permission)::boolean
       from profiles p
      where p.id = auth.uid()),
    false);
$$;

comment on function public.has_permission(text) is
  'Si quien llama tiene ese permiso en profiles.permissions. Lee de la tabla y no del token, para '
  'que un permiso concedido valga sin volver a iniciar sesion.';
