-- El horario de cada colaborador, tomado de sus checadas de appchecar.
--
-- Pedido del 28/09/2026: el semáforo del Checador compara cada checada contra el horario de la
-- persona. Pero NINGÚN colaborador tenía horario asignado en el sistema —0 de 74 activos—: el Panel
-- de appchecar no lo necesitaba porque el horario llega en cada renglón del reporte.
--
-- Decisión del usuario: tomar el de appchecar y asignar los demás desde Usuarios. Así que a cada
-- activo sin horario se le pone el de su checada MÁS RECIENTE en `checador_registros`. Alcanza a 44;
-- los otros 30 no tienen horario en appchecar y se asignan a mano.
--
-- Sólo donde no hay horario: si alguien ya lo tiene, se respeta.

update public.profiles p
   set schedule_id = u.horario_id
  from (
    select distinct on (r.profile_id) r.profile_id, r.horario_id
      from public.checador_registros r
     where r.profile_id is not null and r.horario_id is not null
     order by r.profile_id, r.fecha desc, r.hora desc
  ) u
 where u.profile_id = p.id
   and p.schedule_id is null
   and p.status_sys = 'ACTIVO';
