-- Correspondencia: el cubo de las imagenes del editor.
--
-- Pedido del usuario el 23/09/2026: poder poner imagenes en el cuerpo del comunicado.
--
-- ─── Por que PRIVADO, al contrario que `avisos-imagenes` ───────────────────
--
-- Las imagenes van INCRUSTADAS en el correo: la funcion `correspondencia` las descarga con su llave
-- y las adjunta con `Content-ID`. Nadie de fuera necesita leerlas por una direccion, asi que no hay
-- por que dejarlas publicas. Enlazadas por URL, ademas, Outlook y muchos servidores de empresa las
-- bloquean por defecto.
--
-- La pantalla las ve con URLs FIRMADAS, que caducan, solo mientras se redacta.
--
-- ─── Lo que se acepta ──────────────────────────────────────────────────────
--
-- PNG, JPEG y GIF: lo que la pantalla produce despues de reducir la imagen -reencodea a JPEG o PNG, y
-- deja el GIF como esta para no romper una animacion-. 5 MB, el mismo tope que Avisos; en la
-- practica una imagen reducida pesa unos cientos de KB.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'correspondencia-imagenes',
  'correspondencia-imagenes',
  false,
  5242880,
  array['image/png', 'image/jpeg', 'image/gif']
)
on conflict (id) do update
  set public = false,
      file_size_limit = 5242880,
      allowed_mime_types = array['image/png', 'image/jpeg', 'image/gif'];

-- Subir y ver: solo quienes tienen el permiso del modulo. Ver hace falta para las URLs firmadas con
-- que el editor pinta la imagen mientras se redacta.
--
-- No hay politica de UPDATE ni de DELETE: cada imagen se sube con un nombre nuevo al azar y no se
-- reescribe. Una imagen ya enviada viaja DENTRO del correo, asi que borrarla del cubo no cambiaria lo
-- que recibio nadie.
--
-- OJO: `has_permission` lee de `profiles.permissions`, que hoy cada usuario puede escribirse. Es la
-- misma debilidad del resto del modulo y se cierra en la tarea aparte del 23/09/2026.
drop policy if exists correspondencia_imagenes_subir on storage.objects;
create policy correspondencia_imagenes_subir
  on storage.objects for insert to authenticated
  with check (bucket_id = 'correspondencia-imagenes'
              and public.has_permission('show_correspondencia'));

drop policy if exists correspondencia_imagenes_ver on storage.objects;
create policy correspondencia_imagenes_ver
  on storage.objects for select to authenticated
  using (bucket_id = 'correspondencia-imagenes'
         and public.has_permission('show_correspondencia'));
