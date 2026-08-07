// lib/widgets/loading_retry_widget.dart
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class LoadingRetryWidget extends StatelessWidget {
  final bool isLoading;
  final bool hasError;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final Widget child;
  
  const LoadingRetryWidget({
    super.key,
    required this.isLoading,
    required this.hasError,
    this.errorMessage,
    this.onRetry,
    required this.child,
  });
  
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _buildLoading();
    }
    
    if (hasError) {
      return _buildError(context);
    }
    
    return child;
  }
  
  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            strokeWidth: 2.5,
          ),
          const SizedBox(height: 16),
          Text(
            'Cargando...',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.errorFg,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                color: AppColors.errorDark,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Error al cargar',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage ?? 'Ocurrió un error inesperado',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            if (onRetry != null)
              ElevatedButton.icon(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textOnPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                icon: Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reintentar'),
              ),
          ],
        ),
      ),
    );
  }
}