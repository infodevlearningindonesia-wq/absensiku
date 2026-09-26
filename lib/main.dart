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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
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
