-- El aviso de cambio de estatus dice QUIEN lo autorizo.
--
-- ─── Lo que faltaba ─────────────────────────────────────────────────────────
--
-- El aviso llegaba asi:
--
--     Solicitud de Dulce Marisela Camacho Vargas · 1 dia · del 15/09/2026 al 15/09/2026
--     · PENDIENTE -> APROBADA
--
-- Dice que se aprobo y no dice quien. Con varios administradores y con Soli aprobando por
-- WhatsApp, quien recibe el aviso no tiene manera de saber a quien preguntarle.
--
-- ─── Por que hace falta una columna ─────────────────────────────────────────
--
-- El disparador ya tenia el dato a mano para la app: `auth.uid()`. Lo usaba solo para EXCLUIR de
-- los avisos a quien hizo el cambio, nunca para nombrarlo.
--
-- Pero `auth.uid()` es nulo cuando el cambio viene de una funcion con la llave de servicio, que es
-- justo como aprueba Soli por WhatsApp. Ahi no habria a quien nombrar, y es el camino donde mas
-- falta hace: por la aplicacion al menos ves la pantalla desde la que aprobaste.
--
-- De ahi `autorizada_por`: la rellena Soli, que si sabe quien le esta hablando. La aplicacion NO la
-- escribe, a proposito:
--
--   * no le hace falta -su `auth.uid()` funciona-, y
--   * `auth.uid()` no se puede falsificar y una columna que manda el cliente si. Si la aplicacion
--     la escribiera, cualquiera con permiso de actualizar podria dejar una aprobacion a nombre de
--     otra persona.
--
-- Por eso el disparador prefiere SIEMPRE `auth.uid()` y solo cae en la columna cuando es nulo, que
-- es cuando el que escribe es uno de nuestros propios servicios.

alter table public.incidencias
  add column if not exists autorizada_por uuid references public.profiles(id) on delete set null;

comment on column public.incidencias.autorizada_por is
  'Quien cambio el estatus, cuando el cambio NO viene de una sesion de usuario. La rellenan las '
  'funciones que escriben con la llave de servicio (Soli); la aplicacion no, porque para ella el '
  'disparador usa auth.uid(), que no se puede falsificar.';

create or replace function public.notificar_cambio_de_estatus()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'net', 'vault'
as $function$
declare
  quien    text;
  detalle  text;
  destino  uuid;
  secreto  text;
  url      text := 'https://zkmbebybyyefmqcxjqrg.supabase.co/functions/v1/whatsapp-openwa';
  destinos uuid[] := '{}';
  -- UN solo valor para nombrar y para excluir.
  --
  -- Antes era `auth.uid()` a secas y solo servia para excluir. Con la llave de servicio -Soli- era
  -- nulo, asi que ni se nombraba a nadie ni se excluia a nadie: quien aprobaba por WhatsApp recibia
  -- el aviso de su propia aprobacion si ademas estaba en Desarrollo Humano.
  --
  -- `auth.uid()` va PRIMERO porque no se puede falsificar; la columna solo entra cuando es nulo.
  quien_cambio uuid := coalesce(auth.uid(), new.autorizada_por);
  autor    text;
begin
  select coalesce(nullif(trim(concat_ws(' ', p.nombre, p.paterno, p.materno)), ''),
                  new.nombre_usuario, 'Un colaborador')
    into quien
    from profiles p where p.id = new.usuario_id;
  quien := coalesce(quien, new.nombre_usuario, 'Un colaborador');

  -- Quien lo autorizo, por su nombre.
  --
  -- Si no se sabe, la frase NO se pone: es mejor un aviso que no lo diga que uno que diga «el
  -- sistema» y deje a quien lo lee creyendo que nadie lo reviso.
  if quien_cambio is not null then
    select nullif(trim(concat_ws(' ', p.nombre, p.paterno, p.materno)), '')
      into autor
      from profiles p where p.id = quien_cambio;
  end if;

  detalle := 'Solicitud de ' || quien
    || coalesce(' · ' || new.dias::text || ' dia' || case when new.dias = 1 then '' else 's' end, '')
    || coalesce(' · del ' || to_char(new.fecha_inicio, 'DD/MM/YYYY'), '')
    || coalesce(' al ' || to_char(new.fecha_fin, 'DD/MM/YYYY'), '')
    || ' · ' || old.status || ' -> ' || new.status
    || coalesce(' · ' || case new.status
                           when 'APROBADA'  then 'Autorizada por '
                           when 'RECHAZADA' then 'Rechazada por '
                           when 'CANCELADA' then 'Cancelada por '
                           else 'Cambiada por '
                         end || autor, '');

  -- Quien la pidio.
  begin
    if new.usuario_id is not null
       and (quien_cambio is null or new.usuario_id <> quien_cambio) then
      insert into notifications (title, message, type, is_read, created_at, user_id, metadata)
      values ('Tu solicitud fue ' || new.status,
              detalle, 'incidencia_status', false, now(), new.usuario_id,
              jsonb_build_object('incidencia_id', new.id, 'motivo', 'solicitante',
                                 'de', old.status, 'a', new.status,
                                 -- Queda tambien en los datos, no solo en la frase: asi se puede
                                 -- consultar despues quien autorizo que, sin leer textos.
                                 'por', quien_cambio, 'por_nombre', autor));
      destinos := destinos || new.usuario_id;
    end if;
  exception when others then
    raise warning 'aviso al solicitante fallo, incidencia %: %', new.id, sqlerrm;
  end;

  -- Desarrollo Humano.
  begin
    for destino in
      select p.id from profiles p
       where p.puesto ilike '%DESARROLLO HUMANO%'
         and p.status_rh <> 'BAJA'
         and p.has_auth_account = true
         and p.id <> new.usuario_id
         and (quien_cambio is null or p.id <> quien_cambio)
    loop
      insert into notifications (title, message, type, is_read, created_at, user_id, metadata)
      values ('Solicitud ' || new.status,
              detalle, 'incidencia_status', false, now(), destino,
              jsonb_build_object('incidencia_id', new.id, 'motivo', 'desarrollo_humano',
                                 'de', old.status, 'a', new.status,
                                 'por', quien_cambio, 'por_nombre', autor));
      destinos := destinos || destino;
    end loop;
  exception when others then
    raise warning 'aviso a Desarrollo Humano fallo, incidencia %: %', new.id, sqlerrm;
  end;

  -- Y por WhatsApp, a los mismos.
  begin
    select decrypted_secret into secreto
      from vault.decrypted_secrets where name = 'aviso_whatsapp_secret' limit 1;
    if secreto is not null and secreto <> '' then
      foreach destino in array destinos loop
        perform net.http_post(
          url := url,
          headers := jsonb_build_object('Content-Type', 'application/json', 'X-Aviso', secreto),
          body := jsonb_build_object('accion', 'avisar', 'profile_id', destino,
            'texto', '*Solicitud ' || new.status || '*' || chr(10) || detalle));
      end loop;
    end if;
  exception when others then
    raise warning 'aviso por WhatsApp fallo, incidencia %: %', new.id, sqlerrm;
  end;

  return new;
end;
$function$;
