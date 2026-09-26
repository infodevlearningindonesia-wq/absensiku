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

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
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
  }) async {
    final db = await database;
    final row = {
      colUserNama: nama.trim(),
      colUserEmail: email.toLowerCase().trim(),
      colUserPassword: password,
      colUserCreatedAt: DateTime.now().toIso8601String(),
    };
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

  // Perbarui profil user berdasarkan ID
  Future<int> updateUser({
    required int id,
    required String nama,
    required String email,
    String? phone,
    String? alamat,
    String? foto,
  }) async {
    final db = await database;
    final cleanEmail = email.toLowerCase().trim();

    // Hapus akun lain yang memakai email yang sama agar tidak melanggar UNIQUE constraint
    try {
      await db.delete(
        tableUsers,
        where: 'LOWER($colUserEmail) = ? AND $colUserId != ?',
        whereArgs: [cleanEmail, id],
      );
    } catch (_) {}

    final Map<String, dynamic> data = {
      colUserNama: nama.trim(),
      colUserEmail: cleanEmail,
    };
    if (phone != null) data[colUserPhone] = phone.trim();
    if (alamat != null) data[colUserAlamat] = alamat.trim();
    if (foto != null) data[colUserFoto] = foto.trim();

    // Perbarui juga nama pada tabel absensi milik user ini
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
      data,
      where: '$colUserId = ?',
      whereArgs: [id],
      conflictAlgorithm: ConflictAlgorithm.replace,
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
    final db = await database;
    final cleanOldEmail = oldEmail.toLowerCase().trim();
    final cleanNewEmail = newEmail.toLowerCase().trim();

    // Hapus akun lain yang memakai newEmail jika bukan akun dengan oldEmail ini
    if (cleanOldEmail != cleanNewEmail) {
      try {
        await db.delete(
          tableUsers,
          where: 'LOWER($colUserEmail) = ? AND LOWER($colUserEmail) != ?',
          whereArgs: [cleanNewEmail, cleanOldEmail],
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

    return await db.update(
      tableUsers,
      data,
      where: 'LOWER($colUserEmail) = ?',
      whereArgs: [cleanOldEmail],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==================== FUNGSI RIWAYAT ABSENSI ====================

  // 1. CREATE: Tambah riwayat absensi lokal
  Future<int> insertAbsensi(Map<String, dynamic> row) async {
    final db = await database;
    row[columnCreatedAt] = DateTime.now().toIso8601String();
    return await db.insert(tableAbsensi, row);
  }

  // 2. READ: Ambil semua data absensi (urut dari yang terbaru), bisa difilter per userId
  Future<List<Map<String, dynamic>>> getAllAbsensi({int? userId}) async {
    final db = await database;
    if (userId != null) {
      return await db.query(
        tableAbsensi,
        where: '$columnUserId = ?',
        whereArgs: [userId],
        orderBy: '$columnId DESC',
      );
    }
    return await db.query(
      tableAbsensi,
      orderBy: '$columnId DESC',
    );
  }

  // 3. READ: Ambil data absensi berdasarkan user_id
  Future<List<Map<String, dynamic>>> getAbsensiByUserId(int userId) async {
    return await getAllAbsensi(userId: userId);
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

    // 1. Cek berdasarkan API ID jika ada
    if (apiId != null && apiId.isNotEmpty && apiId != 'null') {
      final resApi = await db.query(
        tableDeletedAbsensi,
        where: '$colDeletedApiId = ?',
        whereArgs: [apiId],
        limit: 1,
      );
      if (resApi.isNotEmpty) return true;
    }

    // 2. Cek berdasarkan tanggal, tipe, dan user_id
    final cleanTipe = tipe.toLowerCase().trim();
    final isMasuk = cleanTipe == 'masuk' || cleanTipe.contains('in');
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

    if (userId != null) {
      where += ' AND $columnUserId = ?';
      whereArgs.add(userId);
    }

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

  // Tutup koneksi database
  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
