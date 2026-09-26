import 'package:shared_preferences/shared_preferences.dart';

class PrefHelper {
  static const String _keyToken = 'auth_token';
  static const String _keyUserId = 'user_id';
  static const String _keyUserName = 'user_name';
  static const String _keyUserEmail = 'user_email';
  static const String _keyIsLoggedIn = 'is_logged_in';

  // Simpan data login / session
  static Future<void> saveSession({
    required String token,
    int? userId,
    required String name,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    if (userId != null) {
      await prefs.setInt(_keyUserId, userId);
    }
    await prefs.setString(_keyUserName, name);
    await prefs.setString(_keyUserEmail, email);
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

  // Ambil Email Pengguna
  static Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserEmail);
  }

  // Simpan / Perbarui Email Pengguna
  static Future<void> setUserEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserEmail, email.trim());
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
    await prefs.setString(_keyUserEmail, email);
    if (phone != null) {
      await prefs.setString(_keyUserPhone, phone);
    }
    if (alamat != null) {
      await prefs.setString(_keyUserAlamat, alamat);
    }
    if (photoPath != null) {
      if (photoPath.isEmpty) {
        await prefs.remove(_keyUserPhoto);
      } else {
        await prefs.setString(_keyUserPhoto, photoPath);
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

  // Hapus semua session saat logout
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
