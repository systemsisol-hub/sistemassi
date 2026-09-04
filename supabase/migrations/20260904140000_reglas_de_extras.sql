-- Las reglas de qué extras puede comprar quién.
--
-- ─── Por qué son DATOS y no texto en el prompt ──────────────────────────────
--
-- Reglas dictadas por el usuario el 04/09/2026 para AG117:
--
--   * Ningún extra se puede comprar sin departamento. Los extras son roof, bodega y
--     estacionamiento.
--   * Bodega: sólo departamentos arriba de $8,000,000.
--   * Estacionamiento: sólo departamentos arriba de $7,000,000.
--   * Roof garden: sólo con la compra de un departamento.
--
-- Escritas en el prompt, el modelo tendría que comparar «este depto cuesta 9,310,000» contra
-- «arriba de 8,000,000» en cada respuesta. Comparar números es donde un modelo falla, y aquí fallar
-- significa prometerle una bodega a un cliente que no puede comprarla. Así que el umbral es un dato
-- y quién califica se calcula en código.
--
-- ─── Por qué `minimo_inclusivo` existe ─────────────────────────────────────
--
-- «Arriba de 8,000,000» quiere decir estrictamente mayor, así que un departamento de exactamente
-- 8,000,000 NO calificaría. Hoy da igual —medido: ningún departamento de AG117 está exactamente en
-- 7 ni en 8 millones— pero los precios cambian cada mes, y el día que uno caiga justo en el corte
-- la respuesta tiene que estar decidida de antemano y no depender de cómo alguien leyó un
-- comentario. Es una columna para poder cambiarla sin desplegar nada.

create table if not exists public.reglas_extras (
  id             uuid primary key default gen_random_uuid(),
  desarrollo_id  uuid not null references public.desarrollos(id) on delete cascade,

  -- ROOF, BODEGA, ESTACIONAMIENTO. Abierto a proposito: el siguiente desarrollo puede vender otra
  -- cosa -una jaula, un muelle- y no hay razon para que eso pida una migracion.
  extra          text not null,

  -- Si se puede comprar suelto. Los tres de AG117 exigen departamento.
  requiere_departamento boolean not null default true,

  -- El precio minimo del DEPARTAMENTO que da derecho a este extra. NULL = sin minimo.
  precio_minimo_departamento numeric(14,2),

  -- false = «arriba de» (estrictamente mayor). true = «desde» (mayor o igual).
  minimo_inclusivo boolean not null default false,

  notas          text,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),

  constraint reglas_extras_una_por_extra unique (desarrollo_id, extra)
);

comment on table public.reglas_extras is
  'Que extras se pueden comprar y con que departamento. El umbral es dato; quien califica se calcula.';
comment on column public.reglas_extras.minimo_inclusivo is
  'false = «arriba de» (>). true = «desde» (>=). Decidido de antemano para el dia que un precio caiga justo en el corte.';

alter table public.reglas_extras enable row level security;

drop policy if exists reglas_extras_lectura on public.reglas_extras;
create policy reglas_extras_lectura on public.reglas_extras
  for select using (is_admin() or has_permission('show_sol'));

drop policy if exists reglas_extras_escritura on public.reglas_extras;
create policy reglas_extras_escritura on public.reglas_extras
  for all using (is_admin() or has_permission('edit_desarrollos'))
       with check (is_admin() or has_permission('edit_desarrollos'));

-- ── Las tres de AG117 ───────────────────────────────────────────────────────
insert into public.reglas_extras
  (desarrollo_id, extra, requiere_departamento, precio_minimo_departamento,
   minimo_inclusivo, notas)
select d.id, v.extra, true, v.minimo, false, v.notas
from public.desarrollos d, (values
  ('ROOF',            null::numeric, 'Solo con la compra de un departamento. Sin precio minimo.'),
  ('BODEGA',           8000000,      'Solo departamentos arriba de $8,000,000.'),
  ('ESTACIONAMIENTO',  7000000,      'Solo departamentos arriba de $7,000,000.')
) as v(extra, minimo, notas)
where d.nombre = 'AG117'
on conflict (desarrollo_id, extra) do update
  set requiere_departamento      = excluded.requiere_departamento,
      precio_minimo_departamento = excluded.precio_minimo_departamento,
      minimo_inclusivo           = excluded.minimo_inclusivo,
      notas                      = excluded.notas,
      actualizado_en             = now();
