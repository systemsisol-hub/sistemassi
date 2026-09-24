-- Sisol lee el Drive comercial: el texto de los brochures, listas de precios y ubicacion de cada
-- desarrollo, al dia con un boton.
--
-- Pedido del usuario el 24/09/2026. Hasta hoy Sisol usaba `workers/ventas/src/knowledge.ts`: el
-- mismo texto, pero sacado a mano en agosto con dos scripts de Python y metido en el codigo. Un
-- brochure nuevo no existia para Sisol hasta que alguien corria los scripts y volvia a desplegar.
--
-- Es el mismo lector que SOL (`drive-sync`, ver 20260923235900_sol_lee_el_drive.sql), con dos
-- diferencias a proposito:
--
--   * Tablas APARTE. Sisol no comparte catalogo con SOL (decidido el 24/09/2026) y lee otra cosa.
--   * SOLO brochures, listas de precios y ubicacion. Sisol le habla a CLIENTES, y el Drive tiene
--     cuentas bancarias, formatos de bancos e Infonavit, KYC, cartas oferta y estudios de mercado.
--     Decision del usuario: nada de eso. La funcion ni siquiera entra a esas carpetas.
--
-- La carpeta raiz es la del Drive comercial completo (region → desarrollo → carpetas numeradas); la
-- funcion ubica cada desarrollo por el nombre de su carpeta.

-- ─── 1. Lo que se leyo ─────────────────────────────────────────────────────
create table if not exists public.ventas_drive_archivos (
  id               text primary key,
  -- El desarrollo del catalogo de Ventas al que pertenece la carpeta. NULL = una carpeta de
  -- desarrollo que no esta en el catalogo, o el material general de SI SOL.
  desarrollo_id    uuid references public.ventas_desarrollos(id) on delete set null,
  -- Como se llama la carpeta del desarrollo en el Drive, sin el emoji: «BONANZA COTO 4 - ÁGATA».
  -- Dos carpetas pueden caer en el mismo desarrollo del catalogo (Jade y Ágata son Bonanza).
  carpeta          text not null,
  -- BROCHURE, PRECIOS o UBICACION: la carpeta numerada de la que sale.
  categoria        text not null check (categoria in ('BROCHURE', 'PRECIOS', 'UBICACION')),
  ruta             text not null default '',
  nombre           text not null,
  enlace           text not null,
  modificado       text,
  tamano           bigint,
  estado           text not null check (estado in ('PENDIENTE', 'LEYENDO', 'LEIDO', 'SIN_TEXTO', 'NO_SE_LEE', 'ERROR')),
  error            text,
  paginas          integer,
  pagina_siguiente integer,
  intentos         integer not null default 0,
  texto            text check (texto is null or length(texto) <= 400000),
  leido_en         timestamptz,
  visto_en         timestamptz not null default now()
);

create index if not exists ventas_drive_pendientes on public.ventas_drive_archivos (estado)
  where estado in ('PENDIENTE', 'LEYENDO');

comment on table public.ventas_drive_archivos is
  'Brochures, listas de precios y ubicacion del Drive comercial que lee Sisol. Solo escribe la funcion ventas-drive-sync.';

-- ─── 2. Cada vez que se recorre ────────────────────────────────────────────
create table if not exists public.ventas_drive_sincronizaciones (
  id            uuid primary key default gen_random_uuid(),
  pedida_por    uuid references public.profiles(id) on delete set null,
  iniciada_en   timestamptz not null default now(),
  terminada_en  timestamptz,
  carpetas      integer,
  archivos      integer,
  nuevos        integer,
  cambiados     integer,
  quitados      integer,
  -- Carpetas de desarrollo que no se pudieron ligar al catalogo: se leen igual, pero conviene
  -- darlas de alta para que el chat las reconozca y muestre su tarjeta.
  sin_catalogo  text[],
  error         text
);

-- ─── 3. Lo que ve el Worker ────────────────────────────────────────────────
--
-- El texto ya limpio y recortado, para no bajar 400 000 caracteres por documento en cada mensaje:
-- 6 000 por documento, lo mismo que usaba el script anterior. Sin correos ni telefonos: Sisol solo
-- da el contacto oficial, nunca el de un brochure.
create or replace view public.v_ventas_drive_conocimiento
with (security_invoker = true) as
select a.id,
       coalesce(d.nombre, a.carpeta) as desarrollo,
       a.carpeta,
       a.categoria,
       a.nombre,
       left(
         regexp_replace(
           regexp_replace(a.texto, '\S+@\S+\.\S+', ' ', 'g'),
           '\m\d{2,4}[ -]\d{3,4}[ -]\d{3,4}\M', ' ', 'g'),
         6000) as texto
  from public.ventas_drive_archivos a
  left join public.ventas_desarrollos d on d.id = a.desarrollo_id
 where a.estado = 'LEIDO' and a.texto is not null
   and (d.id is null or d.is_active);

-- ─── Quien puede ───────────────────────────────────────────────────────────
alter table public.ventas_drive_archivos enable row level security;
alter table public.ventas_drive_sincronizaciones enable row level security;

drop policy if exists ventas_drive_archivos_lectura on public.ventas_drive_archivos;
create policy ventas_drive_archivos_lectura on public.ventas_drive_archivos
  for select to authenticated using (is_admin() or has_permission('show_ventas'));

drop policy if exists ventas_drive_sincronizaciones_lectura on public.ventas_drive_sincronizaciones;
create policy ventas_drive_sincronizaciones_lectura on public.ventas_drive_sincronizaciones
  for select to authenticated using (is_admin() or has_permission('show_ventas'));

-- Sin politicas de escritura y ademas sin permisos: escribe solo la funcion, con la llave de servicio.
revoke insert, update, delete on public.ventas_drive_archivos from anon, authenticated;
revoke insert, update, delete on public.ventas_drive_sincronizaciones from anon, authenticated;
revoke all on public.ventas_drive_archivos from anon;
revoke all on public.ventas_drive_sincronizaciones from anon;
revoke all on public.v_ventas_drive_conocimiento from anon, authenticated;
grant select on public.v_ventas_drive_conocimiento to service_role;
