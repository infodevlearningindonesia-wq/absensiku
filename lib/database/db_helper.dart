import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static const String _databaseName = 'absensiku.db';
  static const int _databaseVersion = 4; // Dinaikkan ke v4 untuk phone, alamat, foto profil

  // ==================== TABEL USERS ====================
  static const String tableUsers = 'users';
  static const String colUserId = 'id';
  static const String colUserNama = 'nama';
  static const String colUserEmail = 'email';
  static const String colUserPassword = 'password';
  static const String colUserPhone = 'phone';
  static const String colUserAlamat = 'alamat';
  static const String colUserFoto = 'foto';
  static const String colUserRole = 'role'; // 'admin' / 'user'
  static const String colUserCreatedAt = 'created_at';

  // ==================== TABEL ABSENSI ====================
  static const String tableAbsensi = 'absensi';
  static const String columnId = 'id';
  static const String columnApiId = 'api_id'; // ID absensi dari server API
  static const String columnUserId = 'user_id';
  static const String columnNama = 'nama';
  static const String columnTanggal = 'tanggal';
  static const String columnWaktu = 'waktu';
  static const String columnTipe = 'tipe'; // Masuk / Pulang
  static const String columnKeterangan = 'keterangan';
  static const String columnLatitude = 'latitude';
  static const String columnLongitude = 'longitude';
  static const String columnStatusSync = 'status_sync'; // 0 = belum, 1 = sudah
  static const String columnCreatedAt = 'created_at';

