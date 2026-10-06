-- Ligas con horario, lugar e inscripcion propia (06/10/2026, a pedido del usuario).
--
-- Antes habia un solo torneo y entraban al sorteo TODOS los inscritos en Torneos. Pero no todos
-- pueden jugar a la misma hora: ahora el organizador crea cada liga con su horario y lugar
-- («Liga Constituyentes, viernes 14:00, Constituyentes») y una fecha de cierre de inscripcion.
-- Cada quien se inscribe solo a las ligas que le acomodan (`torneo_inscritos`).
--
-- Al vencer la fecha se sortea sola (`torneo_sortear_vencidas`, con pg_cron cada 5 minutos y
-- tambien al abrir la pagina). El organizador puede cerrarla antes. Si al cierre hay menos de 4
-- inscritos no se sortea: se avisa a los organizadores para que amplien la fecha o la cancelen.
--
-- Las fechas de cada carrera las sigue poniendo el organizador; el horario de la liga es la
-- referencia que ve todo el mundo. `torneo_jugadores` sigue siendo el perfil del piloto (apodo y
-- avatar), uno por persona para todas las ligas y Kart Garage.

-- ── Columnas nuevas ─────────────────────────────────────────────────────────────────────────────

alter table public.torneos
  add column if not exists lugar              text,
  -- 1 = lunes … 7 = domingo (ISO), como `extract(isodow …)`.
  add column if not exists dia_semana         smallint check (dia_semana between 1 and 7),
  add column if not exists hora               time,
  add column if not exists inscripcion_cierra timestamptz,
  -- Cuando vencio la inscripcion sin jugadores suficientes. Mientras tenga valor, el sorteo
  -- automatico la salta; al cambiar la fecha de cierre se limpia.
  add column if not exists sorteo_fallido_at  timestamptz;

alter table public.torneos drop constraint if exists torneos_fase_check;
alter table public.torneos add constraint torneos_fase_check
  check (fase in ('inscripcion', 'grupos', 'finales', 'terminado', 'cancelado'));

create table if not exists public.torneo_inscritos (
  torneo_id  uuid not null references public.torneos (id) on delete cascade,
  user_id    uuid not null references public.torneo_jugadores (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (torneo_id, user_id)
);
create index if not exists torneo_inscritos_user on public.torneo_inscritos (user_id);

alter table public.torneo_inscritos enable row level security;
drop policy if exists torneo_inscritos_select on public.torneo_inscritos;
create policy torneo_inscritos_select on public.torneo_inscritos for select to authenticated using (true);

do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and tablename = 'torneo_inscritos') then
    alter publication supabase_realtime add table public.torneo_inscritos;
  end if;
end $$;

-- El torneo de prueba de la primera version no tiene horario ni lugar y nadie lo jugo.
delete from public.torneos t
 where t.nombre = 'SiSol Mario Kart Cup' and t.fase = 'inscripcion' and t.lugar is null
   and not exists (select 1 from public.torneo_carreras c where c.torneo_id = t.id);

-- ── Ayudantes ───────────────────────────────────────────────────────────────────────────────────

create or replace function public.torneo_horario(p_t public.torneos)
returns text
language sql
immutable
set search_path = ''
as $$
  select concat_ws(' · ',
    nullif(concat_ws(' ',
      (array['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'])[p_t.dia_semana],
      to_char(p_t.hora, 'HH24:MI')), ''),
    p_t.lugar);
$$;

create or replace function public.torneo_organizadores()
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(id), '{}') from profiles
   where coalesce((permissions ->> 'show_torneos_admin')::boolean, false);
$$;

-- El sorteo en si, sin revisar permisos: lo llaman `torneo_generar_liga` (organizador) y el cierre
-- automatico. Solo entran los inscritos a ESA liga.
create or replace function public.torneo_sortear(p_torneo uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cal constant jsonb := '{
    "4": [[0,1,2,3]],
    "5": [[0,1,2,3],[0,1,3,4],[1,2,3,4],[0,2,3,4],[0,1,2,4]],
    "6": [[0,1,3,4],[1,2,3,5],[0,2,4,5]],
    "7": [[0,2,4,5],[1,3,4,6],[0,3,5,6],[0,1,2,6],[1,2,3,5],[2,4,5,6],[0,1,3,4]],
    "8": [[0,4,5,6],[1,2,3,7],[0,1,6,7],[0,2,3,4],[2,3,5,6],[1,4,5,7]]
  }';
  v_t torneos;
  v_jug uuid[];
  n int;
  g int;
  v_miembros uuid[];
  v_nombre text;
  v_sched jsonb;
  v_id uuid;
  v_total int := 0;
