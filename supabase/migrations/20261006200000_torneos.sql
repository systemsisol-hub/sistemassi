-- Torneos: la SiSol Mario Kart Cup (06/10/2026, a pedido del usuario).
--
-- Viene de un HTML suelto (sisol_mario_kart_cup_v1_7.html) que guardaba todo en el `localStorage`
-- de cada navegador: cada quien veia su propia liga y los puntos no llegaban a nadie mas. Ademas
-- entraba uno con el correo de otro, sin contraseña, y cualquiera podia «Regenerar Liga».
--
-- Aqui:
--   * Se inscribe cualquier usuario con sesion (`torneo_jugadores`), con su apodo y un avatar.
--   * Liga: grupos de 4 a 8 al azar y carreras de 4. Los calendarios son fijos por tamaño de grupo
--     (`torneo_generar_liga`): todos corren las mismas veces y cada quien enfrenta a todo su grupo.
--     En el HTML el reparto era al azar y uno podia correr mas carreras que otro del mismo grupo.
--   * Al cerrarse la ultima carrera de grupos pasan los 2 mejores de cada grupo a finales. Si son mas
--     de 4, se corren rondas de hasta 4 y pasan los 2 mejores de cada carrera, hasta la Gran Final.
--   * Kart Garage: carreras libres (`torneo_id` NULL), abiertas o por invitacion. No cuentan para la
--     Liga; tienen su propio ranking.
--   * Un resultado lo captura alguien que corrio y lo confirma OTRO que corrio. El organizador
--     (permiso `show_torneos_admin`) captura directo y corrige.
--   * Los puntos no se suman a un contador: se calculan de los resultados (`torneo_tabla`,
--     `garage_ranking`). Asi un resultado corregido corrige el ranking.
--
-- Todo se escribe por funciones `security definer`; las tablas solo tienen politica de lectura.

-- ── Tablas ──────────────────────────────────────────────────────────────────────────────────────

