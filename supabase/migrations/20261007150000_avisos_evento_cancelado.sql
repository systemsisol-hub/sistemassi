-- Aviso en el sistema cuando se cancela o se mueve un evento (07/10/2026, a pedido del usuario).
--
-- Hasta hoy, borrar un evento mandaba la cancelación por correo pero dentro del sistema no avisaba:
-- la invitación desaparecía en silencio y la notificación «Te invitaron a…» seguía en la campana,
-- llevando a un evento que ya no existe.
--
--   * Al borrar un evento, cada invitado recibe `event_cancelled` («Se canceló: …»). Si se borra una
--     serie completa, una sola notificación por persona, no una por fecha.
--   * Las notificaciones de invitación de ese evento quedan marcadas `metadata.cancelado = true`, y la
--     app ya no las abre.
--   * Al cambiar la fecha u hora de un evento, cada invitado recibe `event_updated`.
--
-- Va en triggers de la base, así funciona igual desde la web, el teléfono o cualquier otro lado.
-- Quien hace el cambio no se avisa a sí mismo.

create or replace function public.notificar_evento_cancelado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  fecha text := to_char(old.start_time at time zone 'America/Mexico_City', 'DD/MM/YYYY HH24:MI');
begin
  insert into public.notifications (user_id, title, message, type, metadata)
  select i.user_id,
         'Se canceló un evento',
         case when old.serie_id is null
              then 'Se canceló: ' || coalesce(old.title, 'un evento') || ' (' || fecha || ').'
              else 'Se canceló: ' || coalesce(old.title, 'un evento') || '.' end,
         'event_cancelled',
         jsonb_build_object(
           'event_title', coalesce(old.title, ''),
           'event_date',  old.start_time::text,
           'serie_id',    old.serie_id,
           'priority',    coalesce(old.priority, 'Normal'))
    from public.event_invitations i
   where i.event_id = old.id
     and i.user_id is distinct from auth.uid()
     -- Una serie borrada de golpe: un aviso por persona (now() es el mismo en toda la operación).
     and not (old.serie_id is not null and exists (
           select 1 from public.notifications n
            where n.user_id = i.user_id
              and n.type = 'event_cancelled'
              and n.metadata->>'serie_id' = old.serie_id::text
              and n.created_at = now()));

  update public.notifications
     set metadata = coalesce(metadata, '{}'::jsonb) || '{"cancelado": true}'::jsonb
   where type = 'event_invitation'
     and metadata->>'event_id' = old.id::text;

  return old;
end;
$$;

drop trigger if exists tr_notificar_evento_cancelado on public.events;
create trigger tr_notificar_evento_cancelado
  before delete on public.events
  for each row execute function public.notificar_evento_cancelado();

create or replace function public.notificar_evento_movido()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.start_time is not distinct from old.start_time
     and new.end_time is not distinct from old.end_time then
    return null;
  end if;
  insert into public.notifications (user_id, title, message, type, metadata)
  select i.user_id,
         'Cambió un evento',
         coalesce(new.title, 'Un evento') || ' ahora es el '
           || to_char(new.start_time at time zone 'America/Mexico_City', 'DD/MM/YYYY "a las" HH24:MI') || '.',
         'event_updated',
         jsonb_build_object(
           'event_id',    new.id,
           'event_title', coalesce(new.title, ''),
           'event_date',  new.start_time::text,
           'priority',    coalesce(new.priority, 'Normal'))
    from public.event_invitations i
   where i.event_id = new.id
     and i.status is distinct from 'declined'
     and i.user_id is distinct from auth.uid();
  return null;
end;
$$;

drop trigger if exists tr_notificar_evento_movido on public.events;
create trigger tr_notificar_evento_movido
  after update of start_time, end_time on public.events
  for each row execute function public.notificar_evento_movido();
