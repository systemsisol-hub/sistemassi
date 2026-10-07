-- Invitaciones del calendario por correo (07/10/2026, a pedido del usuario).
--
-- Al crear o cambiar un evento se puede mandar una invitación de calendario (.ics) a los invitados
-- del sistema y a correos externos, para que la agreguen a su Outlook, Gmail o iPhone. La manda la
-- Edge Function `calendario-invitar` con su propia cuenta de correo (secretos CALENDARIO_SMTP_*,
-- hoy la de soporte), no la de Correspondencia.
--
--   * `events`: el identificador de la invitación (`ical_uid`), su número de versión (`ical_seq`, los
--     calendarios solo aceptan un cambio si sube) y, para los eventos que se repiten, la serie a la
--     que pertenece cada uno y su fecha original (`serie_id`, `serie_inicio`).
--   * `event_external_invitees`: correos de fuera del sistema invitados a un evento.
--   * `calendario_envios`: a quién se le mandó qué. Sirve para mandar la cancelación a quien se
--     quita de un evento y para el límite por hora. Solo la escribe la función.

alter table public.events
  add column if not exists ical_uid      text,
  add column if not exists ical_seq      integer not null default 0,
  add column if not exists serie_id      uuid,
  add column if not exists serie_inicio  timestamptz;

create index if not exists events_serie_idx on public.events (serie_id) where serie_id is not null;

create table if not exists public.event_external_invitees (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events(id) on delete cascade,
  email       text not null check (email = lower(trim(email)) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  nombre      text,
  created_at  timestamptz not null default now(),
  unique (event_id, email)
);

alter table public.event_external_invitees enable row level security;

drop policy if exists externos_creador on public.event_external_invitees;
create policy externos_creador on public.event_external_invitees for all to authenticated
  using (public.is_event_creator(event_id))
  with check (public.is_event_creator(event_id));

drop policy if exists externos_invitados_ven on public.event_external_invitees;
create policy externos_invitados_ven on public.event_external_invitees for select to authenticated
  using (public.is_event_invitee(event_id));

revoke all on public.event_external_invitees from anon;
grant select, insert, update, delete on public.event_external_invitees to authenticated;

create table if not exists public.calendario_envios (
  id             uuid primary key default gen_random_uuid(),
  ical_uid       text not null,
  recurrence_id  timestamptz,
  email          text not null,
  metodo         text not null check (metodo in ('REQUEST', 'CANCEL')),
  enviado_por    uuid,
  enviado_en     timestamptz not null default now(),
  error          text
);

create index if not exists calendario_envios_uid_idx on public.calendario_envios (ical_uid, email);
create index if not exists calendario_envios_quien_idx on public.calendario_envios (enviado_por, enviado_en);

alter table public.calendario_envios enable row level security;
revoke all on public.calendario_envios from anon, authenticated;
