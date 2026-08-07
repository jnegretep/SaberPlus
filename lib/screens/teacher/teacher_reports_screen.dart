import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/teacher_service.dart';
import '../../widgets/global_scaffold.dart';
import '../../core/theme/app_colors.dart';

class TeacherReportsScreen extends StatefulWidget {
  const TeacherReportsScreen({Key? key}) : super(key: key);

  @override
  State<TeacherReportsScreen> createState() => _TeacherReportsScreenState();
}

class _TeacherReportsScreenState extends State<TeacherReportsScreen> {
  TeacherService get _teacherService => Provider.of<TeacherService>(context, listen: false);
  List<Map<String, dynamic>> _simulacros = [];
  bool _loading = true;
  String? _selectedSimulacro;
  String? _selectedGrado;
  String? _selectedAnio;
  bool _generatingPdf = false;

  @override
  void initState() {
    super.initState();
    _loadSimulacros();
  }

  Future<void> _loadSimulacros() async {
    setState(() => _loading = true);
    
    final auth = Provider.of<AuthService>(context, listen: false);
    final colegio = auth.colegio ?? '';
    
    if (colegio.isEmpty) {
      _showError('No se encontró el colegio');
      setState(() => _loading = false);
      return;
    }
    
    // ✅ USAR FILTROS QUEMADOS SI NO HAY SELECCIÓN - AÑO 2025 por defecto
    if (_selectedGrado == null) {
      _selectedGrado = '11°'; // Valor por defecto
    }
    if (_selectedAnio == null) {
      _selectedAnio = '2025'; // Valor por defecto (aquí hay datos)
    }
    
    try {
      // ✅ CONEXIÓN REAL AL ENDPOINT
      _simulacros = await _teacherService.fetchAvailableSimulacros(
        colegio, 
        _selectedGrado, 
        _selectedAnio,
      );
      
      debugPrint('📋 Simulacros cargados: ${_simulacros.length}');
      debugPrint('📋 Con filtros - Colegio: $colegio, Grado: $_selectedGrado, Año: $_selectedAnio');
      
      if (_simulacros.isNotEmpty && _selectedSimulacro == null) {
        _selectedSimulacro = _simulacros[0]['id'].toString();
      }
      
    } catch (e) {
      debugPrint('❌ Error cargando simulacros: $e');
      _showError('Error al cargar simulacros: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _generateReport() async {
    if (_simulacros.isEmpty) {
      _showError('No hay simulacros disponibles para generar el informe');
      return;
    }

    if (_selectedSimulacro == null) {
      _selectedSimulacro = _simulacros[0]['id'].toString();
    }

    final auth = Provider.of<AuthService>(context, listen: false);
    final colegio = auth.colegio ?? '';
    
    if (colegio.isEmpty) {
      _showError('No se encontró el colegio');
      return;
    }

    // ✅ CORREGIDO: Validar que exista el simulacro
    Map<String, dynamic>? simulacroSeleccionado;
    try {
      simulacroSeleccionado = _simulacros.firstWhere(
        (s) => s['id'].toString() == _selectedSimulacro,
      );
    } catch (e) {
      if (_simulacros.isNotEmpty) {
        simulacroSeleccionado = _simulacros[0];
        _selectedSimulacro = _simulacros[0]['id'].toString();
      }
    }
    
    if (simulacroSeleccionado == null) {
      _showError('No se pudo encontrar el simulacro seleccionado');
      return;
    }
    
    final courseId = simulacroSeleccionado['course_id'] ?? 0;
    
    if (courseId == 0) {
      _showError('No se encontró el curso para este simulacro');
      return;
    }

    setState(() => _generatingPdf = true);
    
    try {
      final result = await _teacherService.generateReport(
        simulacroId: int.parse(_selectedSimulacro!),
        colegio: colegio,
        courseId: courseId,
        grado: _selectedGrado,
        anio: _selectedAnio,
      );
      
      debugPrint('📋 Resultado generación: $result');
      
      if (result['status'] == 'ok') {
        _showSuccess('Informe generado exitosamente');
        
        final pdfUrl = result['download_url'];
        final fileName = result['file_name'];
        
        if (pdfUrl != null) {
          _downloadPdf(pdfUrl, fileName);
        }
      } else {
        _showError('Error: ${result['message']}');
      }
      
    } catch (e) {
      _showError('Error generando el informe: $e');
    } finally {
      setState(() => _generatingPdf = false);
    }
  }

  Widget _buildSimulacroSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Seleccionar simulacro',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        
        if (_simulacros.isEmpty)
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.surfaceClean,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_rounded, color: AppColors.textDisabled, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'No hay simulacros para $_selectedGrado - $_selectedAnio',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textTertiary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceClean,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: _simulacros.map((simulacro) {
                final isSelected = _selectedSimulacro == simulacro['id'].toString();
                final fecha = simulacro['fecha'] ?? 'Sin fecha';
                final estudiantes = simulacro['total_estudiantes'] ?? 0;
                final promedio = simulacro['promedio_global'] ?? 0.0;
                final nombre = simulacro['nombre'] ?? 'Simulacro';
                
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedSimulacro = simulacro['id'].toString());
                    },
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(_simulacros.indexOf(simulacro) == 0 ? 12 : 0),
                      topRight: Radius.circular(_simulacros.indexOf(simulacro) == 0 ? 12 : 0),
                      bottomLeft: Radius.circular(_simulacros.indexOf(simulacro) == _simulacros.length - 1 ? 12 : 0),
                      bottomRight: Radius.circular(_simulacros.indexOf(simulacro) == _simulacros.length - 1 ? 12 : 0),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: _simulacros.indexOf(simulacro) < _simulacros.length - 1
                              ? BorderSide(color: AppColors.border)
                              : BorderSide.none,
                        ),
                        color: isSelected ? AppColors.primary.withOpacity(0.05) : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary : AppColors.border,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                'S${simulacro['id']}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? AppColors.textOnPrimary : AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nombre,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$fecha • $estudiantes estudiantes • Prom: ${promedio.toStringAsFixed(1)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                                if (simulacro['descripcion'] != null && simulacro['descripcion'].isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      simulacro['descripcion'],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textDisabled,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Future<void> _downloadPdf(String pdfUrl, String fileName) async {
    try {
      debugPrint('📋 Descargando PDF: $fileName');
      debugPrint('📋 URL: $pdfUrl');
      
      _showSuccess('PDF listo para descargar: $fileName');
      
    } catch (e) {
      debugPrint('❌ Error descargando PDF: $e');
      _showError('Error al descargar el PDF: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.successDark,
      ),
    );
  }

