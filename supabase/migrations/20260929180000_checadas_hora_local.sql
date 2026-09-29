-- Checadas: la hora local de México, a la vista en la tabla.
--
-- Pedido del 29/09/2026: «en la columna registrada_en no se guarda con la hora local de México».
--
-- `registrada_en` es `timestamptz`: guarda el INSTANTE exacto, y el panel de Supabase lo muestra en
-- UTC —seis horas adelante de la Ciudad de México, cinco de Quintana Roo—. No está mal y se queda
-- así: es lo único que no depende de dónde esté nadie, y convertirlo a una hora «sin zona» perdería
-- cuál de las dos zonas era.
--
-- Lo que se agrega son dos columnas CALCULADAS por la base, para leerla sin hacer cuentas:
--
--   * `zona_horaria` — `America/Cancun` (UTC-5) si se checó en Quintana Roo; si no,
--     `America/Mexico_City` (UTC-6). Se decide por las coordenadas, con la misma caja que usa la
--     aplicación (`desfaseHorasDe` en lib/services/checador.dart).
--   * `hora_local` — la hora en esa zona: lo que marcaba el reloj de la pared al checar.
--
-- Son `generated always ... stored`: se llenan solas, en las checadas que ya existen también, y
-- nadie las puede escribir a mano.
--
-- ─── Y el día, con la misma zona ───────────────────────────────────────────
--
-- `fecha` se calculaba siempre con la hora de la Ciudad de México. En Quintana Roo, una checada a
-- las 00:15 son las 23:15 del día ANTERIOR en la Ciudad de México, y habría caído en el día
-- equivocado. Ahora el disparador la calcula con la zona de donde se checó.

alter table public.checadas
  add column if not exists zona_horaria text generated always as (
    case
      when latitud between 17.8 and 21.8 and longitud between -89.5 and -86.5
      then 'America/Cancun'
      else 'America/Mexico_City'
    end
  ) stored;

alter table public.checadas
  add column if not exists hora_local timestamp generated always as (
    timezone(
      case
        when latitud between 17.8 and 21.8 and longitud between -89.5 and -86.5
        then 'America/Cancun'
        else 'America/Mexico_City'
      end,
      registrada_en)
  ) stored;

comment on column public.checadas.hora_local is
  'La hora de la checada en el lugar donde se hizo (ver zona_horaria). registrada_en es el mismo '
  'instante en UTC.';

create or replace function public.checada_antes_de_guardar()
returns trigger language plpgsql
set search_path = ''
as $$
declare
  hay text[];
  zona text := case
    when new.latitud between 17.8 and 21.8 and new.longitud between -89.5 and -86.5
    then 'America/Cancun'
    else 'America/Mexico_City'
  end;
begin
  new.registrada_en := now();
  new.fecha := (now() at time zone zona)::date;
  new.profile_id := coalesce(auth.uid(), new.profile_id);

  select coalesce(array_agg(c.tipo), '{}') into hay
    from public.checadas c
   where c.profile_id = new.profile_id and c.fecha = new.fecha;

  if new.tipo <> 'ENTRADA' and not ('ENTRADA' = any(hay)) then
    raise exception 'Primero hay que checar la entrada.';
  end if;
  if 'SALIDA' = any(hay) then
    raise exception 'La jornada de hoy ya se terminó.';
  end if;
  if new.tipo = 'REGRESO_COMIDA' and not ('SALIDA_COMIDA' = any(hay)) then
    raise exception 'No hay una salida a comer que cerrar.';
  end if;
  if new.tipo = 'SALIDA' and 'SALIDA_COMIDA' = any(hay) and not ('REGRESO_COMIDA' = any(hay)) then
    raise exception 'Falta checar el regreso de comer antes de terminar la jornada.';
  end if;
  return new;
end $$;
