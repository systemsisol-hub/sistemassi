-- Mas caracteristicas de la vivienda, para la plantilla que van a llenar los desarrollos.
--
-- ─── Por que ahora ─────────────────────────────────────────────────────────
--
-- Peticion del usuario el 04/09/2026: los archivos de los ocho desarrollos que faltan llegaron
-- «todos muy diferentes y algunos ni datos tienen», asi que se decidio repartir UNA plantilla con
-- las columnas necesarias.
--
-- La plantilla solo sirve si sus encabezados son los que el lector reconoce. De ahi el orden de
-- este trabajo: primero la columna en la base y el reconocedor en el lector, y solo despues se
-- genera el Excel A PARTIR de los nombres reconocidos. Al contrario, la plantilla prometeria
-- columnas que al pegarse se descartan.
--
-- ─── Que se agrega y que no ────────────────────────────────────────────────
--
-- Solo lo que un cliente pregunta de verdad y que varia POR UNIDAD. Lo que es igual para todo el
-- desarrollo -amenidades, enganche, mensualidades- ya vive en `desarrollos` y repetirlo en cada
-- unidad seria la misma verdad en doscientos sitios.

alter table public.unidades
  -- Niveles de la UNIDAD, no del edificio: una casa de dos pisos, un depto de uno.
  add column if not exists niveles          smallint,
  add column if not exists orientacion      text,
  -- Texto y no booleano: la respuesta real es «SI», «NO» o «SEMIAMUEBLADO».
  add column if not exists amueblado        text,
  -- La cuota mensual de mantenimiento. Se pregunta casi tanto como el precio.
  add column if not exists mantenimiento    numeric(12,2),
  add column if not exists entrega_estimada date,
  -- De un lote: frente y fondo. No se multiplican para sacar el terreno -un lote irregular no es
  -- un rectangulo-, van como los dos datos que son.
  add column if not exists frente           numeric(8,2),
  add column if not exists fondo            numeric(8,2);

comment on column public.unidades.niveles is
  'Niveles de la unidad (una casa de 2 pisos), no del edificio.';
comment on column public.unidades.amueblado is
  'SI / NO / SEMIAMUEBLADO. Texto porque la respuesta real tiene tres estados.';
comment on column public.unidades.mantenimiento is
  'Cuota mensual de mantenimiento de esta unidad.';
comment on column public.unidades.frente is
  'Frente del lote. NO se multiplica por el fondo: un lote irregular no es un rectangulo.';

-- La vista del global tiene que conocer los campos nuevos, o dirian que nadie los usa.
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
         count(u.orientacion)          as c_orientacion,
         count(u.m2_interior_techada)  as c_m2_int,
         count(u.m2_exterior_techada)  as c_m2_ext,
         count(u.m2_jardin_terraza)    as c_m2_jar,
         count(u.m2_superficie)        as c_m2_sup,
         count(u.m2_terreno)           as c_m2_ter,
         count(u.m2_construccion)      as c_m2_con,
         count(u.frente)               as c_frente,
         count(u.fondo)                as c_fondo,
         count(u.recamaras)            as c_rec,
         count(u.banos)                as c_ban,
         count(u.estacionamientos)     as c_est,
         count(u.niveles)              as c_niveles,
         count(u.amueblado)            as c_amueblado,
         count(u.mantenimiento)        as c_mant,
         count(u.entrega_estimada)     as c_entrega,
         count(u.precio)               as c_precio
  from public.desarrollos d
  left join public.unidades u on u.desarrollo_id = d.id
  group by d.id, d.nombre, d.etiquetas
)
select c.desarrollo_id, c.desarrollo, x.campo,
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
  ('orientacion',         c.c_orientacion),
  ('m2_interior_techada', c.c_m2_int),
  ('m2_exterior_techada', c.c_m2_ext),
  ('m2_jardin_terraza',   c.c_m2_jar),
  ('m2_superficie',       c.c_m2_sup),
  ('m2_terreno',          c.c_m2_ter),
  ('m2_construccion',     c.c_m2_con),
  ('frente',              c.c_frente),
  ('fondo',               c.c_fondo),
  ('recamaras',           c.c_rec),
  ('banos',               c.c_ban),
  ('estacionamientos',    c.c_est),
  ('niveles',             c.c_niveles),
  ('amueblado',           c.c_amueblado),
  ('mantenimiento',       c.c_mant),
  ('entrega_estimada',    c.c_entrega),
  ('precio',              c.c_precio)
) as x(campo, llenas);

comment on view public.v_campos_por_desarrollo is
  'Que campos usa cada desarrollo y como los llama. Calculado de las unidades, no guardado.';

alter view public.v_campos_por_desarrollo set (security_invoker = true);
grant select on public.v_campos_por_desarrollo to authenticated;
