-- Correspondencia: listas de distribucion y mensajes con formato.
--
-- Pedido del usuario el 23/09/2026: poder crear grupos o listas de distribucion, y mandar los
-- comunicados con formato (editor visual). Tres cambios:

-- ─── 1. El registro guarda el HTML y las listas usadas ─────────────────────
--
-- `cuerpo` sigue siendo el TEXTO, sin formato: es lo que se lee rapido en el historial y lo que
-- sirve para buscar. `cuerpo_html` es exactamente lo que salio. `listas` guarda el NOMBRE que tenian
-- las listas en el momento de enviar: si luego se renombran o se borran, el registro sigue diciendo a
-- que se mando.
alter table public.correspondencia
  add column if not exists cuerpo_html text
    check (cuerpo_html is null or length(cuerpo_html) <= 200000);

alter table public.correspondencia
  add column if not exists listas text[] not null default '{}';

-- El tope pasa de 50 por mensaje a 500 por COMUNICADO. Con 74 empleados activos, una lista de
-- «todos» ya no cabia en 50. La funcion ahora envia en tandas de 50 al servidor de correo.
alter table public.correspondencia drop constraint if exists correspondencia_destinatarios_check;
alter table public.correspondencia add constraint correspondencia_destinatarios_check
  check (cardinality(destinatarios) between 1 and 500);

-- PARCIAL: salio a una parte y no al resto. Con envio por tandas puede pasar -la segunda tanda falla
-- y la primera ya salio- y ni ENVIADO ni FALLIDO lo dirian con verdad.
alter table public.correspondencia drop constraint if exists correspondencia_estado_check;
alter table public.correspondencia add constraint correspondencia_estado_check
  check (estado in ('PENDIENTE', 'ENVIADO', 'PARCIAL', 'FALLIDO'));

-- ─── 2. Las listas ─────────────────────────────────────────────────────────
--
-- Compartidas entre quienes tienen el permiso, igual que el historial: todo sale como «Comunicación
-- SI SOL», y una lista que arma una persona la usan las otras dos.
create table if not exists public.listas_distribucion (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null check (length(btrim(nombre)) between 1 and 80),
  descripcion     text check (descripcion is null or length(descripcion) <= 300),
  creada_por      uuid references public.profiles(id) on delete set null default auth.uid(),
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now()
);

comment on table public.listas_distribucion is
  'Listas de distribucion del modulo de Correspondencia. Compartidas entre quienes tienen '
  'show_correspondencia.';

-- Dos listas con el mismo nombre serian indistinguibles al elegirlas en la pantalla.
create unique index if not exists listas_distribucion_nombre_unico
  on public.listas_distribucion (lower(btrim(nombre)));

-- ─── 3. Quien esta en cada lista ───────────────────────────────────────────
--
-- Un miembro es un COMPAÑERO -por su perfil- o un CORREO tecleado, nunca los dos. Los compañeros se
-- guardan por persona y no por correo: el correo se busca al enviar, asi que si alguien cambia de
-- correo la lista no se queda vieja, y quien se da de baja deja de recibir sin que nadie tenga que
-- acordarse de sacarlo.
create table if not exists public.lista_miembros (
  id          uuid primary key default gen_random_uuid(),
  lista_id    uuid not null references public.listas_distribucion(id) on delete cascade,
  profile_id  uuid references public.profiles(id) on delete cascade,
  correo      text check (
                correo is null
                or (correo = lower(btrim(correo)) and correo ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')
              ),
  creado_en   timestamptz not null default now(),
  constraint lista_miembros_uno_u_otro check ((profile_id is null) <> (correo is null))
);

create unique index if not exists lista_miembros_persona_unica
  on public.lista_miembros (lista_id, profile_id) where profile_id is not null;
create unique index if not exists lista_miembros_correo_unico
  on public.lista_miembros (lista_id, correo) where correo is not null;
create index if not exists lista_miembros_por_lista on public.lista_miembros (lista_id);

-- Que la lista diga cuando se toco por ultima vez, tambien si lo que cambio fue su gente.
create or replace function public.lista_distribucion_tocada()
returns trigger language plpgsql as $$
begin
  if tg_table_name = 'listas_distribucion' then
    new.actualizado_en := now();
    return new;
  end if;
  update public.listas_distribucion set actualizado_en = now()
   where id = coalesce(new.lista_id, old.lista_id);
  return coalesce(new, old);
end $$;

drop trigger if exists tr_lista_tocada on public.listas_distribucion;
create trigger tr_lista_tocada before update on public.listas_distribucion
  for each row execute function public.lista_distribucion_tocada();

drop trigger if exists tr_miembros_tocan_lista on public.lista_miembros;
create trigger tr_miembros_tocan_lista after insert or update or delete on public.lista_miembros
  for each row execute function public.lista_distribucion_tocada();

-- ─── Quien puede ───────────────────────────────────────────────────────────
--
-- Quienes tienen el permiso: ver, crear, editar y borrar. Nadie mas, tampoco un administrador sin el
-- permiso, por el mismo pedido que cerro la pagina.
--
-- OJO: `has_permission` lee de `profiles.permissions`, que hoy cada usuario puede escribirse. Es la
-- misma debilidad que ya tiene el resto del modulo y se cierra en la tarea aparte del 23/09/2026.
alter table public.listas_distribucion enable row level security;
alter table public.lista_miembros enable row level security;

drop policy if exists listas_con_permiso on public.listas_distribucion;
create policy listas_con_permiso on public.listas_distribucion
  for all to authenticated
  using (public.has_permission('show_correspondencia'))
  with check (public.has_permission('show_correspondencia'));

drop policy if exists miembros_con_permiso on public.lista_miembros;
create policy miembros_con_permiso on public.lista_miembros
  for all to authenticated
  using (public.has_permission('show_correspondencia'))
  with check (public.has_permission('show_correspondencia'));

revoke all on public.listas_distribucion from anon;
revoke all on public.lista_miembros from anon;
