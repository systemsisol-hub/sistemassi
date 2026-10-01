import 'package:supabase_flutter/supabase_flutter.dart';

/// Credenciales de sistemas (correo, DRP, GP, Bitrix, ENK, otro) de una persona.
///
/// Desde la migracion 20261002090000 viven cifradas en `credenciales_sistemas`, no en `profiles`.
/// Las paginas siguen trabajando con los nombres de columna de antes (`mail_pass`, `drp_user`,
/// `drp_pass`, …); aqui se traducen. El usuario del correo sigue en `profiles.mail_user`.
class Credenciales {
  Credenciales._();

  /// Sistema en la base → (columna de usuario, columna de contraseña) como las usan las paginas.
  static const columnas = {
    'correo': (null, 'mail_pass'),
    'drp': ('drp_user', 'drp_pass'),
    'gp': ('gp_user', 'gp_pass'),
    'bitrix': ('bitrix_user', 'bitrix_pass'),
    'ek': ('ek_user', 'ek_pass'),
    'otro': ('otro_user', 'otro_pass'),
  };

  /// Todas las columnas que antes estaban en `profiles` (menos `mail_user`).
  static final nombresDeColumna = [
    for (final c in columnas.values) ...[if (c.$1 != null) c.$1!, c.$2],
  ];

  /// Lee las credenciales de [profileId] como `{columna: valor}`. Las columnas sin dato vienen en
  /// null, asi que se pueden mezclar sobre un perfil para reemplazar lo que traiga.
  static Future<Map<String, String?>> leer(String profileId) async {
    final filas = await Supabase.instance.client
        .rpc('credenciales_de', params: {'p_profile': profileId});
    final res = <String, String?>{for (final n in nombresDeColumna) n: null};
    for (final f in (filas as List)) {
      final c = columnas[f['sistema']];
      if (c == null) continue;
      if (c.$1 != null) res[c.$1!] = f['usuario'] as String?;
      res[c.$2] = f['secreto'] as String?;
    }
    return res;
  }

  /// Guarda las credenciales de [profileId] a partir de `{columna: valor}`. Solo se tocan los
  /// sistemas que traen alguna de sus columnas; uno con todo vacio se borra. Solo administradores.
  static Future<void> guardar(String profileId, Map<String, dynamic> valores) async {
    final datos = <String, Map<String, String?>>{};
    columnas.forEach((sistema, c) {
      if (!valores.containsKey(c.$2) && (c.$1 == null || !valores.containsKey(c.$1))) return;
      datos[sistema] = {
        if (c.$1 != null) 'usuario': valores[c.$1]?.toString(),
        'secreto': valores[c.$2]?.toString(),
      };
    });
    if (datos.isEmpty) return;
    await Supabase.instance.client.rpc('guardar_credenciales', params: {
      'p_profile': profileId,
      'p_datos': datos,
    });
  }
}
