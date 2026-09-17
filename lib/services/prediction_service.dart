// lib/services/prediction_service.dart
// Saber+ - Servicio de prediccion ICFES y comparativa historica

import 'package:dio/dio.dart';
import '../core/services/dio_client.dart';
import '../core/utils/app_logger.dart';
import '../models/icfes_prediction.dart';

class PredictionService {
  /// Obtiene la prediccion ICFES, historico y analisis de areas.
  static Future<PredictionResponse?> getPrediction() async {
    try {
      final response = await DioClient.post('/icfes_prediction.php');
      if (response.statusCode != 200) return null;

      final data = response.data as Map<String, dynamic>;
      if (data['status'] != 'ok') return null;

      return PredictionResponse.fromJson(data);
    } on DioException catch (e) {
      AppLogger.e('PredictionService.getPrediction Dio error', e);
      return null;
    } catch (e) {
      AppLogger.e('PredictionService.getPrediction error', e);
      return null;
    }
  }
}
