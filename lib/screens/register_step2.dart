// register_step2.dart - Rediseñado con estilo consistente
import '../config/env.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'verify_email_screen.dart';
import '../widgets/profile_avatar_widget.dart';
import '../core/theme/app_colors.dart';

class RegisterStep2 extends StatefulWidget {
  final String nombre;
  final String email;
  final String telefono;
  final String username;
  final File? selectedImage;
  final String? selectedAvatarAsset;

  const RegisterStep2({
    Key? key,
    required this.nombre,
    required this.email,
    required this.telefono,
    required this.username,
    this.selectedImage,
    this.selectedAvatarAsset,
  }) : super(key: key);

  @override
  State<RegisterStep2> createState() => _RegisterStep2State();
}

class _RegisterStep2State extends State<RegisterStep2> {
  final _formKey = GlobalKey<FormState>();

  String? _departamento;
  String? _ciudad;
  String? _colegio;
  String? _grado;
  bool _isLoading = false;

  List<String> _departamentos = [];
  List<String> _ciudades = [];
  List<String> _colegios = [];
  List<String> _filteredColegios = [];

  bool _loadingDepartamentos = false;
  bool _loadingCiudades = false;
  bool _loadingColegios = false;

  final _colegioController = TextEditingController();

  final baseUrl = Env.apiBaseUrl;

  @override
  void initState() {
    super.initState();
    _loadDepartamentos();
  }

