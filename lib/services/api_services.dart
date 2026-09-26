import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import 'package:absensiku/models/auth_response.dart';
import 'package:absensiku/models/login_models.dart';
import 'package:absensiku/models/register_models.dart';
import 'package:absensiku/services/dio_system.dart';
import 'package:absensiku/services/pref_helper.dart';
import 'package:absensiku/database/db_helper.dart';

part 'api_services.g.dart';

@RestApi(baseUrl: 'https://absensib1.mobileprojp.com')
abstract class ApiService {
  factory ApiService(Dio dio, {String baseUrl}) = _ApiService;

  @POST('/api/login')
  Future<AuthResponseModel> login(@Body() LoginModel body);

  @POST('/api/register')
  Future<AuthResponseModel> register(@Body() RegisterModel body);
}

class SubmitAbsensiResult {
  final bool success;
  final String? apiId;
  final String? message;

  SubmitAbsensiResult({
    required this.success,
    this.apiId,
    this.message,
  });
}

class AppApiService {
  // 1. Submit Absensi ke Server API (Absen Masuk & Absen Keluar)
  static Future<SubmitAbsensiResult> submitAbsensiToApi({
    required String tipe,
    required String tanggal,
    required String waktu,
    double? latitude,
    double? longitude,
    String? keterangan,
    bool isFromSync = false,
  }) async {
    final token = await PrefHelper.getToken();
    if (token == null || token.isEmpty) {
      return SubmitAbsensiResult(success: false, message: 'Token otentikasi tidak ditemukan');
    }

    final lat = latitude ?? -6.200000;
    final lng = longitude ?? 106.816666;
    final alamat = (keterangan != null && keterangan.isNotEmpty)
        ? keterangan
        : 'Absen $tipe dari aplikasi Absensiku';

    final cleanTipe = tipe.toLowerCase().trim();
    final isMasuk = cleanTipe == 'masuk' || cleanTipe.contains('in');
    final endpoint = isMasuk ? '/api/absen/check-in' : '/api/absen/check-out';

    // Jika ini Absen Keluar dan bukan dari proses sync, pastikan absen masuk yang pending telah terkirim ke server terlebih dahulu
    if (!isMasuk && !isFromSync) {
      try {
        await syncAllPendingToApi();
      } catch (_) {}
    }

    try {
      final dio = createDioClient();
      final Map<String, dynamic> data = isMasuk
          ? {
              'check_in_lat': lat,
              'check_in_lng': lng,
              'check_in_address': alamat,
              'latitude': lat,
              'longitude': lng,
              'address': alamat,
              'keterangan': alamat,
              'date': tanggal,
              'time': waktu,
            }
          : {
              'check_out_lat': lat,
              'check_out_lng': lng,
              'check_out_address': alamat,
              'latitude': lat,
              'longitude': lng,
              'address': alamat,
              'keterangan': alamat,
              'date': tanggal,
              'time': waktu,
            };

      final response = await dio.post(
        endpoint,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ),
        data: data,
      );

      final isSuccess = response.statusCode == 200 || response.statusCode == 201;
      String? apiId;
      String? message;

      if (response.data is Map) {
        final resMap = response.data as Map;
        message = resMap['message']?.toString();
        if (resMap['data'] is Map && resMap['data']['id'] != null) {
          apiId = resMap['data']['id'].toString();
        } else if (resMap['id'] != null) {
          apiId = resMap['id'].toString();
        }
      }

      return SubmitAbsensiResult(
        success: isSuccess,
        apiId: apiId,
        message: message,
      );
    } catch (e) {
      return SubmitAbsensiResult(success: false, message: e.toString());
    }
  }

  // 2. Mengambil riwayat absensi dari API
  static Future<List<Map<String, dynamic>>?> fetchHistoryFromApi() async {
    final token = await PrefHelper.getToken();
    if (token == null || token.isEmpty) return null;

    try {
      final dio = createDioClient();
      final response = await dio.get(
        '/api/absen/history',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        dynamic rawList;
        if (response.data is List) {
          rawList = response.data;
        } else if (response.data is Map && response.data['data'] is List) {
          rawList = response.data['data'];
        }
        if (rawList is List) {
          return List<Map<String, dynamic>>.from(rawList.whereType<Map<String, dynamic>>());
        }
      }
      return [];
    } catch (_) {
      return null;
    }
  }

  // 3. Hapus data absensi dari API
  static Future<bool> deleteAbsensiFromApi(dynamic id) async {
    final token = await PrefHelper.getToken();
    if (token == null || token.isEmpty) return false;

    try {
      final dio = createDioClient();
      final response = await dio.delete(
        '/api/absen/$id',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 4. Mengambil profil pengguna terbaru dari API
  static Future<Map<String, dynamic>?> getProfileFromApi() async {
    final token = await PrefHelper.getToken();
    if (token == null || token.isEmpty) return null;

    try {
      final dio = createDioClient();
      final response = await dio.get(
        '/api/profile',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data['data'] as Map<String, dynamic>?;
        if (data != null) {
          final name = data['name'] as String?;
          final email = data['email'] as String?;
          final id = data['id'] as int?;
          if (name != null && email != null) {
            await PrefHelper.saveSession(
              token: token,
              userId: id,
              name: name,
              email: email,
            );
          }
          return data;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // 5. Perbarui data profil pengguna ke Server API (PUT /api/profile)
  static Future<bool> updateProfileToApi({
    required String name,
    required String email,
  }) async {
    final token = await PrefHelper.getToken();
    if (token == null || token.isEmpty) return false;

    try {
      final dio = createDioClient();
      final response = await dio.put(
        '/api/profile',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'name': name.trim(),
          'email': email.trim(),
        },
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // 6. Sinkronkan semua data lokal SQLite yang belum tersinkron ke API
  static Future<int> syncAllPendingToApi() async {
    final unsynced = await DatabaseHelper.instance.getUnsyncedAbsensi();
    if (unsynced.isEmpty) return 0;

    int syncedCount = 0;
    for (final item in unsynced) {
      final id = item[DatabaseHelper.columnId] as int;
      final tipe = item[DatabaseHelper.columnTipe] as String? ?? 'Masuk';
      final tanggal = item[DatabaseHelper.columnTanggal] as String? ?? '';
      final waktu = item[DatabaseHelper.columnWaktu] as String? ?? '';
      final lat = (item[DatabaseHelper.columnLatitude] as num?)?.toDouble();
      final lon = (item[DatabaseHelper.columnLongitude] as num?)?.toDouble();
      final ket = item[DatabaseHelper.columnKeterangan] as String?;

      final result = await submitAbsensiToApi(
        tipe: tipe,
        tanggal: tanggal,
        waktu: waktu,
        latitude: lat,
        longitude: lon,
        keterangan: ket,
        isFromSync: true,
      );

      if (result.success) {
        await DatabaseHelper.instance.markAsSynced(id, apiId: result.apiId);
        syncedCount++;
      }
    }
    return syncedCount;
  }

  static bool _isSyncing = false;

  // 7. SINKRONISASI OTOMATIS MENYELURUH (Dua Arah: SQLite <-> Server API)
  static Future<Map<String, dynamic>> autoSyncAllData() async {
    if (_isSyncing) {
      return {
        'pendingSynced': 0,
        'apiItemsSynced': 0,
        'profileSynced': false,
      };
    }

    _isSyncing = true;
    int pendingSynced = 0;
    int apiItemsSynced = 0;
    bool profileSynced = false;

    try {
      // 1. Kirim semua absensi lokal yang berstatus pending (0) ke API server
      pendingSynced = await syncAllPendingToApi();

      // 2. Sinkronkan data profil pengguna terbaru dari server API
      try {
        final profileData = await getProfileFromApi();
        profileSynced = profileData != null;
      } catch (_) {}

      // 3. Tarik riwayat absensi dari API server dan sinkronkan ke SQLite lokal
      final apiHistory = await fetchHistoryFromApi();
      if (apiHistory != null && apiHistory.isNotEmpty) {
        final userId = await PrefHelper.getUserId();
        final userName = await PrefHelper.getUserName();
        final lastClearedAt = await PrefHelper.getLastClearedTimestamp();

        for (final item in apiHistory) {
          final apiId = item['id']?.toString();
          final createdAt = item['created_at']?.toString() ?? item['check_in']?.toString() ?? '';

          // Jika record dibuat sebelum waktu "Hapus Semua", hapus di server & lewati
          if (lastClearedAt != null && createdAt.isNotEmpty) {
            try {
              final itemTime = DateTime.parse(createdAt);
              final clearedTime = DateTime.parse(lastClearedAt);
              if (itemTime.isBefore(clearedTime)) {
                if (apiId != null && apiId.isNotEmpty) {
                  deleteAbsensiFromApi(apiId);
                }
                continue;
              }
            } catch (_) {}
          }

          final checkInStr = item['check_in']?.toString() ?? item['check_in_time']?.toString() ?? '';
          final checkOutStr = item['check_out']?.toString() ?? item['check_out_time']?.toString() ?? '';

          final now = DateTime.now();
          final defaultDate =
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

          // A. SINKRONKAN ABSEN MASUK DARI API KE SQLITE
          if (checkInStr.isNotEmpty && checkInStr != 'null') {
            final tanggalMasuk = checkInStr.contains(' ')
                ? checkInStr.split(' ').first
                : (item['date'] ?? item['tanggal'] ?? defaultDate).toString();
            final waktuMasuk = checkInStr.contains(' ')
                ? checkInStr.split(' ')[1]
                : (item['time'] ?? item['waktu'] ?? checkInStr).toString();
            final ketMasuk = (item['check_in_address'] ??
                    item['keterangan'] ??
                    item['address'] ??
                    'Absen Masuk dari API Server')
                .toString();
            final latMasuk = (item['check_in_lat'] ?? item['latitude'] as num?)?.toDouble() ?? -6.200000;
            final lonMasuk = (item['check_in_lng'] ?? item['longitude'] as num?)?.toDouble() ?? 106.816666;

            final isMasukDeleted = await DatabaseHelper.instance.isAbsensiDeleted(
              apiId: apiId,
              tanggal: tanggalMasuk,
              tipe: 'Masuk',
              userId: userId,
            );

            if (!isMasukDeleted) {
              final existsMasuk = await DatabaseHelper.instance.getAbsensiHariIni(
                tanggal: tanggalMasuk,
                tipe: 'Masuk',
                userId: userId,
              );

              if (existsMasuk == null) {
                await DatabaseHelper.instance.insertAbsensi({
                  DatabaseHelper.columnApiId: apiId,
                  DatabaseHelper.columnUserId: userId,
                  DatabaseHelper.columnNama: userName,
                  DatabaseHelper.columnTanggal: tanggalMasuk,
                  DatabaseHelper.columnWaktu: waktuMasuk,
                  DatabaseHelper.columnTipe: 'Masuk',
                  DatabaseHelper.columnKeterangan: ketMasuk,
                  DatabaseHelper.columnLatitude: latMasuk,
                  DatabaseHelper.columnLongitude: lonMasuk,
                  DatabaseHelper.columnStatusSync: 1,
                });
                apiItemsSynced++;
              } else {
                final existingId = existsMasuk[DatabaseHelper.columnId] as int;
                final curSync = existsMasuk[DatabaseHelper.columnStatusSync] as int? ?? 0;
                final curApiId = existsMasuk[DatabaseHelper.columnApiId]?.toString();
                if (curSync != 1 || curApiId == null || curApiId.isEmpty) {
                  await DatabaseHelper.instance.updateAbsensi(existingId, {
                    DatabaseHelper.columnApiId: apiId,
                    DatabaseHelper.columnStatusSync: 1,
                  });
                  apiItemsSynced++;
                }
              }
            }
          }

          // B. SINKRONKAN ABSEN KELUAR (CHECK-OUT) DARI API KE SQLITE
          if (checkOutStr.isNotEmpty && checkOutStr != 'null') {
            final tanggalKeluar = checkOutStr.contains(' ')
                ? checkOutStr.split(' ').first
                : (item['date'] ?? item['tanggal'] ?? defaultDate).toString();
            final waktuKeluar = checkOutStr.contains(' ')
                ? checkOutStr.split(' ')[1]
                : (item['time'] ?? item['waktu'] ?? checkOutStr).toString();
            final ketKeluar = (item['check_out_address'] ??
                    item['keterangan'] ??
                    item['address'] ??
                    'Absen Keluar dari API Server')
                .toString();
            final latKeluar = (item['check_out_lat'] ?? item['latitude'] as num?)?.toDouble() ?? -6.200000;
            final lonKeluar = (item['check_out_lng'] ?? item['longitude'] as num?)?.toDouble() ?? 106.816666;

            final isKeluarDeleted = await DatabaseHelper.instance.isAbsensiDeleted(
              apiId: apiId,
              tanggal: tanggalKeluar,
              tipe: 'Keluar',
              userId: userId,
            );

            if (!isKeluarDeleted) {
              final existsKeluar = await DatabaseHelper.instance.getAbsensiHariIni(
                tanggal: tanggalKeluar,
                tipe: 'Keluar',
                userId: userId,
              );

              if (existsKeluar == null) {
                await DatabaseHelper.instance.insertAbsensi({
                  DatabaseHelper.columnApiId: apiId,
                  DatabaseHelper.columnUserId: userId,
                  DatabaseHelper.columnNama: userName,
                  DatabaseHelper.columnTanggal: tanggalKeluar,
                  DatabaseHelper.columnWaktu: waktuKeluar,
                  DatabaseHelper.columnTipe: 'Keluar',
                  DatabaseHelper.columnKeterangan: ketKeluar,
                  DatabaseHelper.columnLatitude: latKeluar,
                  DatabaseHelper.columnLongitude: lonKeluar,
                  DatabaseHelper.columnStatusSync: 1,
                });
                apiItemsSynced++;
              } else {
                final existingId = existsKeluar[DatabaseHelper.columnId] as int;
                final curSync = existsKeluar[DatabaseHelper.columnStatusSync] as int? ?? 0;
                final curApiId = existsKeluar[DatabaseHelper.columnApiId]?.toString();
                if (curSync != 1 || curApiId == null || curApiId.isEmpty) {
                  await DatabaseHelper.instance.updateAbsensi(existingId, {
                    DatabaseHelper.columnApiId: apiId,
                    DatabaseHelper.columnStatusSync: 1,
                  });
                  apiItemsSynced++;
                }
              }
            }
          }

          // C. SINKRONKAN JIKA FORMAT ITEM ADALAH SINGLE TRANSACTION (tipe: Masuk / Keluar)
          final itemTipe = (item['tipe'] ?? item['type'] ?? '').toString().toLowerCase().trim();
          if (itemTipe.isNotEmpty && checkInStr.isEmpty && checkOutStr.isEmpty) {
            final isItemMasuk = itemTipe == 'masuk' || itemTipe.contains('in');
            final normalizedTipe = isItemMasuk ? 'Masuk' : 'Keluar';
            final tgl = (item['tanggal'] ?? item['date'] ?? (item['created_at']?.toString().split(' ').first ?? defaultDate)).toString();
            final wkt = (item['waktu'] ?? item['time'] ?? (item['created_at']?.toString().contains(' ') == true ? item['created_at'].toString().split(' ')[1] : '08:00:00')).toString();
            final ket = (item['keterangan'] ?? item['address'] ?? 'Absen $normalizedTipe dari Server').toString();
            final lat = (item['latitude'] ?? item['lat'] as num?)?.toDouble() ?? -6.200000;
            final lon = (item['longitude'] ?? item['lng'] as num?)?.toDouble() ?? 106.816666;

            final isDeleted = await DatabaseHelper.instance.isAbsensiDeleted(
              apiId: apiId,
              tanggal: tgl,
              tipe: normalizedTipe,
              userId: userId,
            );

            if (!isDeleted) {
              final exists = await DatabaseHelper.instance.getAbsensiHariIni(
                tanggal: tgl,
                tipe: normalizedTipe,
                userId: userId,
              );

              if (exists == null) {
                await DatabaseHelper.instance.insertAbsensi({
                  DatabaseHelper.columnApiId: apiId,
                  DatabaseHelper.columnUserId: userId,
                  DatabaseHelper.columnNama: userName,
                  DatabaseHelper.columnTanggal: tgl,
                  DatabaseHelper.columnWaktu: wkt,
                  DatabaseHelper.columnTipe: normalizedTipe,
                  DatabaseHelper.columnKeterangan: ket,
                  DatabaseHelper.columnLatitude: lat,
                  DatabaseHelper.columnLongitude: lon,
                  DatabaseHelper.columnStatusSync: 1,
                });
                apiItemsSynced++;
              } else {
                final existingId = exists[DatabaseHelper.columnId] as int;
                final curSync = exists[DatabaseHelper.columnStatusSync] as int? ?? 0;
                final curApiId = exists[DatabaseHelper.columnApiId]?.toString();
                if (curSync != 1 || curApiId == null || curApiId.isEmpty) {
                  await DatabaseHelper.instance.updateAbsensi(existingId, {
                    DatabaseHelper.columnApiId: apiId,
                    DatabaseHelper.columnStatusSync: 1,
                  });
                  apiItemsSynced++;
                }
              }
            }
          }
        }
      }
    } catch (_) {
    } finally {
      _isSyncing = false;
    }

    return {
      'pendingSynced': pendingSynced,
      'apiItemsSynced': apiItemsSynced,
      'profileSynced': profileSynced,
    };
  }
}