-- Un juego GLOBAL de campos, con el nombre que cada desarrollo les da.
--
-- ─── El problema que resuelve ───────────────────────────────────────────────
--
-- Peticion del usuario el 03/09/2026, y la dijo mejor de lo que yo la tenia pensada:
--
--   «en ag117 torre seria edificio en vidamar»
--
-- O sea: NO son dos campos, es el MISMO campo con dos nombres. Antes de esto, la unica salida
-- habria sido crear una columna por cada nombre que apareciera —torre, edificio, bloque...— y
-- acabar con quince columnas que significan lo mismo y ninguna llena.
--
-- Asi que el campo es uno y el NOMBRE es un dato del desarrollo. Y el nombre no hay que teclearlo:
-- sale del encabezado del Excel que se pega, que es donde ya viene escrito.
--
-- ─── Y los campos que todavia no tienen casa ───────────────────────────────
--
-- Se agregan los que ya sabemos que hacen falta, y se REGISTRAN los que aparezcan sin sitio, para
-- que la siguiente lista se decida con datos en lugar de adivinando. Es lo que pidio el usuario:
-- «ir viendo un global».

-- ── Campos nuevos de la unidad ──────────────────────────────────────────────
--
-- Terreno y construccion NO entran en `m2_total`. Una casa de 160 m2 de terreno y 142 de
-- construccion no es una casa de 302: son dos superficies distintas y sumarlas es un error, no una
-- simplificacion. `m2_total` sigue siendo la superficie vendible de un departamento —capturada de
-- un solo numero o sumada del desglose—; cuando llegue la primera lista de casas real se decide,
-- con esa lista delante, cual de las dos es la que se compara.
alter table public.unidades
  add column if not exists m2_terreno       numeric(10,2),
  add column if not exists m2_construccion  numeric(10,2),
  add column if not exists recamaras        smallint,
  -- Con decimal a proposito: «2.5 banos» es como se anuncia de verdad.
  add column if not exists banos            numeric(4,1),
  add column if not exists estacionamientos smallint;

comment on column public.unidades.m2_terreno is
  'Superficie de terreno. NO se suma a la de construccion: son dos cosas distintas.';
comment on column public.unidades.m2_construccion is
  'Superficie construida. NO entra en m2_total mientras no haya una lista de casas real que lo defina.';

-- ── Como llama cada desarrollo a cada campo ─────────────────────────────────
--
-- `{"torre": "Edificio", "sector": "Cluster"}` para Vidamar; `{}` para AG117, que usa los nombres
-- por omision. Lo escribe la carga del Excel a partir de su encabezado: el nombre ya viene escrito
-- ahi y pedirle al usuario que lo teclee otra vez seria pedirle un dato que ya nos dio.
alter table public.desarrollos
  add column if not exists etiquetas jsonb not null default '{}'::jsonb;

comment on column public.desarrollos.etiquetas is
  'Como llama ESTE desarrollo a cada campo de la unidad. Se aprende del encabezado del Excel.';

-- ── Las columnas que aparecieron y no tienen campo ─────────────────────────
--
-- En lugar de crear columnas a ciegas por si acaso, se guarda lo que de verdad aparece. Cada lista
-- que se pegue deja constancia de sus columnas huerfanas, con un ejemplo del valor y cuantas veces
-- se han visto. Cuando una se repita en varios desarrollos, se crea con evidencia y no por
-- corazonada.
create table if not exists public.columnas_sin_mapear (
  id             uuid primary key default gen_random_uuid(),
  desarrollo_id  uuid not null references public.desarrollos(id) on delete cascade,
  columna        text not null,
  ejemplo        text,
  veces          integer not null default 1,
  primera_vez    timestamptz not null default now(),
  ultima_vez     timestamptz not null default now(),
  constraint columnas_sin_mapear_unica unique (desarrollo_id, columna)
);

comment on table public.columnas_sin_mapear is
  'Columnas de Excel que aparecieron sin campo donde guardarse. Sirven para decidir con datos que campo crear.';

alter table public.columnas_sin_mapear enable row level security;

drop policy if exists columnas_sin_mapear_lectura on public.columnas_sin_mapear;
create policy columnas_sin_mapear_lectura on public.columnas_sin_mapear
  for select using (is_admin() or has_permission('show_sol'));

drop policy if exists columnas_sin_mapear_escritura on public.columnas_sin_mapear;
create policy columnas_sin_mapear_escritura on public.columnas_sin_mapear
  for all using (is_admin() or has_permission('edit_desarrollos'))
       with check (is_admin() or has_permission('edit_desarrollos'));

-- ── El global: que campo usa cada desarrollo, y como lo llama ──────────────
--
-- CALCULADO, no guardado. Cuenta cuantas unidades tienen cada campo lleno, asi que no puede
-- mentir: si dice que Vidamar usa `sector` es porque hay unidades con sector.
-- Primero se CUENTA por desarrollo y despues se despivota. Un `count()` no puede vivir dentro del
-- `values` de un lateral, asi que el orden importa.
create or replace view public.v_campos_por_desarrollo as
with conteos as (
  select d.id as desarrollo_id, d.nombre as desarrollo, d.etiquetas,
         count(u.id)                   as total,
         count(u.sector)               as c_sector,
         count(u.torre)                as c_torre,
         count(u.nivel)                as c_nivel,
         count(u.depto)                as c_depto,
         count(u.tipo)                 as c_tipo,
         count(u.tipologia)            as c_tipologia,
         count(u.vista)                as c_vista,
         count(u.m2_interior_techada)  as c_m2_int,
         count(u.m2_exterior_techada)  as c_m2_ext,
         count(u.m2_jardin_terraza)    as c_m2_jar,
         count(u.m2_superficie)        as c_m2_sup,
         count(u.m2_terreno)           as c_m2_ter,
         count(u.m2_construccion)      as c_m2_con,
         count(u.recamaras)            as c_rec,
         count(u.banos)                as c_ban,
         count(u.estacionamientos)     as c_est,
         count(u.precio)               as c_precio
  from public.desarrollos d
  left join public.unidades u on u.desarrollo_id = d.id
  group by d.id, d.nombre, d.etiquetas
)
select c.desarrollo_id, c.desarrollo, x.campo,
       -- Con el nombre que le da ESTE desarrollo, o el canonico si no le puso otro.
       coalesce(c.etiquetas ->> x.campo, x.campo) as se_llama,
       x.llenas, c.total,
       (x.llenas > 0) as lo_usa
from conteos c
cross join lateral (values
  ('sector',              c.c_sector),
  ('torre',               c.c_torre),
  ('nivel',               c.c_nivel),
  ('depto',               c.c_depto),
  ('tipo',                c.c_tipo),
  ('tipologia',           c.c_tipologia),
  ('vista',               c.c_vista),
  ('m2_interior_techada', c.c_m2_int),
  ('m2_exterior_techada', c.c_m2_ext),
  ('m2_jardin_terraza',   c.c_m2_jar),
  ('m2_superficie',       c.c_m2_sup),
  ('m2_terreno',          c.c_m2_ter),
  ('m2_construccion',     c.c_m2_con),
  ('recamaras',           c.c_rec),
  ('banos',               c.c_ban),
  ('estacionamientos',    c.c_est),
  ('precio',              c.c_precio)
) as x(campo, llenas);

comment on view public.v_campos_por_desarrollo is
  'Que campos usa cada desarrollo y como los llama. Calculado de las unidades, no guardado.';

alter view public.v_campos_por_desarrollo set (security_invoker = true);
grant select on public.v_campos_por_desarrollo to authenticated;