  Widget _buildSelectionCard() {
    // ✅ DATOS QUEMADOS TEMPORALES - AÑO 2025 por defecto (donde hay datos)
    final List<String> grados = ['9°', '10°', '11°'];
    final List<String> anios = ['2025', '2026'];
    
    // Asegurar que hay valores seleccionados
    if (_selectedGrado == null && grados.isNotEmpty) {
      _selectedGrado = grados[0];
    }
    if (_selectedAnio == null && anios.isNotEmpty) {
      _selectedAnio = '2025'; // ✅ 2025 por defecto, no el primero (2026)
    }

    return Container(
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configurar informe',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Selecciona los parámetros para el reporte',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 20),
          
          Row(
            children: [
              Expanded(
                child: _buildFilterDropdown(
                  label: 'Grado',
                  value: _selectedGrado,
                  items: grados,
                  onChanged: (value) {
                    setState(() => _selectedGrado = value);
                    _loadSimulacros();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFilterDropdown(
                  label: 'Año',
                  value: _selectedAnio,
                  items: anios,
                  onChanged: (value) {
                    setState(() => _selectedAnio = value);
                    _loadSimulacros();
                  },
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          _buildSimulacroSelector(),
          
          const SizedBox(height: 24),
          
          _buildReportPreview(),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceClean,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: Icon(Icons.arrow_drop_down_rounded, color: AppColors.textTertiary),
              hint: Text(
                'Seleccionar $label',
                style: TextStyle(color: AppColors.textDisabled),
              ),
              items: items.map((item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Row(
                    children: [
                      if (label == 'Grado')
                        Icon(Icons.school_rounded, size: 18, color: AppColors.textTertiary),
                      if (label == 'Año')
                        Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.textTertiary),
                      const SizedBox(width: 8),
                      Text(
                        item,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportPreview() {
    // ✅ CORREGIDO: Primero verificar si hay simulacros
    if (_simulacros.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceClean,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(Icons.visibility_off_rounded, color: AppColors.textDisabled, size: 48),
            const SizedBox(height: 12),
            Text(
              'No hay simulacros disponibles para $_selectedGrado - $_selectedAnio',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Cambia los filtros de grado o año para ver simulacros disponibles',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textDisabled,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // ✅ CORREGIDO: Manejo seguro del simulacro seleccionado
    Map<String, dynamic> simulacro;
    try {
      if (_selectedSimulacro == null) {
        simulacro = _simulacros[0];
        _selectedSimulacro = _simulacros[0]['id'].toString();
      } else {
        simulacro = _simulacros.firstWhere(
          (s) => s['id'].toString() == _selectedSimulacro,
          orElse: () => _simulacros[0],
        );
      }
    } catch (e) {
      simulacro = _simulacros[0];
      _selectedSimulacro = _simulacros[0]['id'].toString();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
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
          const Text(
            'Vista previa del informe',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          
          // Portada
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'INFORME DE SIMULACRO',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  simulacro['nombre'],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 12),
                Divider(color: AppColors.border),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildPreviewItem('Fecha', simulacro['fecha']),
                    _buildPreviewItem('Estudiantes', '${simulacro['total_estudiantes']}'),
                    _buildPreviewItem('Promedio', '${simulacro['promedio_global']}'),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Contenido del informe
          const Text(
            'Contenido del informe:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          
          Column(
            children: [
              _buildContentItem('Resumen ejecutivo del grupo'),
              _buildContentItem('Tabla de resultados por estudiante'),
              _buildContentItem('Ranking de estudiantes por puntaje'),
              _buildContentItem('Análisis de desempeño por áreas'),
              _buildContentItem('Gráficos comparativos'),
              _buildContentItem('Recomendaciones pedagógicas'),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Botón de generación
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _generatingPdf ? null : _generateReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _generatingPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textOnPrimary,
                      ),
                    )
                  : Icon(Icons.picture_as_pdf_rounded, size: 20),
              label: Text(
                _generatingPdf ? 'Generando PDF...' : 'Generar Informe PDF',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildContentItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: AppColors.successDark,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          const SizedBox(height: 20),
          const Text(
            'Cargando simulacros...',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlobalScaffold(
      currentIndex: 3,
      body: _loading
          ? _buildLoadingState()
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  
                  const SizedBox(height: 24),
                  
                  _buildSelectionCard(),
                  
                  const SizedBox(height: 32),
                  
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceClean,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: AppColors.textTertiary, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Información sobre los informes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Los informes PDF generados incluyen datos detallados obtenidos de Moodle, '
                          'incluyendo respuestas correctas e incorrectas por pregunta. Puedes usar estos '
                          'informes para:\n\n'
                          '• Reuniones con padres de familia\n'
                          '• Análisis en consejo académico\n'
                          '• Planificación de refuerzos\n'
                          '• Seguimiento individual de estudiantes\n\n'
                          'Los informes se generan en formato PDF de alta calidad y pueden ser compartidos '
                          'o impresos fácilmente.',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textTertiary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // Agrega este método que falta
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.error, AppColors.errorFg],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.surface.withOpacity(0.3)),
                ),
                child: Icon(Icons.picture_as_pdf_rounded, color: AppColors.surface, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Generar Informes',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Crea reportes detallados en PDF para compartir',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.surface.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Selecciona un simulacro y genera un informe completo con:',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textOnPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFeatureChip('Resultados por estudiante'),
              _buildFeatureChip('Análisis por áreas'),
              _buildFeatureChip('Ranking interno'),
              _buildFeatureChip('Recomendaciones'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surface.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textOnPrimary,
        ),
      ),
    );
  }
}