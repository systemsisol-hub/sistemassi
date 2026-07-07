import 'package:supabase_flutter/supabase_flutter.dart';

class TrashService {
  static final _client = Supabase.instance.client;

  static Future<void> moveToTrash({
    required String originTable,
    required String originId,
    required Map<String, dynamic> data,
    required String label,
  }) async {
    await _client.from('trash').insert({
      'origin_table': originTable,
      'origin_id': originId,
      'label': label,
      'data': data,
      'deleted_by': _client.auth.currentUser?.id,
    });
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

    await _client.from(originTable).insert(data);
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
