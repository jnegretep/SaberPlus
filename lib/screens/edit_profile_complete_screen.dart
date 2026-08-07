import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../config/env.dart';
import '../widgets/global_scaffold.dart';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';

class EditProfileCompleteScreen extends StatefulWidget {
  const EditProfileCompleteScreen({Key? key}) : super(key: key);

  @override
  State<EditProfileCompleteScreen> createState() => _EditProfileCompleteScreenState();
}

class _EditProfileCompleteScreenState extends State<EditProfileCompleteScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  // Controladores solo para campos editables
  final _nombreController = TextEditingController();
  final _telefonoController = TextEditingController();
  
  // Controladores para campos de solo lectura
  final _departamentoController = TextEditingController();
  final _ciudadController = TextEditingController();
  final _colegioController = TextEditingController();
  final _gradoController = TextEditingController();

  // Variables de estado
  File? _selectedImage;
  String? _selectedAvatarAsset;
  String? _currentAvatarUrl;
  
  bool _loading = true;
  bool _saving = false;

  // Avatar assets
  final List<String> _avatarAssets = List.generate(27, (i) => 'assets/avatars/avatar_${i + 1}.png');

  // URLs base
  late String _baseUrl;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthService>(context, listen: false);
    _baseUrl = Env.apiBaseUrl;
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() => _loading = true);
    final auth = Provider.of<AuthService>(context, listen: false);
    
    try {
      // Cargar perfil actual
      await auth.fetchProfile();
      
      // Establecer valores en controladores
      _nombreController.text = auth.nombre ?? '';
      _telefonoController.text = auth.user?['telefono'] ?? '';
      _departamentoController.text = auth.departamento ?? '';
      _ciudadController.text = auth.ciudad ?? '';
      _colegioController.text = auth.colegio ?? '';
      _gradoController.text = auth.grado ?? '';
      _currentAvatarUrl = auth.avatarUrl;
      
    } catch (e) {
      debugPrint('Error cargando datos: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // [Mantener los métodos _pickImage, _buildBottomSheetOption, _showAvatarSelector, _encodeAvatar iguales]

Future<void> _pickImage() async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    backgroundColor: AppColors.surface,
    builder: (_) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barra de agarre
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Título
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  const Text(
                    'Cambiar foto de perfil',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Elige cómo quieres actualizar tu foto',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            
            // Espacio flexible para las opciones
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildBottomSheetOption(
                        icon: Icons.photo_library_rounded,
                        title: 'Galería',
                        subtitle: 'Elegir de tus fotos',
                        color: AppColors.primaryLight,
                        onTap: () => Navigator.pop(context, ImageSource.gallery),
                      ),
                      const SizedBox(height: 10),
                      _buildBottomSheetOption(
                        icon: Icons.camera_alt_rounded,
                        title: 'Cámara',
                        subtitle: 'Tomar una foto',
                        color: AppColors.successDark,
                        onTap: () => Navigator.pop(context, ImageSource.camera),
                      ),
                      const SizedBox(height: 10),
                      _buildBottomSheetOption(
                        icon: Icons.face_rounded,
                        title: 'Avatar',
                        subtitle: 'Elegir un avatar prediseñado',
                        color: AppColors.purple,
                        onTap: () {
                          Navigator.pop(context);
                          _showAvatarSelector();
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
            
            // Botón cancelar (fuera del scroll)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AppColors.border,
                    width: 1,
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    backgroundColor: AppColors.surfaceVariant,
                  ),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  if (source != null) {
    final pickedFile = await _picker.pickImage(source: source, imageQuality: 70);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
        _selectedAvatarAsset = null;
        _currentAvatarUrl = null;
      });
    }
  }
}

  Widget _buildBottomSheetOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: color.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: color.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  icon,
                  color: color,
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
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: color,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAvatarSelector() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: AppColors.surface,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Elige tu avatar',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textOnPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Selecciona una imagen que te represente',
                        style: TextStyle(
                          color: AppColors.textOnPrimarySubtle,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.surface.withOpacity(0.3)),
                        ),
                        child: Icon(
                          Icons.face_rounded,
                          color: AppColors.textOnPrimary,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _avatarAssets.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (context, index) {
                      final asset = _avatarAssets[index];
                      final isSelected = _selectedAvatarAsset == asset;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedAvatarAsset = asset;
                            _selectedImage = null;
                            _currentAvatarUrl = null;
                          });
                          Navigator.pop(context);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.border,
                              width: isSelected ? 2 : 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.shadowMd,
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              asset,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            backgroundColor: AppColors.surfaceVariant,
                          ),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Listo',
                            style: TextStyle(
                              color: AppColors.textOnPrimary,
                              fontWeight: FontWeight.w600,
                            ),
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
      ),
    );
  }

  Future<String?> _encodeAvatar() async {
    try {
      if (_selectedImage != null) {
        final bytes = await _selectedImage!.readAsBytes();
        return base64Encode(bytes);
      } else if (_selectedAvatarAsset != null) {
        final bytes = await DefaultAssetBundle.of(context).load(_selectedAvatarAsset!);
        return base64Encode(bytes.buffer.asUint8List());
      }
    } catch (e) {
      debugPrint("Error convirtiendo avatar: $e");
    }
    return null;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _saving = true);
    
    final auth = Provider.of<AuthService>(context, listen: false);
    final avatarBase64 = await _encodeAvatar();

    // SOLO enviar campos editables + identificadores
    final body = {
      "nombre": _nombreController.text.trim(),
      "telefono": _telefonoController.text.trim(),
      "username": auth.username,
      "email": auth.user?['email'],
      if (avatarBase64 != null) "avatar": avatarBase64,
    };

    try {
      final url = Uri.parse("$_baseUrl/update_profile.php");
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          if (auth.token != null) "Authorization": "Bearer ${auth.token}",
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (data['status'] == 'ok') {
        await auth.fetchProfile();
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Perfil actualizado correctamente',
              style: TextStyle(color: AppColors.textOnPrimary),
            ),
            backgroundColor: AppColors.successDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        
        Navigator.pop(context);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['msg'] ?? "Error al actualizar perfil",
              style: TextStyle(color: AppColors.textOnPrimary),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Error de conexión: $e",
            style: TextStyle(color: AppColors.textOnPrimary),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildInputField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    bool readOnly = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
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
            color: readOnly ? AppColors.surfaceClean : AppColors.surface,
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
                  readOnly: readOnly,
                  keyboardType: keyboardType,
                  validator: validator,
                  style: TextStyle(
                    color: readOnly 
                        ? AppColors.textTertiary
                        : AppColors.textSecondary,
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
            ],
          ),
        ),
      ],
    );
  }

  // Nuevo método para campos de solo lectura con mejor estilo
  Widget _buildReadOnlyField({
    required String label,
    required IconData icon,
    required String value,
    String hint = '',
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
            color: AppColors.surfaceClean,
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
                  color: AppColors.textDisabled,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    value.isNotEmpty ? value : hint,
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final size = MediaQuery.of(context).size;

    return GlobalScaffold(
      currentIndex: 1,
      body: _loading
          ? _buildLoadingState()
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(24),
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
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceClean,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.textOnPrimary,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  if (_selectedImage != null)
                                    ClipOval(
                                      child: Image.file(
                                        _selectedImage!,
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  else if (_selectedAvatarAsset != null)
                                    ClipOval(
                                      child: Image.asset(
                                        _selectedAvatarAsset!,
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  else if (_currentAvatarUrl != null && _currentAvatarUrl!.isNotEmpty)
                                    ClipOval(
                                      child: Image.network(
                                        _currentAvatarUrl!,
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Icon(
                                            Icons.person_rounded,
                                            size: 48,
                                            color: AppColors.textDisabled,
                                          );
                                        },
                                      ),
                                    )
                                  else
                                    Icon(
                                      Icons.person_rounded,
                                      size: 48,
                                      color: AppColors.textDisabled,
                                    ),
                                  Positioned(
                                    right: 4,
                                    bottom: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primary.withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.edit_rounded,
                                        color: AppColors.textOnPrimary,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Editar perfil',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textOnPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Actualiza tu información personal',
                            style: TextStyle(
                              color: AppColors.textOnPrimarySubtle,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Información personal (EDITABLE)
                    Container(
                      padding: const EdgeInsets.all(20),
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
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Información personal',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Datos básicos de tu cuenta',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Column(
                            children: [
                              _buildInputField(
                                label: 'Nombre completo',
                                icon: Icons.person_rounded,
                                controller: _nombreController,
                                hint: 'Ingresa tu nombre completo',
                                validator: (v) =>
                                    v!.isEmpty ? "Ingresa tu nombre completo" : null,
                              ),
                              const SizedBox(height: 16),
                              _buildInputField(
                                label: 'Teléfono',
                                icon: Icons.phone_rounded,
                                controller: _telefonoController,
                                hint: 'Ingresa tu número telefónico',
                                keyboardType: TextInputType.phone,
                                validator: (v) => v == null || v.isEmpty
                                    ? "Ingresa tu teléfono"
                                    : (v.length < 7 ? "Teléfono inválido" : null),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Ubicación (SOLO LECTURA)
                    Container(
                      padding: const EdgeInsets.all(20),
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
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ubicación',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Información de tu localización',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Column(
                            children: [
                              _buildReadOnlyField(
                                label: 'Departamento',
                                icon: Icons.map_rounded,
                                value: _departamentoController.text,
                                hint: 'No asignado',
                              ),
                              const SizedBox(height: 16),
                              _buildReadOnlyField(
                                label: 'Ciudad / Municipio',
                                icon: Icons.location_city_rounded,
                                value: _ciudadController.text,
                                hint: 'No asignado',
                              ),
                              const SizedBox(height: 16),
                              _buildReadOnlyField(
                                label: 'Institución educativa',
                                icon: Icons.school_rounded,
                                value: _colegioController.text,
                                hint: 'No asignado',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Información académica (SOLO LECTURA)
                    Container(
                      padding: const EdgeInsets.all(20),
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
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Información académica',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Datos de tu institución educativa',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildReadOnlyField(
                            label: 'Grado académico',
                            icon: Icons.school_rounded,
                            value: _gradoController.text,
                            hint: 'No asignado',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Información de cuenta (solo lectura)
                    Container(
                      padding: const EdgeInsets.all(20),
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
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Información de cuenta',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Datos que no se pueden modificar',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Column(
                            children: [
                              _buildReadOnlyField(
                                label: 'Usuario',
                                icon: Icons.alternate_email_rounded,
                                value: auth.username ?? '',
                                hint: 'Usuario del sistema',
                              ),
                              const SizedBox(height: 16),
                              _buildReadOnlyField(
                                label: 'Correo electrónico',
                                icon: Icons.email_rounded,
                                value: auth.user?['email'] ?? '',
                                hint: 'Correo electrónico',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Botones de acción
                    Column(
                      children: [
                        _saving
                            ? Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          AppColors.textOnPrimary),
                                    ),
                                  ),
                                ),
                              )
                            : ElevatedButton(
                                onPressed: _saveProfile,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: AppColors.textOnPrimary,
                                  minimumSize: Size(size.width, 56),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.save_rounded, size: 20),
                                    SizedBox(width: 10),
                                    Text(
                                      'Guardar cambios',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            Nav.goChangePassword(context);
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textTertiary,
                            minimumSize: Size(size.width, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_reset_rounded, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Cambiar contraseña',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
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
            'Cargando perfil...',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}