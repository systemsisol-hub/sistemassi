-- SOL lee la carpeta del Drive de un desarrollo: los nombres de todo lo que hay y el TEXTO de los PDF.
--
-- Pedido del usuario el 23/09/2026, empezando por AG117. Antes SOL solo conocia los 20 enlaces que
-- alguien capturo a mano en `documentos`, 17 de ellos carpetas: no veia lo que habia dentro, y un
-- archivo nuevo —las tipologias de cada mes— no existia para SOL hasta que alguien cambiaba el
-- enlace.
--
-- ─── Sin llave de Google, por decision del usuario ─────────────────────────
--
-- La carpeta es publica y se lee por su vista publica (`embeddedfolderview`), que no pide llave. La
-- API oficial SI la pide aunque la carpeta sea publica: responde 403 a quien no se identifica. Se le
-- planteo al usuario que esa vista no es una API y que Google puede cambiarla sin avisar; eligio
-- esta via. Si un dia deja de funcionar, el recorrido falla, queda registrado en
-- `drive_sincronizaciones.error` y se ve en Configuracion. Lo ya leido se conserva.
--
-- ─── Quien escribe y quien lee ─────────────────────────────────────────────
--
-- Escribe SOLO la funcion `drive-sync`, con la llave de servicio. Leen los administradores, que son
-- quienes ven la pestaña de Configuracion de SOL. SOL busca con `buscar_en_drive`, que solo puede
-- ejecutar la llave de servicio.

-- ─── 1. La carpeta de cada desarrollo ──────────────────────────────────────
alter table public.desarrollos
  add column if not exists drive_carpeta_id text
    check (drive_carpeta_id is null or drive_carpeta_id ~ '^[A-Za-z0-9_-]{10,}$');

comment on column public.desarrollos.drive_carpeta_id is
  'Id de la carpeta PUBLICA del Drive que SOL recorre y lee. Null = no se lee ninguna.';

update public.desarrollos
   set drive_carpeta_id = '15qj0oVBgFrHec1GU-pgWdLG6F8SIPN63'
 where nombre = 'AG117';

-- ─── 2. Buscar sin que importen los acentos ────────────────────────────────
--
-- «tipologia» tiene que encontrar «TIPOLOGÍA», y «recamara» a «RECÁMARA». `unaccent` no es
-- IMMUTABLE y no se puede usar en una columna calculada, asi que se envuelve en una que si lo es,
-- fijando el diccionario. Es la forma habitual de hacerlo.
create extension if not exists unaccent with schema extensions;

create or replace function public.sin_acentos(t text)
returns text language sql immutable parallel safe strict
set search_path = ''
as $$ select extensions.unaccent('extensions.unaccent'::regdictionary, t) $$;

-- ─── 3. Lo que hay en la carpeta ───────────────────────────────────────────
create table if not exists public.drive_archivos (
  -- El id del Drive. Un archivo que se sube de nuevo trae otro id, y es otra fila.
  id              text primary key,
  desarrollo_id   uuid not null references public.desarrollos(id) on delete cascade,
  -- La carpeta donde esta, desde la raiz: «7. Planos/VGZ/Plantas». Vacio = en la raiz.
  ruta            text not null default '',
  nombre          text not null,
  es_carpeta      boolean not null default false,
  enlace          text not null,
  -- La fecha TAL COMO LA MUESTRA Google: «Sep 17», «7/25/25». La vista publica no da mas.
  modificado      text,
  tamano          bigint,
  -- PENDIENTE: falta leerlo. LEYENDO: a medias, por paginas. LEIDO. SIN_TEXTO: un PDF escaneado o
  -- de pura imagen. NO_SE_LEE: no es PDF. ERROR: ver `error`. Las carpetas no llevan estado.
  estado          text check (estado in ('PENDIENTE', 'LEYENDO', 'LEIDO', 'SIN_TEXTO', 'NO_SE_LEE', 'ERROR')),
  error           text,
  paginas         integer,
  -- Por donde va la lectura de un PDF largo. Se lee por partes para no pasarse del tiempo de CPU
  -- de una funcion; ver `drive-sync/leer.ts`.
  pagina_siguiente integer,
  -- Cuantas veces se intento la MISMA pagina. Si la funcion se muere a media pagina —por CPU— no
  -- alcanza a escribir el error, y sin esto volveria a intentarla para siempre.
  intentos        integer not null default 0,
  texto          text check (texto is null or length(texto) <= 400000),
  leido_en        timestamptz,
  visto_en        timestamptz not null default now(),
  busqueda        tsvector generated always as (
                    to_tsvector('spanish', public.sin_acentos(
                      nombre || ' ' || ruta || ' ' || coalesce(texto, '')))
                  ) stored
);

comment on table public.drive_archivos is
  'Lo que SOL sabe de la carpeta del Drive de cada desarrollo. Solo escribe la funcion drive-sync.';

create index if not exists drive_archivos_busqueda on public.drive_archivos using gin (busqueda);
create index if not exists drive_archivos_por_desarrollo on public.drive_archivos (desarrollo_id, ruta);
create index if not exists drive_archivos_pendientes on public.drive_archivos (estado)
  where estado in ('PENDIENTE', 'LEYENDO');

