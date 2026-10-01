-- Paso 2 de 2: una sesion normal ya no puede leer de `profiles` las columnas sensibles.
--
-- Hasta hoy `authenticated` tenia SELECT en todas las columnas y `profiles_select_auth` es
-- `USING (true)`: cualquier sesion bajaba contraseñas en claro, CLABE, CURP y datos de salud de los
-- 2,508 perfiles pidiendolos directo a la API (revision del 01/10/2026,
-- docs/revision-seguridad-credenciales.md).
--
-- Los renglones se siguen viendo (Social, Directorio, buscadores y selectores de personas los
-- necesitan), pero solo con las columnas de abajo. Lo sensible se lee por las vistas de la migracion
-- 20261001200000: `perfiles_completos` (el propio perfil, o todos para admin / show_users / show_cssi)
-- y `nomina_perfiles` (admin / show_tablas). La app dejo de pedirlo a `profiles` en la version
-- publicada el 01/10/2026 (22841a2).
--
-- Decisiones del usuario (01/10/2026): nombres y correos visibles para todos; telefono y celular
-- solo para administradores (el Directorio ya los filtra); la fecha de nacimiento sigue visible por
-- los cumpleaños de Social.
--
-- No cambia: INSERT/UPDATE/DELETE (las rige RLS y el trigger tr_0_proteger_perfil), la llave de
-- servicio de las Edge Functions, ni las vistas, que corren con los permisos de su dueño.
--
-- OJO al agregar una columna a `profiles`: `authenticated` NO la podra leer hasta agregarla aqui
-- (si no es sensible) o leerla por `perfiles_completos`.

revoke select on public.profiles from authenticated, anon;

grant select (
  id, full_name, role, created_at, numero_empleado, is_blocked, permissions, email, status_sys,
  nombre, paterno, materno, fecha_nacimiento, empresa_tipo, area, puesto, ubicacion, empresa,
  jefe_inmediato, lider, gerente_regional, director, fecha_ingreso, fecha_reingreso, fecha_cambio,
  foto_url, status_rh, updated_at, has_auth_account, work_start_time, work_end_time, schedule_id,
  mail_user, horario, fecha_baja
) on public.profiles to authenticated;
