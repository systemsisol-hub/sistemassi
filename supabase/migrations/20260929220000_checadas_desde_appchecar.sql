-- Las checadas de appchecar, pasadas al checador propio.
--
-- Pedido del usuario el 29/09/2026: «una migración de la base de datos de appchecar a la de
-- checador creada por nosotros». appchecar se va a dejar de usar, y su historia —3,217 checadas del
-- 16/07 al 15/09/2026, 49 personas— tiene que seguir viéndose en Registros.
--
-- Decisiones del usuario el mismo día: las FOTOS se copian a nuestro almacenamiento (lo hace la
-- función `copiar-fotos-appchecar`, por partes); las justificaciones de appchecar NO se usan; y la
-- pestaña Panel se queda por ahora, para comparar.
--
-- ─── Lo que appchecar no tiene ─────────────────────────────────────────────
--
-- * Coordenadas: trae la DIRECCIÓN y la SUCURSAL, no latitud ni longitud. Por eso las coordenadas
--   dejan de ser obligatorias —sólo para las que vienen de appchecar— y se guarda la dirección.
-- * Comida: sólo trae Entrada y Salida.
-- * Zona horaria: se saca de la sucursal. Quintana Roo va en hora de Cancún; Baja California en la
--   de Tijuana, que SÍ cambia de horario en verano; Constituyentes y Acapulco, en la del centro.
--
-- ─── La zona horaria, ahora con Baja California ────────────────────────────
--
-- La regla de la migración anterior sólo sabía de Quintana Roo y del centro. En appchecar hay
-- tres personas en Ensenada. Las columnas calculadas se rehacen: primero `zona` si viene —las de
-- appchecar—, si no, por las coordenadas, ahora con la caja de Baja California.
--
-- ─── Lo que no se migra ────────────────────────────────────────────────────
--
-- * Las 50 checadas sin persona (la sucursal «Temporales»): no hay a quién asignarlas.
-- * Las repetidas: 13 días tienen dos checadas del mismo tipo, y el checador admite una por tipo
--   por día. Se queda la PRIMERA entrada y la ÚLTIMA salida.
--
-- Se puede volver a correr: `appchecar_id` es único y lo que ya pasó no se duplica.

-- ─── 1. Las columnas nuevas ────────────────────────────────────────────────
alter table public.checadas
  add column if not exists origen text not null default 'SISTEMA'
    check (origen in ('SISTEMA', 'APPCHECAR')),
  add column if not exists zona text
    check (zona is null or zona in ('America/Mexico_City', 'America/Cancun', 'America/Tijuana')),
  add column if not exists direccion text,
  -- La foto en appchecar, mientras se copia. Y si no se pudo copiar, por qué.
  add column if not exists foto_origen text,
  add column if not exists foto_error text,
  add column if not exists appchecar_id uuid unique;

alter table public.checadas alter column latitud drop not null;
alter table public.checadas alter column longitud drop not null;
alter table public.checadas alter column foto drop not null;

-- Las del sistema siguen necesitando todo: coordenadas y foto.
alter table public.checadas drop constraint if exists checadas_sistema_completa;
alter table public.checadas add constraint checadas_sistema_completa check (
  origen = 'APPCHECAR' or (latitud is not null and longitud is not null and foto is not null)
);

-- ─── 2. La zona y la hora local, rehechas ──────────────────────────────────
alter table public.checadas drop column if exists hora_local;
alter table public.checadas drop column if exists zona_horaria;

alter table public.checadas
  add column zona_horaria text generated always as (
    coalesce(zona, case
      when latitud between 17.8 and 21.8 and longitud between -89.5 and -86.5
        then 'America/Cancun'
      when latitud between 28.0 and 32.8 and longitud between -117.3 and -112.5
        then 'America/Tijuana'
      else 'America/Mexico_City'
    end)
  ) stored;

alter table public.checadas
  add column hora_local timestamp generated always as (
    timezone(
      coalesce(zona, case
        when latitud between 17.8 and 21.8 and longitud between -89.5 and -86.5
          then 'America/Cancun'
        when latitud between 28.0 and 32.8 and longitud between -117.3 and -112.5
          then 'America/Tijuana'
        else 'America/Mexico_City'
      end),
      registrada_en)
  ) stored;

comment on column public.checadas.hora_local is
  'La hora de la checada en el lugar donde se hizo (ver zona_horaria). registrada_en es el mismo '
  'instante en UTC.';

-- El disparador, con la misma regla de zona para el día.
create or replace function public.checada_antes_de_guardar()
returns trigger language plpgsql
set search_path = ''
as $$
declare
  hay text[];
  zona text := case
    when new.latitud between 17.8 and 21.8 and new.longitud between -89.5 and -86.5
      then 'America/Cancun'
    when new.latitud between 28.0 and 32.8 and new.longitud between -117.3 and -112.5
      then 'America/Tijuana'
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

-- ─── 3. Nadie puede fabricar una checada «de appchecar» ────────────────────
drop policy if exists checadas_crea_la_propia on public.checadas;
create policy checadas_crea_la_propia on public.checadas
  for insert to authenticated
  with check (profile_id = auth.uid()
              and origen = 'SISTEMA'
              and zona is null
              and appchecar_id is null
              and foto like (auth.uid()::text || '/%'));

-- ─── 4. La migración ───────────────────────────────────────────────────────
--
-- Sin el disparador, que pondría la hora de AHORA y exigiría el orden del día.
alter table public.checadas disable trigger tr_checada_antes_de_guardar;

insert into public.checadas
  (profile_id, tipo, registrada_en, fecha, foto, dispositivo, origen, zona, direccion,
   foto_origen, appchecar_id)
select profile_id, tipo, registrada_en, fecha, null, dispositivo, 'APPCHECAR', zona, direccion,
       foto_url, id
  from (
    select distinct on (r.profile_id, r.fecha, t.tipo)
           r.id, r.profile_id, r.fecha, r.hora, r.foto_url, r.direccion,
           left(r.registro_con, 300) as dispositivo,
           t.tipo, z.zona,
           ((r.fecha + r.hora) at time zone z.zona) as registrada_en
      from public.checador_registros r
      cross join lateral (select case r.tipo when 'Entrada' then 'ENTRADA' else 'SALIDA' end as tipo) t
      cross join lateral (select case r.sucursal
                                   when 'Quintana Roo' then 'America/Cancun'
                                   when 'Baja California' then 'America/Tijuana'
                                   else 'America/Mexico_City'
                                 end as zona) z
     where r.profile_id is not null
       and r.tipo in ('Entrada', 'Salida')
       and r.fecha is not null and r.hora is not null
     -- La primera entrada del día y la última salida.
     order by r.profile_id, r.fecha, t.tipo,
              case when t.tipo = 'ENTRADA' then r.hora end asc,
              case when t.tipo = 'SALIDA' then r.hora end desc
  ) x
on conflict do nothing;

alter table public.checadas enable trigger tr_checada_antes_de_guardar;
