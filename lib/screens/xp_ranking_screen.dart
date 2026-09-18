// lib/screens/xp_ranking_screen.dart
// Saber+ — Pantalla de Ranking de XP (gamificación) v1.6.0
//
// Muestra el ranking por XP con dos dimensiones:
//  A) Estudiantes (v1.5): histórico / mensual / semanal
//  B) Institucional (v1.6.0): ranking de COLEGIOS y DEPARTAMENTOS
//     por XP acumulada de sus estudiantes — con posición de la
//     institución propia destacada.
//
// Características:
// - Selector de tipo (Estudiantes / Colegios / Departamentos)
// - Podio animado para los top 3 (oro, plata, bronce)
// - Lista de los siguientes lugares
// - Tarjeta del usuario / institución actual
// - Compartir posición en redes sociales (v1.6.0)
// - Pull-to-refresh + shimmer loading

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme/app_colors.dart';
import '../core/animations/app_animations.dart';
import '../core/animations/shimmer_loading.dart';
import '../core/utils/app_logger.dart';
import '../providers/gamification_provider.dart';
import '../models/ranking_entry.dart';
import '../config/env.dart';
import '../services/share_service.dart';

class XpRankingScreen extends StatefulWidget {
  const XpRankingScreen({super.key});

  @override
  State<XpRankingScreen> createState() => _XpRankingScreenState();
}

