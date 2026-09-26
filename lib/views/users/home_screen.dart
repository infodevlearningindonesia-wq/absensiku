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
import 'package:absensiku/services/pref_helper.dart';
import 'package:absensiku/views/auth/login_screen.dart';
import 'package:absensiku/views/users/daftar_hadir_screen.dart';
import 'package:absensiku/views/users/maps_screen.dart';
import 'package:absensiku/views/users/profile_screen.dart';

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

  void _startPeriodicAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
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

    final data = await DatabaseHelper.instance.getAllAbsensi(userId: _userId);
    final today = _getTodayString();

    final masuk = await DatabaseHelper.instance.getAbsensiHariIni(
      tanggal: today,
      tipe: 'Masuk',
      userId: _userId,
    );

    final pulang = await DatabaseHelper.instance.getAbsensiHariIni(
      tanggal: today,
      tipe: 'Keluar',
      userId: _userId,
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

  // 3b. Mengambil posisi GPS dan alamat terkini untuk widget Maps di bagian bawah Home
  Future<void> _getHomeLocation() async {
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
    // CEK: Jika SUDAH absen masuk hari ini
    if (_absenMasukHariIni != null) {
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
              'Anda SUDAH melakukan Absen Masuk hari ini pada pukul ${_absenMasukHariIni!['waktu']} WIB.\n\nTidak dapat melakukan absen masuk dua kali.',
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
    // CEK 1: Mencegah kesalahan jika BELUM absen masuk
    if (_absenMasukHariIni == null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Perhatian!',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: const SingleChildScrollView(
            child: Text(
              'Anda BELUM melakukan Absen Masuk hari ini!\n\nUntuk menghindari kesalahan data, silakan lakukan Absen Masuk terlebih dahulu sebelum Absen Keluar.',
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Kembali', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      return;
    }

    // CEK 2: Jika SUDAH absen keluar hari ini
    if (_absenPulangHariIni != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blueAccent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Informasi Absen Keluar',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              'Anda SUDAH melakukan Absen Keluar hari ini pada pukul ${_absenPulangHariIni!['waktu']} WIB.\n\nKehadiran hari ini telah lengkap.',
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

    // Jika sudah absen masuk dan BELUM absen keluar, minta konfirmasi
    final now = DateTime.now();
    final waktu =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

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

    // 1. Coba hubungkan dan kirim ke API Server Backend
    bool apiSuccess = false;
    try {
      apiSuccess = await AppApiService.submitAbsensiToApi(
        tipe: tipe,
        tanggal: tanggal,
        waktu: waktu,
        latitude: lat,
        longitude: lon,
        keterangan: ket,
      );
    } catch (_) {
      apiSuccess = false;
    }

    // 2. Simpan ke database lokal SQLite
    final id = await DatabaseHelper.instance.insertAbsensi({
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

    if (id > 0) {
      final isMasuk = tipe.toLowerCase() == 'masuk';
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.check_circle, color: isMasuk ? Colors.green : Colors.blue),
                const SizedBox(width: 8),
                Text('Presensi $tipe Berhasil'),
              ],
            ),
            content: Text(
              'Data absen $tipe berhasil disimpan.\n\n'
              '• Waktu: $waktu WIB\n'
              '• Tanggal: $tanggal\n'
              '• Status: ${apiSuccess ? "Tersinkron ke Server API" : "Tersimpan di SQLite Lokal"}',
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
      _loadAbsensiFromDb();
      _autoSyncAll();
    }
  }

  // 7. Hapus 1 riwayat secara PERMANEN dari SQLite & API (dengan Alert Dialog)
  Future<void> _hapusAbsensi(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text('Hapus Catatan Kehadiran?')),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Catatan ini akan dihapus secara PERMANEN dari database lokal SQLite dan server API.\n\n'
            '• Data yang telah dihapus TIDAK akan muncul kembali saat reload.\n'
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
                  icon: const Icon(Icons.delete, size: 18),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Hapus Permanen')),
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

    // 2. Hapus juga di server API menggunakan ID API yang sebenarnya
    final apiId = deleted?[DatabaseHelper.columnApiId] ?? id;
    try {
      await AppApiService.deleteAbsensiFromApi(apiId);
    } catch (_) {}

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text('Catatan berhasil dihapus permanen.')),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
    _loadAbsensiFromDb();
  }

  // Hapus semua riwayat presensi secara PERMANEN (TIDAK mempengaruhi akun login)
  Future<void> _hapusSemuaRiwayatHome() async {
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
            'Seluruh riwayat presensi akan dihapus secara PERMANEN.\n\n'
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
            Text('Penghapusan Berhasil'),
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

  // Tampilkan Alert Dialog Detail Catatan Kehadiran (Read Detail)
  void _showDetailAbsensiDialog(Map<String, dynamic> item) {
    final id = item[DatabaseHelper.columnId] as int;
    final tipe = item[DatabaseHelper.columnTipe] as String? ?? 'Masuk';
    final tanggal = item[DatabaseHelper.columnTanggal] as String? ?? '-';
    final waktu = item[DatabaseHelper.columnWaktu] as String? ?? '-';
    final keterangan = item[DatabaseHelper.columnKeterangan] as String? ?? '-';
    final lat = item[DatabaseHelper.columnLatitude];
    final lon = item[DatabaseHelper.columnLongitude];
    final isSync = (item[DatabaseHelper.columnStatusSync] as int? ?? 0) == 1;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              tipe.toLowerCase() == 'masuk' ? Icons.login : Icons.logout,
              color: tipe.toLowerCase() == 'masuk' ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('Detail Absen $tipe')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailItemRow('Tanggal', tanggal),
              _buildDetailItemRow('Waktu', '$waktu WIB'),
              _buildDetailItemRow('Tipe', tipe),
              _buildDetailItemRow(
                'Status Sync',
                isSync ? 'Sudah Tersinkron ke Server' : 'Tersimpan Lokal (SQLite)',
              ),
              if (lat != null && lon != null)
                _buildDetailItemRow('Koordinat GPS', '$lat, $lon'),
              _buildDetailItemRow('Keterangan / Lokasi', keterangan),
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
                    _hapusAbsensi(id);
                  },
                  icon: const Icon(Icons.delete, size: 16),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Hapus Data')),
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

  // Sinkronisasi data yang masih pending (status_sync = 0) ke API server dengan Alert Dialog
  Future<void> _syncPendingAbsensi() async {
    final unsynced = await DatabaseHelper.instance.getUnsyncedAbsensi();
    if (!mounted) return;

    if (unsynced.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Sinkronisasi Selesai'),
            ],
          ),
          content: const Text('Semua data absensi sudah tersinkronisasi ke API server.'),
          actions: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Tutup'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Menyinkronkan ${unsynced.length} data ke API server...'),
        duration: const Duration(seconds: 1),
      ),
    );

    final count = await AppApiService.syncAllPendingToApi();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cloud_done, color: Colors.green),
            SizedBox(width: 8),
            Text('Hasil Sinkronisasi'),
          ],
        ),
        content: Text('$count data kehadiran berhasil disinkronkan ke API server!'),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Tutup'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    _loadAbsensiFromDb();
  }

  // 8. Logout dan hapus SharedPreferences
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Konfirmasi Logout'),
        content: const SingleChildScrollView(
          child: Text('Apakah Anda yakin ingin keluar? Session login di SharedPreferences akan dihapus.'),
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

    await PrefHelper.clearSession();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sudahMasuk = _absenMasukHariIni != null;
    final sudahPulang = _absenPulangHariIni != null;

    return Scaffold(
      appBar: _currentTabIndex == 0
          ? AppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('Absensiku'),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.cloud_sync),
                  tooltip: 'Sinkronisasi API',
                  onPressed: _syncPendingAbsensi,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh Status',
                  onPressed: () async {
                    await _loadUserData();
                    await _loadAbsensiFromDb();
                  },
                ),
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
            // 1. Profil Pengguna (SharedPreferences)
            Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _currentTabIndex = 2;
                  });
                },
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Builder(
                        builder: (ctx) {
                          final hasPhoto = _userPhotoPath != null &&
                              _userPhotoPath!.isNotEmpty &&
                              File(_userPhotoPath!).existsSync();
                          return CircleAvatar(
                            radius: 28,
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            backgroundImage: hasPhoto ? FileImage(File(_userPhotoPath!)) : null,
                            child: !hasPhoto
                                ? Text(
                                    _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              _userEmail.isNotEmpty ? _userEmail : 'Email pengguna',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey[700],
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.black45),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 2. KARTU INFORMASI STATUS HARI INI (MEMBEDAKAN SUDAH VS BELUM)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.access_time_filled, size: 20, color: Colors.blueAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Status Kehadiran Hari Ini',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),

                      // Baris 2 Kotak Status: Masuk & Pulang
                      Row(
                        children: [
                          // KOTAK STATUS MASUK
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: sudahMasuk ? Colors.green.shade50 : Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: sudahMasuk ? Colors.green.shade300 : Colors.red.shade200,
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Absen Masuk',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      Icon(
                                        sudahMasuk ? Icons.check_circle : Icons.cancel_outlined,
                                        color: sudahMasuk ? Colors.green : Colors.red,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      sudahMasuk ? 'SUDAH ABSEN' : 'BELUM ABSEN',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: sudahMasuk ? Colors.green.shade800 : Colors.red.shade800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    sudahMasuk ? '${_absenMasukHariIni!['waktu']} WIB' : '-- : -- WIB',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: sudahMasuk ? Colors.black87 : Colors.grey[600],
                                      fontWeight: sudahMasuk ? FontWeight.w600 : FontWeight.normal,
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
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: sudahPulang ? Colors.blue.shade50 : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: sudahPulang ? Colors.blue.shade300 : Colors.orange.shade200,
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Absen Keluar',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      Icon(
                                        sudahPulang ? Icons.check_circle : Icons.cancel_outlined,
                                        color: sudahPulang ? Colors.blue : Colors.orange,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      sudahPulang ? 'SUDAH ABSEN' : 'BELUM ABSEN',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: sudahPulang ? Colors.blue.shade800 : Colors.orange.shade900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    sudahPulang ? '${_absenPulangHariIni!['waktu']} WIB' : '-- : -- WIB',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: sudahPulang ? Colors.black87 : Colors.grey[600],
                                      fontWeight: sudahPulang ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // TAMPILAN HARI, TANGGAL, BULAN, TAHUN DI BAWAH
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.calendar_month, size: 18, color: Colors.blueAccent),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _getFormattedToday(), // Menampilkan Hari, Tanggal Bulan Tahun
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueAccent,
                                  letterSpacing: 0.3,
                                ),
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

            const SizedBox(height: 12),

            // 3. TOMBOL AKSI DENGAN INDIKATOR STATUS JELAS
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  // Tombol Absen Masuk
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _handleAbsenMasuk,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: sudahMasuk ? Colors.grey[300] : Colors.green,
                        foregroundColor: sudahMasuk ? Colors.black54 : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: sudahMasuk ? 0 : 2,
                      ),
                      icon: Icon(sudahMasuk ? Icons.check : Icons.login),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          sudahMasuk ? 'Sudah Masuk' : 'Absen Masuk',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Tombol Absen Keluar (Sync ke API & SQLite)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _handleAbsenPulang,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: sudahPulang
                            ? Colors.grey[300]
                            : (!sudahMasuk ? Colors.grey[350] : Colors.orange[800]),
                        foregroundColor: sudahPulang || !sudahMasuk ? Colors.black54 : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: sudahPulang || !sudahMasuk ? 0 : 2,
                      ),
                      icon: Icon(sudahPulang ? Icons.check : Icons.logout),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          sudahPulang ? 'Sudah Keluar' : 'Absen Keluar',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 4. Header Riwayat SQFlite
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.history, size: 20, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Riwayat Absensi',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_riwayatAbsensi.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_sweep, size: 20, color: Colors.red),
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Lihat Semua (${_riwayatAbsensi.length})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const Icon(Icons.chevron_right, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(),

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
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _riwayatAbsensi.length > 5 ? 5 : _riwayatAbsensi.length,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                itemBuilder: (context, index) {
                  final item = _riwayatAbsensi[index];
                  final id = item[DatabaseHelper.columnId] as int;
                  final tipe = item[DatabaseHelper.columnTipe] as String? ?? 'Masuk';
                  final tanggal = item[DatabaseHelper.columnTanggal] as String? ?? '';
                  final waktu = item[DatabaseHelper.columnWaktu] as String? ?? '';
                  final keterangan = item[DatabaseHelper.columnKeterangan] as String? ?? '';
                  final lat = item[DatabaseHelper.columnLatitude];
                  final lon = item[DatabaseHelper.columnLongitude];
                  final isSync = (item[DatabaseHelper.columnStatusSync] as int? ?? 0) == 1;

                  final isMasuk = tipe.toLowerCase() == 'masuk';

                  final lokasiText = keterangan.isNotEmpty
                      ? keterangan
                      : (lat != null && lon != null
                          ? 'Koordinat: $lat, $lon'
                          : 'Lokasi tercatat saat presensi');

                  return Card(
                    elevation: 1.5,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      onTap: () => _showDetailAbsensiDialog(item),
                      leading: CircleAvatar(
                        backgroundColor: isMasuk ? Colors.green.shade100 : Colors.orange.shade100,
                        child: Icon(
                          isMasuk ? Icons.arrow_downward : Icons.arrow_upward,
                          color: isMasuk ? Colors.green : Colors.orange,
                        ),
                      ),
                      title: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Absen $tipe',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          // Badge Sinkronisasi (Sudah Sync vs Belum Sync)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSync ? Colors.green.shade100 : Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isSync ? 'Sudah Sync' : 'Lokal (Belum Sync)',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isSync ? Colors.green.shade800 : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text(
                            '$tanggal • $waktu WIB',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blue.withValues(alpha: 0.18)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.location_on, size: 14, color: Colors.redAccent),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    lokasiText,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'Hapus data',
                        onPressed: () => _hapusAbsensi(id),
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
              const Icon(Icons.location_on, size: 20, color: Colors.redAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Lokasi Presensi & Peta',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  minimumSize: Size.zero,
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
                icon: const Icon(Icons.fullscreen, size: 18),
                label: const Text(
                  'Layar Penuh',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Kartu Peta
          Card(
            elevation: 2,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Box Peta Interaktif (Google Maps Asli)
                SizedBox(
                  height: 190,
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
                              color: Colors.black.withValues(alpha: 0.7),
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
                                  style: TextStyle(color: Colors.white, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Tombol GPS Refresh Melayang di Pojok Kanan Atas
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Material(
                          color: Colors.white,
                          shape: const CircleBorder(),
                          elevation: 3,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _getHomeLocation,
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.my_location, size: 20, color: Colors.blueAccent),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Informasi Alamat & Tombol Aksi di Bawah Peta
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.place_outlined, size: 18, color: Colors.redAccent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _homeCurrentAddress,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Tag Koordinat
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              lat != null
                                  ? 'Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng!.toStringAsFixed(5)}'
                                  : 'Koordinat: Default (-6.2000, 106.8166)',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.blueAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Tombol Aksi di Bagian Bawah
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _getHomeLocation,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Update GPS', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                          /*
                          // COMENT YANG LAUNCHER
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _openInExternalMaps,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('Buka Maps', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                          */
                        ],
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
}
