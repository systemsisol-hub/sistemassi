# Revisión de seguridad: credenciales y datos de `profiles`

01/10/2026 · Supabase `zkmbebybyyefmqcxjqrg`.

**Estado: cerrado el 01/10/2026.** Los cuatro hallazgos están corregidos en producción (base, web,
iPhone y Android); el detalle está en [Lo que se hizo](#lo-que-se-hizo). Lo de abajo describe cómo
estaba al revisarlo: la revisión fue de solo lectura y las pruebas de escritura se deshicieron.

## Resumen

| # | Hallazgo | Gravedad |
|---|---|---|
| 1 | Cualquier usuario con sesión puede leer **todas las columnas de los 2,508 perfiles**, incluidas las contraseñas | Crítica |
| 2 | Cualquier usuario puede **darse a sí mismo cualquier permiso** y el rol `admin` | Crítica |
| 3 | Las **1,529 contraseñas están en texto plano**; Mi Perfil dice «Cifradas» | Alta |
| 4 | Varias pantallas piden `select()` o `mail_pass` de muchos perfiles a la vez | Media |

La app oculta estos datos en pantalla según los permisos, pero la protección real está en la base:
la llave pública de Supabase viene dentro de la web, y con el token de cualquier sesión se puede
consultar la API directamente.

## 1. Lectura de todos los perfiles

La política `profiles_select_auth` (SELECT, rol `authenticated`) es `USING (true)`. No hay permisos
por columna: `authenticated` tiene SELECT en todas.

Prueba con la identidad de la cuenta de revisión de Google Play (rol `usuario`, sin permisos de
usuarios ni colaboradores), contando sin leer ningún valor:

| Dato | Registros visibles |
|---|---|
| Perfiles | 2,508 (todos) |
| `mail_pass` | 1,147 |
| `drp_pass`, `gp_pass`, `bitrix_pass`, `ek_pass`, `otro_pass` | 168 perfiles |
| CLABE | 2,452 |
| CURP | 2,404 |
| Alergias o padecimientos | 5 |

Hoy hay 79 cuentas con acceso. Cualquiera de ellas (y los revisores de Google, si se les da la cuenta
de prueba) puede bajar todo.

## 2. Escalada de permisos

La política `profiles_update_self` deja a cada quien actualizar **su propio renglón sin límite de
columnas**, y no hay trigger que lo impida. Prueba (deshecha) con la cuenta `usuario`:

```
filas=1  rol=admin  show_users=true  has_permission('show_users')=true
```

- `has_permission()` lee `profiles.permissions`, así que el permiso que uno se pone vale en la base.
  Protege 22 tablas: `whatsapp_autorizados`/`whatsapp_bitacora`, `system_logs`, `issi_inventory`,
  `correspondencia` y sus listas (envío de comunicados a todos), las `ventas_*` (leads de clientes),
  `avisos`, y las de SOL (`desarrollos`, `unidades`, `promociones`, …).
- `role = 'admin'` en `profiles` hace que la app muestre todo el menú de administrador.
- Lo que sí resiste: `is_admin()` usa `app_metadata` del token, no `profiles.role`, así que las
  políticas solo de administrador (p. ej. `profiles_all_admin`, `trash`) no se abren con esto.

## 3. Contraseñas en texto plano

Ninguno de los 1,529 valores tiene forma de dato cifrado (todos miden de 2 a 18 caracteres):

| Columna | Llenas |
|---|---|
| `profiles.mail_pass` | 1,147 |
| `profiles.otro_pass` | 117 |
| `profiles.drp_pass` | 64 |
| `profiles.gp_pass` | 62 |
| `profiles.bitrix_pass` | 52 |
| `profiles.ek_pass` | 49 |
| `passwords.password` (bóveda) | 38 |

La bóveda `passwords` sí tiene bien su acceso (`owner_all`, y `shared_read` solo para con quien se
compartió); el problema ahí es solo que está en claro. `lib/user_dashboard.dart:1012` muestra la
etiqueta «Cifradas», que no es cierta. Ya existen `pgcrypto` y `supabase_vault` en el proyecto.

## 4. Lecturas de más en la app

| Archivo | Qué pide | Problema |
|---|---|---|
| `lib/usuarios_page.dart:224` | `mail_user, mail_pass` de todos los usuarios para la lista | Baja las contraseñas de todos al abrir Usuarios |
| `lib/passwords_page.dart:1351` | `select()` de todos los perfiles con `show_passwords` | Para elegir con quién compartir baja todas sus columnas, contraseñas incluidas |
| `lib/colaborador_page.dart:182` | `select()` de todos los perfiles, de 1,000 en 1,000 | La lista de Colaboradores baja el expediente completo de todos |
| `lib/user_dashboard.dart:96`, `lib/signature_generator_page.dart:100` | `select('*')` | Del propio perfil: menor, pero conviene pedir solo lo necesario |

Otros que tocan las columnas de credenciales: `lib/colaborador_detail_page.dart` (12),
`lib/user_dashboard.dart` (6), `lib/correspondencia_page.dart` (1). La función `correspondencia` no
pide `mail_pass` a propósito.

## Lo que se hizo

Cada migración se probó antes en producción dentro de una transacción que se deshacía, con la cuenta
de prueba (rol `usuario`) y con un administrador.

**Fase 1 — cerrar la base** (hallazgos 1, 2 y 4):

| Migración | Qué cambia |
|---|---|
| `20261001150000_perfil_sin_autoescalada` | Trigger `tr_0_proteger_perfil`: quien no es admin solo cambia su `foto_url`. `update_user_admin`, `update_user_password`, `revoke_user_access` y `sincronizar_rol_en_jwt` deciden con `is_admin()` (token) y no con `profiles.role` |
| `20261001200000_perfiles_completos` | Vistas `perfiles_completos` (el propio perfil, o todos para admin / `show_users` / `show_cssi`) y `nomina_perfiles` (admin / `show_tablas`); `directorio` corre con los permisos de su dueño |
| `20261001220000_profiles_sin_columnas_sensibles` | `authenticated` solo lee de `profiles` las columnas no sensibles; `anon`, ninguna |

La app dejó de pedir columnas sensibles a `profiles` y las lee por las vistas. Decisiones del
usuario: nombres y correos visibles para todos (es una app del personal), teléfono y celular solo para
administradores, la fecha de nacimiento visible por los cumpleaños de Social.

Comprobado después: la cuenta de prueba ve los 2,508 perfiles, pero sin contraseñas, CLABE, CURP,
salud ni celular; en `perfiles_completos` solo el suyo y en `nomina_perfiles` nada. Ya no puede
cambiarse el rol ni los permisos.

**Fase 2 — credenciales cifradas** (hallazgo 3):

| Migración | Qué cambia |
|---|---|
| `20261002090000_credenciales_cifradas` | Tabla `credenciales_sistemas`, con la contraseña cifrada (`pgp_sym_encrypt`, llave `credenciales_clave` en Vault) y sin acceso directo. Se lee con `credenciales_de()` (el propio perfil, o admin / `show_users` / `show_cssi`) y solo un administrador guarda con `guardar_credenciales()`. La bóveda guarda `passwords.secreto` cifrado (llave `boveda_clave`) y la app la lee de la vista `boveda` (dueño o compartida) |
| `20261002120000_credenciales_sin_texto_claro` | Vacía `profiles.mail_pass` y `*_user`/`*_pass` y `passwords.password`. Si una app vieja escribe ahí, un trigger lo copia cifrado y lo vuelve a vaciar |

Se copiaron 1,500 credenciales de 1,147 personas y las 38 de la bóveda; todas descifran igual al
original. Mi Perfil, Colaborador, Usuarios y Contraseñas leen por lo nuevo
(`lib/services/credenciales.dart`), y la etiqueta «Cifradas» ya es cierta. `mail_user` sigue en
`profiles`.

**Fase 3 — no se hará:** la propuesta era cambiar las contraseñas guardadas, porque estuvieron al
alcance de las 79 cuentas. El usuario decidió no hacerlo: quienes tenían acceso no son personal
técnico ni tienen APIs conectadas, así que en la práctica no las vieron, y cambiarlas sería mucho
trabajo para todos.

**Al agregar una columna a `profiles`:** `authenticated` no la puede leer hasta agregarla al permiso
de la migración `20261001220000` (si no es sensible) o leerla por `perfiles_completos`.
