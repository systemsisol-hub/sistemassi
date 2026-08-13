-- En estas dos `anon` tenia concesion EXPLICITA (`anon=X/postgres`), no heredada de PUBLIC, asi que
-- el `revoke ... from public` de la migracion anterior fue un no-op. Al contrario que en
-- `update_user_admin`, donde el permiso SI venia de PUBLIC. Conviene mirar la ACL de cada una en vez
-- de suponer por donde entra:
--
--   select proname, proacl from pg_proc join pg_namespace n on n.oid=pronamespace where nspname='public';
revoke execute on function public.revoke_user_access(uuid) from anon;
revoke execute on function public.increment_knowledge_views(uuid) from anon;
