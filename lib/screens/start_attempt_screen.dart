// lib/screens/start_attempt_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/quiz.dart';
import '../models/attempt.dart';
import '../services/api_service.dart';
import '../config/navigation.dart';

class StartAttemptScreen extends StatefulWidget {
  final Quiz quiz;

  const StartAttemptScreen({Key? key, required this.quiz}) : super(key: key);

  @override
  State<StartAttemptScreen> createState() => _StartAttemptScreenState();
}

class _StartAttemptScreenState extends State<StartAttemptScreen> {
  late Future<Attempt> _attemptFuture;

  @override
  void initState() {
    super.initState();
    // Disparamos el endpoint al cargar la pantalla
    final api = context.read<ApiService>();
    _attemptFuture = api.startAttempt(widget.quiz.quizid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Iniciando “${widget.quiz.name}”')),
      body: FutureBuilder<Attempt>(
        future: _attemptFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final attempt = snapshot.data!;
          // Una vez tenemos el attempt, navegamos a preguntas
          WidgetsBinding.instance!.addPostFrameCallback((_) {
            Nav.goQuestions(
              context,
              quiz: widget.quiz,
              attempt: attempt,
            );
          });
          return const Center(child: Text('Preparando preguntas...'));
        },
      ),
    );
  }
}
