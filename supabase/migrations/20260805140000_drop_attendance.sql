-- Retira el checador: tabla de asistencia y sus fotos.
--
-- Era un piloto detenido: 15 registros entre el 25 de marzo y el 21 de mayo de 2026, con 30
-- fotos (entrada y salida por registro, ~1.8 MB). Se retiró el código que lo alimentaba y lo
-- consultaba: las páginas de Flutter y la herramienta ver_asistencia del asistente IA.
--
-- La tabla `schedules` NO se toca: sigue en uso por colaborador_page y colaborador_detail_page,
-- que resuelven el campo `profiles.horario` contra ella.
--
-- Las 4 políticas RLS de attendance (Admins can view all / Users can insert, update, view their
-- own) caen con el DROP TABLE, no hace falta retirarlas por separado.

DROP TABLE IF EXISTS attendance;

-- ⚠️ El bucket `asistencia_registros` (30 objetos, ~1.8 MB) NO se borra aquí.
--
-- Supabase bloquea el borrado directo de storage.objects con un guardarraíl:
--   "Direct deletion from storage tables is not allowed. Use the Storage API instead.
--    HINT: This prevents accidental data loss from orphaned objects."
--
-- Es correcto que lo bloquee: borrar la fila deja el archivo huérfano en el almacenamiento.
-- Hay que eliminarlo por la API de Storage o desde el dashboard:
--   Storage → asistencia_registros → Delete bucket
--
-- Mientras el bucket exista, las fotos siguen accesibles por URL pública. Ya nada en el código
-- las genera ni las consulta.
