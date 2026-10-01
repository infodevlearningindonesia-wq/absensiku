import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
// COMENT YANG LAUNCHER
// import 'package:url_launcher/url_launcher.dart';
import 'package:absensiku/database/db_helper.dart';
import 'package:absensiku/services/api_services.dart';
import 'package:absensiku/services/network_helper.dart';
import 'package:absensiku/services/notification_helper.dart';
import 'package:absensiku/services/pref_helper.dart';
import 'package:absensiku/views/auth/login_screen.dart';
import 'package:absensiku/views/users/daftar_hadir_screen.dart';
import 'package:absensiku/views/users/form_izin_screen.dart';
import 'package:absensiku/views/users/maps_screen.dart';
import 'package:absensiku/views/users/notification_center_screen.dart';
import 'package:absensiku/views/users/profile_screen.dart';
import 'package:absensiku/views/users/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTabIndex = 0;
  String _userName = '';
  String _userEmail = '';
  String? _userPhotoPath;
  int? _userId;
  Timer? _autoSyncTimer;

  List<Map<String, dynamic>> _riwayatAbsensi = [];
  bool _isLoadingDb = true;
  String _selectedHistoryFilter = 'Semua';

  List<Map<String, dynamic>> get _filteredRiwayatAbsensi {
    if (_selectedHistoryFilter == 'Semua') {
      return _riwayatAbsensi;
    } else if (_selectedHistoryFilter == 'Absensi') {
      return _riwayatAbsensi.where((item) {
        final t = item[DatabaseHelper.columnTipe] as String? ?? '';
        final k = item[DatabaseHelper.columnKeterangan] as String? ?? '';
        return _isMasukTipe(t, k) || _isPulangTipe(t, k);
      }).toList();
    } else if (_selectedHistoryFilter == 'Izin' || _selectedHistoryFilter == 'Semua Izin') {
      return _riwayatAbsensi.where((item) {
        final t = item[DatabaseHelper.columnTipe] as String? ?? '';
        final k = item[DatabaseHelper.columnKeterangan] as String? ?? '';
        return _isIzinTipe(t, k);
      }).toList();
    } else if (_selectedHistoryFilter == 'Sakit') {
      return _riwayatAbsensi.where((item) {
        final t = item[DatabaseHelper.columnTipe] as String? ?? '';
        final k = item[DatabaseHelper.columnKeterangan] as String? ?? '';
        return _isSakitTipe(t, k);
      }).toList();
    } else if (_selectedHistoryFilter == 'Cuti') {
      return _riwayatAbsensi.where((item) {
        final t = item[DatabaseHelper.columnTipe] as String? ?? '';
        final k = item[DatabaseHelper.columnKeterangan] as String? ?? '';
        return _isCutiTipe(t, k);
      }).toList();
    } else if (_selectedHistoryFilter == 'Dinas') {
      return _riwayatAbsensi.where((item) {
        final t = item[DatabaseHelper.columnTipe] as String? ?? '';
        final k = item[DatabaseHelper.columnKeterangan] as String? ?? '';
        return _isDinasTipe(t, k);
      }).toList();
    } else if (_selectedHistoryFilter == 'Izin Biasa') {
      return _riwayatAbsensi.where((item) {
        final t = item[DatabaseHelper.columnTipe] as String? ?? '';
        final k = item[DatabaseHelper.columnKeterangan] as String? ?? '';
        return _isIzinBiasaTipe(t, k);
      }).toList();
    } else if (_selectedHistoryFilter == 'Masuk') {
      return _riwayatAbsensi.where((item) {
        final t = item[DatabaseHelper.columnTipe] as String? ?? '';
        final k = item[DatabaseHelper.columnKeterangan] as String? ?? '';
        return _isMasukTipe(t, k);
      }).toList();
    } else if (_selectedHistoryFilter == 'Pulang') {
      return _riwayatAbsensi.where((item) {
        final t = item[DatabaseHelper.columnTipe] as String? ?? '';
        final k = item[DatabaseHelper.columnKeterangan] as String? ?? '';
        return _isPulangTipe(t, k);
      }).toList();
    }
    return _riwayatAbsensi;
  }

  // Status absensi hari ini (membedakan SUDAH vs BELUM)
  Map<String, dynamic>? _absenMasukHariIni;
  Map<String, dynamic>? _absenPulangHariIni;

  // State Lokasi & Peta di bagian bawah Home (Google Maps Asli)
  GoogleMapController? _homeMapController;
  Set<Marker> _homeMarkers = {};
  Position? _homeCurrentPosition;
  String _homeCurrentAddress = "Mencari lokasi GPS...";
  bool _isLoadingLocation = false;
  final LatLng _defaultLocation = const LatLng(-6.2000, 106.816666);
  Geocoding? _geocodingInstance;
  Geocoding? get _geocoding {
    try {
      return _geocodingInstance ??= Geocoding();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _homeMapController?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _startPeriodicAutoSync();
  }

  Future<void> _startPeriodicAutoSync() async {
    _autoSyncTimer?.cancel();
    final isAutoSync = await PrefHelper.isAutoCloudSyncEnabled();
    if (!isAutoSync) return;

    final interval = await PrefHelper.getSyncIntervalSeconds();
    _autoSyncTimer = Timer.periodic(Duration(seconds: interval), (_) async {
      if (mounted) {
        await _autoSyncAll();
      }
    });
  }

  Future<void> _loadInitialData() async {
    await _loadUserData();
    await _loadAbsensiFromDb();
    _getHomeLocation();
    _autoSyncAll();
  }

  bool _isIzinTipe(String tipe, [String keterangan = '']) {
    final t = tipe.toLowerCase();
    final k = keterangan.toLowerCase();
    return t.contains('izin') ||
        t.contains('ijin') ||
        t.contains('sakit') ||
        t.contains('cuti') ||
        t.contains('dinas') ||
        t.contains('dispensasi') ||
        k.contains('[izin]') ||
        k.contains('[sakit]') ||
        k.contains('[cuti]') ||
        k.contains('[dinas');
  }

  bool _isSakitTipe(String tipe, [String keterangan = '']) {
    final t = tipe.toLowerCase();
    final k = keterangan.toLowerCase();
    return t.contains('sakit') || k.contains('[sakit]');
  }

  bool _isCutiTipe(String tipe, [String keterangan = '']) {
    final t = tipe.toLowerCase();
    final k = keterangan.toLowerCase();
    return t.contains('cuti') || k.contains('[cuti]');
  }

  bool _isDinasTipe(String tipe, [String keterangan = '']) {
    final t = tipe.toLowerCase();
    final k = keterangan.toLowerCase();
    return t.contains('dinas') || k.contains('[dinas');
  }

  bool _isIzinBiasaTipe(String tipe, [String keterangan = '']) {
    if (!_isIzinTipe(tipe, keterangan)) return false;
    return !_isSakitTipe(tipe, keterangan) &&
        !_isCutiTipe(tipe, keterangan) &&
        !_isDinasTipe(tipe, keterangan);
  }

  bool _isMasukTipe(String tipe, [String keterangan = '']) {
    if (_isIzinTipe(tipe, keterangan)) return false;
    final t = tipe.toLowerCase();
    return t == 'masuk' || t.contains('in');
  }

  bool _isPulangTipe(String tipe, [String keterangan = '']) {
    if (_isIzinTipe(tipe, keterangan)) return false;
    final t = tipe.toLowerCase();
    return t == 'pulang' || t == 'keluar' || t.contains('out');
  }

  // 1. Membaca data pengguna dari SharedPreferences (PrefHelper)
  Future<void> _loadUserData() async {
    final name = await PrefHelper.getUserName();
    final email = await PrefHelper.getUserEmail();
    final id = await PrefHelper.getUserId();
    final photo = await PrefHelper.getUserPhoto();

    if (!mounted) return;
    setState(() {
      _userName = name;
      _userEmail = email ?? '';
      _userId = id;
      _userPhotoPath = photo;
    });

    // Tampilkan 1 notifikasi resmi saat masuk aplikasi (Welcome, Versi & Info App)
    AppNotificationHelper.showWelcomeAppNotification(userName: name);
  }

  // 2. Ambil tanggal hari ini dalam format YYYY-MM-DD
  String _getTodayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // Format tanggal bahasa Indonesia (contoh: Jumat, 25 September 2026)
  String _getFormattedToday() {
    final now = DateTime.now();
    const namaHari = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];
    const namaBulan = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    final hari = namaHari[now.weekday % 7];
    final bulan = namaBulan[now.month - 1];
    return '$hari, ${now.day} $bulan ${now.year}';
  }

  // 3. Membaca riwayat absensi dari SQLite sekaligus cek status hari ini
  Future<void> _loadAbsensiFromDb() async {
    setState(() {
      _isLoadingDb = true;
    });

    final data = await DatabaseHelper.instance.getAllAbsensi(
      userId: _userId,
      userName: _userName,
    );
    final today = _getTodayString();

    final masuk = await DatabaseHelper.instance.getAbsensiHariIni(
      tanggal: today,
      tipe: 'Masuk',
      userId: _userId,
      userName: _userName,
    );

    final pulang = await DatabaseHelper.instance.getAbsensiHariIni(
      tanggal: today,
      tipe: 'Keluar',
      userId: _userId,
      userName: _userName,
    );

    if (!mounted) return;
    setState(() {
      _riwayatAbsensi = data;
      _absenMasukHariIni = masuk;
      _absenPulangHariIni = pulang;
      _isLoadingDb = false;
    });
  }

  // 3a. Otomatis sinkronisasi SEMUA data antara API dan SQLite secara background
  Future<void> _autoSyncAll() async {
    final isAutoSync = await PrefHelper.isAutoCloudSyncEnabled();
    if (!isAutoSync) return;

    try {
      final result = await AppApiService.autoSyncAllData();
      final pendingCount = result['pendingSynced'] as int? ?? 0;
      final apiCount = result['apiItemsSynced'] as int? ?? 0;
      final profileUpdated = result['profileSynced'] as bool? ?? false;

      if ((pendingCount > 0 || apiCount > 0 || profileUpdated) && mounted) {
        await _loadUserData();
        await _loadAbsensiFromDb();
      }
    } catch (_) {}
  }

  bool _isManualSyncing = false;

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 4 && hour < 11) {
      return 'Selamat Pagi ☀️';
    } else if (hour >= 11 && hour < 15) {
      return 'Selamat Siang 🌤️';
    } else if (hour >= 15 && hour < 18) {
      return 'Selamat Sore ⛅';
    } else {
      return 'Selamat Malam 🌙';
    }
  }

  Future<void> _triggerManualSync() async {
    if (_isManualSyncing) return;
    setState(() => _isManualSyncing = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Menyinkronkan data Cloud API & SharedPreferences...')),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final result = await AppApiService.autoSyncAllData();
      final pendingCount = result['pendingSynced'] as int? ?? 0;
      final apiCount = result['apiItemsSynced'] as int? ?? 0;
      final total = pendingCount + apiCount;

      await _loadUserData();
      await _loadAbsensiFromDb();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.cloud_done, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    total > 0
                        ? 'Sinkronisasi berhasil! $total catatan diselaraskan ke Cloud API.'
                        : 'Semua data telah sinkron sempurna dengan Cloud API & lokal.',
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline: Data tersimpan aman di SharedPreferences & lokal.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isManualSyncing = false);
      }
    }
  }

  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 3b. Mengambil posisi GPS dan alamat terkini untuk widget Maps di bagian bawah Home (Hanya saat Online)
  Future<void> _getHomeLocation({bool showDialogIfOffline = false}) async {
    final isOnline = await NetworkHelper.hasInternetConnection();
    if (!mounted) return;
    if (!isOnline) {
      setState(() {
        _homeCurrentAddress = "GPS Offline: Pembaruan lokasi dan geocoding alamat jalan memerlukan koneksi internet aktif.";
        _isLoadingLocation = false;
      });
      if (showDialogIfOffline) {
        NetworkHelper.showOfflineDialog(context, featureName: 'Pembaruan Lokasi GPS & Peta');
      }
      return;
    }

    if (_isLoadingLocation) return;
    if (mounted) {
      setState(() {
        _isLoadingLocation = true;
      });
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _homeCurrentAddress = "Layanan GPS perangkat dinonaktifkan.";
            _isLoadingLocation = false;
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _homeCurrentAddress = "Izin lokasi ditolak oleh pengguna.";
              _isLoadingLocation = false;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _homeCurrentAddress = "Izin lokasi ditolak permanen di pengaturan.";
            _isLoadingLocation = false;
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );

      final currentLatLng = LatLng(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() {
        _homeCurrentPosition = position;
        _homeMarkers = {
          Marker(
            markerId: const MarkerId('homeCurrentLocation'),
            position: currentLatLng,
            infoWindow: const InfoWindow(title: 'Lokasi Anda Saat Ini'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        };
      });

      try {
        _homeMapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: currentLatLng, zoom: 16.0),
          ),
        );
      } catch (_) {}

      // Reverse geocoding alamat jalan
      try {
        final placemarks = await _geocoding?.placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks != null && placemarks.isNotEmpty && mounted) {
          final place = placemarks.first;
          final formatted = [
            place.street,
            place.subLocality,
            place.locality,
            place.subAdministrativeArea,
            place.administrativeArea,
          ].where((part) => part != null && part.isNotEmpty).join(', ');

          setState(() {
            _homeCurrentAddress = formatted.isNotEmpty ? formatted : "Lokasi berhasil dideteksi";
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _homeCurrentAddress =
                "Lat: ${position.latitude.toStringAsFixed(5)}, Lng: ${position.longitude.toStringAsFixed(5)}";
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _homeCurrentAddress = "Tidak dapat mengambil lokasi GPS saat ini.";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  /*
  // COMENT YANG LAUNCHER
  // 3c. Buka lokasi saat ini di aplikasi Google Maps eksternal
  Future<void> _openInExternalMaps() async {
    final lat = _homeCurrentPosition?.latitude ?? _defaultLocation.latitude;
    final lng = _homeCurrentPosition?.longitude ?? _defaultLocation.longitude;
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('Tidak dapat membuka Google Maps');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka peta: $e')),
      );
    }
  }
  */

  // 4. Logika Absen Masuk dengan validasi BELUM / SUDAH
  Future<void> _handleAbsenMasuk() async {
    final isOnline = await NetworkHelper.hasInternetConnection();
    if (!mounted) return;
    if (!isOnline) {
      NetworkHelper.showOfflineDialog(context, featureName: 'Presensi Absen Masuk');
      return;
    }

    final today = _getTodayString();
    _absenMasukHariIni = await DatabaseHelper.instance.getAbsensiHariIni(
      tanggal: today,
      tipe: 'Masuk',
      userId: _userId,
    );

    final waktuMasuk = _absenMasukHariIni?['waktu']?.toString() ?? '';
    final isSudahMasuk = _absenMasukHariIni != null &&
        waktuMasuk.isNotEmpty &&
        waktuMasuk != '00:00:00' &&
        waktuMasuk != '-' &&
        waktuMasuk != '--:--' &&
        waktuMasuk != '--:--:--';

    // CEK: Jika SUDAH absen masuk hari ini
    if (isSudahMasuk) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actionsOverflowDirection: VerticalDirection.down,
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blueAccent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Informasi',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              'Anda SUDAH melakukan Absen Masuk hari ini pada pukul $waktuMasuk WIB.\n\nTidak dapat melakukan absen masuk dua kali.',
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Mengerti'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      return;
    }

    // Jika BELUM, minta konfirmasi sebelum mencatat
    final now = DateTime.now();
    final waktu = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.login, color: Colors.green),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Konfirmasi Absen Masuk',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text('Catat kehadiran Masuk sekarang pada pukul $waktu WIB?'),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Batal')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Ya, Absen Masuk', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _simpanAbsensi(tipe: 'Masuk', waktu: waktu);
    }
  }

  // 5. Logika Absen Keluar dengan validasi BELUM / SUDAH (Async ke API & SQLite)
  Future<void> _handleAbsenPulang() async {
    final isOnline = await NetworkHelper.hasInternetConnection();
    if (!mounted) return;
    if (!isOnline) {
      NetworkHelper.showOfflineDialog(context, featureName: 'Presensi Absen Keluar');
      return;
    }

    // Ambil waktu saat ini
    final now = DateTime.now();
    final waktu =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final today = _getTodayString();

    // Periksa status absensi keluar lokal spesifik user hari ini
    _absenPulangHariIni = await DatabaseHelper.instance.getAbsensiHariIni(
      tanggal: today,
      tipe: 'Keluar',
      userId: _userId,
    );

    if (!mounted) return;

    final waktuKeluar = _absenPulangHariIni?['waktu']?.toString() ?? '';
    final isSudahKeluar = _absenPulangHariIni != null &&
        waktuKeluar.isNotEmpty &&
        waktuKeluar != '00:00:00' &&
        waktuKeluar != '-' &&
        waktuKeluar != '--:--' &&
        waktuKeluar != '--:--:--';

    // CEK: Jika SUDAH absen keluar hari ini
    if (isSudahKeluar) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actionsOverflowDirection: VerticalDirection.down,
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blueAccent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Informasi',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              'Anda SUDAH melakukan Absen Keluar hari ini pada pukul $waktuKeluar WIB.\n\nKehadiran hari ini telah lengkap.',
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Mengerti'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      return;
    }

    // Jika BELUM, minta konfirmasi sebelum mencatat (Sama persis seperti Absen Masuk)
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Konfirmasi Absen Keluar',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text('Catat kehadiran Keluar sekarang pada pukul $waktu WIB?'),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Batal')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Ya, Absen Keluar', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _simpanAbsensi(tipe: 'Keluar', waktu: waktu);
    }
  }

  // 6. Menyimpan ke database SQLite & Sinkron ke API
  Future<void> _simpanAbsensi({required String tipe, required String waktu}) async {
    final tanggal = _getTodayString();
    final lat = _homeCurrentPosition?.latitude ?? -6.200000;
    final lon = _homeCurrentPosition?.longitude ?? 106.816666;
    final ket = (_homeCurrentAddress.isNotEmpty &&
            !_homeCurrentAddress.startsWith('Mencari') &&
            !_homeCurrentAddress.startsWith('Gagal') &&
            !_homeCurrentAddress.startsWith('Layanan') &&
            !_homeCurrentAddress.startsWith('Izin'))
        ? 'Absen $tipe di $_homeCurrentAddress'
        : 'Absen $tipe via Absensiku Mobile';

    // 1. Coba hubungkan dan kirim ke API Server Backend jika mode Penyimpanan Awan Otomatis aktif
    final isAutoCloud = await PrefHelper.isAutoCloudSyncEnabled();
    bool apiSuccess = false;
    String? apiId;
    if (isAutoCloud) {
      try {
        final res = await AppApiService.submitAbsensiToApi(
          tipe: tipe,
          tanggal: tanggal,
          waktu: waktu,
          latitude: lat,
          longitude: lon,
          keterangan: ket,
        );
        apiSuccess = res.success;
        apiId = res.apiId;
      } catch (_) {
        apiSuccess = false;
      }
    }

    // JIKA GA ONLINE, SIMPAN KE SHARED PREFERENCES (Offline Fallback)
    if (!apiSuccess) {
      await PrefHelper.saveOfflineAbsensi({
        DatabaseHelper.columnApiId: null,
        DatabaseHelper.columnUserId: _userId,
        DatabaseHelper.columnNama: _userName,
        DatabaseHelper.columnTanggal: tanggal,
        DatabaseHelper.columnWaktu: waktu,
        DatabaseHelper.columnTipe: tipe,
        DatabaseHelper.columnKeterangan: ket,
        DatabaseHelper.columnLatitude: lat,
        DatabaseHelper.columnLongitude: lon,
      });
    }

    // 2. Simpan ke database lokal SQLite (menyimpan api_id jika berhasil tersambung)
    final id = await DatabaseHelper.instance.insertAbsensi({
      DatabaseHelper.columnApiId: apiId,
      DatabaseHelper.columnUserId: _userId,
      DatabaseHelper.columnNama: _userName,
      DatabaseHelper.columnTanggal: tanggal,
      DatabaseHelper.columnWaktu: waktu,
      DatabaseHelper.columnTipe: tipe,
      DatabaseHelper.columnKeterangan: ket,
      DatabaseHelper.columnLatitude: lat,
      DatabaseHelper.columnLongitude: lon,
      DatabaseHelper.columnStatusSync: apiSuccess ? 1 : 0,
    });

    if (!mounted) return;

    // 3. Segera perbarui state lokal agar status tombol Absen Masuk / Keluar langsung ter-update
    await _loadAbsensiFromDb();

    // 4. Jalankan sinkronisasi background dua arah
    _autoSyncAll();

    // 5. Alert dialog konfirmasi sukses presensi
    if (id > 0 && mounted) {
      final isMasuk = tipe.toLowerCase() == 'masuk';
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: isMasuk ? Colors.green : Colors.blue),
              const SizedBox(width: 8),
              Expanded(child: Text('Presensi $tipe Berhasil')),
            ],
          ),
          content: Text(
            'Data presensi $tipe berhasil disimpan.\n\n'
            '• Waktu: $waktu WIB\n'
            '• Tanggal: $tanggal\n'
            '• Status: ${apiSuccess ? "Tersimpan di Server API (Online)" : "Disimpan di SharedPreferences (Offline)"}\n\n'
            '${apiSuccess ? "Data tersinkronisasi otomatis ke server API." : "Data otomatis dikirim ke server API begitu terhubung ke internet."}',
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK / Tutup'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
  }

  // 7. Hapus 1 riwayat secara PERMANEN dari SQLite & API (dengan Alert Dialog Detail)
  Future<void> _hapusAbsensi(int id, {Map<String, dynamic>? item}) async {
    final isOnline = await NetworkHelper.hasInternetConnection();
    if (!mounted) return;
    if (!isOnline) {
      NetworkHelper.showOfflineDialog(context, featureName: 'Hapus Riwayat Presensi');
      return;
    }

    final targetItem = item ??
        _riwayatAbsensi.firstWhere(
          (e) => e[DatabaseHelper.columnId] == id,
          orElse: () => <String, dynamic>{},
        );

    final tipe = targetItem[DatabaseHelper.columnTipe]?.toString() ?? 'Presensi';
    final tanggal = targetItem[DatabaseHelper.columnTanggal]?.toString() ?? '-';
    final waktu = targetItem[DatabaseHelper.columnWaktu]?.toString() ?? '-';
    final keterangan = targetItem[DatabaseHelper.columnKeterangan]?.toString() ?? '-';
    final isIzin = _isIzinTipe(tipe, keterangan);
    final isMasuk = _isMasukTipe(tipe, keterangan);
    final isPulang = _isPulangTipe(tipe, keterangan);

    final IconData deleteIcon;
    final Color deleteColor;
    final Color deleteBgColor;
    final Color deleteBorderColor;
    final String deleteTitle;
    final String badgeLabel;

    if (isIzin) {
      deleteIcon = Icons.event_busy_rounded;
      deleteColor = const Color(0xFF7C3AED);
      deleteBgColor = const Color(0xFFF5F3FF);
      deleteBorderColor = const Color(0xFFDDD6FE);
      deleteTitle = 'Hapus Pengajuan $tipe?';
      badgeLabel = 'Pengajuan Izin';
    } else if (isMasuk) {
      deleteIcon = Icons.login_rounded;
      deleteColor = const Color(0xFF059669);
      deleteBgColor = const Color(0xFFECFDF5);
      deleteBorderColor = const Color(0xFFA7F3D0);
      deleteTitle = 'Hapus Absen Masuk?';
      badgeLabel = 'Absen Masuk';
    } else {
      deleteIcon = isPulang ? Icons.logout_rounded : Icons.history_rounded;
      deleteColor = const Color(0xFFEA580C);
      deleteBgColor = const Color(0xFFFFF7ED);
      deleteBorderColor = const Color(0xFFFED7AA);
      deleteTitle = isPulang ? 'Hapus Absen Pulang?' : 'Hapus Absen $tipe?';
      badgeLabel = isPulang ? 'Absen Pulang' : 'Presensi $tipe';
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: deleteBgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: deleteBorderColor),
              ),
              child: Icon(deleteIcon, color: deleteColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                deleteTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: deleteBgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: deleteBorderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: deleteColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badgeLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          waktu.contains('WIB') ? waktu : '$waktu WIB',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isIzin ? 'Tanggal Izin: $tanggal' : 'Tanggal Presensi: $tanggal',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    if (keterangan.isNotEmpty && keterangan != '-') ...[
                      const SizedBox(height: 3),
                      Text(
                        isIzin ? 'Alasan: $keterangan' : 'Lokasi: $keterangan',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isIzin
                    ? 'Catatan pengajuan izin ini akan dihapus secara permanen.\n\n'
                        '• Data perizinan yang dihapus tidak dapat dipulihkan.\n'
                        '• Riwayat sinkronisasi lokal dan cloud akan dibersihkan.'
                    : 'Catatan kehadiran ini akan dihapus secara permanen.\n\n'
                        '• Data yang telah dihapus tidak akan muncul kembali.\n'
                        '• Akun Anda yang sedang login tetap aktif.',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Batal')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Hapus $tipe'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 1. Hapus dari SQLite dan catat ke blacklist permanen
    final deleted = await DatabaseHelper.instance.deleteAbsensi(id);

    // 2. Hapus juga di server API menggunakan ID API yang sebenarnya (hanya jika valid api_id)
    final apiId = deleted?[DatabaseHelper.columnApiId]?.toString();
    if (apiId != null &&
        apiId.isNotEmpty &&
        apiId != '0' &&
        apiId != 'null') {
      try {
        await AppApiService.deleteAbsensiFromApi(apiId);
      } catch (_) {}
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Catatan Absen $tipe berhasil dihapus secara permanen.'),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
    _loadAbsensiFromDb();
    _autoSyncAll();
  }

  // Hapus semua riwayat presensi secara PERMANEN (TIDAK mempengaruhi akun login)
  Future<void> _hapusSemuaRiwayatHome() async {
    final isOnline = await NetworkHelper.hasInternetConnection();
    if (!mounted) return;
    if (!isOnline) {
      NetworkHelper.showOfflineDialog(context, featureName: 'Hapus Semua Riwayat');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text('Hapus Semua Riwayat Absensi?')),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Seluruh riwayat presensi akan dihapus secara PERMANEN dari database dan server API.\n\n'
            '• Data yang dihapus TIDAK akan muncul kembali saat reload.\n'
            '• Akun Anda yang sedang login TIDAK akan terpengaruh sama sekali.',
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Batal')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Hapus Semua Permanen')),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final itemsToDelete = await DatabaseHelper.instance.getAllAbsensi(userId: _userId);
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
    await DatabaseHelper.instance.clearAllAbsensi(userId: _userId);
    await PrefHelper.setLastClearedTimestamp(DateTime.now().toIso8601String());

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Expanded(child: Text('Penghapusan Berhasil')),
          ],
        ),
        content: const Text(
          'Semua riwayat absensi berhasil dihapus permanen. Akun Anda tetap aktif.',
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Selesai'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    _loadAbsensiFromDb();
  }

  // Tampilkan Alert Dialog Detail Catatan Kehadiran / Perizinan (Read Detail)
  void _showDetailAbsensiDialog(Map<String, dynamic> item) {
    final id = item[DatabaseHelper.columnId] as int;
    final tipe = item[DatabaseHelper.columnTipe] as String? ?? 'Masuk';
    final tanggal = item[DatabaseHelper.columnTanggal] as String? ?? '-';
    final waktu = item[DatabaseHelper.columnWaktu] as String? ?? '-';
    final keterangan = item[DatabaseHelper.columnKeterangan] as String? ?? '-';
    final lat = item[DatabaseHelper.columnLatitude];
    final lon = item[DatabaseHelper.columnLongitude];
    final isSync = (item[DatabaseHelper.columnStatusSync] as int? ?? 0) == 1;

    final isIzin = _isIzinTipe(tipe, keterangan);
    final isMasuk = _isMasukTipe(tipe, keterangan);

    final IconData headerIcon;
    final Color headerColor;
    final String dialogTitle;

    if (isIzin) {
      headerIcon = Icons.event_note_rounded;
      headerColor = const Color(0xFF7C3AED);
      dialogTitle = 'Detail Pengajuan $tipe';
    } else if (isMasuk) {
      headerIcon = Icons.login_rounded;
      headerColor = const Color(0xFF059669);
      dialogTitle = 'Detail Absen Masuk';
    } else {
      headerIcon = Icons.logout_rounded;
      headerColor = const Color(0xFFEA580C);
      dialogTitle = 'Detail Absen Pulang';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: headerColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(headerIcon, color: headerColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                dialogTitle,
                style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailItemRow(isIzin ? 'Tanggal Izin' : 'Tanggal', tanggal),
              _buildDetailItemRow(isIzin ? 'Waktu Pengajuan' : 'Waktu', '$waktu WIB'),
              _buildDetailItemRow(
                'Kategori',
                isIzin ? 'Pengajuan Perizinan / Cuti ($tipe)' : 'Presensi Kehadiran ($tipe)',
              ),
              _buildDetailItemRow(
                'Status Sinkronisasi',
                isSync ? 'Tersinkron ke Cloud API' : 'Tersimpan di Lokal',
              ),
              if (lat != null && lon != null) ...[
                _buildDetailItemRow('Koordinat GPS', '$lat, $lon'),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      side: const BorderSide(color: Color(0xFF2563EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const GoogleMapsScreenDay19()),
                      );
                    },
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('Buka di Peta (Google Maps)', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _buildDetailItemRow(
                isIzin ? 'Alasan & Keterangan Izin' : 'Keterangan / Lokasi',
                keterangan.isNotEmpty ? keterangan : '-',
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isIzin ? const Color(0xFFF5F3FF) : Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isIzin ? const Color(0xFFDDD6FE) : Colors.amber.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isIzin ? Icons.verified_user_outlined : Icons.lock_outline,
                      size: 16,
                      color: isIzin ? const Color(0xFF7C3AED) : Colors.brown,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isIzin
                            ? 'Catatan pengajuan izin resmi tercatat di database dan terenkripsi.'
                            : 'Catatan presensi kehadiran resmi terkunci otomatis dan tidak dapat diedit.',
                        style: TextStyle(
                          fontSize: 11,
                          color: isIzin ? const Color(0xFF6B21A8) : Colors.brown,
                          fontWeight: FontWeight.w500,
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Tutup')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _hapusAbsensi(id, item: item);
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Hapus')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItemRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // 8. Logout dan hapus SharedPreferences
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Konfirmasi Logout'),
        content: const SingleChildScrollView(
          child: Text('Apakah Anda yakin ingin keluar dari akun?'),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Batal')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Logout', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm != true) return;

    AppNotificationHelper.hasShownWelcomeSession = false;
    await PrefHelper.clearSession();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  // Dialog / BottomSheet Pusat Notifikasi & Status (Riwayat Notifikasi Lengkap seperti YouTube)
  void _showNotificationCenterBottomSheet() {
    NotificationCenterScreen.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final waktuMasuk = _absenMasukHariIni?['waktu']?.toString() ?? '';
    final sudahMasuk = _absenMasukHariIni != null &&
        waktuMasuk.isNotEmpty &&
        waktuMasuk != '00:00:00' &&
        waktuMasuk != '-' &&
        waktuMasuk != '--:--' &&
        waktuMasuk != '--:--:--';

    final waktuPulang = _absenPulangHariIni?['waktu']?.toString() ?? '';
    final sudahPulang = _absenPulangHariIni != null &&
        waktuPulang.isNotEmpty &&
        waktuPulang != '00:00:00' &&
        waktuPulang != '-' &&
        waktuPulang != '--:--' &&
        waktuPulang != '--:--:--';

    return Scaffold(
      appBar: _currentTabIndex == 0
          ? AppBar(
              elevation: 0,
              scrolledUnderElevation: 1,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Absensiku',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                // Tombol Manual Cloud Sync
                IconButton(
                  icon: _isManualSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                          ),
                        )
                      : const Icon(Icons.cloud_sync_outlined),
                  tooltip: 'Sinkronisasi Cloud API',
                  onPressed: _isManualSyncing ? null : _triggerManualSync,
                ),
                // Tombol Notifikasi dengan Badge Live
                ValueListenableBuilder<int>(
                  valueListenable: AppNotificationHelper.unreadCountNotifier,
                  builder: (context, unreadCount, _) {
                    return IconButton(
                      icon: Badge(
                        isLabelVisible: unreadCount > 0,
                        label: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        backgroundColor: Colors.redAccent,
                        child: const Icon(Icons.notifications_outlined),
                      ),
                      tooltip: 'Pusat Notifikasi & Riwayat',
                      onPressed: _showNotificationCenterBottomSheet,
                    );
                  },
                ),
                // Tombol Pengaturan
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Pengaturan & Cloud',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    ).then((_) {
                      _startPeriodicAutoSync();
                      _loadUserData();
                      _loadAbsensiFromDb();
                    });
                  },
                ),
                // Tombol Refresh
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh Status',
                  onPressed: () async {
                    await _loadUserData();
                    await _loadAbsensiFromDb();
                  },
                ),
                // Tombol Logout
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: _logout,
                ),
              ],
            )
          : null,
      body: _buildBody(sudahMasuk, sudahPulang),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        elevation: 3,
        onDestinationSelected: (int index) {
          setState(() {
            _currentTabIndex = index;
          });
          if (index == 0) {
            _loadAbsensiFromDb();
            _loadUserData();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Daftar Hadir',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool sudahMasuk, bool sudahPulang) {
    switch (_currentTabIndex) {
      case 0:
        return _buildBerandaContent(sudahMasuk, sudahPulang);
      case 1:
        return const DaftarHadirScreen();
      case 2:
        return const ProfileScreen();
      default:
        return _buildBerandaContent(sudahMasuk, sudahPulang);
    }
  }

  Widget _buildBerandaContent(bool sudahMasuk, bool sudahPulang) {
    final totalMasukHome = _riwayatAbsensi.where((item) {
      final t = item[DatabaseHelper.columnTipe] as String? ?? '';
      final k = item[DatabaseHelper.columnKeterangan] as String? ?? '';
      return _isMasukTipe(t, k);
    }).length;

    final totalPulangHome = _riwayatAbsensi.where((item) {
      final t = item[DatabaseHelper.columnTipe] as String? ?? '';
      final k = item[DatabaseHelper.columnKeterangan] as String? ?? '';
      return _isPulangTipe(t, k);
    }).length;

    final totalIzinHome = _riwayatAbsensi.where((item) {
      final t = item[DatabaseHelper.columnTipe] as String? ?? '';
      final k = item[DatabaseHelper.columnKeterangan] as String? ?? '';
      return _isIzinTipe(t, k);
    }).length;

    final totalAbsensiHome = totalMasukHome + totalPulangHome;
    final displayHistoryList = _filteredRiwayatAbsensi;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadUserData();
        await _loadAbsensiFromDb();
        await _getHomeLocation();
        await _autoSyncAll();
        try {
          await AppApiService.getProfileFromApi();
        } catch (_) {}
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. HERO HEADER: PROFIL MODERN & SAPAAN DENGAN BACKGROUND GRADIENT
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF0F172A), // Deep Slate Navy
                    Color(0xFF1E3A8A), // Royal Blue
                    Color(0xFF2563EB), // Vibrant Azure
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: Stack(
                children: [
                  // Ambient light decorative circles for depth
                  Positioned(
                    top: -40,
                    right: -30,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -30,
                    left: 20,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.lightBlueAccent.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  // Konten Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Baris Sapaan & Tag Status Cloud
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _getGreeting(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade100,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _triggerManualSync,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xFF34D399), // Emerald pulse dot
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Cloud Sync Aktif',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Baris Avatar Profil & Nama Pengguna
                        InkWell(
                          onTap: () {
                            setState(() {
                              _currentTabIndex = 2;
                            });
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Stack(
                                  children: [
                                    Builder(
                                      builder: (ctx) {
                                        final hasPhoto = _userPhotoPath != null &&
                                            _userPhotoPath!.isNotEmpty &&
                                            (_userPhotoPath!.startsWith('http://') ||
                                                _userPhotoPath!.startsWith('https://') ||
                                                File(_userPhotoPath!).existsSync());
                                        ImageProvider? imageProvider;
                                        if (hasPhoto) {
                                          if (_userPhotoPath!.startsWith('http://') ||
                                              _userPhotoPath!.startsWith('https://')) {
                                            imageProvider = NetworkImage(_userPhotoPath!);
                                          } else {
                                            imageProvider = FileImage(File(_userPhotoPath!));
                                          }
                                        }
                                        return Container(
                                          padding: const EdgeInsets.all(2.5),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white.withValues(alpha: 0.85),
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.2),
                                                blurRadius: 8,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: CircleAvatar(
                                            radius: 26,
                                            backgroundColor: Colors.white.withValues(alpha: 0.25),
                                            backgroundImage: imageProvider,
                                            child: !hasPhoto
                                                ? Text(
                                                    _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                                                    style: const TextStyle(
                                                      fontSize: 22,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                        );
                                      },
                                    ),
                                    Positioned(
                                      bottom: 2,
                                      right: 2,
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF10B981),
                                          border: Border.all(color: Colors.white, width: 2),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _userName.isNotEmpty ? _userName : 'Karyawan',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _userEmail.isNotEmpty ? _userEmail : 'Presensi Digital Terverifikasi',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w400,
                                          color: Colors.blue.shade100,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Baris Tanggal Hari Ini
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_note_rounded, size: 16, color: Colors.white),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _getFormattedToday(),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              Text(
                                '${DateTime.now().year}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade200,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 2. KARTU INFORMASI STATUS HARI INI (MEMBEDAKAN SUDAH VS BELUM)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blueGrey.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.10),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.schedule_rounded,
                            size: 18,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Status Presensi Hari Ini',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (sudahMasuk && sudahPulang)
                                ? const Color(0xFFECFDF5)
                                : (sudahMasuk
                                    ? const Color(0xFFEFF6FF)
                                    : const Color(0xFFFFFBEB)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: (sudahMasuk && sudahPulang)
                                  ? const Color(0xFFA7F3D0)
                                  : (sudahMasuk
                                      ? const Color(0xFFBFDBFE)
                                      : const Color(0xFFFDE68A)),
                            ),
                          ),
                          child: Text(
                            (sudahMasuk && sudahPulang)
                                ? 'Lengkap'
                                : (sudahMasuk ? 'Aktif Bekerja' : 'Belum Mulai'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: (sudahMasuk && sudahPulang)
                                  ? const Color(0xFF047857)
                                  : (sudahMasuk
                                      ? const Color(0xFF1D4ED8)
                                      : const Color(0xFFB45309)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Baris 2 Kotak Status: Masuk & Pulang
                    Row(
                      children: [
                        // KOTAK STATUS MASUK
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: sudahMasuk ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: sudahMasuk ? const Color(0xFF86EFAC) : const Color(0xFFFED7AA),
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Flexible(
                                      child: Text(
                                        'Absen Masuk',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                                      ),
                                    ),
                                    Icon(
                                      sudahMasuk ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                                      color: sudahMasuk ? const Color(0xFF10B981) : const Color(0xFFF97316),
                                      size: 18,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  sudahMasuk ? 'SUDAH ABSEN' : 'BELUM ABSEN',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                    color: sudahMasuk ? const Color(0xFF065F46) : const Color(0xFF9A3412),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  sudahMasuk ? '${_absenMasukHariIni!['waktu']} WIB' : '-- : -- WIB',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: sudahMasuk ? FontWeight.bold : FontWeight.w500,
                                    color: sudahMasuk ? const Color(0xFF1F2937) : Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // KOTAK STATUS PULANG
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: sudahPulang ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: sudahPulang ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0),
                                width: 1.2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Flexible(
                                      child: Text(
                                        'Absen Keluar',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                                      ),
                                    ),
                                    Icon(
                                      sudahPulang ? Icons.check_circle_rounded : Icons.schedule_outlined,
                                      color: sudahPulang ? const Color(0xFF2563EB) : Colors.grey[400],
                                      size: 18,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  sudahPulang ? 'SUDAH ABSEN' : 'BELUM ABSEN',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                    color: sudahPulang ? const Color(0xFF1E40AF) : Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  sudahPulang ? '${_absenPulangHariIni!['waktu']} WIB' : '-- : -- WIB',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: sudahPulang ? FontWeight.bold : FontWeight.w500,
                                    color: sudahPulang ? const Color(0xFF1F2937) : Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // 3. TOMBOL AKSI PRESENSI DENGAN GRADIENT & SHADOW MEWAH
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  // Tombol Absen Masuk
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: sudahMasuk
                            ? null
                            : const LinearGradient(
                                colors: [Color(0xFF059669), Color(0xFF10B981)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        color: sudahMasuk ? const Color(0xFFE2E8F0) : null,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: sudahMasuk
                            ? null
                            : [
                                BoxShadow(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _handleAbsenMasuk,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  sudahMasuk ? Icons.check_circle_outline : Icons.login_rounded,
                                  color: sudahMasuk ? Colors.black45 : Colors.white,
                                  size: 19,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    sudahMasuk ? 'Sudah Masuk' : 'Absen Masuk',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: sudahMasuk ? Colors.black54 : Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Tombol Absen Keluar
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: (sudahMasuk && !sudahPulang)
                            ? const LinearGradient(
                                colors: [Color(0xFFEA580C), Color(0xFFF97316)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: (sudahPulang || !sudahMasuk) ? const Color(0xFFE2E8F0) : null,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: (sudahMasuk && !sudahPulang)
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFF97316).withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _handleAbsenPulang,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  sudahPulang ? Icons.check_circle_outline : Icons.logout_rounded,
                                  color: (sudahPulang || !sudahMasuk) ? Colors.black45 : Colors.white,
                                  size: 19,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    sudahPulang ? 'Sudah Keluar' : 'Absen Keluar',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: (sudahPulang || !sudahMasuk) ? Colors.black54 : Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 4. MENU CEPAT / FITUR PINTAR (Peta GPS, Izin, Hadir, Sync Cloud)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blueGrey.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // A. PETA LOKASI
                    _buildQuickActionItem(
                      icon: Icons.map_outlined,
                      label: 'Peta GPS',
                      color: const Color(0xFFEF4444),
                      bgColor: const Color(0xFFFEE2E2),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const GoogleMapsScreenDay19(),
                          ),
                        );
                      },
                    ),
                    // B. AJUKAN IZIN
                    _buildQuickActionItem(
                      icon: Icons.assignment_outlined,
                      label: 'Ajukan Izin',
                      color: const Color(0xFF2563EB),
                      bgColor: const Color(0xFFDBEAFE),
                      onTap: () async {
                        final res = await FormIzinScreen.showAsBottomSheet(context);
                        if (res == true) {
                          _loadInitialData();
                        }
                      },
                    ),
                    // C. RIWAYAT
                    _buildQuickActionItem(
                      icon: Icons.history_rounded,
                      label: 'Riwayat',
                      color: const Color(0xFF059669),
                      bgColor: const Color(0xFFD1FAE5),
                      onTap: () {
                        setState(() {
                          _currentTabIndex = 1;
                        });
                      },
                    ),
                    // D. SINKRON CLOUD
                    _buildQuickActionItem(
                      icon: Icons.cloud_sync_outlined,
                      label: 'Sync Cloud',
                      color: const Color(0xFF7C3AED),
                      bgColor: const Color(0xFFEDE9FE),
                      onTap: _triggerManualSync,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            // 5. HEADER RIWAYAT ABSENSI TERKINI
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.history_rounded, size: 18, color: Color(0xFF2563EB)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Riwayat Terkini',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_riwayatAbsensi.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_riwayatAbsensi.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.redAccent),
                      tooltip: 'Hapus Semua Riwayat',
                      onPressed: _hapusSemuaRiwayatHome,
                    ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      setState(() {
                        _currentTabIndex = 1;
                      });
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Lihat Semua',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right, size: 16, color: Color(0xFF2563EB)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Tab Filter Kategori Riwayat Terkini (Full-width dengan Expanded)
            if (_riwayatAbsensi.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    _buildExpandedFilterTab(
                      label: 'Semua',
                      count: _riwayatAbsensi.length,
                      icon: Icons.apps_rounded,
                      activeColor: const Color(0xFF2563EB),
                      isSelected: _selectedHistoryFilter == 'Semua',
                      onTap: () {
                        setState(() {
                          _selectedHistoryFilter = 'Semua';
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildExpandedFilterTab(
                      label: 'Absensi',
                      count: totalAbsensiHome,
                      icon: Icons.how_to_reg_rounded,
                      activeColor: const Color(0xFF0284C7),
                      isSelected: _selectedHistoryFilter == 'Absensi' ||
                          _selectedHistoryFilter == 'Masuk' ||
                          _selectedHistoryFilter == 'Pulang',
                      onTap: () {
                        setState(() {
                          _selectedHistoryFilter = 'Absensi';
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildExpandedFilterTab(
                      label: 'Izin',
                      count: totalIzinHome,
                      icon: Icons.event_note_rounded,
                      activeColor: const Color(0xFF7C3AED),
                      isSelected: _selectedHistoryFilter == 'Izin',
                      onTap: () {
                        setState(() {
                          _selectedHistoryFilter = 'Izin';
                        });
                      },
                    ),
                  ],
                ),
              ),

              // Sub-Filter untuk Absensi (Semua Absensi, Masuk, Pulang - juga dengan Expanded)
              if (_selectedHistoryFilter == 'Absensi' ||
                  _selectedHistoryFilter == 'Masuk' ||
                  _selectedHistoryFilter == 'Pulang') ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      _buildSubFilterTab(
                        label: 'Semua Absensi',
                        count: totalAbsensiHome,
                        icon: Icons.done_all_rounded,
                        activeColor: const Color(0xFF0284C7),
                        isSelected: _selectedHistoryFilter == 'Absensi',
                        onTap: () {
                          setState(() {
                            _selectedHistoryFilter = 'Absensi';
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildSubFilterTab(
                        label: 'Masuk',
                        count: totalMasukHome,
                        icon: Icons.login_rounded,
                        activeColor: const Color(0xFF059669),
                        isSelected: _selectedHistoryFilter == 'Masuk',
                        onTap: () {
                          setState(() {
                            _selectedHistoryFilter = 'Masuk';
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildSubFilterTab(
                        label: 'Pulang',
                        count: totalPulangHome,
                        icon: Icons.logout_rounded,
                        activeColor: const Color(0xFFEA580C),
                        isSelected: _selectedHistoryFilter == 'Pulang',
                        onTap: () {
                          setState(() {
                            _selectedHistoryFilter = 'Pulang';
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],

            // 5. Daftar Riwayat dari SQLite (Tanpa Expanded agar tidak RenderFlex overflow)
            if (_isLoadingDb)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32.0),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_riwayatAbsensi.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off, size: 54, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'Belum ada riwayat absensi tersimpan',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              )
            else if (displayHistoryList.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _selectedHistoryFilter == 'Izin'
                            ? Icons.event_busy_rounded
                            : (_selectedHistoryFilter == 'Absensi'
                                ? Icons.how_to_reg_rounded
                                : (_selectedHistoryFilter == 'Masuk'
                                    ? Icons.login_rounded
                                    : (_selectedHistoryFilter == 'Pulang'
                                        ? Icons.logout_rounded
                                        : Icons.history_toggle_off))),
                        size: 44,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tidak ada riwayat kategori $_selectedHistoryFilter yang sesuai',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: displayHistoryList.length > 5 ? 5 : displayHistoryList.length,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                itemBuilder: (context, index) {
                  final item = displayHistoryList[index];
                  final id = item[DatabaseHelper.columnId] as int;
                  final tipe = item[DatabaseHelper.columnTipe] as String? ?? 'Masuk';
                  final tanggal = item[DatabaseHelper.columnTanggal] as String? ?? '';
                  final waktu = item[DatabaseHelper.columnWaktu] as String? ?? '';
                  final keterangan = item[DatabaseHelper.columnKeterangan] as String? ?? '';
                  final lat = item[DatabaseHelper.columnLatitude];
                  final lon = item[DatabaseHelper.columnLongitude];
                  final isSync = (item[DatabaseHelper.columnStatusSync] as int? ?? 0) == 1;

                  final isIzin = _isIzinTipe(tipe, keterangan);
                  final isMasuk = _isMasukTipe(tipe, keterangan);

                  final Color itemBgColor;
                  final Color itemBorderColor;
                  final Color itemColor;
                  final IconData itemIcon;
                  final String titleText;
                  final String badgeCategory;

                  if (isIzin) {
                    final isSakit = keterangan.toLowerCase().contains('[sakit]') ||
                        tipe.toLowerCase().contains('sakit');
                    final isCuti = keterangan.toLowerCase().contains('[cuti]') ||
                        tipe.toLowerCase().contains('cuti');
                    itemBgColor = const Color(0xFFF5F3FF);
                    itemBorderColor = const Color(0xFFDDD6FE);
                    itemColor = const Color(0xFF7C3AED);
                    itemIcon = isSakit
                        ? Icons.medical_services_rounded
                        : (isCuti ? Icons.beach_access_rounded : Icons.event_note_rounded);
                    titleText = isSakit ? 'Izin Sakit' : (isCuti ? 'Pengajuan Cuti' : 'Pengajuan Izin');
                    badgeCategory = 'Izin';
                  } else if (isMasuk) {
                    itemBgColor = const Color(0xFFECFDF5);
                    itemBorderColor = const Color(0xFFA7F3D0);
                    itemColor = const Color(0xFF059669);
                    itemIcon = Icons.login_rounded;
                    titleText = 'Absen Masuk';
                    badgeCategory = 'Masuk';
                  } else {
                    itemBgColor = const Color(0xFFFFF7ED);
                    itemBorderColor = const Color(0xFFFED7AA);
                    itemColor = const Color(0xFFEA580C);
                    itemIcon = Icons.logout_rounded;
                    titleText = 'Absen Pulang';
                    badgeCategory = 'Pulang';
                  }

                  final lokasiText = keterangan.isNotEmpty
                      ? keterangan
                      : (isIzin
                          ? 'Pengajuan perizinan tercatat'
                          : (lat != null && lon != null
                              ? 'Koordinat: $lat, $lon'
                              : 'Lokasi tercatat saat presensi'));

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showDetailAbsensiDialog(item),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Icon Tipe Absen (Diferensiasi Izin vs Masuk vs Pulang)
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: itemBgColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: itemBorderColor),
                                ),
                                child: Icon(
                                  itemIcon,
                                  color: itemColor,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Content Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          titleText,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        // Badge Kategori (Izin, Masuk, Pulang)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: itemBgColor,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: itemBorderColor),
                                          ),
                                          child: Text(
                                            badgeCategory,
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: itemColor,
                                            ),
                                          ),
                                        ),
                                        // Badge Sinkronisasi
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: isSync
                                                ? const Color(0xFFECFDF5)
                                                : const Color(0xFFFFFBEB),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isSync
                                                  ? const Color(0xFFA7F3D0)
                                                  : const Color(0xFFFDE68A),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                isSync
                                                    ? Icons.cloud_done_rounded
                                                    : Icons.cloud_upload_outlined,
                                                size: 11,
                                                color: isSync
                                                    ? const Color(0xFF059669)
                                                    : const Color(0xFFD97706),
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                isSync ? 'Tersinkron' : 'Lokal',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: isSync
                                                      ? const Color(0xFF059669)
                                                      : const Color(0xFFD97706),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.access_time_rounded,
                                          size: 13,
                                          color: Colors.grey[500],
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '$tanggal • $waktu WIB',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[700],
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isIzin ? Icons.edit_note_rounded : Icons.location_on_rounded,
                                            size: 14,
                                            color: isIzin ? const Color(0xFF7C3AED) : const Color(0xFFEF4444),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              lokasiText,
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF334155),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Trailing Delete Button
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    color: Color(0xFFEF4444), size: 20),
                                tooltip: 'Hapus data',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _hapusAbsensi(id, item: item),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

            const SizedBox(height: 16),

            // 6. Section Peta Google Maps di Bawah Beranda (Home)
            _buildHomeMapsSection(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // 7. Widget Tampilan Peta & Lokasi di Bagian Bawah Beranda (Home)
  Widget _buildHomeMapsSection() {
    final lat = _homeCurrentPosition?.latitude;
    final lng = _homeCurrentPosition?.longitude;
    final initialPos = _homeCurrentPosition != null
        ? LatLng(_homeCurrentPosition!.latitude, _homeCurrentPosition!.longitude)
        : _defaultLocation;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 18,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lokasi Presensi & Radius',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                    ),
                    Text(
                      'Deteksi koordinat GPS presensi real-time',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GoogleMapsScreenDay19(),
                    ),
                  );
                },
                icon: const Icon(Icons.fullscreen_rounded, size: 16, color: Color(0xFF2563EB)),
                label: const Text(
                  'Layar Penuh',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Kartu Peta Modern
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Box Peta Interaktif (Google Maps Asli)
                SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: initialPos,
                          zoom: 15.0,
                        ),
                        onMapCreated: (GoogleMapController controller) {
                          _homeMapController = controller;
                          if (_homeCurrentPosition != null) {
                            controller.animateCamera(
                              CameraUpdate.newCameraPosition(
                                CameraPosition(
                                  target: LatLng(_homeCurrentPosition!.latitude, _homeCurrentPosition!.longitude),
                                  zoom: 16.0,
                                ),
                              ),
                            );
                          }
                        },
                        markers: _homeMarkers,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                      ),

                      // Indikator Loading GPS
                      if (_isLoadingLocation)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Mencari GPS...',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Tombol GPS Refresh Melayang di Pojok Kanan Atas
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          elevation: 4,
                          shadowColor: Colors.black.withValues(alpha: 0.2),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _getHomeLocation(showDialogIfOffline: true),
                            child: const Padding(
                              padding: EdgeInsets.all(9.0),
                              child: Icon(Icons.my_location_rounded, size: 20, color: Color(0xFF2563EB)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Informasi Alamat & Tombol Aksi di Bawah Peta
                Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.place_rounded, size: 16, color: Color(0xFFEF4444)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _homeCurrentAddress,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Tag Koordinat
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.pin_drop_outlined, size: 12, color: Color(0xFF475569)),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    lat != null
                                        ? 'Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng!.toStringAsFixed(5)}'
                                        : 'Koordinat: Default (-6.2000, 106.8166)',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Tombol Aksi di Bagian Bawah
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _getHomeLocation,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF2563EB)),
                          label: const Text(
                            'Perbarui Koordinat GPS',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedFilterTab({
    required String label,
    required int count,
    required IconData icon,
    required Color activeColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected ? activeColor : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? activeColor : const Color(0xFFCBD5E1),
                width: isSelected ? 1.6 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: isSelected ? Colors.white : activeColor,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFF334155),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.25)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubFilterTab({
    required String label,
    required int count,
    required IconData icon,
    required Color activeColor,
    required bool isSelected,
    required VoidCallback onTap,
    bool isExpanded = true,
  }) {
    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            vertical: 6,
            horizontal: isExpanded ? 4 : 10,
          ),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? activeColor : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? activeColor : const Color(0xFF64748B),
              ),
              const SizedBox(width: 4),
              if (isExpanded)
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? activeColor : const Color(0xFF475569),
                    ),
                  ),
                )
              else
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? activeColor : const Color(0xFF475569),
                  ),
                ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor.withValues(alpha: 0.15)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? activeColor : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return isExpanded ? Expanded(child: content) : content;
  }
}