begin
  select * into v_t from torneos where id = p_torneo for update;
  if not found then raise exception 'No existe esa liga.'; end if;
  if v_t.fase in ('terminado', 'cancelado') then raise exception 'Esta liga ya terminó.'; end if;

  select array_agg(user_id order by random()) into v_jug from torneo_inscritos where torneo_id = p_torneo;
  n := coalesce(cardinality(v_jug), 0);
  if n < 4 then raise exception 'Se necesitan al menos 4 inscritos para sortear (hay %).', n; end if;

  delete from torneo_carreras where torneo_id = p_torneo;
  delete from torneo_grupos where torneo_id = p_torneo;

  g := ceil(n / 8.0);
  for i in 0..g - 1 loop
    v_nombre := chr(65 + i);
    select array_agg(v_jug[j] order by j) into v_miembros
      from generate_series(1, n) j where (j - 1) % g = i;
    insert into torneo_grupos (torneo_id, user_id, grupo)
    select p_torneo, u, v_nombre from unnest(v_miembros) u;

    v_sched := v_cal -> cardinality(v_miembros)::text;
    for k in 0..jsonb_array_length(v_sched) - 1 loop
      insert into torneo_carreras (torneo_id, tipo, grupo, ronda, cupo, creada_por)
      values (p_torneo, 'grupo', v_nombre, k + 1, 4, auth.uid())
      returning id into v_id;
      insert into torneo_carrera_jugadores (carrera_id, user_id)
      select v_id, v_miembros[(x)::int + 1] from jsonb_array_elements_text(v_sched -> k) x;
      v_total := v_total + 1;
    end loop;
  end loop;

  update torneo_carreras c set numero = r.num
    from (select id, row_number() over (order by ronda, grupo) as num
            from torneo_carreras where torneo_id = p_torneo) r
   where c.id = r.id;

  update torneos set fase = 'grupos', campeon = null, sorteo_fallido_at = null where id = p_torneo;

  for i in 0..g - 1 loop
    v_nombre := chr(65 + i);
    select array_agg(user_id) into v_miembros from torneo_grupos
     where torneo_id = p_torneo and grupo = v_nombre;
    perform torneo_avisar(v_miembros, '🏎️ ¡Ya se sorteó ' || v_t.nombre || '!',
      'Quedaste en el Grupo ' || v_nombre || coalesce(' (' || nullif(torneo_horario(v_t), '') || ')', '')
        || '. Revisa tus carreras en Torneos.',
      jsonb_build_object('torneo_id', p_torneo));
  end loop;

  return jsonb_build_object('grupos', g, 'carreras', v_total, 'jugadores', n);
end;
$$;

-- ── Funciones del organizador ───────────────────────────────────────────────────────────────────

drop function if exists public.torneo_crear(text);

create or replace function public.torneo_crear(
  p_nombre text, p_lugar text, p_dia_semana int, p_hora time, p_cierre timestamptz)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_t torneos;
  v_todos uuid[];
begin
  if not torneo_es_organizador() then raise exception 'Solo el organizador puede crear ligas.'; end if;
  if btrim(coalesce(p_nombre, '')) = '' then raise exception 'Ponle nombre a la liga.'; end if;
  if p_cierre is null or p_cierre <= now() then
    raise exception 'La fecha de cierre de inscripción tiene que ser en el futuro.';
  end if;

  insert into torneos (nombre, lugar, dia_semana, hora, inscripcion_cierra)
  values (btrim(p_nombre), nullif(btrim(p_lugar), ''), p_dia_semana, p_hora, p_cierre)
  returning * into v_t;
  v_id := v_t.id;

  -- Aviso a todos los usuarios activos, pedido del usuario: que cada quien vea si le acomoda.
  select array_agg(p.id) into v_todos
    from profiles p join auth.users u on u.id = p.id
   where p.status_sys = 'ACTIVO' and not coalesce(p.is_blocked, false);
  perform torneo_avisar(v_todos, '🏁 Nueva liga: ' || v_t.nombre,
    coalesce(nullif(torneo_horario(v_t), '') || '. ', '')
      || 'Inscríbete en Torneos antes del '
      || to_char(p_cierre at time zone 'America/Mexico_City', 'DD/MM "a las" HH24:MI') || '.',
    jsonb_build_object('torneo_id', v_id), auth.uid());
  return v_id;
end;
$$;

