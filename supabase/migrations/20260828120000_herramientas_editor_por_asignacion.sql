-- Quien puede ACTUALIZAR una herramienta sin ser administrador.
--
-- El caso: una persona se encarga del Cotizador de ventas y tiene que subirle versiones nuevas.
-- Hasta ahora los cuatro candados de la página pedían `is_admin()` —la interfaz, la tabla, y el
-- INSERT/UPDATE/DELETE del bucket—, así que la única forma de dejarla trabajar era hacerla
-- administradora del sistema entero.
--
-- ─── Por qué por ASIGNACIÓN y no con un permiso de ACCESOS ────────────────────
--
-- Un interruptor global habría concedido bastante más de lo que se pidió: crear y BORRAR cualquier
-- herramienta, incluidas las que se creen después. Colgándolo de la asignación que ya existe, la
-- persona manda sobre las herramientas que se le den y sobre ninguna otra.
--
-- Y hay una razón técnica igual de fuerte. El sistema ya tiene `has_permission()`, que es lo que
-- usaríamos para un permiso de ACCESOS, y ESTÁ ROTA: lee los permisos de `app_metadata` mientras
-- `update_user_admin` los escribe en `user_metadata`. Medido el 28/08/2026: de 73 cuentas, 0 tienen
-- permisos en `app_metadata` y 49 los tienen en `user_metadata`, así que devuelve `false` siempre.
-- Se arregla aparte; construir esto encima habría dado botones que no funcionan.
--
-- Leer la tabla de asignaciones tiene además una ventaja sobre leer el token: surte efecto en el
-- momento, sin que la persona tenga que volver a iniciar sesión.

alter table public.herramientas_users
  add column if not exists puede_editar boolean not null default false;

comment on column public.herramientas_users.puede_editar is
  'Si esta persona puede subir versiones, editar y borrar ESTA herramienta sin ser administradora.';

-- ─── El equivalente de `herramienta_asignada`, pero para escribir ─────────────
--
-- Misma forma y mismo truco: la ruta del archivo en el bucket empieza por el id de la herramienta
-- —`{id}/{version}/archivo.html`—, así que `split_part(ruta,'/',1)` dice de cuál se trata.
--
-- SECURITY DEFINER porque la política del bucket la evalúa quien sube el archivo, que no tiene por
-- qué poder leer `herramientas_users` de los demás. `stable` para que el planificador no la llame
-- una vez por fila.
create or replace function public.herramienta_editable(p_ruta text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from herramientas h
    join herramientas_users hu on hu.herramienta_id = h.id
    where hu.user_id = auth.uid()
      and hu.puede_editar
      and h.id::text = split_part(p_ruta, '/', 1)
  );
$$;

revoke execute on function public.herramienta_editable(text) from public;
grant execute on function public.herramienta_editable(text) to authenticated;

-- Y la versión por id, para las políticas de la TABLA, donde no hay ruta que partir.
create or replace function public.herramienta_editable_id(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from herramientas_users hu
    where hu.user_id = auth.uid() and hu.herramienta_id = p_id and hu.puede_editar
  );
$$;

revoke execute on function public.herramienta_editable_id(uuid) from public;
grant execute on function public.herramienta_editable_id(uuid) to authenticated;

-- ─── La tabla ────────────────────────────────────────────────────────────────
--
-- Se AÑADEN políticas en lugar de tocar `herramientas_gestion_admin`: las permisivas se suman con
-- OR, así que el administrador conserva exactamente lo que tenía y esto sólo abre el caso nuevo.
--
-- El editor NO puede crear herramientas: no hay política de INSERT para él. Crear una es decidir
-- que existe, y eso sigue siendo de administración.
--
-- `with check` repite la condición para que no pueda reasignar la fila a otra herramienta en el
-- mismo UPDATE y quedarse mandando sobre una que no le dieron.
drop policy if exists herramientas_update_editor on public.herramientas;
create policy herramientas_update_editor on public.herramientas
  for update to authenticated
  using (public.herramienta_editable_id(id))
  with check (public.herramienta_editable_id(id));

drop policy if exists herramientas_delete_editor on public.herramientas;
create policy herramientas_delete_editor on public.herramientas
  for delete to authenticated
  using (public.herramienta_editable_id(id));

-- ─── El bucket ───────────────────────────────────────────────────────────────
--
-- Las tres que faltaban. Sin ellas los botones aparecerían y fallarían al pulsarlos, que es peor
-- que no tenerlos: el error de storage no dice que sea un problema de permisos.
drop policy if exists herramientas_archivos_insert_editor on storage.objects;
create policy herramientas_archivos_insert_editor on storage.objects
  for insert to authenticated
  with check (bucket_id = 'herramientas' and public.herramienta_editable(name));

drop policy if exists herramientas_archivos_update_editor on storage.objects;
create policy herramientas_archivos_update_editor on storage.objects
  for update to authenticated
  using (bucket_id = 'herramientas' and public.herramienta_editable(name))
  with check (bucket_id = 'herramientas' and public.herramienta_editable(name));

drop policy if exists herramientas_archivos_delete_editor on storage.objects;
create policy herramientas_archivos_delete_editor on storage.objects
  for delete to authenticated
  using (bucket_id = 'herramientas' and public.herramienta_editable(name));

-- ─── Y que el editor siga viendo la suya si la desactiva ─────────────────────
--
-- La política de lectura exigía `is_active`. Un editor que apagara su propia herramienta desde el
-- formulario dejaría de verla en el mismo instante, y sin verla no puede volver a encenderla:
-- quedaría fuera de su alcance hasta que un administrador la rescatara.
--
-- Se le añade la vía del editor SIN la condición de `is_active`. Para los demás asignados no cambia
-- nada: siguen viendo sólo las activas.
drop policy if exists herramientas_select_asignadas on public.herramientas;
create policy herramientas_select_asignadas on public.herramientas
  for select to authenticated
  using (
    public.is_admin()
    or (is_active and exists (
      select 1 from herramientas_users hu
      where hu.herramienta_id = herramientas.id and hu.user_id = auth.uid()
    ))
    or public.herramienta_editable_id(id)
  );
