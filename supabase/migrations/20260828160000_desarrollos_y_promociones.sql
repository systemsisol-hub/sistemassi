-- Lo que SOL va a saber: desarrollos y promociones.
--
-- SOL es un asistente APARTE de Soli, con su propio modelo y su propia factura. Comparte con ella
-- una sola cosa a proposito: quien es quien -`profiles`, `is_admin()`, `has_permission()`-. Todo lo
-- demas es suyo. Duplicar la definicion de los permisos habria sido tener dos verdades sobre la
-- misma persona, que es el fallo que mas veces ha costado en este sistema.
--
-- ─── Por que los precios viven AQUI y no en el Drive de marketing ────────────
--
-- Los folletos son PDFs e imagenes, y pedirle a un modelo que saque un precio de un folleto es la
-- via mas corta a que se lo invente. Estan documentados cuatro casos de Soli inventando cifras de
-- vacaciones e incidencias, una de ellas una solicitud entera con folio y fechas que no existian.
-- Un saldo de vacaciones mal dicho se corrige; un PRECIO mal dicho a un cliente, no.
--
-- Por eso: el precio esta en una columna, el chat lo COPIA de aqui, y el modelo no escribe ni un
-- numero. El folleto se guarda como enlace -`url_folleto`- para poder mandarlo, no para leerlo.

create table if not exists public.desarrollos (
  id               uuid primary key default gen_random_uuid(),
  nombre           text not null,
  ubicacion        text,
  -- Texto y no enum: la lista de etapas la decide marketing y va a cambiar. La pagina ofrece las
  -- de siempre en un desplegable, que es donde toca cerrar la lista sin bloquear la base.
  etapa            text,
  descripcion      text,

  -- ─── Precios ──────────────────────────────────────────────────────────────
  --
  -- `numeric` y no `float`: un precio en coma flotante acumula centavos de error, y aqui el numero
  -- se le va a citar a un cliente.
  precio_desde     numeric(14,2),
  precio_hasta     numeric(14,2),
  moneda           text not null default 'MXN',
  enganche_pct     numeric(5,2),
  mensualidades    integer,

  superficie_desde numeric(10,2),
  superficie_hasta numeric(10,2),
  amenidades       text,

  -- El enlace al folleto del Drive. Se pega a mano: es un campo, no una integracion.
  url_folleto      text,

  -- Lo que no cabe en ninguna columna y SOL tiene que saber igual. Va al final del contexto que se
  -- le da al modelo, tal cual se escribio.
  notas            text,

  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  actualizado_en   timestamptz not null default now(),
  actualizado_por  uuid references public.profiles(id) on delete set null,

  -- Un rango al reves haria que SOL dijera «de 3 a 1 millon». Se corta en la base, no en la pagina:
  -- la pagina se puede saltar, la restriccion no.
  constraint desarrollos_rango_precio check (
    precio_desde is null or precio_hasta is null or precio_hasta >= precio_desde),
  constraint desarrollos_rango_superficie check (
    superficie_desde is null or superficie_hasta is null or superficie_hasta >= superficie_desde),
  constraint desarrollos_enganche check (
    enganche_pct is null or (enganche_pct >= 0 and enganche_pct <= 100))
);

create index if not exists desarrollos_activos_idx on public.desarrollos (is_active, nombre);

-- ─── Promociones ─────────────────────────────────────────────────────────────
--
-- La vigencia es OBLIGATORIA, y es lo que hace que esto se pueda poner en boca de un asesor. Una
-- promocion vencida citada a un cliente es peor que no tener respuesta: compromete algo que ya no
-- existe. Con fecha de fin, la consulta las excluye sola y la respuesta siempre dice hasta cuando.
create table if not exists public.promociones (
  id             uuid primary key default gen_random_uuid(),
  -- Nulo = aplica a TODOS los desarrollos. Es el caso de las promociones de temporada.
  desarrollo_id  uuid references public.desarrollos(id) on delete cascade,
  titulo         text not null,
  detalle        text,
  vigente_desde  date not null,
  vigente_hasta  date not null,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  actualizado_por uuid references public.profiles(id) on delete set null,

  constraint promociones_vigencia check (vigente_hasta >= vigente_desde)
);

create index if not exists promociones_vigencia_idx
  on public.promociones (is_active, vigente_hasta, vigente_desde);

-- ─── Quien ve y quien captura ────────────────────────────────────────────────
--
-- Dos permisos, no uno. `show_sol` es para USAR SOL y ver la informacion; `edit_desarrollos` es
-- para capturarla. Se separan por la misma razon que en Herramientas: juntarlas convertiria un
-- descuido al dar acceso en permiso de borrado sobre los precios de la empresa.
--
-- `has_permission()` se arreglo hoy -leia de `app_metadata`, donde nadie escribe- asi que estas
-- politicas SI funcionan. Antes de ese arreglo habrian devuelto false a todo el mundo.
alter table public.desarrollos enable row level security;
alter table public.promociones enable row level security;

drop policy if exists desarrollos_lectura on public.desarrollos;
create policy desarrollos_lectura on public.desarrollos
  for select to authenticated
  using (public.is_admin() or public.has_permission('show_sol'));

drop policy if exists desarrollos_escritura on public.desarrollos;
create policy desarrollos_escritura on public.desarrollos
  for all to authenticated
  using (public.is_admin() or public.has_permission('edit_desarrollos'))
  with check (public.is_admin() or public.has_permission('edit_desarrollos'));

drop policy if exists promociones_lectura on public.promociones;
create policy promociones_lectura on public.promociones
  for select to authenticated
  using (public.is_admin() or public.has_permission('show_sol'));

drop policy if exists promociones_escritura on public.promociones;
create policy promociones_escritura on public.promociones
  for all to authenticated
  using (public.is_admin() or public.has_permission('edit_desarrollos'))
  with check (public.is_admin() or public.has_permission('edit_desarrollos'));

-- ─── La marca de agua de quien capturo ───────────────────────────────────────
--
-- Se pone en la base y no en la pagina: un precio es un dato del que alguien responde, y si se deja
-- que lo mande el cliente, basta una peticion a mano para atribuirselo a otro.
create or replace function public.sellar_actualizacion()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  new.actualizado_en := now();
  new.actualizado_por := auth.uid();
  return new;
end;
$$;

drop trigger if exists tr_desarrollos_sello on public.desarrollos;
create trigger tr_desarrollos_sello before insert or update on public.desarrollos
  for each row execute function public.sellar_actualizacion();

drop trigger if exists tr_promociones_sello on public.promociones;
create trigger tr_promociones_sello before insert or update on public.promociones
  for each row execute function public.sellar_actualizacion();