create table if not exists public.torneo_jugadores (
  user_id    uuid primary key default auth.uid() references public.profiles (id) on delete cascade,
  apodo      text not null check (char_length(btrim(apodo)) between 2 and 24),
  avatar     text not null default '🏎️' check (char_length(avatar) between 1 and 8),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists torneo_jugadores_apodo_unico
  on public.torneo_jugadores (lower(btrim(apodo)));

create table if not exists public.torneos (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null check (btrim(nombre) <> ''),
  fase       text not null default 'inscripcion'
             check (fase in ('inscripcion', 'grupos', 'finales', 'terminado')),
  -- Puntos por posicion en Liga (1.º, 2.º, 3.º, 4.º).
  puntos     int[] not null default '{10,7,5,3}',
  campeon    uuid references public.torneo_jugadores (user_id) on delete set null,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null
);

create table if not exists public.torneo_grupos (
  torneo_id uuid not null references public.torneos (id) on delete cascade,
  user_id   uuid not null references public.torneo_jugadores (user_id) on delete cascade,
  grupo     text not null,
  primary key (torneo_id, user_id)
);

create table if not exists public.torneo_carreras (
  id            uuid primary key default gen_random_uuid(),
  -- NULL = Kart Garage.
  torneo_id     uuid references public.torneos (id) on delete cascade,
  tipo          text not null check (tipo in ('grupo', 'final', 'libre')),
  -- En grupos, la letra ('A', 'B'…). En finales, '<ronda>-<carrera>' ('1-1', '1-2', '2-1').
  grupo         text,
  -- Jornada en grupos; ronda en finales.
  ronda         int not null default 1,
  -- Carrera 1, 2, 3… dentro del torneo, para nombrarlas.
  numero        int,
  fecha_hora    timestamptz,
  abierta       boolean not null default false,
  cupo          int not null default 4 check (cupo between 2 and 8),
  estado        text not null default 'programada'
                check (estado in ('programada', 'por_confirmar', 'completada', 'cancelada')),
  creada_por    uuid default auth.uid() references auth.users (id) on delete set null,
  capturada_por uuid references auth.users (id) on delete set null,
  capturada_at  timestamptz,
  confirmada_por uuid references auth.users (id) on delete set null,
  confirmada_at timestamptz,
  created_at    timestamptz not null default now(),
  check ((tipo = 'libre') = (torneo_id is null))
);
create index if not exists torneo_carreras_torneo on public.torneo_carreras (torneo_id, tipo, ronda);
create index if not exists torneo_carreras_libres on public.torneo_carreras (estado) where torneo_id is null;

create table if not exists public.torneo_carrera_jugadores (
  carrera_id uuid not null references public.torneo_carreras (id) on delete cascade,
  user_id    uuid not null references public.torneo_jugadores (user_id) on delete cascade,
  posicion   int check (posicion between 1 and 8),
  puntos     int,
  primary key (carrera_id, user_id),
  -- Diferida: al recapturar se reacomodan todas las posiciones en un mismo UPDATE.
  constraint torneo_carrera_posicion_unica unique (carrera_id, posicion) deferrable initially deferred
);
create index if not exists torneo_carrera_jugadores_user on public.torneo_carrera_jugadores (user_id);

alter table public.torneo_jugadores         enable row level security;
alter table public.torneos                  enable row level security;
alter table public.torneo_grupos            enable row level security;
alter table public.torneo_carreras          enable row level security;
alter table public.torneo_carrera_jugadores enable row level security;

drop policy if exists torneo_jugadores_select on public.torneo_jugadores;
drop policy if exists torneos_select on public.torneos;
drop policy if exists torneo_grupos_select on public.torneo_grupos;
drop policy if exists torneo_carreras_select on public.torneo_carreras;
drop policy if exists torneo_carrera_jugadores_select on public.torneo_carrera_jugadores;
create policy torneo_jugadores_select on public.torneo_jugadores for select to authenticated using (true);
create policy torneos_select on public.torneos for select to authenticated using (true);
create policy torneo_grupos_select on public.torneo_grupos for select to authenticated using (true);
create policy torneo_carreras_select on public.torneo_carreras for select to authenticated using (true);
create policy torneo_carrera_jugadores_select on public.torneo_carrera_jugadores
  for select to authenticated using (true);

-- La pagina se refresca sola cuando alguien captura, confirma o se une a una carrera.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and tablename = 'torneo_carreras') then
    alter publication supabase_realtime add table public.torneo_carreras;
  end if;
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and tablename = 'torneo_carrera_jugadores') then
    alter publication supabase_realtime add table public.torneo_carrera_jugadores;
  end if;
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and tablename = 'torneos') then
    alter publication supabase_realtime add table public.torneos;
  end if;
end $$;

-- ── Tablas de posiciones ────────────────────────────────────────────────────────────────────────
--
-- Una fila por jugador y por grupo (en grupos) o por carrera (en finales: cada carrera de finales
-- es su propio «grupo», '1-1', '1-2'…). El orden del ranking es el mismo en la app y en
-- `torneo_avanzar`: puntos, victorias, mejor posicion promedio.

create or replace view public.torneo_tabla
with (security_invoker = true) as
select c.torneo_id,
       c.tipo,
       c.grupo,
       max(c.ronda)                                                          as ronda,
       cj.user_id,
       coalesce(sum(cj.puntos) filter (where c.estado = 'completada'), 0)::int as puntos,
       count(*) filter (where c.estado = 'completada')::int                  as carreras,
       count(*) filter (where c.estado <> 'cancelada')::int                  as carreras_total,
       count(*) filter (where c.estado = 'completada' and cj.posicion = 1)::int as victorias,
       avg(cj.posicion) filter (where c.estado = 'completada')               as posicion_media
  from public.torneo_carreras c
  join public.torneo_carrera_jugadores cj on cj.carrera_id = c.id
 where c.tipo in ('grupo', 'final')
 group by c.torneo_id, c.tipo, c.grupo, cj.user_id;

