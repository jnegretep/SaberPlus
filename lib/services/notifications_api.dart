import 'dart:convert';
import 'package:http/http.dart' as http;

class NotificationsApi {
  final String baseUrl;
  final String? token; // JWT opcional para futuras protecciones

  NotificationsApi({required this.baseUrl, this.token});

  /// 🔹 Obtener notificaciones con soporte de paginación
  Future<Map<String, dynamic>> fetchForUser(
    int userId, {
    int page = 1,
    int limit = 5,
  }) async {
    final uri = Uri.parse(
        '$baseUrl/get_notifications.php?user_id=$userId&page=$page&limit=$limit');
    final res = await http.get(uri, headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    });

    final data = jsonDecode(utf8.decode(res.bodyBytes));

    if (data['success'] != true) {
      return {
        "success": false,
        "notifications": [],
        "total_count": 0,
        "count": 0,
        "page": page,
        "limit": limit,
      };
    }

    final notifications = (data['notifications'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return {
      "success": true,
      "notifications": notifications,
      "total_count": data['total_count'] ?? notifications.length,
      "count": data['count'] ?? notifications.length,
      "page": data['page'] ?? page,
      "limit": data['limit'] ?? limit,
    };
  }

  /// 🔹 Marcar una notificación como leída y devolver la lista actualizada
  Future<Map<String, dynamic>?> markRead({
    required int id,
    required int userId,
  }) async {
    final uri = Uri.parse('$baseUrl/mark_notification_read.php');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'id': id, 'user_id': userId}),
    );

    final data = jsonDecode(utf8.decode(res.bodyBytes));

    if (data['success'] == true) {
      final notifications = (data['notifications'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      return {
        "success": true,
        "notifications": notifications,
        "total_count": data['total_count'] ?? notifications.length,
        "count": data['count'] ?? notifications.length,
        "page": data['page'],
        "limit": data['limit'],
      };
    }
    return null;
  }
}