import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class PodiumWidget extends StatelessWidget {
  final List<Map<String, dynamic>> ranking;
  final double? maxWidth;

  const PodiumWidget({
    Key? key,
    required this.ranking,
    this.maxWidth,
  }) : super(key: key);

  String _formatScore(dynamic score) {
    if (score == null) return '0.00';
    final value = score is num ? score.toDouble() : double.tryParse(score.toString()) ?? 0.0;
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    // Tomar los primeros 3 o menos para el podio
    final topParticipants = ranking.take(3).toList();
    
    if (topParticipants.isEmpty) {
      return Container();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = maxWidth ?? constraints.maxWidth;
          final isSmallScreen = availableWidth < 350;
          
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '🏆 Podio del Reto',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              
              // Podio visual con dimensiones adaptativas
              _buildAdaptivePodium(topParticipants, isSmallScreen),
              
              // Indicador si hay menos de 3 participantes
              if (ranking.length < 3)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '${ranking.length} participante(s) en total',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAdaptivePodium(List<Map<String, dynamic>> participants, bool isSmallScreen) {
    final int count = participants.length;
    
    // Dimensiones adaptativas
    final double firstWidth = isSmallScreen ? 90 : 110;
    final double secondWidth = isSmallScreen ? 80 : 90;
    final double thirdWidth = isSmallScreen ? 80 : 90;
    final double spacing = isSmallScreen ? 8 : 12;
    
    final double firstHeight = isSmallScreen ? 100 : 120;
    final double secondHeight = isSmallScreen ? 80 : 90;
    final double thirdHeight = isSmallScreen ? 60 : 70;

    if (count == 1) {
      return Center(
        child: _buildPodiumItem(
          participant: participants[0],
          place: 1,
          podiumHeight: firstHeight,
          podiumWidth: firstWidth,
          podiumColor: AppColors.gold,
          medalColor: AppColors.warningText,
          isFirst: true,
        ),
      );
    } else if (count == 2) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPodiumItem(
            participant: participants[1],
            place: 2,
            podiumHeight: secondHeight,
            podiumWidth: secondWidth,
            podiumColor: AppColors.silver,
            medalColor: AppColors.statusDefault,
            isFirst: false,
          ),
          SizedBox(width: spacing),
          _buildPodiumItem(
            participant: participants[0],
            place: 1,
            podiumHeight: firstHeight,
            podiumWidth: firstWidth,
            podiumColor: AppColors.gold,
            medalColor: AppColors.warningText,
            isFirst: true,
          ),
          SizedBox(width: spacing),
          // Espacio vacío para mantener simetría
          Container(
            width: secondWidth,
            height: secondHeight,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
          ),
        ],
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPodiumItem(
            participant: participants[1],
            place: 2,
            podiumHeight: secondHeight,
            podiumWidth: secondWidth,
            podiumColor: AppColors.silver,
            medalColor: AppColors.statusDefault,
            isFirst: false,
          ),
          SizedBox(width: spacing),
          _buildPodiumItem(
            participant: participants[0],
            place: 1,
            podiumHeight: firstHeight,
            podiumWidth: firstWidth,
            podiumColor: AppColors.gold,
            medalColor: AppColors.warningText,
            isFirst: true,
          ),
          SizedBox(width: spacing),
          _buildPodiumItem(
            participant: participants[2],
            place: 3,
            podiumHeight: thirdHeight,
            podiumWidth: thirdWidth,
            podiumColor: AppColors.bronze,
            medalColor: AppColors.warningDark,
            isFirst: false,
          ),
        ],
      );
    }
  }

  Widget _buildPodiumItem({
    required Map<String, dynamic> participant,
    required int place,
    required double podiumHeight,
    required double podiumWidth,
    required Color podiumColor,
    required Color medalColor,
    required bool isFirst,
  }) {
    final nombre = participant['nombre']?.toString() ?? '—';
    final score = participant['score'];
    final avatarUrl = participant['avatar_url']?.toString();

    return Container(
      width: podiumWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Base del podio
          Container(
            width: podiumWidth,
            height: podiumHeight,
            decoration: BoxDecoration(
              color: podiumColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Center(
              child: Text(
                '$place°',
                style: TextStyle(
                  fontSize: isFirst ? 16 : 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textOnPrimary,
                ),
              ),
            ),
          ),
          
          // Contenedor del participante
          Container(
            width: podiumWidth - 10,
            margin: const EdgeInsets.only(bottom: 10),
            transform: Matrix4.translationValues(0, -20, 0),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadowLg,
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: podiumColor.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Medalla
                Container(
                  width: isFirst ? 40 : 36,
                  height: isFirst ? 40 : 36,
                  decoration: BoxDecoration(
                    color: medalColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.surface,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$place',
                      style: TextStyle(
                        fontSize: isFirst ? 18 : 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                
                // Avatar o inicial
                if (avatarUrl != null && avatarUrl.isNotEmpty)
                  CircleAvatar(
                    radius: isFirst ? 18 : 16,
                    backgroundImage: NetworkImage(avatarUrl),
                  )
                else
                  Container(
                    width: isFirst ? 32 : 28,
                    height: isFirst ? 32 : 28,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        nombre[0].toUpperCase(),
                        style: TextStyle(
                          fontSize: isFirst ? 14 : 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                
                const SizedBox(height: 6),
                
                // Nombre
                Text(
                  nombre.length > 8 ? '${nombre.substring(0, 8)}...' : nombre,
                  style: TextStyle(
                    fontSize: isFirst ? 12 : 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                
                const SizedBox(height: 2),
                
                // Puntaje
                Text(
                  '${_formatScore(score)} pts',
                  style: TextStyle(
                    fontSize: isFirst ? 11 : 10,
                    fontWeight: FontWeight.w700,
                    color: podiumColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}