import 'package:flutter/material.dart';
import 'package:absensiku/services/api_services.dart';
import 'package:absensiku/services/network_helper.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isObscure = true;
  bool _isObscure2 = true;
  bool _isLoading = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _resetPassword() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() {
        _isLoading = true;
      });

      // Periksa koneksi internet (Wajib online)
      final hasInternet = await NetworkHelper.hasInternetConnection();
      if (!hasInternet) {
        if (mounted) setState(() => _isLoading = false);
        if (!mounted) return;
        NetworkHelper.showOfflineDialog(context, featureName: 'Fitur Reset Password');
        return;
      }

      try {
        await AppApiService.resetPassword(
          _emailController.text.trim(),
          _passwordController.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password berhasil direset! Silakan login dengan password baru.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
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
  }

  String? _emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Masukkan email Anda';
    }
    if (!value.contains('@') || !value.contains('.')) {
      return 'Masukkan format email yang valid';
    }
    return null;
  }

  String? _passwordValidator(String? value) {
    if (value == null || value.isEmpty) {
      return 'Masukkan password baru Anda';
    }
    if (value.length < 6) {
      return 'Password minimal 6 karakter';
    }
    return null;
  }

  String? _confirmPasswordValidator(String? value) {
    if (value == null || value.isEmpty) {
      return 'Masukkan konfirmasi password Anda';
    }
    if (value != _passwordController.text) {
      return 'Konfirmasi password tidak cocok';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // 1. Hero Gradient Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 230,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF1E3A8A),
                    Color(0xFF2563EB),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                            onPressed: () => Navigator.pop(context),
                            tooltip: 'Kembali',
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Atur Ulang Kata Sandi',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 12, top: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pemulihan Keamanan Akun 🔑',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Masukkan email terdaftar dan tentukan kata sandi baru',
                              style: TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 12.5,
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
          ),

          // 2. White Card Form Sheet
          Positioned.fill(
            top: 165,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Form Email
                      TextFormField(
                        controller: _emailController,
                        validator: _emailValidator,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email Terdaftar',
                          hintText: 'nama@domain.com',
                          prefixIcon: Icon(Icons.mail_outline_rounded, color: Color(0xFF2563EB)),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Form Password Baru
                      TextFormField(
                        controller: _passwordController,
                        validator: _passwordValidator,
                        obscureText: _isObscure,
                        decoration: InputDecoration(
                          labelText: 'Kata Sandi Baru',
                          hintText: 'Minimal 6 karakter',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF2563EB)),
                          filled: true,
                          fillColor: Colors.white,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: const Color(0xFF64748B),
                            ),
                            onPressed: () {
                              setState(() {
                                _isObscure = !_isObscure;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Form Konfirmasi Password Baru
                      TextFormField(
                        controller: _confirmPasswordController,
                        validator: _confirmPasswordValidator,
                        obscureText: _isObscure2,
                        decoration: InputDecoration(
                          labelText: 'Konfirmasi Kata Sandi Baru',
                          hintText: 'Ulangi kata sandi baru',
                          prefixIcon: const Icon(Icons.lock_reset_rounded, color: Color(0xFF2563EB)),
                          filled: true,
                          fillColor: Colors.white,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isObscure2 ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: const Color(0xFF64748B),
                            ),
                            onPressed: () {
                              setState(() {
                                _isObscure2 = !_isObscure2;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Tombol Reset Password dengan Modern Gradient
                      Container(
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _isLoading ? null : _resetPassword,
                            child: Center(
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Simpan Kata Sandi Baru',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      Center(
                        child: TextButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded, size: 16, color: Color(0xFF64748B)),
                          label: const Text(
                            'Kembali ke Halaman Login',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}