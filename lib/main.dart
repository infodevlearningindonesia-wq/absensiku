
import 'package:flutter/material.dart';
import 'package:absensiku/services/notification_helper.dart';
import 'package:absensiku/splashscreen/splash_screen.dart';
import 'package:absensiku/views/auth/login_screen.dart';
import 'package:absensiku/views/auth/register_screen.dart';
import 'package:absensiku/views/users/daftar_hadir_screen.dart';
import 'package:absensiku/views/users/home_screen.dart';
import 'package:absensiku/views/users/maps_screen.dart';
import 'package:absensiku/views/users/profile_screen.dart';
import 'package:absensiku/views/users/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inisialisasi plugin notifikasi status bar native & pemantau konektivitas
  await AppNotificationHelper.initialize();
  AppNotificationHelper.startNetworkMonitoring();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  final bool? isLoggedIn;
  const MyApp({super.key, this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    Widget initialHome;
    if (isLoggedIn == true) {
      initialHome = const HomeScreen();
    } else if (isLoggedIn == false) {
      initialHome = const LoginScreen();
    } else {
      initialHome = const SplashScreen();
    }

    return MaterialApp(
      title: 'Absensiku',
      scaffoldMessengerKey: AppNotificationHelper.messengerKey,
      navigatorKey: AppNotificationHelper.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          primary: const Color(0xFF2563EB),
          surface: const Color(0xFFF8FAFC),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 1.5,
          centerTitle: true,
          iconTheme: IconThemeData(color: Color(0xFF0F172A)),
          titleTextStyle: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.06),
          indicatorColor: const Color(0xFFEFF6FF),
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2563EB),
                letterSpacing: 0.2,
              );
            }
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFF2563EB), size: 23);
            }
            return const IconThemeData(color: Color(0xFF64748B), size: 23);
          }),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titleTextStyle: const TextStyle(
            fontSize: 17.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            letterSpacing: -0.2,
          ),
          contentTextStyle: const TextStyle(
            fontSize: 13.5,
            color: Color(0xFF475569),
            height: 1.45,
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFF1F5F9),
          selectedColor: const Color(0xFFEFF6FF),
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFF1F5F9),
          thickness: 1,
          space: 20,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF0F172A),
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 4,
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF2563EB),
            textStyle: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.8),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFEF4444)),
          ),
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
          labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
          prefixIconColor: const Color(0xFF64748B),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF2563EB),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      // Inisialisasi awal aplikasi: default membuka SplashScreen, atau rute langsung untuk testing
      home: initialHome,
      // Seluruh rute terdaftar untuk navigasi antar halaman
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const HomeScreen(),
        '/daftar_hadir': (context) => const DaftarHadirScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/maps': (context) => const GoogleMapsScreenDay19(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
