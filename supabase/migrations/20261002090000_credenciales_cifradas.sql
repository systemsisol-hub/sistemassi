-- Fase 2a de la revision de seguridad del 01/10/2026 (docs/revision-seguridad-credenciales.md):
-- las credenciales de sistemas salen de `profiles` a una tabla cifrada.
--
-- Hoy viven en claro en `profiles` (`mail_pass` y `drp/gp/bitrix/ek/otro` `_user`/`_pass`). Desde la
-- migracion 20261001220000 una sesion normal ya no las lee, pero siguen en texto plano en la base, en
-- los respaldos y en `perfiles_completos`.
--
-- Este paso solo AGREGA y COPIA: el texto en claro de `profiles` se borra en el paso siguiente, cuando
-- la app que lee y guarda por aqui ya este publicada.
--
--   * `credenciales_sistemas`: un renglon por persona y sistema. El usuario va en claro (se muestra);
--     la contraseña va cifrada con pgcrypto (`pgp_sym_encrypt`).
--   * La llave vive en Supabase Vault (`credenciales_clave`); se genera aqui, en la base, y no aparece
--     ni en este archivo ni en el historial de migraciones.
--   * Nadie lee la tabla directo (RLS sin politicas y sin permisos para `authenticated`). Se lee con
--     `credenciales_de()` — el propio perfil, o cualquiera para admin / show_users / show_cssi, igual
--     que `perfiles_completos` — y se escribe con `guardar_credenciales()`, solo administradores (hoy
--     solo ellos pueden editar perfiles ajenos).

-- ── La llave ─────────────────────────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'credenciales_clave') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'credenciales_clave',
      'Llave de pgp_sym_encrypt para public.credenciales_sistemas (migracion 20261002090000).'
    );
  end if;
end $$;

create or replace function public._clave_credenciales()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'credenciales_clave';
$$;

revoke all on function public._clave_credenciales() from public, anon, authenticated;

-- ── La tabla ─────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.credenciales_sistemas (
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  sistema        text not null check (sistema in ('correo', 'drp', 'gp', 'bitrix', 'ek', 'otro')),
  usuario        text,
  secreto        bytea,
  actualizado_en timestamptz not null default now(),
  actualizado_por uuid,
  primary key (profile_id, sistema)
);

comment on table public.credenciales_sistemas is
  'Credenciales de sistemas por persona; secreto cifrado (pgp_sym_encrypt, llave en Vault). Solo por credenciales_de() / guardar_credenciales(). El usuario de correo sigue en profiles.mail_user.';

alter table public.credenciales_sistemas enable row level security;
revoke all on public.credenciales_sistemas from anon, authenticated;

