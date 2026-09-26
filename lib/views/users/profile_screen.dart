import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:absensiku/database/db_helper.dart';
import 'package:absensiku/services/api_services.dart';
import 'package:absensiku/services/pref_helper.dart';
import 'package:absensiku/views/auth/login_screen.dart';

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

        if (!mounted) return;
        setState(() {
          _userPhotoPath = path;
        });
        if (modalSetState != null) {
          modalSetState(() {});
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto profil berhasil diperbarui!'),
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
          child: Text('Apakah Anda yakin ingin keluar dari akun? Session akan dihapus.'),
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
                                  backgroundImage: hasPhoto ? FileImage(File(_userPhotoPath!)) : null,
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

                                      // 2. Simpan ke SQLite Database
                                      try {
                                        if (_userId != null) {
                                          await DatabaseHelper.instance.updateUser(
                                            id: _userId!,
                                            nama: newName,
                                            email: newEmail,
                                            phone: newPhone,
                                            alamat: newAlamat,
                                            foto: _userPhotoPath,
                                          );
                                        } else {
                                          await DatabaseHelper.instance.updateUserByEmail(
                                            oldEmail: _userEmail,
                                            nama: newName,
                                            newEmail: newEmail,
                                            phone: newPhone,
                                            alamat: newAlamat,
                                            foto: _userPhotoPath,
                                          );
                                        }
                                      } catch (dbError) {
                                        debugPrint('Error updating SQLite user profile: $dbError');
                                      }

                                      // 3. Otomatis perbarui data profil ke API Server (PUT /api/profile)
                                      UpdateProfileResult apiResult = UpdateProfileResult(
                                        success: false,
                                        message: 'Belum terhubung ke server',
                                      );
                                      try {
                                        apiResult = await AppApiService.updateProfileToApi(
                                          name: newName,
                                          email: newEmail,
                                        );
                                      } catch (e) {
                                        apiResult = UpdateProfileResult(
                                          success: false,
                                          message: e.toString(),
                                        );
                                      }

                                      if (ctx.mounted) {
                                        Navigator.pop(ctx);
                                      }

                                      await _loadProfileData();

                                      if (!mounted) return;
                                      showDialog(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          title: Row(
                                            children: [
                                              Icon(
                                                apiResult.success ? Icons.check_circle : Icons.info_outline,
                                                color: apiResult.success ? Colors.green : Colors.orange,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  apiResult.success
                                                      ? 'Profil Berhasil Diperbarui'
                                                      : 'Profil Tersimpan Lokal',
                                                ),
                                              ),
                                            ],
                                          ),
                                          content: SingleChildScrollView(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Text(
                                                  'Data profil pengguna telah diproses:',
                                                  style: TextStyle(fontWeight: FontWeight.w600),
                                                ),
                                                const SizedBox(height: 10),
                                                const Text('• Database Lokal (SQLite): Tersimpan'),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '• Server Backend API: '
                                                  '${apiResult.success ? "Berhasil Diperbarui (PUT /api/profile)" : "Tertunda / Gagal"}',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: apiResult.success ? Colors.green.shade800 : Colors.orange.shade900,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: apiResult.success
                                                        ? Colors.green.shade50
                                                        : Colors.orange.shade50,
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: apiResult.success
                                                          ? Colors.green.shade200
                                                          : Colors.orange.shade200,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    apiResult.message,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: apiResult.success
                                                          ? Colors.green.shade900
                                                          : Colors.orange.shade900,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
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
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Formulir Profil',
            onPressed: _showEditProfileBottomSheet,
          ),
          IconButton(
            icon: const Icon(Icons.cloud_sync),
            tooltip: 'Sinkronisasi Profil ke API',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Menghubungkan ke API server untuk sinkronisasi profil...'),
                  duration: Duration(seconds: 1),
                ),
              );
              final apiData = await AppApiService.getProfileFromApi();
              await _loadProfileData();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(apiData != null
                      ? 'Profil berhasil disinkronkan dengan API Server!'
                      : 'API Server offline / tidak dapat dihubungi. Data dimuat dari lokal.'),
                  backgroundColor: apiData != null ? Colors.green : Colors.orange,
                  behavior: SnackBarBehavior.floating,
                ),
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
                                onTap: _showImagePickerOptions,
                                child: CircleAvatar(
                                  radius: 50,
                                  backgroundColor: Theme.of(context).colorScheme.primary,
                                  backgroundImage: hasPhoto ? FileImage(File(_userPhotoPath!)) : null,
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
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _userEmail,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
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
                              if (hasPhoto) ...[
                                const SizedBox(width: 6),
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
                        _buildSectionTitle('Informasi Formulir Akun'),
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
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.blueAccent.withValues(alpha: 0.15),
                              backgroundImage: hasPhoto ? FileImage(File(_userPhotoPath!)) : null,
                              child: !hasPhoto
                                  ? const Icon(Icons.person, color: Colors.blueAccent, size: 20)
                                  : null,
                            ),
                            title: const Text('Foto Profil'),
                            subtitle: Text(
                              hasPhoto ? 'Foto kustom terpasang' : 'Belum memasang foto profil',
                            ),
                            trailing: TextButton(
                              onPressed: _showImagePickerOptions,
                              child: Text(hasPhoto ? 'Ganti' : 'Pasang'),
                            ),
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
                            title: Text('Status Data'),
                            subtitle: Text('Tersinkron di SQLite & SharedPreferences'),
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
                          const ListTile(
                            leading: Icon(Icons.storage_outlined, color: Colors.blueAccent),
                            title: Text('Database Lokal'),
                            subtitle: Text('SQLite (absensiku.db v4) Aktif'),
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

                    // 5. TOMBOL LOGOUT BESAR
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
                        label: const Text(
                          'Keluar dari Akun (Logout)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
