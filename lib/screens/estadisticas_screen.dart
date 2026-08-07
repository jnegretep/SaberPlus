import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../widgets/global_scaffold.dart'; // 🔹 importa tu GlobalScaffold
import '../core/theme/app_colors.dart';

class EstadisticasScreen extends StatelessWidget {
  const EstadisticasScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final userName = auth.nombre ?? 'Usuario';
    final avatarUrl = auth.avatarUrl;

    return GlobalScaffold(
      currentIndex: 2, // 🔹 Estadísticas seleccionado
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado con avatar y nombre
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : const AssetImage('assets/avatars/default.png')
                          as ImageProvider,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    userName,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.subjectTeal),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Mock de gráficas de progreso por áreas
            const Text("Tu rendimiento por áreas",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _ProgressBar(label: "Matemáticas", value: 0.8, color: Colors.blue),
            _ProgressBar(label: "Lectura crítica", value: 0.65, color: AppColors.success),
            _ProgressBar(label: "Ciencias", value: 0.5, color: AppColors.warning),
            _ProgressBar(label: "Sociales", value: 0.7, color: Colors.purple),
            const SizedBox(height: 24),

            // Mock de ranking
            const Text("Ranking general",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _RankingTile(position: 1, name: "Ana Pérez", score: 95),
            _RankingTile(position: 2, name: "Carlos Gómez", score: 90),
            _RankingTile(position: 3, name: "Tú", score: 88, highlight: true),
            _RankingTile(position: 4, name: "María López", score: 85),
            _RankingTile(position: 5, name: "Juan Torres", score: 82),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _ProgressBar({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 10,
            backgroundColor: AppColors.stepInactive,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _RankingTile extends StatelessWidget {
  final int position;
  final String name;
  final int score;
  final bool highlight;

  const _RankingTile({
    required this.position,
    required this.name,
    required this.score,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: highlight ? Colors.teal.shade50 : AppColors.surface,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.subjectTeal,
          child: Text(position.toString(),
              style: TextStyle(color: AppColors.textOnPrimary)),
        ),
        title: Text(name,
            style: TextStyle(
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal)),
        trailing: Text("$score pts",
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
