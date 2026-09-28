-- Incidencias: el tipo «Ajuste de saldo», que descuenta días pero no es tiempo de descanso.
--
-- Pedido del usuario el 28/09/2026 con el caso del colaborador 1178: RH (1230) cerró sus periodos
-- viejos con tres registros de un solo día —25/10/2023, 25/10/2024, 25/10/2025— por 6, 14 y 22
-- días. En «Mis incidencias» salían como vacaciones: en su tabla, en su calendario y en su gráfica
-- por mes, con 22 días en octubre. Y en RH inflaban el resumen por quincena.
--
-- El usuario propuso guardar QUIÉN creó cada registro y ocultar los que no creó el colaborador. Se
-- le planteó la alternativa y la eligió: marcar el TIPO. Las razones:
--
--   * RH también captura vacaciones DE VERDAD por quien no usa el sistema, y ésas el colaborador sí
--     las tiene que ver. «Lo creó otro» no distingue unas de otras.
--   * De los 1,207 registros que ya había, ninguno dice quién lo creó.
--   * Un ajuste tampoco debe contarse como días fuera en los reportes de RH.
--
-- Un ajuste SÍ descuenta del saldo, como hasta hoy —decisión del usuario—. Lo que cambia es sólo
-- dónde se ve. Ver `esAjuste` en incidencias_page.dart.

alter table public.incidencias
  add column if not exists tipo text not null default 'VACACIONES'
    check (tipo in ('VACACIONES', 'AJUSTE'));

comment on column public.incidencias.tipo is
  'VACACIONES o AJUSTE (ajuste de saldo: descuenta días pero no es tiempo fuera). Sólo RH o un '
  'administrador crean ajustes.';

-- ─── Un colaborador no puede crearse un ajuste ─────────────────────────────
--
-- Un ajuste no se muestra y cierra periodos: si un colaborador pudiera crearse uno, podría mover su
-- propio saldo sin que nadie lo viera en su tabla. Las políticas de administrador y de RH no cambian.
drop policy if exists "Usuarios crean sus propias incidencias" on public.incidencias;
create policy "Usuarios crean sus propias incidencias" on public.incidencias
  for insert with check (auth.uid() = usuario_id and tipo = 'VACACIONES');

drop policy if exists "Usuarios actualizan sus propias incidencias pendientes" on public.incidencias;
create policy "Usuarios actualizan sus propias incidencias pendientes" on public.incidencias
  for update
  using ((auth.uid() = usuario_id) and (status = 'PENDIENTE'::text))
  with check ((auth.uid() = usuario_id) and (status = 'PENDIENTE'::text) and tipo = 'VACACIONES');

-- ─── El caso que lo pidió ──────────────────────────────────────────────────
--
-- Los tres registros del colaborador 1178 que creó RH el 28/09/2026. Por id, no por un patrón: hay
-- otros 90 registros de un solo día con varios días, y de ésos no se sabe cuáles son ajustes y
-- cuáles vacaciones mal capturadas. Se dejan como están hasta que RH los revise.
update public.incidencias
   set tipo = 'AJUSTE'
 where id in ('466f4c1f-3199-496f-a4e5-393cab7849da',
              '401266c5-87cb-44f7-af11-9a4e464fa756',
              '9dc5f5e0-1008-4977-b777-0071a5af2b14');
