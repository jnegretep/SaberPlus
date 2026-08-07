import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/course.dart';
import '../models/quiz.dart';
import '../services/api_service.dart';
import '../controllers/quiz_controller.dart';
import '../screens/question_screen.dart';
import '../core/theme/app_colors.dart';

class QuizListScreen extends StatefulWidget {
  final Course course;

  const QuizListScreen({Key? key, required this.course}) : super(key: key);

  @override
  State<QuizListScreen> createState() => _QuizListScreenState();
}

class _QuizListScreenState extends State<QuizListScreen> {
  late Future<List<Quiz>> _futureQuizzes;

  @override
  void initState() {
    super.initState();
    _futureQuizzes = context.read<ApiService>().fetchQuizzes(widget.course.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Cuestionarios de ${widget.course.name}')),
      body: FutureBuilder<List<Quiz>>(
        future: _futureQuizzes,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final quizzes = snap.data!;
          if (quizzes.isEmpty) {
            return const Center(child: Text('No hay cuestionarios.'));
          }
          return ListView.separated(
            itemCount: quizzes.length,
            separatorBuilder: (_, __) => Divider(),
            itemBuilder: (ctx, i) {
              final q = quizzes[i];
              return ListTile(
                title: Text(q.name),
                subtitle: Text('${q.questions} preguntas • Límite: ${q.timelimit}s'),
                onTap: () async {
                  final api = context.read<ApiService>();

                  // ✅ Pasamos también courseId al controlador
                  final controller = QuizController(
                    api: api,
                    quizId: q.id,
                    quizName: q.name,
                    courseId: q.courseId, // 👈 añadido
                  );

                  try {
                    await controller.start();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QuestionScreen(
                          controller: controller,
                          courseId: q.courseId, // 👈 corregido: usamos q.courseId
                        ),
                      ),
                    );
                  } catch (e) {
                    debugPrint('Error al iniciar intento: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('No se pudo iniciar el intento: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
