import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static SupabaseClient get client => Supabase.instance.client;

  /// Stream de notificaciones del usuario actual para filtrado en tiempo real
  static Stream<List<Map<String, dynamic>>> get allNotificationsStream {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return Stream.value([]);
    
    return client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false);
  }

  /// Obtiene todas las notificaciones recientes del usuario actual
  static Future<List<Map<String, dynamic>>> fetchRecent() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];
    
    final response = await client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(20);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Marca como leídas todas las notificaciones status_sys_alert del mismo colaborador
  /// para todos los destinatarios (read compartido entre admins)
  static Future<void> markStatusSysAlertGroupAsRead(String collaboratorUserId) async {
    await client
        .from('notifications')
        .update({'is_read': true})
        .eq('type', 'status_sys_alert')
        .eq('metadata->>user_id', collaboratorUserId)
        .eq('is_read', false);
  }

  /// Marca una notificación como leída (solo del usuario actual)
  static Future<void> markAsRead(String id) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    await client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', id)
        .eq('user_id', userId);
  }

  /// Marca todas las notificaciones del usuario actual como leídas
  static Future<void> markAllAsRead() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    await client
        .from('notifications')
        .update({'is_read': true})
        .eq('is_read', false)
        .eq('user_id', userId);
  }

  /// Obtiene notificaciones paginadas del usuario actual
  static Future<List<Map<String, dynamic>>> fetchPage({int offset = 0, int limit = 30}) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];
    final response = await client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('is_read', ascending: true)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Elimina una notificación del usuario actual
  static Future<void> deleteNotification(String id) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    await client.from('notifications').delete().eq('id', id).eq('user_id', userId);
  }

  /// Envía una nueva notificación
  static Future<void> send({
    required String title,
    required String message,
    String type = 'incidencia_alert',
    String? userId,
    Map<String, dynamic>? metadata,
  }) async {
    await client.from('notifications').insert({
      'title': title,
      'message': message,
      'type': type,
      'user_id': userId,
      'metadata': metadata ?? {},
    });
  }

  /// Envía una notificación a todos los usuarios con permiso show_users activos
  static Future<void> sendToUsersPage({
    required String title,
    required String message,
    String type = 'status_sys_alert',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final targets = await client
          .from('profiles')
          .select('id')
          .eq('permissions->>show_users', 'true')
          .eq('status_sys', 'ACTIVO');
      for (final target in targets) {
        await client.from('notifications').insert({
          'title': title,
          'message': message,
          'type': type,
          'user_id': target['id'],
          'metadata': metadata ?? {},
        });
      }
    } catch (e) {
      // No interrumpir el flujo principal
    }
  }

  /// Envía una notificación a todos los admins activos
  static Future<void> sendToAdmins({
    required String title,
    required String message,
    String type = 'incidencia_alert',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final admins = await client
          .from('profiles')
          .select('id')
          .eq('role', 'admin')
          .eq('status_sys', 'ACTIVO');

      for (final admin in admins) {
        await client.from('notifications').insert({
          'title': title,
          'message': message,
          'type': type,
          'user_id': admin['id'],
          'metadata': metadata ?? {},
        });
      }
    } catch (e) {
      // No interrumpir el flujo principal si falla
    }
  }
}
