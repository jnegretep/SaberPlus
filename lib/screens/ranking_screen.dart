import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/rank_stats.dart';
import '../services/api_service.dart';
import '../core/theme/app_colors.dart';

class RankingScreen extends StatefulWidget {
  final String area;   // "lectura", "matematicas", etc. o "global"
  final String scope;  // "national", "city", "dept", "school"

  const RankingScreen({
    super.key,
    required this.area,
    required this.scope,
  });

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  late Future<RankStats> _future;
  String _selectedScope = 'national';
  final List<Map<String, dynamic>> _scopes = [
    {'key': 'national', 'label': 'Nacional', 'icon': Icons.flag_rounded},
    {'key': 'dept', 'label': 'Departamento', 'icon': Icons.map_rounded},
    {'key': 'city', 'label': 'Ciudad', 'icon': Icons.location_city_rounded},
    {'key': 'school', 'label': 'Colegio', 'icon': Icons.school_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _selectedScope = widget.scope;
    _loadData();
  }

  void _loadData() {
    final api = context.read<ApiService>();
    _future = api.fetchRankStats(widget.area, _selectedScope);
  }

  Future<void> _refreshData() async {
    setState(() {
      _loadData();
    });
  }

  void _changeScope(String newScope) {
    setState(() {
      _selectedScope = newScope;
      _loadData();
    });
  }

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

  Color _getAreaColor(String area) {
    switch (area) {
      case 'lectura':
        return AppColors.primary;
      case 'matematicas':
        return AppColors.successDark;
      case 'sociales':
        return AppColors.purple;
      case 'naturales':
        return AppColors.warning;
      case 'ingles':
        return AppColors.error;
      case 'global':
        return AppColors.textSecondary;
      default:
        return AppColors.primary;
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
        return Icons.category_rounded;
    }
  }

  Widget _buildScopeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMd,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ámbito de ranking',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _scopes.map((scope) {
              final isSelected = _selectedScope == scope['key'];
              return GestureDetector(
                onTap: () => _changeScope(scope['key'] as String),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? _getAreaColor(widget.area) : AppColors.surfaceClean,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? _getAreaColor(widget.area) : AppColors.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        scope['icon'] as IconData,
                        size: 16,
                        color: isSelected ? AppColors.textOnPrimary : AppColors.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        scope['label'] as String,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? AppColors.textOnPrimary : AppColors.textTertiary,
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

  Widget _buildUserRankCard(RankStats stats) {
    final userPosition = stats.tuPosicion;
    final totalParticipants = stats.totalParticipantes ?? 0;
    final percentil = totalParticipants > 0 && userPosition != null
        ? ((totalParticipants - userPosition) / totalParticipants * 100).round()
        : null;

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
                  color: _getAreaColor(widget.area).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _getAreaColor(widget.area).withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  _getAreaIcon(widget.area),
                  color: _getAreaColor(widget.area),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ranking de ${_getAreaLabel(widget.area)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _scopes.firstWhere(
                        (s) => s['key'] == _selectedScope,
                        orElse: () => {'label': ''},
                      )['label'] as String,
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
          
          // Posición del usuario
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      userPosition?.toString() ?? '—',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        color: _getAreaColor(widget.area),
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tu posición',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: Column(
                  children: [
                    Text(
                      totalParticipants.toString(),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: AppColors.borderDark,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Participantes totales',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              
              if (percentil != null) ...[
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getAreaColor(widget.area).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Top $percentil%',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _getAreaColor(widget.area),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Percentil',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          
          if (userPosition != null && userPosition > 3) ...[
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: totalParticipants > 0 ? userPosition / totalParticipants : 0,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(_getAreaColor(widget.area)),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              'Avance en el ranking: $userPosition de $totalParticipants',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopList(RankStats stats) {
    if (stats.top.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(
              Icons.leaderboard_outlined,
              size: 48,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 12),
            const Text(
              'No hay datos de ranking disponibles',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.borderDark,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Completa más simulacros para aparecer en el ranking',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMd,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top 10 del Ranking',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ...stats.top.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final isTop3 = index < 3;
            
            final promedioNum = (item['promedio'] is num)
                ? (item['promedio'] as num).toDouble()
                : double.tryParse(item['promedio']?.toString() ?? '');
            final promedioStr = promedioNum != null
                ? promedioNum.toStringAsFixed(1)
                : '-';

            final nombre = item['nombre']?.toString();
            final avatarUrl = item['avatar']?.toString();
            final usuarioId = item['usuario_id']?.toString();

            // Colores para los primeros 3 puestos
            Color podiumColor;
            switch (index) {
              case 0:
                podiumColor = AppColors.gold; // Oro
                break;
              case 1:
                podiumColor = AppColors.silver; // Plata
                break;
              case 2:
                podiumColor = AppColors.bronze; // Bronce
                break;
              default:
                podiumColor = AppColors.surfaceVariant;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isTop3 ? podiumColor : AppColors.border,
                  width: isTop3 ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowMd,
                    blurRadius: isTop3 ? 8 : 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Número de posición
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isTop3 ? podiumColor : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                      border: isTop3 ? Border.all(color: podiumColor, width: 2) : null,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isTop3 ? AppColors.textOnPrimary : AppColors.borderDark,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Avatar
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.surfaceVariant,
                    backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: (avatarUrl == null || avatarUrl.isEmpty)
                        ? Text(
                            (nombre?.isNotEmpty == true
                                    ? nombre![0]
                                    : usuarioId?[0] ?? '?')
                                .toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textTertiary,
                            ),
                          )
                        : null,
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Información del usuario
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre?.isNotEmpty == true
                              ? nombre!
                              : 'Usuario ${usuarioId ?? 'Desconocido'}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isTop3 ? podiumColor : AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Puntaje: $promedioStr',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Indicador de podio
                  if (isTop3)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: podiumColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.emoji_events_rounded,
                            size: 12,
                            color: podiumColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            index == 0 ? '1°' : index == 1 ? '2°' : '3°',
                            style: TextStyle(
                              fontSize: 11,
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
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildEligibilityMessage(RankStats stats) {
    final eligibility = stats.eligibility;
    if (eligibility.isEmpty || eligibility['cumple'] == true) {
      return const SizedBox();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.errorFaint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.errorFg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.errorDark,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Requisitos no cumplidos',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.errorDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            eligibility['mensaje']?.toString() ?? 
            'Necesitas completar más simulacros para aparecer en el ranking.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.errorDeep,
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
        child: Column(
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
                  const SizedBox(width: 8),
                  const Text(
                    'Ranking de Desempeño',
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
                onRefresh: _refreshData,
                color: _getAreaColor(widget.area),
                backgroundColor: AppColors.surface,
                child: FutureBuilder<RankStats>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.errorFg),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 48,
                                color: AppColors.errorDark,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Error al cargar ranking',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.errorDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                snapshot.error.toString(),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.errorDeep,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _refreshData,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.errorDark,
                                  foregroundColor: AppColors.textOnPrimary,
                                ),
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Center(
                        child: Text('No hay datos disponibles'),
                      );
                    }

                    final stats = snapshot.data!;
                    
                    // Verificar elegibilidad
                    final eligibility = stats.eligibility;
                    if (eligibility.isEmpty || eligibility['cumple'] != true) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildScopeSelector(),
                            const SizedBox(height: 24),
                            _buildEligibilityMessage(stats),
                          ],
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Selector de ámbito
                          _buildScopeSelector(),
                          
                          const SizedBox(height: 24),
                          
                          // Tarjeta de posición del usuario
                          _buildUserRankCard(stats),
                          
                          const SizedBox(height: 24),
                          
                          // Lista del top 10
                          _buildTopList(stats),
                          
                          const SizedBox(height: 32),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}