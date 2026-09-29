-- Un solo horario por colaborador.
--
-- Pedido del usuario el 29/09/2026: el horario de Colaboradores «no es el mismo que el de la página
-- de usuarios, me gustaría que fuera el mismo». Y no lo era: eran dos columnas.
--
--   * `profiles.horario` (texto) — lo escribía Colaboradores, y lo leen Soli y la ficha.
--   * `profiles.schedule_id` (uuid) — lo usan Usuarios, `update_user_admin` y el Checador. El
--     28/09/2026 se llenó con el horario de appchecar para 44 personas.
--
-- Quedaron 11 activos con un horario distinto en cada una —8 con los dos puestos y 3 sólo en
-- Colaboradores—. Decisión del usuario: se queda el de COLABORADORES, que es el que alguien de RH
-- asignó a mano; el de appchecar lo tomó el sistema en automático.
--
-- ─── La columna que manda es `schedule_id` ─────────────────────────────────
--
-- La aplicación ya lee y escribe sólo `schedule_id`. `horario` se queda por ahora porque Soli lo usa
-- —«quiero mi horario», y crear o editar un colaborador— y la versión de la aplicación que está en
-- producción todavía escribe ahí. Mientras exista, el disparador de abajo la mantiene IGUAL a
-- `schedule_id` en los dos sentidos, así que no pueden volver a separarse. Cuando Soli pase a
-- `schedule_id`, `horario` y el disparador se quitan.

-- ─── 1. Lo de Colaboradores gana ───────────────────────────────────────────
update public.profiles p
   set schedule_id = p.horario::uuid
 where p.horario ~ '^[0-9a-fA-F-]{36}$'
   and exists (select 1 from public.schedules s where s.id::text = p.horario)
   and p.schedule_id is distinct from p.horario::uuid;

-- Y `horario` queda igual a `schedule_id` para todos, también donde sólo había uno o ninguno válido.
update public.profiles
   set horario = schedule_id::text
 where horario is distinct from schedule_id::text;

-- ─── 2. Que no vuelvan a separarse ─────────────────────────────────────────
create or replace function public.un_solo_horario()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and new.horario is distinct from old.horario
     and new.schedule_id is not distinct from old.schedule_id then
    -- Cambió sólo `horario` (Soli o la versión anterior de Colaboradores): manda el texto. Puede
    -- venir el id o el NOMBRE del horario —Soli recibe lo que el modelo escriba—. Vacío lo quita; un
    -- texto que no es ningún horario NO lo borra: se queda el que tenía.
    new.schedule_id := case
      when nullif(btrim(new.horario), '') is null then null
      else coalesce(
        (select s.id from public.schedules s where s.id::text = btrim(new.horario)),
        (select s.id from public.schedules s
          where lower(btrim(s.name)) = lower(btrim(new.horario)) limit 1),
        old.schedule_id)
    end;
  elsif tg_op = 'INSERT' and new.schedule_id is null
        and new.horario ~ '^[0-9a-fA-F-]{36}$'
        and exists (select 1 from public.schedules s where s.id::text = new.horario) then
    new.schedule_id := new.horario::uuid;
  end if;
  -- En cualquier otro caso manda `schedule_id`.
  new.horario := new.schedule_id::text;
  return new;
end $$;

drop trigger if exists tr_un_solo_horario on public.profiles;
create trigger tr_un_solo_horario before insert or update of horario, schedule_id on public.profiles
  for each row execute function public.un_solo_horario();
