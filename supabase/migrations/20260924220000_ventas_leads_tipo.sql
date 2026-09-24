-- Quien es cada registro de Sisol: un cliente, un asesor externo, un proveedor o alguien que busca
-- empleo.
--
-- Pedido del usuario el 24/09/2026: al chat de sisol.com.mx llegan brokers que quieren vender los
-- desarrollos y empresas que quieren ofrecer servicios. Sisol les pide los mismos datos (nombre,
-- correo, telefono), pero en lugar de la cotizacion les da una tarjeta con los contactos de SI SOL,
-- y el registro queda etiquetado para no mezclarlo con los clientes. «Busca empleo» lo agrego el
-- usuario en la misma decision; recibe la tarjeta de proveedores.
--
-- Los 21 leads que ya existen quedan como CLIENTE, que es lo que el chat asumia al registrarlos.

alter table public.ventas_leads
  add column if not exists tipo text not null default 'CLIENTE'
    check (tipo in ('CLIENTE', 'ASESOR_EXTERNO', 'PROVEEDOR', 'BUSCA_EMPLEO'));

comment on column public.ventas_leads.tipo is
  'CLIENTE recibe cotizacion; ASESOR_EXTERNO, PROVEEDOR y BUSCA_EMPLEO reciben la tarjeta de contacto.';

create index if not exists idx_ventas_leads_tipo on public.ventas_leads (tipo, created_at desc);