create or replace view public.garage_ranking
with (security_invoker = true) as
select cj.user_id,
       coalesce(sum(cj.puntos), 0)::int                     as puntos,
       count(*)::int                                        as carreras,
       count(*) filter (where cj.posicion = 1)::int         as victorias
  from public.torneo_carreras c
  join public.torneo_carrera_jugadores cj on cj.carrera_id = c.id
 where c.tipo = 'libre' and c.estado = 'completada'
 group by cj.user_id;

grant select on public.torneo_tabla, public.garage_ranking to authenticated;

-- ── Ayudantes (no los llama el cliente) ─────────────────────────────────────────────────────────

create or replace function public.torneo_es_organizador()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.has_permission('show_torneos_admin'), false);
$$;

create or replace function public.torneo_avisar(
  p_usuarios uuid[], p_titulo text, p_mensaje text, p_meta jsonb default '{}'::jsonb,
  p_excluir uuid default null)
returns void
language sql
security definer
set search_path = public
as $$
  insert into notifications (title, message, type, is_read, created_at, user_id, metadata)
  select p_titulo, p_mensaje, 'torneo', false, now(), u, coalesce(p_meta, '{}'::jsonb)
    from (select distinct unnest(p_usuarios) as u) x
   where u is not null and u is distinct from p_excluir;
$$;

create or replace function public.torneo_nombre_carrera(p_carrera public.torneo_carreras)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_carrera.tipo = 'libre' then 'Kart Garage'
    when p_carrera.tipo = 'grupo' then 'Carrera ' || p_carrera.numero || ' · Grupo ' || p_carrera.grupo
    else 'Carrera ' || p_carrera.numero || ' · Finales'
  end;
$$;

-- Crea una ronda de finales con los jugadores en orden de siembra (el mejor primero).
-- Carreras de hasta 4, repartidas en serpiente para que los mejores no caigan juntos.
create or replace function public.torneo_crear_ronda(p_torneo uuid, p_ronda int, p_jugadores uuid[])
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  n int := cardinality(p_jugadores);
  k int := ceil(n / 4.0);
  v_base int;
  v_ids uuid[] := '{}';
  v_id uuid;
  i int;
  fila int;
  col int;
  idx int;
begin
  select coalesce(max(numero), 0) into v_base from torneo_carreras where torneo_id = p_torneo;
  for j in 1..k loop
    insert into torneo_carreras (torneo_id, tipo, grupo, ronda, numero, cupo, creada_por)
    values (p_torneo, 'final', p_ronda || '-' || j, p_ronda, v_base + j, 4, auth.uid())
    returning id into v_id;
    v_ids := v_ids || v_id;
  end loop;
  for i in 0..n - 1 loop
    fila := i / k;
    col := i % k;
    idx := case when fila % 2 = 0 then col else k - 1 - col end;
    insert into torneo_carrera_jugadores (carrera_id, user_id) values (v_ids[idx + 1], p_jugadores[i + 1]);
  end loop;
  return k;
end;
$$;

