// register_step1.dart - Rediseñado con estilo consistente
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'register_step2.dart';
import '../widgets/profile_avatar_widget.dart';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';

class RegisterStep1 extends StatefulWidget {
  const RegisterStep1({Key? key}) : super(key: key);

  @override
  State<RegisterStep1> createState() => _RegisterStep1State();
}

class _RegisterStep1State extends State<RegisterStep1> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _usernameController = TextEditingController();

  File? _selectedImage;
  String? _selectedAvatarAsset;

  final List<String> _avatarAssets =
      List.generate(27, (i) => 'assets/avatars/avatar_${i + 1}.png');

  @override
  void initState() {
    super.initState();
    _setRandomAvatar();
  }

  // 🔧 Normalizar texto: quitar tildes, ñ y caracteres especiales
  String _normalizeText(String input) {
    const withAccents = 'áéíóúÁÉÍÓÚñÑ';
    const withoutAccents = 'aeiouAEIOUnN';
    var normalized = input;
    for (int i = 0; i < withAccents.length; i++) {
      normalized = normalized.replaceAll(withAccents[i], withoutAccents[i]);
    }
    // Solo letras y números
    normalized = normalized.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    return normalized.toLowerCase();
  }

  // Generar usuario único basado en nombre + número aleatorio
  void _generateUsername() {
    final nombre = _nombreController.text.trim().toLowerCase();
    if (nombre.isEmpty) return;

    final parts = nombre.split(' ');
    String base = '';
    if (parts.isNotEmpty) {
      base = parts[0][0]; // primera letra del primer nombre
      if (parts.length > 1) {
        base += parts.last; // apellido completo
      }
    }

    // Normalizar para quitar acentos y ñ
    base = _normalizeText(base);

    final randomNumber = Random().nextInt(9000) + 1000; // 4 dígitos
    final username = '$base$randomNumber';

    setState(() {
      _usernameController.text = username;
    });
  }

  void _setRandomAvatar() {
    final random = Random();
    setState(() {
      _selectedAvatarAsset =
          _avatarAssets[random.nextInt(_avatarAssets.length)];
    });
  }

