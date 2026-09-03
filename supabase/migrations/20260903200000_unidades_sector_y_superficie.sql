-- Las listas de inventario NO tienen la misma forma. Dos campos nuevos y dos redefiniciones.
--
-- ─── Lo que obligo el cambio ────────────────────────────────────────────────
--
-- La lista de VIDAMAR, real, del 03/09/2026:
--
--   CLUSTER | EDIFICIO | DEPTO. | NIVEL | SUP. M2 | PRECIO | ESTATUS
--
-- Frente a la de AG117, que fue con la que se diseño la tabla:
--
--   Torre | Nivel | Tipo | Tipologia | # Depto | Numero | Vista |
--   AREA INTERIOR TECHADA | AREA EXTERIOR TECHADA | JARDIN TERRAZA | ... | Precio
--
-- Dos diferencias de fondo:
--
--   1. CLUSTER es una agrupacion POR ENCIMA del edificio, y no habia donde ponerla. Y no es solo
--      que se perderia el dato: sin ella la clave de Vidamar no puede ser unica. Medido sobre sus
--      17 filas, `DEPTO.` solo da 7 claves distintas y EDIFICIO + DEPTO. da 14. Hacen falta las
--      tres.
--   2. AG117 trae la superficie DESGLOSADA en tres columnas y la base las suma; Vidamar trae un
--      solo numero. Meter 155 en `m2_interior_techada` habria sido etiquetarlo mal: no es la
--      superficie interior techada, es la superficie.

alter table public.unidades
  add column if not exists sector text,
  add column if not exists m2_superficie numeric(10,2);

comment on column public.unidades.sector is
  'La agrupacion por encima del edificio: cluster, coto, seccion, manzana.';
comment on column public.unidades.m2_superficie is
  'La superficie cuando la lista da un solo numero, sin desglose. `m2_total` la prefiere.';

-- ─── Los totales siguen siendo CALCULADOS, sea cual sea la forma ────────────
--
-- Una columna generada no se puede alterar: hay que tirarla y volverla a crear. El dato no se
-- pierde porque nunca estuvo guardado —se recalcula solo—.
--
-- `m2_total` prefiere `m2_superficie` y cae al desglose si no viene. Asi el total NUNCA se teclea,
-- ni en una lista ni en la otra, que es la regla que ha sostenido esta tabla desde el principio.

-- La vista se tira ANTES que las columnas: depende de `m2_total`, y Postgres se niega a tirar una
-- columna de la que cuelga una vista. Se recrea abajo, con la misma definicion.
drop view if exists public.v_desarrollo_inventario;

alter table public.unidades drop column if exists precio_m2;
alter table public.unidades drop column if exists m2_total;
alter table public.unidades drop column if exists m2_total_interior;

alter table public.unidades
  add column m2_total_interior numeric(10,2) generated always as (
    -- NULL y no 0 cuando la lista no desglosa: un 0 diria que la unidad no tiene interior, que es
    -- falso; lo cierto es que no lo sabemos.
    case
      when m2_interior_techada is null and m2_exterior_techada is null then null
      else coalesce(m2_interior_techada, 0) + coalesce(m2_exterior_techada, 0)
    end
  ) stored;

alter table public.unidades
  add column m2_total numeric(10,2) generated always as (
    coalesce(
      m2_superficie,
      case
        when m2_interior_techada is null and m2_exterior_techada is null
             and m2_jardin_terraza is null then null
        else coalesce(m2_interior_techada, 0) + coalesce(m2_exterior_techada, 0)
             + coalesce(m2_jardin_terraza, 0)
      end
    )
  ) stored;

alter table public.unidades
  add column precio_m2 numeric(14,2) generated always as (
    case
      when precio is null then null
      when coalesce(
             m2_superficie,
             coalesce(m2_interior_techada, 0) + coalesce(m2_exterior_techada, 0)
             + coalesce(m2_jardin_terraza, 0)
           ) is null then null
      when coalesce(
             m2_superficie,
             coalesce(m2_interior_techada, 0) + coalesce(m2_exterior_techada, 0)
             + coalesce(m2_jardin_terraza, 0)
           ) = 0 then null
      else round(precio / coalesce(
             m2_superficie,
             coalesce(m2_interior_techada, 0) + coalesce(m2_exterior_techada, 0)
             + coalesce(m2_jardin_terraza, 0)
           ), 2)
    end
  ) stored;

-- Y se vuelve a crear, con la MISMA definicion que tenia.
create view public.v_desarrollo_inventario as
select
  d.id                                    as desarrollo_id,
  d.nombre                                as desarrollo,
  count(u.id)                             as unidades_totales,
  count(u.id) filter (where u.estatus = 'DISPONIBLE') as disponibles,
  count(u.id) filter (where u.estatus = 'APARTADO')   as apartadas,
  count(u.id) filter (where u.estatus = 'VENDIDO')    as vendidas,
  min(u.precio)    filter (where u.estatus = 'DISPONIBLE') as precio_desde,
  max(u.precio)    filter (where u.estatus = 'DISPONIBLE') as precio_hasta,
  min(u.m2_total)  filter (where u.estatus = 'DISPONIBLE') as m2_desde,
  max(u.m2_total)  filter (where u.estatus = 'DISPONIBLE') as m2_hasta,
  max(u.lista_al)                         as lista_al
from public.desarrollos d
left join public.unidades u on u.desarrollo_id = d.id
group by d.id, d.nombre;

alter view public.v_desarrollo_inventario set (security_invoker = true);
grant select on public.v_desarrollo_inventario to authenticated;
