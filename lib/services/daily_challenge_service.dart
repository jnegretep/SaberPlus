// lib/services/daily_challenge_service.dart
// Saber+ — Servicio de Retos Diarios

import 'package:dio/dio.dart';
import '../core/services/dio_client.dart';
import '../core/utils/app_logger.dart';
import '../models/daily_challenge.dart';

class DailyChallengeService {
  /// Obtiene los retos diarios disponibles para el usuario.
  static Future<DailyChallengesResponse?> getDailyChallenges() async {
    try {
      final response = await DioClient.post('/daily_challenges.php');
      if (response.statusCode != 200) return null;

      final data = response.data as Map<String, dynamic>;
      if (data['status'] != 'ok') return null;

      return DailyChallengesResponse.fromJson(data);
    } on DioException catch (e) {
      AppLogger.e('DailyChallengeService.getDailyChallenges Dio error', e);
      return null;
    } catch (e) {
      AppLogger.e('DailyChallengeService.getDailyChallenges error', e);
      return null;
    }
  }
}