create or replace function public.torneo_editar(
  p_torneo uuid, p_nombre text, p_lugar text, p_dia_semana int, p_hora time, p_cierre timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_t torneos;
begin
  if not torneo_es_organizador() then raise exception 'Solo el organizador puede editar ligas.'; end if;
  select * into v_t from torneos where id = p_torneo for update;
  if not found then raise exception 'No existe esa liga.'; end if;
  if btrim(coalesce(p_nombre, '')) = '' then raise exception 'Ponle nombre a la liga.'; end if;
  if v_t.fase = 'inscripcion' and (p_cierre is null or p_cierre <= now()) then
    raise exception 'La fecha de cierre de inscripción tiene que ser en el futuro.';
  end if;
  update torneos
     set nombre = btrim(p_nombre),
         lugar = nullif(btrim(p_lugar), ''),
         dia_semana = p_dia_semana,
         hora = p_hora,
         inscripcion_cierra = case when fase = 'inscripcion' then p_cierre else inscripcion_cierra end,
         sorteo_fallido_at = case when fase = 'inscripcion' then null else sorteo_fallido_at end
   where id = p_torneo;
end;
$$;

-- «Cerrar inscripcion y sortear» y «Volver a sortear».
create or replace function public.torneo_generar_liga(p_torneo uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_res jsonb;
begin
  if not torneo_es_organizador() then raise exception 'Solo el organizador puede sortear la liga.'; end if;
  v_res := torneo_sortear(p_torneo);
  -- Si se cerro antes de tiempo, la fecha de cierre pasa a ser ahora.
  update torneos set inscripcion_cierra = least(coalesce(inscripcion_cierra, now()), now())
   where id = p_torneo;
  return v_res;
end;
$$;

create or replace function public.torneo_cancelar(p_torneo uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_t torneos;
  v_jug uuid[];
begin
  if not torneo_es_organizador() then raise exception 'Solo el organizador puede cancelar ligas.'; end if;
  select * into v_t from torneos where id = p_torneo for update;
  if not found then raise exception 'No existe esa liga.'; end if;
  if v_t.fase in ('terminado', 'cancelado') then raise exception 'Esta liga ya terminó.'; end if;
  update torneos set fase = 'cancelado' where id = p_torneo;
  update torneo_carreras set estado = 'cancelada'
   where torneo_id = p_torneo and estado in ('programada', 'por_confirmar');
  select array_agg(user_id) into v_jug from torneo_inscritos where torneo_id = p_torneo;
  perform torneo_avisar(v_jug, '❌ Se canceló ' || v_t.nombre,
    'El organizador canceló la liga.', jsonb_build_object('torneo_id', p_torneo), auth.uid());
end;
$$;

-- ── Inscripcion de cada jugador ─────────────────────────────────────────────────────────────────

create or replace function public.torneo_inscribirme(p_torneo uuid, p_inscribir boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_t torneos;
begin
  if not exists (select 1 from torneo_jugadores where user_id = auth.uid()) then
    raise exception 'Primero crea tu perfil de piloto.';
  end if;
  select * into v_t from torneos where id = p_torneo for share;
  if not found then raise exception 'No existe esa liga.'; end if;
  if v_t.fase <> 'inscripcion' or (v_t.inscripcion_cierra is not null and v_t.inscripcion_cierra <= now()) then
    raise exception 'La inscripción de esta liga ya cerró.';
  end if;
  if p_inscribir then
    insert into torneo_inscritos (torneo_id, user_id) values (p_torneo, auth.uid())
    on conflict do nothing;
  else
    delete from torneo_inscritos where torneo_id = p_torneo and user_id = auth.uid();
  end if;
end;
$$;

-- ── Cierre automatico ───────────────────────────────────────────────────────────────────────────
--
-- Sortea las ligas con la inscripcion vencida. Lo corre pg_cron cada 5 minutos y la pagina al
-- abrirse (por si el cron se atrasa): es idempotente y no depende de quien la llame.
create or replace function public.torneo_sortear_vencidas()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_t torneos;
  v_n int;
  v_hechas int := 0;
begin
  for v_t in
    select * from torneos
     where fase = 'inscripcion' and inscripcion_cierra <= now() and sorteo_fallido_at is null
     for update skip locked
  loop
    select count(*) into v_n from torneo_inscritos where torneo_id = v_t.id;
    if v_n >= 4 then
      perform torneo_sortear(v_t.id);
      v_hechas := v_hechas + 1;
    else
      update torneos set sorteo_fallido_at = now() where id = v_t.id;
      perform torneo_avisar(torneo_organizadores(), '⚠️ ' || v_t.nombre || ' no se sorteó',
        'Cerró la inscripción con ' || v_n || ' inscrito' || case when v_n = 1 then '' else 's' end
          || ' y se necesitan 4. Amplía la fecha de cierre o cancela la liga.',
        jsonb_build_object('torneo_id', v_t.id));
    end if;
  end loop;
  return v_hechas;
end;
$$;

-- ── Permisos ────────────────────────────────────────────────────────────────────────────────────

revoke all on function public.torneo_organizadores() from public, anon, authenticated;
revoke all on function public.torneo_sortear(uuid) from public, anon, authenticated;
revoke all on function public.torneo_crear(text, text, int, time, timestamptz) from public, anon;
revoke all on function public.torneo_editar(uuid, text, text, int, time, timestamptz) from public, anon;
revoke all on function public.torneo_cancelar(uuid) from public, anon;
revoke all on function public.torneo_inscribirme(uuid, boolean) from public, anon;
revoke all on function public.torneo_sortear_vencidas() from public, anon;

grant execute on function public.torneo_crear(text, text, int, time, timestamptz) to authenticated;
grant execute on function public.torneo_editar(uuid, text, text, int, time, timestamptz) to authenticated;
grant execute on function public.torneo_cancelar(uuid) to authenticated;
grant execute on function public.torneo_inscribirme(uuid, boolean) to authenticated;
grant execute on function public.torneo_sortear_vencidas() to authenticated;

-- ── pg_cron ─────────────────────────────────────────────────────────────────────────────────────

create extension if not exists pg_cron;

select cron.unschedule(jobid) from cron.job where jobname = 'torneos-sortear-vencidas';
select cron.schedule('torneos-sortear-vencidas', '*/5 * * * *', 'select public.torneo_sortear_vencidas()');
