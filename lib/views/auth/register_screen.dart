import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:absensiku/database/db_helper.dart';
import 'package:absensiku/models/register_models.dart';
import 'package:absensiku/services/api_services.dart';
import 'package:absensiku/services/dio_system.dart';
import 'package:absensiku/services/network_helper.dart';
import 'package:absensiku/views/auth/login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Tampilkan dialog konfirmasi sebelum melakukan registrasi
  Future<void> _confirmAndRegister() async {
    // Validasi form dan cek konfirmasi password
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.blueAccent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Konfirmasi Pendaftaran',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            'Pastikan data Anda sudah benar:\n\n'
            '• Nama: ${_nameController.text.trim()}\n'
            '• Email: ${_emailController.text.trim()}\n\n'
            'Apakah Anda yakin ingin mendaftar?',
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Batal')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Ya, Daftarkan')),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _executeRegister();
    }
  }

  Future<void> _executeRegister() async {
    setState(() {
      _isLoading = true;
    });

    // 1. Periksa koneksi internet (Wajib online)
    final hasInternet = await NetworkHelper.hasInternetConnection();
    if (!hasInternet) {
      if (mounted) setState(() => _isLoading = false);
      if (!mounted) return;
      NetworkHelper.showOfflineDialog(context, featureName: 'Fitur Registrasi Akun');
      return;
    }

    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    try {
      // 1. PANGGIL API REGISTRASI KE SERVER BACKEND
      final dio = createDioClient();
      final apiService = ApiService(dio);

      final response = await apiService.register(
        RegisterModel(
          name: name,
          email: email,
          password: password,
          passwordConfirmation: confirmPassword,
        ),
      );

      // 2. SIMPAN KE TABEL USERS SQLITE (LOKAL)
      final isLocalRegistered = await DatabaseHelper.instance.isEmailRegistered(email);
      if (!isLocalRegistered) {
        await DatabaseHelper.instance.registerUser(
          nama: name,
          email: email,
          password: password,
        );
      }

      if (!mounted) return;

      // 3. DIALOG SUKSES DENGAN OPSI TAMBAH AKUN LAGI ATAU LOGIN
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Colors.green,
                  size: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Registrasi Berhasil!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  response.message ?? 'Akun baru ($email) berhasil didaftarkan dan tersimpan.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          // Reset formulir untuk menambah akun baru lainnya
                          _nameController.clear();
                          _emailController.clear();
                          _passwordController.clear();
                          _confirmPasswordController.clear();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Silakan masukkan data untuk menambah akun baru lainnya.'),
                              backgroundColor: Colors.blueAccent,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Tambah Akun Lain'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                          );
                        },
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Masuk Sekarang'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } on DioException catch (e) {
      String errorMessage = 'Terjadi kesalahan pada server API.';
      if (e.response != null && e.response?.data is Map) {
        final data = e.response?.data as Map;
        if (data['message'] != null) {
          errorMessage = data['message'];
        }
        if (data['errors'] != null && data['errors'] is Map) {
          final errors = data['errors'] as Map;
          final errorList = <String>[];
          errors.forEach((key, val) {
            if (val is List) {
              errorList.add(val.join('\n'));
            } else {
              errorList.add(val.toString());
            }
          });
          if (errorList.isNotEmpty) {
            errorMessage = errorList.join('\n');
          }
        }
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Koneksi timeout. Silakan periksa jaringan internet Anda.';
      } else if (e.error != null) {
        errorMessage = e.error.toString();
      }

      if (!mounted) return;

      // Cek apakah error karena email sudah terdaftar di server
      final isEmailTaken = errorMessage.toLowerCase().contains('email sudah terdaftar') ||
          errorMessage.toLowerCase().contains('email has already been taken');

      if (isEmailTaken) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blueAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Email Sudah Terdaftar',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Text(
                'Email ($email) sudah terdaftar.\n\n'
                'Silakan langsung login menggunakan email ini atau gunakan email baru.',
              ),
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _emailController.clear();
                      },
                      child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Ganti Email Baru')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                        );
                      },
                      child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Langsung Login')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
        return;
      }

      // Notifikasi dialog error API
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Registrasi API Gagal',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(errorMessage),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tutup'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Registrasi Gagal',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text('Terjadi error: ${e.toString()}'),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tutup'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Akun'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.25),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Buat Akun Baru',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Isi data di bawah untuk mendaftar akun Absensiku',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 32),
                  // Input Nama
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Lengkap',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Nama lengkap wajib diisi';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Input Email
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
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
                  // Input Password
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: 'Min. 8 karakter: kombinasi huruf besar, kecil & angka/simbol (cth: Rahasia123)',
                      helperMaxLines: 2,
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password wajib diisi';
                      }
                      if (value.length < 8) {
                        return 'Password minimal 8 karakter (sesuai aturan server)';
                      }
                      final hasUppercase = value.contains(RegExp(r'[A-Z]'));
                      final hasLowercase = value.contains(RegExp(r'[a-z]'));
                      final hasNumberOrSymbol = value.contains(RegExp(r'[0-9!@#\$%^&*(),.?":{}|<>]'));

                      if (!hasUppercase || !hasLowercase || !hasNumberOrSymbol) {
                        return 'Harus ada huruf besar, kecil & angka/simbol (cth: Rahasia123)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Input Cek Konfirmasi Password
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Konfirmasi Password',
                      prefixIcon: const Icon(Icons.lock_reset_outlined),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Konfirmasi password wajib diisi';
                      }
                      if (value != _passwordController.text) {
                        return 'Konfirmasi password tidak cocok dengan password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  // Tombol Daftar
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _confirmAndRegister,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Daftar Sekarang',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Sudah punya akun?'),
                      TextButton(
                        onPressed: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                          );
                        },
                        child: const Text('Masuk di sini'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
