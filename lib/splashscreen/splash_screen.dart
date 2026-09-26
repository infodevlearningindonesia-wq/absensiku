import 'dart:async';
import 'package:flutter/material.dart';
import 'package:absensiku/services/api_services.dart';
import 'package:absensiku/services/pref_helper.dart';
import 'package:absensiku/views/auth/login_screen.dart';
import 'package:absensiku/views/users/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        _checkSessionAndNavigate();
      }
    });
  }

  Future<void> _checkSessionAndNavigate() async {

    if (!mounted) return;

    try {
      final isLoggedIn = await PrefHelper.isLoggedIn();

      if (isLoggedIn) {
        // Otomatis sinkronisasi data presensi dan profil di background
        AppApiService.autoSyncAllData();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } catch (_) {
      // Fallback jika terjadi kegagalan pembacaan preferensi
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Logo Aplikasi
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.25),
                      blurRadius: 18,
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
              const SizedBox(height: 20),
              // Nama Aplikasi
              const Text(
                'Absensiku',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Colors.blueAccent,
                ),
              ),
              const SizedBox(height: 6),
              // Slogan / Subtitle
              Text(
                'Sistem Presensi Karyawan & Siswa',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),
              // Indikator Loading
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.blueAccent,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Menyiapkan aplikasi...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
              const Spacer(),
              // Versi Aplikasi di Bagian Bawah
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: Text(
                  'Versi 1.0.0',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[400],
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}