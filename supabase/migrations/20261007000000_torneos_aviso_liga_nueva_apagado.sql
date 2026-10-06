-- El aviso de «Nueva liga» a todos los usuarios activos, apagado mientras se prueba con un grupo
-- (06/10/2026, a pedido del usuario). Solo ese aviso: los de sorteo, resultados, finales, Kart Garage
-- y el de liga sin jugadores para los organizadores siguen igual.
--
-- Para volver a encenderlo:
--   update public.torneo_ajustes set avisar_liga_nueva = true;

create table if not exists public.torneo_ajustes (
  id                boolean primary key default true check (id), -- una sola fila
  avisar_liga_nueva boolean not null default false
);
insert into public.torneo_ajustes (id) values (true) on conflict do nothing;

alter table public.torneo_ajustes enable row level security;
drop policy if exists torneo_ajustes_select on public.torneo_ajustes;
create policy torneo_ajustes_select on public.torneo_ajustes for select to authenticated using (true);

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

  if coalesce((select avisar_liga_nueva from torneo_ajustes limit 1), false) then
    select array_agg(p.id) into v_todos
      from profiles p join auth.users u on u.id = p.id
     where p.status_sys = 'ACTIVO' and not coalesce(p.is_blocked, false);
    perform torneo_avisar(v_todos, '🏁 Nueva liga: ' || v_t.nombre,
      coalesce(nullif(torneo_horario(v_t), '') || '. ', '')
        || 'Inscríbete en Torneos antes del '
        || to_char(p_cierre at time zone 'America/Mexico_City', 'DD/MM "a las" HH24:MI') || '.',
      jsonb_build_object('torneo_id', v_id), auth.uid());
  end if;
  return v_id;
end;
$$;
