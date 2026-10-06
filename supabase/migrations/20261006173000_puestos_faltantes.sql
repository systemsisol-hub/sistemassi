-- Los tres puestos que tenían colaboradores y no venían en la lista del 06/10/2026. El usuario
-- pidió dejarlos como están y agregarlos al catálogo, no cambiarlos por sus parecidos.
insert into public.puestos (nombre, created_by) values
  ('COMPRAS', null), ('DIRECTOR DE PROYECTOS', null), ('GERENTE DE POSTVENTA', null)
on conflict (nombre) do nothing;