Future<void> _pickImage() async {
  final picker = ImagePicker();

  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    isScrollControlled: true, // IMPORTANTE: Permite controlar el scroll
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    backgroundColor: AppColors.surface,
    builder: (_) => SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7, // Limita la altura máxima
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barra de agarre
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4), // Reducido
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Título
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Reducido
              child: Column(
                children: [
                  const Text(
                    'Seleccionar foto de perfil',
                    style: TextStyle(
                      fontSize: 16, // Reducido de 18
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2), // Reducido
                  const Text(
                    'Elige cómo quieres tu foto de perfil',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13, // Reducido de 14
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            
            // Opciones con scroll
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Reducido
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
                      const SizedBox(height: 10), // Reducido
                      _buildBottomSheetOption(
                        icon: Icons.camera_alt_rounded,
                        title: 'Cámara',
                        subtitle: 'Tomar una foto',
                        color: AppColors.successDark,
                        onTap: () => Navigator.pop(context, ImageSource.camera),
                      ),
                      const SizedBox(height: 10), // Reducido
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
                      const SizedBox(height: 16), // Reducido
                    ],
                  ),
                ),
              ),
            ),
            
            // Botón cancelar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 15, // Reducido
                    fontWeight: FontWeight.w600,
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
    final pickedFile =
        await picker.pickImage(source: source, imageQuality: 70);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
        _selectedAvatarAsset = null;
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
      borderRadius: BorderRadius.circular(10), // Reducido
      child: Container(
        padding: const EdgeInsets.all(14), // Reducido de 16
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10), // Reducido
          border: Border.all(
            color: color.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44, // Reducido de 48
              height: 44, // Reducido de 48
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10), // Reducido
                border: Border.all(
                  color: color.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                color: color,
                size: 22, // Reducido de 24
              ),
            ),
            const SizedBox(width: 14), // Reducido de 16
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15, // Reducido de 16
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 1), // Reducido de 2
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12, // Reducido de 13
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: color,
              size: 14, // Reducido de 16
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
        borderRadius: BorderRadius.circular(16), // Reducido de 20
      ),
      backgroundColor: AppColors.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8, // Limita altura
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20), // Reducido de 24
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
                        fontSize: 18, // Reducido de 20
                        fontWeight: FontWeight.w700,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
                    const SizedBox(height: 2), // Reducido
                    const Text(
                      'Selecciona una imagen que te represente',
                      style: TextStyle(
                        color: AppColors.textOnPrimarySubtle,
                        fontSize: 13, // Reducido de 14
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12), // Reducido
                    Container(
                      padding: const EdgeInsets.all(10), // Reducido
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10), // Reducido
                        border: Border.all(color: AppColors.surface.withOpacity(0.3)),
                      ),
                      child: Icon(
                        Icons.face_rounded,
                        color: AppColors.textOnPrimary,
                        size: 32, // Reducido
                      ),
                    ),
                  ],
                ),
              ),
              
              // Grid de avatares - Más compacto
              Container(
                padding: const EdgeInsets.all(16), // Reducido
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _avatarAssets.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8, // Reducido de 12
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
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12), // Reducido
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.border,
                            width: isSelected ? 2 : 1.5, // Reducido
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.shadowMd, // Reducido
                              blurRadius: 6, // Reducido
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10), // Reducido
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
              
              // Footer más compacto
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), // Reducido
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10), // Reducido
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10), // Reducido
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
                    const SizedBox(width: 10), // Reducido
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 10), // Reducido
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10), // Reducido
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

  void _nextStep() {
    if (_formKey.currentState!.validate()) {
      _generateUsername();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RegisterStep2(
            nombre: _nombreController.text.trim(),
            email: _emailController.text.trim(),
            telefono: _telefonoController.text.trim(),
            username: _usernameController.text.trim(),
            selectedImage: _selectedImage,
            selectedAvatarAsset: _selectedAvatarAsset,
          ),
        ),
      );
    }
  }

  Widget _buildInputField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    bool readOnly = false,
    bool autoGenerate = false,
    VoidCallback? onChanged,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.borderDark,
              ),
            ),
            if (autoGenerate)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.successDark),
                ),
                child: const Text(
                  'AUTO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.successDark,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: readOnly 
                ? AppColors.surfaceClean
                : AppColors.surface,
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
                  onChanged: onChanged != null ? (_) => onChanged() : null,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              // 🔹 Logo y progreso
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
                    // Logo
                    Image.asset(
                      'assets/logo.png',
                      height: 80,
                      color: AppColors.textOnPrimary,
                    ),
                    const SizedBox(height: 16),
                    
                    // Progreso
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildProgressStep(number: 1, label: 'Datos', isActive: true),
                        Container(
                          width: 40,
                          height: 2,
                          color: AppColors.surface.withOpacity(0.5),
                        ),
                        _buildProgressStep(number: 2, label: 'Perfil', isActive: false),
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

              // 🔹 Card principal del formulario
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
                      // Avatar selector
                      Column(
                        children: [
                          GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceClean,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.border,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.shadowSm,
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
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  else if (_selectedAvatarAsset != null)
                                    ClipOval(
                                      child: Image.asset(
                                        _selectedAvatarAsset!,
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  else
                                    Center(
                                      child: Icon(
                                        Icons.person_add_alt_1_rounded,
                                        size: 48,
                                        color: AppColors.textDisabled,
                                      ),
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
                          const SizedBox(height: 12),
                          const Text(
                            'Tu foto de perfil',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedImage != null || _selectedAvatarAsset != null
                                ? 'Toca para cambiar'
                                : 'Toca para agregar una foto',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // Campos del formulario
                      Column(
                        children: [
                          _buildInputField(
                            label: 'Nombre completo',
                            icon: Icons.person_rounded,
                            controller: _nombreController,
                            hint: 'Ingresa tu nombre completo',
                            validator: (v) =>
                                v!.isEmpty ? "Ingresa tu nombre completo" : null,
                            onChanged: _generateUsername,
                          ),
                          const SizedBox(height: 20),
                          _buildInputField(
                            label: 'Correo electrónico',
                            icon: Icons.email_rounded,
                            controller: _emailController,
                            hint: 'ejemplo@correo.com',
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) => v!.contains('@')
                                ? null
                                : "Ingresa un correo válido",
                          ),
                          const SizedBox(height: 20),
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
                          const SizedBox(height: 20),
                          _buildInputField(
                            label: 'Usuario único',
                            icon: Icons.alternate_email_rounded,
                            controller: _usernameController,
                            hint: 'Se generará automáticamente',
                            readOnly: true,
                            autoGenerate: true,
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      // Botón siguiente
                      SizedBox(
                        height: 52,
                        child: Material(
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: _nextStep,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppColors.primary, AppColors.primaryLight],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'CONTINUAR AL SIGUIENTE PASO',
                                      style: TextStyle(
                                        color: AppColors.textOnPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(
                                      Icons.arrow_forward_rounded,
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

                      const SizedBox(height: 24),

                      // Enlace a login
                      Center(
                        child: GestureDetector(
                          onTap: () =>
                              Nav.goLogin(context),
                          child: RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textTertiary,
                              ),
                              children: [
                                TextSpan(text: '¿Ya tienes una cuenta? '),
                                TextSpan(
                                  text: 'Inicia sesión aquí',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Footer
              Text(
                'Paso 1 de 3 • PrepSaber © 2024',
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