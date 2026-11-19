import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notification_provider.dart';
import '../models/notification_item.dart';
import '../core/theme/app_colors.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // 🔹 Cargar la primera página al iniciar después del primer frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<NotificationProvider>();
      provider.refresh(page: provider.page, limit: provider.limit);
    });
  }

  void _loadPage(int page) {
    final provider = context.read<NotificationProvider>();
    provider.refresh(page: page, limit: provider.limit);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              color: AppColors.textDisabled,
              size: 56,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No tienes notificaciones',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.borderDark,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Aquí aparecerán tus notificaciones cuando recibas actualizaciones importantes',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          const SizedBox(height: 16),
          const Text(
            'Cargando notificaciones...',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

Widget _buildPaginationControls(NotificationProvider provider) {
  final totalPages = (provider.totalCount / provider.limit).ceil();

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: AppColors.shadowMd,
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      children: [
        // Botón Anterior
        Expanded(
          child: ElevatedButton(
            onPressed: provider.hasPrevPage
                ? () => _loadPage(provider.page - 1)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: provider.hasPrevPage
                  ? AppColors.primary
                  : AppColors.surfaceVariant,
              foregroundColor: provider.hasPrevPage
                  ? AppColors.textOnPrimary
                  : AppColors.textDisabled,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              elevation: 0,
              shadowColor: Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chevron_left_rounded,
                  size: 18,
                  color: provider.hasPrevPage
                      ? AppColors.textOnPrimary
                      : AppColors.textDisabled,
                ),
                const SizedBox(width: 4),
                Text(
                  "Anterior",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: provider.hasPrevPage
                        ? AppColors.textOnPrimary
                        : AppColors.textDisabled,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Indicador de página
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceClean,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            "Página ${provider.page} de $totalPages",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),

        const SizedBox(width: 12),

        // Botón Siguiente
        Expanded(
          child: ElevatedButton(
            onPressed: provider.hasNextPage
                ? () => _loadPage(provider.page + 1)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: provider.hasNextPage
                  ? AppColors.primary
                  : AppColors.surfaceVariant,
              foregroundColor: provider.hasNextPage
                  ? AppColors.textOnPrimary
                  : AppColors.textDisabled,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
              elevation: 0,
              shadowColor: Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Siguiente",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: provider.hasNextPage
                        ? AppColors.textOnPrimary
                        : AppColors.textDisabled,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: provider.hasNextPage
                      ? AppColors.textOnPrimary
                      : AppColors.textDisabled,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}


  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final items = provider.items;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // 🔹 Header personalizado (igual al de tus otras pantallas)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowSm,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textSecondary,
                      size: 24,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    'Notificaciones',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // 🔹 Contenido principal
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => provider.refresh(page: provider.page, limit: provider.limit),
                color: AppColors.primary,
                backgroundColor: AppColors.surface,
                child: provider.loading && !provider.initialized
                    ? _buildLoadingState()
                    : items.isEmpty
                        ? _buildEmptyState()
                        : Column(
                            children: [
                              Expanded(
                                child: ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(16),
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final n = items[index];
                                    return NotificationTile(
                                      notification: n,
                                      index: index,
                                      onMarkAsRead: () {
                                        // Actualizar el estado local cuando se marca como leída
                                        setState(() {});
                                      },
                                    );
                                  },
                                ),
                              ),
                              
                              // 🔹 Controles de paginación con diseño profesional
                              _buildPaginationControls(provider),
                            ],
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationTile extends StatefulWidget {
  final NotificationItem notification;
  final int index;
  final VoidCallback onMarkAsRead;

  const NotificationTile({
    super.key,
    required this.notification,
    required this.index,
    required this.onMarkAsRead,
  });

  @override
  State<NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<NotificationTile> {
  late NotificationItem _notification;
  bool _isUnread = true;

  @override
  void initState() {
    super.initState();
    _notification = widget.notification;
    _isUnread = _notification.isUnread;
  }

  @override
  void didUpdateWidget(NotificationTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.notification != oldWidget.notification) {
      setState(() {
        _notification = widget.notification;
        _isUnread = _notification.isUnread;
      });
    }
  }

  String _formatRelative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} d';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Color _getNotificationColor(String type) {
    switch (type.toLowerCase()) {
      case 'warning':
      case 'alert':
        return AppColors.warning;
      case 'error':
      case 'danger':
        return AppColors.error;
      case 'success':
      case 'completed':
        return AppColors.successDark;
      case 'info':
      default:
        return AppColors.primary;
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type.toLowerCase()) {
      case 'warning':
      case 'alert':
        return Icons.warning_amber_rounded;
      case 'error':
      case 'danger':
        return Icons.error_outline_rounded;
      case 'success':
      case 'completed':
        return Icons.check_circle_outline_rounded;
      case 'info':
      default:
        return Icons.info_outline_rounded;
    }
  }

  // Método para marcar notificación como leída con actualización local inmediata
  Future<void> _markAsRead() async {
    if (!_isUnread) return;
    
    // 1. Actualizar estado local INMEDIATAMENTE
    setState(() {
      _isUnread = false;
    });
    
    // 2. Notificar al padre que se marcó como leída
    widget.onMarkAsRead();
    
    // 3. Enviar petición al backend
    try {
      final provider = context.read<NotificationProvider>();
      await provider.markAsRead(_notification.id);
    } catch (e) {
      // Si falla el backend, revertir estado local
      setState(() {
        _isUnread = true;
      });
      // Podrías mostrar un snackbar de error aquí si quieres
    }
  }

  @override
  Widget build(BuildContext context) {
    final notificationColor = _getNotificationColor(_notification.type ?? 'info');
    final notificationIcon = _getNotificationIcon(_notification.type ?? 'info');

    return GestureDetector(
      onTap: () async {
        // 🔹 Mostrar diálogo con contenido completo
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            title: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: notificationColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    notificationIcon,
                    color: notificationColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _notification.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _notification.body,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.borderDark,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceClean,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 16,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatRelative(_notification.createdAt),
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textTertiary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text(
                  "Cerrar",
                  style: TextStyle(fontSize: 14),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  // Marcar como leído antes de cerrar el diálogo
                  await _markAsRead();
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textOnPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: Text(
                  _isUnread ? "Marcar como leído" : "Leído",
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowMd,
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: _isUnread 
                ? notificationColor.withOpacity(0.3)
                : AppColors.border,
            width: _isUnread ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔹 Ícono de notificación
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _isUnread 
                    ? notificationColor.withOpacity(0.1)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isUnread 
                      ? notificationColor.withOpacity(0.3)
                      : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: Icon(
                notificationIcon,
                color: _isUnread ? notificationColor : AppColors.textDisabled,
                size: 20,
              ),
            ),
            
            const SizedBox(width: 16),
            
            // 🔹 Contenido de la notificación
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _notification.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: _isUnread ? FontWeight.w700 : FontWeight.w600,
                            color: _isUnread 
                                ? AppColors.textSecondary
                                : AppColors.borderDark,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      
                      if (_isUnread)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: notificationColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Nuevo',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: notificationColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  
                  const SizedBox(height: 6),
                  
                  Text(
                    _notification.body,
                    style: TextStyle(
                      fontSize: 13,
                      color: _isUnread 
                          ? AppColors.borderMedium
                          : AppColors.textTertiary,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  const SizedBox(height: 12),
                  
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: AppColors.textDisabled,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatRelative(_notification.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}