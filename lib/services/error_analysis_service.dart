// lib/services/error_analysis_service.dart
// Saber+ - Servicio de analisis de errores

import 'package:dio/dio.dart';
import '../core/services/dio_client.dart';
import '../core/utils/app_logger.dart';
import '../models/error_analysis.dart';

class ErrorAnalysisService {
  static Future<ErrorAnalysisResponse?> getAnalysis() async {
    try {
      final response = await DioClient.post('/error_analysis.php');
      if (response.statusCode != 200) return null;

      final data = response.data as Map<String, dynamic>;
      if (data['status'] != 'ok') return null;

      return ErrorAnalysisResponse.fromJson(data);
    } on DioException catch (e) {
      AppLogger.e('ErrorAnalysisService.getAnalysis Dio error', e);
      return null;
    } catch (e) {
      AppLogger.e('ErrorAnalysisService.getAnalysis error', e);
      return null;
    }
  }
}
