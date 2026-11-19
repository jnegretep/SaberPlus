import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/context_stats.dart';
import '../services/api_service.dart';
import '../core/theme/app_colors.dart';

class ComparativasScreen extends StatefulWidget {
  final String area; // "lectura", "matematicas", etc. o "global"
  final String scope; // "city", "dept", "school", "national"

  const ComparativasScreen({
    super.key,
    required this.area,
    required this.scope,
  });

  @override
  State<ComparativasScreen> createState() => _ComparativasScreenState();
}

class _ComparativasScreenState extends State<ComparativasScreen> {
  late Future<ContextStats> _future;
  String _selectedScope = 'national';
  final List<Map<String, dynamic>> _scopes = [
    {'key': 'national', 'label': 'Nacional', 'icon': Icons.flag_rounded},
    {'key': 'dept', 'label': 'Departamento', 'icon': Icons.map_rounded},
    {'key': 'city', 'label': 'Ciudad', 'icon': Icons.location_city_rounded},
    {'key': 'school', 'label': 'Colegio', 'icon': Icons.school_rounded},
  ];

  String _getAreaLabel(String area) {
    switch (area) {
      case 'lectura':
        return 'Lectura';
      case 'matematicas':
        return 'Matemáticas';
      case 'sociales':
        return 'Sociales';
      case 'naturales':
        return 'Naturales';
      case 'ingles':
        return 'Inglés';
      case 'global':
        return 'Global';
      default:
        return area;
    }
  }

  IconData _getAreaIcon(String area) {
    switch (area) {
      case 'lectura':
        return Icons.menu_book_rounded;
      case 'matematicas':
        return Icons.calculate_rounded;
      case 'sociales':
        return Icons.public_rounded;
      case 'naturales':
        return Icons.eco_rounded;
      case 'ingles':
        return Icons.language_rounded;
      case 'global':
        return Icons.bar_chart_rounded;
      default:
        return Icons.assessment_rounded;
    }
  }

