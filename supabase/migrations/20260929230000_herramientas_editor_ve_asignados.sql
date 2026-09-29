-- Quien mantiene una herramienta ve a quién está asignada.
--
-- ─── Qué estaba roto ─────────────────────────────────────────────────────────
--
-- Reportado el 29/09/2026: la editora del Cotizador abría la herramienta para subir una versión
-- nueva y la lista «Quién la ve» la marcaba sólo a ella, como si nadie más la tuviera. Las
-- asignaciones estaban completas (12 personas en AG117): era la lectura de `herramientas_users`,
-- que para quien no es administrador se limita a su propia fila (`herramientas_users_select_propias`).
--
-- ─── Qué se abre y qué no ────────────────────────────────────────────────────
--
-- Sólo LEER, y sólo las asignaciones de las herramientas que esa persona mantiene
-- (`herramienta_editable_id`, la misma función de las políticas de la tabla y del bucket). Cambiar
-- quién la ve se abre aparte, en la migración siguiente (20260929233000), sólo para la lectura.
--
-- Se AÑADE una política en lugar de tocar la de siempre: las permisivas se suman con OR, así que lo
-- que ya veía cada quien no cambia.
drop policy if exists herramientas_users_select_editor on public.herramientas_users;
create policy herramientas_users_select_editor on public.herramientas_users
  for select to authenticated
  using (public.herramienta_editable_id(herramienta_id));
