import 'package:absensiku/models/dio_client.dart';
import 'package:absensiku/services/dio_system.dart';
import 'package:absensiku/views/auth/login_screen.dart';
import 'package:flutter/material.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _namaController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Inisialisasi dioClient dengan createDioClient()
  final dioClient = DioClient(createDioClient());

  // api
  Future<void> _handleRegister() async {
    if (_formKey.currentState!.validate()) {
      _showLoading();
      try {
        final response = await RegisterApiService.register(
          _namaController.text,
          _emailController.text,
          _passwordController.text,
          _confirmPasswordController.text,
        );

        if (mounted) {
          Navigator.pop(context); // Tutup dialog loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message),
              backgroundColor: Colors.green,
            ),
          );
          _handleRegisterSuccess();
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Tutup dialog loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Registrasi gagal: ${e.toString().replaceAll("Exception: ", "")}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // Loading indicator
  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  // Handle register success
  void _handleRegisterSuccess() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  // reset controller saat dispose
  @override
  void dispose() {
    _namaController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register'),
        backgroundColor: Colors.blue,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Daftar Akun Baru",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _namaController,
                  decoration: const InputDecoration(
                    labelText: "Nama",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nama wajib diisi';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: "Email",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Email wajib diisi';
                    }
                    if (!value.contains('@')) {
                      return 'Format email tidak valid';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Password",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Password wajib diisi';
                    }
                    if (value.length < 6) {
                      return 'Password minimal 6 karakter';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Konfirmasi Password",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Konfirmasi password wajib diisi';
                    }
                    if (value != _passwordController.text) {
                      return 'Konfirmasi password tidak cocok';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _handleRegister,
                    child: const Text("Register"),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                    );
                  },
                  child: const Text("Sudah punya akun? Login di sini"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ResponseRegister {
  final String message;
  final bool success;

  ResponseRegister({
    required this.message,
    required this.success,
  });

  factory ResponseRegister.fromJson(Map<String, dynamic> json) {
    return ResponseRegister(
      message: json['message']?.toString() ?? 'Registrasi berhasil',
      success: json['success'] == true || json['data'] != null,
    );
  }
}

// Service API Register menggunakan DioClient
class RegisterApiService {
  static Future<ResponseRegister> register(
    String nama,
    String email,
    String password,
    String confirmPassword,
  ) async {
    final dio = createDioClient();
    final dioClient = DioClient(dio);

    final response = await dioClient.post(
      '/api/register',
      data: {
        'name': nama,
        'email': email,
        'password': password,
        'password_confirmation': confirmPassword,
      },
    );

    if (response is Map<String, dynamic>) {
      return ResponseRegister.fromJson(response);
    } else {
      return ResponseRegister(
        message: 'Registrasi berhasil',
        success: true,
      );
    }
  }
}