import 'package:flutter/material.dart';
import '../models/notification_item.dart';
import '../core/theme/app_colors.dart';

class NotificationTile extends StatelessWidget {
  final NotificationItem notification;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;

  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
    this.onDismiss,
  });

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'reto_invitacion':
        return AppColors.primary;
      case 'reto_aceptado':
        return AppColors.successDark;
      case 'reto_rechazado':
        return AppColors.error;
      case 'reto_eliminado':
        return AppColors.warning;
      case 'reto_creado':
        return AppColors.purple;
      case 'reto_10min':
      case 'reto_5min':
        return AppColors.purple; // Pink ≈ purple for notifications
      case 'inactividad':
        return AppColors.textTertiary;
      case 'simulacro_en_curso':
        return AppColors.sky; // Cyan ≈ sky for notifications
      default:
        return AppColors.primary;
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'reto_invitacion':
        return Icons.assignment_turned_in;
      case 'reto_aceptado':
        return Icons.check_circle;
      case 'reto_rechazado':
        return Icons.cancel;
      case 'reto_eliminado':
        return Icons.delete;
      case 'reto_creado':
        return Icons.add_circle;
      case 'reto_10min':
      case 'reto_5min':
        return Icons.access_time;
      case 'inactividad':
        return Icons.timeline;
      case 'simulacro_en_curso':
        return Icons.quiz;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUnread = notification.isUnread;
    final notificationColor = _getNotificationColor(notification.type);
    final notificationIcon = _getNotificationIcon(notification.type);

    return GestureDetector(
      onTap: onTap,
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
            color: isUnread 
                ? notificationColor.withOpacity(0.3)
                : AppColors.border,
            width: isUnread ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ícono de notificación
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isUnread 
                    ? notificationColor.withOpacity(0.1)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isUnread 
                      ? notificationColor.withOpacity(0.3)
                      : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: Icon(
                notificationIcon,
                color: isUnread ? notificationColor : AppColors.textDisabled,
                size: 20,
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Contenido de la notificación
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notification.displayTitle,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                            color: isUnread 
                                ? AppColors.textSecondary
                                : AppColors.borderDark,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      
                      if (isUnread)
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
                  
                  // Mostrar remitente si existe
                  if (notification.senderInfo.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        notification.senderInfo,
                        style: TextStyle(
                          fontSize: 12,
                          color: isUnread 
                              ? AppColors.borderMedium
                              : AppColors.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  
                  Text(
                    notification.displayBody,
                    style: TextStyle(
                      fontSize: 13,
                      color: isUnread 
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
                        notification.formattedDate,
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