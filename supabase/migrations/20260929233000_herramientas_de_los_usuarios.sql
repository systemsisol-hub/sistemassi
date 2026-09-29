-- Los usuarios crean sus propias herramientas y deciden quién las ve.
--
-- Pedido del 29/09/2026: que no sólo el administrador pueda crear herramientas, y que quien las
-- crea pueda darle acceso a los usuarios de la lista.
--
-- ─── Quién puede crear ───────────────────────────────────────────────────────
--
-- Quien tiene el acceso «Herramientas» (`show_herramientas`), el mismo interruptor que le abre la
-- página. Se lee de `profiles.permissions`, como lo lee el menú, y no del token: `has_permission()`
-- lee `app_metadata`, donde los permisos no se copian.
--
-- Al crearla, quien la crea queda ASIGNADO y como EDITOR (`puede_editar`). Así todo lo demás —subir
-- versiones, editarla, borrarla, y el bucket— sale de las políticas que ya existen por asignación,
-- sin una vía nueva para el creador.
--
-- ─── Qué puede hacer un editor con los accesos ───────────────────────────────
--
-- Dar y quitar el acceso de LECTURA de sus herramientas. Lo que no puede: dar ni quitar el permiso
-- de editar (`puede_editar`), que sigue siendo de administración. Por eso sus políticas exigen
-- `not puede_editar` en la fila: no puede crear editores, ni borrar a un editor —tampoco a sí
-- mismo, que lo dejaría fuera de su propia herramienta—.

create or replace function public.tiene_acceso_herramientas()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(
    (select p.permissions -> 'show_herramientas' = 'true'::jsonb
       from profiles p where p.id = auth.uid()),
    false);
$$;

revoke execute on function public.tiene_acceso_herramientas() from public;
grant execute on function public.tiene_acceso_herramientas() to authenticated;

-- ─── Crear ───────────────────────────────────────────────────────────────────
--
-- `created_by` tiene que ser quien la crea: es lo que el disparador usa para hacerlo editor.
drop policy if exists herramientas_insert_usuario on public.herramientas;
create policy herramientas_insert_usuario on public.herramientas
  for insert to authenticated
  with check (created_by = auth.uid() and public.tiene_acceso_herramientas());

-- El creador queda asignado como editor. SECURITY DEFINER porque todavía no es editor de nada
-- cuando se inserta su fila. Al administrador no se le asigna: ya ve y mantiene todas.
--
-- `coalesce` porque `is_admin()` devuelve NULL —no false— cuando el token no trae `role` en
-- `app_metadata`, y `not NULL` se saltaría la asignación: el creador se quedaría sin su herramienta.
create or replace function public.herramienta_creada()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.created_by is not null and not coalesce(public.is_admin(), false) then
    insert into herramientas_users (herramienta_id, user_id, puede_editar)
    values (new.id, new.created_by, true)
    on conflict (herramienta_id, user_id) do update set puede_editar = true;
  end if;
  return new;
end $$;

revoke execute on function public.herramienta_creada() from public;

drop trigger if exists tr_herramienta_creada on public.herramientas;
create trigger tr_herramienta_creada
  after insert on public.herramientas
  for each row execute function public.herramienta_creada();

-- ─── Dar y quitar acceso ─────────────────────────────────────────────────────
drop policy if exists herramientas_users_insert_editor on public.herramientas_users;
create policy herramientas_users_insert_editor on public.herramientas_users
  for insert to authenticated
  with check (public.herramienta_editable_id(herramienta_id) and not puede_editar);

-- La app da el acceso con `upsert`, que en un conflicto se vuelve UPDATE.
drop policy if exists herramientas_users_update_editor on public.herramientas_users;
create policy herramientas_users_update_editor on public.herramientas_users
  for update to authenticated
  using (public.herramienta_editable_id(herramienta_id) and not puede_editar)
  with check (public.herramienta_editable_id(herramienta_id) and not puede_editar);

drop policy if exists herramientas_users_delete_editor on public.herramientas_users;
create policy herramientas_users_delete_editor on public.herramientas_users
  for delete to authenticated
  using (public.herramienta_editable_id(herramienta_id) and not puede_editar);
