// lib/screens/create_challenge_screen.dart
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'challenge_detail_screen.dart';
import '../core/theme/app_colors.dart';

class CreateChallengeScreen extends StatefulWidget {
  final ApiService api;
  const CreateChallengeScreen({Key? key, required this.api}) : super(key: key);

  @override
  State<CreateChallengeScreen> createState() => _CreateChallengeScreenState();
}

class _CreateChallengeScreenState extends State<CreateChallengeScreen> {
  int _currentStep = 0;

  String? _area;
  String? _level;
  Map<String, dynamic>? _selectedQuiz;
  DateTime? _scheduled;
  int _duration = 20;
  List<Map<String, dynamic>> _invitedUsers = [];
  List<Map<String, dynamic>> _searchResults = [];

  final List<String> _areas = ["ingles", "sociales", "naturales", "lectura", "matematicas"];
  final List<String> _levels = ["nivel1", "nivel2", "nivel3", "nivel4"];
  final TextEditingController _searchController = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ==========================
  //   DISEÑO: INDICADORES DE PASO (MEJORADO)
  // ==========================
  Widget _buildStepIndicator() {
    final steps = [
      {"title": "Área", "subtitle": "Selecciona"},
      {"title": "Test", "subtitle": "Elige"},
      {"title": "Programar", "subtitle": "Fecha"},
      {"title": "Invitados", "subtitle": "Agrega"},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Barra de progreso
          LinearProgressIndicator(
            value: (_currentStep + 1) / 4,
            backgroundColor: AppColors.surfaceVariant,
            color: AppColors.primary,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 16),
          
          // Pasos mejorados - Layout responsivo
          LayoutBuilder(
            builder: (context, constraints) {
              final bool isSmallScreen = constraints.maxWidth < 380;
              
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: steps.asMap().entries.map((entry) {
                  final index = entry.key;
                  final step = entry.value;
                  final isActive = index == _currentStep;
                  final isCompleted = index < _currentStep;
                  
                  return GestureDetector(
                    onTap: () {
                      if (index <= _currentStep) {
                        setState(() => _currentStep = index);
                      }
                    },
                    child: Container(
                      constraints: BoxConstraints(
                        minWidth: isSmallScreen ? 60 : 72,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Círculo del paso
                          Container(
                            width: isSmallScreen ? 32 : 36,
                            height: isSmallScreen ? 32 : 36,
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppColors.primary
                                  : isCompleted
                                      ? AppColors.successDark
                                      : AppColors.surfaceVariant,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isActive
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: isActive ? 2 : 1,
                              ),
                            ),
                            child: Center(
                              child: isCompleted
                                  ? Icon(
                                      Icons.check_rounded,
                                      size: isSmallScreen ? 16 : 18,
                                      color: AppColors.textOnPrimary,
                                    )
                                  : Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 12 : 14,
                                        fontWeight: FontWeight.w700,
                                        color: isActive ? AppColors.textOnPrimary : AppColors.textTertiary,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          
                          // Título y subtítulo optimizados
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                step['title'] ?? '',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 10 : 12,
                                  fontWeight: FontWeight.w600,
                                  color: isActive ? AppColors.primary : AppColors.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (!isSmallScreen) ...[
                                const SizedBox(height: 2),
                                Text(
                                  step['subtitle'] ?? '',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: isActive ? AppColors.primary.withOpacity(0.7) : AppColors.textDisabled,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================
  //   DISEÑO: PASO 1 - ÁREA Y NIVEL
  // ==========================
  Widget _buildStep1() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Selecciona el área y nivel",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Elige el área de conocimiento y el nivel de dificultad",
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 24),
          
          // Selección de Área
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Área de conocimiento",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _areas.map((area) {
                  final isSelected = _area == area;
                  return ChoiceChip(
                    label: Text(
                      area[0].toUpperCase() + area.substring(1),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? AppColors.textOnPrimary : AppColors.borderDark,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _area = selected ? area : null;
                        _selectedQuiz = null;
                      });
                    },
                    backgroundColor: AppColors.surfaceClean,
                    selectedColor: _getAreaColor(area),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? _getAreaColor(area) : AppColors.border,
                        width: isSelected ? 0 : 1,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          
          const SizedBox(height: 28),
          
          // Selección de Nivel
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Nivel de dificultad",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _levels.map((level) {
                  final isSelected = _level == level;
                  return ChoiceChip(
                    label: Text(
                      level[0].toUpperCase() + level.substring(1),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? AppColors.textOnPrimary : AppColors.borderDark,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _level = selected ? level : null;
                        _selectedQuiz = null;
                      });
                    },
                    backgroundColor: AppColors.surfaceClean,
                    selectedColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? AppColors.primary : AppColors.border,
                        width: isSelected ? 0 : 1,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Consejo
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.infoBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.infoBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline_rounded, color: AppColors.sky, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Selecciona un área y nivel que se adapte a todos los participantes para una competencia justa.",
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.infoDeeper,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================
  //   DISEÑO: PASO 2 - CUESTIONARIO (MEJORADO CON RESALTADO)
  // ==========================
  Widget _buildStep2() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Elige el cuestionario",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Selecciona uno de los cuestionarios disponibles",
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 24),
          
          if (_area == null || _level == null)
            _buildEmptyState(
              icon: Icons.quiz_outlined,
              title: 'Selecciona primero el área y nivel',
              message: 'Debes completar el paso anterior para ver los cuestionarios disponibles',
            )
          else
            FutureBuilder<List<Map<String, dynamic>>>(
              future: widget.api.getQuizzes(area: _area!, level: _level!),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingState();
                }
                
                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error.toString());
                }
                
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _buildEmptyState(
                    icon: Icons.assignment_outlined,
                    title: 'No hay cuestionarios disponibles',
                    message: 'Intenta con otra área o nivel para encontrar más opciones',
                  );
                }

                final quizzes = snapshot.data!;
                return Column(
                  children: quizzes.map((q) {
                    final title = q['title'] ?? q['name'] ?? 'Sin título';
                    final isSelected = _selectedQuiz == q;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary.withOpacity(0.05) : AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.border,
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.shadowLg,
                            blurRadius: isSelected ? 12 : 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedQuiz = q;
                            });
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.assignment_rounded,
                                    color: isSelected ? AppColors.textOnPrimary : AppColors.textTertiary,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Área: ${_area!.toUpperCase()} • Nivel: ${_level!.toUpperCase()}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.check_rounded,
                                      color: AppColors.textOnPrimary,
                                      size: 16,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  // ==========================
  //   DISEÑO: PASO 3 - FECHA Y DURACIÓN (MEJORADO)
  // ==========================
  Widget _buildStep3() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Programa tu reto",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Define cuándo será el reto y cuánto durará",
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 24),
          
          // Selector de fecha y hora - DISEÑO MEJORADO
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceClean,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.explanationBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.calendar_today_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Fecha y hora programada",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _scheduled == null
                                ? "No se ha seleccionado una fecha"
                                : _formatDateTime(_scheduled!),
                            style: TextStyle(
                              fontSize: 13,
                              color: _scheduled == null
                                  ? AppColors.textDisabled
                                  : AppColors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _pickDateTime,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textOnPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        minimumSize: const Size(0, 40),
                      ),
                      child: const Text('Seleccionar'),
                    ),
                  ],
                ),
                
                if (_scheduled != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.successLight),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppColors.successDeep, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _formatDateTime(_scheduled!),
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.successDeep,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Selector de duración
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Duración del reto",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Selecciona cuánto tiempo durará (minutos)",
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 20),
              