-- ── Leer ─────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.credenciales_de(p_profile uuid)
returns table (sistema text, usuario text, secreto text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (
       p_profile = auth.uid()
    or coalesce(public.is_admin(), false)
    or public.has_permission('show_users')
    or public.has_permission('show_cssi')
  ) then
    raise exception 'No tienes permiso para ver estas credenciales.' using errcode = '42501';
  end if;

  return query
    select c.sistema,
           c.usuario,
           case when c.secreto is null then null
                else extensions.pgp_sym_decrypt(c.secreto, public._clave_credenciales()) end
      from public.credenciales_sistemas c
     where c.profile_id = p_profile
     order by array_position(array['correo','drp','gp','bitrix','ek','otro'], c.sistema);
end;
$$;

revoke all on function public.credenciales_de(uuid) from public, anon;
grant execute on function public.credenciales_de(uuid) to authenticated;

-- ── Guardar ──────────────────────────────────────────────────────────────────────────────────────
-- `p_datos`: {"correo": {"secreto": "…"}, "drp": {"usuario": "…", "secreto": "…"}, …}. Un sistema con
-- usuario y secreto vacios se borra; uno que no viene en `p_datos` no se toca.
create or replace function public.guardar_credenciales(p_profile uuid, p_datos jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  s text;
  u text;
  k text;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'Solo un administrador puede cambiar credenciales.' using errcode = '42501';
  end if;

  for s in select jsonb_object_keys(coalesce(p_datos, '{}'::jsonb)) loop
    if s not in ('correo', 'drp', 'gp', 'bitrix', 'ek', 'otro') then
      raise exception 'Sistema desconocido: %', s;
    end if;
    u := nullif(trim(p_datos -> s ->> 'usuario'), '');
    k := nullif(p_datos -> s ->> 'secreto', '');

    if u is null and k is null then
      delete from public.credenciales_sistemas where profile_id = p_profile and sistema = s;
    else
      insert into public.credenciales_sistemas as c (profile_id, sistema, usuario, secreto, actualizado_en, actualizado_por)
      values (p_profile, s, u,
              case when k is null then null else extensions.pgp_sym_encrypt(k, public._clave_credenciales()) end,
              now(), auth.uid())
      on conflict (profile_id, sistema) do update
        set usuario = excluded.usuario, secreto = excluded.secreto,
            actualizado_en = excluded.actualizado_en, actualizado_por = excluded.actualizado_por;
    end if;
  end loop;
end;
$$;

revoke all on function public.guardar_credenciales(uuid, jsonb) from public, anon;
grant execute on function public.guardar_credenciales(uuid, jsonb) to authenticated;

-- ── Copiar lo que hay hoy en profiles ─────────────────────────────────────────────────────────────
insert into public.credenciales_sistemas (profile_id, sistema, usuario, secreto)
select p.id, x.sistema, nullif(trim(x.usuario), ''),
       case when nullif(x.secreto, '') is null then null
            else extensions.pgp_sym_encrypt(x.secreto, public._clave_credenciales()) end
  from public.profiles p
 cross join lateral (values
   ('correo', null::text,    p.mail_pass),
   ('drp',    p.drp_user,    p.drp_pass),
   ('gp',     p.gp_user,     p.gp_pass),
   ('bitrix', p.bitrix_user, p.bitrix_pass),
   ('ek',     p.ek_user,     p.ek_pass),
   ('otro',   p.otro_user,   p.otro_pass)
 ) as x(sistema, usuario, secreto)
 where nullif(trim(x.usuario), '') is not null or nullif(x.secreto, '') is not null
on conflict (profile_id, sistema) do nothing;

-- Mientras quede alguna app vieja que guarde las credenciales en `profiles` (el formulario de Usuarios
-- de antes de esta version), lo que escriba se copia cifrado aqui. El paso siguiente borra el texto en
-- claro y este trigger pasa a vaciarlo despues de copiarlo.
create or replace function public._espejo_credenciales()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  s text; u text; k text; ou text; ok text;
begin
  for s, u, k, ou, ok in
    select * from (values
      ('correo', null::text,    new.mail_pass,   null::text,      old.mail_pass),
      ('drp',    new.drp_user,    new.drp_pass,    old.drp_user,    old.drp_pass),
      ('gp',     new.gp_user,     new.gp_pass,     old.gp_user,     old.gp_pass),
      ('bitrix', new.bitrix_user, new.bitrix_pass, old.bitrix_user, old.bitrix_pass),
      ('ek',     new.ek_user,     new.ek_pass,     old.ek_user,     old.ek_pass),
      ('otro',   new.otro_user,   new.otro_pass,   old.otro_user,   old.otro_pass)
    ) as x(s, u, k, ou, ok)
  loop
    continue when tg_op = 'UPDATE' and u is not distinct from ou and k is not distinct from ok;
    continue when tg_op = 'INSERT' and nullif(trim(u), '') is null and nullif(k, '') is null;
    if nullif(trim(u), '') is null and nullif(k, '') is null then
      delete from public.credenciales_sistemas where profile_id = new.id and sistema = s;
    else
      insert into public.credenciales_sistemas as c (profile_id, sistema, usuario, secreto, actualizado_en, actualizado_por)
      values (new.id, s, nullif(trim(u), ''),
              case when nullif(k, '') is null then null else extensions.pgp_sym_encrypt(k, public._clave_credenciales()) end,
              now(), auth.uid())
      on conflict (profile_id, sistema) do update
        set usuario = excluded.usuario, secreto = excluded.secreto,
            actualizado_en = excluded.actualizado_en, actualizado_por = excluded.actualizado_por;
    end if;
  end loop;
  return null;
end;
$$;

drop trigger if exists tr_espejo_credenciales on public.profiles;
create trigger tr_espejo_credenciales
  after insert or update of mail_pass, drp_user, drp_pass, gp_user, gp_pass, bitrix_user, bitrix_pass,
                            ek_user, ek_pass, otro_user, otro_pass
  on public.profiles
  for each row execute function public._espejo_credenciales();

-- ══ La boveda de Contraseñas (`passwords`) ═══════════════════════════════════════════════════════
--
-- RLS ya la limita al dueño y a quien se la compartieron; lo que falta es que no este en claro. Misma
-- idea, con su propia llave (`boveda_clave`):
--
--   * `passwords.secreto` guarda la contraseña cifrada; un trigger la llena cada vez que se guarda
--     `password`, asi la app sigue escribiendo igual que hoy.
--   * La app lee de la vista `boveda`, que corre con los permisos de quien consulta (RLS de
--     `passwords`) y descifra con `contrasena_de_boveda()`, que vuelve a revisar dueño o compartida.
--   * El paso siguiente vacia `passwords.password` y el trigger deja de guardarla en claro.

do $$
begin
  if not exists (select 1 from vault.secrets where name = 'boveda_clave') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'boveda_clave',
      'Llave de pgp_sym_encrypt para public.passwords.secreto (migracion 20261002090000).'
    );
  end if;
end $$;

create or replace function public._clave_boveda()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'boveda_clave';
$$;

revoke all on function public._clave_boveda() from public, anon, authenticated;

alter table public.passwords add column if not exists secreto bytea;

create or replace function public._cifrar_boveda()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.password is distinct from old.password then
    new.secreto := case when nullif(new.password, '') is null then null
                        else extensions.pgp_sym_encrypt(new.password, public._clave_boveda()) end;
  end if;
  return new;
end;
$$;

drop trigger if exists tr_cifrar_boveda on public.passwords;
create trigger tr_cifrar_boveda
  before insert or update on public.passwords
  for each row execute function public._cifrar_boveda();

update public.passwords
   set secreto = extensions.pgp_sym_encrypt(password, public._clave_boveda())
 where nullif(password, '') is not null and secreto is null;

create or replace function public.contrasena_de_boveda(p_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when p.secreto is null then nullif(p.password, '')
              else extensions.pgp_sym_decrypt(p.secreto, public._clave_boveda()) end
    from public.passwords p
   where p.id = p_id
     and (p.owner_id = auth.uid()
          or exists (select 1 from public.password_shares s
                      where s.password_id = p.id and s.shared_with_id = auth.uid()));
$$;

revoke all on function public.contrasena_de_boveda(uuid) from public, anon;
grant execute on function public.contrasena_de_boveda(uuid) to authenticated;

create or replace view public.boveda
with (security_invoker = true)
as
select p.id, p.owner_id, p.name, p.url, p.username,
       public.contrasena_de_boveda(p.id) as password,
       p.description, p.created_at, p.updated_at
  from public.passwords p;

comment on view public.boveda is
  'passwords con la contraseña descifrada; RLS de passwords (dueño o compartida). Ver migracion 20261002090000.';

revoke all on public.boveda from anon;
grant select on public.boveda to authenticated;
