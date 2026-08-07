-- Regla de días a descontar, configurable.
--
-- La regla acordada: cada 3 retardos son 1 día de descuento, y cada falta sin justificar es 1 día.
-- El número de retardos se guarda en la base en lugar de fijarlo en el código, por lo mismo que los
-- umbrales del semáforo: es una decisión de nómina y cambia sin que deba desplegarse nada.
--
-- ⚠️ El redondeo es POR PERSONA, no sobre el total. Medido en el periodo del 16 al 31 de julio:
-- 102 retardos dan 25 días contando por persona y 34 si se dividiera el total. Nueve días de
-- diferencia en nómina, siempre en contra del trabajador. Dos personas con 2 retardos cada una no
-- hacen un día de descuento.
--
-- Las faltas justificadas no descuentan: una incapacidad la cubre el IMSS y las vacaciones son
-- pagadas. Por eso el conteo usa el estado FALTA, que ya excluye lo justificado.

ALTER TABLE checador_umbrales
  ADD COLUMN IF NOT EXISTS retardos_por_descuento int NOT NULL DEFAULT 3;

ALTER TABLE checador_umbrales
  DROP CONSTRAINT IF EXISTS retardos_por_descuento_positivo;
ALTER TABLE checador_umbrales
  ADD CONSTRAINT retardos_por_descuento_positivo
  CHECK (retardos_por_descuento >= 1);

COMMENT ON COLUMN checador_umbrales.retardos_por_descuento IS
  'Cuántos retardos acumulados equivalen a un día de descuento. El cociente se redondea hacia abajo y por persona.';
