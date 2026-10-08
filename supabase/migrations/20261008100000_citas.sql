-- Citas: horarios que publica un profesional (p. ej. la nutrióloga) y que los usuarios apartan
-- (08/10/2026, a pedido del usuario).
--
-- Decisiones del usuario: general (sirve para cualquier servicio, no solo nutrición); una cita a la
-- vez por persona y servicio; se cancela hasta 2 horas antes; pueden apartar todos; al apartar solo
-- una nota opcional.
--
--   * `citas_espacios`: cada horario publicado. Nadie la lee directo: los demás solo deben ver
--     «ocupado», sin quién (es una cita de salud). Se usa por las funciones de abajo.
--   * `citas_publicar`: quien tiene el permiso `publicar_citas` (o es admin) crea sus horarios.
--   * `citas_apartar`: aparta con bloqueo de renglón (dos personas a la vez: gana la primera), crea
--     el evento en el calendario del profesional con la persona invitada, y avisa a los dos.
--   * `citas_cancelar`: la persona libera su cita (hasta 2 h antes) o el profesional quita el
--     horario; el aviso «Se canceló» lo pone el trigger de eventos al borrar el evento.
--   * Los correos (.ics) los manda la app con la función `calendario-invitar`.

create table if not exists public.citas_espacios (
  id            uuid primary key default gen_random_uuid(),
  proveedor_id  uuid not null references public.profiles(id) on delete cascade,
  servicio      text not null check (length(trim(servicio)) > 0),
  lugar         text,
  inicio        timestamptz not null,
  fin           timestamptz not null,
  estado        text not null default 'libre' check (estado in ('libre', 'apartado')),
  apartado_por  uuid references public.profiles(id) on delete set null,
  apartado_en   timestamptz,
  nota          text,
  evento_id     uuid references public.events(id) on delete set null,
  creado_en     timestamptz not null default now(),
  check (fin > inicio),
  unique (proveedor_id, inicio)
);

create index if not exists citas_espacios_inicio_idx on public.citas_espacios (inicio);
create index if not exists citas_espacios_apartado_idx on public.citas_espacios (apartado_por) where apartado_por is not null;

alter table public.citas_espacios enable row level security;
revoke all on public.citas_espacios from anon, authenticated;

-- El aviso de invitación (trigger de `event_invitations`) usaba `events%ROWTYPE` sin esquema y sin
-- `search_path` propio: tomaba el de quien lo disparaba, y desde una función con `search_path = ''`
-- (como `citas_apartar`) fallaba con «relation "events" does not exist». No cambia lo que hace.
alter function public.notify_event_invitation() set search_path = public;

create or replace function public.puede_publicar_citas()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.is_admin(), false) or public.has_permission('publicar_citas');
$$;

