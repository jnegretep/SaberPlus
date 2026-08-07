// lib/screens/challenge_list_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/challenge.dart';
import '../widgets/global_scaffold.dart';
import 'package:intl/intl.dart';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';

class ChallengeListScreen extends StatefulWidget {
  final ApiService api;

  const ChallengeListScreen({Key? key, required this.api}) : super(key: key);

  @override
  State<ChallengeListScreen> createState() => _ChallengeListScreenState();
}

class _ChallengeListScreenState extends State<ChallengeListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _created = [];
  List<dynamic> _invited = [];
  List<dynamic> _pending = [];
  bool _loading = true;
  Timer? _autoRefreshTimer;
  int _activeTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _activeTabIndex = _tabController.index;
        });
      }
    });
    _loadChallenges();

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _loadChallenges();
    });
  }

  Future<void> _loadChallenges() async {
    try {
      final data = await widget.api.getChallenges();
      if (!mounted) return;
      setState(() {
        _created = data['created'] ?? [];
        _invited = data['invited'] ?? [];
        _pending = data['pending'] ?? [];
        _loading = false;
      });
    } catch (e) {
      debugPrint("Error cargando retos: $e");
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'finalizado':
        return AppColors.successDark;
      case 'en_curso':
        return AppColors.warning;
      case 'pendiente':
        return AppColors.textTertiary;
      default:
        return AppColors.textDisabled;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'finalizado':
        return Icons.check_circle_rounded;
      case 'en_curso':
        return Icons.access_time_filled_rounded;
      case 'pendiente':
        return Icons.pending_actions_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  Color _getAreaColor(String area) {
    switch (area.toLowerCase()) {
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
      default:
        return AppColors.primary;
    }
  }

  IconData _getAreaIcon(String area) {
    switch (area.toLowerCase()) {
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
      default:
        return Icons.category_rounded;
    }
  }

  Widget _buildChallengeCard(Map<String, dynamic> json) {
    final challenge = Challenge.fromJson(json);
    final statusColor = _getStatusColor(challenge.status);
    final statusIcon = _getStatusIcon(challenge.status);
    final areaColor = _getAreaColor(challenge.area);
    final areaIcon = _getAreaIcon(challenge.area);

    // Verificar si el reto es próximo (en las próximas 24 horas)
    final now = DateTime.now();
    DateTime? scheduledDate;
    try {
      scheduledDate = DateTime.parse(challenge.scheduledDatetime);
    } catch (e) {
      scheduledDate = null;
    }
    
    final isUpcoming = scheduledDate != null && 
        scheduledDate.isAfter(now) && 
        scheduledDate.difference(now).inHours <= 24;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        border: Border.all(
          color: isUpcoming 
              ? AppColors.warning.withOpacity(0.3)
              : AppColors.border,
          width: isUpcoming ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () {
            Nav.goChallengeDetail(context, id: challenge.id);
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header con título y estado - Mejorado
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ícono del área
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: areaColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: areaColor.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        areaIcon,
                        color: areaColor,
                        size: 22,
                      ),
                    ),
                    
                    const SizedBox(width: 12),
                    
                    // Título y descripción
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      challenge.title,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textSecondary,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "ID: #${challenge.id} • ${challenge.area}",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textDisabled,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // Badge de estado - Mejorado
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: statusColor.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      statusIcon, 
                                      size: 14, 
                                      color: statusColor
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      challenge.status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 12),
                          
                          // Información del reto en chips - Mejorado
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              // Área
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: areaColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: areaColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      challenge.area.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: areaColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // Nivel - Mejorado
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.trending_up_rounded,
                                      size: 12,
                                      color: AppColors.textTertiary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Nivel ${challenge.level}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),

// Fecha y hora - Mejorado
Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: AppColors.surfaceClean,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: AppColors.border),
  ),
  child: Row(
    children: [
      Icon(
        Icons.calendar_month_rounded,
        size: 16,
        color: AppColors.textTertiary,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fecha programada:',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textDisabled,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              // 👇 formateo amigable
              DateFormat("EEEE, d 'de' MMMM 'de' yyyy 'a las' h:mm a", 'es_ES')
                  .format(DateTime.parse(challenge.scheduledDatetime)),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.borderDark,
              ),
            ),
          ],
        ),
      ),

      if (isUpcoming)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.warning),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.access_time_filled_rounded,
                size: 12,
                color: AppColors.warning,
              ),
              const SizedBox(width: 4),
              Text(
                'PRÓXIMO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
        ),
    ],
  ),
),

                
                const SizedBox(height: 16),
                
                // Participantes y detalles - Mejorado
                Row(
                  children: [
                    // Participantes
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.group_rounded,
                            size: 14,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${challenge.participantsCount} participantes',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const Spacer(),
                    
                    // Botón de ver detalles - Mejorado
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryLight],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Ver detalles',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textOnPrimary,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: AppColors.textOnPrimary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String category) {
    String title;
    String subtitle;
    IconData icon;
    Color color;
    
    switch (category) {
      case 'created':
        title = 'Aún no has creado retos';
        subtitle = 'Crea tu primer reto académico para competir con amigos';
        icon = Icons.emoji_events_rounded;
        color = AppColors.warning;
        break;
      case 'invited':
        title = 'No tienes invitaciones';
        subtitle = 'Te aparecerán aquí cuando alguien te invite a un reto';
        icon = Icons.mail_outline_rounded;
        color = AppColors.purple;
        break;
      case 'pending':
        title = 'No hay retos pendientes';
        subtitle = 'Todos tus retos están activos o completados';
        icon = Icons.check_circle_outline_rounded;
        color = AppColors.successDark;
        break;
      default:
        title = 'No hay retos disponibles';
        subtitle = 'Crea un reto para comenzar';
        icon = Icons.inbox_rounded;
        color = AppColors.textTertiary;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                color: color,
                size: 56,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Nav.goCreateChallenge(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                elevation: 0,
                shadowColor: Colors.transparent,
              ),
              icon: Icon(Icons.add_rounded, size: 20),
              label: const Text(
                'Crear nuevo reto',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
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
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppColors.primary,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textTertiary,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        tabs: [
          Tab(
            icon: _activeTabIndex == 0
                ? Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                : const SizedBox(width: 6, height: 6),
            text: 'Creados (${_created.length})',
          ),
          Tab(
            icon: _activeTabIndex == 1
                ? Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                : const SizedBox(width: 6, height: 6),
            text: 'Invitados (${_invited.length})',
          ),
          Tab(
            icon: _activeTabIndex == 2
                ? Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                : const SizedBox(width: 6, height: 6),
            text: 'Pendientes (${_pending.length})',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.removeListener(() {});
    _tabController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlobalScaffold(
      currentIndex: 1,
      body: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            // Header mejorado
            Container(
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Retos Académicos",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textOnPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Competencias en tiempo real • ${_created.length + _invited.length + _pending.length} retos",
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textOnPrimarySubtle,
                    ),
                  ),
                ],
              ),
            ),
            
            // Tabs mejorados
            _buildTabBar(),
            
            // Contenido
            Expanded(
              child: _loading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Cargando tus retos...',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _created.isEmpty
                            ? _buildEmptyState('created')
                            : RefreshIndicator(
                                onRefresh: _loadChallenges,
                                color: AppColors.primary,
                                backgroundColor: AppColors.surface,
                                child: ListView.builder(
                                  padding: const EdgeInsets.only(top: 16, bottom: 100),
                                  itemCount: _created.length,
                                  itemBuilder: (ctx, i) => _buildChallengeCard(_created[i]),
                                ),
                              ),
                        _invited.isEmpty
                            ? _buildEmptyState('invited')
                            : RefreshIndicator(
                                onRefresh: _loadChallenges,
                                color: AppColors.primary,
                                backgroundColor: AppColors.surface,
                                child: ListView.builder(
                                  padding: const EdgeInsets.only(top: 16, bottom: 100),
                                  itemCount: _invited.length,
                                  itemBuilder: (ctx, i) => _buildChallengeCard(_invited[i]),
                                ),
                              ),
                        _pending.isEmpty
                            ? _buildEmptyState('pending')
                            : RefreshIndicator(
                                onRefresh: _loadChallenges,
                                color: AppColors.primary,
                                backgroundColor: AppColors.surface,
                                child: ListView.builder(
                                  padding: const EdgeInsets.only(top: 16, bottom: 100),
                                  itemCount: _pending.length,
                                  itemBuilder: (ctx, i) => _buildChallengeCard(_pending[i]),
                                ),
                              ),
                      ],
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          onPressed: () {
            Nav.goCreateChallenge(context);
          },
          child: Icon(Icons.add_rounded, size: 28),
        ),
      ),
    );
  }
}