import '../config/env.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'verify_email_screen.dart';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _colegioController = TextEditingController();

  String? _selectedDepartamento;
  String? _selectedCiudad;
  String? _selectedGrado;
  bool _loading = false;

  List<String> _departamentos = [];
  List<String> _ciudades = [];
  List<String> _colegios = [];
  List<String> _filteredColegios = [];

  bool _loadingDepartamentos = false;
  bool _loadingCiudades = false;
  bool _loadingColegios = false;

  final baseUrl = "Env.apiBaseUrl";

  File? _selectedImage;
  String? _selectedAvatarAsset;

  final List<String> _avatarAssets = List.generate(
    27,
    (i) => 'assets/avatars/avatar_${i + 1}.png',
  );

  @override
  void initState() {
    super.initState();
    _loadDepartamentos();
    _setRandomAvatar();
  }

  void _setRandomAvatar() {
    final random = Random();
    setState(() {
      _selectedAvatarAsset = _avatarAssets[random.nextInt(_avatarAssets.length)];
    });
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
      _selectedCiudad = null;
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

  Future<void> _pickImage() async {
    final picker = ImagePicker();

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(Icons.photo_library, color: AppColors.subjectTeal),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt, color: AppColors.subjectTeal),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.person, color: AppColors.subjectTeal),
              title: const Text('Elegir avatar de la app'),
              onTap: () {
                Navigator.pop(context);
                _showAvatarSelector();
              },
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      final pickedFile =
          await picker.pickImage(source: source, imageQuality: 70);
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _selectedAvatarAsset = null; // si toma foto o galería, se descarta avatar
        });
      }
    }
  }

  void _showAvatarSelector() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Selecciona tu avatar'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            itemCount: _avatarAssets.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemBuilder: (context, index) {
              final asset = _avatarAssets[index];
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedAvatarAsset = asset;
                    _selectedImage = null;
                  });
                  Navigator.pop(context);
                },
                child: CircleAvatar(
                  backgroundImage: AssetImage(asset),
                  radius: 30,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final body = {
      "nombre": _nombreController.text.trim(),
      "email": _emailController.text.trim(),
      "telefono": _telefonoController.text.trim(),
      "departamento": _selectedDepartamento ?? '',
      "ciudad": _selectedCiudad ?? '',
      "colegio": _colegioController.text.trim(),
      "grado": _selectedGrado ?? '',
      "tipo_usuario": "estudiante",
    };

    try {
      final request = http.MultipartRequest(
        "POST",
        Uri.parse("$baseUrl/register.php"),
      );
      request.fields['data'] = json.encode(body);

      // Imagen o avatar predefinido
      if (_selectedImage != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'avatar',
          _selectedImage!.path,
        ));
      } else if (_selectedAvatarAsset != null) {
        final bytes = await DefaultAssetBundle.of(context)
            .load(_selectedAvatarAsset!);
        final temp = File('${Directory.systemTemp.path}/temp_avatar.png');
        await temp.writeAsBytes(bytes.buffer.asUint8List());
        request.files.add(await http.MultipartFile.fromPath('avatar', temp.path));
      }

      final response = await request.send();
      final respStr = await response.stream.bytesToString();
      final jsonResp = json.decode(respStr);

      if (response.statusCode == 200 && jsonResp['status'] == 'ok') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(jsonResp['msg'] ?? 'Registro exitoso')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => VerifyEmailScreen(
              email: _emailController.text.trim(),
              userId: jsonResp['user_id'].toString(),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(jsonResp['msg'] ?? 'Error en el registro')),
        );
      }
    } catch (e) {
      debugPrint("❌ Error en registro: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error de conexión con el servidor")),
      );
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceClean,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/logo.png', height: 80),
                    const SizedBox(height: 12),
                    const Text(
                      'Crea tu cuenta',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.subjectTeal,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 📸 Avatar selector
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 45,
                          backgroundColor: AppColors.stepInactive,
                          backgroundImage: _selectedImage != null
                              ? FileImage(_selectedImage!)
                              : (_selectedAvatarAsset != null
                                  ? AssetImage(_selectedAvatarAsset!)
                                  : null) as ImageProvider<Object>?,
                          child: (_selectedImage == null &&
                                  _selectedAvatarAsset == null)
                              ? Icon(Icons.person,
                                  size: 50, color: AppColors.textOnPrimary)
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 4,
                          child: InkWell(
                            onTap: _pickImage,
                            child: const CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.subjectTeal,
                              child: Icon(Icons.camera_alt,
                                  color: AppColors.textOnPrimary, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nombreController,
                      decoration: InputDecoration(
                        labelText: 'Nombre completo',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v!.isEmpty ? "Ingrese su nombre completo" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v!.contains('@') ? null : "Correo inválido",
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _telefonoController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Teléfono',
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.isEmpty
                          ? "Ingrese su teléfono"
                          : (v.length < 7 ? "Teléfono inválido" : null),
                    ),
                    const SizedBox(height: 16),

                    // 📍 Departamento
                    DropdownButtonFormField<String>(
                      value: _selectedDepartamento,
                      decoration: InputDecoration(
                        labelText: 'Departamento',
                        prefixIcon: Icon(Icons.map),
                        border: OutlineInputBorder(),
                      ),
                      items: _departamentos
                          .map((d) =>
                              DropdownMenuItem(value: d, child: Text(d)))
                          .toList(),
                      onChanged: (v) {
                        setState(() => _selectedDepartamento = v);
                        _loadCiudades(v!);
                      },
                      validator: (v) =>
                          v == null ? "Seleccione un departamento" : null,
                    ),
                    const SizedBox(height: 16),

                    // 🏙 Ciudad
                    DropdownButtonFormField<String>(
                      value: _selectedCiudad,
                      decoration: InputDecoration(
                        labelText: 'Ciudad / Municipio',
                        prefixIcon: Icon(Icons.location_city),
                        border: OutlineInputBorder(),
                      ),
                      items: _ciudades
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) {
                        setState(() => _selectedCiudad = v);
                        if (_selectedDepartamento != null && v != null) {
                          _loadColegios(_selectedDepartamento!, v);
                        }
                      },
                      validator: (v) =>
                          v == null ? "Seleccione una ciudad" : null,
                    ),
                    const SizedBox(height: 16),

                    // 🏫 Colegio
                    _loadingColegios
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: _colegioController,
                                decoration: InputDecoration(
                                  labelText: 'Colegio',
                                  prefixIcon: Icon(Icons.school),
                                  border: OutlineInputBorder(),
                                  hintText: 'Escriba parte del nombre',
                                ),
                                onChanged: _filterColegios,
                                validator: (v) => v!.isEmpty
                                    ? "Ingrese o seleccione su colegio"
                                    : null,
                              ),
                              if (_filteredColegios.isNotEmpty &&
                                  _colegioController.text.isNotEmpty)
                                Container(
                                  constraints:
                                      const BoxConstraints(maxHeight: 200),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: AppColors.stepInactive),
                                    borderRadius: BorderRadius.circular(8),
                                    color: AppColors.surface,
                                  ),
                                  child: ListView.builder(
                                    itemCount: _filteredColegios.length,
                                    itemBuilder: (context, index) {
                                      final colegio =
                                          _filteredColegios[index];
                                      return ListTile(
                                        title: Text(colegio),
                                        onTap: () {
                                          _colegioController.text = colegio;
                                          FocusScope.of(context).unfocus();
                                          setState(() {
                                            _filteredColegios = [];
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                    const SizedBox(height: 16),

                    // 🎓 Grado
                    DropdownButtonFormField<String>(
                      value: _selectedGrado,
                      decoration: InputDecoration(
                        labelText: 'Grado',
                        prefixIcon: Icon(Icons.class_),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: "9°", child: Text("9°")),
                        DropdownMenuItem(value: "10°", child: Text("10°")),
                        DropdownMenuItem(value: "11°", child: Text("11°")),
                        DropdownMenuItem(value: "Egresado", child: Text("Egresado")),
                        DropdownMenuItem(value: "Graduado", child: Text("Graduado")),
                      ],
                      onChanged: (v) => setState(() => _selectedGrado = v),
                      validator: (v) =>
                          v == null ? "Seleccione su grado" : null,
                    ),
                    const SizedBox(height: 24),

                    // 🟢 Botón
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const AppColors.subjectTeal,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.textOnPrimary,
                                ),
                              )
                            : const Text(
                                'Registrar',
                                style: TextStyle(
                                    fontSize: 16, color: AppColors.textOnPrimary),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextButton(
                      onPressed: () =>
                          Nav.goLogin(context),
                      child: const Text(
                        '¿Ya tienes cuenta? Inicia sesión',
                        style: TextStyle(color: AppColors.subjectTeal),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