// tabel lokasi
  static const String tableLocations = 'locations';
  static const String colLocationId = 'id';
  static const String colLocationUserId = 'user_id';
  static const String colLocationName = 'name';
  static const String colLocationAddress = 'address';
  static const String colLocationLatitude = 'latitude';
  static const String colLocationLongitude = 'longitude';
  static const String colLocationRadius = 'radius'; // meter
  static const String colLocationCreatedAt = 'created_at';
  static const String colLocationUpdatedAt = 'updated_at';
  
  // ==================== TABEL DELETED ABSENSI (Blacklist Permanen) ====================
  static const String tableDeletedAbsensi = 'deleted_absensi';
  static const String colDeletedId = 'id';
  static const String colDeletedApiId = 'api_id';
  static const String colDeletedTanggal = 'tanggal';
  static const String colDeletedTipe = 'tipe';
  static const String colDeletedUserId = 'user_id';
  static const String colDeletedWaktu = 'waktu';
  static const String colDeletedAt = 'deleted_at';

  // Singleton pattern
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    final db = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    // Pastikan kolom role ada di tabel users
    try {
      await db.execute('ALTER TABLE $tableUsers ADD COLUMN $colUserRole TEXT DEFAULT "user";');
    } catch (_) {}

    // Pastikan tabel locations ada
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableLocations (
          $colLocationId INTEGER PRIMARY KEY AUTOINCREMENT,
          $colLocationUserId INTEGER,
          $colLocationName TEXT NOT NULL,
          $colLocationAddress TEXT,
          $colLocationLatitude REAL NOT NULL,
          $colLocationLongitude REAL NOT NULL,
          $colLocationRadius REAL DEFAULT 100,
          $colLocationCreatedAt TEXT,
          $colLocationUpdatedAt TEXT
        )
      ''');
      final locCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $tableLocations')) ?? 0;
      if (locCount == 0) {
        await db.insert(tableLocations, {
          colLocationName: 'Kantor Pusat Mobile Pro JP',
          colLocationAddress: 'Jl. Jenderal Sudirman No. 45, Jakarta Pusat',
          colLocationLatitude: -6.2087634,
          colLocationLongitude: 106.845599,
          colLocationRadius: 100.0,
          colLocationCreatedAt: DateTime.now().toIso8601String(),
          colLocationUpdatedAt: DateTime.now().toIso8601String(),
        });
      }
    } catch (_) {}

    return db;
  }

  // Membuat tabel baru saat database pertama kali diinisialisasi
  Future<void> _onCreate(Database db, int version) async {
    // 1. Buat Tabel Users
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableUsers (
        $colUserId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colUserNama TEXT NOT NULL,
        $colUserEmail TEXT NOT NULL UNIQUE,
        $colUserPassword TEXT NOT NULL,
        $colUserPhone TEXT,
        $colUserAlamat TEXT,
        $colUserFoto TEXT,
        $colUserRole TEXT DEFAULT "user",
        $colUserCreatedAt TEXT
      )
    ''');

    // 2. Buat Tabel Absensi
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableAbsensi (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnApiId TEXT,
        $columnUserId INTEGER,
        $columnNama TEXT,
        $columnTanggal TEXT NOT NULL,
        $columnWaktu TEXT NOT NULL,
        $columnTipe TEXT NOT NULL,
        $columnKeterangan TEXT,
        $columnLatitude REAL,
        $columnLongitude REAL,
        $columnStatusSync INTEGER DEFAULT 0,
        $columnCreatedAt TEXT
      )
    ''');

    // 3. Buat Tabel Blacklist Penghapusan Permanen
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableDeletedAbsensi (
        $colDeletedId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colDeletedApiId TEXT,
        $colDeletedTanggal TEXT NOT NULL,
        $colDeletedTipe TEXT NOT NULL,
        $colDeletedUserId INTEGER,
        $colDeletedWaktu TEXT,
        $colDeletedAt TEXT
      )
    ''');

    // 4. Buat Tabel Titik Lokasi Kantor
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableLocations (
        $colLocationId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colLocationUserId INTEGER,
        $colLocationName TEXT NOT NULL,
        $colLocationAddress TEXT,
        $colLocationLatitude REAL NOT NULL,
        $colLocationLongitude REAL NOT NULL,
        $colLocationRadius REAL DEFAULT 100,
        $colLocationCreatedAt TEXT,
        $colLocationUpdatedAt TEXT
      )
    ''');

    // Seed default office
    await db.insert(tableLocations, {
      colLocationName: 'Kantor Pusat Mobile Pro JP',
      colLocationAddress: 'Jl. Jenderal Sudirman No. 45, Jakarta Pusat',
      colLocationLatitude: -6.2087634,
      colLocationLongitude: 106.845599,
      colLocationRadius: 100.0,
      colLocationCreatedAt: DateTime.now().toIso8601String(),
      colLocationUpdatedAt: DateTime.now().toIso8601String(),
    });
  }

  // Migrasi database jika versi bertambah
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableUsers (
          $colUserId INTEGER PRIMARY KEY AUTOINCREMENT,
          $colUserNama TEXT NOT NULL,
          $colUserEmail TEXT NOT NULL UNIQUE,
          $colUserPassword TEXT NOT NULL,
          $colUserCreatedAt TEXT
        )
      ''');
    }

    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE $tableAbsensi ADD COLUMN $columnApiId TEXT;');
      } catch (_) {}

      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableDeletedAbsensi (
          $colDeletedId INTEGER PRIMARY KEY AUTOINCREMENT,
          $colDeletedApiId TEXT,
          $colDeletedTanggal TEXT NOT NULL,
          $colDeletedTipe TEXT NOT NULL,
          $colDeletedUserId INTEGER,
          $colDeletedWaktu TEXT,
          $colDeletedAt TEXT
        )
      ''');
    }

    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE $tableUsers ADD COLUMN $colUserPhone TEXT;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $tableUsers ADD COLUMN $colUserAlamat TEXT;');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE $tableUsers ADD COLUMN $colUserFoto TEXT;');
      } catch (_) {}
    }
  }

  // ==================== FUNGSI AUTH (USERS) ====================

  // Cek apakah email sudah terdaftar di database SQLite lokal
  Future<bool> isEmailRegistered(String email) async {
    final db = await database;
    final result = await db.query(
      tableUsers,
      where: 'LOWER($colUserEmail) = ?',
      whereArgs: [email.toLowerCase().trim()],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  // Register user baru ke tabel users SQLite
  Future<int> registerUser({
    required String nama,
    required String email,
    required String password,
    String? phone,
    String? alamat,
    String? foto,
    String role = 'user',
  }) async {
    final db = await database;
    final row = {
      colUserNama: nama.trim(),
      colUserEmail: email.toLowerCase().trim(),
      colUserPassword: password,
      colUserRole: role.toLowerCase().trim(),
      colUserCreatedAt: DateTime.now().toIso8601String(),
    };
    if (phone != null) row[colUserPhone] = phone.trim();
    if (alamat != null) row[colUserAlamat] = alamat.trim();
    if (foto != null) row[colUserFoto] = foto.trim();
    return await db.insert(tableUsers, row);
  }

  // Login user: cek kecocokan email dan password di SQLite
  Future<Map<String, dynamic>?> loginUser({
    required String email,
    required String password,
  }) async {
    final db = await database;
    final result = await db.query(
      tableUsers,
      where: 'LOWER($colUserEmail) = ? AND $colUserPassword = ?',
      whereArgs: [email.toLowerCase().trim(), password],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  // Ambil user berdasarkan email
  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final db = await database;
    final result = await db.query(
      tableUsers,
      where: 'LOWER($colUserEmail) = ?',
      whereArgs: [email.toLowerCase().trim()],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  // Ambil user berdasarkan ID
  Future<Map<String, dynamic>?> getUserById(int id) async {
    final db = await database;
    final result = await db.query(
      tableUsers,
      where: '$colUserId = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  // Ambil semua daftar users lokal
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await database;
    return await db.query(tableUsers, orderBy: '$colUserId DESC');
  }

  // Hapus user berdasarkan email (opsional untuk reset)
  Future<int> deleteUserByEmail(String email) async {
    final db = await database;
    return await db.delete(
      tableUsers,
      where: 'LOWER($colUserEmail) = ?',
      whereArgs: [email.toLowerCase().trim()],
    );
  }

  // Hapus user berdasarkan ID (dengan opsi hapus seluruh riwayat absensi terkait)
  Future<int> deleteUserById(int id, {bool deleteAbsensi = false}) async {
    final db = await database;
    if (deleteAbsensi) {
      await db.delete(
        tableAbsensi,
        where: '$columnUserId = ?',
        whereArgs: [id],
      );
    }
    return await db.delete(
      tableUsers,
      where: '$colUserId = ?',
      whereArgs: [id],
    );
  }

  // Perbarui data user secara lengkap oleh Administrator
  Future<int> updateUserFull({
    required int id,
    required String nama,
    required String email,
    required String role,
    String? phone,
    String? alamat,
    String? foto,
    String? password,
  }) async {
    final db = await database;
    final cleanEmail = email.toLowerCase().trim();

    // Cek apakah email bentrok dengan ID lain
    final exist = await db.query(
      tableUsers,
      where: 'LOWER($colUserEmail) = ? AND $colUserId != ?',
      whereArgs: [cleanEmail, id],
    );
    if (exist.isNotEmpty) {
      throw Exception('Email "$email" sudah dipakai oleh akun lain!');
    }

    final Map<String, dynamic> row = {
      colUserNama: nama.trim(),
      colUserEmail: cleanEmail,
      colUserRole: role.toLowerCase().trim(),
    };
    if (phone != null) row[colUserPhone] = phone.trim();
    if (alamat != null) row[colUserAlamat] = alamat.trim();
    if (foto != null) row[colUserFoto] = foto.trim();
    if (password != null && password.trim().isNotEmpty) {
      row[colUserPassword] = password.trim();
    }

    // Sinkronkan nama di riwayat absensi user
    try {
      await db.update(
        tableAbsensi,
        {columnNama: nama.trim()},
        where: '$columnUserId = ?',
        whereArgs: [id],
      );
    } catch (_) {}

    return await db.update(
      tableUsers,
      row,
      where: '$colUserId = ?',
      whereArgs: [id],
    );
  }

  // Hitung jumlah user per role
  Future<Map<String, int>> getUserRoleCounts() async {
    final users = await getAllUsers();
    int adminCount = 0;
    int userCount = 0;
    for (final u in users) {
      final role = (u[colUserRole] as String? ?? 'user').toLowerCase().trim();
      final email = (u[colUserEmail] as String? ?? '').toLowerCase();
      if (role == 'admin' || email.contains('admin')) {
        adminCount++;
      } else {
        userCount++;
      }
    }
    return {
      'total': users.length,
      'admin': adminCount,
      'user': userCount,
    };
  }

  // Ringkasan kehadiran untuk 1 akun pengguna
  Future<Map<String, int>> getUserAbsensiSummary(int userId, {String? userName}) async {
    final list = await getAllAbsensi(userId: userId, userName: userName);
    int masuk = 0;
    int pulang = 0;
    int izin = 0;

    for (final a in list) {
      final tipe = (a[columnTipe] as String? ?? '').toLowerCase();
      final ket = (a[columnKeterangan] as String? ?? '').toLowerCase();
      final isIzin = tipe.contains('izin') ||
          tipe.contains('sakit') ||
          tipe.contains('cuti') ||
          tipe.contains('dinas') ||
          ket.contains('[izin]');
      if (isIzin) {
        izin++;
      } else if (tipe == 'masuk' || tipe.contains('in')) {
        masuk++;
      } else if (tipe == 'pulang' || tipe == 'keluar' || tipe.contains('out')) {
        pulang++;
      }
    }
    return {
      'total': list.length,
      'masuk': masuk,
      'pulang': pulang,
      'izin': izin,
    };
  }

  // Update password user berdasarkan email
  Future<int> updateUserPassword({
    required String email,
    required String newPassword,
  }) async {
    final db = await database;
    return await db.update(
      tableUsers,
      {colUserPassword: newPassword},
      where: 'LOWER($colUserEmail) = ?',
      whereArgs: [email.toLowerCase().trim()],
    );
  }

  // Perbarui profil pengguna dengan penanganan otomatis email lama / ID / email baru
  Future<int> updateUserProfileSafe({
    int? id,
    String? oldEmail,
    required String nama,
    required String newEmail,
    String? phone,
    String? alamat,
    String? foto,
  }) async {
    final db = await database;
    final cleanNewEmail = newEmail.toLowerCase().trim();
    final cleanOldEmail = (oldEmail ?? '').toLowerCase().trim();

    // 1. Cari user yang akan diperbarui (berdasarkan cleanOldEmail dulu, lalu ID, lalu cleanNewEmail)
    Map<String, dynamic>? existingUser;
    if (cleanOldEmail.isNotEmpty) {
      final res = await db.query(
        tableUsers,
        where: 'LOWER($colUserEmail) = ?',
        whereArgs: [cleanOldEmail],
        limit: 1,
      );
      if (res.isNotEmpty) {
        existingUser = res.first;
      }
    }

    if (existingUser == null && id != null) {
      final res = await db.query(
        tableUsers,
        where: '$colUserId = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (res.isNotEmpty) {
        existingUser = res.first;
      }
    }

    if (existingUser == null) {
      final res = await db.query(
        tableUsers,
        where: 'LOWER($colUserEmail) = ?',
        whereArgs: [cleanNewEmail],
        limit: 1,
      );
      if (res.isNotEmpty) {
        existingUser = res.first;
      }
    }

    // 2. Cegah UNIQUE constraint: hapus baris lain yang punya cleanNewEmail jika berbeda dari baris target
    final int? targetLocalId = existingUser != null ? (existingUser[colUserId] as int?) : null;
    if (targetLocalId != null) {
      try {
        await db.delete(
          tableUsers,
          where: 'LOWER($colUserEmail) = ? AND $colUserId != ?',
          whereArgs: [cleanNewEmail, targetLocalId],
        );
      } catch (_) {}
    } else {
      try {
        await db.delete(
          tableUsers,
          where: 'LOWER($colUserEmail) = ?',
          whereArgs: [cleanNewEmail],
        );
      } catch (_) {}
    }

    final Map<String, dynamic> data = {
      colUserNama: nama.trim(),
      colUserEmail: cleanNewEmail,
    };
    if (phone != null) data[colUserPhone] = phone.trim();
    if (alamat != null) data[colUserAlamat] = alamat.trim();
    if (foto != null) data[colUserFoto] = foto.trim();

    int result = 0;
    if (targetLocalId != null) {
      result = await db.update(
        tableUsers,
        data,
        where: '$colUserId = ?',
        whereArgs: [targetLocalId],
      );
    } else {
      // Jika belum ada di lokal, tambahkan sebagai user baru
      data[colUserPassword] = 'OfflinePassword123!';
      data[colUserCreatedAt] = DateTime.now().toIso8601String();
      result = await db.insert(tableUsers, data);
    }

    // 3. Perbarui juga nama pada tabel absensi milik user ini
    try {
      if (targetLocalId != null) {
        await db.update(
          tableAbsensi,
          {columnNama: nama.trim()},
          where: '$columnUserId = ?',
          whereArgs: [targetLocalId],
        );
      }
    } catch (_) {}

    return result;
  }

  // Perbarui profil user berdasarkan ID
  Future<int> updateUser({
    required int id,
    required String nama,
    required String email,
    String? phone,
    String? alamat,
    String? foto,
  }) async {
    return await updateUserProfileSafe(
      id: id,
      nama: nama,
      newEmail: email,
      phone: phone,
      alamat: alamat,
      foto: foto,
    );
  }

  // Perbarui profil user berdasarkan Email lama
  Future<int> updateUserByEmail({
    required String oldEmail,
    required String nama,
    required String newEmail,
    String? phone,
    String? alamat,
    String? foto,
  }) async {
    return await updateUserProfileSafe(
      oldEmail: oldEmail,
      nama: nama,
      newEmail: newEmail,
      phone: phone,
      alamat: alamat,
      foto: foto,
    );
  }

  // ==================== FUNGSI RIWAYAT ABSENSI ====================

  // 1. CREATE: Tambah riwayat absensi lokal
  Future<int> insertAbsensi(Map<String, dynamic> row) async {
    final db = await database;
    row[columnCreatedAt] = DateTime.now().toIso8601String();
    return await db.insert(tableAbsensi, row);
  }

  // 2. READ: Ambil semua data absensi (urut dari yang terbaru), difilter per akun (userId / userName)
  Future<List<Map<String, dynamic>>> getAllAbsensi({int? userId, String? userName}) async {
    final db = await database;
    if (userId != null && userName != null && userName.trim().isNotEmpty) {
      return await db.query(
        tableAbsensi,
        where: '$columnUserId = ? OR ($columnUserId IS NULL AND LOWER($columnNama) = ?)',
        whereArgs: [userId, userName.toLowerCase().trim()],
        orderBy: '$columnId DESC',
      );
    } else if (userId != null) {
      return await db.query(
        tableAbsensi,
        where: '$columnUserId = ?',
        whereArgs: [userId],
        orderBy: '$columnId DESC',
      );
    } else if (userName != null && userName.trim().isNotEmpty) {
      return await db.query(
        tableAbsensi,
        where: 'LOWER($columnNama) = ?',
        whereArgs: [userName.toLowerCase().trim()],
        orderBy: '$columnId DESC',
      );
    }
    return await db.query(
      tableAbsensi,
      orderBy: '$columnId DESC',
    );
  }

  // 3. READ: Ambil data absensi berdasarkan user_id & userName
  Future<List<Map<String, dynamic>>> getAbsensiByUserId(int userId, {String? userName}) async {
    return await getAllAbsensi(userId: userId, userName: userName);
  }

  // 4. UPDATE: Update status sync atau keterangan
  Future<int> updateAbsensi(int id, Map<String, dynamic> row) async {
    final db = await database;
    return await db.update(
      tableAbsensi,
      row,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  // 5. DELETE: Hapus 1 riwayat absensi secara PERMANEN (dicatat ke blacklist deleted_absensi)
  Future<Map<String, dynamic>?> deleteAbsensi(int id) async {
    final db = await database;
    final rows = await db.query(
      tableAbsensi,
      where: '$columnId = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final item = rows.first;
      // Catat ke blacklist agar tidak pernah muncul lagi saat reload dari API
      await recordDeletedAbsensi(
        apiId: item[columnApiId]?.toString(),
        tanggal: (item[columnTanggal] as String? ?? '').trim(),
        tipe: (item[columnTipe] as String? ?? '').trim(),
        userId: item[columnUserId] as int?,
        waktu: item[columnWaktu] as String?,
      );

      await db.delete(
        tableAbsensi,
        where: '$columnId = ?',
        whereArgs: [id],
      );
      return item;
    }
    return null;
  }

  // 6. DELETE: Hapus semua data absensi secara PERMANEN (TIDAK mempengaruhi akun/users)
  Future<int> clearAllAbsensi({int? userId}) async {
    final db = await database;
    String? where;
    List<dynamic>? whereArgs;
    if (userId != null) {
      where = '$columnUserId = ?';
      whereArgs = [userId];
    }

    final rows = await db.query(
      tableAbsensi,
      where: where,
      whereArgs: whereArgs,
    );

    for (final item in rows) {
      await recordDeletedAbsensi(
        apiId: item[columnApiId]?.toString(),
        tanggal: (item[columnTanggal] as String? ?? '').trim(),
        tipe: (item[columnTipe] as String? ?? '').trim(),
        userId: item[columnUserId] as int?,
        waktu: item[columnWaktu] as String?,
      );
    }

    return await db.delete(
      tableAbsensi,
      where: where,
      whereArgs: whereArgs,
    );
  }

  // 6b. RESET: Hapus seluruh data master absensi dan kelola blacklist sinkronisasi
  Future<int> resetMasterAbsensi({bool cleanBlacklist = false}) async {
    final db = await database;
    final rows = await db.query(tableAbsensi);
    for (final item in rows) {
      await recordDeletedAbsensi(
        apiId: item[columnApiId]?.toString(),
        tanggal: (item[columnTanggal] as String? ?? '').trim(),
        tipe: (item[columnTipe] as String? ?? '').trim(),
        userId: item[columnUserId] as int?,
        waktu: item[columnWaktu] as String?,
      );
    }
    if (cleanBlacklist) {
      await db.delete(tableDeletedAbsensi);
    }
    return await db.delete(tableAbsensi);
  }

  // ==================== FUNGSI BLACKLIST PENGHAPUSAN PERMANEN ====================

  // Catat riwayat absensi yang dihapus ke tabel deleted_absensi
  Future<void> recordDeletedAbsensi({
    String? apiId,
    required String tanggal,
    required String tipe,
    int? userId,
    String? waktu,
  }) async {
    final db = await database;
    await db.insert(tableDeletedAbsensi, {
      colDeletedApiId: apiId,
      colDeletedTanggal: tanggal,
      colDeletedTipe: tipe,
      colDeletedUserId: userId,
      colDeletedWaktu: waktu,
      colDeletedAt: DateTime.now().toIso8601String(),
    });
  }

  // Cek apakah suatu data absensi sudah pernah dihapus secara permanen oleh pengguna
  Future<bool> isAbsensiDeleted({
    String? apiId,
    required String tanggal,
    required String tipe,
    int? userId,
  }) async {
    final db = await database;

    final cleanTipe = tipe.toLowerCase().trim();
    final isMasuk = cleanTipe == 'masuk' || cleanTipe.contains('in');

    // 1. Cek berdasarkan API ID DAN TIPE jika ada (Memisahkan alur Masuk & Keluar)
    if (apiId != null && apiId.isNotEmpty && apiId != 'null') {
      final resApi = await db.query(
        tableDeletedAbsensi,
        where: isMasuk
            ? '$colDeletedApiId = ? AND (LOWER($colDeletedTipe) = ? OR LOWER($colDeletedTipe) LIKE ?)'
            : '$colDeletedApiId = ? AND (LOWER($colDeletedTipe) = ? OR LOWER($colDeletedTipe) = ? OR LOWER($colDeletedTipe) LIKE ? OR LOWER($colDeletedTipe) LIKE ?)',
        whereArgs: isMasuk
            ? [apiId, 'masuk', '%masuk%']
            : [apiId, 'keluar', 'pulang', '%keluar%', '%pulang%'],
        limit: 1,
      );
      if (resApi.isNotEmpty) return true;
    }
    String where;
    List<dynamic> whereArgs = [tanggal];

    if (isMasuk) {
      where = '$colDeletedTanggal = ? AND (LOWER($colDeletedTipe) = ? OR LOWER($colDeletedTipe) LIKE ?)';
      whereArgs.addAll(['masuk', '%masuk%']);
    } else {
      where =
          '$colDeletedTanggal = ? AND (LOWER($colDeletedTipe) = ? OR LOWER($colDeletedTipe) = ? OR LOWER($colDeletedTipe) LIKE ? OR LOWER($colDeletedTipe) LIKE ?)';
      whereArgs.addAll(['keluar', 'pulang', '%keluar%', '%pulang%']);
    }

    if (userId != null) {
      where += ' AND $colDeletedUserId = ?';
      whereArgs.add(userId);
    }

    final res = await db.query(
      tableDeletedAbsensi,
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );

    return res.isNotEmpty;
  }

  // 7. READ: Cek status absensi hari ini (Masuk / Keluar / Pulang)
  Future<Map<String, dynamic>?> getAbsensiHariIni({
    required String tanggal,
    required String tipe,
    int? userId,
    String? userName,
  }) async {
    final db = await database;
    final cleanTipe = tipe.toLowerCase().trim();
    final isMasuk = cleanTipe == 'masuk' || cleanTipe.contains('in');

    String where;
    List<dynamic> whereArgs = [tanggal];

    if (isMasuk) {
      where = '$columnTanggal = ? AND (LOWER($columnTipe) = ? OR LOWER($columnTipe) LIKE ?)';
      whereArgs.addAll(['masuk', '%masuk%']);
    } else {
      // Absen Keluar / Pulang
      where =
          '$columnTanggal = ? AND (LOWER($columnTipe) = ? OR LOWER($columnTipe) = ? OR LOWER($columnTipe) LIKE ? OR LOWER($columnTipe) LIKE ?)';
      whereArgs.addAll(['keluar', 'pulang', '%keluar%', '%pulang%']);
    }

    if (userId != null && userId > 0 && userName != null && userName.trim().isNotEmpty) {
      where += ' AND ($columnUserId = ? OR ($columnUserId IS NULL AND LOWER($columnNama) = ?))';
      whereArgs.addAll([userId, userName.toLowerCase().trim()]);
    } else if (userId != null && userId > 0) {
      where += ' AND $columnUserId = ?';
      whereArgs.add(userId);
    } else if (userName != null && userName.trim().isNotEmpty) {
      where += ' AND LOWER($columnNama) = ?';
      whereArgs.add(userName.toLowerCase().trim());
    }

    // Pastikan hanya mencocokkan record dengan waktu yang valid (bukan dummy/kosong/00:00:00)
    where += " AND $columnWaktu IS NOT NULL AND $columnWaktu != '' AND $columnWaktu != '00:00:00' AND $columnWaktu != '-' AND $columnWaktu != '--:--' AND $columnWaktu != '--:--:--'";

    final result = await db.query(
      tableAbsensi,
      where: where,
      whereArgs: whereArgs,
      orderBy: '$columnId DESC',
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  // 8. READ: Ambil semua riwayat absensi yang belum disinkronkan ke API (status_sync = 0)
  Future<List<Map<String, dynamic>>> getUnsyncedAbsensi() async {
    final db = await database;
    return await db.query(
      tableAbsensi,
      where: '$columnStatusSync = ?',
      whereArgs: [0],
      orderBy: '$columnId ASC',
    );
  }

  // 9. UPDATE: Tandai riwayat absensi sudah berhasil disinkronkan ke API (status_sync = 1)
  Future<int> markAsSynced(int id, {String? apiId}) async {
    final db = await database;
    final Map<String, dynamic> row = {columnStatusSync: 1};
    if (apiId != null && apiId.isNotEmpty) {
      row[columnApiId] = apiId;
    }
    return await db.update(
      tableAbsensi,
      row,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  // 4b. UPDATE DETAIL: Update riwayat absensi oleh admin secara terstruktur
  Future<int> updateAbsensiRecord({
    required int id,
    required String tanggal,
    required String waktu,
    required String tipe,
    required String keterangan,
    String? nama,
    double? latitude,
    double? longitude,
  }) async {
    final db = await database;
    final Map<String, dynamic> row = {
      columnTanggal: tanggal.trim(),
      columnWaktu: waktu.trim(),
      columnTipe: tipe.trim(),
      columnKeterangan: keterangan.trim(),
    };
    if (nama != null && nama.trim().isNotEmpty) {
      row[columnNama] = nama.trim();
    }
    if (latitude != null) row[columnLatitude] = latitude;
    if (longitude != null) row[columnLongitude] = longitude;

    return await db.update(
      tableAbsensi,
      row,
      where: '$columnId = ?',
      whereArgs: [id],
    );
  }

  // 1b. CREATE MANUAL: Tambah absensi manual oleh admin
  Future<int> insertAbsensiManual({
    required String nama,
    required String tanggal,
    required String waktu,
    required String tipe,
    required String keterangan,
    int? userId,
    double? latitude,
    double? longitude,
  }) async {
    final row = {
      columnNama: nama.trim(),
      columnTanggal: tanggal.trim(),
      columnWaktu: waktu.trim(),
      columnTipe: tipe.trim(),
      columnKeterangan: keterangan.trim(),
      columnStatusSync: 0,
      columnCreatedAt: DateTime.now().toIso8601String(),
    };
    if (userId != null) row[columnUserId] = userId;
    if (latitude != null) row[columnLatitude] = latitude;
    if (longitude != null) row[columnLongitude] = longitude;

    return await insertAbsensi(row);
  }

  // ==================== FUNGSI LOKASI KANTOR (CRUD) ====================
  Future<List<Map<String, dynamic>>> getAllLocations() async {
    final db = await database;
    try {
      return await db.query(tableLocations, orderBy: '$colLocationId ASC');
    } catch (_) {
      return [];
    }
  }

  Future<int> insertLocation(Map<String, dynamic> row) async {
    final db = await database;
    row[colLocationCreatedAt] = DateTime.now().toIso8601String();
    row[colLocationUpdatedAt] = DateTime.now().toIso8601String();
    return await db.insert(tableLocations, row);
  }

  Future<int> updateLocation(int id, Map<String, dynamic> row) async {
    final db = await database;
    row[colLocationUpdatedAt] = DateTime.now().toIso8601String();
    return await db.update(
      tableLocations,
      row,
      where: '$colLocationId = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteLocation(int id) async {
    final db = await database;
    return await db.delete(
      tableLocations,
      where: '$colLocationId = ?',
      whereArgs: [id],
    );
  }

  // Tutup koneksi database
  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
