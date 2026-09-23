-- Conocimientos: artículos con un archivo HTML que se ve dentro del sistema.
--
-- Pedido del usuario el 23/09/2026: además de PDF, poder subir archivos HTML y que se desplieguen.
--
-- ─── Por qué un bucket aparte, y PRIVADO ───────────────────────────────────
--
-- Los demás adjuntos van a `knowledge-files`, que es PÚBLICO: cualquiera con la dirección los
-- descarga, también los de la pestaña de Administradores. Para un HTML eso no sirve por dos razones:
--
--   * Supabase no lo entrega como página (lo manda como `text/plain` con `sandbox`), así que la
--     dirección pública tampoco lo desplegaría. Lo entrega la Pages Function `functions/c/` a partir
--     de una URL FIRMADA, y firmar exige pasar por la política de lectura de aquí abajo.
--   * Con esa política se puede hacer lo que el bucket público no hace: que el archivo lo lea
--     exactamente quien puede leer el artículo.
--
-- ─── La lectura sigue al artículo ──────────────────────────────────────────
--
-- La ruta es `<id del artículo>/<milisegundos>.html`. La política pregunta si el artículo de esa
-- carpeta existe PARA QUIEN PREGUNTA, y la consulta pasa por la RLS de `knowledge_articles`: los de
-- `audience = 'all'` los ve cualquiera, los de `admin` sólo un administrador. Si mañana cambia esa
-- regla, el archivo la sigue sin tocar esto.
--
-- ─── Quién sube y borra ────────────────────────────────────────────────────
--
-- Quien puede crear y borrar artículos: la misma condición que `knowledge_files_insert` y que las
-- políticas de la tabla. No hay UPDATE: cada versión se sube con un nombre nuevo.
--
-- OJO: esa condición lee `profiles.role`, que hoy cada usuario puede escribirse. Es la misma
-- debilidad que ya tiene la tabla y se cierra en la tarea aparte del 23/09/2026.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('conocimientos-html', 'conocimientos-html', false, 52428800, array['text/html'])
on conflict (id) do update
  set public = false,
      file_size_limit = 52428800,
      allowed_mime_types = array['text/html'];

drop policy if exists conocimientos_html_ver on storage.objects;
create policy conocimientos_html_ver
  on storage.objects for select to authenticated
  using (
    bucket_id = 'conocimientos-html'
    and exists (
      select 1 from public.knowledge_articles a
       where a.id::text = (storage.foldername(name))[1]
    )
  );

drop policy if exists conocimientos_html_subir on storage.objects;
create policy conocimientos_html_subir
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'conocimientos-html'
    and exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin'::user_role)
  );

drop policy if exists conocimientos_html_borrar on storage.objects;
create policy conocimientos_html_borrar
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'conocimientos-html'
    and exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin'::user_role)
  );
