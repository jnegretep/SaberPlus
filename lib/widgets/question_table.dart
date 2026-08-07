import 'package:flutter/material.dart';
import '../models/question.dart';

class QuestionTable extends StatelessWidget {
  final List<Question> questions;
  final int total;
  final int page;
  final int perPage;
  final VoidCallback onNext;
  final VoidCallback onPrev;

  const QuestionTable({
    required this.questions,
    required this.total,
    required this.page,
    required this.perPage,
    required this.onNext,
    required this.onPrev,
    Key? key
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DataTable(
          columns: const [
            DataColumn(label: Text('ID')),
            DataColumn(label: Text('Área')),
            DataColumn(label: Text('Competencia')),
            DataColumn(label: Text('Enunciado')),
            DataColumn(label: Text('Dificultad')),
            DataColumn(label: Text('Fecha')),
          ],
          rows: questions.map((q) {
            return DataRow(cells: [
              DataCell(Text(q.id.toString())),
              DataCell(Text(q.area)),
              DataCell(Text(q.competencia)),
              DataCell(Text(q.enunciado)),
              DataCell(Text(q.dificultad)),
              DataCell(Text(q.fechaCreacion.toLocal().toString().split(' ')[0])),
            ]);
          }).toList(),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Página $page de ${ (total / perPage).ceil() }  '),
            IconButton(
              icon: Icon(Icons.chevron_left),
              onPressed: page > 1 ? onPrev : null,
            ),
            IconButton(
              icon: Icon(Icons.chevron_right),
              onPressed: page * perPage < total ? onNext : null,
            ),
          ],
        ),
      ],
    );
  }
}
