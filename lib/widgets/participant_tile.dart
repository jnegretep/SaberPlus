import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class ParticipantTile extends StatelessWidget {
  final Map<String, dynamic> participant;
  const ParticipantTile(this.participant, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final String name = participant['username'] ?? 'Usuario';
    final String status = participant['ready_status'] ?? 'esperando';
    final String invitation = participant['invitation_status'] ?? '';
    final bool accepted = invitation == 'aceptado';

    Color color;
    IconData icon;
    if (!accepted) {
      color = AppColors.textDisabled;
      icon = Icons.hourglass_empty;
    } else if (status == 'listo') {
      color = AppColors.success;
      icon = Icons.check_circle;
    } else if (status == 'esperando') {
      color = AppColors.warning;
      icon = Icons.access_time;
    } else {
      color = AppColors.textTertiary;
      icon = Icons.help_outline;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(icon, color: AppColors.textOnPrimary),
        ),
        title: Text(name),
        subtitle: Text('Invitación: $invitation | Estado: $status'),
      ),
    );
  }
}
