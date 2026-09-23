-- Correspondencia: el historial lo leen quienes tienen el permiso, y SOLO ellos.
--
-- ─── Que cambia ─────────────────────────────────────────────────────────────
--
-- Antes: cada quien leia lo suyo, y los administradores todo.
-- Ahora: quien tenga `show_correspondencia` lee TODOS los comunicados; nadie mas.
--
-- Por dos pedidos del usuario el 23/09/2026:
--
--   * «No todos los administradores lo pueden ver». Ser administrador ya no abre ni la pagina ni la
--     funcion, y tampoco tiene que abrir el historial por la puerta de atras.
--   * Todo sale como «Comunicación SI SOL», y quien lo mando se guarda aqui. Con un unico remitente
--     para las tres personas que lo usan, cada una necesita ver lo que ya salio de las otras: si no,
--     acaban mandando dos veces el mismo aviso. Y el registro de «quien lo mando» solo sirve si
--     alguien puede leerlo.
--
-- ─── Lo que no cambia ───────────────────────────────────────────────────────
--
-- Sigue sin haber politicas de INSERT, UPDATE ni DELETE: solo escribe la funcion, con la llave de
-- servicio. El registro sigue sin poderse arreglar a mano.
--
-- OJO: `has_permission` lee de `profiles.permissions`, que hoy cada usuario puede escribirse. Es la
-- MISMA debilidad que ya tienen la pagina y la funcion, y se cierra en la tarea aparte identificada
-- el 23/09/2026, no aqui.

drop policy if exists correspondencia_lee_lo_suyo on public.correspondencia;
drop policy if exists correspondencia_lee_quien_tiene_permiso on public.correspondencia;

create policy correspondencia_lee_quien_tiene_permiso on public.correspondencia
  for select to authenticated
  using (public.has_permission('show_correspondencia'));