  Future<void> _loadDepartamentos() async {
    setState(() => _loadingDepartamentos = true);
    try {
      final response = await http.get(Uri.parse("$baseUrl/departamentos.php"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _departamentos = List<String>.from(data["departamentos"]);
        });
      }
    } catch (e) {
      debugPrint("❌ Error cargando departamentos: $e");
    } finally {
      setState(() => _loadingDepartamentos = false);
    }
  }

  Future<void> _loadCiudades(String departamento) async {
    setState(() {
      _loadingCiudades = true;
      _ciudades = [];
      _ciudad = null;
    });
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/municipios.php?departamento=$departamento"),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _ciudades = List<String>.from(data["municipios"]);
        });
      }
    } catch (e) {
      debugPrint("❌ Error cargando municipios: $e");
    } finally {
      setState(() => _loadingCiudades = false);
    }
  }

  Future<void> _loadColegios(String departamento, String ciudad) async {
    setState(() {
      _loadingColegios = true;
      _colegios = [];
      _filteredColegios = [];
    });
    try {
      final response = await http.get(Uri.parse(
          "$baseUrl/colegios.php?departamento=$departamento&municipio=$ciudad"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final colegios = List<String>.from(data["colegios"]);
        colegios.sort((a, b) => a.compareTo(b));
        setState(() {
          _colegios = colegios;
          _filteredColegios = colegios;
        });
      }
    } catch (e) {
      debugPrint("❌ Error cargando colegios: $e");
    } finally {
      setState(() => _loadingColegios = false);
    }
  }

  void _filterColegios(String query) {
    setState(() {
      _filteredColegios = _colegios
          .where((c) => c.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  Future<void> _registerUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final uri = Uri.parse('$baseUrl/register.php');

    final body = {
      "nombre": widget.nombre,
      "email": widget.email,
      "telefono": widget.telefono,
      "departamento": _departamento ?? '',
      "ciudad": _ciudad ?? '',
      "colegio": _colegio ?? '',
      "grado": _grado ?? '',
      "username": widget.username,
      "tipo_usuario": "estudiante",
      "avatar": await _encodeAvatar(),
    };

    try {
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final jsonResp = jsonDecode(response.body);
        if (jsonResp['status'] == 'ok') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(jsonResp['msg'] ?? "Registro exitoso"),
              backgroundColor: AppColors.successDark,
            ),
          );
          // ✅ FIX: pasar userId como int (no String)
          final userId = jsonResp['user_id'] as int;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => VerifyEmailScreen(
                email: widget.email,
                userId: userId,
                selectedImage: widget.selectedImage,
                selectedAvatarAsset: widget.selectedAvatarAsset,
              ),
            ),
          );
        } else {
          _showDialog(
            title: "Error",
            message: jsonResp['msg'] ?? "No se pudo registrar.",
            success: false,
          );
        }
      } else {
        _showDialog(
          title: "Error",
          message: "Respuesta inesperada del servidor (${response.statusCode}).",
          success: false,
        );
      }
    } catch (e) {
      _showDialog(
        title: "Error de conexión",
        message: "No se pudo conectar con el servidor.",
        success: false,
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<String?> _encodeAvatar() async {
    try {
      if (widget.selectedImage != null) {
        final bytes = await widget.selectedImage!.readAsBytes();
        return base64Encode(bytes);
      } else if (widget.selectedAvatarAsset != null) {
        final bytes = await DefaultAssetBundle.of(context)
            .load(widget.selectedAvatarAsset!);
        return base64Encode(bytes.buffer.asUint8List());
      }
    } catch (e) {
      debugPrint("❌ Error convirtiendo avatar: $e");
    }
    return null;
  }

  void _showDialog({
    required String title,
    required String message,
    required bool success,
  }) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: success ? AppColors.successLight : AppColors.errorLight,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: success ? AppColors.successDark : AppColors.errorFg,
                    width: 2,
                  ),
                ),
                child: Icon(
                  success ? Icons.check_rounded : Icons.error_outline_rounded,
                  color: success ? AppColors.successDark : AppColors.errorDark,
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: success ? AppColors.successDark : AppColors.errorDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'ENTENDIDO',
                    style: TextStyle(
                      color: AppColors.textOnPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
    required String? Function(String?)? validator,
    bool isLoading = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.borderDark,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.border,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Icon(
                  icon,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Cargando...',
                          style: TextStyle(
                            color: AppColors.textDisabled,
                            fontSize: 15,
                          ),
                        ),
                      )
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: value,
                          isExpanded: true,
                          icon: Icon(
                            Icons.arrow_drop_down_rounded,
                            color: AppColors.textTertiary,
                          ),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                          ),
                          dropdownColor: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          menuMaxHeight: 300,
                          hint: Text(
                            'Selecciona $label',
                            style: TextStyle(
                              color: AppColors.textDisabled,
                            ),
                          ),
                          items: items
                              .map((item) => DropdownMenuItem<String>(
                                    value: item,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: Text(
                                        item,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ))
                              .toList(),
                          onChanged: onChanged,
                        ),
                      ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
        if (validator != null && validator(value) != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              validator(value) ?? '',
              style: TextStyle(
                color: AppColors.errorDark,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInputField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    required void Function(String) onChanged,
    required String? Function(String?)? validator,
    bool showSuggestions = false,
    List<String> suggestions = const [],
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.borderDark,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.border,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Icon(
                  icon,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  onChanged: onChanged,
                  validator: validator,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: AppColors.textDisabled,
                      fontSize: 15,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
        if (showSuggestions && suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.border,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadowSm,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final colegio = suggestions[index];
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _colegio = colegio;
                          controller.text = colegio;
                          _filteredColegios = [];
                        });
                        FocusScope.of(context).unfocus();
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.school_rounded,
                              size: 16,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                colegio,
                                style: TextStyle(
                                  color: AppColors.borderDark,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              // 🔹 Header con progreso
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Logo pequeño
                    Image.asset(
                      'assets/logo.png',
                      height: 60,
                      color: AppColors.textOnPrimary,
                    ),
                    const SizedBox(height: 16),
                    // Progreso
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildProgressStep(number: 1, label: 'Datos', isActive: false),
                        Container(
                          width: 40,
                          height: 2,
                          color: AppColors.surface.withOpacity(0.5),
                        ),
                        _buildProgressStep(number: 2, label: 'Institucionales', isActive: true),
                        Container(
                          width: 40,
                          height: 2,
                          color: AppColors.surface.withOpacity(0.5),
                        ),
                        _buildProgressStep(number: 3, label: 'Contraseña', isActive: false),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // 🔹 Avatar de visualización
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowLg,
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: widget.selectedImage != null
                      ? Image.file(
                          widget.selectedImage!,
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        )
                      : widget.selectedAvatarAsset != null
                          ? Image.asset(
                              widget.selectedAvatarAsset!,
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: AppColors.surfaceClean,
                              child: Icon(
                                Icons.person_rounded,
                                size: 48,
                                color: AppColors.textDisabled,
                              ),
                            ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Completa tus datos institucionales',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Información de tu colegio y grado académico',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              // 🔹 Formulario
              Container(
                padding: const EdgeInsets.all(24),
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
                    color: AppColors.border,
                    width: 1,
                  ),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Departamento
                      _buildDropdownField(
                        label: 'Departamento',
                        icon: Icons.map_rounded,
                        value: _departamento,
                        items: _departamentos,
                        onChanged: (v) {
                          setState(() => _departamento = v);
                          if (v != null) _loadCiudades(v);
                        },
                        validator: (v) => v == null ? "Selecciona un departamento" : null,
                        isLoading: _loadingDepartamentos,
                      ),
                      const SizedBox(height: 20),
                      // Ciudad/Municipio
                      _buildDropdownField(
                        label: 'Ciudad / Municipio',
                        icon: Icons.location_city_rounded,
                        value: _ciudad,
                        items: _ciudades,
                        onChanged: (v) {
                          setState(() => _ciudad = v);
                          if (_departamento != null && v != null) {
                            _loadColegios(_departamento!, v);
                          }
                        },
                        validator: (v) => v == null ? "Selecciona una ciudad" : null,
                        isLoading: _loadingCiudades,
                      ),
                      const SizedBox(height: 20),
                      // Institución educativa (autocompletado)
                      _buildInputField(
                        label: 'Institución educativa',
                        icon: Icons.school_rounded,
                        controller: _colegioController,
                        hint: 'Busca o escribe tu colegio',
                        onChanged: (v) {
                          _colegio = v;
                          _filterColegios(v);
                        },
                        validator: (v) =>
                            v == null || v.isEmpty ? "Ingresa o selecciona tu colegio" : null,
                        showSuggestions:
                            _filteredColegios.isNotEmpty && _colegioController.text.isNotEmpty,
                        suggestions: _filteredColegios,
                      ),
                      const SizedBox(height: 20),
                      // Grado
                      _buildDropdownField(
                        label: 'Grado académico',
                        icon: Icons.school_rounded,
                        value: _grado,
                        items: const [
                          "9°",
                          "10°",
                          "11°",
                          "Egresado",
                          "Graduado",
                        ],
                        onChanged: (v) => setState(() => _grado = v),
                        validator: (v) => v == null ? "Selecciona tu grado" : null,
                      ),
                      const SizedBox(height: 32),
                      // Botón Registrar
                      SizedBox(
                        height: 52,
                        child: Material(
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: _isLoading ? null : _registerUser,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: _isLoading
                                    ? null
                                    : const LinearGradient(
                                        colors: [AppColors.primary, AppColors.primaryLight],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: _isLoading
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: AppColors.primary.withOpacity(0.3),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                color: _isLoading ? AppColors.textDisabled : null,
                              ),
                              child: Center(
                                child: _isLoading
                                    ? const CircularProgressIndicator(
                                        color: AppColors.textOnPrimary,
                                        strokeWidth: 2,
                                      )
                                    : const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'COMPLETAR REGISTRO',
                                            style: TextStyle(
                                              color: AppColors.textOnPrimary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Icon(
                                            Icons.check_circle_rounded,
                                            color: AppColors.textOnPrimary,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Información adicional
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.infoBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.infoBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: AppColors.sky,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Tus datos institucionales nos ayudan a personalizar tu experiencia',
                                style: TextStyle(
                                  color: AppColors.infoDark,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              // Footer
              Text(
                'Paso 2 de 3 • PrepSaber © 2024',
                style: TextStyle(
                  color: AppColors.textDisabled,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressStep({
    required int number,
    required String label,
    required bool isActive,
  }) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? AppColors.textOnPrimary : AppColors.surface.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number.toString(),
              style: TextStyle(
                color: isActive ? AppColors.primary : AppColors.textOnPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textOnPrimary,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}