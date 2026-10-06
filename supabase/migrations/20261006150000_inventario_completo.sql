-- Inventario de cómputo más completo (06/10/2026, a pedido del usuario).
--
-- 1. Fotos: el bucket `issi-docs` solo aceptaba PDF de hasta 400 KB y rechazaba las fotos (400).
-- 2. Seguridad de `issi-docs`: cualquier sesión veía, subía y borraba cualquier resguardo. Ahora
--    como la tabla: admin / edit_issi todo; show_issi ver; cada quien ve y sube en la carpeta de sus
--    propios equipos (el resguardo firmado).
-- 3. Datos unificados: LAP-TOP → LAPTOP, TEL. CELULAR → CELULAR, NO-BREACK → NO-BREAK,
--    BUENO → USADO, MALO → DAÑADO, KINGGSTON → KINGSTON, KIOCERA → KYOCERA.
-- 4. Campos nuevos: número de inventario (único, para la etiqueta QR), compra y garantía, software,
--    red / línea, accesorios y baja.
-- 5. `issi_asignaciones`: historial de quién tuvo cada equipo; lo llena un trigger al cambiar el
--    usuario, así no depende de la app.
-- 6. `issi_mantenimientos`: mantenimientos y reparaciones de cada equipo.

-- ── 1. Bucket ───────────────────────────────────────────────────────────────────────────────────
update storage.buckets
   set allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'],
       file_size_limit = 3145728
 where id = 'issi-docs';

-- ── 2. Políticas de issi-docs ───────────────────────────────────────────────────────────────────
create or replace function public.puede_ver_archivo_inventario(p_nombre text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.is_admin(), false)
      or public.has_permission('edit_issi')
      or public.has_permission('show_issi')
      or exists (
           select 1 from public.issi_inventory i
            where i.usuario_id = auth.uid()
              and i.id::text = (storage.foldername(p_nombre))[2]);
$$;

create or replace function public.puede_subir_archivo_inventario(p_nombre text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.is_admin(), false)
      or public.has_permission('edit_issi')
      or exists (
           select 1 from public.issi_inventory i
            where i.usuario_id = auth.uid()
              and i.id::text = (storage.foldername(p_nombre))[2]);
$$;

revoke all on function public.puede_ver_archivo_inventario(text) from public, anon;
revoke all on function public.puede_subir_archivo_inventario(text) from public, anon;
grant execute on function public.puede_ver_archivo_inventario(text) to authenticated;
grant execute on function public.puede_subir_archivo_inventario(text) to authenticated;

drop policy if exists issi_docs_select on storage.objects;
drop policy if exists issi_docs_insert on storage.objects;
drop policy if exists issi_docs_update on storage.objects;
drop policy if exists issi_docs_delete on storage.objects;

create policy issi_docs_select on storage.objects for select to authenticated
  using (bucket_id = 'issi-docs' and public.puede_ver_archivo_inventario(name));
create policy issi_docs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'issi-docs' and public.puede_subir_archivo_inventario(name));
create policy issi_docs_update on storage.objects for update to authenticated
  using (bucket_id = 'issi-docs' and public.puede_subir_archivo_inventario(name));
create policy issi_docs_delete on storage.objects for delete to authenticated
  using (bucket_id = 'issi-docs'
         and (coalesce(public.is_admin(), false) or public.has_permission('edit_issi')));

-- ── 3. Datos unificados ─────────────────────────────────────────────────────────────────────────
update public.issi_inventory set tipo = 'LAPTOP'   where tipo = 'LAP-TOP';
update public.issi_inventory set tipo = 'CELULAR'  where tipo = 'TEL. CELULAR';
update public.issi_inventory set tipo = 'NO-BREAK' where tipo = 'NO-BREACK';
update public.issi_inventory set condicion = 'USADO'  where condicion = 'BUENO';
update public.issi_inventory set condicion = 'DAÑADO' where condicion = 'MALO';
update public.issi_inventory set marca = 'KINGSTON' where marca = 'KINGGSTON';
update public.issi_inventory set marca = 'KYOCERA'  where marca = 'KIOCERA';

-- ── 4. Campos nuevos ────────────────────────────────────────────────────────────────────────────
create sequence if not exists public.issi_numero_inventario_seq;

alter table public.issi_inventory
  add column if not exists numero_inventario text,
  add column if not exists fecha_compra      date,
  add column if not exists proveedor         text,
  add column if not exists factura           text,
  add column if not exists garantia_hasta    date,
  add column if not exists sistema_operativo text,
  add column if not exists licencias         text,
  add column if not exists antivirus         text,
  add column if not exists nombre_equipo     text,
  add column if not exists mac               text,
  add column if not exists linea             text,
  add column if not exists compania          text,
  add column if not exists accesorios        text,
  add column if not exists fecha_baja        date,
  add column if not exists motivo_baja       text;

