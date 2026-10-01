import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PrefHelper {
  static const String _keyToken = 'auth_token';
  static const String _keyUserId = 'user_id';
  static const String _keyUserName = 'user_name';
  static const String _keyUserEmail = 'user_email';
  static const String _keyIsLoggedIn = 'is_logged_in';

  static const String _keyUserCustomEmail = 'user_custom_email';

  // Simpan data login / session dengan proteksi & isolasi profil per akun pengguna
  static Future<void> saveSession({
    required String token,
    int? userId,
    required String name,
    required String email,
    String? phone,
    String? alamat,
    String? photoPath,
    String? role,
    bool forceEmailOverwrite = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    if (userId != null) {
      await prefs.setInt(_keyUserId, userId);
    } else {
      await prefs.remove(_keyUserId);
    }
    await prefs.setString(_keyUserName, name);

    final cleanEmail = email.trim();
    final customEmail = prefs.getString(_keyUserCustomEmail);
    final previousEmail = prefs.getString(_keyUserEmail);
    final isDifferentUser = previousEmail != null &&
        previousEmail.isNotEmpty &&
        previousEmail.toLowerCase() != cleanEmail.toLowerCase();

    if (forceEmailOverwrite || isDifferentUser) {
      if (cleanEmail.isNotEmpty) {
        await prefs.setString(_keyUserEmail, cleanEmail);
        await prefs.setString(_keyUserCustomEmail, cleanEmail);
      }
    } else {
      // Pertahankan email kustom pengguna jika ada, jangan timpa dengan default production API
      if (customEmail != null && customEmail.isNotEmpty) {
        await prefs.setString(_keyUserEmail, customEmail);
      } else if (cleanEmail.isNotEmpty) {
        await prefs.setString(_keyUserEmail, cleanEmail);
        await prefs.setString(_keyUserCustomEmail, cleanEmail);
      } else if (previousEmail == null || previousEmail.isEmpty) {
        await prefs.setString(_keyUserEmail, cleanEmail);
      }
    }

    // Isolasi Profil: Phone, Alamat, Foto hanya milik akun yang sedang login
    if (phone != null && phone.isNotEmpty) {
      await prefs.setString(_keyUserPhone, phone);
    } else {
      await prefs.remove(_keyUserPhone);
    }

    if (alamat != null && alamat.isNotEmpty) {
      await prefs.setString(_keyUserAlamat, alamat);
    } else {
      await prefs.remove(_keyUserAlamat);
    }

    if (photoPath != null && photoPath.isNotEmpty) {
      await prefs.setString(_keyUserPhoto, photoPath);
    } else {
      await prefs.remove(_keyUserPhoto);
    }

    // Simpan ke cache scoped per email
    if (cleanEmail.isNotEmpty) {
      final safeKey = cleanEmail.toLowerCase();
      await prefs.setString('user_name_$safeKey', name);
      if (phone != null && phone.isNotEmpty) {
        await prefs.setString('user_phone_$safeKey', phone);
      } else {
        await prefs.remove('user_phone_$safeKey');
      }
      if (alamat != null && alamat.isNotEmpty) {
        await prefs.setString('user_alamat_$safeKey', alamat);
      } else {
        await prefs.remove('user_alamat_$safeKey');
      }
      if (photoPath != null && photoPath.isNotEmpty) {
        await prefs.setString('user_photo_$safeKey', photoPath);
      } else {
        await prefs.remove('user_photo_$safeKey');
      }
    }

    // Simpan Role Pengguna ('admin' / 'user')
    if (role != null && role.isNotEmpty) {
      await prefs.setString(_keyUserRole, role.toLowerCase().trim());
    } else if (cleanEmail.toLowerCase().contains('admin') || name.toLowerCase().contains('admin')) {
      await prefs.setString(_keyUserRole, 'admin');
    } else {
      await prefs.setString(_keyUserRole, 'user');
    }

    await prefs.setBool(_keyIsLoggedIn, true);
  }

  // Ambil Token
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  // Ambil Nama Pengguna
  static Future<String> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserName) ?? 'Pengguna';
  }

  // Simpan / Perbarui Nama Pengguna
  static Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserName, name.trim());
  }

  // Ambil Email Pengguna (memprioritaskan email pengguna yang disimpan)
  static Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_keyUserCustomEmail);
    if (custom != null && custom.isNotEmpty) return custom;
    return prefs.getString(_keyUserEmail);
  }

  // Simpan / Perbarui Email Pengguna secara permanen
  static Future<void> setUserEmail(String email) async {
    final clean = email.trim();
    if (clean.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserEmail, clean);
    await prefs.setString(_keyUserCustomEmail, clean);
  }

  // Ambil User ID
  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyUserId);
  }

  // Cek apakah user sedang login
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyToken);
    final isLogged = prefs.getBool(_keyIsLoggedIn) ?? false;
    return isLogged && token != null && token.isNotEmpty;
  }

  static const String _keyUserRole = 'user_role';

  // Simpan / Perbarui Role Pengguna ('admin' / 'user')
  static Future<void> setUserRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserRole, role.toLowerCase().trim());
  }

  // Ambil Role Pengguna ('admin' / 'user')
  static Future<String> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString(_keyUserRole);
    if (role != null && role.isNotEmpty) return role.toLowerCase().trim();
    final email = await getUserEmail();
    if (email != null && email.toLowerCase().contains('admin')) return 'admin';
    final name = await getUserName();
    if (name.toLowerCase().contains('admin')) return 'admin';
    return 'user';
  }

  // Cek apakah akun yang sedang aktif adalah Administrator
  static Future<bool> isAdmin() async {
    final role = await getUserRole();
    return role == 'admin';
  }

  static const String _keyUserPhone = 'user_phone';
  static const String _keyUserAlamat = 'user_alamat';
  static const String _keyUserPhoto = 'user_photo';

  // Ambil Foto Profil Pengguna (Path File Lokal)
  static Future<String?> getUserPhoto() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserPhoto);
  }

  // Simpan / Perbarui Foto Profil
  static Future<void> setUserPhoto(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_keyUserPhoto);
    } else {
      await prefs.setString(_keyUserPhoto, path);
    }
  }

  // Ambil Nomor Telepon Pengguna
  static Future<String?> getUserPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserPhone);
  }

  // Simpan Nomor Telepon Pengguna
  static Future<void> setUserPhone(String? phone) async {
    final prefs = await SharedPreferences.getInstance();
    if (phone == null || phone.isEmpty) {
      await prefs.remove(_keyUserPhone);
    } else {
      await prefs.setString(_keyUserPhone, phone);
    }
  }

  // Ambil Alamat Pengguna
  static Future<String?> getUserAlamat() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserAlamat);
  }

  // Simpan Alamat Pengguna
  static Future<void> setUserAlamat(String? alamat) async {
    final prefs = await SharedPreferences.getInstance();
    if (alamat == null || alamat.isEmpty) {
      await prefs.remove(_keyUserAlamat);
    } else {
      await prefs.setString(_keyUserAlamat, alamat);
    }
  }

  // Perbarui profil pengguna (Nama, Email, Phone, Alamat, Foto) di SharedPreferences
  static Future<void> updateUserProfile({
    required String name,
    required String email,
    String? phone,
    String? alamat,
    String? photoPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserName, name);
    final cleanEmail = email.trim();
    if (cleanEmail.isNotEmpty) {
      await prefs.setString(_keyUserEmail, cleanEmail);
      await prefs.setString(_keyUserCustomEmail, cleanEmail);
    }
    if (phone != null) {
      if (phone.isEmpty) {
        await prefs.remove(_keyUserPhone);
      } else {
        await prefs.setString(_keyUserPhone, phone);
      }
    }
    if (alamat != null) {
      if (alamat.isEmpty) {
        await prefs.remove(_keyUserAlamat);
      } else {
        await prefs.setString(_keyUserAlamat, alamat);
      }
    }
    if (photoPath != null) {
      if (photoPath.isEmpty) {
        await prefs.remove(_keyUserPhoto);
      } else {
        await prefs.setString(_keyUserPhoto, photoPath);
      }
    }

    // Cache scoped per user
    if (cleanEmail.isNotEmpty) {
      final safeKey = cleanEmail.toLowerCase();
      await prefs.setString('user_name_$safeKey', name);
      if (phone != null) {
        if (phone.isEmpty) {
          await prefs.remove('user_phone_$safeKey');
        } else {
          await prefs.setString('user_phone_$safeKey', phone);
        }
      }
      if (alamat != null) {
        if (alamat.isEmpty) {
          await prefs.remove('user_alamat_$safeKey');
        } else {
          await prefs.setString('user_alamat_$safeKey', alamat);
        }
      }
      if (photoPath != null) {
        if (photoPath.isEmpty) {
          await prefs.remove('user_photo_$safeKey');
        } else {
          await prefs.setString('user_photo_$safeKey', photoPath);
        }
      }
    }
  }

  static const String _keyLastClearedAt = 'last_cleared_at';
  static const String _keyAutoCloudSync = 'auto_cloud_sync';
  static const String _keyAutoPhotoSync = 'auto_photo_sync';
  static const String _keySyncInterval = 'sync_interval_seconds';
  static const String _keyNotificationReminder = 'notif_reminder';
  static const String _keySoundVibration = 'sound_vibration';
  static const String _keyLastCloudSyncTime = 'last_cloud_sync_time';

  // Catat waktu terakhir "Hapus Semua" dilakukan agar sinkronisasi tidak menarik kembali data lama
  static Future<void> setLastClearedTimestamp(String timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastClearedAt, timestamp);
  }

  // Ambil waktu terakhir "Hapus Semua"
  static Future<String?> getLastClearedTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastClearedAt);
  }

  // --- PENGATURAN CLOUD SYNC & SISTEM PENYIMPANAN AWAN ---

  // Cek apakah Penyimpanan Otomatis ke Cloud / API aktif (Default: true)
  static Future<bool> isAutoCloudSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoCloudSync) ?? true;
  }

  // Atur status Penyimpanan Otomatis ke Cloud / API
  static Future<void> setAutoCloudSync(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoCloudSync, enabled);
  }

  // Cek apakah Upload Foto Profil Otomatis aktif (Default: true)
  static Future<bool> isAutoPhotoSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoPhotoSync) ?? true;
  }

  // Atur status Upload Foto Profil Otomatis
  static Future<void> setAutoPhotoSync(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoPhotoSync, enabled);
  }

  // Ambil interval sinkronisasi otomatis dalam detik (Default: 30 detik)
  static Future<int> getSyncIntervalSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keySyncInterval) ?? 30;
  }

  // Atur interval sinkronisasi otomatis dalam detik
  static Future<void> setSyncIntervalSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySyncInterval, seconds);
  }

  // Cek apakah Pengingat Notifikasi aktif (Default: true)
  static Future<bool> isNotificationReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNotificationReminder) ?? true;
  }

  // Atur status Pengingat Notifikasi
  static Future<void> setNotificationReminder(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotificationReminder, enabled);
  }

  // Cek apakah Suara & Getaran aktif (Default: true)
  static Future<bool> isSoundVibrationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySoundVibration) ?? true;
  }

  // Atur status Suara & Getaran
  static Future<void> setSoundVibration(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySoundVibration, enabled);
  }

  // Catat waktu sinkronisasi cloud terakhir
  static Future<void> setLastCloudSyncTime(String timeStr) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastCloudSyncTime, timeStr);
  }

  // Ambil waktu sinkronisasi cloud terakhir
  static Future<String?> getLastCloudSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastCloudSyncTime);
  }

  // --- PENGATURAN PENYIMPANAN INTERNAL & EKSTERNAL PONSEL ---
  static const String _keyStorageTarget = 'storage_target_location'; // 'internal' | 'external'

  // Ambil lokasi target penyimpanan yang dipilih pengguna (Default: 'internal')
  static Future<String> getStorageTarget() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyStorageTarget) ?? 'internal';
  }

  // Atur lokasi target penyimpanan ('internal' atau 'external')
  static Future<void> setStorageTarget(String target) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStorageTarget, target);
  }

  // --- OFFLINE DATA & QUEUE DALAM SHARED PREFERENCES ---
  static const String _keyOfflineAbsensiList = 'offline_absensi_list';
  static const String _keyOfflineProfilePending = 'offline_profile_pending';

  // Simpan data absensi offline ke SharedPreferences
  static Future<void> saveOfflineAbsensi(Map<String, dynamic> item) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyOfflineAbsensiList);
    List<dynamic> list = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        list = jsonDecode(raw) as List<dynamic>;
      } catch (_) {}
    }

    final entry = Map<String, dynamic>.from(item);
    entry['saved_to_prefs_at'] = DateTime.now().toIso8601String();

    list.add(entry);
    await prefs.setString(_keyOfflineAbsensiList, jsonEncode(list));
  }

  // Ambil daftar absensi offline dari SharedPreferences
  static Future<List<Map<String, dynamic>>> getOfflineAbsensiList() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyOfflineAbsensiList);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  // Bersihkan data absensi offline dari SharedPreferences setelah berhasil tersimpan di API
  static Future<void> clearOfflineAbsensiList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyOfflineAbsensiList);
  }

  // Simpan data update profil offline yang tertunda ke SharedPreferences
  static Future<void> setPendingProfileUpdate(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOfflineProfilePending, jsonEncode(data));
  }

  // Ambil data update profil offline yang tertunda dari SharedPreferences
  static Future<Map<String, dynamic>?> getPendingProfileUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyOfflineProfilePending);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  // Hapus data update profil offline yang tertunda
  static Future<void> clearPendingProfileUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyOfflineProfilePending);
  }

  // Hapus semua session saat logout
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
