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

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoFadeAnimation;
  late Animation<double> _titleSlideAnimation;
  late Animation<double> _titleFadeAnimation;
  late Animation<double> _subtitleFadeAnimation;
  late Animation<double> _loadingFadeAnimation;
  late Animation<double> _pulseAnimation;

  Timer? _navigationTimer;
  Timer? _watchdogTimer;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    // 1. Controller Animasi (Durasi 2200ms agar semua elemen muncul bersamaan secara halus)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    // Kurva Sinkronisasi: Semua Elemen (Logo, Judul, Subtitle, Loading & Footer) MUNCUL BERSAMAAN
    final unifiedCurve = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
    );

    // Animasi Scale Logo (Zoom in lembut & bersamaan)
    _logoScaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(unifiedCurve);

    // Animasi Fade In Bersamaan
    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(unifiedCurve);
    _titleFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(unifiedCurve);
    _subtitleFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(unifiedCurve);
    _loadingFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(unifiedCurve);

    // Animasi Slide Halus Judul "Absensiku" Bersamaan
    _titleSlideAnimation = Tween<double>(begin: 14.0, end: 0.0).animate(unifiedCurve);

    // Animasi Denyut / Glow Halo di Belakang Logo
    _pulseAnimation = Tween<double>(begin: 14.0, end: 28.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 1.0, curve: Curves.easeInOut),
      ),
    );

    // Jalankan animasi
    _controller.forward();

    // 2. Timer Durasi Splash & Loading Anti-Stuck (2 Detik)
    _startNavigationTimer();
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _watchdogTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startNavigationTimer() {
    _navigationTimer?.cancel();
    _watchdogTimer?.cancel();

    // Timer utama: 2.2 detik sinkron dengan animasi muncul bersamaan
    _navigationTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted && !_hasNavigated) {
        _checkSessionAndNavigate();
      }
    });

    // Watchdog timer cadangan: memastikan navigasi pasti berjalan maksimal dalam 3.5 detik
    _watchdogTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted && !_hasNavigated) {
        _checkSessionAndNavigate();
      }
    });
  }

  Future<void> _checkSessionAndNavigate() async {
    if (_hasNavigated) return;

    try {
      // Timeout 1.5 detik agar pengecekan status login tidak pernah hang/stuck
      final isLoggedIn = await PrefHelper.isLoggedIn().timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () => false,
      );

      if (_hasNavigated) return;

      if (isLoggedIn) {
        // Otomatis sinkronisasi data presensi dan profil di background secara non-blocking
        try {
          AppApiService.autoSyncAllData();
        } catch (_) {}

        final isAdmin = await PrefHelper.isAdmin();

       
      } else {
        if (!mounted || _hasNavigated) return;
        _navigateWithFastTransition(const LoginScreen());
      }
    } catch (_) {
      if (!mounted || _hasNavigated) return;
      _navigateWithFastTransition(const LoginScreen());
    }
  }

  // Navigasi dengan transisi Fade yang cepat & responsif (350ms)
  void _navigateWithFastTransition(Widget targetScreen) {
    if (_hasNavigated) return;
    _hasNavigated = true;
    _navigationTimer?.cancel();
    _watchdogTimer?.cancel();

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF3F8FE), // Nuansa biru es sangat lembut di atas
              Color(0xFFFFFFFF), // Putih bersih di tengah
              Color(0xFFEBF3FD), // Nuansa pastel sky blue di bawah
            ],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Ornamen ambient glow melingkar di sudut kanan atas
            Positioned(
              top: -60,
              right: -50,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.blueAccent.withValues(alpha: 0.12),
                      Colors.blueAccent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Ornamen ambient glow di sudut kiri bawah
            Positioned(
              bottom: -70,
              left: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.lightBlueAccent.withValues(alpha: 0.14),
                      Colors.lightBlueAccent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Konten utama SplashScreen
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                // Tap to Skip: ketuk layar untuk langsung lanjut tanpa menunggu timer
                if (!_hasNavigated) {
                  _checkSessionAndNavigate();
                }
              },
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: AnimatedBuilder(
                            animation: _controller,
                            builder: (context, child) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24.0,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Spacer(flex: 2),

                                      // 1. LOGO DENGAN SLOW MOTION SCALE, FADE & PULSE GLOW
                                      Transform.scale(
                                        scale: _logoScaleAnimation.value,
                                        child: Opacity(
                                          opacity: _logoFadeAnimation.value,
                                          child: Container(
                                            width: 120,
                                            height: 120,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(28),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFF1E88E5)
                                                      .withValues(alpha: 0.22),
                                                  blurRadius:
                                                      _pulseAnimation.value,
                                                  spreadRadius: 2,
                                                  offset: const Offset(0, 8),
                                                ),
                                                BoxShadow(
                                                  color: const Color(0xFF1565C0)
                                                      .withValues(alpha: 0.10),
                                                  blurRadius:
                                                      _pulseAnimation.value *
                                                      1.5,
                                                  spreadRadius: 4,
                                                  offset: const Offset(0, 16),
                                                ),
                                              ],
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 2.5,
                                              ),
                                            ),
                                            padding: const EdgeInsets.all(10),
                                            clipBehavior: Clip.antiAlias,
                                            child: Image.asset(
                                              'assets/images/absensiku.png',
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(height: 24),

                                      // 2. NAMA APLIKASI DENGAN TEKS GRADASI & SLIDE FADE
                                      Transform.translate(
                                        offset: Offset(
                                          0,
                                          _titleSlideAnimation.value,
                                        ),
                                        child: Opacity(
                                          opacity: _titleFadeAnimation.value,
                                          child: ShaderMask(
                                            shaderCallback: (bounds) =>
                                                const LinearGradient(
                                                  colors: [
                                                    Color(0xFF1565C0),
                                                    Color(0xFF1E88E5),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ).createShader(bounds),
                                            child: const Text(
                                              'Absensiku',
                                              style: TextStyle(
                                                fontSize: 34,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.8,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(height: 8),

                                      // 3. SUBTITEL / SLOGAN DENGAN SLOW MOTION FADE
                                      Opacity(
                                        opacity: _subtitleFadeAnimation.value,
                                        child: Column(
                                          children: [
                                            const Text(
                                              'Hadir untuk memulai',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF1E88E5),
                                                letterSpacing: 0.4,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Sistem Presensi Karyawan',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.grey.shade600,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(height: 36),

                                      // 4. INDIKATOR LOADING SLOW MOTION
                                      Opacity(
                                        opacity: _loadingFadeAnimation.value,
                                        child: Column(
                                          children: [
                                            const SizedBox(
                                              width: 26,
                                              height: 26,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.8,
                                                color: Color(0xFF1E88E5),
                                              ),
                                            ),
                                            const SizedBox(height: 14),
                                            Text(
                                              'Menyiapkan aplikasi...',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.grey[500],
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      const Spacer(flex: 3),

                                      // 5. FOOTER VERSI DAN INFORMASI PENGEMBANG (UI BY)
                                      Opacity(
                                        opacity: _loadingFadeAnimation.value,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 24.0,
                                            top: 16.0,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Versi 1.0.0 • Absensiku',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.grey[500],
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Developed by Muhammad Faiz Aldo Firmansyah | Method By Ashabibie | UI By Hardi | Logo By Canva Design | Maps By Google Maps | Source API By OpenWeatherMap | PPKD Jakarta Utara',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors
                                                      .blueAccent
                                                      .shade200,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
