import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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
  static OverlayEntry? _currentOverlayEntry;

  /// Inisialisasi Native Notification Plugin untuk Status Bar Android / iOS (Samping Baterai)
  static Future<void> initialize() async {
    if (_isPluginInitialized) return;

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
          // Handle klik notifikasi sistem
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
    } catch (_) {}
  }

  /// Memulai pemantauan koneksi internet otomatis (Hardware Wi-Fi & Data Seluler)
  static void startNetworkMonitoring() {
    if (_isListening) return;
    _isListening = true;

    // Pastikan plugin native terinisialisasi
    initialize();

    // Cek awal status hardware koneksi
    Connectivity().checkConnectivity().then((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      _lastOnlineStatus = isOnline;
    }).catchError((_) {});

    // Dengarkan perubahan konektivitas perangkat (Wi-Fi atau Data Seluler dimatikan/dihidupkan)
    _connectivitySubscription?.cancel();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);

      if (_lastOnlineStatus == null) {
        _lastOnlineStatus = isOnline;
        return;
      }

      // Hanya beri notifikasi jika terjadi perubahan status nyata dari HP
      if (isOnline && _lastOnlineStatus == false) {
        _lastOnlineStatus = true;
        showOnlineNotification();
      } else if (!isOnline && _lastOnlineStatus == true) {
        _lastOnlineStatus = false;
        showOfflineNotification();
      }
    });
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
    );
  }

  /// Menampilkan Notifikasi Perangkat di Status Bar (Samping Baterai) & Melayang di Atas Aplikasi
  static void showNotification({
    required String title,
    required String message,
    required IconData icon,
    Color backgroundColor = const Color(0xFF1E293B),
    Color iconColor = Colors.white,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onTap,
  }) {
    // 1. TAMPILKAN DI STATUS BAR PERANGKAT HP (Samping Baterai / Status Bar Android)
    _showNativeSystemNotification(title, message);

    // 2. TAMPILKAN IN-APP BANNER MELAYANG DI BAGIAN ATAS LAYAR
    _showInAppTopOverlay(
      title: title,
      message: message,
      icon: icon,
      backgroundColor: backgroundColor,
      iconColor: iconColor,
      duration: duration,
      onTap: onTap,
    );
  }

  /// Kirim notifikasi native sistem operasi Android / iOS
  static Future<void> _showNativeSystemNotification(
      String title, String message) async {
    try {
      if (!_isPluginInitialized) {
        await initialize();
      }

      const androidDetails = AndroidNotificationDetails(
        'absensiku_main_channel',
        'Notifikasi Absensiku',
        channelDescription: 'Notifikasi status koneksi, presensi, dan sinkronisasi data',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: true,
        playSound: true,
        showWhen: true,
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

      final notifId = DateTime.now().millisecondsSinceEpoch % 100000;
      await _localNotifications.show(
        notifId,
        title,
        message,
        notificationDetails,
      );
    } catch (_) {}
  }

  /// Tampilkan Banner Melayang di Atas Aplikasi
  static void _showInAppTopOverlay({
    required String title,
    required String message,
    required IconData icon,
    required Color backgroundColor,
    required Color iconColor,
    required Duration duration,
    VoidCallback? onTap,
  }) {
    final overlayState = navigatorKey.currentState?.overlay;
    if (overlayState != null) {
      try {
        _currentOverlayEntry?.remove();
      } catch (_) {}
      _currentOverlayEntry = null;

      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (context) => _TopNotificationOverlayWidget(
          title: title,
          message: message,
          icon: icon,
          backgroundColor: backgroundColor,
          iconColor: iconColor,
          duration: duration,
          onTap: onTap,
          onDismiss: () {
            if (_currentOverlayEntry == entry) {
              try {
                entry.remove();
              } catch (_) {}
              _currentOverlayEntry = null;
            }
          },
        ),
      );

      _currentOverlayEntry = entry;
      overlayState.insert(entry);
      return;
    }

    final state = messengerKey.currentState;
    if (state == null) return;

    state.removeCurrentSnackBar();
    state.showSnackBar(
      SnackBar(
        duration: duration,
        elevation: 6,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        backgroundColor: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Notifikasi Presensi Berhasil
  static void showPresensiSuccess(String tipe, String waktu) {
    final isMasuk = tipe.toLowerCase() == 'masuk';
    showNotification(
      title: 'Presensi $tipe Berhasil',
      message: 'Catatan $tipe pukul $waktu WIB tersimpan & tersinkron.',
      icon: isMasuk ? Icons.login_rounded : Icons.logout_rounded,
      backgroundColor: isMasuk ? const Color(0xFF1B5E20) : const Color(0xFFE65100),
      iconColor: Colors.white,
    );
  }

  /// Notifikasi Sinkronisasi Awan Berhasil
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
    );
  }
}

/// Widget Notifikasi Melayang di Bagian Atas Layar (Heads-up Notification Banner)
class _TopNotificationOverlayWidget extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final Duration duration;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  const _TopNotificationOverlayWidget({
    required this.title,
    required this.message,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    required this.duration,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_TopNotificationOverlayWidget> createState() =>
      _TopNotificationOverlayWidgetState();
}

class _TopNotificationOverlayWidgetState
    extends State<_TopNotificationOverlayWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      reverseDuration: const Duration(milliseconds: 250),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();

    _dismissTimer = Timer(widget.duration, () {
      _dismiss();
    });
  }

  void _dismiss() {
    if (!mounted) return;
    _dismissTimer?.cancel();
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: SlideTransition(
          position: _offsetAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                if (details.primaryDelta != null && details.primaryDelta! < -4) {
                  _dismiss();
                }
              },
              onTap: () {
                if (widget.onTap != null) {
                  widget.onTap!();
                }
                _dismiss();
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.backgroundColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: 2,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(widget.icon, color: widget.iconColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Text(
                                  'Sekarang',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.message,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 12,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _dismiss,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white70, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
