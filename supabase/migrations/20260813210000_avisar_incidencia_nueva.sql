-- Avisa al jefe directo y a Desarrollo Humano cuando se crea una incidencia.
--
-- ─── Por qué es un DISPARADOR y no código del asistente ──────────────────────
--
-- Se pidió al crear una solicitud por WhatsApp, pero las incidencias nacen por TRES caminos: el
-- formulario de la página, la herramienta `crear_incidencia` de Soli en la aplicación, y esa misma
-- herramienta por el puente de WhatsApp. Ponerlo en la herramienta dejaría sin aviso las que se crean
-- desde la página, que son la mayoría. Aquí cubre los tres y no hay copia que se desincronice.
--
-- ─── A quién avisa, y qué se midió antes de escribirlo ───────────────────────
--
-- **El jefe** sale de `profiles.jefe_inmediato`, que guarda el NOMBRE COMPLETO EN TEXTO, no un id. Así
-- que hay que resolverlo, y sólo se avisa si el nombre empata con EXACTAMENTE UN perfil vigente con
-- cuenta. Medido sobre los 83 vigentes con cuenta:
--
--     54  resuelven a un jefe            <- reciben el aviso
--     18  no empatan con nadie vigente   <- nombre viejo, con dedazo, o el jefe está de baja
--     11  no tienen jefe capturado
--
-- O sea que un tercio no llegará a ningún jefe, y eso es un problema de DATOS, no de este código:
-- se arregla capturando bien `jefe_inmediato` en la página de Colaboradores. Desarrollo Humano recibe
-- el aviso siempre, así que ninguna solicitud queda sin destinatario.
--
-- **Desarrollo Humano** se deduce del puesto y NO se fija por id. La razón de no fijarlo es que el día
-- que cambie la persona, nadie va a recordar que existe esta migración. La razón de exigir vigencia es
-- concreta: hay DOS perfiles cuyo puesto habla de desarrollo humano —«COORDINADOR DESARROLLO HUMANO»
-- (1230, KANDI AMERICA, vigente) y «COORDINADOR DE DESARROLLO HUMANO» (0175, GERARDO RENE, BAJA)— y sin
-- el filtro se avisaría a alguien que ya no está.
--
-- El precio de deducirlo: si el puesto se escribe distinto, o esa persona se va sin reemplazo
-- capturado, Desarrollo Humano deja de recibir avisos EN SILENCIO. Es el riesgo que se acepta a cambio
-- de que no haya que tocar una migración para cambiar de coordinador.
--
-- ─── Dos cosas que no puede hacer ────────────────────────────────────────────
--
-- 1. NO puede tumbar la creación de la incidencia. Todo va envuelto en un manejador de excepciones que
--    devuelve NEW: una solicitud de vacaciones importa más que su aviso, y un fallo al notificar no
--    puede impedir que alguien pida sus días.
-- 2. NO avisa a quien la creó. Recibir una notificación de tu propia solicitud es ruido, y cuando el
--    jefe o la coordinadora crean una para sí mismos se avisarían a sí mismos.

create or replace function public.notificar_incidencia_nueva()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  quien       text;
  jefe_id     uuid;
  cuantos     int;
  detalle     text;
  destino     uuid;
