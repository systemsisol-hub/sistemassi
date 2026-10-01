import 'package:supabase_flutter/supabase_flutter.dart';

class TrashService {
  static final _client = Supabase.instance.client;

  /// Devuelve el id del renglon en la papelera, para poder deshacer.
  static Future<String> moveToTrash({
    required String originTable,
    required String originId,
    required Map<String, dynamic> data,
    required String label,
  }) async {
    final fila = await _client.from('trash').insert({
      'origin_table': originTable,
      'origin_id': originId,
      'label': label,
      'data': data,
      'deleted_by': _client.auth.currentUser?.id,
    }).select('id').single();
    return fila['id'] as String;
  }

  static Future<void> restore(String trashId) async {
    final row = await _client.from('trash').select().eq('id', trashId).single();
    final originTable = row['origin_table'] as String;
    final data = Map<String, dynamic>.from(row['data'] as Map);

    if (originTable == 'profiles') {
      // Strip the old ID to avoid FK conflict with deleted auth.users entry
      data.remove('id');
      data['has_auth_account'] = false;
    }

    // Un enlace de BI se lleva a quienes lo podian ver: `powerbi_link_users` se borra en cascada
    // con el enlace, asi que se guardan aparte y se vuelven a asignar al restaurarlo.
    final usuariosBi = originTable == 'powerbi_links'
        ? List<String>.from((data.remove('_usuarios') as List?) ?? const [])
        : const <String>[];

    await _client.from(originTable).insert(data);
    if (usuariosBi.isNotEmpty) {
      await _client.from('powerbi_link_users').insert([
        for (final u in usuariosBi) {'link_id': data['id'], 'user_id': u},
      ]);
    }
    await _client.from('trash').delete().eq('id', trashId);
  }

  static Future<void> deletePermanently(String trashId) async {
    await _client.from('trash').delete().eq('id', trashId);
  }

  static Future<void> emptyTrash() async {
    await _client.from('trash').delete().not('id', 'is', null);
  }

  static Future<List<Map<String, dynamic>>> fetchAll() async {
    await _client
        .from('trash')
        .delete()
        .lt('expires_at', DateTime.now().toUtc().toIso8601String());

    return List<Map<String, dynamic>>.from(
      await _client
          .from('trash')
          .select()
          .order('deleted_at', ascending: false),
    );
  }
}
