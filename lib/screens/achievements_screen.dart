// lib/screens/achievements_screen.dart
// Saber+ — Pantalla de Logros / Achievements
//
// Muestra todos los badges del usuario organizados por categoría:
// - Header con resumen: XP total, nivel, racha, % completado
// - Tabs por categoría: Todos, Simulacros, Rachas, Social, Especiales
// - Grid de badges con estado (desbloqueado/bloqueado)
// - Badges bloqueados muestran progreso hacia desbloquearlos
// - Badges secretos se muestran como "???" hasta desbloquearlos

import 'package:flutter/material.dart' hide Badge; // <-- SOLUCIÓN
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../core/animations/app_animations.dart';
import '../core/animations/shimmer_loading.dart';
import '../providers/gamification_provider.dart';
import '../models/gamification_state.dart';
import '../config/navigation.dart';
import '../widgets/gamification/xp_bar.dart';
import '../widgets/gamification/streak_indicator.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _selectedCategory = 'all';

  final List<_CategoryTab> _tabs = [
    _CategoryTab(key: 'all', label: 'Todos', icon: Icons.grid_view_rounded),
    _CategoryTab(key: 'simulacros', label: 'Simulacros', icon: Icons.assignment_rounded),
    _CategoryTab(key: 'rachas', label: 'Rachas', icon: Icons.local_fire_department_rounded),
    _CategoryTab(key: 'social', label: 'Social', icon: Icons.emoji_events_rounded),
    _CategoryTab(key: 'especial', label: 'Especiales', icon: Icons.auto_awesome_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedCategory = _tabs[_tabController.index].key;
        });
      }
    });

    // Cargar/refresh gamification al entrar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GamificationProvider>().refresh();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gamif = context.watch<GamificationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Custom App Bar ──
            _buildAppBar(context, isDark),

            // ── Contenido ──
            Expanded(
              child: gamif.isLoading && gamif.state.badges.totalCount == 0
                  ? _buildShimmer(isDark)
                  : RefreshIndicator(
                      onRefresh: () => gamif.refresh(),
                      color: AppColors.primary,
                      backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Resumen: XP + racha ──
                            _buildSummarySection(gamif, isDark),
                            const SizedBox(height: 24),

                            // ── Progreso de badges ──
                            _buildBadgesProgress(gamif, isDark),
                            const SizedBox(height: 20),

                            // ── Tabs por categoría ──
                            _buildCategoryTabs(isDark),
                            const SizedBox(height: 16),

                            // ── Grid de badges ──
                            _buildBadgesGrid(gamif, isDark),
                          ],
                        ),
                      ),
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
            child: Text(
              'Logros',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              ),
            ),
          ),
          // ✅ Botón de Ranking de XP
          IconButton(
            icon: const Icon(Icons.leaderboard_rounded),
            onPressed: () => Nav.goXpRanking(context),
            tooltip: 'Ranking de XP',
            color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => context.read<GamificationProvider>().refresh(),
            color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection(GamificationProvider gamif, bool isDark) {
    return Column(
      children: [
        // XP bar (versión no compacta)
        XpBar(
          compact: false,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sigue estudiando para ganar más XP'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        // Streak indicator (versión no compacta)
        StreakIndicator(
          compact: false,
          onTap: () {
            if (gamif.currentStreak > 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '¡Llevas ${gamif.currentStreak} días consecutivos! '
                    'Tu racha máxima es ${gamif.maxStreak} días.',
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildBadgesProgress(GamificationProvider gamif, bool isDark) {
    final unlocked = gamif.unlockedBadgesCount;
    final total = gamif.totalBadgesCount;
    final pct = total > 0 ? (unlocked / total * 100) : 0.0;

    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progreso de logros',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              Text(
                '$unlocked / $total',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceVariant
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: (pct / 100).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.success, AppColors.successDark],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${pct.toStringAsFixed(0)}% completado',
            style: TextStyle(
              fontSize: 11,
              color: textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs(bool isDark) {
    return Container(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = _tabs[index];
          final isSelected = _selectedCategory == tab.key;

          return GestureDetector(
            onTap: () {
              _tabController.animateTo(index);
              setState(() {
                _selectedCategory = tab.key;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.darkSurface : AppColors.surface),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkBorder : AppColors.border),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tab.icon,
                    size: 16,
                    color: isSelected
                        ? AppColors.textOnPrimary
                        : (isDark ? AppColors.darkTextTertiary : AppColors.textTertiary),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? AppColors.textOnPrimary
                          : (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBadgesGrid(GamificationProvider gamif, bool isDark) {
    // Combinar badges desbloqueados y bloqueados
    final allBadges = <Badge>[];

    // Si la categoría es "all", mostrar todos
    if (_selectedCategory == 'all') {
      allBadges.addAll(gamif.state.badges.unlocked);
      allBadges.addAll(gamif.state.badges.locked);
    } else {
      // Filtrar por categoría
      allBadges.addAll(
        gamif.state.badges.unlocked.where((b) => b.category == _selectedCategory),
      );
      allBadges.addAll(
        gamif.state.badges.locked.where((b) => b.category == _selectedCategory),
      );
    }

    if (allBadges.isEmpty) {
      return _buildEmptyState(isDark);
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: allBadges.length,
      itemBuilder: (context, index) {
        final badge = allBadges[index];
        return _BadgeCard(badge: badge, isDark: isDark);
      },
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 64,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: 16),
          Text(
            'No hay logros en esta categoría',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ShimmerLoading(
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ShimmerLoading(
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            itemCount: 9,
            itemBuilder: (_, __) => ShimmerLoading(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// BADGE CARD
// ═══════════════════════════════════════════════════

class _BadgeCard extends StatelessWidget {
  final Badge badge;
  final bool isDark;

  const _BadgeCard({required this.badge, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isUnlocked = badge.isUnlocked;
    final color = _parseColor(badge.color);
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;

    return PressScale(
      onTap: () => _showBadgeDetail(context),
      child: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUnlocked
                ? color.withOpacity(0.5)
                : (isDark ? AppColors.darkBorder : AppColors.border),
            width: isUnlocked ? 1.5 : 1,
          ),
          boxShadow: isUnlocked
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Icono del badge ──
            Expanded(
              flex: 3,
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Glow de fondo si está desbloqueado
                    if (isUnlocked)
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withOpacity(0.15),
                        ),
                      ),
                    // Icono
                    Icon(
                      _getBadgeIcon(badge.icon),
                      size: 36,
                      color: isUnlocked ? color : AppColors.textDisabled,
                    ),
                    // Candado si está bloqueado
                    if (!isUnlocked && !badge.isHidden)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: surfaceColor,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.lock_rounded,
                            size: 10,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Nombre del badge ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                badge.isHidden && !isUnlocked ? '???' : badge.name,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isUnlocked
                      ? (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary)
                      : AppColors.textTertiary,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // ── Progreso o XP reward ──
            if (isUnlocked && badge.xpReward > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '+${badge.xpReward} XP',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              )
            else if (!isUnlocked && !badge.isHidden && badge.progress != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${badge.progress}/${badge.progressTarget}',
                  style: TextStyle(
                    fontSize: 9,
                    color: AppColors.textTertiary,
                  ),
                ),
              )
            else if (!isUnlocked)
              const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showBadgeDetail(BuildContext context) {
    final isUnlocked = badge.isUnlocked;
    final color = _parseColor(badge.color);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(ctx).brightness == Brightness.dark
              ? AppColors.darkSurface
              : AppColors.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icono grande
            Stack(
              alignment: Alignment.center,
              children: [
                if (isUnlocked)
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.15),
                    ),
                  ),
                Icon(
                  _getBadgeIcon(badge.icon),
                  size: 64,
                  color: isUnlocked ? color : AppColors.textDisabled,
                ),
                if (!isUnlocked && !badge.isHidden)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 3),
                      ),
                      child: Icon(
                        Icons.lock_rounded,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              badge.isHidden && !isUnlocked ? 'Logro secreto' : badge.name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isUnlocked ? color : AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              badge.isHidden && !isUnlocked
                  ? 'Sigue estudiando para descubrir este logro especial'
                  : badge.description,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textTertiary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Estado / progreso
            if (isUnlocked) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, color: color, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Desbloqueado',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge.xpReward > 0) ...[
                const SizedBox(height: 12),
                Text(
                  'Recompensa: +${badge.xpReward} XP',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ] else if (!badge.isHidden && badge.progress != null) ...[
              // Barra de progreso
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 12,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: ((badge.progressPct ?? 0) / 100)
                            .clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${badge.progress} / ${badge.progressTarget}'
                ' (${(badge.progressPct ?? 0).toStringAsFixed(0)}%)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              ),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Convierte un string hex (#FF8B5CF6) a Color
  Color _parseColor(String hex) {
    try {
      final hexValue = hex.replaceAll('#', '');
      return Color(int.parse('FF$hexValue', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  /// Mapea el nombre del icono del backend a un IconData de Material
  IconData _getBadgeIcon(String iconName) {
    const iconMap = {
      'assignment_turned_in': Icons.assignment_turned_in_rounded,
      'school': Icons.school_rounded,
      'workspace_premium': Icons.workspace_premium_rounded,
      'military_tech': Icons.military_tech_rounded,
      'local_fire_department': Icons.local_fire_department_rounded,
      'whatshot': Icons.whatshot_rounded,
      'bolt': Icons.bolt_rounded,
      'auto_awesome': Icons.auto_awesome_rounded,
      'trending_up': Icons.trending_up_rounded,
      'star': Icons.star_rounded,
      'emoji_events': Icons.emoji_events_rounded,
      'wb_sunny': Icons.wb_sunny_rounded,
      'nightlight': Icons.nightlight_rounded,
      'check_circle': Icons.check_circle_rounded,
      'balance': Icons.balance_rounded,
      'lock': Icons.lock_rounded,
    };
    return iconMap[iconName] ?? Icons.emoji_events_rounded;
  }
}

// ═══════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════

class _CategoryTab {
  final String key;
  final String label;
  final IconData icon;

  _CategoryTab({required this.key, required this.label, required this.icon});
}