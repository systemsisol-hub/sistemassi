-- Citas dentro del Calendario (08/10/2026): reemplaza la página «Citas» de 20261008100000.
--
-- Pedido del usuario: en el formulario de evento, además de Público y Personal, el tipo «Cita»; se
-- crean una por una (no una configuración de varias). Lleva título, ubicación, descripción, inicio y
-- fin, un estado en lugar de prioridad (Disponible / Apartada) e invitados vacíos hasta que alguien
-- la aparta. Se publica en el calendario Grupal: todos ven las disponibles y, en gris, las apartadas.
--
-- Reglas que siguen (decididas el 08/10/2026): una cita a la vez por persona con el mismo
-- organizador; se cancela hasta 2 horas antes; pueden apartar todos; nota opcional al apartar.
--
--   * `events`: `es_cita` y `cita_estado` (disponible / apartada). Una cita es pública
--     (`is_public = true`) para que salga en Grupal: todos ven si está libre o apartada.
--   * `citas_reservas`: QUIÉN la apartó y su nota, aparte, porque el evento lo lee cualquiera. Solo
--     la ven el organizador y la propia persona (es una cita de salud).
--   * `cita_apartar` / `cita_cancelar`: lo único que cambia el estado. La persona queda como
--     invitada (aceptada), así la cita aparece en su calendario y en «Invitados» del organizador.
--   * Si el organizador mueve o borra la cita, avisan los triggers de eventos que ya existen.
--   * Los correos los manda la app con `calendario-invitar`.

-- ── Lo de la versión anterior (nadie llegó a publicar horarios) ─────────────────────────────────
drop function if exists public.citas_listar(timestamptz, timestamptz);
drop function if exists public.citas_publicar(text, text, jsonb);
drop function if exists public.citas_apartar(uuid, text);
drop function if exists public.citas_cancelar(uuid);
drop function if exists public.puede_publicar_citas();
drop table if exists public.citas_espacios;

-- ── Columnas ─────────────────────────────────────────────────────────────────────────────────────
alter table public.events
  add column if not exists es_cita      boolean not null default false,
  add column if not exists cita_estado  text check (cita_estado in ('disponible', 'apartada'));

alter table public.events drop constraint if exists events_cita_estado_ck;
alter table public.events add constraint events_cita_estado_ck
  check (not es_cita or cita_estado is not null);

create table if not exists public.citas_reservas (
  event_id      uuid primary key references public.events(id) on delete cascade,
  apartado_por  uuid not null references public.profiles(id) on delete cascade,
  nota          text,
  apartado_en   timestamptz not null default now()
);

create index if not exists citas_reservas_persona_idx on public.citas_reservas (apartado_por);

alter table public.citas_reservas enable row level security;
drop policy if exists citas_reservas_ver on public.citas_reservas;
create policy citas_reservas_ver on public.citas_reservas for select to authenticated
  using (apartado_por = auth.uid() or public.is_event_creator(event_id));
revoke all on public.citas_reservas from anon, authenticated;
grant select on public.citas_reservas to authenticated;

-- ── Apartar ──────────────────────────────────────────────────────────────────────────────────────
create or replace function public.cita_apartar(p_event uuid, p_nota text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  e       public.events%rowtype;
  yo      uuid := auth.uid();
  nombre  text;
  cuando  text;
begin
  if yo is null then raise exception 'Inicia sesión.'; end if;
  select * into e from public.events where id = p_event for update;
  if not found or not e.es_cita then raise exception 'Esa cita ya no existe.'; end if;
  if e.cita_estado <> 'disponible' then raise exception 'Esa cita se acaba de apartar. Elige otra.'; end if;
  if e.start_time <= now() then raise exception 'Esa cita ya pasó.'; end if;
  if e.creator_id = yo then raise exception 'No puedes apartar una cita tuya.'; end if;
  if exists (select 1 from public.citas_reservas r join public.events o on o.id = r.event_id
              where r.apartado_por = yo and o.creator_id = e.creator_id
                and o.start_time > now()) then
    raise exception 'Ya tienes una cita pendiente con esta persona. Cancélala para apartar otra.';
  end if;

  select coalesce(full_name, '') into nombre from public.profiles where id = yo;
  cuando := to_char(e.start_time at time zone 'America/Mexico_City', 'DD/MM/YYYY "a las" HH24:MI');

  update public.events set cita_estado = 'apartada' where id = e.id;
  insert into public.citas_reservas (event_id, apartado_por, nota)
  values (e.id, yo, nullif(trim(coalesce(p_nota, '')), ''));

  insert into public.event_invitations (event_id, user_id, status)
  values (e.id, yo, 'accepted')
  on conflict do nothing;
  update public.notifications
     set title = 'Cita confirmada',
         message = 'Tu cita «' || coalesce(e.title, 'Cita') || '» quedó confirmada para el ' || cuando || '.'
   where user_id = yo and type = 'event_invitation' and metadata->>'event_id' = e.id::text
     and created_at = now();

  insert into public.notifications (user_id, title, message, type, metadata)
  values (e.creator_id, 'Nueva cita',
          nombre || ' apartó la cita «' || coalesce(e.title, 'Cita') || '» del ' || cuando || '.',
          'cita_apartada',
          jsonb_build_object('event_id', e.id, 'event_date', e.start_time::text));
end;
$$;

-- ── Cancelar (quien la apartó) ───────────────────────────────────────────────────────────────────
-- El organizador no usa esto: si borra la cita, avisa el trigger de eventos.
create or replace function public.cita_cancelar(p_event uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  e      public.events%rowtype;
  yo     uuid := auth.uid();
  nombre text;
begin
  select * into e from public.events where id = p_event for update;
  if not found or not e.es_cita then return; end if;
  if not exists (select 1 from public.citas_reservas
                  where event_id = e.id and apartado_por = yo) then
    raise exception 'No apartaste esta cita.' using errcode = '42501';
  end if;
  if e.start_time - now() < interval '2 hours' then
    raise exception 'Ya no se puede cancelar desde aquí: faltan menos de 2 horas. Avisa directamente.';
  end if;

  select coalesce(full_name, '') into nombre from public.profiles where id = yo;
  delete from public.event_invitations where event_id = e.id and user_id = yo;
  delete from public.citas_reservas where event_id = e.id;
  update public.events set cita_estado = 'disponible' where id = e.id;
  update public.notifications
     set metadata = coalesce(metadata, '{}'::jsonb) || '{"cancelado": true}'::jsonb
   where user_id = yo and type = 'event_invitation' and metadata->>'event_id' = e.id::text;

  insert into public.notifications (user_id, title, message, type, metadata)
  values (e.creator_id, 'Se canceló una cita',
          nombre || ' canceló la cita «' || coalesce(e.title, 'Cita') || '» del '
            || to_char(e.start_time at time zone 'America/Mexico_City', 'DD/MM/YYYY "a las" HH24:MI')
            || '. Quedó disponible otra vez.',
          'cita_cancelada',
          jsonb_build_object('event_id', e.id, 'event_date', e.start_time::text));
end;
$$;

revoke all on function public.cita_apartar(uuid, text) from public, anon;
revoke all on function public.cita_cancelar(uuid) from public, anon;
grant execute on function public.cita_apartar(uuid, text) to authenticated;
grant execute on function public.cita_cancelar(uuid) to authenticated;
