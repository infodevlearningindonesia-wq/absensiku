import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:absensiku/models/notification_item.dart';
import 'package:absensiku/services/api_services.dart';
import 'package:absensiku/views/users/notification_center_screen.dart';

class AppNotificationHelper {
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _isPluginInitialized = false;

  static bool? _lastOnlineStatus;
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static bool _isListening = false;

  // Notifier untuk reaktif Badge notifikasi (seperti YouTube / bell badge)
  static final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);
  static const String _keyNotificationHistory = 'app_notification_history_list';

  /// Inisialisasi Native Notification Plugin untuk Status Bar Android / iOS (Samping Baterai)
  static Future<void> initialize() async {
    if (_isPluginInitialized) {
      await refreshUnreadCount();
      return;
    }

    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Handle klik notifikasi sistem -> Buka Pusat Notifikasi Aplikasi
          final nav = navigatorKey.currentState;
          if (nav != null) {
            nav.push(
              MaterialPageRoute(
                builder: (context) => const NotificationCenterScreen(),
              ),
            );
          }
        },
      );

      // Buat Android Notification Channel dengan Prioritas Tertinggi (Heads-Up & Status Bar)
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        const androidChannel = AndroidNotificationChannel(
          'absensiku_main_channel',
          'Notifikasi Absensiku',
          description: 'Notifikasi status koneksi, presensi, dan sinkronisasi data',
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
        );

        await androidImplementation.createNotificationChannel(androidChannel);
      }

      _isPluginInitialized = true;
      await refreshUnreadCount();
    } catch (_) {}
  }

  /// Memulai pemantauan koneksi internet otomatis (Hardware Wi-Fi & Data Seluler)
  static void startNetworkMonitoring() {
    if (_isListening) return;
    _isListening = true;

    // Menjalankan pemantauan secara aman tanpa menghasilkan uncaught microtask exception
    _initNetworkListener();
  }

  static Future<void> _initNetworkListener() async {
    try {
      await initialize();
    } catch (_) {}

    try {
      final results = await Connectivity().checkConnectivity();
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      _lastOnlineStatus = isOnline;
    } catch (_) {}

    try {
      _connectivitySubscription?.cancel();
      _connectivitySubscription =
          Connectivity().onConnectivityChanged.listen(
        (results) {
          try {
            final isOnline = results.any((r) => r != ConnectivityResult.none);

            if (_lastOnlineStatus == null) {
              _lastOnlineStatus = isOnline;
              return;
            }

            // Hanya beri notifikasi jika terjadi perubahan status nyata dari HP
            if (isOnline && _lastOnlineStatus == false) {
              _lastOnlineStatus = true;
              showOnlineNotification();
              // Otomatis sinkronkan semua data offline SharedPreferences & SQLite ke API
              try {
                AppApiService.autoSyncAllData();
              } catch (_) {}
            } else if (!isOnline && _lastOnlineStatus == true) {
              _lastOnlineStatus = false;
              showOfflineNotification();
            }
          } catch (_) {}
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {}
  }

  /// Hentikan pemantauan
  static void stopNetworkMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _isListening = false;
  }

  /// Notifikasi saat terhubung kembali ke internet
  static void showOnlineNotification() {
    showNotification(
      title: 'Terhubung ke Internet',
      message: 'Koneksi online aktif. Semua fitur Absensiku siap digunakan.',
      icon: Icons.wifi_rounded,
      backgroundColor: const Color(0xFF1B5E20), // Hijau tua elegan
      iconColor: Colors.greenAccent,
      duration: const Duration(seconds: 4),
      category: 'network_online',
    );
  }

  /// Notifikasi saat terputus dari internet
  static void showOfflineNotification() {
    showNotification(
      title: 'Koneksi Terputus (Offline)',
      message: 'Perangkat offline. Fitur online dinonaktifkan sementara.',
      icon: Icons.wifi_off_rounded,
      backgroundColor: const Color(0xFFB71C1C), // Merah tua elegan
      iconColor: Colors.amberAccent,
      duration: const Duration(seconds: 4),
      category: 'network_offline',
    );
  }

  /// Menampilkan 1 Notifikasi Terpadu (Notifikasi Resmi Perangkat & Riwayat Notifikasi Aplikasi)
  static void showNotification({
    required String title,
    required String message,
    required IconData icon,
    Color backgroundColor = const Color(0xFF1E293B),
    Color iconColor = Colors.white,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onTap,
    String category = 'system',
    bool saveToHistory = true,
  }) {
    // 1. Simpan ke Riwayat Notifikasi Aplikasi (seperti riwayat YouTube)
    if (saveToHistory) {
      addNotificationHistory(
        NotificationItem(
          id: '${DateTime.now().millisecondsSinceEpoch}_${(title.hashCode).abs() % 10000}',
          title: title,
          message: message,
          timestamp: DateTime.now(),
          category: category,
          iconCodePoint: icon.codePoint,
          colorValue: backgroundColor.toARGB32(),
          isRead: false,
        ),
      );
    }

    // 2. Tampilkan 1 Notifikasi Resmi Perangkat di Status Bar HP Android / iOS
    _showNativeSystemNotification(title, message);
  }

  /// ID Notifikasi Tunggal Tetap (Menjamin HANYA 1 notifikasi di status bar / notification tray)
  static const int singleNotificationId = 1001;

  /// Kirim notifikasi native sistem operasi Android / iOS (Selalu 1 notifikasi tunggal ter-update)
  static Future<void> _showNativeSystemNotification(
      String title, String message) async {
    try {
      if (!_isPluginInitialized) {
        await initialize();
      }

      const androidDetails = AndroidNotificationDetails(
        'absensiku_main_channel',
        'Notifikasi Absensiku',
        channelDescription: 'Notifikasi tunggal sistem, status jaringan, dan pembaruan',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
        showWhen: true,
        onlyAlertOnce: false,
        tag: 'absensiku_single_notification',
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      // Selalu gunakan 1 ID tetap agar notifikasi baru me-replace notifikasi lama (1 notif saja)
      await _localNotifications.show(
        singleNotificationId,
        title,
        message,
        notificationDetails,
      );
    } catch (_) {}
  }

  /// Hapus/Tutup notifikasi aktif dari status bar HP
  static Future<void> cancelNativeNotification() async {
    try {
      await _localNotifications.cancel(singleNotificationId);
    } catch (_) {}
  }

  static bool hasShownWelcomeSession = false;

  /// Notifikasi Saat Masuk Aplikasi (Ucapan Welcome, Versi & Informasi Aplikasi)
  static void showWelcomeAppNotification({
    String? userName,
    String version = '1.0.0',
    String? customMessage,
    bool force = false,
  }) {
    if (!force && hasShownWelcomeSession) return;
    hasShownWelcomeSession = true;

    final nameGreeting = (userName != null && userName.isNotEmpty && userName != 'Pengguna')
        ? 'Selamat Datang, $userName!'
        : 'Selamat Datang di Absensiku!';

    final infoMessage = customMessage ??
        'Versi Aplikasi: v$version • Aplikasi Presensi & Manajemen Kehadiran Online & Offline siap digunakan.';

    showNotification(
      title: '$nameGreeting (v$version)',
      message: infoMessage,
      icon: Icons.verified_user_rounded,
      backgroundColor: const Color(0xFF1E3A8A), // Biru tua elegan
      iconColor: Colors.lightBlueAccent,
      category: 'login',
    );
  }

  /// Notifikasi Saat Masuk (Login / Masuk Akun)
  static void showLoginSuccess(String userName, {String version = '1.0.0'}) {
    showWelcomeAppNotification(
      userName: userName,
      version: version,
      force: true,
    );
  }

  /// Notifikasi Informasi Sistem
  static void showSystemInfo({
    required String title,
    required String message,
    IconData icon = Icons.info_outline_rounded,
    Color backgroundColor = const Color(0xFF1E293B),
    Color iconColor = Colors.white,
  }) {
    showNotification(
      title: title,
      message: message,
      icon: icon,
      backgroundColor: backgroundColor,
      iconColor: iconColor,
      category: 'system',
    );
  }

  /// Notifikasi Informasi dan Permintaan Update Aplikasi
  static void showAppUpdateAvailable({
    String version = '1.0.1',
    String message = 'Pembaruan aplikasi versi terbaru telah tersedia. Segera perbarui aplikasi Anda.',
  }) {
    showNotification(
      title: 'Pembaruan Aplikasi ($version)',
      message: message,
      icon: Icons.system_update_rounded,
      backgroundColor: const Color(0xFF6B21A8), // Ungu elegan
      iconColor: Colors.purpleAccent,
      category: 'update',
    );
  }

  /// Notifikasi Informasi Update / Pengumuman Sistem
  static void showUpdateInfo({
    required String title,
    required String message,
  }) {
    showNotification(
      title: title,
      message: message,
      icon: Icons.update_rounded,
      backgroundColor: const Color(0xFF4C1D95),
      iconColor: Colors.amberAccent,
      category: 'update',
    );
  }

  /// Notifikasi Sinkronisasi Awan Berhasil (Informasi Sistem)
  static void showSyncSuccess(int count, {int total = 0}) {
    final msg = count > 0
        ? '$count data presensi baru berhasil diunggah ke server API.'
        : (total > 0
            ? 'Seluruh $total data presensi telah tersimpan & sinkron di Awan.'
            : 'Semua data presensi telah tersimpan aman di server Awan.');
    showNotification(
      title: 'Sinkronisasi Awan Selesai',
      message: msg,
      icon: Icons.cloud_done_rounded,
      backgroundColor: const Color(0xFF0D47A1),
      iconColor: Colors.lightBlueAccent,
      category: 'sync',
    );
  }

  // ==========================================
  // RIWAYAT NOTIFIKASI (SEPERTI YOUTUBE / NOTIFICATION CENTER)
  // ==========================================

  /// Ambil semua riwayat notifikasi dari penyimpanan lokal (terbaru di atas)
  static Future<List<NotificationItem>> getNotificationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listJson = prefs.getStringList(_keyNotificationHistory);

      if (listJson == null || listJson.isEmpty) {
        // Jika belum ada riwayat sama sekali, inisialisasi dengan notifikasi selamat datang
        final initialItems = [
          NotificationItem(
            id: 'init_welcome',
            title: 'Selamat Datang di Absensiku!',
            message: 'Aplikasi siap digunakan. Anda dapat melakukan presensi online maupun offline.',
            timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
            category: 'system',
            isRead: false,
            iconCodePoint: Icons.check_circle_outline_rounded.codePoint,
            colorValue: const Color(0xFF3B82F6).toARGB32(),
          ),
          NotificationItem(
            id: 'init_sync',
            title: 'Penyimpanan Awan Aktif',
            message: 'Data kehadiran Anda disinkronkan secara aman dengan basis data dan cloud.',
            timestamp: DateTime.now().subtract(const Duration(hours: 1)),
            category: 'sync',
            isRead: true,
            iconCodePoint: Icons.cloud_done_rounded.codePoint,
            colorValue: const Color(0xFF0D47A1).toARGB32(),
          ),
        ];
        await saveNotificationHistoryList(initialItems);
        return initialItems;
      }

      final items = listJson
          .map((itemStr) => NotificationItem.fromJson(jsonDecode(itemStr) as Map<String, dynamic>))
          .toList();

      // Urutkan dari yang paling baru
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Simpan seluruh list notifikasi ke SharedPreferences
  static Future<void> saveNotificationHistoryList(List<NotificationItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listJson = items.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_keyNotificationHistory, listJson);
      await refreshUnreadCount();
    } catch (_) {}
  }

  /// Tambahkan satu notifikasi baru ke riwayat
  static Future<void> addNotificationHistory(NotificationItem item) async {
    try {
      final list = await getNotificationHistory();
      // Maksimal simpan 100 riwayat notifikasi terbaru
      final updatedList = [item, ...list.where((i) => i.id != item.id)];
      if (updatedList.length > 100) {
        updatedList.removeRange(100, updatedList.length);
      }
      await saveNotificationHistoryList(updatedList);
    } catch (_) {}
  }

  /// Tandai satu notifikasi sebagai sudah dibaca
  static Future<void> markAsRead(String id) async {
    try {
      final list = await getNotificationHistory();
      final updatedList = list.map((item) {
        if (item.id == id) {
          return item.copyWith(isRead: true);
        }
        return item;
      }).toList();
      await saveNotificationHistoryList(updatedList);
    } catch (_) {}
  }

  /// Tandai SEMUA notifikasi sebagai sudah dibaca
  static Future<void> markAllAsRead() async {
    try {
      final list = await getNotificationHistory();
      final updatedList = list.map((item) => item.copyWith(isRead: true)).toList();
      await saveNotificationHistoryList(updatedList);
      await cancelNativeNotification();
    } catch (_) {}
  }

  /// Hapus satu notifikasi dari riwayat
  static Future<void> deleteNotification(String id) async {
    try {
      final list = await getNotificationHistory();
      final updatedList = list.where((item) => item.id != id).toList();
      await saveNotificationHistoryList(updatedList);
    } catch (_) {}
  }

  /// Bersihkan seluruh riwayat notifikasi
  static Future<void> clearNotificationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyNotificationHistory);
      unreadCountNotifier.value = 0;
      await cancelNativeNotification();
    } catch (_) {}
  }

  /// Perbarui nilai unreadCountNotifier dari storage
  static Future<void> refreshUnreadCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listJson = prefs.getStringList(_keyNotificationHistory);
      if (listJson == null || listJson.isEmpty) {
        unreadCountNotifier.value = 0;
        return;
      }
      final items = listJson
          .map((itemStr) => NotificationItem.fromJson(jsonDecode(itemStr) as Map<String, dynamic>))
          .toList();
      final unread = items.where((e) => !e.isRead).length;
      unreadCountNotifier.value = unread;
    } catch (_) {
      unreadCountNotifier.value = 0;
    }
  }
}
