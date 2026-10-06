-- Catálogo de puestos (06/10/2026, a pedido del usuario).
--
-- El desplegable «Puesto» de Colaborador era una lista fija en el código: agregar un puesto
-- pedía una versión nueva de la app. Ahora vive en `puestos` y se agrega desde la ficha del
-- propio formulario. Lo leen todas las sesiones; lo cambian solo los admin, igual que `profiles`.
--
-- Datos: se quitan los espacios sobrantes («ADMINISTRADOR DE VENTAS », «RECEPCIONISTA »…), que
-- salían como un puesto aparte, y «DISE+ADOR GRAFICO» —una Ñ mal importada— pasa a DISEÑADOR.

create table if not exists public.puestos (
  nombre     text primary key check (nombre = upper(btrim(nombre)) and nombre <> ''),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users (id) on delete set null
);

alter table public.puestos enable row level security;

drop policy if exists puestos_select on public.puestos;
drop policy if exists puestos_admin on public.puestos;
create policy puestos_select on public.puestos for select to authenticated using (true);
create policy puestos_admin on public.puestos for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ── Limpieza de los puestos ya guardados ────────────────────────────────────────────────────────
update public.profiles set puesto = btrim(puesto) where puesto <> btrim(puesto);
update public.profiles set puesto = 'DISEÑADOR GRAFICO' where puesto = 'DISE+ADOR GRAFICO';

