import 'package:flutter/foundation.dart';
import '../models/notification_item.dart';
import '../services/notifications_api.dart';

class NotificationProvider extends ChangeNotifier {
  final NotificationsApi api;
  final int userId;

  NotificationProvider({required this.api, required this.userId});

  List<NotificationItem> _items = [];
  bool _loading = false;
  bool _initialized = false;

  int _page = 1;
  int _limit = 5;
  int _totalCount = 0;

  List<NotificationItem> get items => _items;
  bool get loading => _loading;
  bool get initialized => _initialized;
  int get unreadCount => _items.where((n) => n.isUnread).length;
  int get page => _page;
  int get limit => _limit;
  int get totalCount => _totalCount;

  bool get hasPrevPage => _page > 1;
  bool get hasNextPage => (_page * _limit) < _totalCount;

  /// 🔹 Refresca notificaciones desde el backend con soporte de paginación
  Future<void> refresh({int? page, int? limit}) async {
    _loading = true;
    notifyListeners();
    try {
      if (page != null) _page = page;
      if (limit != null) _limit = limit;

      final raw = await api.fetchForUser(userId, page: _page, limit: _limit);

      // raw ahora es un Map con notifications y total_count
      final list = raw['notifications'] as List<dynamic>? ?? [];
      _items = list.map((j) => NotificationItem.fromJson(j)).toList();

      // 🔹 Convertir total_count a int de forma segura
      _totalCount = int.tryParse(raw['total_count']?.toString() ?? '') ?? _items.length;

      _initialized = true;
    } catch (e) {
      debugPrint("[NotificationProvider][refresh][ERROR] $e");
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 🔹 Marca una notificación como leída y actualiza la lista completa
  Future<void> markAsRead(int id) async {
    try {
      final raw = await api.markRead(id: id, userId: userId);
      if (raw != null && raw['success'] == true) {
        final list = raw['notifications'] as List<dynamic>? ?? [];
        _items = list.map((j) => NotificationItem.fromJson(j)).toList();

        // 🔹 Convertir total_count también aquí
        _totalCount = int.tryParse(raw['total_count']?.toString() ?? '') ?? _items.length;

        _initialized = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("[NotificationProvider][markAsRead][ERROR] $e");
    }
  }
}