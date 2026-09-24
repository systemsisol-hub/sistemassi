-- Reemplazar el inventario de un desarrollo de Ventas en UNA transaccion.
--
-- La pagina carga el inventario pegando el Excel del mes, que sustituye todas las unidades del
-- desarrollo. Hecho desde la app como «borrar» y luego «insertar», un fallo entre las dos (una
-- celda que la base rechaza, la red que se cae) dejaria el desarrollo SIN inventario, y Sisol le
-- diria a un cliente que no hay nada disponible. Aqui o entran todas o no cambia nada.
--
-- `security invoker`: corre con los permisos de quien la llama, asi que la RLS de
-- ventas_unidades (edit_ventas) sigue decidiendo quien puede.

create or replace function public.ventas_reemplazar_inventario(p_desarrollo uuid, p_filas jsonb)
returns integer
language plpgsql
security invoker
set search_path to 'public'
as $$
declare
  n integer;
begin
  delete from ventas_unidades where desarrollo_id = p_desarrollo;

  insert into ventas_unidades
    (desarrollo_id, tipo, nivel, numero, area_int, area_ext, area_total,
     precio_mxn, precio_usd, fecha_escritura, estatus, orden)
  select p_desarrollo,
         f ->> 'tipo', f ->> 'nivel', f ->> 'numero',
         (f ->> 'area_int')::numeric, (f ->> 'area_ext')::numeric, (f ->> 'area_total')::numeric,
         (f ->> 'precio_mxn')::numeric, (f ->> 'precio_usd')::numeric,
         f ->> 'fecha_escritura',
         coalesce(f ->> 'estatus', 'DISPONIBLE'),
         i::integer
  from jsonb_array_elements(p_filas) with ordinality as t(f, i);

  get diagnostics n = row_count;
  return n;
end;
$$;

revoke execute on function public.ventas_reemplazar_inventario(uuid, jsonb) from public, anon;
grant execute on function public.ventas_reemplazar_inventario(uuid, jsonb) to authenticated;
