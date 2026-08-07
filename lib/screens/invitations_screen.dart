// lib/screens/invitations_screen.dart
// Saber+ — Invitations screen for challenge and group invitations
// Phase 4: Full implementation replacing the empty stub

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../core/theme/app_colors.dart';
import '../core/animations/app_animations.dart';
import '../core/animations/page_transitions.dart';
import '../core/widgets/empty_state.dart';

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({super.key});

  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnimation;

  bool _isLoading = true;
  List<Map<String, dynamic>> _invitations = [];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: AppAnimations.slow,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: AppAnimations.enterCurve,
    );
    _loadInvitations();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _loadInvitations() async {
    // TODO: Replace with actual API call when invitations endpoint is ready
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _isLoading = false);
      _entranceController.forward();
    }
  }

  Future<void> _refreshInvitations() async {
    setState(() => _isLoading = true);
    await _loadInvitations();
  }

  void _acceptInvitation(int index) {
    AppHaptics.mediumImpact();
    setState(() {
      _invitations.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Invitación aceptada'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _declineInvitation(int index) {
    setState(() {
      _invitations.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Invitación rechazada'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.border;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: const Text('Invitaciones'),
        backgroundColor: surfaceColor,
        foregroundColor: textPrimary,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : FadeTransition(
              opacity: _fadeAnimation,
              child: _invitations.isEmpty
                  ? PremiumEmptyState(
                      icon: Icons.mail_outlined,
                      title: 'Sin invitaciones',
                      subtitle: 'No tienes invitaciones pendientes. Cuando alguien te invite a un reto o grupo, aparecerán aquí.',
                      accentColor: AppColors.primary,
                    )
                  : RefreshIndicator(
                      onRefresh: _refreshInvitations,
                      color: AppColors.primary,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _invitations.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final inv = _invitations[index];
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: surfaceColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  inv['title'] ?? 'Invitación',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  inv['from'] ?? 'De: Desconocido',
                                  style: TextStyle(fontSize: 14, color: textTertiary),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () => _declineInvitation(index),
                                      child: const Text('Rechazar'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () => _acceptInvitation(index),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: const Text('Aceptar'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
    );
  }
}
