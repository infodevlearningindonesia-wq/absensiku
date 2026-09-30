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

  @override
  void initState() {
    super.initState();

    // 1. Controller Animasi (Durasi 1000ms agar animasi muncul lebih cepat dan responsif)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Animasi Scale Logo (Zoom in cepat dan halus)
    _logoScaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    // Animasi Fade In Logo
    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    // Animasi Denyut / Glow Halo di Belakang Logo
    _pulseAnimation = Tween<double>(begin: 12.0, end: 28.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeInOut),
      ),
    );

    // Animasi Slide & Fade Judul "Absensiku"
    _titleSlideAnimation = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOutCubic),
      ),
    );
    _titleFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.5, curve: Curves.easeIn),
      ),
    );

    // Animasi Fade Subjudul
    _subtitleFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.7, curve: Curves.easeIn),
      ),
    );

    // Animasi Fade Indikator Loading
    _loadingFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.45, 0.75, curve: Curves.easeIn),
      ),
    );

    // Jalankan animasi
    _controller.forward();

    // 2. Timer Durasi Splash & Loading Tepat 3 Detik
    _startNavigationTimer();
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startNavigationTimer() {
    _navigationTimer?.cancel();
    // Menahan tampilan splash & loading selama 5 detik agar informasi dan kredit pengembang terbaca jelas
    _navigationTimer = Timer(const Duration(seconds: 5), () {
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
        _navigateWithFastTransition(const HomeScreen());
      } else {
        if (!mounted) return;
        _navigateWithFastTransition(const LoginScreen());
      }
    } catch (_) {
      if (!mounted) return;
      _navigateWithFastTransition(const LoginScreen());
    }
  }

  // Navigasi dengan transisi Fade yang cepat & responsif (450ms)
  void _navigateWithFastTransition(Widget targetScreen) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
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
      backgroundColor: Colors.white,
      body: SafeArea(
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
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
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
                                    width: 104,
                                    height: 104,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(26),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.blueAccent.withValues(alpha: 0.28),
                                          blurRadius: _pulseAnimation.value,
                                          spreadRadius: 2,
                                          offset: const Offset(0, 8),
                                        ),
                                        BoxShadow(
                                          color: Colors.blue.withValues(alpha: 0.12),
                                          blurRadius: _pulseAnimation.value * 1.5,
                                          spreadRadius: 4,
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
                              ),

                              const SizedBox(height: 24),

                              // 2. NAMA APLIKASI DENGAN SLOW MOTION SLIDE & FADE
                              Transform.translate(
                                offset: Offset(0, _titleSlideAnimation.value),
                                child: Opacity(
                                  opacity: _titleFadeAnimation.value,
                                  child: const Text(
                                    'Absensiku',
                                    style: TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                      color: Colors.blueAccent,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 8),

                              // 3. SUBTITEL / SLOGAN DENGAN SLOW MOTION FADE
                              Opacity(
                                opacity: _subtitleFadeAnimation.value,
                                child: Text(
                                  'Sistem Presensi Karyawan & Siswa',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[600],
                                    letterSpacing: 0.3,
                                  ),
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
                                        color: Colors.blueAccent,
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
                                  padding: const EdgeInsets.only(bottom: 24.0, top: 16.0),
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
                                          color: Colors.blueAccent.shade200,
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
    );
  }
}