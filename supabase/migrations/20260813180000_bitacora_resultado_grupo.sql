-- Admite el resultado `GRUPO` en la bitácora de WhatsApp.
--
-- ─── Por qué hace falta antes de desplegar la función ────────────────────────
--
-- Soli no contesta en grupos, y eso no cambia. Lo que cambia es que ahora queda RASTRO: antes, si
-- alguien metía el número del bot a un grupo y luego reportaba «Soli no contesta», en el panel no
-- había nada que mirar.
--
-- La columna `resultado` tiene un CHECK con los siete valores anteriores. Sin este `ALTER`, el insert
-- de un renglón `GRUPO` falla — y falla EN SILENCIO, porque `registrar()` envuelve el insert en un
-- try/catch para que un problema de bitácora no tumbe la respuesta al usuario. El síntoma sería
-- exactamente el que se quería arreglar: nada en el panel.
--
-- Por eso el orden importa: primero esta migración, después el despliegue de la función.

alter table public.whatsapp_bitacora
  drop constraint if exists whatsapp_bitacora_resultado_check;

alter table public.whatsapp_bitacora
  add constraint whatsapp_bitacora_resultado_check
  check (resultado = any (array[
    'ATENDIDO'::text,
    'NO_AUTORIZADO'::text,
    'SIN_REGISTRO'::text,
    'AMBIGUO'::text,
    'SIN_PERMISO'::text,
    'LIMITE'::text,
    'ERROR'::text,
    -- Llegó de un grupo. No es un fallo: es la decisión de no responder ahí, porque la identidad se
    -- resuelve por el teléfono de quien escribe y la respuesta —nombre, número de empleado y saldo de
    -- vacaciones— quedaría a la vista de todo el grupo.
    'GRUPO'::text
  ]));