  Color _getAreaColor(String area) {
    switch (area) {
      case 'lectura':
        return AppColors.primary;
      case 'matematicas':
        return AppColors.primaryLight;
      case 'sociales':
        return AppColors.successDark;
      case 'naturales':
        return AppColors.purple;
      case 'ingles':
        return AppColors.warning;
      case 'global':
        return AppColors.primary;
      default:
        return AppColors.primary;
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedScope = widget.scope;
    final api = context.read<ApiService>();
    _future = api.fetchContextStats(widget.area, _selectedScope);
  }

  void _reloadScope(String newScope) {
    setState(() {
      _selectedScope = newScope;
      final api = context.read<ApiService>();
      _future = api.fetchContextStats(widget.area, _selectedScope);
    });
  }

  Widget _buildScopeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selecciona el ámbito de comparación',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _scopes.map((scope) {
              final isSelected = _selectedScope == scope['key'];
              return GestureDetector(
                onTap: () => _reloadScope(scope['key']),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.surfaceClean,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: 1.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        scope['icon'],
                        size: 20,
                        color: isSelected ? AppColors.textOnPrimary : AppColors.textTertiary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        scope['label'],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? AppColors.textOnPrimary : AppColors.borderDark,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCard(
      double userScore, double segmentScore, String scopeLabel, int sampleSize) {
    final difference = userScore - segmentScore;
    final differencePercent = segmentScore > 0 ? (difference / segmentScore * 100) : 0;
    final isAbove = difference > 0;
    final isEqual = difference == 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Encabezado
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.compare_arrows_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Comparativa $scopeLabel',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Basado en $sampleSize estudiantes',
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

          const SizedBox(height: 20),
          Divider(color: AppColors.border),
          const SizedBox(height: 16),

          // Puntajes comparativos
          Row(
            children: [
              Expanded(
                child: _buildScoreCard(
                  title: 'Tu puntaje',
                  score: userScore,
                  color: AppColors.primary,
                  icon: Icons.person_rounded,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildScoreCard(
                  title: 'Promedio $scopeLabel',
                  score: segmentScore,
                  color: AppColors.textDisabled,
                  icon: Icons.group_rounded,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Diferencia
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isAbove
                  ? AppColors.successLight
                  : isEqual
                      ? AppColors.surfaceVariant
                      : AppColors.errorFaint,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isAbove
                    ? AppColors.successDark
                    : isEqual
                        ? AppColors.border
                        : AppColors.errorFg,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isAbove
                        ? AppColors.successDark
                        : isEqual
                            ? AppColors.textDisabled
                            : AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isAbove
                        ? Icons.arrow_upward_rounded
                        : isEqual
                            ? Icons.remove_rounded
                            : Icons.arrow_downward_rounded,
                    color: AppColors.textOnPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAbove
                            ? 'Por encima del promedio'
                            : isEqual
                                ? 'En el promedio'
                                : 'Por debajo del promedio',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isAbove
                              ? AppColors.successDeep
                              : isEqual
                                  ? AppColors.borderDark
                                  : AppColors.errorDeep,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${difference > 0 ? '+' : ''}${difference.toStringAsFixed(1)} puntos '
                        '(${differencePercent > 0 ? '+' : ''}${differencePercent.abs().toStringAsFixed(1)}%)',
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

          const SizedBox(height: 20),

          // Gráfico de barras comparativo
          _buildComparisonBarChart(userScore, segmentScore),
        ],
      ),
    );
  }

Widget _buildScoreCard({
  required String title,
  required double score,
  required Color color,
  required IconData icon,
}) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surfaceClean,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min, // evita que la columna fuerce altura extra
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis, // corta si no cabe
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            score.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'puntos',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textDisabled,
          ),
        ),
      ],
    ),
  );
}


  Widget _buildComparisonBarChart(double userScore, double segmentScore) {
    final maxScore = userScore > segmentScore ? userScore * 1.2 : segmentScore * 1.2;
    final userPercentage = maxScore > 0 ? (userScore / maxScore) : 0;
    final segmentPercentage = maxScore > 0 ? (segmentScore / maxScore) : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Visualización comparativa',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),

        // Barra del usuario
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tu puntaje',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.borderDark,
                    ),
                  ),
                  Text(
                    userScore.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 24,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.surfaceVariant,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: MediaQuery.of(context).size.width * userPercentage * 0.8,
                    height: 24,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryLight],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Barra del segmento
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Promedio del ámbito',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.borderDark,
                  ),
                ),
                Text(
                  segmentScore.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 24,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppColors.surfaceVariant,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: MediaQuery.of(context).size.width * segmentPercentage * 0.8,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.textDisabled, AppColors.textSubtle],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Escala
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '0',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
            Text(
              (maxScore / 2).toStringAsFixed(0),
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
            Text(
              maxScore.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPercentileCard(int? percentile, ContextStats stats) {
    if (percentile == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceClean,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.help_outline_rounded,
              color: AppColors.textDisabled,
              size: 48,
            ),
            SizedBox(height: 12),
            Text(
              'Percentil no disponible',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    // Definir tipos explícitos para evitar errores de Object
    final Map<String, dynamic> percentileCategory = percentile >= 90
        ? {
            'label': 'Excelente', 
            'color': AppColors.successDark, 
            'icon': Icons.emoji_events_rounded
          }
        : percentile >= 70
            ? {
                'label': 'Bueno', 
                'color': AppColors.primaryLight, 
                'icon': Icons.thumb_up_rounded
              }
            : percentile >= 40
                ? {
                    'label': 'Promedio', 
                    'color': AppColors.warning, 
                    'icon': Icons.equalizer_rounded
                  }
                : {
                    'label': 'Por mejorar', 
                    'color': AppColors.error, 
                    'icon': Icons.trending_up_rounded
                  };

    // Extraer valores con tipos correctos
    final Color categoryColor = percentileCategory['color'] as Color;
    final IconData categoryIcon = percentileCategory['icon'] as IconData;
    final String categoryLabel = percentileCategory['label'] as String;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: categoryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  categoryIcon,
                  color: categoryColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Percentil $percentile',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Superas al $percentile% de estudiantes',
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

          const SizedBox(height: 20),
          Divider(color: AppColors.border),
          const SizedBox(height: 16),

          // Indicador visual del percentil
          Stack(
            children: [
              Container(
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              Container(
                height: 12,
                width: MediaQuery.of(context).size.width * (percentile / 100),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary,
                      categoryColor,
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              Positioned(
                left: MediaQuery.of(context).size.width * (percentile / 100) - 8,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: categoryColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.textOnPrimary, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadowLg,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Información adicional
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceClean,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  categoryIcon,
                  color: categoryColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Estás en el rango "$categoryLabel"',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: categoryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (stats.preliminar == true) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.warning,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Estos datos son preliminares (n=${stats.n})',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.warningDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAreaInfoCard() {
    final areaColor = _getAreaColor(widget.area);
    final areaLabel = _getAreaLabel(widget.area);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: areaColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: areaColor.withOpacity(0.3), width: 1.5),
            ),
            child: Icon(
              _getAreaIcon(widget.area),
              color: areaColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Comparativa de $areaLabel',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Analiza tu desempeño en comparación con otros estudiantes',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FutureBuilder<ContextStats>(
          future: _future,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              );
            }

            if (snap.hasError) {
              return Column(
                children: [
                  // Header
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
                          'Comparativas',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.all(24),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.errorFaint,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.errorFg),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: AppColors.errorDark,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Error al cargar datos',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.errorDeep,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              snap.error.toString(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            final stats = snap.data!;
            if (stats.segmentoPromedio == null) {
              return Column(
                children: [
                  // Header
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
                          'Comparativas',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.all(24),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.shadowSm,
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.insights_rounded,
                              color: AppColors.textDisabled,
                              size: 64,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Datos insuficientes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.borderDark,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'No hay suficientes datos para esta comparativa',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            final selectedScope = _scopes.firstWhere(
              (s) => s['key'] == _selectedScope,
              orElse: () => _scopes[0],
            );

            return Column(
              children: [
                // Header
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
                        'Comparativas',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Contenido
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => _reloadScope(_selectedScope),
                    color: AppColors.primary,
                    backgroundColor: AppColors.surface,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Tarjeta informativa del área
                          _buildAreaInfoCard(),

                          const SizedBox(height: 20),

                          // Selector de ámbito
                          _buildScopeSelector(),

                          const SizedBox(height: 20),

                          // Tarjeta de comparación
                          _buildComparisonCard(
                            stats.tuPromedio ?? 0,
                            stats.segmentoPromedio ?? 0,
                            selectedScope['label'],
                            stats.n ?? 0,
                          ),

                          const SizedBox(height: 20),

                          // Tarjeta de percentil
                          _buildPercentileCard(stats.percentil?.toInt(), stats),

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}