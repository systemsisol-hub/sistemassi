-- Inventario de unidades por desarrollo.
--
-- ─── Por que existe ─────────────────────────────────────────────────────────
--
-- `desarrollos` guarda `precio_desde`, `precio_hasta`, `superficie_desde` y `superficie_hasta` como
-- cuatro numeros escritos a mano, y los diez desarrollos los tienen en NULL. Por eso SOL no pudo
-- contestar cuando le pidieron la lista de precios de Zenesis Club: no habia de donde. Con las
-- unidades cargadas esos cuatro numeros se calculan, y dejan de poder mentir.
--
-- ─── Que se guarda y que no ─────────────────────────────────────────────────
--
-- El archivo de AG117 trae 13 columnas, pero solo 11 son datos:
--
--   TOTAL INTERIOR M2 = interior techada + exterior techada   (38 de 38 filas cuadran)
--   M2 TOTAL          = TOTAL INTERIOR + jardin/terraza        (38 de 38 filas cuadran)
--
-- Guardarlas seria tener el mismo hecho en dos lugares, y tarde o temprano una fila queda con un
-- total que no corresponde a sus partes. Van como columnas generadas, que Postgres recalcula solo.
-- `precio_m2` se agrega por lo mismo: se pide mucho y nadie deberia teclearlo.
--
-- ─── La llave ───────────────────────────────────────────────────────────────
--
-- Es `numero` -AG004, AG006...-, unico en las 38 filas. NO es `# Depto`: las cuatro azoteas dicen
-- todas «ROOF», asi que como llave chocarian entre si.

create table if not exists public.unidades (
  id                    uuid primary key default gen_random_uuid(),
  desarrollo_id         uuid not null references public.desarrollos(id) on delete cascade,

  -- Identificacion
  numero                text not null,
  depto                 text,
  torre                 text,
  nivel                 text,
  tipo                  text,
  tipologia             text,
  vista                 text,

  -- Superficies, tal como vienen. Dos decimales: el Excel arrastra ruido de coma flotante
  -- -113.72999999999999 por 113.73- y guardarlo asi hace que las sumas se vean sucias.
  m2_interior_techada   numeric(10,2),
  m2_exterior_techada   numeric(10,2),
  m2_jardin_terraza     numeric(10,2),

  -- Y las que son cuentas. Una columna generada no se puede apoyar en otra generada, asi que
  -- `m2_total` repite la suma completa en lugar de reusar `m2_total_interior`.
  m2_total_interior     numeric(10,2) generated always as (
                          coalesce(m2_interior_techada, 0) + coalesce(m2_exterior_techada, 0)
                        ) stored,
  m2_total              numeric(10,2) generated always as (
                          coalesce(m2_interior_techada, 0) + coalesce(m2_exterior_techada, 0)
                          + coalesce(m2_jardin_terraza, 0)
                        ) stored,

  precio                numeric(14,2),
  moneda                text not null default 'MXN',

  precio_m2             numeric(14,2) generated always as (
                          case
                            when precio is null then null
                            when (coalesce(m2_interior_techada, 0) + coalesce(m2_exterior_techada, 0)
                                  + coalesce(m2_jardin_terraza, 0)) = 0 then null
                            else round(precio / (coalesce(m2_interior_techada, 0)
                                 + coalesce(m2_exterior_techada, 0)
                                 + coalesce(m2_jardin_terraza, 0)), 2)
                          end
                        ) stored,

  -- DISPONIBLE / APARTADO / VENDIDO son los tres que alguien declara a proposito.
  --
  -- NO_DISPONIBLE es distinto y hace falta: la lista mensual SOLO trae las disponibles, asi que
  -- cuando una unidad desaparece sabemos que ya no se vende pero NO sabemos si se aparto o se
  -- vendio. Inventar cual de las dos seria escribir un dato que nadie dijo.
  estatus               text not null default 'DISPONIBLE'
                          check (estatus in ('DISPONIBLE','APARTADO','VENDIDO','NO_DISPONIBLE')),

  -- De que lista salio el dato. El archivo se llama «SEPTIEMBRE 1» y el precio viene marcado
  -- «(Manual)»: sin esta fecha, un precio de hace cinco meses se ve igual que uno de ayer.
  lista_al              date,

  notas                 text,
  created_at            timestamptz not null default now(),
  actualizado_en        timestamptz not null default now(),
  actualizado_por       uuid references auth.users(id),

  constraint unidades_numero_por_desarrollo unique (desarrollo_id, numero)
);

create index if not exists unidades_desarrollo_idx on public.unidades (desarrollo_id);
-- El indice parcial es el que sirve: casi toda consulta de SOL filtra por disponibles.
create index if not exists unidades_disponibles_idx on public.unidades (desarrollo_id, precio)
  where estatus = 'DISPONIBLE';

comment on table public.unidades is
  'Inventario de unidades por desarrollo. Los m2 totales y el precio por m2 son columnas generadas.';

-- ─── Resumen por desarrollo ─────────────────────────────────────────────────
--
-- Una sola definicion para los dos consumidores -el panel y SOL-. Si cada uno lo calculara por su
-- lado, terminarian dando numeros distintos, que es el error que mas ha costado en este proyecto.
--
-- Solo cuenta las DISPONIBLES: «desde $4,950,000» debe referirse a algo que se puede comprar hoy.

create or replace view public.v_desarrollo_inventario as
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

comment on view public.v_desarrollo_inventario is
  'Rangos de precio y superficie calculados del inventario disponible. Unica fuente para el panel y SOL.';

-- ─── Permisos ───────────────────────────────────────────────────────────────
--
-- El mismo criterio que `desarrollos`, `documentos` y `promociones`: leer con `show_sol`, escribir
-- con `edit_desarrollos`.

alter table public.unidades enable row level security;

drop policy if exists unidades_lectura on public.unidades;
create policy unidades_lectura on public.unidades
  for select using (is_admin() or has_permission('show_sol'));

drop policy if exists unidades_escritura on public.unidades;
create policy unidades_escritura on public.unidades
  for all using (is_admin() or has_permission('edit_desarrollos'))
       with check (is_admin() or has_permission('edit_desarrollos'));

-- La vista hereda el RLS de `unidades` porque no es SECURITY DEFINER: quien no pueda leer la tabla
-- ve renglones vacios, no los numeros.
alter view public.v_desarrollo_inventario set (security_invoker = true);
grant select on public.v_desarrollo_inventario to authenticated;

-- ─── `actualizado_en` al dia ────────────────────────────────────────────────

create or replace function public.unidades_toca_actualizado()
returns trigger language plpgsql as $$
begin
  new.actualizado_en := now();
  return new;
end;
$$;

drop trigger if exists unidades_actualizado on public.unidades;
create trigger unidades_actualizado before update on public.unidades
  for each row execute function public.unidades_toca_actualizado();
