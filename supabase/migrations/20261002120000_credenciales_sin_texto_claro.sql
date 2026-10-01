-- Fase 2b: se borra el texto en claro que la migracion 20261002090000 ya copio cifrado.
--
-- Aplicar SOLO cuando la app que lee `credenciales_de()` y la vista `boveda` ya este publicada (web,
-- iPhone y Android). Antes de eso, una app vieja mostraria las credenciales y la boveda vacias.
--
-- Despues de esto:
--   * `profiles.mail_pass` y `drp/gp/bitrix/ek/otro` `_user`/`_pass` quedan en NULL. Las columnas se
--     dejan (las usa `perfiles_completos`, que es `p.*`); si una app vieja todavia escribe ahi, el
--     trigger lo copia cifrado y lo vuelve a vaciar.
--   * `passwords.password` queda en NULL; el trigger cifra lo que llegue y no guarda el texto.

-- ── profiles ─────────────────────────────────────────────────────────────────────────────────────
create or replace function public._espejo_credenciales()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  s text; u text; k text; ou text; ok text;
begin
  -- El UPDATE de abajo vuelve a disparar este trigger; ese no copia nada.
  if pg_trigger_depth() > 1 then
    return null;
  end if;

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
    continue when nullif(trim(u), '') is null and nullif(k, '') is null;
    insert into public.credenciales_sistemas as c (profile_id, sistema, usuario, secreto, actualizado_en, actualizado_por)
    values (new.id, s, nullif(trim(u), ''),
            case when nullif(k, '') is null then null else extensions.pgp_sym_encrypt(k, public._clave_credenciales()) end,
            now(), auth.uid())
    on conflict (profile_id, sistema) do update
      set usuario = excluded.usuario, secreto = excluded.secreto,
          actualizado_en = excluded.actualizado_en, actualizado_por = excluded.actualizado_por;
  end loop;

  update public.profiles
     set mail_pass = null, drp_user = null, drp_pass = null, gp_user = null, gp_pass = null,
         bitrix_user = null, bitrix_pass = null, ek_user = null, ek_pass = null,
         otro_user = null, otro_pass = null
   where id = new.id;
  return null;
end;
$$;

update public.profiles
   set mail_pass = null, drp_user = null, drp_pass = null, gp_user = null, gp_pass = null,
       bitrix_user = null, bitrix_pass = null, ek_user = null, ek_pass = null,
       otro_user = null, otro_pass = null
 where coalesce(mail_pass, drp_user, drp_pass, gp_user, gp_pass, bitrix_user, bitrix_pass,
                ek_user, ek_pass, otro_user, otro_pass) is not null;

-- ── passwords ────────────────────────────────────────────────────────────────────────────────────
create or replace function public._cifrar_boveda()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.password is distinct from old.password then
    if new.password is not null then
      new.secreto := case when new.password = '' then null
                          else extensions.pgp_sym_encrypt(new.password, public._clave_boveda()) end;
    end if;
    new.password := null;
  end if;
  return new;
end;
$$;

-- `password` era NOT NULL; ahora la contraseña vive en `secreto`.
alter table public.passwords alter column password drop not null;

update public.passwords set password = null where password is not null;
