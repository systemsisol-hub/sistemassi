-- El checador propio del sistema: foto, hora y ubicación de cada checada.
--
-- Pedido del usuario el 28/09/2026: una pestaña «Checador» en Asistencia con la foto del usuario, su
-- hora de checada y su ubicación por GPS, y checadas para salir a comer y para el fin de la jornada.
--
-- Decisiones del usuario, el mismo día:
--
--   * Cuatro checadas: ENTRADA, SALIDA_COMIDA, REGRESO_COMIDA y SALIDA (fin de jornada).
--   * INDEPENDIENTE de appchecar: «lo dejaremos de usar, entre más independiente mejor». Por eso es
--     una tabla nueva y no se mezcla con `checador_registros`, que es la importación de appchecar.
--   * La ubicación se REGISTRA —latitud, longitud y precisión—, pero no se bloquea a nadie por
--     estar lejos. Una geocerca por oficina puede venir después.
--   * Desde el teléfono y desde la computadora, con la foto tomada EN VIVO por la cámara.
--
-- ─── Lo que no se puede falsear desde el teléfono ───────────────────────────
--
-- La HORA la pone el servidor, no el dispositivo: el disparador ignora lo que llegue en
-- `registrada_en` y `fecha`. Adelantar el reloj del teléfono no cambia nada.
--
-- Una checada no se edita ni se borra: no hay políticas de UPDATE ni DELETE. Si hace falta corregir
-- algo, se hace con justificaciones, no reescribiendo el registro.
--
-- Lo que SÍ se puede falsear es el GPS —hay aplicaciones que lo simulan—. Por eso se guarda también
-- la precisión que reporta el dispositivo y la foto: son la forma de revisarlo.

create table if not exists public.checadas (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  tipo          text not null check (tipo in ('ENTRADA', 'SALIDA_COMIDA', 'REGRESO_COMIDA', 'SALIDA')),
  -- La pone el disparador. Ver arriba.
  registrada_en timestamptz not null default now(),
  -- El día al que pertenece, en hora del centro de México. También lo pone el disparador.
  fecha         date not null default ((now() at time zone 'America/Mexico_City')::date),
  latitud       double precision not null check (latitud between -90 and 90),
  longitud      double precision not null check (longitud between -180 and 180),
  -- En metros, lo que el dispositivo dice que puede equivocarse. En computadora, sin GPS, suele ser
  -- de cientos o miles de metros: la ubicación sale de la red.
  precision_m   double precision check (precision_m is null or precision_m >= 0),
  -- La foto, en el bucket privado `checador-fotos`: `<id del usuario>/<fecha>/<nombre>.jpg`.
  foto          text not null,
  -- «web» o «android», y el navegador. Para saber desde dónde se checó.
  dispositivo   text check (dispositivo is null or length(dispositivo) <= 300),
  -- Una de cada tipo por persona y por día. Es lo que hace que el orden tenga sentido.
  constraint checadas_una_por_tipo unique (profile_id, fecha, tipo)
);

comment on table public.checadas is
  'El checador propio del sistema (foto, hora del servidor y GPS). Independiente de appchecar.';

create index if not exists checadas_por_dia on public.checadas (fecha, profile_id);

-- ─── La hora del servidor y el orden del día ───────────────────────────────
create or replace function public.checada_antes_de_guardar()
returns trigger language plpgsql
set search_path = ''
as $$
declare
  hay text[];
begin
  new.registrada_en := now();
  new.fecha := (now() at time zone 'America/Mexico_City')::date;
  new.profile_id := coalesce(auth.uid(), new.profile_id);

  select coalesce(array_agg(c.tipo), '{}') into hay
    from public.checadas c
   where c.profile_id = new.profile_id and c.fecha = new.fecha;

  -- El orden del día: sin entrada no hay nada más; a comer se sale después de entrar y antes de
  -- terminar; se regresa sólo si se salió; y al terminar ya no hay comida que abrir.
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

drop trigger if exists tr_checada_antes_de_guardar on public.checadas;
create trigger tr_checada_antes_de_guardar before insert on public.checadas
  for each row execute function public.checada_antes_de_guardar();

-- ─── Quién puede ───────────────────────────────────────────────────────────
--
-- Cada quien checa por sí mismo y ve lo suyo. Los administradores ven todo: es la foto y la
-- ubicación de otra persona, y eso en este sistema sólo lo ve un administrador. `is_admin()` lee el
-- token, no `profiles`.
alter table public.checadas enable row level security;

drop policy if exists checadas_crea_la_propia on public.checadas;
create policy checadas_crea_la_propia on public.checadas
  for insert to authenticated
  with check (profile_id = auth.uid() and foto like (auth.uid()::text || '/%'));

drop policy if exists checadas_ve_la_propia on public.checadas;
create policy checadas_ve_la_propia on public.checadas
  for select to authenticated
  using (profile_id = auth.uid() or public.is_admin());

revoke update, delete on public.checadas from anon, authenticated;
revoke all on public.checadas from anon;

-- ─── Las fotos ─────────────────────────────────────────────────────────────
--
-- Privado: son fotos de la cara de las personas. Cada quien sube sólo a SU carpeta y ve la suya;
-- los administradores ven todas. 2 MB bastan: la pantalla las reduce a 800 px antes de subirlas.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('checador-fotos', 'checador-fotos', false, 2097152, array['image/jpeg'])
on conflict (id) do update
  set public = false, file_size_limit = 2097152, allowed_mime_types = array['image/jpeg'];

drop policy if exists checador_fotos_sube_la_propia on storage.objects;
create policy checador_fotos_sube_la_propia on storage.objects
  for insert to authenticated
  with check (bucket_id = 'checador-fotos'
              and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists checador_fotos_ve on storage.objects;
create policy checador_fotos_ve on storage.objects
  for select to authenticated
  using (bucket_id = 'checador-fotos'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
