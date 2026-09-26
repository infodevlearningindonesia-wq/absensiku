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
  final bool isAlreadyOnServer;

  SubmitAbsensiResult({
    required this.success,
    this.apiId,
    this.message,
    this.isAlreadyOnServer = false,
  });
}

class SyncAllResult {
  final int totalPending;
  final int syncedCount;
  final int failedCount;
  final String message;
  final List<String> errors;
  final bool isAuthError;

  SyncAllResult({
    required this.totalPending,
    required this.syncedCount,
    required this.failedCount,
    required this.message,
    this.errors = const [],
    this.isAuthError = false,
  });

  @override
  String toString() => '$syncedCount/$totalPending data tersinkron';
}

class UpdateProfileResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;
  final bool isAuthError;

  UpdateProfileResult({
    required this.success,
    required this.message,
    this.data,
    this.isAuthError = false,
  });
}

class UpdateAbsensiResult {
  final bool success;
  final String? newApiId;
  final String message;

  UpdateAbsensiResult({
    required this.success,
    this.newApiId,
    required this.message,
  });
}

class AppApiService {
  // Memastikan tersedianya token API yang valid (mencoba login otomatis jika saat ini offline/dummy)
  static Future<String?> ensureValidApiToken() async {
    final token = await PrefHelper.getToken();
    final isOffline = token == null || token.isEmpty || token.startsWith('local_token_');

    if (!isOffline) {
      return token;
    }

    // Coba re-autentikasi otomatis menggunakan kredensial tersimpan di SQLite lokal
    try {
      final email = await PrefHelper.getUserEmail();
      if (email != null && email.isNotEmpty) {
        final localUser = await DatabaseHelper.instance.getUserByEmail(email);
        if (localUser != null) {
          final password = localUser[DatabaseHelper.colUserPassword] as String?;
          if (password != null && password.isNotEmpty) {
            final dio = createDioClient();
            final apiService = ApiService(dio);
            final res = await apiService.login(LoginModel(email: email, password: password));
            final newToken = res.data?.token;
            if (newToken != null && newToken.isNotEmpty) {
              await PrefHelper.saveSession(
                token: newToken,
                userId: res.data?.user?.id ?? localUser[DatabaseHelper.colUserId] as int?,
                name: res.data?.user?.name ?? localUser[DatabaseHelper.colUserNama] as String? ?? 'Pengguna',
                email: email,
              );
              return newToken;
            }
          }
        }
      }
    } catch (_) {}

    return isOffline ? null : token;
  }

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
    final token = await ensureValidApiToken();
    if (token == null || token.isEmpty) {
      return SubmitAbsensiResult(
        success: false,
        message: 'Akun belum terhubung ke API (Mode Offline / Sesi Berakhir). Silakan login kembali dengan koneksi internet.',
      );
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
        message: message ?? 'Absen $tipe berhasil disinkronkan ke API.',
      );
    } catch (e) {
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final resData = e.response?.data;

        // 1. HTTP 409 Conflict: Data absensi hari ini sudah ada di server API!
        // Ini adalah SUKSES karena data absensi sudah tercatat di server.
        if (statusCode == 409) {
          String? apiId;
          String? message;
          if (resData is Map) {
            message = resData['message']?.toString();
            if (resData['data'] is Map && resData['data']['id'] != null) {
              apiId = resData['data']['id'].toString();
            } else if (resData['id'] != null) {
              apiId = resData['id'].toString();
            }
          }
          return SubmitAbsensiResult(
            success: true,
            apiId: apiId,
            message: message ?? 'Absensi sudah tercatat di server API (Tersinkron).',
            isAlreadyOnServer: true,
          );
        }

        // 2. HTTP 401 Unauthorized: Sesi login kedaluwarsa atau token tidak valid
        if (statusCode == 401) {
          return SubmitAbsensiResult(
            success: false,
            message: 'Sesi otentikasi API tidak valid atau telah berakhir (401). Silakan login ulang.',
          );
        }

        // 3. HTTP 404 Not Found: Biasanya pada absen keluar jika belum absen masuk di server
        if (statusCode == 404) {
          String? msg;
          if (resData is Map && resData['message'] != null) {
            msg = resData['message'].toString();
          }
          return SubmitAbsensiResult(
            success: false,
            message: msg ?? 'Data absen masuk hari ini belum ditemukan di server API (404).',
          );
        }

        // 4. HTTP 422: Validasi ditolak oleh server
        if (statusCode == 422) {
          String msg = 'Validasi data ditolak server.';
          if (resData is Map && resData['message'] != null) {
            msg = resData['message'].toString();
          }
          return SubmitAbsensiResult(success: false, message: msg);
        }

        // 5. Gangguan Jaringan / Timeout
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.connectionError) {
          return SubmitAbsensiResult(
            success: false,
            message: 'Koneksi ke server timeout atau tidak ada jaringan internet.',
          );
        }
      }
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
    if (id == null || id.toString().trim().isEmpty || id.toString().trim() == '0') return false;
    final token = await ensureValidApiToken();
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
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  // 4. Mengambil profil pengguna terbaru dari API
  static Future<Map<String, dynamic>?> getProfileFromApi() async {
    final token = await ensureValidApiToken();
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
          final serverEmail = data['email'] as String?;
          final id = data['id'] as int?;

          // Pertahankan email lokal yang sudah diperbarui agar tidak tertimpa email lama server
          final localEmail = await PrefHelper.getUserEmail();
          final effectiveEmail = (localEmail != null && localEmail.isNotEmpty)
              ? localEmail
              : (serverEmail ?? '');

          if (name != null) {
            await PrefHelper.saveSession(
              token: token,
              userId: id,
              name: name,
              email: effectiveEmail,
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
  static Future<UpdateProfileResult> updateProfileToApi({
    required String name,
    required String email,
  }) async {
    final token = await ensureValidApiToken();
    if (token == null || token.isEmpty) {
      return UpdateProfileResult(
        success: false,
        message: 'Akun belum terhubung ke API (Sesi Offline / Kedaluwarsa). Silakan login kembali dengan koneksi internet.',
        isAuthError: true,
      );
    }

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

      final isSuccess = response.statusCode == 200 || response.statusCode == 201;
      Map<String, dynamic>? resData;
      String? resMsg;

      if (response.data is Map) {
        final resMap = response.data as Map;
        resMsg = resMap['message']?.toString();
        if (resMap['data'] is Map) {
          resData = Map<String, dynamic>.from(resMap['data'] as Map);
        }
      }

      if (isSuccess) {
        final confirmedName = resData?['name']?.toString() ?? name.trim();
        final confirmedId = (resData?['id'] as num?)?.toInt();

        // Email yang diperbarui oleh pengguna selalu disimpan dan diprioritaskan
        final targetEmail = email.trim();

        // Perbarui sesi SharedPreferences dengan email yang diperbarui
        await PrefHelper.saveSession(
          token: token,
          userId: confirmedId,
          name: confirmedName,
          email: targetEmail,
        );

        return UpdateProfileResult(
          success: true,
          message: resMsg ?? 'Data profil berhasil diperbarui di server API.',
          data: resData,
        );
      }

      return UpdateProfileResult(
        success: false,
        message: resMsg ?? 'Gagal memperbarui profil di server API (${response.statusCode}).',
      );
    } catch (e) {
      if (e is DioException) {
        final status = e.response?.statusCode;
        final resData = e.response?.data;
        String? msg;
        if (resData is Map) {
          msg = resData['message']?.toString();
          if (resData['errors'] is Map) {
            final errs = (resData['errors'] as Map).values.map((v) {
              if (v is List) return v.join(', ');
              return v.toString();
            }).join('\n');
            if (errs.isNotEmpty) {
              msg = '$msg\n$errs';
            }
          }
        }

        if (status == 401) {
          return UpdateProfileResult(
            success: false,
            message: 'Sesi otentikasi API telah kedaluwarsa (401). Silakan login ulang.',
            isAuthError: true,
          );
        }
        if (status == 422) {
          return UpdateProfileResult(
            success: false,
            message: msg ?? 'Validasi profil ditolak server API.',
          );
        }
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.receiveTimeout) {
          return UpdateProfileResult(
            success: false,
            message: 'Koneksi ke server timeout atau tidak ada jaringan internet.',
          );
        }
        return UpdateProfileResult(
          success: false,
          message: msg ?? 'Gagal memperbarui profil di server API ($status).',
        );
      }
      return UpdateProfileResult(success: false, message: e.toString());
    }
  }

  // 5b. Perbarui data absensi di Server API (Replace strategy: Delete old + Create new jika sudah ada api_id)
  static Future<UpdateAbsensiResult> updateAbsensiOnApi({
    String? oldApiId,
    required String tipe,
    required String tanggal,
    required String waktu,
    double? latitude,
    double? longitude,
    String? keterangan,
  }) async {
    final token = await ensureValidApiToken();
    if (token == null || token.isEmpty) {
      return UpdateAbsensiResult(
        success: false,
        message: 'Akun belum terhubung ke API (Mode Offline). Perubahan disimpan di SQLite lokal.',
      );
    }

    // Jika memiliki API ID lama di server, hapus dulu record lama di server
    if (oldApiId != null &&
        oldApiId.isNotEmpty &&
        oldApiId != '0' &&
        oldApiId != 'null') {
      try {
        await deleteAbsensiFromApi(oldApiId);
      } catch (_) {}
    }

    // Kemudian submit data yang telah diperbarui ke server API
    final submitRes = await submitAbsensiToApi(
      tipe: tipe,
      tanggal: tanggal,
      waktu: waktu,
      latitude: latitude,
      longitude: longitude,
      keterangan: keterangan,
      isFromSync: true,
    );

    return UpdateAbsensiResult(
      success: submitRes.success,
      newApiId: submitRes.apiId,
      message: submitRes.message ??
          (submitRes.success
              ? 'Data absensi berhasil diperbarui di server API.'
              : 'Gagal memperbarui data di server API.'),
    );
  }

  // 6. Sinkronkan semua data lokal SQLite yang belum tersinkron ke API
  static Future<SyncAllResult> syncAllPendingToApi() async {
    final unsynced = await DatabaseHelper.instance.getUnsyncedAbsensi();
    if (unsynced.isEmpty) {
      return SyncAllResult(
        totalPending: 0,
        syncedCount: 0,
        failedCount: 0,
        message: 'Semua data absensi sudah tersinkronisasi ke API server.',
      );
    }

    // Urutkan agar pada tanggal yang sama, Absen Masuk selalu dikirim SEBELUM Absen Keluar
    final sortedUnsynced = List<Map<String, dynamic>>.from(unsynced);
    sortedUnsynced.sort((a, b) {
      final tglA = a[DatabaseHelper.columnTanggal]?.toString() ?? '';
      final tglB = b[DatabaseHelper.columnTanggal]?.toString() ?? '';
      if (tglA != tglB) {
        return tglA.compareTo(tglB);
      }
      final tipeA = a[DatabaseHelper.columnTipe]?.toString().toLowerCase() ?? '';
      final isMasukA = tipeA.contains('masuk') || tipeA.contains('in');
      final tipeB = b[DatabaseHelper.columnTipe]?.toString().toLowerCase() ?? '';
      final isMasukB = tipeB.contains('masuk') || tipeB.contains('in');
      if (isMasukA && !isMasukB) return -1;
      if (!isMasukA && isMasukB) return 1;
      return (a[DatabaseHelper.columnId] as int).compareTo(b[DatabaseHelper.columnId] as int);
    });

    int syncedCount = 0;
    int failedCount = 0;
    final List<String> errors = [];
    bool isAuthError = false;

    for (final item in sortedUnsynced) {
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
      } else {
        failedCount++;
        final err = '$tanggal ($tipe): ${result.message ?? "Gagal terhubung"}';
        errors.add(err);
        if (result.message != null &&
            (result.message!.contains('401') ||
                result.message!.toLowerCase().contains('offline') ||
                result.message!.toLowerCase().contains('sesi') ||
                result.message!.toLowerCase().contains('token'))) {
          isAuthError = true;
        }
      }
    }

    return SyncAllResult(
      totalPending: unsynced.length,
      syncedCount: syncedCount,
      failedCount: failedCount,
      message: syncedCount == unsynced.length
          ? 'Semua data kehadiran ($syncedCount) berhasil disinkronkan ke API server.'
          : '$syncedCount dari ${unsynced.length} data berhasil disinkronkan.',
      errors: errors,
      isAuthError: isAuthError,
    );
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
      final pendingResult = await syncAllPendingToApi();
      pendingSynced = pendingResult.syncedCount;

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
            DateTime? parsedCheckIn;
            try {
              parsedCheckIn = DateTime.tryParse(checkInStr.replaceFirst(' ', 'T'));
            } catch (_) {}

            String tanggalMasuk;
            String waktuMasuk;

            if (parsedCheckIn != null) {
              final local = parsedCheckIn.toLocal();
              tanggalMasuk =
                  '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
              waktuMasuk =
                  '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
            } else {
              tanggalMasuk = checkInStr.contains(' ')
                  ? checkInStr.split(' ').first
                  : (checkInStr.contains('T')
                      ? checkInStr.split('T').first
                      : (item['date'] ?? item['tanggal'] ?? defaultDate).toString());
              waktuMasuk = checkInStr.contains(' ')
                  ? checkInStr.split(' ')[1]
                  : (checkInStr.contains('T')
                      ? checkInStr.split('T')[1].split('.').first
                      : (item['time'] ?? item['waktu'] ?? '08:00:00').toString());
            }

            final ketMasuk = (item['check_in_address'] ??
                    item['keterangan'] ??
                    item['address'] ??
                    'Absen Masuk dari API Server')
                .toString();

            double latMasuk = -6.200000;
            double lonMasuk = 106.816666;
            if (item['check_in_lat'] != null) {
              latMasuk = double.tryParse(item['check_in_lat'].toString()) ?? -6.200000;
            } else if (item['latitude'] != null) {
              latMasuk = double.tryParse(item['latitude'].toString()) ?? -6.200000;
            }
            if (item['check_in_lng'] != null) {
              lonMasuk = double.tryParse(item['check_in_lng'].toString()) ?? 106.816666;
            } else if (item['longitude'] != null) {
              lonMasuk = double.tryParse(item['longitude'].toString()) ?? 106.816666;
            }

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
            DateTime? parsedCheckOut;
            try {
              parsedCheckOut = DateTime.tryParse(checkOutStr.replaceFirst(' ', 'T'));
            } catch (_) {}

            String tanggalKeluar;
            String waktuKeluar;

            if (parsedCheckOut != null) {
              final local = parsedCheckOut.toLocal();
              tanggalKeluar =
                  '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
              waktuKeluar =
                  '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
            } else {
              tanggalKeluar = checkOutStr.contains(' ')
                  ? checkOutStr.split(' ').first
                  : (checkOutStr.contains('T')
                      ? checkOutStr.split('T').first
                      : (item['date'] ?? item['tanggal'] ?? defaultDate).toString());
              waktuKeluar = checkOutStr.contains(' ')
                  ? checkOutStr.split(' ')[1]
                  : (checkOutStr.contains('T')
                      ? checkOutStr.split('T')[1].split('.').first
                      : (item['time'] ?? item['waktu'] ?? checkOutStr).toString());
            }

            final ketKeluar = (item['check_out_address'] ??
                    item['keterangan'] ??
                    item['address'] ??
                    'Absen Keluar dari API Server')
                .toString();

            double latKeluar = -6.200000;
            double lonKeluar = 106.816666;
            if (item['check_out_lat'] != null) {
              latKeluar = double.tryParse(item['check_out_lat'].toString()) ?? -6.200000;
            } else if (item['latitude'] != null) {
              latKeluar = double.tryParse(item['latitude'].toString()) ?? -6.200000;
            }
            if (item['check_out_lng'] != null) {
              lonKeluar = double.tryParse(item['check_out_lng'].toString()) ?? 106.816666;
            } else if (item['longitude'] != null) {
              lonKeluar = double.tryParse(item['longitude'].toString()) ?? 106.816666;
            }

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
            final tgl = (item['tanggal'] ??
                    item['date'] ??
                    (item['created_at']?.toString().split(' ').first ?? defaultDate))
                .toString();
            final wkt = (item['waktu'] ??
                    item['time'] ??
                    (item['created_at']?.toString().contains(' ') == true
                        ? item['created_at'].toString().split(' ')[1]
                        : '08:00:00'))
                .toString();
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