-- El permiso estaba concedido a PUBLIC (`=X/postgres` en la ACL), no a `anon` directamente, asi que
-- revocarselo a `anon` era un no-op: lo heredaba de PUBLIC igualmente.
--
-- `authenticated` y `service_role` tienen concesion EXPLICITA, asi que siguen pudiendo ejecutarlas:
-- la pagina de Usuarios y el puente de WhatsApp no se enteran de este cambio.
revoke execute on function public.update_user_admin(
  uuid, text, text, text, text, boolean, jsonb, text, text, uuid
) from public;

revoke execute on function public.whatsapp_resolver_telefono(text) from public;