begin
  -- Nombre de quien pide, para el texto del aviso. Se prefiere el del perfil al `nombre_usuario` de la
  -- incidencia, que lo escribe quien la crea y puede venir a medias.
  select coalesce(nullif(trim(concat_ws(' ', p.nombre, p.paterno, p.materno)), ''),
                  new.nombre_usuario, 'Un colaborador')
    into quien
    from profiles p where p.id = new.usuario_id;
  quien := coalesce(quien, new.nombre_usuario, 'Un colaborador');

  detalle := quien
    || coalesce(' · ' || new.dias::text || ' día' || case when new.dias = 1 then '' else 's' end, '')
    || coalesce(' · del ' || to_char(new.fecha_inicio, 'DD/MM/YYYY'), '')
    || coalesce(' al ' || to_char(new.fecha_fin, 'DD/MM/YYYY'), '')
    || coalesce(' · regreso ' || to_char(new.fecha_regreso, 'DD/MM/YYYY'), '')
    || coalesce(' · periodo ' || new.periodo, '');

  -- ── El jefe directo ──────────────────────────────────────────────────────
  select count(*), min(j.id)
    into cuantos, jefe_id
    from profiles solicitante
    join profiles j
      on upper(trim(concat_ws(' ', j.nombre, j.paterno, j.materno)))
       = upper(trim(solicitante.jefe_inmediato))
   where solicitante.id = new.usuario_id
     and j.status_rh <> 'BAJA'
     and j.has_auth_account = true;

  -- Sólo si el nombre resuelve a UNA persona. Con varios homónimos no se elige: avisar al que salga
  -- primero sería mandarle la solicitud de un desconocido a alguien que no es su jefe.
  if cuantos = 1 and jefe_id is not null and jefe_id <> new.usuario_id then
    insert into notifications (title, message, type, is_read, created_at, user_id, metadata)
    values ('Nueva solicitud de vacaciones',
            detalle || ' — te toca autorizarla.',
            'new_incidencia', false, now(), jefe_id,
            jsonb_build_object('incidencia_id', new.id, 'solicitante_id', new.usuario_id,
                               'motivo', 'jefe_directo'));
  end if;

  -- ── Desarrollo Humano ────────────────────────────────────────────────────
  for destino in
    select p.id from profiles p
     where p.puesto ilike '%DESARROLLO HUMANO%'
       and p.status_rh <> 'BAJA'
       and p.has_auth_account = true
       and p.id <> new.usuario_id
       and (jefe_id is null or p.id <> jefe_id)   -- si ya se le avisó como jefe, no dos veces
  loop
    insert into notifications (title, message, type, is_read, created_at, user_id, metadata)
    values ('Nueva solicitud de vacaciones',
            detalle,
            'new_incidencia', false, now(), destino,
            jsonb_build_object('incidencia_id', new.id, 'solicitante_id', new.usuario_id,
                               'motivo', 'desarrollo_humano'));
  end loop;

  return new;
exception
  when others then
    -- Un fallo al avisar NO puede impedir que alguien pida sus vacaciones.
    raise warning 'notificar_incidencia_nueva fallo para la incidencia %: %', new.id, sqlerrm;
    return new;
end;
$function$;

drop trigger if exists tr_notificar_incidencia_nueva on public.incidencias;

create trigger tr_notificar_incidencia_nueva
  after insert on public.incidencias
  for each row execute function public.notificar_incidencia_nueva();

-- No se concede EXECUTE a nadie: la llama el disparador, que corre con el dueño de la tabla.
revoke execute on function public.notificar_incidencia_nueva() from public;
revoke execute on function public.notificar_incidencia_nueva() from anon;

-- ─── Nota sobre el tipo y sobre lo que se retira ─────────────────────────────
--
-- Se usa el tipo `new_incidencia`, que ya existía y ya tiene icono en el modal de notificaciones. No
-- hace falta tocar el filtro de visibilidad: `allNotificationsStream` consulta con
-- `.eq('user_id', userId)`, así que cada quien ve sólo las suyas.
--
-- A cambio, el formulario de la página deja de mandar su aviso a TODOS los administradores
-- (`sendToAdmins` en incidencias_page.dart). Si se dejara, crear una solicitud desde la página
-- generaría las dos cosas: el aviso dirigido al jefe y a Desarrollo Humano, MÁS el antiguo a los cinco
-- administradores. Y ese antiguo sólo salía desde la página: por WhatsApp no avisaba a nadie, que es
-- justo lo que se reportó.

-- ─── Dos correcciones que salieron de PROBARLA, no de leerla ─────────────────
--
-- La primera version fallaba entera y en silencio. Aplicada en produccion como
-- `avisar_incidencia_nueva_corregido`:
--
-- 1. `min(j.id)` NO EXISTE para uuid en PostgreSQL -«function min(uuid) does not exist»-. El
--    disparador reventaba en la primera consulta. Se usa `(array_agg(j.id))[1]`.
--
-- 2. Los dos avisos van ahora en bloques SEPARADOS, cada uno con su manejador. Con uno solo, el fallo
--    al resolver al jefe cancelaba tambien el aviso a Desarrollo Humano: se perdian los dos.
--
-- La leccion del manejador de excepciones: sigue siendo lo correcto -una solicitud de vacaciones
-- importa mas que su aviso- pero convierte cualquier error en silencio. El insert de la incidencia
-- funciono y todo parecia bien; el fallo solo aparecio al preguntar si la notificacion EXISTIA. Con un
-- manejador asi hay que comprobar el resultado, no que la operacion no reventara.
--
-- Verificado en produccion con dos incidencias de prueba, creadas y borradas: la de ANGEL ANTONIO
-- (0163) genero exactamente dos avisos, a MARCO ANTONIO MONTOYA (0186, su jefe, con «te toca
-- autorizarla») y a KANDI AMERICA GARCIA (1230, Desarrollo Humano).
