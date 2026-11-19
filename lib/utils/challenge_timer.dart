// lib/utils/challenge_timer.dart
import 'dart:async';
import '../core/utils/app_logger.dart';

class ChallengeTimer {
  Timer? _countdownTimer;
  Timer? _syncTimer;
  int _remainingSeconds = 0;
  int _challengeId;
  final Function(int) onTick;
  final Function() onComplete;
  final Future<Map<String, dynamic>> Function(int) fetchTime;
  
  // Para corrección de desfase
  int _timeOffset = 0;
  bool _isSyncing = false;
  
  ChallengeTimer({
    required this._challengeId,
    required this.onTick,
    required this.onComplete,
    required this.fetchTime,
  });
  
  // Inicializar con tiempo del servidor
  Future<void> initialize() async {
    await _syncWithServer();
    _startSyncTimer();
  }
  
  Future<void> _syncWithServer() async {
    if (_isSyncing) return;
    _isSyncing = true;
    
    try {
      final response = await fetchTime(_challengeId);
      
      if (response['status'] == 'ok') {
        final challenge = response['challenge'];
        final serverRemaining = challenge['remaining_seconds'] ?? 0;
        
        // Calcular desfase
        final serverTime = response['server_time'];
        final localTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        _timeOffset = localTime - serverTime;
        
        // Actualizar tiempo restante (usando el del servidor)
        _remainingSeconds = serverRemaining;
        
        // Si el tiempo cambió significativamente (> 5 segundos), reiniciar timer
        if (_countdownTimer != null && 
            _remainingSeconds > 0 && 
            (_remainingSeconds - _getLocalRemaining()).abs() > 5) {
          _startCountdown();
        }
      }
    } catch (e) {
      AppLogger.e('Error sincronizando tiempo', e);
      // Continuar con tiempo local en caso de error
    } finally {
      _isSyncing = false;
    }
  }
  
  void _startCountdown() {
    _countdownTimer?.cancel();
    
    _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        timer.cancel();
        onComplete();
      } else {
        _remainingSeconds--;
        onTick(_remainingSeconds);
      }
    });
  }
  
  void _startSyncTimer() {
    _syncTimer?.cancel();
    
    // Sincronizar cada 20 segundos
    _syncTimer = Timer.periodic(Duration(seconds: 20), (timer) async {
      await _syncWithServer();
      
      // Si el tiempo se acabó según el servidor, detener
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _countdownTimer?.cancel();
        onComplete();
      }
    });
  }
  
  int _getLocalRemaining() {
    return _remainingSeconds;
  }
  
  String formatTime() {
    final minutes = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
  
  void pause() {
    _countdownTimer?.cancel();
    _syncTimer?.cancel();
  }
  
  void resume() {
    if (_remainingSeconds > 0) {
      _startCountdown();
      _startSyncTimer();
    }
  }
  
  void dispose() {
    _countdownTimer?.cancel();
    _syncTimer?.cancel();
  }
  
  int get remainingSeconds => _remainingSeconds;
}