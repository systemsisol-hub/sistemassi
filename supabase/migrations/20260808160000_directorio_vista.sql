-- El Directorio pasa a leer una vista: sin número de empleado, y con los teléfonos sólo para
-- administradores.
--
-- ─── Por qué una vista y no un `if` en la pantalla ───────────────────────────
--
-- Esconder los teléfonos en Dart no los esconde: la consulta los seguiría trayendo y cualquiera con
-- la sesión abierta los leería desde la API. La regla tiene que estar donde se sirven los datos.
--
-- `security_invoker = true` para que la vista no se salte la RLS de `profiles`; el enmascarado no lo
-- hace la RLS —que trabaja por renglón, no por columna— sino el CASE de cada teléfono.
--
-- ⚠️ ALCANCE HONESTO DE ESTE CAMBIO. La política de lectura de `profiles` es literalmente `true`, así
-- que un usuario normal puede consultar `profiles.telefono` directo y obtener los 2 252 teléfonos
-- capturados —y también las 1 140 contraseñas de correo que guarda esa tabla—. Esta vista cierra el
-- camino del Directorio y deja la regla en el lugar correcto, pero NO cierra ese hueco: hacerlo
-- obliga a sacar de `profiles` las columnas sensibles y servirlas por vistas, y eso toca el panel de
-- cada usuario, el generador de firmas y las páginas de Colaborador. Queda documentado aquí para que
-- nadie lea esta vista como una garantía que no da.

DROP VIEW IF EXISTS directorio;

CREATE VIEW directorio
WITH (security_invoker = true) AS
SELECT
  p.id,
  -- El nombre se sigue armando en la pantalla con los componentes: 24 perfiles tienen `full_name`
  -- desfasado, así que se exponen los cuatro campos y no una concatenación ya hecha.
  p.nombre,
  p.paterno,
  p.materno,
  p.full_name,
  p.puesto,
  p.area,
  p.ubicacion,
  p.empresa,

  -- Los teléfonos, sólo para quien administra. Para el resto llegan en NULL, y la tarjeta ya sabe no
  -- pintar un contacto vacío.
  CASE WHEN is_admin() THEN p.telefono END AS telefono,
  CASE WHEN is_admin() THEN p.celular  END AS celular,

  -- El correo de trabajo se queda para todos: es lo que se pidió que el directorio sirviera.
  p.mail_user,
  p.email,
  p.foto_url
FROM profiles p
-- Mismo criterio que traía la pantalla, ahora en un solo lugar: personal vigente por las DOS señales
-- a la vez. De los 2 488 registros, 2 192 son bajas; con todos, el directorio sería 88% de
-- exempleados y publicaría el celular de quien ya no trabaja aquí.
WHERE p.status_rh IN ('ACTIVO', 'CAMBIO', 'REINGRESO')
  AND p.fecha_baja IS NULL;

COMMENT ON VIEW directorio IS
  'Directorio interno de personal vigente. No expone numero_empleado. Los teléfonos sólo se devuelven a administradores; para el resto llegan en NULL. No sustituye una restricción sobre profiles: esa tabla sigue siendo legible por cualquier autenticado.';

GRANT SELECT ON directorio TO authenticated;
