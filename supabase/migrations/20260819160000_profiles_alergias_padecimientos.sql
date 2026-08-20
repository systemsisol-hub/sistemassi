-- Alergias y enfermedades crónicas en el expediente, después del tipo de sangre.
--
-- ─── Texto libre, al contrario que el tipo de sangre ─────────────────────────
--
-- El tipo de sangre tiene ocho valores posibles y por eso lleva restricción y desplegable. Esto no:
-- «penicilina», «alergia estacional», «diabetes tipo 2 e hipertensión» no caben en una lista cerrada, y
-- una lista incompleta obligaría a dejar el campo vacío cuando lo que falta es justo lo importante.
--
-- ─── No se guarda en MAYÚSCULAS, al contrario que el resto ───────────────────
--
-- Los demás campos del expediente se normalizan a mayúsculas —CURP, RFC, nombres— porque son códigos o
-- se comparan entre sí. Esto es prosa que alguien va a LEER, y probablemente deprisa: «DIABETES TIPO 2
-- E HIPERTENSIÓN ARTERIAL CONTROLADA CON MEDICAMENTO» se lee peor que la misma frase en minúsculas.
--
-- ─── Dato de salud ──────────────────────────────────────────────────────────
--
-- Vive donde ya vive el tipo de sangre: la página del expediente, que exige `show_cssi`. NO se expone
-- por el asistente mientras no se pida explícitamente, igual que se decidió con el tipo de sangre.

alter table public.profiles
  add column if not exists alergias text;

alter table public.profiles
  add column if not exists padecimientos text;

comment on column public.profiles.alergias is
  'Alergias, en texto libre. Dato de salud: solo en el expediente, que exige show_cssi.';

comment on column public.profiles.padecimientos is
  'Enfermedades cronicas o padecimientos, en texto libre. Dato de salud: solo en el expediente.';