-- Los existentes, en el orden en que se dieron de alta.
with numerados as (
  select id, row_number() over (order by created_at, id) as n
    from public.issi_inventory
   where numero_inventario is null
)
update public.issi_inventory i
   set numero_inventario = 'INV-' || lpad(n::text, 4, '0')
  from numerados
 where numerados.id = i.id;

select setval('public.issi_numero_inventario_seq',
              greatest((select count(*) from public.issi_inventory), 1));

alter table public.issi_inventory
  alter column numero_inventario
    set default 'INV-' || lpad(nextval('public.issi_numero_inventario_seq')::text, 4, '0');

create unique index if not exists issi_inventory_numero_inventario_key
  on public.issi_inventory (numero_inventario);

-- ── 5. Historial de asignaciones ────────────────────────────────────────────────────────────────
create table if not exists public.issi_asignaciones (
  id              uuid primary key default gen_random_uuid(),
  equipo_id       uuid not null references public.issi_inventory(id) on delete cascade,
  usuario_id      uuid,
  usuario_nombre  text,
  ubicacion       text,
  desde           timestamptz not null default now(),
  hasta           timestamptz,
  registrado_por  uuid
);

create index if not exists issi_asignaciones_equipo_idx on public.issi_asignaciones (equipo_id, desde);

alter table public.issi_asignaciones enable row level security;

drop policy if exists issi_asignaciones_ver on public.issi_asignaciones;
create policy issi_asignaciones_ver on public.issi_asignaciones for select to authenticated
  using (coalesce(public.is_admin(), false)
         or public.has_permission('edit_issi')
         or public.has_permission('show_issi')
         or usuario_id = auth.uid());

revoke all on public.issi_asignaciones from anon;
grant select on public.issi_asignaciones to authenticated;

create or replace function public._registrar_asignacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.usuario_id is not distinct from old.usuario_id then
    return null;
  end if;
  update public.issi_asignaciones
     set hasta = now()
   where equipo_id = new.id and hasta is null;
  if new.usuario_id is not null then
    insert into public.issi_asignaciones (equipo_id, usuario_id, usuario_nombre, ubicacion, registrado_por)
    values (new.id, new.usuario_id, new.usuario_nombre, new.ubicacion, auth.uid());
  end if;
  return null;
end;
$$;

drop trigger if exists tr_registrar_asignacion on public.issi_inventory;
create trigger tr_registrar_asignacion
  after insert or update of usuario_id on public.issi_inventory
  for each row execute function public._registrar_asignacion();

-- Lo que hay hoy: una asignación abierta por equipo, desde que se dio de alta.
insert into public.issi_asignaciones (equipo_id, usuario_id, usuario_nombre, ubicacion, desde)
select i.id, i.usuario_id, i.usuario_nombre, i.ubicacion, i.created_at
  from public.issi_inventory i
 where i.usuario_id is not null
   and not exists (select 1 from public.issi_asignaciones a where a.equipo_id = i.id);

-- ── 6. Mantenimientos ───────────────────────────────────────────────────────────────────────────
create table if not exists public.issi_mantenimientos (
  id             uuid primary key default gen_random_uuid(),
  equipo_id      uuid not null references public.issi_inventory(id) on delete cascade,
  fecha          date not null default current_date,
  tipo           text not null default 'PREVENTIVO'
                   check (tipo in ('PREVENTIVO', 'CORRECTIVO', 'REPARACION', 'ACTUALIZACION')),
  descripcion    text,
  costo          numeric,
  realizado_por  text,
  creado_por     uuid default auth.uid(),
  created_at     timestamptz not null default now()
);

create index if not exists issi_mantenimientos_equipo_idx on public.issi_mantenimientos (equipo_id, fecha);

alter table public.issi_mantenimientos enable row level security;

drop policy if exists issi_mantenimientos_ver on public.issi_mantenimientos;
create policy issi_mantenimientos_ver on public.issi_mantenimientos for select to authenticated
  using (coalesce(public.is_admin(), false)
         or public.has_permission('edit_issi')
         or public.has_permission('show_issi'));

drop policy if exists issi_mantenimientos_editar on public.issi_mantenimientos;
create policy issi_mantenimientos_editar on public.issi_mantenimientos for all to authenticated
  using (coalesce(public.is_admin(), false) or public.has_permission('edit_issi'))
  with check (coalesce(public.is_admin(), false) or public.has_permission('edit_issi'));

revoke all on public.issi_mantenimientos from anon;
grant select, insert, update, delete on public.issi_mantenimientos to authenticated;