class _XpRankingScreenState extends State<XpRankingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _selectedPeriod = 'all_time';
  RankingResponse? _rankingData;
  bool _isLoading = false;
  String? _error;

  // ✅ v1.6.0 — dimensión del ranking
  String _selectedType = 'estudiantes'; // 'estudiantes' | 'colegios' | 'departamentos'
  InstitutionRankingResponse? _instRankingData;

  final List<_PeriodTab> _periods = [
    _PeriodTab(key: 'all_time', label: 'Histórico', icon: Icons.emoji_events_rounded),
    _PeriodTab(key: 'monthly', label: 'Mensual', icon: Icons.calendar_month_rounded),
    _PeriodTab(key: 'weekly', label: 'Semanal', icon: Icons.date_range_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _periods.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final newPeriod = _periods[_tabController.index].key;
        if (newPeriod != _selectedPeriod) {
          setState(() {
            _selectedPeriod = newPeriod;
          });
          _loadRanking();
        }
      }
    });

    // Cargar ranking al iniciar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRanking();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRanking() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final gamif = context.read<GamificationProvider>();

      // ✅ v1.6.0 — dispatch según la dimensión seleccionada
      if (_selectedType == 'estudiantes') {
        final data = await gamif.getRanking(
          period: _selectedPeriod,
          limit: 50,
        );

        if (!mounted) return;

        setState(() {
          _rankingData = data;
          _isLoading = false;
        });

        AppLogger.i('Ranking cargado: período=$_selectedPeriod, '
            '${data?.ranking.length ?? 0} entradas, '
            'usuario en posición ${data?.userPosition ?? 'N/A'}');
      } else {
        final data = await gamif.getInstitutionRanking(
          tipo: _selectedType,
          period: _selectedPeriod,
          limit: 50,
        );

        if (!mounted) return;

        setState(() {
          _instRankingData = data;
          _isLoading = false;
        });

        AppLogger.i('Ranking institucional cargado: tipo=$_selectedType, '
            '${data?.ranking.length ?? 0} instituciones');
      }
    } catch (e) {
      AppLogger.e('Error cargando ranking', e);
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el ranking';
        _isLoading = false;
      });
    }
  }

  /// ✅ v1.6.0 — cambia la dimensión (estudiantes / colegios / departamentos)
  void _changeType(String newType) {
    if (newType == _selectedType) return;
    setState(() {
      _selectedType = newType;
    });
    _loadRanking();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── App Bar ──
            _buildAppBar(context, isDark),

            // ── v1.6.0: selector de dimensión ──
            _buildTypeSelector(isDark),

            // ── Tabs de período ──
            _buildPeriodTabs(isDark),

            // ── Contenido ──
            Expanded(
              child: _isLoading
                  ? _buildShimmer(isDark)
                  : _error != null
                      ? _buildError(isDark)
                      : RefreshIndicator(
                          onRefresh: _loadRanking,
                          color: AppColors.primary,
                          backgroundColor:
                              isDark ? AppColors.darkSurface : AppColors.surface,
                          child: _selectedType == 'estudiantes'
                              ? (_rankingData == null ||
                                      _rankingData!.ranking.isEmpty
                                  ? _buildEmptyState(isDark)
                                  : _buildRankingContent(isDark))
                              : (_instRankingData == null ||
                                      _instRankingData!.ranking.isEmpty
                                  ? _buildEmptyState(isDark)
                                  : _buildInstitutionContent(isDark)),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // WIDGETS DE SECCIONES
  // ═══════════════════════════════════════════════════

  Widget _buildAppBar(BuildContext context, bool isDark) {
    final bool esInstitucional = _selectedType != 'estudiantes';
    final String titulo = _selectedType == 'colegios'
        ? 'Ranking de Colegios'
        : _selectedType == 'departamentos'
            ? 'Ranking de Departamentos'
            : 'Ranking de XP';
    final String subtitulo = esInstitucional
        ? '${_instRankingData?.totalInstituciones ?? 0} '
            '${_selectedType == 'colegios' ? "colegios" : "departamentos"} compitiendo'
        : '${_rankingData?.totalUsers ?? 0} estudiantes compitiendo';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
            color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitulo,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),

          // ✅ v1.6.0: compartir posición
          IconButton(
            icon: Icon(
              Icons.share_rounded,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
            onPressed: _compartirPosicion,
            tooltip: 'Compartir mi posición',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadRanking,
            color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
          ),
        ],
      ),
    );
  }

  /// ✅ v1.6.0 — comparte la posición actual (estudiante o institución)
  Future<void> _compartirPosicion() async {
    if (_selectedType == 'estudiantes') {
      final data = _rankingData;
      if (data == null || data.userPosition <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aún no tienes posición en el ranking')),
        );
        return;
      }
      final gamif = context.read<GamificationProvider>();
      await ShareService.shareRankingPosition(
        posicion: data.userPosition,
        total: data.totalUsers,
        xp: gamif.state.totalXp,
        tipo: 'estudiantes',
      );
    } else {
      final data = _instRankingData;
      final mia = data?.miInstitucion;
      if (data == null || mia == null || mia.posicion <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_selectedType == 'colegios'
              ? 'Tu colegio aún no aparece en el ranking'
              : 'Tu departamento aún no aparece en el ranking')),
        );
        return;
      }
      await ShareService.shareRankingPosition(
        posicion: mia.posicion,
        total: data.totalInstituciones,
        xp: mia.totalXp ?? 0,
        tipo: _selectedType,
      );
    }
  }

  /// ✅ v1.6.0 — selector de dimensión del ranking.
  Widget _buildTypeSelector(bool isDark) {
    final tipos = [
      {'key': 'estudiantes', 'label': 'Estudiantes', 'icon': Icons.person_rounded},
      {'key': 'colegios', 'label': 'Colegios', 'icon': Icons.school_rounded},
      {'key': 'departamentos', 'label': 'Departamentos', 'icon': Icons.map_rounded},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final t in tipos)
            Expanded(
              child: GestureDetector(
                onTap: () => _changeType(t['key'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: EdgeInsets.only(
                      right: t['key'] != 'departamentos' ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _selectedType == t['key']
                        ? AppColors.primary.withOpacity(0.12)
                        : (isDark
                            ? AppColors.darkSurface
                            : AppColors.surface),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedType == t['key']
                          ? AppColors.primary
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        t['icon'] as IconData,
                        size: 16,
                        color: _selectedType == t['key']
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.textTertiary),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          t['label'] as String,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: _selectedType == t['key']
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: _selectedType == t['key']
                                ? AppColors.primary
                                : (isDark
                                    ? AppColors.darkTextTertiary
                                    : AppColors.textTertiary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPeriodTabs(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: AppColors.textOnPrimary,
        unselectedLabelColor:
            isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        tabs: _periods
            .map((p) => Tab(
                  icon: Icon(p.icon, size: 14),
                  text: p.label,
                  iconMargin: const EdgeInsets.only(bottom: 2),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildRankingContent(bool isDark) {
    final ranking = _rankingData!.ranking;
    final userPosition = _rankingData!.userPosition;

    return CustomScrollView(
      slivers: [
        // ── Podio (top 3) ──
        if (ranking.length >= 3)
          SliverToBoxAdapter(
            child: _buildPodium(ranking.sublist(0, 3), isDark),
          ),

        // ── Lista del resto (posición 4+) ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              ranking.length >= 3 ? 'Demás posiciones' : 'Ranking completo',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              // Si hay podio, empezamos desde la posición 3 (4to lugar)
              final rankIndex = ranking.length >= 3 ? index + 3 : index;
              if (rankIndex >= ranking.length) return null;
              return _buildRankTile(ranking[rankIndex], isDark);
            },
            childCount: ranking.length >= 3
                ? ranking.length - 3
                : ranking.length,
          ),
        ),

        // ── Tarjeta del usuario actual (si no está en la lista) ──
        if (userPosition > ranking.length)
          SliverToBoxAdapter(
            child: _buildUserCard(isDark),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  // v1.6.0 — CONTENIDO INSTITUCIONAL (colegios / departamentos)
  // ═══════════════════════════════════════════════════

  Widget _buildInstitutionContent(bool isDark) {
    final data = _instRankingData!;
    final ranking = data.ranking;

    return CustomScrollView(
      slivers: [
        // ── Podio institucional (top 3) ──
        if (ranking.length >= 3)
          SliverToBoxAdapter(
            child: _buildInstitutionPodium(
              [ranking[0], ranking[1], ranking[2]],
              isDark,
            ),
          ),

        // ── Lista del resto ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              ranking.length >= 3 ? 'Demás posiciones' : 'Ranking completo',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final rankIndex = ranking.length >= 3 ? index + 3 : index;
              if (rankIndex >= ranking.length) return null;
              return _buildInstitutionTile(ranking[rankIndex], isDark);
            },
            childCount: ranking.length >= 3
                ? ranking.length - 3
                : ranking.length,
          ),
        ),

        // ── Tarjeta de mi institución (si no está en el top) ──
        if (data.miInstitucion != null &&
            data.miInstitucion!.posicion > ranking.length)
          SliverToBoxAdapter(
            child: _buildMiInstitucionCard(isDark),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  /// Podio olímpico institucional: 2.º izq, 1.º centro, 3.º der.
  Widget _buildInstitutionPodium(
      List<InstitutionRankingEntry> top3, bool isDark) {
    final second = top3[1];
    final first = top3[0];
    final third = top3[2];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AppColors.darkSurface, AppColors.darkSurfaceVariant]
              : [AppColors.surface, AppColors.surfaceVariant],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2do lugar
          _buildInstitutionPodiumColumn(
            second, 66, const Color(0xFFC0C0C0), '2', isDark,
            key: const ValueKey('inst-second'),
          ),
          // 1er lugar
          _buildInstitutionPodiumColumn(
            first, 86, const Color(0xFFFFD700), '1', isDark,
            key: const ValueKey('inst-first'),
          ),
          // 3er lugar
          _buildInstitutionPodiumColumn(
            third, 54, const Color(0xFFCD7F32), '3', isDark,
            key: const ValueKey('inst-third'),
          ),
        ],
      ),
    );
  }

  Widget _buildInstitutionPodiumColumn(
    InstitutionRankingEntry entry,
    double altura,
    Color colorMedalla,
    String lugar,
    bool isDark, {
    Key? key,
  }) {
    return SizedBox(
      key: key,
      width: 104,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar de la institución
          Container(
            width: lugar == '1' ? 52 : 44,
            height: lugar == '1' ? 52 : 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [colorMedalla, colorMedalla.withOpacity(0.6)],
              ),
              boxShadow: [
                BoxShadow(
                  color: colorMedalla.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                _selectedType == 'colegios'
                    ? Icons.school_rounded
                    : Icons.map_rounded,
                color: Colors.white,
                size: lugar == '1' ? 26 : 22,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.nombre,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: lugar == '1' ? 12 : 10.5,
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatXp(entry.totalXp),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          // Base del podio
          Container(
            height: altura,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorMedalla.withOpacity(0.85),
                  colorMedalla.withOpacity(0.55),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Center(
              child: Text(
                lugar,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tile de institución en la lista (posición 4+).
  Widget _buildInstitutionTile(InstitutionRankingEntry entry, bool isDark) {
    final bool destacada = entry.esMia;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: destacada
            ? AppColors.primary.withOpacity(0.10)
            : (isDark ? AppColors.darkSurface : AppColors.surface),
        borderRadius: BorderRadius.circular(14),
        border: destacada
            ? Border.all(color: AppColors.primary, width: 1.5)
            : null,
        boxShadow: destacada
            ? null
            : [
                BoxShadow(
                  color: AppColors.shadowSm,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          // Posición
          SizedBox(
            width: 34,
            child: Text(
              '${entry.posicion}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: entry.posicion <= 3
                    ? AppColors.warning
                    : (isDark
                        ? AppColors.darkTextTertiary
                        : AppColors.textTertiary),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          // Avatar institución
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary.withOpacity(0.12),
            child: Icon(
              _selectedType == 'colegios'
                  ? Icons.school_rounded
                  : Icons.map_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          // Nombre + detalles
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: destacada ? FontWeight.w800 : FontWeight.w700,
                    color:
                        isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    '${entry.usuarios} est.',
                    if (entry.ciudad != null && _selectedType == 'colegios')
                      entry.ciudad!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.darkTextTertiary
                        : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          // XP
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt_rounded,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 2),
                  Text(
                    _formatXp(entry.totalXp),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              if (destacada)
                Text(
                  'Tu ${_selectedType == 'colegios' ? 'colegio' : 'departamento'}',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Tarjeta con la posición de la institución propia (fuera del top).
  Widget _buildMiInstitucionCard(bool isDark) {
    final data = _instRankingData!;
    final mia = data.miInstitucion!;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tu ${_selectedType == 'colegios' ? 'colegio' : 'departamento'}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textOnPrimary.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            mia.nombre,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textOnPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildUserStat(
                  'Posición',
                  '#${mia.posicion}',
                  Icons.emoji_events_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildUserStat(
                  'Estudiantes',
                  '${mia.usuarios ?? '—'}',
                  Icons.group_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => ShareService.shareRankingPosition(
                posicion: mia.posicion,
                total: data.totalInstituciones,
                xp: mia.totalXp ?? 0,
                tipo: _selectedType,
              ),
              icon: const Icon(Icons.share_rounded, size: 16),
              label: const Text('Compartir'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.textOnPrimary,
                foregroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatXp(int xp) {
    if (xp >= 1000000) return '${(xp / 1000000).toStringAsFixed(1)}M';
    if (xp >= 1000) return '${(xp / 1000).toStringAsFixed(1)}k';
    return '$xp';
  }

  /// Construye el podio animado para los top 3.
  /// El 1er lugar va en el centro (más alto), 2do a la izquierda, 3ro a la derecha.
  Widget _buildPodium(List<RankingEntry> top3, bool isDark) {
    // Ordenar visualmente: 2do, 1ro, 3ro (estilo podio olímpico)
    final second = top3[1];
    final first = top3[0];
    final third = top3[2];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AppColors.darkSurface, AppColors.darkSurfaceVariant]
              : [AppColors.surface, AppColors.surfaceVariant],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── 2do lugar (plata) ──
          Expanded(
            child: _buildPodiumItem(second, AppColors.silver, 110, isDark, 2),
          ),
          const SizedBox(width: 8),

          // ── 1er lugar (oro) ──
          Expanded(
            child: _buildPodiumItem(first, AppColors.gold, 140, isDark, 1),
          ),
          const SizedBox(width: 8),

          // ── 3er lugar (bronce) ──
          Expanded(
            child: _buildPodiumItem(third, AppColors.bronze, 95, isDark, 3),
          ),
        ],
      ),
    );
  }

  Widget _buildPodiumItem(
    RankingEntry entry,
    Color medalColor,
    double height,
    bool isDark,
    int position,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Medalla
        Stack(
          alignment: Alignment.topCenter,
          children: [
            // Avatar
            Container(
              width: position == 1 ? 56 : 48,
              height: position == 1 ? 56 : 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: medalColor,
                  width: position == 1 ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: medalColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: _buildAvatar(entry, position == 1 ? 56 : 48),
            ),
            // Corona para el 1er lugar
            if (position == 1)
              Positioned(
                top: -16,
                child: Icon(
                  Icons.emoji_events_rounded,
                  color: AppColors.gold,
                  size: 24,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),

        // Nombre
        Text(
          _truncateName(entry.name),
          style: TextStyle(
            fontSize: position == 1 ? 12 : 11,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),

        // XP
        Text(
          '${entry.xp} XP',
          style: TextStyle(
            fontSize: position == 1 ? 13 : 11,
            fontWeight: FontWeight.w800,
            color: medalColor,
          ),
        ),
        const SizedBox(height: 8),

        // Columna del podio
        Container(
          width: double.infinity,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                medalColor.withOpacity(0.8),
                medalColor.withOpacity(0.4),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(8),
              bottom: Radius.circular(4),
            ),
          ),
          child: Center(
            child: Text(
              '$position',
              style: TextStyle(
                fontSize: position == 1 ? 32 : 24,
                fontWeight: FontWeight.w900,
                color: AppColors.textOnPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Tile individual para posiciones 4+
  Widget _buildRankTile(RankingEntry entry, bool isDark) {
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: entry.isCurrentUser
            ? AppColors.primary.withOpacity(0.08)
            : surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: entry.isCurrentUser
            ? Border.all(color: AppColors.primary.withOpacity(0.4), width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          // Posición
          SizedBox(
            width: 36,
            child: Text(
              '${entry.position}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: entry.isCurrentUser ? AppColors.primary : textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 10),

          // Avatar
          _buildAvatar(entry, 36),
          const SizedBox(width: 10),

          // Nombre + ciudad
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name + (entry.isCurrentUser ? ' (Tú)' : ''),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: entry.isCurrentUser
                        ? FontWeight.w700
                        : FontWeight.w600,
                    color: entry.isCurrentUser ? AppColors.primary : textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.ciudad != null && entry.ciudad!.isNotEmpty)
                  Text(
                    entry.ciudad!,
                    style: TextStyle(
                      fontSize: 10,
                      color: textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // XP
          Text(
            '${entry.xp} XP',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: entry.isCurrentUser ? AppColors.primary : textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  /// Tarjeta destacada del usuario actual (cuando no está en el top visible)
  Widget _buildUserCard(bool isDark) {
    final userPosition = _rankingData!.userPosition;
    final gamif = context.watch<GamificationProvider>();
    final userXp = gamif.totalXp;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_rounded,
                color: AppColors.textOnPrimary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tu posición',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textOnPrimary.withOpacity(0.9),
                  ),
                ),
              ),
              Text(
                '#$userPosition',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textOnPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildUserStat(
                  'Tu XP',
                  '$userXp',
                  Icons.bolt_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildUserStat(
                  'Tu nivel',
                  '${gamif.level}',
                  Icons.star_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserStat(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.textOnPrimary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textOnPrimary, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textOnPrimary.withOpacity(0.8),
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textOnPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Construye el avatar de un usuario (imagen o iniciales)
  Widget _buildAvatar(RankingEntry entry, double size) {
    if (entry.avatarPath != null && entry.avatarPath!.isNotEmpty) {
      // Avatar del backend (puede ser URL relativa)
      String imageUrl = entry.avatarPath!;
      if (!imageUrl.startsWith('http')) {
        // Construir URL completa
        var cleanPath = imageUrl;
        if (cleanPath.startsWith('/')) cleanPath = cleanPath.substring(1);
        if (cleanPath.startsWith('uploads/avatars/')) {
          cleanPath = cleanPath.replaceFirst('uploads/avatars/', '');
        }
        imageUrl = '${Env.avatarBaseUrl}$cleanPath';
      }

      return CircleAvatar(
        radius: size / 2,
        backgroundColor: AppColors.surfaceVariant,
        backgroundImage: CachedNetworkImageProvider(imageUrl),
      );
    }

    // Avatar con iniciales
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.primary.withOpacity(0.15),
      child: Text(
        entry.initials,
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }

  String _truncateName(String name) {
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0];
    // Mostrar primer nombre + inicial del apellido
    return '${parts[0]} ${parts[1][0]}.';
  }

  Widget _buildShimmer(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Shimmer del podio
          ShimmerLoading(
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Shimmer de la lista
          ...List.generate(
            8,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ShimmerLoading(
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(fontSize: 14, color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadRanking,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.emoji_events_outlined, size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text(
              'Aún no hay datos de ranking para este período',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '¡Sé el primero en ganar XP!',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodTab {
  final String key;
  final String label;
  final IconData icon;

  _PeriodTab({required this.key, required this.label, required this.icon});
}
