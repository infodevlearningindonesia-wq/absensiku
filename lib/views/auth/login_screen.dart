import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:absensiku/database/db_helper.dart';
import 'package:absensiku/services/pref_helper.dart';
import 'package:absensiku/models/login_models.dart';
import 'package:absensiku/services/api_services.dart';
import 'package:absensiku/services/dio_system.dart';
import 'package:absensiku/services/network_helper.dart';
import 'package:absensiku/views/auth/register_screen.dart';
import 'package:absensiku/views/auth/reset_password.dart';
import 'package:absensiku/views/users/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // Validasi input form
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // 1. Periksa koneksi internet (Wajib online)
    final hasInternet = await NetworkHelper.hasInternetConnection();
    if (!hasInternet) {
      if (mounted) setState(() => _isLoading = false);
      if (!mounted) return;
      NetworkHelper.showOfflineDialog(context, featureName: 'Fitur Login');
      return;
    }

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    try {
      // 2. Panggil API Login ke Server Backend
      final dio = createDioClient();
      final apiService = ApiService(dio);

      final response = await apiService.login(
        LoginModel(
          email: email,
          password: password,
        ),
      );

      final token = response.data?.token;
      final user = response.data?.user;
      final userName = user?.name ?? 'Pengguna';

      if (token != null) {
        await PrefHelper.saveSession(
          token: token,
          userId: user?.id,
          name: userName,
          email: user?.email ?? email,
        );

        // Sinkronkan ke tabel users SQLite lokal
        final isRegisteredLocally = await DatabaseHelper.instance.isEmailRegistered(email);
        if (!isRegisteredLocally) {
          await DatabaseHelper.instance.registerUser(
            nama: userName,
            email: email,
            password: password,
          );
        }

        // Otomatis sinkronisasi semua data API (riwayat absensi dan profil)
        AppApiService.autoSyncAllData();
      }

      if (!mounted) return;

      // Notifikasi sukses via SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  response.message ?? 'Login berhasil! Selamat datang $userName.',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Navigasi ke Halaman Utama
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    } on DioException catch (e) {
      String errorMessage = 'Email atau password salah.';

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

      // Notifikasi Dialog Error Login
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
                  'Login Gagal',
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
                    child: const Text('Coba Lagi'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
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
        title: const Text('Login'),
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
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
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
                    'Masuk ke Absensiku',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Silakan masukkan email dan password Anda',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 32),
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
                      if (value.length < 6) {
                        return 'Password minimal 6 karakter';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  // Tombol Masuk
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
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
                              'Masuk',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Belum punya akun?'),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegisterScreen(),
                            ),
                          );
                        },
                        child: const Text('Daftar Sekarang'),
                      ),
                      const SizedBox(width: 24),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ResetPasswordScreen(),
                            ),
                          );
                        },
                        child: const Text('Lupa Password?'),
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
