-- Correspondencia: el registro de los correos que se mandan desde el sistema.
--
-- ─── Quien escribe aqui ─────────────────────────────────────────────────────
--
-- SOLO la funcion `correspondencia`, con la llave de servicio. Ni la aplicacion ni ningun usuario
-- pueden insertar, cambiar ni borrar: el registro vale porque nadie puede arreglarlo a mano.
--
-- Y es lo que sostiene el limite por hora. La funcion cuenta aqui los intentos de cada quien; si la
-- aplicacion pudiera escribir en esta tabla, tambien podria borrar sus filas y quedarse sin tope.
--
-- ─── Quien lee ──────────────────────────────────────────────────────────────
--
-- Cada quien lo suyo, y los administradores todo. `is_admin()` lee el rol del TOKEN, no de
-- `profiles`, asi que aqui no sirve cambiarse el rol en el propio perfil.

create table if not exists public.correspondencia (
  id               uuid primary key default gen_random_uuid(),
  -- `set null` y no `cascade`: si se da de baja a alguien, su historial de envios se queda. Es el
  -- registro de lo que salio de la cuenta de la empresa, y no deberia desaparecer con una persona.
  remitente_id     uuid references public.profiles(id) on delete set null,
  -- El nombre se guarda en el momento: si la persona cambia de nombre o se va, el registro sigue
  -- diciendo quien lo mando.
  remitente_nombre text not null,
  asunto           text not null check (length(trim(asunto)) between 1 and 200),
  cuerpo           text not null check (length(cuerpo) between 1 and 20000),
  destinatarios    text[] not null check (cardinality(destinatarios) between 1 and 50),
  estado           text not null default 'PENDIENTE'
                     check (estado in ('PENDIENTE', 'ENVIADO', 'FALLIDO')),
  error            text,
  creado_en        timestamptz not null default now(),
  enviado_en       timestamptz
);

comment on table public.correspondencia is
  'Correos enviados desde el modulo de Correspondencia. Solo escribe la funcion `correspondencia`; '
  'cada usuario lee lo suyo y los administradores todo.';

-- Para el limite por hora y para el historial de cada quien, que son las dos consultas que hay.
create index if not exists correspondencia_remitente_fecha
  on public.correspondencia (remitente_id, creado_en desc);

alter table public.correspondencia enable row level security;

drop policy if exists correspondencia_lee_lo_suyo on public.correspondencia;
create policy correspondencia_lee_lo_suyo on public.correspondencia
  for select to authenticated
  using (remitente_id = auth.uid() or public.is_admin());

-- Ninguna politica de INSERT, UPDATE ni DELETE: sin politica, RLS lo niega. Y ademas se quitan los
-- permisos, para que no dependa de que nadie agregue una politica sin pensar.
revoke insert, update, delete on public.correspondencia from anon, authenticated;
revoke all on public.correspondencia from anon;