-- ── La lista del usuario ────────────────────────────────────────────────────────────────────────
insert into public.puestos (nombre, created_by) values
  ('ABOGADO', null), ('ABOGADO FREELANCE', null), ('ADMINISTRACION DE VENTAS', null),
  ('ADMINISTRADOR DE CREDITOS Y AVALUOS', null), ('ADMINISTRADOR DE OBRA', null),
  ('ADMINISTRADOR DE VENTAS', null), ('AGENTE INMOBILIARIO', null), ('ALMACEN', null),
  ('ALMACENISTA', null), ('ANALISTA ADMINISTRATIVO', null), ('ANALISTA CONTABLE', null),
  ('ANALISTA DE BASE DE DATOS', null), ('ANALISTA DE GESTIONES Y TRAMITES', null),
  ('ANALISTA DE MERCADO SECUNDARIO', null), ('ANALISTA DE OBRA SOLIDA', null),
  ('ANALISTA DE SISTEMAS', null), ('ANALISTA DE TI', null), ('ANALISTA DE TITULACION', null),
  ('ASESOR DE CALL CENTER', null), ('ASESOR LEGAL', null), ('ASISTENTE DE DIRECCION', null),
  ('ATENCION A CLIENTES', null), ('AUXILIAR ADMINISTRATIVO', null),
  ('AUXILIAR ADMINISTRATIVO CONTABLE', null), ('AUXILIAR CONTABLE', null),
  ('AUXILIAR DE ALMACEN', null), ('AUXILIAR DE CONTROL DE OBRA', null),
  ('AUXILIAR DE MANTENIMIENTO', null), ('AUXILIAR DE OBRA', null),
  ('AUXILIAR DE TITULACION', null), ('AUXILIAR DE TOPOGRAFO', null), ('AUXILIAR GENERAL', null),
  ('AUXILIAR OAP', null), ('AUXILIAR RH', null), ('AUXILIAR TITULACION', null),
  ('BECARIA ADMINISTRACION', null), ('BECARIO ADMINISTRACION', null),
  ('BECARIO DE FINANZAS', null), ('BECARIO MKT', null), ('BECARIO RH', null), ('CADENERO', null),
  ('COMERCIALIZADOR EXTERNO', null), ('COMISIONISTA EXTERNO', null),
  ('COMISIONISTA INTERNO', null), ('ENCARGADO DE COMPRAS', null), ('CONTADOR GENERAL', null),
  ('CONTADOR JR.', null), ('CONTRALOR', null), ('CONTRALORA', null), ('CONTROL DE ALMACEN', null),
  ('CONTROL DE AVANCES FISCALES FINANCIEROS', null), ('CONTROL PRESUPUESTAL', null),
  ('COORDINACION DE PROYECTOS', null), ('COORDINADOR DE ACABADOS', null),
  ('COORDINADOR DE DESARROLLO HUMANO', null), ('COORDINADOR DE ESTRUCTURA ALTAMAR', null),
  ('COORDINADOR DE ESTRUCTURA SOLIDA', null), ('COORDINADOR DE PROYECTO', null),
  ('COORDINADOR DE TESORERIA', null), ('COORDINADOR DE TITULACION', null),
  ('COORDINADOR DE URBANIZACION', null), ('COORDINADOR DESARROLLO HUMANO', null),
  ('COORDINADOR JURIDICO MS', null), ('COORDINADOR MERCADO SECUNDARIO', null),
  ('COORDINADOR VENTAS', null), ('CUANTIFICADOR', null), ('CUBRE TURNOS', null),
  ('DESALOJADOR EXTERNO', null), ('DETALLISTA DE POSVENTA', null), ('DIRECTOR COMERCIAL', null),
  ('DIRECTOR DE ADMINISTRACION Y FINANZAS', null), ('DIRECTOR DE OPERACIONES', null),
  ('DIRECTOR DE PROYECTO', null), ('DIRECTOR GENERAL', null), ('DIRECTOR JURIDICO', null),
  ('DIRECTORA DE PROYECTO', null), ('DISEÑADOR GRAFICO', null), ('EJECUTIVA DE POSVENTA', null),
  ('ENCARGADA DE POSTVENTA', null), ('ENCARGADO DE COCINA', null), ('ENCARGADO DE TURNO', null),
  ('ENTREGA DE OBRA', null), ('FACTURACION', null), ('FREELANCE MK', null),
  ('GERENTE COMERCIAL', null), ('GERENTE CONTROL PRESUPUESTAL', null),
  ('GERENTE DE DESARROLLO HUMANO', null), ('GERENTE DE IMPLEMENTACION Y SOPORTE', null),
  ('GERENTE DE MERCADO SECUNDARIO', null), ('GERENTE DE OBRA', null),
  ('GERENTE DE POSVENTA', null), ('GERENTE DE TIENDA', null),
  ('GERENTE REGIONAL DE VENTAS', null), ('GERENTE TI', null), ('GESTOR ADMINISTRATIVO', null),
  ('INTENDENTE DE OBRA', null), ('JEFE DE ALMACEN', null), ('JEFE DE MANTENIMIENTO', null),
  ('JEFE DE OBRA', null), ('JEFE DE TITULACION', null), ('JEFE DE VENTAS', null),
  ('JEFE RESIDENCIAL ALPUYECA', null), ('JEFE TITULACION', null), ('LIMPIEZA', null),
  ('LOCALIZADOR DE VIVIENDA', null), ('MANTENIMIENTO GENERAL', null), ('MARKETING', null),
  ('MERCADO SECUNDARIO', null), ('OFICIAL DE ACABADOS', null), ('POSVENTA', null),
  ('RECEPCIONISTA', null), ('RESIDENTE DE ACABADOS', null), ('RESIDENTE DE CALIDAD', null),
  ('RESIDENTE DE OBRA', null), ('RESIDENTE DE URBANIZACION', null),
  ('RESPONSABLE OPERATIVO DE RESTAURANTE', null), ('SALVAVIDAS', null),
  ('SUP. DE REHABILITACION Y ENTREGAS', null), ('SUPERINTENDENTE DE ACABADOS', null),
  ('SUPERINTENDENTE DE OBRA', null), ('SUPERINTENDENTE DE URBANIZACION', null),
  ('SUPERVISORA DE OBRA', null), ('TESORERIA', null), ('TITULACION', null),
  ('TITULACION MS', null), ('TOPOGRAFO', null), ('VELADOR', null), ('VIGILANTE', null)
on conflict (nombre) do nothing;
