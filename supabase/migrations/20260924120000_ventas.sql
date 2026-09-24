-- Ventas: lo que sabe y lo que captura Sisol, el agente de ventas publico de sisol.com.mx.
--
-- ─── Por que todo es suyo y no se comparte con SOL ──────────────────────────
--
-- Sisol (antes «Soli» en el Worker de chat.sisol.red) le habla a CLIENTES; SOL le habla a asesores.
-- Decidido el 24/09/2026: no comparten desarrollos ni inventario. Sisol tiene mas desarrollos que
-- SOL y va a tener reglas propias, y un cambio pensado para uno no debe cambiar lo que dice el otro.
-- Lo unico compartido es quien es quien: `profiles`, `is_admin()`, `has_permission()`.
--
-- ─── Quien escribe aqui ──────────────────────────────────────────────────────
--
-- El modelo sigue en Cloudflare (Llama de Workers AI), asi que el Worker se queda como la puerta
-- publica: chat, cotizacion y brochures. El Worker lee y escribe con la llave de servicio, que se
-- salta RLS. Por eso leads y conversaciones NO tienen politica de insert: un visitante anonimo
-- nunca toca una tabla, solo el Worker.
--
-- Permisos nuevos: `show_ventas` (ver) y `edit_ventas` (capturar y configurar).

-- ─── Catalogo de desarrollos ─────────────────────────────────────────────────
create table if not exists public.ventas_desarrollos (
  id              uuid primary key default gen_random_uuid(),
  estado          text not null,
  municipio       text not null,
  nombre          text not null unique,
  -- La pagina del desarrollo en sisol.com.mx y el nombre de sus brochures ({slug}-es.pdf).
  slug            text not null unique,
  url_pagina      text,
  -- Otras formas en que el cliente o el modelo lo escriben («punta pacífico», «pp»). Hoy estan en
  -- una regex dentro del codigo; como dato, un desarrollo nuevo no pide desplegar.
  alias           text[] not null default '{}',
  -- Ruta en el bucket `ventas-brochures`. NULL = no hay, y el chat no lo ofrece.
  brochure_es     text,
  brochure_en     text,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid references public.profiles(id) on delete set null
);

-- ─── Inventario ──────────────────────────────────────────────────────────────
--
-- `numeric` y no el texto «$5,950,000» que guardaba D1: el precio se formatea al mostrarlo, y un
-- numero se puede ordenar y comparar. Sin unique en `numero`: la carga reemplaza el inventario
-- completo del desarrollo, como hacia el panel anterior.
create table if not exists public.ventas_unidades (
  id              uuid primary key default gen_random_uuid(),
  desarrollo_id   uuid not null references public.ventas_desarrollos(id) on delete cascade,
  tipo            text,
  nivel           text,
  numero          text,
  area_int        numeric(10,2),
  area_ext        numeric(10,2),
  area_total      numeric(10,2),
  precio_mxn      numeric(14,2),
  precio_usd      numeric(14,2),
  fecha_escritura text,
  estatus         text not null default 'DISPONIBLE'
    check (estatus in ('DISPONIBLE', 'APARTADO', 'RESERVADO', 'VENDIDO', 'EN_PROCESO')),
  orden           integer not null default 0,
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid references public.profiles(id) on delete set null
);
create index if not exists idx_ventas_unidades_desarrollo on public.ventas_unidades (desarrollo_id);

-- ─── Conocimiento adicional (lo que antes eran knowledge_chunks) ────────────
create table if not exists public.ventas_conocimiento (
  id              uuid primary key default gen_random_uuid(),
  -- NULL = aplica a todos los desarrollos.
  desarrollo_id   uuid references public.ventas_desarrollos(id) on delete cascade,
  titulo          text not null,
  contenido       text not null,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid references public.profiles(id) on delete set null
);

-- ─── Configuracion del agente ────────────────────────────────────────────────
--
-- Clave → valor. Una clave ausente = el Worker usa su valor predeterminado; «Restaurar» es borrar
-- la fila. `chat_detenido` = '1' apaga el chat publico.
create table if not exists public.ventas_config (
  clave           text primary key,
  valor           text not null,
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid references public.profiles(id) on delete set null
);

