import 'package:flutter/material.dart';

class FilterBar extends StatelessWidget {
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onAreaChanged;
  final ValueChanged<String?> onDifficultyChanged;

  const FilterBar({
    required this.onSearch,
    required this.onAreaChanged,
    required this.onDifficultyChanged,
    Key? key
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            decoration: InputDecoration(labelText: 'Buscar enunciado'),
            onChanged: onSearch,
          ),
        ),
        const SizedBox(width: 16),
        DropdownButton<String>(
          hint: Text('Área'),
          onChanged: onAreaChanged,
          items: [
            DropdownMenuItem(value: null, child: Text('Todas')),
            DropdownMenuItem(value: '1', child: Text('Matemáticas')),
            DropdownMenuItem(value: '2', child: Text('Ciencias')),
          ],
        ),
        const SizedBox(width: 16),
        DropdownButton<String>(
          hint: Text('Dificultad'),
          onChanged: onDifficultyChanged,
          items: [
            DropdownMenuItem(value: null, child: Text('Todas')),
            DropdownMenuItem(value: 'baja', child: Text('Baja')),
            DropdownMenuItem(value: 'media', child: Text('Media')),
            DropdownMenuItem(value: 'alta', child: Text('Alta')),
          ],
        ),
      ],
    );
  }
}
