// lib/services/gamification_service.dart
// Saber+ — Servicio de gamificación (XP, niveles, rachas, badges, ranking)
//
// Habla con los endpoints del backend:
// - /gamification_status.php   → estado completo del usuario
// - /gamification_award_xp.php → otorgar XP por una acción
// - /gamification_ranking.php  → ranking de usuarios

import 'package:dio/dio.dart';
import '../core/services/dio_client.dart';
import '../core/utils/app_logger.dart';
import '../models/gamification_state.dart';
import '../models/ranking_entry.dart';

class GamificationService {
  /// Obtiene el estado completo de gamificación del usuario autenticado.
  ///
  /// Incluye: XP total, nivel actual, racha, badges (desbloqueados y bloqueados),
  /// y actividad de hoy.
  Future<GamificationState?> getStatus() async {
    try {
      final response = await DioClient.post('/gamification_status.php');
      if (response.statusCode != 200) return null;

      final data = response.data as Map<String, dynamic>;
      if (data['status'] != 'ok') return null;

      return GamificationState.fromJson(data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      AppLogger.e('GamificationService.getStatus Dio error', e);
      return null;
    } catch (e) {
      AppLogger.e('GamificationService.getStatus error', e);
      return null;
    }
  }

  /// Otorga XP al usuario por completar una acción.
  ///
  /// [reason] debe ser uno de: 'simulacro', 'reto', 'curso', 'daily_login',
  /// 'streak_bonus', 'manual'.
  ///
  /// Si [xpAmount] no se especifica, el backend lo calcula automáticamente
  /// según el [reason].
  ///
  /// Retorna [AwardXpResult] con info sobre XP ganada, nivel subido, badges
  /// desbloqueados, etc.
  Future<AwardXpResult?> awardXp({
    required String reason,
    int? xpAmount,
    int? referenceId,
    String? description,
  }) async {
    try {
      final body = <String, dynamic>{'reason': reason};
      if (xpAmount != null) body['xp_amount'] = xpAmount;
      if (referenceId != null) body['reference_id'] = referenceId;
      if (description != null) body['description'] = description;

      final response = await DioClient.post(
        '/gamification_award_xp.php',
        data: body,
      );
      if (response.statusCode != 200) return null;

      final data = response.data as Map<String, dynamic>;
      if (data['status'] != 'ok') return null;

      return AwardXpResult.fromJson(data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      AppLogger.e('GamificationService.awardXp Dio error', e);
      return null;
    } catch (e) {
      AppLogger.e('GamificationService.awardXp error', e);
      return null;
    }
  }

  /// Obtiene el ranking de usuarios.
  ///
  /// [period] puede ser: 'all_time', 'weekly', 'monthly'.
  /// [limit] es el número máximo de entradas a devolver (default 50, max 200).
  Future<RankingResponse?> getRanking({
    String period = 'all_time',
    int limit = 50,
  }) async {
    try {
      final response = await DioClient.post(
        '/gamification_ranking.php',
        data: {'period': period, 'limit': limit},
      );
      if (response.statusCode != 200) return null;

      final data = response.data as Map<String, dynamic>;
      if (data['status'] != 'ok') return null;

      return RankingResponse.fromJson(data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      AppLogger.e('GamificationService.getRanking Dio error', e);
      return null;
    } catch (e) {
      AppLogger.e('GamificationService.getRanking error', e);
      return null;
    }
  }
}