-- ─── Leads ───────────────────────────────────────────────────────────────────
--
-- `folio` es lo que va en el enlace de la cotizacion que recibe el cliente. Los 21 leads que vienen
-- de D1 conservan su folio de 8 caracteres para que los enlaces ya enviados sigan abriendo; los
-- nuevos llevan 32 hex, porque 8 caracteres de un UUID se pueden adivinar y la cotizacion trae
-- nombre, correo y telefono.
create table if not exists public.ventas_leads (
  id              uuid primary key default gen_random_uuid(),
  folio           text not null unique default replace(gen_random_uuid()::text, '-', ''),
  created_at      timestamptz not null default now(),
  nombre          text not null,
  email           text not null,
  telefono        text not null,
  presupuesto     text not null,
  -- Como lo capturo el chat. `desarrollo_id` se resuelve contra el catalogo cuando se puede.
  desarrollo      text not null,
  desarrollo_id   uuid references public.ventas_desarrollos(id) on delete set null,
  resumen         text,
  notificado      boolean not null default false,
  notificado_en   timestamptz
);
create index if not exists idx_ventas_leads_created on public.ventas_leads (created_at desc);

-- ─── Conversaciones ──────────────────────────────────────────────────────────
--
-- El id lo genera el navegador del visitante (una conversacion = un id) y el Worker hace upsert en
-- cada turno. El hilo es jsonb: [{role, content}, ...].
create table if not exists public.ventas_conversaciones (
  id              text primary key,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  num_mensajes    integer not null default 0,
  transcript      jsonb not null default '[]'::jsonb,
  origen          text not null default '',
  lead_id         uuid references public.ventas_leads(id) on delete set null
);
create index if not exists idx_ventas_conv_updated on public.ventas_conversaciones (updated_at desc);

-- ─── Sello de quien capturo ──────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['ventas_desarrollos', 'ventas_unidades', 'ventas_conocimiento', 'ventas_config']
  loop
    execute format('drop trigger if exists tr_%1$s_sello on public.%1$s', t);
    execute format('create trigger tr_%1$s_sello before insert or update on public.%1$s
                      for each row execute function public.sellar_actualizacion()', t);
  end loop;
end $$;

-- ─── RLS ─────────────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['ventas_desarrollos', 'ventas_unidades', 'ventas_conocimiento',
                           'ventas_config', 'ventas_leads', 'ventas_conversaciones']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %1$s_lectura on public.%1$s', t);
    execute format('create policy %1$s_lectura on public.%1$s for select
                      using (is_admin() or has_permission(''show_ventas''))', t);
  end loop;

  -- Catalogo, inventario, conocimiento y configuracion: los captura quien tiene edit_ventas.
  foreach t in array array['ventas_desarrollos', 'ventas_unidades', 'ventas_conocimiento', 'ventas_config']
  loop
    execute format('drop policy if exists %1$s_escritura on public.%1$s', t);
    execute format('create policy %1$s_escritura on public.%1$s for all
                      using (is_admin() or has_permission(''edit_ventas''))
                      with check (is_admin() or has_permission(''edit_ventas''))', t);
  end loop;
end $$;

-- Leads y conversaciones los escribe solo el Worker. Desde la app solo se borra una conversacion.
drop policy if exists ventas_conversaciones_borrar on public.ventas_conversaciones;
create policy ventas_conversaciones_borrar on public.ventas_conversaciones
  for delete using (is_admin() or has_permission('edit_ventas'));

-- ─── Brochures ───────────────────────────────────────────────────────────────
--
-- Bucket publico: los brochures ya se entregan sin sesion a cualquier visitante del chat. Subir y
-- borrar pide edit_ventas.
insert into storage.buckets (id, name, public)
values ('ventas-brochures', 'ventas-brochures', true)
on conflict (id) do nothing;

drop policy if exists ventas_brochures_escritura on storage.objects;
create policy ventas_brochures_escritura on storage.objects
  for all using (bucket_id = 'ventas-brochures' and (is_admin() or has_permission('edit_ventas')))
  with check (bucket_id = 'ventas-brochures' and (is_admin() or has_permission('edit_ventas')));