-- ─── 4. Cada vez que se recorre ────────────────────────────────────────────
--
-- Para que Configuracion diga cuando se actualizo por ultima vez, que cambio y, sobre todo, si
-- FALLO. Un recorrido que falla en silencio deja a SOL contestando con una carpeta vieja.
create table if not exists public.drive_sincronizaciones (
  id            uuid primary key default gen_random_uuid(),
  desarrollo_id uuid not null references public.desarrollos(id) on delete cascade,
  pedida_por    uuid references public.profiles(id) on delete set null,
  iniciada_en   timestamptz not null default now(),
  terminada_en  timestamptz,
  carpetas      integer,
  archivos      integer,
  nuevos        integer,
  cambiados     integer,
  quitados      integer,
  error         text
);

create index if not exists drive_sincronizaciones_recientes
  on public.drive_sincronizaciones (desarrollo_id, iniciada_en desc);

-- ─── Quien puede ───────────────────────────────────────────────────────────
alter table public.drive_archivos enable row level security;
alter table public.drive_sincronizaciones enable row level security;

drop policy if exists drive_archivos_admin_lee on public.drive_archivos;
create policy drive_archivos_admin_lee on public.drive_archivos
  for select to authenticated using (public.is_admin());

drop policy if exists drive_sincronizaciones_admin_lee on public.drive_sincronizaciones;
create policy drive_sincronizaciones_admin_lee on public.drive_sincronizaciones
  for select to authenticated using (public.is_admin());

-- Sin politicas de escritura, y ademas sin permisos: que no dependa de que nadie agregue una.
revoke insert, update, delete on public.drive_archivos from anon, authenticated;
revoke insert, update, delete on public.drive_sincronizaciones from anon, authenticated;
revoke all on public.drive_archivos from anon;
revoke all on public.drive_sincronizaciones from anon;

-- ─── 5. La busqueda de SOL ─────────────────────────────────────────────────
--
-- Primero con TODAS las palabras; si no sale nada, con CUALQUIERA. «tipologia c recamaras» casi
-- nunca tiene las tres palabras en el mismo archivo con esa forma, y un cero ahi se lee como «no
-- existe».
--
-- El fragmento sale con `ts_headline` sobre el texto ya sin acentos: es lo que se busco, y asi el
-- resaltado cae donde toca.
create or replace function public.buscar_en_drive(
  consulta text,
  en_desarrollo text default null,
  limite integer default 6
)
returns table (
  id text, desarrollo text, ruta text, nombre text, es_carpeta boolean, enlace text,
  modificado text, estado text, paginas integer, fragmento text, relevancia real
)
language plpgsql stable
set search_path = public, extensions
as $$
declare
  q tsquery := websearch_to_tsquery('spanish', public.sin_acentos(coalesce(consulta, '')));
  tope integer := least(greatest(coalesce(limite, 6), 1), 20);
begin
  if numnode(q) = 0 then return; end if;

  return query
    select a.id, d.nombre, a.ruta, a.nombre, a.es_carpeta, a.enlace, a.modificado, a.estado,
           a.paginas,
           case when a.texto is null then null else
             ts_headline('spanish', public.sin_acentos(a.texto), q,
               'MaxFragments=3, MaxWords=40, MinWords=12, FragmentDelimiter=" … ", StartSel=«, StopSel=»')
           end,
           ts_rank(a.busqueda, q)
      from public.drive_archivos a
      join public.desarrollos d on d.id = a.desarrollo_id
     where a.busqueda @@ q
       and (en_desarrollo is null or d.nombre ilike '%' || en_desarrollo || '%')
     order by ts_rank(a.busqueda, q) desc, a.nombre
     limit tope;

  if found then return; end if;

  -- Ninguno con todas: se prueba con cualquiera de las palabras.
  q := replace(q::text, ' & ', ' | ')::tsquery;
  return query
    select a.id, d.nombre, a.ruta, a.nombre, a.es_carpeta, a.enlace, a.modificado, a.estado,
           a.paginas,
           case when a.texto is null then null else
             ts_headline('spanish', public.sin_acentos(a.texto), q,
               'MaxFragments=3, MaxWords=40, MinWords=12, FragmentDelimiter=" … ", StartSel=«, StopSel=»')
           end,
           ts_rank(a.busqueda, q)
      from public.drive_archivos a
      join public.desarrollos d on d.id = a.desarrollo_id
     where a.busqueda @@ q
       and (en_desarrollo is null or d.nombre ilike '%' || en_desarrollo || '%')
     order by ts_rank(a.busqueda, q) desc, a.nombre
     limit tope;
end $$;

-- La ejecuta SOL con la llave de servicio. Nadie desde la aplicacion: saltaria la RLS de la tabla.
revoke all on function public.buscar_en_drive(text, text, integer) from public, anon, authenticated;
grant execute on function public.buscar_en_drive(text, text, integer) to service_role;