-- ── Ver ──────────────────────────────────────────────────────────────────────────────────────────
-- Los futuros para todos (los apartados salen como «Ocupado»); además las citas propias y, para el
-- profesional, todos sus horarios. Quién apartó y su nota solo los ven el profesional y la persona.
create or replace function public.citas_listar(p_desde timestamptz, p_hasta timestamptz)
returns table (
  id uuid, servicio text, lugar text, inicio timestamptz, fin timestamptz, estado text,
  proveedor_id uuid, proveedor_nombre text, es_mia boolean, soy_proveedor boolean,
  apartado_por_nombre text, nota text, evento_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.servicio, c.lugar, c.inicio, c.fin, c.estado,
         c.proveedor_id, coalesce(pp.full_name, ''),
         c.apartado_por = auth.uid(),
         c.proveedor_id = auth.uid(),
         case when c.proveedor_id = auth.uid() or c.apartado_por = auth.uid()
              then pa.full_name end,
         case when c.proveedor_id = auth.uid() or c.apartado_por = auth.uid()
              then c.nota end,
         case when c.proveedor_id = auth.uid() or c.apartado_por = auth.uid()
              then c.evento_id end
    from public.citas_espacios c
    left join public.profiles pp on pp.id = c.proveedor_id
    left join public.profiles pa on pa.id = c.apartado_por
   where c.inicio >= p_desde and c.inicio < p_hasta
     and (   c.inicio > now()
          or c.apartado_por = auth.uid()
          or c.proveedor_id = auth.uid())
   order by c.inicio;
$$;

-- ── Publicar ─────────────────────────────────────────────────────────────────────────────────────
-- `p_espacios`: [{"inicio": "...", "fin": "..."}, ...]. Los que ya existen a esa hora se saltan.
create or replace function public.citas_publicar(p_servicio text, p_lugar text, p_espacios jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  if not public.puede_publicar_citas() then
    raise exception 'No tienes permiso para publicar horarios de citas.' using errcode = '42501';
  end if;
  if coalesce(trim(p_servicio), '') = '' then
    raise exception 'Escribe el nombre del servicio.';
  end if;
  if jsonb_array_length(coalesce(p_espacios, '[]'::jsonb)) > 500 then
    raise exception 'Son demasiados horarios de una vez (máximo 500).';
  end if;

  insert into public.citas_espacios (proveedor_id, servicio, lugar, inicio, fin)
  select auth.uid(), trim(p_servicio), nullif(trim(coalesce(p_lugar, '')), ''),
         (e->>'inicio')::timestamptz, (e->>'fin')::timestamptz
    from jsonb_array_elements(p_espacios) e
   where (e->>'inicio')::timestamptz > now()
  on conflict (proveedor_id, inicio) do nothing;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ── Apartar ──────────────────────────────────────────────────────────────────────────────────────
create or replace function public.citas_apartar(p_id uuid, p_nota text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  c        public.citas_espacios%rowtype;
  yo       uuid := auth.uid();
  nombre   text;
  ev       uuid;
  cuando   text;
begin
  if yo is null then raise exception 'Inicia sesión.'; end if;

  select * into c from public.citas_espacios where id = p_id for update;
  if not found then raise exception 'Ese horario ya no existe.'; end if;
  if c.estado <> 'libre' then raise exception 'Ese horario se acaba de ocupar. Elige otro.'; end if;
  if c.inicio <= now() then raise exception 'Ese horario ya pasó.'; end if;
  if c.proveedor_id = yo then raise exception 'No puedes apartar un horario tuyo.'; end if;
  if exists (select 1 from public.citas_espacios o
              where o.apartado_por = yo and o.proveedor_id = c.proveedor_id
                and o.servicio = c.servicio and o.inicio > now()) then
    raise exception 'Ya tienes una cita de % pendiente. Cancélala para apartar otra.', c.servicio;
  end if;

  select coalesce(full_name, '') into nombre from public.profiles where id = yo;
  cuando := to_char(c.inicio at time zone 'America/Mexico_City', 'DD/MM/YYYY "a las" HH24:MI');

  insert into public.events (title, description, location, start_time, end_time, creator_id,
                             is_public, priority, recurrence)
  values ('Cita ' || c.servicio || ' · ' || nombre,
          nullif(trim(coalesce(p_nota, '')), ''),
          c.lugar, c.inicio, c.fin, c.proveedor_id, false, 'Normal', 'No repetir')
  returning id into ev;

  -- La invitación ya va aceptada; el trigger de invitaciones le crea su notificación, que se
  -- reescribe como confirmación de la cita.
  insert into public.event_invitations (event_id, user_id, status) values (ev, yo, 'accepted');
  update public.notifications
     set title = 'Cita confirmada',
         message = 'Tu cita de ' || c.servicio || ' quedó confirmada para el ' || cuando || '.'
   where user_id = yo and type = 'event_invitation' and metadata->>'event_id' = ev::text;

  update public.citas_espacios
     set estado = 'apartado', apartado_por = yo, apartado_en = now(),
         nota = nullif(trim(coalesce(p_nota, '')), ''), evento_id = ev
   where id = c.id;

  insert into public.notifications (user_id, title, message, type, metadata)
  values (c.proveedor_id, 'Nueva cita',
          nombre || ' apartó una cita de ' || c.servicio || ' el ' || cuando || '.',
          'cita_apartada',
          jsonb_build_object('event_id', ev, 'cita_id', c.id, 'event_date', c.inicio::text));

  return ev;
end;
$$;

-- ── Cancelar ─────────────────────────────────────────────────────────────────────────────────────
-- La persona que apartó: hasta 2 horas antes; el horario vuelve a quedar libre.
-- El profesional (o un admin): quita el horario, esté libre o apartado.
create or replace function public.citas_cancelar(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c      public.citas_espacios%rowtype;
  yo     uuid := auth.uid();
  nombre text;
begin
  select * into c from public.citas_espacios where id = p_id for update;
  if not found then return; end if;

  if c.apartado_por = yo and c.proveedor_id <> yo then
    if c.inicio - now() < interval '2 hours' then
      raise exception 'Ya no se puede cancelar desde aquí: faltan menos de 2 horas. Avisa directamente.';
    end if;
    select coalesce(full_name, '') into nombre from public.profiles where id = yo;
    if c.evento_id is not null then delete from public.events where id = c.evento_id; end if;
    update public.citas_espacios
       set estado = 'libre', apartado_por = null, apartado_en = null, nota = null, evento_id = null
     where id = c.id;
    insert into public.notifications (user_id, title, message, type, metadata)
    values (c.proveedor_id, 'Se canceló una cita',
            nombre || ' canceló su cita de ' || c.servicio || ' del '
              || to_char(c.inicio at time zone 'America/Mexico_City', 'DD/MM/YYYY "a las" HH24:MI')
              || '. El horario quedó libre.',
            'cita_cancelada', jsonb_build_object('cita_id', c.id, 'event_date', c.inicio::text));
  elsif c.proveedor_id = yo or coalesce(public.is_admin(), false) then
    -- Borrar el evento avisa a la persona («Se canceló: …», trigger de eventos).
    if c.evento_id is not null then delete from public.events where id = c.evento_id; end if;
    delete from public.citas_espacios where id = c.id;
  else
    raise exception 'No puedes cancelar esta cita.' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.puede_publicar_citas() from public, anon;
revoke all on function public.citas_listar(timestamptz, timestamptz) from public, anon;
revoke all on function public.citas_publicar(text, text, jsonb) from public, anon;
revoke all on function public.citas_apartar(uuid, text) from public, anon;
revoke all on function public.citas_cancelar(uuid) from public, anon;
grant execute on function public.puede_publicar_citas() to authenticated;
grant execute on function public.citas_listar(timestamptz, timestamptz) to authenticated;
grant execute on function public.citas_publicar(text, text, jsonb) to authenticated;
grant execute on function public.citas_apartar(uuid, text) to authenticated;
grant execute on function public.citas_cancelar(uuid) to authenticated;
