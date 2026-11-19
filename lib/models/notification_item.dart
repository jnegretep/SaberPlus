import 'dart:convert';

class NotificationItem {
  final int id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? readAt;

  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.payload,
    required this.createdAt,
    this.readAt,
  });

  bool get isUnread => readAt == null;

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      // 🔹 Usamos directamente el campo `payload` que ya viene decodificado del backend
      payload: _parsePayload(json['payload'] ?? json['payload_json']),
      // 🔹 Preferimos created_at_local si está disponible, si no usamos created_at_iso o created_at
      createdAt: DateTime.tryParse(
            (json['created_at_local'] ??
             json['created_at_iso'] ??
             json['created_at'])
            ?.toString() ?? '',
          )?.toLocal() ?? DateTime.now(),
      readAt: DateTime.tryParse(
        (json['read_at_local'] ??
         json['read_at_iso'] ??
         json['read_at'])
        ?.toString() ?? '',
      )?.toLocal(),
    );
  }

  static Map<String, dynamic> _parsePayload(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map<String, dynamic>) return raw;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }
}