-- Revisa si la fase actual ya termino y, si si, arma la siguiente.
create or replace function public.torneo_avanzar(p_torneo uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_t torneos;
  v_ronda int;
  v_carreras int;
  v_pasan uuid[];
  v_todos uuid[];
  v_campeon uuid;
  v_apodo text;
begin
  select * into v_t from torneos where id = p_torneo for update;
  if v_t.fase not in ('grupos', 'finales') then return; end if;

  if v_t.fase = 'grupos' then
    if exists (select 1 from torneo_carreras
                where torneo_id = p_torneo and tipo = 'grupo' and estado <> 'completada') then
      return;
    end if;
    -- Los 2 mejores de cada grupo. Siembra: primero los 1.º lugares, luego los 2.º.
    select array_agg(user_id order by lugar, puntos desc, victorias desc, posicion_media, user_id)
      into v_pasan
      from (select t.*, row_number() over (partition by t.grupo
                          order by t.puntos desc, t.victorias desc, t.posicion_media, t.user_id) as lugar
              from torneo_tabla t
             where t.torneo_id = p_torneo and t.tipo = 'grupo') r
     where lugar <= 2;
    v_ronda := 1;
  else
    select max(ronda) into v_ronda from torneo_carreras where torneo_id = p_torneo and tipo = 'final';
    if exists (select 1 from torneo_carreras
                where torneo_id = p_torneo and tipo = 'final' and ronda = v_ronda
                  and estado <> 'completada') then
      return;
    end if;
    select count(*) into v_carreras
      from torneo_carreras where torneo_id = p_torneo and tipo = 'final' and ronda = v_ronda;

    if v_carreras = 1 then
      select cj.user_id into v_campeon
        from torneo_carreras c join torneo_carrera_jugadores cj on cj.carrera_id = c.id
       where c.torneo_id = p_torneo and c.tipo = 'final' and c.ronda = v_ronda and cj.posicion = 1;
      update torneos set fase = 'terminado', campeon = v_campeon where id = p_torneo;
      select apodo into v_apodo from torneo_jugadores where user_id = v_campeon;
      select array_agg(user_id) into v_todos from torneo_grupos where torneo_id = p_torneo;
      perform torneo_avisar(v_todos, '🏆 ¡Tenemos campeón!',
        coalesce(v_apodo, 'Alguien') || ' ganó la Gran Final de ' || v_t.nombre || '.',
        jsonb_build_object('torneo_id', p_torneo));
      return;
    end if;

    select array_agg(user_id order by lugar, puntos desc, victorias desc, posicion_media, user_id)
      into v_pasan
      from (select t.*, row_number() over (partition by t.grupo
                          order by t.puntos desc, t.victorias desc, t.posicion_media, t.user_id) as lugar
              from torneo_tabla t
             where t.torneo_id = p_torneo and t.tipo = 'final' and t.ronda = v_ronda) r
     where lugar <= 2;
    v_ronda := v_ronda + 1;
  end if;

  update torneos set fase = 'finales' where id = p_torneo;
  v_carreras := torneo_crear_ronda(p_torneo, v_ronda, v_pasan);
  perform torneo_avisar(v_pasan,
    case when v_carreras = 1 then '🏁 ¡Estás en la Gran Final!' else '🏁 ¡Pasaste a finales!' end,
    case when v_carreras = 1 then 'Corres la Gran Final de ' || v_t.nombre || '. Revisa el horario en Torneos.'
         else 'Pasaste a la ronda ' || v_ronda || ' de finales de ' || v_t.nombre || '.' end,
    jsonb_build_object('torneo_id', p_torneo));
end;
$$;

-- ── Funciones del cliente ───────────────────────────────────────────────────────────────────────

create or replace function public.torneo_registrarme(p_apodo text, p_avatar text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Inicia sesión para inscribirte.'; end if;
  if char_length(btrim(coalesce(p_apodo, ''))) < 2 then
    raise exception 'El apodo debe tener al menos 2 letras.';
  end if;
  if exists (select 1 from torneo_jugadores
              where lower(btrim(apodo)) = lower(btrim(p_apodo)) and user_id <> auth.uid()) then
    raise exception 'Ese apodo ya lo tiene otro jugador.';
  end if;
  insert into torneo_jugadores (user_id, apodo, avatar)
  values (auth.uid(), btrim(p_apodo), coalesce(nullif(btrim(p_avatar), ''), '🏎️'))
  on conflict (user_id) do update
     set apodo = excluded.apodo, avatar = excluded.avatar, updated_at = now();
end;
$$;

create or replace function public.torneo_crear(p_nombre text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not torneo_es_organizador() then raise exception 'Solo el organizador puede crear torneos.'; end if;
  if exists (select 1 from torneos where fase <> 'terminado') then
    raise exception 'Ya hay un torneo en curso. Termínalo antes de crear otro.';
  end if;
  insert into torneos (nombre) values (btrim(p_nombre)) returning id into v_id;
  return v_id;
end;
$$;

-- Calendarios por tamaño de grupo (indices de jugador, carreras de 4). Buscados el 06/10/2026:
-- en todos, cada jugador corre las mismas veces y enfrenta al menos una vez a cada uno de su grupo.
--   4 → 1 carrera (1 c/u)   5 → 5 (4 c/u)   6 → 3 (2 c/u)   7 → 7 (4 c/u)   8 → 6 (3 c/u)
create or replace function public.torneo_generar_liga(p_torneo uuid)
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
  if not torneo_es_organizador() then raise exception 'Solo el organizador puede armar la Liga.'; end if;
  select * into v_t from torneos where id = p_torneo for update;
  if not found then raise exception 'No existe ese torneo.'; end if;
  if v_t.fase = 'terminado' then raise exception 'Este torneo ya terminó.'; end if;

  select array_agg(user_id order by random()) into v_jug from torneo_jugadores;
  n := coalesce(cardinality(v_jug), 0);
  if n < 4 then raise exception 'Se necesitan al menos 4 jugadores inscritos (hay %).', n; end if;

  delete from torneo_carreras where torneo_id = p_torneo;
  delete from torneo_grupos where torneo_id = p_torneo;

  -- Grupos de 4 a 8: ceil(n/8) grupos, repartidos de uno en uno.
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

  -- Numeradas por jornada: primero la 1 de cada grupo, luego la 2…
  update torneo_carreras c set numero = r.num
    from (select id, row_number() over (order by ronda, grupo) as num
            from torneo_carreras where torneo_id = p_torneo) r
   where c.id = r.id;

  update torneos set fase = 'grupos', campeon = null where id = p_torneo;

  for i in 0..g - 1 loop
    v_nombre := chr(65 + i);
    select array_agg(user_id) into v_miembros from torneo_grupos
     where torneo_id = p_torneo and grupo = v_nombre;
    perform torneo_avisar(v_miembros, '🏎️ ¡Ya estás en la Liga!',
      'Quedaste en el Grupo ' || v_nombre || ' de ' || v_t.nombre || '. Revisa tus carreras en Torneos.',
      jsonb_build_object('torneo_id', p_torneo));
  end loop;

  return jsonb_build_object('grupos', g, 'carreras', v_total, 'jugadores', n);
end;
$$;

-- p_orden: los jugadores del 1.º al último lugar.
create or replace function public.torneo_capturar(p_carrera uuid, p_orden uuid[])
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c torneo_carreras;
  v_t torneos;
  v_org boolean := torneo_es_organizador();
  v_participantes uuid[];
  v_puntos int[];
  v_apodo text;
begin
  select * into v_c from torneo_carreras where id = p_carrera for update;
  if not found then raise exception 'No existe esa carrera.'; end if;
  if v_c.estado = 'cancelada' then raise exception 'Esa carrera se canceló.'; end if;

  select array_agg(user_id) into v_participantes from torneo_carrera_jugadores where carrera_id = p_carrera;
  if not (auth.uid() = any (v_participantes)) and not v_org then
    raise exception 'Solo quien corrió esta carrera puede capturar el resultado.';
  end if;
  if coalesce(cardinality(v_participantes), 0) < 2 then
    raise exception 'Una carrera necesita al menos 2 jugadores.';
  end if;
  if cardinality(p_orden) <> cardinality(v_participantes)
     or (select count(distinct x) from unnest(p_orden) x) <> cardinality(v_participantes)
     or not (p_orden <@ v_participantes) then
    raise exception 'Ordena a todos los jugadores de la carrera, sin repetir.';
  end if;

  if v_c.estado = 'completada' then
    if not v_org then raise exception 'Este resultado ya está confirmado.'; end if;
    -- Corregir una carrera que ya dio lugar a la fase siguiente dejaría las finales mal armadas.
    select * into v_t from torneos where id = v_c.torneo_id;
    if v_c.tipo = 'grupo' and v_t.fase <> 'grupos'
       or v_c.tipo = 'final' and (v_t.fase = 'terminado' or exists (
            select 1 from torneo_carreras where torneo_id = v_c.torneo_id and tipo = 'final'
               and ronda > v_c.ronda)) then
      raise exception 'Ya se armó la fase siguiente con este resultado; no se puede corregir.';
    end if;
  end if;

  if v_c.tipo = 'libre' then
    v_puntos := '{10,7,5,3,2,1,0,0}';
  else
    select puntos into v_puntos from torneos where id = v_c.torneo_id;
  end if;

  update torneo_carrera_jugadores
     set posicion = array_position(p_orden, user_id),
         puntos = coalesce(v_puntos[array_position(p_orden, user_id)], 0)
   where carrera_id = p_carrera;

  if v_org then
    update torneo_carreras
       set estado = 'completada', capturada_por = auth.uid(), capturada_at = now(),
           confirmada_por = auth.uid(), confirmada_at = now()
     where id = p_carrera;
    if v_c.torneo_id is not null then perform torneo_avanzar(v_c.torneo_id); end if;
    return 'completada';
  end if;

  update torneo_carreras
     set estado = 'por_confirmar', capturada_por = auth.uid(), capturada_at = now(),
         confirmada_por = null, confirmada_at = null
   where id = p_carrera;
  select apodo into v_apodo from torneo_jugadores where user_id = auth.uid();
  perform torneo_avisar(v_participantes, '🏁 Confirma el resultado',
    coalesce(v_apodo, 'Un jugador') || ' capturó el resultado de ' || torneo_nombre_carrera(v_c)
      || '. Entra a Torneos para confirmarlo.',
    jsonb_build_object('carrera_id', p_carrera), auth.uid());
  return 'por_confirmar';
end;
$$;

create or replace function public.torneo_confirmar(p_carrera uuid, p_acepta boolean)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c torneo_carreras;
  v_org boolean := torneo_es_organizador();
  v_apodo text;
begin
  select * into v_c from torneo_carreras where id = p_carrera for update;
  if not found then raise exception 'No existe esa carrera.'; end if;
  if v_c.estado <> 'por_confirmar' then raise exception 'Esta carrera no tiene un resultado por confirmar.'; end if;
  if not v_org then
    if not exists (select 1 from torneo_carrera_jugadores where carrera_id = p_carrera and user_id = auth.uid()) then
      raise exception 'Solo quien corrió esta carrera puede confirmar el resultado.';
    end if;
    if v_c.capturada_por = auth.uid() then
      raise exception 'Otro jugador de la carrera tiene que confirmar lo que capturaste.';
    end if;
  end if;

  select apodo into v_apodo from torneo_jugadores where user_id = auth.uid();

  if p_acepta then
    update torneo_carreras set estado = 'completada', confirmada_por = auth.uid(), confirmada_at = now()
     where id = p_carrera;
    if v_c.torneo_id is not null then perform torneo_avanzar(v_c.torneo_id); end if;
    perform torneo_avisar(array[v_c.capturada_por], '✅ Resultado confirmado',
      coalesce(v_apodo, 'Otro jugador') || ' confirmó el resultado de ' || torneo_nombre_carrera(v_c) || '.',
      jsonb_build_object('carrera_id', p_carrera), auth.uid());
    return 'completada';
  end if;

  update torneo_carrera_jugadores set posicion = null, puntos = null where carrera_id = p_carrera;
  update torneo_carreras set estado = 'programada', capturada_por = null, capturada_at = null
   where id = p_carrera;
  perform torneo_avisar(array[v_c.capturada_por], '↩️ Resultado rechazado',
    coalesce(v_apodo, 'Otro jugador') || ' no estuvo de acuerdo con el resultado de '
      || torneo_nombre_carrera(v_c) || '. Vuelvan a capturarlo.',
    jsonb_build_object('carrera_id', p_carrera), auth.uid());
  return 'programada';
end;
$$;

create or replace function public.torneo_programar(p_carrera uuid, p_fecha timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c torneo_carreras;
  v_jug uuid[];
begin
  select * into v_c from torneo_carreras where id = p_carrera for update;
  if not found then raise exception 'No existe esa carrera.'; end if;
  if not torneo_es_organizador() and not (v_c.tipo = 'libre' and v_c.creada_por = auth.uid()) then
    raise exception 'Solo el organizador puede poner el horario.';
  end if;
  if v_c.estado not in ('programada', 'por_confirmar') then
    raise exception 'Esa carrera ya no se puede reprogramar.';
  end if;
  update torneo_carreras set fecha_hora = p_fecha where id = p_carrera;
  if p_fecha is not null then
    select array_agg(user_id) into v_jug from torneo_carrera_jugadores where carrera_id = p_carrera;
    perform torneo_avisar(v_jug, '🗓️ Horario de carrera',
      torneo_nombre_carrera(v_c) || ': '
        || to_char(p_fecha at time zone 'America/Mexico_City', 'DD/MM/YYYY HH24:MI') || '.',
      jsonb_build_object('carrera_id', p_carrera), auth.uid());
  end if;
end;
$$;

-- ── Kart Garage ─────────────────────────────────────────────────────────────────────────────────

create or replace function public.garage_crear(
  p_fecha timestamptz, p_abierta boolean, p_cupo int, p_invitados uuid[] default '{}')
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_inv uuid[];
  v_apodo text;
begin
  select apodo into v_apodo from torneo_jugadores where user_id = auth.uid();
  if v_apodo is null then raise exception 'Inscríbete primero para crear carreras.'; end if;
  if p_cupo is null or p_cupo not between 2 and 8 then raise exception 'El cupo va de 2 a 8 jugadores.'; end if;

  select coalesce(array_agg(j.user_id), '{}') into v_inv
    from torneo_jugadores j
   where j.user_id = any (coalesce(p_invitados, '{}')) and j.user_id <> auth.uid();
  if not p_abierta and cardinality(v_inv) = 0 then
    raise exception 'Una carrera por invitación necesita al menos un invitado.';
  end if;
  if cardinality(v_inv) + 1 > p_cupo then
    raise exception 'Invitaste a más jugadores de los que caben (cupo de %).', p_cupo;
  end if;

  insert into torneo_carreras (tipo, fecha_hora, abierta, cupo, creada_por)
  values ('libre', p_fecha, coalesce(p_abierta, true), p_cupo, auth.uid())
  returning id into v_id;
  insert into torneo_carrera_jugadores (carrera_id, user_id)
  select v_id, u from unnest(array[auth.uid()] || v_inv) u;

  perform torneo_avisar(v_inv, '🔥 Te retaron en Kart Garage',
    v_apodo || ' te invitó a una carrera'
      || coalesce(' el ' || to_char(p_fecha at time zone 'America/Mexico_City', 'DD/MM/YYYY "a las" HH24:MI'), '')
      || '.',
    jsonb_build_object('carrera_id', v_id));
  return v_id;
end;
$$;

create or replace function public.garage_unirme(p_carrera uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c torneo_carreras;
begin
  select * into v_c from torneo_carreras where id = p_carrera for update;
  if not found or v_c.tipo <> 'libre' then raise exception 'No existe esa carrera.'; end if;
  if v_c.estado <> 'programada' then raise exception 'Esta carrera ya no acepta jugadores.'; end if;
  if not v_c.abierta then raise exception 'Esta carrera es solo por invitación.'; end if;
  if not exists (select 1 from torneo_jugadores where user_id = auth.uid()) then
    raise exception 'Inscríbete primero.';
  end if;
  -- Sin ON CONFLICT: la restriccion diferida de `posicion` no le sirve de arbitro.
  if exists (select 1 from torneo_carrera_jugadores where carrera_id = p_carrera and user_id = auth.uid()) then
    return;
  end if;
  if (select count(*) from torneo_carrera_jugadores where carrera_id = p_carrera) >= v_c.cupo then
    raise exception 'La carrera ya está llena.';
  end if;
  insert into torneo_carrera_jugadores (carrera_id, user_id) values (p_carrera, auth.uid());
end;
$$;

create or replace function public.garage_salir(p_carrera uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c torneo_carreras;
begin
  select * into v_c from torneo_carreras where id = p_carrera for update;
  if not found or v_c.tipo <> 'libre' then raise exception 'No existe esa carrera.'; end if;
  if v_c.estado <> 'programada' then raise exception 'Ya no puedes salirte de esta carrera.'; end if;
  if v_c.creada_por = auth.uid() then raise exception 'Creaste la carrera: cancélala en lugar de salirte.'; end if;
  delete from torneo_carrera_jugadores where carrera_id = p_carrera and user_id = auth.uid();
end;
$$;

create or replace function public.garage_cancelar(p_carrera uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c torneo_carreras;
  v_jug uuid[];
begin
  select * into v_c from torneo_carreras where id = p_carrera for update;
  if not found or v_c.tipo <> 'libre' then raise exception 'No existe esa carrera.'; end if;
  if v_c.creada_por is distinct from auth.uid() and not torneo_es_organizador() then
    raise exception 'Solo quien creó la carrera puede cancelarla.';
  end if;
  if v_c.estado = 'completada' then raise exception 'Esa carrera ya se corrió.'; end if;
  update torneo_carreras set estado = 'cancelada' where id = p_carrera;
  select array_agg(user_id) into v_jug from torneo_carrera_jugadores where carrera_id = p_carrera;
  perform torneo_avisar(v_jug, '❌ Carrera cancelada',
    'Se canceló una carrera de Kart Garage a la que ibas.',
    jsonb_build_object('carrera_id', p_carrera), auth.uid());
end;
$$;

-- ── Permisos de ejecucion ───────────────────────────────────────────────────────────────────────

revoke all on function public.torneo_es_organizador() from public, anon;
revoke all on function public.torneo_avisar(uuid[], text, text, jsonb, uuid) from public, anon, authenticated;
revoke all on function public.torneo_crear_ronda(uuid, int, uuid[]) from public, anon, authenticated;
revoke all on function public.torneo_avanzar(uuid) from public, anon, authenticated;
revoke all on function public.torneo_registrarme(text, text) from public, anon;
revoke all on function public.torneo_crear(text) from public, anon;
revoke all on function public.torneo_generar_liga(uuid) from public, anon;
revoke all on function public.torneo_capturar(uuid, uuid[]) from public, anon;
revoke all on function public.torneo_confirmar(uuid, boolean) from public, anon;
revoke all on function public.torneo_programar(uuid, timestamptz) from public, anon;
revoke all on function public.garage_crear(timestamptz, boolean, int, uuid[]) from public, anon;
revoke all on function public.garage_unirme(uuid) from public, anon;
revoke all on function public.garage_salir(uuid) from public, anon;
revoke all on function public.garage_cancelar(uuid) from public, anon;

grant execute on function public.torneo_es_organizador() to authenticated;
grant execute on function public.torneo_registrarme(text, text) to authenticated;
grant execute on function public.torneo_crear(text) to authenticated;
grant execute on function public.torneo_generar_liga(uuid) to authenticated;
grant execute on function public.torneo_capturar(uuid, uuid[]) to authenticated;
grant execute on function public.torneo_confirmar(uuid, boolean) to authenticated;
grant execute on function public.torneo_programar(uuid, timestamptz) to authenticated;
grant execute on function public.garage_crear(timestamptz, boolean, int, uuid[]) to authenticated;
grant execute on function public.garage_unirme(uuid) to authenticated;
grant execute on function public.garage_salir(uuid) to authenticated;
grant execute on function public.garage_cancelar(uuid) to authenticated;

-- ── Datos iniciales ─────────────────────────────────────────────────────────────────────────────

-- Organizadores, a pedido del usuario: empleados 0163 y 2245.
update public.profiles
   set permissions = coalesce(permissions, '{}'::jsonb) || '{"show_torneos_admin": true}'::jsonb
 where numero_empleado in ('0163', '2245');

-- El primer torneo, para que la inscripcion abra desde ya.
insert into public.torneos (nombre, created_by)
select 'SiSol Mario Kart Cup', null
 where not exists (select 1 from public.torneos);
