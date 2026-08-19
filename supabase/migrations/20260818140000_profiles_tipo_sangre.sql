-- Tipo de sangre en el expediente del colaborador, después del IMSS.
--
-- ─── Por qué con restricción y no texto libre ────────────────────────────────
--
-- Es un dato que se consulta en una urgencia, y ahí un valor mal capturado es peor que un hueco: un
-- hueco hace preguntar, y un «0+» hace actuar. Y ése es justamente el error clásico de este campo —el
-- CERO en lugar de la letra O— junto con «o positivo», «O +», «orh+» y demás variantes que luego no se
-- pueden agrupar ni buscar.
--
-- La restricción admite los ocho grupos del sistema ABO/Rh y nada más. El formulario usa un desplegable
-- con esos mismos ocho, así que la restricción no debería dispararse nunca desde la aplicación: está
-- para lo que entre por otra vía —una carga masiva, una corrección a mano en el editor SQL—.
--
-- Se admite NULL a propósito: hoy no hay ni un dato capturado, y obligar el campo bloquearía guardar
-- cualquier otro cambio de los 2488 expedientes existentes.

alter table public.profiles
  add column if not exists tipo_sangre text;

alter table public.profiles
  drop constraint if exists profiles_tipo_sangre_check;

alter table public.profiles
  add constraint profiles_tipo_sangre_check
  check (tipo_sangre is null or tipo_sangre in
    ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'));

comment on column public.profiles.tipo_sangre is
  'Grupo ABO y factor Rh, uno de los ocho valores de profiles_tipo_sangre_check. Dato de salud: '
  'sólo se muestra en el expediente del colaborador, que ya exige el permiso show_cssi, y NO se '
  'expone por el asistente.';
