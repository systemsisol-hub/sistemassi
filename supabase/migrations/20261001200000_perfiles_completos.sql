-- Paso 1 de 2 para dejar de exponer los datos sensibles de `profiles` (revision del 01/10/2026,
-- docs/revision-seguridad-credenciales.md). Este paso solo AGREGA; no le quita nada a nadie.
--
-- Hoy `profiles_select_auth` es `USING (true)` y `authenticated` tiene SELECT en todas las columnas:
-- cualquier sesion lee contraseñas, CLABE, CURP y salud de los 2,508 perfiles. El paso 2 le quita a
-- `authenticated` esas columnas de `profiles`. Antes, la app tiene que leerlas por aqui:
--
--   * `perfiles_completos`: todas las columnas, solo del propio perfil o de todos para quien
--     administra usuarios o expedientes (admin, `show_users`, `show_cssi`). Lo usan Mi Perfil, Firmas,
--     la ficha propia de Incidencias, Usuarios y Colaboradores.
--   * `nomina_perfiles`: lo que muestra la tabla de nomina en Tablas (banco, cuenta, CLABE), para quien
--     tiene `show_tablas`. Sin contraseñas ni datos de salud.
--
-- Las dos corren con los permisos de su dueño (como cualquier vista sin `security_invoker`): asi siguen
-- leyendo las columnas que el paso 2 le quita a `authenticated`. El filtro de renglones lo hacen ellas,
-- con `is_admin()` (token) y `has_permission()` (que ya no se puede auto-asignar: migracion
-- 20261001150000_perfil_sin_autoescalada).

create or replace view public.perfiles_completos
with (security_barrier = true)
as
select p.*
  from public.profiles p
 where p.id = auth.uid()
    or coalesce(public.is_admin(), false)
    or public.has_permission('show_users')
    or public.has_permission('show_cssi');

comment on view public.perfiles_completos is
  'Perfil con todas las columnas: el propio, o todos para admin / show_users / show_cssi. Ver migracion 20261001200000.';

create or replace view public.nomina_perfiles
with (security_barrier = true)
as
select p.id, p.nombre, p.paterno, p.materno, p.numero_empleado, p.fecha_ingreso, p.mail_user,
       p.ubicacion, p.banco, p.cuenta, p.clabe, p.puesto, p.status_rh
  from public.profiles p
 where coalesce(public.is_admin(), false)
    or public.has_permission('show_tablas');

comment on view public.nomina_perfiles is
  'Columnas de la tabla de nomina (Tablas), para admin / show_tablas. Ver migracion 20261001200000.';

revoke all on public.perfiles_completos from anon;
revoke all on public.nomina_perfiles from anon;
grant select on public.perfiles_completos to authenticated;
grant select on public.nomina_perfiles to authenticated;

-- El Directorio ya filtraba sus columnas (telefono y celular solo para admin), pero corria con los
-- permisos de quien consulta: con el paso 2 dejaria de poder leer telefono y celular incluso para el
-- administrador. Pasa a correr con los de su dueño; lo que muestra no cambia.
alter view public.directorio set (security_invoker = false);
