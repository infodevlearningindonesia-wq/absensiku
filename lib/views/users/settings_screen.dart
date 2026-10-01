import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:absensiku/database/db_helper.dart';
import 'package:absensiku/services/api_services.dart';
import 'package:absensiku/services/cache_helper.dart';
import 'package:absensiku/services/network_helper.dart';
import 'package:absensiku/services/notification_helper.dart';
import 'package:absensiku/services/pref_helper.dart';
import 'package:absensiku/views/users/notification_center_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool _autoCloudSync = true;
  bool _autoPhotoSync = true;
  int _syncIntervalSeconds = 30;
  bool _notifReminder = true;
  bool _soundVibration = true;
  bool _isNotificationGranted = false;

  bool _isSyncingNow = false;
  bool _isTestingConnection = false;
  bool _isBackingUp = false;
  String? _lastSyncTime;
  int _totalLocalAbsensi = 0;
  int _pendingSyncCount = 0;
  bool _isLoading = true;

  // Variabel Penyimpanan Internal & Eksternal HP
  String _internalStoragePath = 'Memuat direktori...';
  String _externalStoragePath = 'Memuat direktori...';
  bool _isExternalAvailable = false;
  String _storageTarget = 'internal'; // 'internal' | 'external'
  String _databaseSize = '0 KB';
  String _cacheSizeFormatted = 'Memuat...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNotificationPermissionStatus();
    }
  }

  Future<void> _checkNotificationPermissionStatus() async {
    try {
      final status = await Permission.notification.status;
      if (!mounted) return;
      setState(() {
        _isNotificationGranted = status.isGranted;
      });
    } catch (_) {}
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    await _checkNotificationPermissionStatus();
    final autoSync = await PrefHelper.isAutoCloudSyncEnabled();
    final photoSync = await PrefHelper.isAutoPhotoSyncEnabled();
    final interval = await PrefHelper.getSyncIntervalSeconds();
    final notif = await PrefHelper.isNotificationReminderEnabled();
    final sound = await PrefHelper.isSoundVibrationEnabled();
    final lastSync = await PrefHelper.getLastCloudSyncTime();
    final target = await PrefHelper.getStorageTarget();

    int totalAbsensi = 0;
    int unsyncedCount = 0;
    try {
      final all = await DatabaseHelper.instance.getAllAbsensi();
      totalAbsensi = all.length;
      final unsynced = await DatabaseHelper.instance.getUnsyncedAbsensi();
      unsyncedCount = unsynced.length;
    } catch (_) {}

    // Dapatkan path penyimpanan internal & eksternal ponsel
    String internalPath = 'Internal Storage';
    String externalPath = 'Tidak Terpasang / Akses Dibatasi';
    bool externalAvailable = false;
    String dbSize = '0 KB';
    String cacheSize = '0 KB';

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      internalPath = appDocDir.path;
    } catch (_) {}

    try {
      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          externalPath = extDir.path;
          externalAvailable = true;
        }
      } else {
        final docs = await getApplicationDocumentsDirectory();
        externalPath = docs.path;
        externalAvailable = true;
      }
    } catch (_) {}

    try {
      final dbFolder = await getDatabasesPath();
      final dbFile = File(p.join(dbFolder, 'absensiku.db'));
      if (await dbFile.exists()) {
        final bytes = await dbFile.length();
        if (bytes < 1024) {
          dbSize = '$bytes B';
        } else if (bytes < 1024 * 1024) {
          dbSize = '${(bytes / 1024).toStringAsFixed(1)} KB';
        } else {
          dbSize = '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
        }
      }
    } catch (_) {}

    try {
      cacheSize = await AppCacheHelper.getFormattedCacheSize();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _autoCloudSync = autoSync;
      _autoPhotoSync = photoSync;
      _syncIntervalSeconds = interval;
      _notifReminder = notif;
      _soundVibration = sound;
      _lastSyncTime = lastSync ?? 'Belum pernah sinkron';
      _totalLocalAbsensi = totalAbsensi;
      _pendingSyncCount = unsyncedCount;
      _internalStoragePath = internalPath;
      _externalStoragePath = externalPath;
      _isExternalAvailable = externalAvailable;
      _storageTarget = target;
      _databaseSize = dbSize;
      _cacheSizeFormatted = cacheSize;
      _isLoading = false;
    });
  }

  Future<void> _triggerManualCloudSync() async {
    final isOnline = await NetworkHelper.hasInternetConnection();
    if (!isOnline) {
      if (mounted) {
        NetworkHelper.showOfflineDialog(context, featureName: 'Sinkronisasi Awan Manual');
      }
      return;
    }

    setState(() => _isSyncingNow = true);
    try {
      // Jalankan sinkronisasi dua arah (Unggah data pending + Tarik riwayat awan terbaru)
      final syncResult = await AppApiService.autoSyncAllData();
      final pendingUploaded = syncResult['pendingSynced'] as int? ?? 0;

      final now = DateTime.now();
      final formattedNow =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} WIB';
      await PrefHelper.setLastCloudSyncTime(formattedNow);

      final all = await DatabaseHelper.instance.getAllAbsensi();
      final unsynced = await DatabaseHelper.instance.getUnsyncedAbsensi();

      if (!mounted) return;
      setState(() {
        _lastSyncTime = formattedNow;
        _totalLocalAbsensi = all.length;
        _pendingSyncCount = unsynced.length;
        _isSyncingNow = false;
      });

      AppNotificationHelper.showSyncSuccess(pendingUploaded, total: all.length);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pendingUploaded > 0
                ? '$pendingUploaded data baru berhasil diunggah. Total ${all.length} data tersimpan di Awan.'
                : 'Semua ${all.length} data presensi telah tersimpan aman & tersinkron penuh dengan server Awan.',
          ),
          backgroundColor: Colors.green.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSyncingNow = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal sinkronisasi ke cloud: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _testApiConnection() async {
    setState(() => _isTestingConnection = true);
    try {
      // 1. Cek koneksi internet aktif perangkat (dengan delay sejenak agar animasi loading spinner terlihat jelas)
      final hasInternet = await NetworkHelper.hasInternetConnection();
      await Future.delayed(const Duration(milliseconds: 1200));

      if (!mounted) return;

      if (!hasInternet) {
        setState(() => _isTestingConnection = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.red, size: 26),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Peringatan Jaringan Internet',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: const SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pengujian server memerlukan koneksi internet aktif.',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Perangkat Anda saat ini tidak terhubung ke jaringan Wi-Fi maupun Data Seluler.\n\n'
                    'Silakan aktifkan koneksi internet pada ponsel Anda dan coba lagi.',
                    style: TextStyle(fontSize: 12.5, color: Colors.black87),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _testApiConnection();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                icon: const Icon(Icons.refresh, size: 16, color: Colors.white),
                label: const Text('Coba Lagi', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        return;
      }

      // 2. Jika online, uji coba otentikasi & koneksi ke Server API
      final token = await AppApiService.ensureValidApiToken();
      final hasConnection = token != null && token.isNotEmpty;

      if (!mounted) return;
      setState(() => _isTestingConnection = false);

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                hasConnection ? Icons.cloud_done_rounded : Icons.warning_amber_rounded,
                color: hasConnection ? Colors.green : Colors.orange,
                size: 26,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasConnection ? 'Koneksi Server Online Berhasil' : 'Server Tidak Menanggapi',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              hasConnection
                  ? 'Perangkat Anda berhasil terhubung ke Server API Cloud (https://absensib1.mobileprojp.com).\n\nSesi otentikasi aktif dan data presensi siap disinkronkan secara online.'
                  : 'Terhubung ke internet, namun server API utama sedang tidak menanggapi. Silakan coba beberapa saat lagi.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Tutup', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isTestingConnection = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error pengujian koneksi: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _clearTemporaryCache() async {
    final currentCache = await AppCacheHelper.getFormattedCacheSize();

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_outlined, color: Colors.blueAccent),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pembersih Cache HP & APK',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storage, color: Colors.blueAccent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Perkiraan Ukuran Cache:',
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                          Text(
                            currentCache,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Proses ini akan membersihkan:\n'
                '• Cache memori visual & thumbnail gambar\n'
                '• File sementara (temporary files) di perangkat\n'
                '• Cache berkas singgah APK\n\n'
                'Semua data absensi lokal SQLite & akun cloud Anda tetap aman 100%.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.auto_delete_outlined, size: 18),
            label: const Text('Mulai Bersihkan'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Padding(
          padding: EdgeInsets.symmetric(vertical: 16.0),
          child: Row(
            children: [
              CircularProgressIndicator(color: Colors.blueAccent),
              SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Sedang membersihkan cache perangkat & APK...',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final cleanResult = await AppCacheHelper.cleanAllCache();
    final newCacheSize = await AppCacheHelper.getFormattedCacheSize();

    if (mounted) {
      Navigator.pop(context); // Tutup dialog loading
      setState(() {
        _cacheSizeFormatted = newCacheSize;
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Expanded(child: Text('Pembersihan Selesai')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cleanResult.message,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 12),
              Text(
                'Sisa cache saat ini: $newCacheSize',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    }
  }

  // ==================== RESET DATA MASTER (ABSENSI & CACHE) ====================
  Future<void> _resetMasterData() async {
    final allAbsensi = await DatabaseHelper.instance.getAllAbsensi();
    final count = allAbsensi.length;

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Reset Data Master',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Data Master Presensi:',
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                          Text(
                            '$count Catatan Absensi',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Tindakan reset data master ini akan:\n'
                '• Menghapus seluruh riwayat presensi lokal SQLite secara permanen\n'
                '• Menghapus data riwayat di server cloud (bila terhubung online)\n'
                '• Membersihkan berkas cache sementara, gambar & singgahan APK\n'
                '• Mengosongkan riwayat notifikasi presensi\n\n'
                'Catatan: Akun login & data profil pengguna Anda tetap aman dan aktif.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('Ya, Reset Data Master'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Padding(
          padding: EdgeInsets.symmetric(vertical: 16.0),
          child: Row(
            children: [
              CircularProgressIndicator(color: Colors.redAccent),
              SizedBox(width: 20),
              Expanded(
                child: Text(
                  'Sedang mereset data master & cache...',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      // 1. Hapus riwayat di server API jika ada API ID
      final itemsToDelete = await DatabaseHelper.instance.getAllAbsensi();
      for (final it in itemsToDelete) {
        final apiId = it[DatabaseHelper.columnApiId]?.toString();
        if (apiId != null &&
            apiId.isNotEmpty &&
            apiId != '0' &&
            apiId != 'null') {
          try {
            await AppApiService.deleteAbsensiFromApi(apiId);
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 2. Hapus seluruh data absensi SQLite secara permanen
    await DatabaseHelper.instance.resetMasterAbsensi(cleanBlacklist: false);

    // 3. Catat timestamp reset
    await PrefHelper.setLastClearedTimestamp(DateTime.now().toIso8601String());

    // 4. Bersihkan cache aplikasi & gambar
    await AppCacheHelper.cleanAllCache();

    // 5. Bersihkan riwayat notifikasi
    await AppNotificationHelper.clearNotificationHistory();

    // 6. Muat ulang status pengaturan (recalculate size & count)
    await _loadSettings();

    if (mounted) {
      Navigator.pop(context); // Tutup dialog loading

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Expanded(child: Text('Reset Master Berhasil')),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Data master riwayat presensi, cache lokal, dan notifikasi telah berhasil dibersihkan.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              SizedBox(height: 10),
              Text(
                'Aplikasi kembali dalam kondisi bersih (fresh state). Akun login Anda tetap aman dan aktif.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Selesai'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _openDeviceNotificationSettings() async {
    try {
      final opened = await openAppSettings();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Buka Pengaturan HP > Aplikasi > Absensiku > Izin > Notifikasi.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Buka Pengaturan HP > Aplikasi > Absensiku > Izin > Notifikasi.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final currentStatus = await Permission.notification.status;
      if (!currentStatus.isGranted) {
        final requestStatus = await Permission.notification.request();
        if (!mounted) return;
        setState(() {
          _isNotificationGranted = requestStatus.isGranted;
        });

        if (requestStatus.isGranted) {
          AppNotificationHelper.showNotification(
            title: 'Izin Notifikasi Aktif',
            message: 'Notifikasi perangkat Absensiku berhasil diaktifkan.',
            icon: Icons.notifications_active_rounded,
            backgroundColor: const Color(0xFF1B5E20),
            iconColor: Colors.greenAccent,
          );
          return;
        }
      }
      _showNotificationPermissionInfo();
    } catch (_) {
      _showNotificationPermissionInfo();
    }
  }

  void _testDeviceNotification() {
    AppNotificationHelper.showNotification(
      title: 'Uji Notifikasi Perangkat',
      message: 'Izin notifikasi perangkat Anda telah aktif & bekerja normal.',
      icon: Icons.notifications_active_rounded,
      backgroundColor: const Color(0xFF1E293B),
      iconColor: Colors.blueAccent,
    );
  }

  void _showNotificationPermissionInfo() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                _isNotificationGranted ? Icons.notifications_active : Icons.notification_important,
                color: _isNotificationGranted ? Colors.blueAccent : Colors.orange,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Izin Notifikasi Perangkat',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isNotificationGranted
                      ? 'Status Perizinan di Ponsel: Aktif'
                      : 'Status Perizinan di Ponsel: Belum Aktif',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: _isNotificationGranted ? const Color(0xFF1B5E20) : const Color(0xFFC62828),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isNotificationGranted ? Colors.green.shade50 : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isNotificationGranted ? Colors.green.shade200 : Colors.orange.shade300,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isNotificationGranted ? Icons.check_circle : Icons.warning_amber_rounded,
                            color: _isNotificationGranted ? Colors.green : Colors.orange.shade800,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isNotificationGranted
                                  ? 'Izin Notifikasi (POST_NOTIFICATIONS) Diizinkan'
                                  : 'Izin Notifikasi (POST_NOTIFICATIONS) Belum Diberikan',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _isNotificationGranted ? Colors.green.shade900 : Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Izin Getaran & Bunyi (VIBRATE) Tersedia',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Pemantauan Status Jaringan Otomatis',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (!_isNotificationGranted) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.red, size: 16),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Sistem membatasi notifikasi pop-up. Tekan "Minta Izin" atau "Buka Setelan HP" untuk mengaktifkannya.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFFB71C1C), height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const Text(
                  'Notifikasi perangkat berguna untuk:\n'
                  '• Informasi status koneksi Online / Offline otomatis\n'
                  '• Konfirmasi presensi Absen Masuk & Pulang\n'
                  '• Pengingat jam presensi kerja\n'
                  '• Informasi sinkronisasi basis data Awan',
                  style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                ),
              ],
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openDeviceNotificationSettings();
                    },
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Setelan HP')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (_isNotificationGranted) {
                        Navigator.pop(ctx);
                        _testDeviceNotification();
                      } else {
                        try {
                          final req = await Permission.notification.request();
                          if (mounted) {
                            setState(() {
                              _isNotificationGranted = req.isGranted;
                            });
                          }
                          setDialogState(() {});
                          if (req.isGranted) {
                            if (ctx.mounted) Navigator.pop(ctx);
                            AppNotificationHelper.showNotification(
                              title: 'Izin Notifikasi Aktif',
                              message: 'Notifikasi perangkat Absensiku berhasil diaktifkan.',
                              icon: Icons.notifications_active_rounded,
                              backgroundColor: const Color(0xFF1B5E20),
                              iconColor: Colors.greenAccent,
                            );
                          } else if (req.isPermanentlyDenied) {
                            if (ctx.mounted) Navigator.pop(ctx);
                            _openDeviceNotificationSettings();
                          }
                        } catch (_) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          _openDeviceNotificationSettings();
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isNotificationGranted ? Colors.blueAccent : Colors.green.shade700,
                    ),
                    icon: Icon(
                      _isNotificationGranted ? Icons.send_rounded : Icons.lock_open_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _isNotificationGranted ? 'Kirim Uji' : 'Minta Izin',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Cadangkan Database SQLite ke Penyimpanan Pilihan Ponsel & Sinkron ke Awan jika Online
  Future<void> _backupDatabaseToStorage() async {
    setState(() => _isBackingUp = true);
    try {
      final dbFolder = await getDatabasesPath();
      final dbFile = File(p.join(dbFolder, 'absensiku.db'));

      if (!await dbFile.exists()) {
        if (!mounted) return;
        setState(() => _isBackingUp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File database belum tersedia untuk dicadangkan.')),
        );
        return;
      }

      Directory targetDirectory;
      if (_storageTarget == 'external' && _isExternalAvailable) {
        final extDir = await getExternalStorageDirectory();
        targetDirectory = extDir ?? await getApplicationDocumentsDirectory();
      } else {
        targetDirectory = await getApplicationDocumentsDirectory();
      }

      final now = DateTime.now();
      final timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final backupFileName = 'absensiku_backup_$timestamp.db';
      final backupFilePath = p.join(targetDirectory.path, backupFileName);

      await dbFile.copy(backupFilePath);

      // Sinkronkan juga ke Awan Online jika perangkat terhubung ke internet
      bool isOnlineSynced = false;
      final isOnline = await NetworkHelper.hasInternetConnection();
      if (isOnline) {
        try {
          await AppApiService.syncAllPendingToApi();
          isOnlineSynced = true;
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _isBackingUp = false);

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pencadangan Berhasil',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Salinan database lokal ($_databaseSize) telah tersimpan di ${_storageTarget == "external" ? "Penyimpanan Eksternal (SD Card)" : "Penyimpanan Internal Ponsel"}:',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SelectableText(
                    backupFilePath,
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.black87),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isOnlineSynced ? Colors.blue.shade50 : Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isOnlineSynced ? Colors.blue.shade200 : Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOnlineSynced ? Icons.cloud_done : Icons.cloud_off,
                        color: isOnlineSynced ? Colors.blueAccent : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isOnlineSynced
                              ? 'Data juga berhasil dicadangkan ke Server API Awan secara Online!'
                              : 'Perangkat sedang offline. Data tersimpan aman di penyimpanan ponsel.',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isOnlineSynced ? Colors.blue.shade900 : Colors.brown.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              child: const Text('Selesai', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBackingUp = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mencadangkan database: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.cloud_queue, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pengaturan & Cloud',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Segarkan',
            icon: const Icon(Icons.refresh),
            onPressed: _loadSettings,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              children: [
                // 1. KARTU HEADER CLOUD STORAGE BANNER (SISTEM AWAN)
                _buildCloudStatusBanner(),

                const SizedBox(height: 16),

                // 2. KELOMPOK PENGATURAN PENYIMPANAN AWAN / API
                _buildSectionHeader('Penyimpanan Awan & Sinkronisasi API', Icons.cloud_sync_outlined),
                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _autoCloudSync,
                        activeTrackColor: Colors.blueAccent,
                        title: const Text(
                          'Penyimpanan Awan Otomatis',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          _autoCloudSync
                              ? 'Aktif: Presensi & profil otomatis tersimpan ke server API'
                              : 'Nonaktif: Data hanya disimpan secara offline di SQLite',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        onChanged: (val) async {
                          await PrefHelper.setAutoCloudSync(val);
                          setState(() => _autoCloudSync = val);
                          if (val) {
                            _triggerManualCloudSync();
                          }
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _autoPhotoSync,
                        activeTrackColor: Colors.blueAccent,
                        title: const Text(
                          'Upload Foto Profil ke Awan',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          _autoPhotoSync
                              ? 'Otomatis mengunggah file foto profil baru ke server API'
                              : 'Foto profil hanya disimpan di memori perangkat lokal',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        onChanged: (val) async {
                          await PrefHelper.setAutoPhotoSync(val);
                          setState(() => _autoPhotoSync = val);
                        },
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                        child: Row(
                          children: [
                            const Icon(Icons.timer_outlined, color: Colors.blueAccent, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Interval Sinkronisasi Otomatis',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Setiap $_syncIntervalSeconds detik jika online',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            DropdownButtonHideUnderline(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: DropdownButton<int>(
                                  value: _syncIntervalSeconds,
                                  isDense: true,
                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.blueAccent, size: 18),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueAccent,
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 15, child: Text('15 Detik')),
                                    DropdownMenuItem(value: 30, child: Text('30 Detik')),
                                    DropdownMenuItem(value: 60, child: Text('1 Menit')),
                                    DropdownMenuItem(value: 300, child: Text('5 Menit')),
                                  ],
                                  onChanged: (newVal) async {
                                    if (newVal != null) {
                                      await PrefHelper.setSyncIntervalSeconds(newVal);
                                      setState(() => _syncIntervalSeconds = newVal);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _isSyncingNow ? null : _triggerManualCloudSync,
                            icon: _isSyncingNow
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload_outlined, size: 20),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _isSyncingNow
                                    ? 'Menyinkronkan ke Awan...'
                                    : (_pendingSyncCount > 0
                                        ? 'Sinkronkan ke Cloud Sekarang ($_pendingSyncCount pending)'
                                        : 'Sinkronkan ke Cloud Sekarang'),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // 3. KELOMPOK PENYIMPANAN PONSEL PENGGUNA (INTERNAL & EKSTERNAL)
                _buildSectionHeader('Penyimpanan Ponsel Pengguna', Icons.phone_android_outlined),
                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      // INFO PENYIMPANAN INTERNAL
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.phone_android, color: Colors.blueAccent, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Penyimpanan Internal',
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.blue.shade200),
                                        ),
                                        child: const Text(
                                          'Utama (Aktif)',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: Colors.blueAccent,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _internalStoragePath,
                                    style: TextStyle(fontSize: 11, color: Colors.grey[700], fontFamily: 'monospace'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Database: $_databaseSize • $_totalLocalAbsensi Data Tersimpan',
                                    style: const TextStyle(fontSize: 11.5, color: Colors.teal, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),

                      // INFO PENYIMPANAN EKSTERNAL / SD CARD
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.sd_card_outlined,
                              color: _isExternalAvailable ? Colors.teal : Colors.grey,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Penyimpanan Eksternal / SD Card',
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _isExternalAvailable ? Colors.teal.shade50 : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: _isExternalAvailable ? Colors.teal.shade200 : Colors.grey.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          _isExternalAvailable ? 'Tersedia' : 'Tidak Terdeteksi',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: _isExternalAvailable ? Colors.teal : Colors.grey,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _externalStoragePath,
                                    style: TextStyle(fontSize: 11, color: Colors.grey[700], fontFamily: 'monospace'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _isExternalAvailable
                                        ? 'Siap digunakan untuk pencadangan file & ekspor'
                                        : 'Menggunakan memori internal perangkat sebagai default',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),

                      // PILIHAN LOKASI PENYIMPANAN TARGET
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Lokasi Target Penyimpanan & Cadangan:',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text('Internal HP'),
                                    selected: _storageTarget == 'internal',
                                    onSelected: (selected) async {
                                      if (selected) {
                                        await PrefHelper.setStorageTarget('internal');
                                        setState(() => _storageTarget = 'internal');
                                      }
                                    },
                                    selectedColor: Colors.blue.shade100,
                                    avatar: const Icon(Icons.phone_android, size: 16, color: Colors.blueAccent),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ChoiceChip(
                                    label: const Text('Eksternal / SD'),
                                    selected: _storageTarget == 'external',
                                    onSelected: _isExternalAvailable
                                        ? (selected) async {
                                            if (selected) {
                                              await PrefHelper.setStorageTarget('external');
                                              setState(() => _storageTarget = 'external');
                                            }
                                          }
                                        : null,
                                    selectedColor: Colors.teal.shade100,
                                    avatar: Icon(
                                      Icons.sd_card_outlined,
                                      size: 16,
                                      color: _isExternalAvailable ? Colors.teal : Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),

                      // TOMBOL CADANGKAN DATABASE KE PENYIMPANAN HP
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.teal.shade800,
                              side: BorderSide(color: Colors.teal.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _isBackingUp ? null : _backupDatabaseToStorage,
                            icon: _isBackingUp
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.backup_outlined, size: 18),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _isBackingUp
                                    ? 'Mencadangkan Database...'
                                    : 'Cadangkan Database ke Memori (${_storageTarget == "external" ? "Eksternal" : "Internal"})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),

                      // BERSIHKAN CACHE HP & APK
                      ListTile(
                        leading: const Icon(Icons.cleaning_services_outlined, color: Colors.orange),
                        title: const Text('Pembersih Cache HP & APK'),
                        subtitle: Text(
                          'Bersihkan file temporary, cache gambar & berkas APK ($_cacheSizeFormatted)',
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        onTap: _clearTemporaryCache,
                      ),
                      const Divider(height: 1),

                      // RESET DATA MASTER & RIWAYAT ABSENSI
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20),
                        ),
                        title: const Text(
                          'Reset Data Master & Riwayat',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'Hapus seluruh catatan absensi lokal ($_totalLocalAbsensi data) & cache database',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.redAccent),
                        onTap: _resetMasterData,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // 4. KELOMPOK NOTIFIKASI & PREFERENSI
                _buildSectionHeader('Notifikasi & Preferensi', Icons.notifications_active_outlined),
                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _notifReminder,
                        activeTrackColor: Colors.blueAccent,
                        title: const Text(
                          'Pengingat Jadwal Presensi',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Kirim notifikasi pengingat waktu absen masuk & pulang',
                          style: TextStyle(fontSize: 12),
                        ),
                        onChanged: (val) async {
                          await PrefHelper.setNotificationReminder(val);
                          setState(() => _notifReminder = val);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _soundVibration,
                        activeTrackColor: Colors.blueAccent,
                        title: const Text(
                          'Suara & Getaran Presensi',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Umpan balik haptik saat tombol absen ditekan',
                          style: TextStyle(fontSize: 12),
                        ),
                        onChanged: (val) async {
                          await PrefHelper.setSoundVibration(val);
                          setState(() => _soundVibration = val);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _isNotificationGranted ? Colors.green.shade50 : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _isNotificationGranted ? Icons.verified_user_outlined : Icons.notification_important_outlined,
                            color: _isNotificationGranted ? Colors.green : Colors.orange.shade800,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Izin Notifikasi Perangkat',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          _isNotificationGranted
                              ? 'Status: Aktif & Diizinkan di sistem ponsel'
                              : 'Status: Belum Aktif. Ketuk untuk mengaktifkan.',
                          style: TextStyle(
                            fontSize: 12,
                            color: _isNotificationGranted ? Colors.grey.shade700 : Colors.deepOrange,
                            fontWeight: _isNotificationGranted ? FontWeight.normal : FontWeight.w500,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _isNotificationGranted ? Colors.green.shade100 : Colors.red.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _isNotificationGranted ? 'Aktif' : 'Belum Aktif',
                                style: TextStyle(
                                  color: _isNotificationGranted ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                          ],
                        ),
                        onTap: _requestNotificationPermission,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.inbox_rounded,
                            color: Colors.blueAccent,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Pusat & Riwayat Notifikasi',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Buka kotak masuk notifikasi dan riwayat lengkap (seperti YouTube)',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ValueListenableBuilder<int>(
                              valueListenable: AppNotificationHelper.unreadCountNotifier,
                              builder: (context, count, _) {
                                if (count <= 0) return const SizedBox.shrink();
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$count baru',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                          ],
                        ),
                        onTap: () {
                          NotificationCenterScreen.show(context);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // 5. KELOMPOK INFORMASI SERVER & APLIKASI
                _buildSectionHeader('Koneksi Server & Sistem', Icons.dns_outlined),
                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        child: Row(
                          children: [
                            const Icon(Icons.link, color: Colors.blueAccent, size: 22),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'API Server Endpoint',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'https://absensib1.mobileprojp.com',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 32,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: _isTestingConnection ? null : _testApiConnection,
                                child: _isTestingConnection
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Uji', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            'assets/images/logo.png',
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: const Text('Absensiku'),
                        subtitle: const Text('Versi 1.0.0 • by Muhammad Faiz Aldo Firmansyah'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 10.0, top: 8.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF475569),
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudStatusBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _autoCloudSync
              ? [const Color(0xFF0F172A), const Color(0xFF1E3A8A), const Color(0xFF2563EB)]
              : [const Color(0xFF334155), const Color(0xFF475569)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _autoCloudSync ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _autoCloudSync ? 'Penyimpanan Awan: Otomatis' : 'Penyimpanan Awan: Manual',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _autoCloudSync
                          ? 'Semua data otomatis tersimpan ke API'
                          : 'Data tersimpan lokal, perlu sync manual',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
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
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, color: Colors.white70, size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Terakhir: $_lastSyncTime',
                    style: const TextStyle(color: Colors.white, fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_pendingSyncCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_pendingSyncCount Pending',
                      style: const TextStyle(
                        color: Color(0xFF78350F),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