              // Slider mejorado
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceClean,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$_duration minutos',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Recomendado: 20 minutos',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: AppColors.explanationBg,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primary, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              '$_duration',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Slider(
                      value: _duration.toDouble(),
                      min: 15,
                      max: 25,
                      divisions: 2,
                      label: "$_duration min",
                      activeColor: AppColors.primary,
                      inactiveColor: AppColors.border,
                      onChanged: (value) {
                        setState(() {
                          _duration = value.round();
                        });
                      },
                    ),
                    const SizedBox(height: 6),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('15 min', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                        Text('20 min', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                        Text('25 min', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================
  //   DISEÑO: PASO 4 - INVITADOS
  // ==========================
  Widget _buildStep4() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Invita participantes",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Agrega amigos para competir en tiempo real (opcional)",
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 24),
          
          // Búsqueda de usuarios
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceClean,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Buscar usuarios",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Nombre de usuario o email...",
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.textTertiary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (query) async {
                    if (query.length < 2) {
                      setState(() => _searchResults = []);
                      return;
                    }
                    try {
                      final results = await widget.api.searchUsers(query);
                      final filtered = results.where((u) {
                        return !_invitedUsers.any((inv) => inv['id'] == u['id']);
                      }).toList();
                      setState(() => _searchResults = filtered);
                    } catch (_) {}
                  },
                ),
              ],
            ),
          ),
          
          // Resultados de búsqueda
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              "Resultados de búsqueda",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            ..._searchResults.map((u) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowMd,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.surfaceVariant,
                    child: Text(
                      (u['name']?[0] ?? '?').toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  title: Text(
                    u['name'] ?? 'Usuario',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  subtitle: u['email'] != null
                      ? Text(
                          u['email'],
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        )
                      : null,
                  trailing: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      color: AppColors.textOnPrimary,
                      size: 16,
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _invitedUsers.add(u);
                      _searchResults.removeWhere((s) => s['id'] == u['id']);
                      _searchController.clear();
                    });
                  },
                ),
              );
            }).toList(),
          ],
          
          // Invitados seleccionados
          const SizedBox(height: 20),
          const Text(
            "Invitados seleccionados",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          
          if (_invitedUsers.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceClean,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.group_add_outlined,
                    size: 40,
                    color: AppColors.textDisabled,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No hay invitados aún',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Puedes crear el reto sin invitados y agregarlos después',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Column(
              children: _invitedUsers.asMap().entries.map((entry) {
                final index = entry.key;
                final u = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.explanationBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      CircleAvatar(
                        backgroundColor: AppColors.surfaceVariant,
                        child: Text(
                          (u['name']?[0] ?? '?').toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              u['name'] ?? 'Usuario',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (u['email'] != null)
                              Text(
                                u['email'],
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _invitedUsers.removeAt(index);
                          });
                        },
                        icon: Icon(
                          Icons.close_rounded,
                          color: AppColors.error,
                          size: 18,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          
          // Consejo
          if (_invitedUsers.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.infoBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.infoBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.sky, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Los invitados recibirán una notificación para unirse al reto.",
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.infoDeeper,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================
  //   BOTONES DE NAVEGACIÓN (MEJORADO CON SAFE AREA)
  // ==========================
  Widget _buildNavigationButtons() {
    final isLastStep = _currentStep == 3;
    final canContinue = _validateCurrentStep();
    
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _currentStep > 0
                  ? () {
                      setState(() {
                        _currentStep -= 1;
                      });
                    }
                  : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textTertiary,
                side: BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chevron_left_rounded, size: 18),
                  SizedBox(width: 6),
                  Text('Anterior', style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: canContinue
                  ? () {
                      if (isLastStep) {
                        _createChallenge();
                      } else {
                        setState(() {
                          _currentStep += 1;
                        });
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isLastStep ? AppColors.successDark : AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: _creating
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textOnPrimary,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isLastStep ? 'Crear reto' : 'Continuar',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          isLastStep ? Icons.rocket_launch_rounded : Icons.chevron_right_rounded,
                          size: 18,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================
  //   WIDGETS REUTILIZABLES
  // ==========================
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          SizedBox(height: 12),
          Text(
            'Buscando cuestionarios...',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.errorFaint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.errorFg),
      ),
      child: Column(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: AppColors.errorDark,
          ),
          SizedBox(height: 12),
          Text(
            'Error al cargar cuestionarios',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.errorDark,
            ),
          ),
          SizedBox(height: 6),
          Text(
            error,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.errorDeep,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String message}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceClean,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 40,
            color: AppColors.textDisabled,
          ),
          SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ==========================
  //   VALIDACIÓN
  // ==========================
  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _area != null && _level != null;
      case 1:
        return _selectedQuiz != null;
      case 2:
        return _scheduled != null;
      case 3:
        return true;
      default:
        return false;
    }
  }

  // ==========================
  //   HELPERS
  // ==========================
  Color _getAreaColor(String area) {
    switch (area.toLowerCase()) {
      case 'lectura':
        return AppColors.primaryLight;
      case 'matematicas':
        return AppColors.successDark;
      case 'sociales':
        return AppColors.purple;
      case 'naturales':
        return AppColors.warning;
      case 'ingles':
        return AppColors.error;
      default:
        return AppColors.primary;
    }
  }

  String _formatDateTime(DateTime dt) {
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0'); // 👈 ya está bien
  return "$day/$month/${dt.year} a las $hour:$minute"; // 👈 corregido
}


  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initialDate = now.add(const Duration(days: 1));
    
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: AppColors.textOnPrimary,
              surface: AppColors.surface,
              onSurface: AppColors.textSecondary,
            ),
            dialogBackgroundColor: AppColors.surface,
          ),
          child: child!,
        );
      },
    );
    
    if (date == null) return;
    
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: AppColors.textOnPrimary,
              surface: AppColors.surface,
              onSurface: AppColors.textSecondary,
            ),
            dialogBackgroundColor: AppColors.surface,
          ),
          child: child!,
        );
      },
    );
    
    if (time == null) return;
    
    setState(() {
      _scheduled = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  // ==========================
  //   CREACIÓN DEL RETO
  // ==========================
  Future<void> _createChallenge() async {
  if (_area == null || _level == null || _selectedQuiz == null || _scheduled == null) {
    _showAlert(
      "Completa todos los campos requeridos",
      "Debes seleccionar área, nivel, cuestionario y fecha antes de crear el reto.",
      Icons.error_outline_rounded,
      AppColors.error,
    );
    return;
  }

  setState(() => _creating = true);

  try {
    final resp = await widget.api.createChallenge(
      title: _selectedQuiz?['title'] ?? _selectedQuiz?['name'],
      area: _area!,
      level: _level!,
      quizId: _selectedQuiz?['quizid'] ?? _selectedQuiz?['id'],
      scheduledDatetime: _scheduled!.toIso8601String(),
      durationMinutes: _duration,
      // 👇 Ajuste: convertir explícitamente a List<int>
      invitedUsers: _invitedUsers
    .map<int>((u) => int.parse(u['id'].toString()))
    .toList(),

    );

    debugPrint("[CrearReto] Respuesta API: $resp");

    if (resp['status'] == 'error' || resp['success'] == false) {
      final msg = _buildErrorMessage(resp);
      _showAlert("Error al crear reto", msg, Icons.error_outline_rounded, AppColors.error);
      setState(() => _creating = false);
      return;
    }

    final challengeId = resp['challenge_id'];
    if (challengeId == null) {
      _showAlert("Error", "No se pudo crear el reto. Intenta nuevamente.", Icons.error_outline_rounded, AppColors.error);
      setState(() => _creating = false);
      return;
    }

    // Mostrar mensaje de éxito
    final skipped = resp['invited_skipped'];
    final friendly = resp['friendly_message']?.toString().trim();

    if (friendly != null && friendly.isNotEmpty) {
      await _showAlert("¡Reto creado!", friendly, Icons.check_circle_rounded, AppColors.successDark);
    } else if (skipped is List && skipped.isNotEmpty) {
      final info = _buildSkippedMessage(skipped);
      await _showAlert("Reto creado con advertencias", info, Icons.warning_amber_rounded, AppColors.warning);
    } else {
      await _showAlert("¡Éxito!", "El reto ha sido creado exitosamente.", Icons.check_circle_rounded, AppColors.successDark);
    }

    // Navegar a la pantalla de detalle
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChallengeDetailScreen(
          api: widget.api,
          challengeId: challengeId,
        ),
      ),
    );
  } catch (e) {
    _showAlert("Error", "No se pudo crear el reto: $e", Icons.error_outline_rounded, AppColors.error);
  } finally {
    if (mounted) setState(() => _creating = false);
  }
}


  String _buildErrorMessage(Map resp) {
    final baseMsg = (resp['msg'] ?? 'No se pudo crear el reto').toString();
    final skipped = resp['invited_skipped'];
    if (skipped is List && skipped.isNotEmpty) {
      final details = _buildSkippedLines(skipped).join('\n');
      return "$baseMsg\n\nInvitados omitidos:\n$details";
    }
    return baseMsg;
  }

  String _buildSkippedMessage(List skipped) {
    final lines = _buildSkippedLines(skipped);
    return "Algunos invitados fueron omitidos por restricciones:\n\n${lines.join('\n')}";
  }

  List<String> _buildSkippedLines(List skipped) {
    return skipped.map((item) {
      final m = item is Map ? item : {};
      final name = (m['name'] ?? '').toString().trim();
      final uid = m['user_id']?.toString() ?? '';
      final reason = (m['reason'] ?? 'Omitido por restricción').toString();
      final who = name.isNotEmpty ? name : (uid.isNotEmpty ? "Usuario $uid" : "Usuario");
      return "- $who: $reason";
    }).toList();
  }

  Future<void> _showAlert(String title, String message, IconData icon, Color color) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowLg,
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Icon(icon, color: color, size: 28),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textTertiary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Divider(height: 0),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: AppColors.textOnPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    child: const Text('Entendido'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 1,
        centerTitle: false,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Crear nuevo reto",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 2),
            Text(
              "Compite con amigos en tiempo real",
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildStepIndicator(),
                    const SizedBox(height: 16),
                    if (_currentStep == 0) _buildStep1(),
                    if (_currentStep == 1) _buildStep2(),
                    if (_currentStep == 2) _buildStep3(),
                    if (_currentStep == 3) _buildStep4(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }
}