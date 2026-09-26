import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:absensiku/database/db_helper.dart';
import 'package:absensiku/services/api_services.dart';
import 'package:absensiku/services/network_helper.dart';
import 'package:absensiku/services/notification_helper.dart';
import 'package:absensiku/services/pref_helper.dart';
import 'package:absensiku/views/auth/login_screen.dart';
import 'package:absensiku/views/auth/register_screen.dart';
import 'package:absensiku/views/users/settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _userName = '';
  String _userEmail = '';
  String? _userPhone;
  String? _userAlamat;
  String? _userPhotoPath;
  int? _userId;

  int _totalAbsensi = 0;
  int _totalMasuk = 0;
  int _totalPulang = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData({bool syncApi = true}) async {
    try {
      // 1. Baca data dari SharedPreferences dan SQLite
      final name = await PrefHelper.getUserName();
      final email = await PrefHelper.getUserEmail();
      final phone = await PrefHelper.getUserPhone();
      final alamat = await PrefHelper.getUserAlamat();
      final photo = await PrefHelper.getUserPhoto();
      final id = await PrefHelper.getUserId();

      List<Map<String, dynamic>> allAbsensi = [];
      try {
        allAbsensi = await DatabaseHelper.instance.getAllAbsensi();
      } catch (_) {}

      final masukCount = allAbsensi.where((item) {
        final t = (item[DatabaseHelper.columnTipe] as String? ?? '').toLowerCase();
        return t == 'masuk' || t.contains('in');
      }).length;
      final pulangCount = allAbsensi.where((item) {
        final t = (item[DatabaseHelper.columnTipe] as String? ?? '').toLowerCase();
        return t == 'pulang' || t == 'keluar' || t.contains('out');
      }).length;

      if (!mounted) return;
      setState(() {
        _userName = name;
        _userEmail = email ?? 'Belum ada email';
        _userPhone = phone;
        _userAlamat = alamat;
        _userPhotoPath = photo;
        _userId = id;
        _totalAbsensi = allAbsensi.length;
        _totalMasuk = masukCount;
        _totalPulang = pulangCount;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }

    // 2. Sinkronkan profil terbaru dari API Server jika dipanggil
    if (syncApi) {
      try {
        final apiData = await AppApiService.getProfileFromApi();
        if (apiData != null && mounted) {
          final updatedName = await PrefHelper.getUserName();
          final updatedEmail = await PrefHelper.getUserEmail();
          setState(() {
            _userName = updatedName;
            _userEmail = updatedEmail ?? 'Belum ada email';
          });
        }
      } catch (_) {}
    }
  }

  // Pilih foto dari Kamera atau Galeri
  Future<void> _pickImage(ImageSource source, {StateSetter? modalSetState}) async {
    final isOnline = await NetworkHelper.hasInternetConnection();
    if (!isOnline) {
      if (mounted) {
        NetworkHelper.showOfflineDialog(context, featureName: 'Ubah Foto Profil');
      }
      return;
    }

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (picked != null) {
        final path = picked.path;
        await PrefHelper.setUserPhoto(path);

        if (_userId != null) {
          await DatabaseHelper.instance.updateUser(
            id: _userId!,
            nama: _userName,
            email: _userEmail,
            foto: path,
          );
        }

        // 3. Unggah foto profil ke Server API
        try {
          await AppApiService.uploadProfilePhotoToApi(path);
        } catch (_) {}

        if (!mounted) return;
        setState(() {
          _userPhotoPath = path;
        });
        if (modalSetState != null) {
          modalSetState(() {});
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto profil berhasil diperbarui & tersinkron ke API!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memilih foto: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Hapus foto profil dan kembalikan ke avatar inisial
  Future<void> _hapusFotoProfil({StateSetter? modalSetState}) async {
    final isOnline = await NetworkHelper.hasInternetConnection();
    if (!mounted) return;
    if (!isOnline) {
      NetworkHelper.showOfflineDialog(context, featureName: 'Hapus Foto Profil');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text('Hapus Foto Profil?')),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text('Foto profil akan dihapus dan diganti dengan inisial nama Anda.'),
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
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Hapus Foto', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await PrefHelper.setUserPhoto(null);
    if (_userId != null) {
      await DatabaseHelper.instance.updateUser(
        id: _userId!,
        nama: _userName,
        email: _userEmail,
        foto: '',
      );
    }

    if (!mounted) return;
    setState(() {
      _userPhotoPath = null;
    });
    if (modalSetState != null) {
      modalSetState(() {});
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Foto profil berhasil dihapus.'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Helper untuk memuat gambar profil baik dari path lokal maupun URL remote API
  ImageProvider? _getProfileImageProvider(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return NetworkImage(path);
    }
    final file = File(path);
    if (file.existsSync()) {
      return FileImage(file);
    }
    return null;
  }

  // Menampilkan Dialog Detail Foto Profil (Fullscreen / Zoom / Pinch)
  void _showPhotoDetailDialog() {
    final hasPhoto = _userPhotoPath != null &&
        _userPhotoPath!.isNotEmpty &&
        (_userPhotoPath!.startsWith('http://') ||
            _userPhotoPath!.startsWith('https://') ||
            File(_userPhotoPath!).existsSync());

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: Judul, Nama, dan Tombol Tutup
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade900.withValues(alpha: 0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_pin, color: Colors.blueAccent, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Detail Foto Profil',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _userName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),

            // Container Foto Detail dengan InteractiveViewer (Zoom & Pan)
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.60,
                maxWidth: double.infinity,
              ),
              color: Colors.black,
              child: Center(
                child: hasPhoto
                    ? InteractiveViewer(
                        panEnabled: true,
                        boundaryMargin: const EdgeInsets.all(20),
                        minScale: 0.8,
                        maxScale: 4.0,
                        child: _userPhotoPath!.startsWith('http://') ||
                                _userPhotoPath!.startsWith('https://')
                            ? Image.network(
                                _userPhotoPath!,
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(
                                    child: CircularProgressIndicator(color: Colors.white),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildFallbackAvatar(),
                              )
                            : Image.file(
                                File(_userPhotoPath!),
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildFallbackAvatar(),
                              ),
                      )
                    : _buildFallbackAvatar(),
              ),
            ),

            // Footer Toolbar: Action Buttons (Ubah Foto, Hapus, Tutup)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900.withValues(alpha: 0.95),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showImagePickerOptions();
                      },
                      icon: const Icon(Icons.camera_alt, size: 18),
                      label: Text(hasPhoto ? 'Ubah Foto' : 'Pasang Foto'),
                    ),
                  ),
                  if (hasPhoto) ...[
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _hapusFotoProfil();
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Hapus'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackAvatar() {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: Colors.blueAccent,
            child: Text(
              _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
              style: const TextStyle(
                fontSize: 54,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Belum ada foto profil terpasang',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // Dialog / BottomSheet Pusat Notifikasi & Status
  void _showNotificationCenterBottomSheet() async {
    final isOnline = await NetworkHelper.hasInternetConnection();
    final today =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
    final allAbsensi = await DatabaseHelper.instance.getAllAbsensi(userId: _userId);
    final unsynced = await DatabaseHelper.instance.getUnsyncedAbsensi();

    final masukHariIni = await DatabaseHelper.instance.getAbsensiHariIni(
      tanggal: today,
      tipe: 'Masuk',
      userId: _userId,
    );
    final pulangHariIni = await DatabaseHelper.instance.getAbsensiHariIni(
      tanggal: today,
      tipe: 'Keluar',
      userId: _userId,
    );

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle Bar
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_active, color: Colors.blueAccent, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pusat Notifikasi & Status',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Text(
                            'Status koneksi, sinkronisasi, dan presensi akun',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 1. Kartu Status Jaringan Internet
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isOnline ? Colors.green.shade200 : Colors.red.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOnline ? Icons.wifi : Icons.wifi_off,
                        color: isOnline ? Colors.green.shade700 : Colors.red.shade700,
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOnline ? 'Jaringan Online (Aktif)' : 'Mode Offline (Terputus)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: isOnline ? Colors.green.shade900 : Colors.red.shade900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isOnline
                                  ? 'Profil & data terhubung ke server API'
                                  : 'Perubahan tersimpan di database lokal',
                              style: TextStyle(
                                fontSize: 12,
                                color: isOnline ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isOnline ? 'ONLINE' : 'OFFLINE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2. Kartu Status Presensi Hari Ini
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.today, size: 18, color: Colors.blueAccent),
                          const SizedBox(width: 8),
                          Text(
                            'Status Kehadiran Hari Ini ($today)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  masukHariIni != null ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: masukHariIni != null ? Colors.green : Colors.grey,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    masukHariIni != null
                                        ? 'Masuk: ${masukHariIni['waktu']} WIB'
                                        : 'Masuk: Belum',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: masukHariIni != null ? FontWeight.bold : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  pulangHariIni != null ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: pulangHariIni != null ? Colors.orange.shade800 : Colors.grey,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    pulangHariIni != null
                                        ? 'Keluar: ${pulangHariIni['waktu']} WIB'
                                        : 'Keluar: Belum',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: pulangHariIni != null ? FontWeight.bold : FontWeight.normal,
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
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 3. Kartu Sinkronisasi
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_sync, color: Colors.blueAccent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          unsynced.isEmpty
                              ? 'Total ${allAbsensi.length} data presensi telah tersimpan aman.'
                              : '${unsynced.length} data sedang menunggu antrean sinkronisasi.',
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Tombol Aksi: Uji Notifikasi
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          AppNotificationHelper.showNotification(
                            title: 'Uji Notifikasi Profil',
                            message: 'Layanan notifikasi perangkat & bilah status berjalan lancar!',
                            icon: Icons.notifications_active_rounded,
                            backgroundColor: const Color(0xFF1E293B),
                            iconColor: Colors.amberAccent,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Notifikasi uji berhasil dikirim!')),
                          );
                        },
                        icon: const Icon(Icons.notifications_active_outlined, size: 18),
                        label: const Text('Uji Notifikasi'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const SettingsScreen()),
                          ).then((_) => _loadProfileData());
                        },
                        icon: const Icon(Icons.settings, size: 18),
                        label: const Text('Pengaturan'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Dialog / BottomSheet Pemilihan Sumber Foto (Kamera / Galeri / Hapus)
  void _showImagePickerOptions({StateSetter? modalSetState}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Pilih Foto Profil',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blueAccent,
                  child: Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: const Text('Ambil Foto dari Kamera'),
                subtitle: const Text('Gunakan kamera perangkat secara langsung'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera, modalSetState: modalSetState);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.purpleAccent,
                  child: Icon(Icons.photo_library, color: Colors.white),
                ),
                title: const Text('Pilih dari Galeri Foto'),
                subtitle: const Text('Pilih gambar tersimpan di galeri HP'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery, modalSetState: modalSetState);
                },
              ),
              if (_userPhotoPath != null && _userPhotoPath!.isNotEmpty)
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.redAccent,
                    child: Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  title: const Text('Hapus Foto Profil'),
                  subtitle: const Text('Kembalikan ke avatar inisial default'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _hapusFotoProfil(modalSetState: modalSetState);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Batal')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
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

  // BOTTOM SHEET EDIT SEMUA FORM DAN FOTO PROFIL
  Future<void> _showEditProfileBottomSheet() async {
    final isOnline = await NetworkHelper.hasInternetConnection();
    if (!mounted) return;
    if (!isOnline) {
      NetworkHelper.showOfflineDialog(context, featureName: 'Ubah Data Profil');
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: _userName);
    final emailController = TextEditingController(
      text: _userEmail == 'Belum ada email' ? '' : _userEmail,
    );
    final phoneController = TextEditingController(text: _userPhone ?? '');
    final alamatController = TextEditingController(text: _userAlamat ?? '');
    bool isSaving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final hasPhoto = _userPhotoPath != null &&
                _userPhotoPath!.isNotEmpty &&
                File(_userPhotoPath!).existsSync();

            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 24,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.manage_accounts, color: Colors.blueAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Edit Formulir & Foto Profil',
                              style: Theme.of(modalContext).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // EDIT FOTO PROFIL PREVIEW & BUTTON
                      Center(
                        child: Column(
                          children: [
                            Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                CircleAvatar(
                                  radius: 46,
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  backgroundImage: _getProfileImageProvider(_userPhotoPath),
                                  child: !hasPhoto
                                      ? Text(
                                          _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                                          style: const TextStyle(
                                            fontSize: 38,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        )
                                      : null,
                                ),
                                InkWell(
                                  onTap: () => _showImagePickerOptions(modalSetState: setModalState),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: Colors.blueAccent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _showImagePickerOptions(modalSetState: setModalState),
                                  icon: const Icon(Icons.add_a_photo, size: 15),
                                  label: Text(hasPhoto ? 'Ganti Foto' : 'Pilih Foto'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  ),
                                ),
                                if (hasPhoto)
                                  TextButton.icon(
                                    onPressed: () => _hapusFotoProfil(modalSetState: setModalState),
                                    icon: const Icon(Icons.delete_outline, size: 15, color: Colors.red),
                                    label: const Text('Hapus Foto', style: TextStyle(color: Colors.red, fontSize: 13)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 1. FORM NAMA LENGKAP
                      TextFormField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Nama Lengkap',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Nama tidak boleh kosong';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // 2. FORM EMAIL
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email Akun',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Email tidak boleh kosong';
                          }
                          if (!val.contains('@') || !val.contains('.')) {
                            return 'Format email tidak valid';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // 3. FORM NO TELEPON / WHATSAPP
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'No. Telepon / WhatsApp',
                          hintText: 'Contoh: 081234567890',
                          prefixIcon: const Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 4. FORM ALAMAT / DOMISILI / PENEMPATAN
                      TextFormField(
                        controller: alamatController,
                        keyboardType: TextInputType.streetAddress,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Alamat / Domisili / Lokasi Penempatan',
                          hintText: 'Masukkan alamat atau lokasi kantor penempatan',
                          prefixIcon: const Icon(Icons.location_on_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ACTION BUTTONS (BATAL & SIMPAN DENGAN EXPANDED)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving ? null : () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Batal')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate()) return;

                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          title: const Row(
                                            children: [
                                              Icon(Icons.edit_note, color: Colors.blueAccent),
                                              SizedBox(width: 8),
                                              Expanded(child: Text('Simpan Perubahan?')),
                                            ],
                                          ),
                                          content: const SingleChildScrollView(
                                            child: Text(
                                              'Apakah Anda yakin ingin memperbarui data profil akun dan foto Anda?',
                                            ),
                                          ),
                                          actions: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: OutlinedButton(
                                                    onPressed: () => Navigator.pop(c, false),
                                                    child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Batal')),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: ElevatedButton(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.blueAccent,
                                                      foregroundColor: Colors.white,
                                                    ),
                                                    onPressed: () => Navigator.pop(c, true),
                                                    child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Simpan')),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirm != true) return;

                                      setModalState(() => isSaving = true);

                                      final newName = nameController.text.trim();
                                      final newEmail = emailController.text.trim();
                                      final newPhone = phoneController.text.trim();
                                      final newAlamat = alamatController.text.trim();

                                      // 1. Simpan ke SharedPreferences
                                      await PrefHelper.updateUserProfile(
                                        name: newName,
                                        email: newEmail,
                                        phone: newPhone,
                                        alamat: newAlamat,
                                        photoPath: _userPhotoPath,
                                      );

                                      // 2. Simpan ke SQLite Database secara aman tanpa collision UNIQUE
                                      try {
                                        await DatabaseHelper.instance.updateUserProfileSafe(
                                          id: _userId,
                                          oldEmail: _userEmail,
                                          nama: newName,
                                          newEmail: newEmail,
                                          phone: newPhone,
                                          alamat: newAlamat,
                                          foto: _userPhotoPath,
                                        );
                                      } catch (dbError) {
                                        debugPrint('Error updating SQLite user profile: $dbError');
                                      }

                                      // 3. Otomatis perbarui data profil & foto ke API Server
                                      try {
                                        await AppApiService.updateProfileToApi(
                                          name: newName,
                                          email: newEmail,
                                          photoPath: _userPhotoPath,
                                        );
                                      } catch (_) {}

                                      if (ctx.mounted) {
                                        Navigator.pop(ctx);
                                      }

                                      // Perbarui state secara langsung agar UI langsung responsif
                                      if (mounted) {
                                        setState(() {
                                          _userName = newName;
                                          _userEmail = newEmail;
                                          _userPhone = newPhone;
                                          _userAlamat = newAlamat;
                                        });
                                      }

                                      await _loadProfileData(syncApi: false);

                                      if (!mounted) return;
                                      showDialog(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          title: const Row(
                                            children: [
                                              Icon(
                                                Icons.check_circle,
                                                color: Colors.green,
                                              ),
                                              SizedBox(width: 8),
                                              Expanded(
                                                child: Text('Profil Berhasil Diperbarui'),
                                              ),
                                            ],
                                          ),
                                          content: const SingleChildScrollView(
                                            child: Text('Data profil pengguna berhasil tersimpan.'),
                                          ),
                                          actions: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: ElevatedButton(
                                                    onPressed: () => Navigator.pop(c),
                                                    child: const Text('OK'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Simpan', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _userPhotoPath != null &&
        _userPhotoPath!.isNotEmpty &&
        File(_userPhotoPath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Pengguna'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Pusat Notifikasi & Status',
            onPressed: _showNotificationCenterBottomSheet,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Pengaturan & Cloud',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              ).then((_) => _loadProfileData());
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Formulir Profil',
            onPressed: _showEditProfileBottomSheet,
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt),
            tooltip: 'Tambah Akun di Register',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RegisterScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Segarkan Profil',
            onPressed: _loadProfileData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadProfileData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  children: [
                    // 1. Header Avatar, Nama, dan Tombol Ubah Foto Langsung
                    Center(
                      child: Column(
                        children: [
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              GestureDetector(
                                onTap: _showPhotoDetailDialog,
                                child: CircleAvatar(
                                  radius: 50,
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  backgroundImage: _getProfileImageProvider(_userPhotoPath),
                                  child: !hasPhoto
                                      ? Text(
                                          _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                                          style: const TextStyle(
                                            fontSize: 42,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              // Tombol badge kamera untuk edit foto langsung
                              GestureDetector(
                                onTap: _showImagePickerOptions,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _userName,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _userEmail,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _userId != null ? 'User ID: #$_userId' : 'User Session Aktif',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueAccent,
                                  ),
                                ),
                              ),
                              if (hasPhoto)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle, size: 12, color: Colors.green),
                                      SizedBox(width: 4),
                                      Text(
                                        'Foto Ada',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _showEditProfileBottomSheet,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                icon: const Icon(Icons.edit, size: 15),
                                label: const Text('Edit Formulir & Foto'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _showImagePickerOptions,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                icon: const Icon(Icons.add_a_photo, size: 15),
                                label: const Text('Ganti Foto'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Mini Statistik Kehadiran Pengguna
                          Row(
                            children: [
                              _buildStatBox('Total Absen', '$_totalAbsensi', Icons.list_alt, Colors.blueAccent),
                              const SizedBox(width: 8),
                              _buildStatBox('Masuk', '$_totalMasuk', Icons.login, Colors.green),
                              const SizedBox(width: 8),
                              _buildStatBox('Pulang', '$_totalPulang', Icons.logout, Colors.orange),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),

                    // 2. KARTU RINCIAN AKUN & FORMULIR
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: _buildSectionTitle('Informasi Formulir Akun')),
                        TextButton.icon(
                          onPressed: _showEditProfileBottomSheet,
                          icon: const Icon(Icons.edit, size: 14),
                          label: const Text('Ubah Semua', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                    Card(
                      elevation: 1.5,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        children: [
                          // Foto Profil status
                          ListTile(
                            leading: GestureDetector(
                              onTap: _showPhotoDetailDialog,
                              child: CircleAvatar(
                                radius: 20,
                                backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                                backgroundImage: _getProfileImageProvider(_userPhotoPath),
                                child: !hasPhoto
                                    ? const Icon(Icons.person, color: Colors.blueAccent, size: 20)
                                    : null,
                              ),
                            ),
                            title: const Text('Foto Profil'),
                            subtitle: Text(
                              hasPhoto ? 'Ketuk untuk lihat foto detail' : 'Belum memasang foto profil',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasPhoto)
                                  IconButton(
                                    icon: const Icon(Icons.fullscreen, color: Colors.blueAccent),
                                    tooltip: 'Lihat Detail Foto',
                                    onPressed: _showPhotoDetailDialog,
                                  ),
                                TextButton(
                                  onPressed: _showImagePickerOptions,
                                  child: Text(hasPhoto ? 'Ganti' : 'Pasang'),
                                ),
                              ],
                            ),
                            onTap: hasPhoto ? _showPhotoDetailDialog : _showImagePickerOptions,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.badge_outlined, color: Colors.blueAccent),
                            title: const Text('Nama Lengkap'),
                            subtitle: Text(_userName.isNotEmpty ? _userName : 'Belum diisi'),
                            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                            onTap: _showEditProfileBottomSheet,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.email_outlined, color: Colors.blueAccent),
                            title: const Text('Email Terdaftar'),
                            subtitle: Text(_userEmail.isNotEmpty ? _userEmail : 'Belum diisi'),
                            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                            onTap: _showEditProfileBottomSheet,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.phone_outlined, color: Colors.green),
                            title: const Text('No. Telepon / WhatsApp'),
                            subtitle: Text(
                              _userPhone != null && _userPhone!.isNotEmpty
                                  ? _userPhone!
                                  : 'Belum diisi (Ketuk untuk menambah)',
                            ),
                            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                            onTap: _showEditProfileBottomSheet,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.location_on_outlined, color: Colors.deepOrange),
                            title: const Text('Alamat / Lokasi Domisili'),
                            subtitle: Text(
                              _userAlamat != null && _userAlamat!.isNotEmpty
                                  ? _userAlamat!
                                  : 'Belum diisi (Ketuk untuk menambah)',
                            ),
                            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                            onTap: _showEditProfileBottomSheet,
                          ),
                          const Divider(height: 1),
                          const ListTile(
                            leading: Icon(Icons.verified_user_outlined, color: Colors.green),
                            title: Text('Status Akun'),
                            subtitle: Text('Aktif & Tersinkron'),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 3. KARTU CATATAN RESMI ABSENSI (KECUALI ABSEN)
                    Card(
                      color: Colors.amber.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.amber.shade300),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.lock_clock, color: Colors.amber, size: 22),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Ketentuan Data Absensi (Presensi)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.brown,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Semua formulir profil & foto profil dapat diedit sewaktu-waktu. '
                                    'Namun catatan log presensi kehadiran terkunci otomatis dan tidak dapat diubah (hanya dapat dilihat atau dihapus).',
                                    style: TextStyle(fontSize: 12, color: Colors.brown),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 4. KARTU PENGATURAN & APLIKASI
                    _buildSectionTitle('Aplikasi & Sistem'),
                    Card(
                      elevation: 1.5,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.cloud_sync_outlined, color: Colors.blueAccent),
                            title: const Text('Pengaturan & Cloud Storage'),
                            subtitle: const Text('Kelola sinkronisasi awan otomatis & preferensi'),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const SettingsScreen()),
                              ).then((_) => _loadProfileData());
                            },
                          ),
                          const Divider(height: 1),
                          const ListTile(
                            leading: Icon(Icons.storage_outlined, color: Colors.teal),
                            title: Text('Penyimpanan Data'),
                            subtitle: Text('SQLite Lokal & Server Awan (Tersinkron)'),
                          ),
                          const Divider(height: 1),
                          const ListTile(
                            leading: Icon(Icons.cloud_done_outlined, color: Colors.blueAccent),
                            title: Text('API Server Backend'),
                            subtitle: Text('https://absensib1.mobileprojp.com'),
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
                            title: const Text('Versi Aplikasi'),
                            subtitle: const Text('Absensiku v1.0.0+1'),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 5. KARTU KELOLA AKUN (TAMBAH AKUN DI REGISTER)
                    _buildSectionTitle('Kelola & Pendaftaran Akun'),
                    Card(
                      elevation: 1.5,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.blueAccent,
                              child: Icon(Icons.person_add_alt_1, color: Colors.white, size: 20),
                            ),
                            title: const Text(
                              'Tambah Akun di Register',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Daftarkan akun pengguna baru ke dalam aplikasi',
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const RegisterScreen()),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 6. TOMBOL LOGOUT BESAR
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _logout,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade50,
                          foregroundColor: Colors.red,
                          elevation: 0,
                          side: BorderSide(color: Colors.red.shade200),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.logout, color: Colors.red),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Keluar dari Akun (Logout)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildStatBox(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
