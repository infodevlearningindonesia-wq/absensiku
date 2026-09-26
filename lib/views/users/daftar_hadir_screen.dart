import 'package:flutter/material.dart';
import 'package:absensiku/database/db_helper.dart';
import 'package:absensiku/services/api_services.dart';
import 'package:absensiku/services/pref_helper.dart';

class DaftarHadirScreen extends StatefulWidget {
  const DaftarHadirScreen({super.key});

  @override
  State<DaftarHadirScreen> createState() => _DaftarHadirScreenState();
}

class _DaftarHadirScreenState extends State<DaftarHadirScreen> {
  List<Map<String, dynamic>> _allAbsensi = [];
  List<Map<String, dynamic>> _filteredAbsensi = [];
  bool _isLoading = true;
  String _selectedFilter = 'Semua'; // 'Semua', 'Masuk', 'Pulang'
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDaftarHadir();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDaftarHadir() async {
    setState(() {
      _isLoading = true;
    });

    final userId = await PrefHelper.getUserId();
    final data = await DatabaseHelper.instance.getAllAbsensi(userId: userId);

    if (!mounted) return;
    setState(() {
      _allAbsensi = data;
      _applyFilter();
      _isLoading = false;
    });

    // Otomatis sinkronkan data yang belum tersinkron di background
    _autoSyncBackground();
  }

  Future<void> _autoSyncBackground() async {
    try {
      final result = await AppApiService.autoSyncAllData();
      final pendingCount = result['pendingSynced'] as int? ?? 0;
      final apiCount = result['apiItemsSynced'] as int? ?? 0;
      if ((pendingCount > 0 || apiCount > 0) && mounted) {
        final userId = await PrefHelper.getUserId();
        final refreshed = await DatabaseHelper.instance.getAllAbsensi(userId: userId);
        setState(() {
          _allAbsensi = refreshed;
          _applyFilter();
        });
      }
    } catch (_) {}
  }

  // Sinkronisasi data kehadiran lokal yang belum tersinkron ke API server dengan Alert Dialog
  Future<void> _syncToApi() async {
    final unsynced = await DatabaseHelper.instance.getUnsyncedAbsensi();
    if (!mounted) return;

    if (unsynced.isEmpty) {
      // Sinkronkan dua arah di background untuk memastikan tidak ada data baru dari server yang tertinggal
      AppApiService.autoSyncAllData().then((_) {
        if (mounted) _loadDaftarHadir();
      });
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
          content: const Text('Semua catatan absensi di perangkat sudah tersinkron ke API server.'),
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
        content: Text('Menyinkronkan ${unsynced.length} data kehadiran ke API server...'),
        duration: const Duration(seconds: 1),
      ),
    );

    final syncResult = await AppApiService.syncAllPendingToApi();
    // Sinkronisasi dua arah untuk memperbarui riwayat
    await AppApiService.autoSyncAllData();
    await _loadDaftarHadir();
    if (!mounted) return;

    if (syncResult.syncedCount > 0 && syncResult.failedCount == 0) {
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
          content: Text('${syncResult.syncedCount} data kehadiran berhasil disinkronkan ke API!'),
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
    } else if (syncResult.syncedCount > 0 && syncResult.failedCount > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Sinkronisasi Sebagian'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('• Berhasil: ${syncResult.syncedCount} data kehadiran'),
                Text('• Tertunda: ${syncResult.failedCount} data kehadiran'),
                const SizedBox(height: 12),
                const Text('Catatan Kendala:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  syncResult.errors.join('\n'),
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
            ),
          ),
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
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('Sinkronisasi Tertunda'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sebanyak ${syncResult.totalPending} data absensi belum berhasil dikirim ke API server.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text('Penyebab / Kendala:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  syncResult.errors.isNotEmpty ? syncResult.errors.join('\n') : syncResult.message,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
                const SizedBox(height: 12),
                const Text('Petunjuk Solusi:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  syncResult.isAuthError
                      ? 'Sesi token API offline atau telah berakhir. Silakan login kembali dengan koneksi internet aktif agar sesi terhubung ke server.'
                      : 'Pastikan koneksi internet ponsel stabil dan server API sedang aktif.',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
            ),
          ),
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
    }
    _loadDaftarHadir();
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase().trim();

    setState(() {
      _filteredAbsensi = _allAbsensi.where((item) {
        final tipe = (item[DatabaseHelper.columnTipe] as String? ?? '').toLowerCase();
        final tanggal = (item[DatabaseHelper.columnTanggal] as String? ?? '').toLowerCase();
        final nama = (item[DatabaseHelper.columnNama] as String? ?? '').toLowerCase();

        // Filter Tipe (Masuk / Keluar / Pulang)
        final matchesType = _selectedFilter == 'Semua' ||
            (_selectedFilter == 'Masuk' && (tipe == 'masuk' || tipe.contains('in'))) ||
            (_selectedFilter == 'Pulang' && (tipe == 'pulang' || tipe == 'keluar' || tipe.contains('out'))) ||
            (_selectedFilter == 'Keluar' && (tipe == 'pulang' || tipe == 'keluar' || tipe.contains('out')));

        // Filter Pencarian
        final matchesQuery = query.isEmpty ||
            tanggal.contains(query) ||
            nama.contains(query) ||
            tipe.contains(query);

        return matchesType && matchesQuery;
      }).toList();
    });
  }

  // READ (R): Tampilkan Detail Lengkap Catatan Kehadiran (Resmi & Tidak Dapat Diedit)
  void _showDetailItem(Map<String, dynamic> item) {
    final id = item[DatabaseHelper.columnId] as int;
    final tipe = item[DatabaseHelper.columnTipe] as String? ?? 'Masuk';
    final nama = item[DatabaseHelper.columnNama] as String? ?? '-';
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
              _buildDetailInfoRow('Nama', nama),
              _buildDetailInfoRow('Tanggal', tanggal),
              _buildDetailInfoRow('Waktu', '$waktu WIB'),
              _buildDetailInfoRow('Tipe', tipe),
              _buildDetailInfoRow(
                'Status Sync',
                isSync ? 'Sudah Tersinkron ke Server' : 'Tersimpan Lokal (SQLite)',
              ),
              if (lat != null && lon != null)
                _buildDetailInfoRow('Koordinat GPS', '$lat, $lon'),
              _buildDetailInfoRow('Keterangan / Lokasi', keterangan),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline, size: 18, color: Colors.brown),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Catatan presensi kehadiran bersifat resmi & terkunci otomatis (tidak dapat diedit demi integritas data presensi).',
                        style: TextStyle(fontSize: 11, color: Colors.brown, fontWeight: FontWeight.w500),
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _hapusItem(id);
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Hapus Riwayat')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailInfoRow(String label, String value) {
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

  // DELETE (D): Hapus 1 riwayat secara PERMANEN dari SQLite & Server API
  Future<void> _hapusItem(int id) async {
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
            'Catatan kehadiran ini akan dihapus secara PERMANEN dari database dan server API.\n\n'
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

    // 2. Hapus juga di API menggunakan ID API yang sebenarnya (hanya jika valid api_id)
    final apiId = deleted?[DatabaseHelper.columnApiId]?.toString();
    bool apiDeleted = false;
    if (apiId != null &&
        apiId.isNotEmpty &&
        apiId != '0' &&
        apiId != 'null') {
      try {
        apiDeleted = await AppApiService.deleteAbsensiFromApi(apiId);
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
              child: Text(apiDeleted
                  ? 'Catatan kehadiran berhasil dihapus dari database lokal dan server API.'
                  : 'Catatan kehadiran berhasil dihapus dari database lokal.'),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
    _loadDaftarHadir();
  }

  // DELETE (D): Hapus semua riwayat secara PERMANEN (TIDAK mempengaruhi akun pengguna)
  Future<void> _hapusSemua() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text('Kosongkan Semua Riwayat?')),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Seluruh data kehadiran akan dihapus secara PERMANEN dari database dan server API.\n\n'
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

    final userId = await PrefHelper.getUserId();
    final itemsToDelete = await DatabaseHelper.instance.getAllAbsensi(userId: userId);
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
    await DatabaseHelper.instance.clearAllAbsensi(userId: userId);
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
          'Semua riwayat kehadiran berhasil dihapus permanen. Akun login Anda tetap aman dan aktif.',
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

    _loadDaftarHadir();
  }

  @override
  Widget build(BuildContext context) {
    final totalMasuk = _allAbsensi.where((item) {
      final t = (item[DatabaseHelper.columnTipe] as String? ?? '').toLowerCase();
      return t == 'masuk' || t.contains('in');
    }).length;
    final totalPulang = _allAbsensi.where((item) {
      final t = (item[DatabaseHelper.columnTipe] as String? ?? '').toLowerCase();
      return t == 'pulang' || t == 'keluar' || t.contains('out');
    }).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Kehadiran'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_sync),
            tooltip: 'Sinkronkan ke API',
            onPressed: _syncToApi,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat Ulang',
            onPressed: _loadDaftarHadir,
          ),
          if (_allAbsensi.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Hapus Semua',
              onPressed: _hapusSemua,
            ),
        ],
      ),
      body: Column(
        children: [
          // 1. Ringkasan Statistik Kartu
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                _buildSummaryCard(
                  title: 'Total Absensi',
                  count: '${_allAbsensi.length}',
                  icon: Icons.list_alt,
                  color: Colors.blueAccent,
                ),
                const SizedBox(width: 10),
                _buildSummaryCard(
                  title: 'Absen Masuk',
                  count: '$totalMasuk',
                  icon: Icons.login,
                  color: Colors.green,
                ),
                const SizedBox(width: 10),
                _buildSummaryCard(
                  title: 'Absen Keluar',
                  count: '$totalPulang',
                  icon: Icons.logout,
                  color: Colors.orange,
                ),
              ],
            ),
          ),

          // 2. Bar Pencarian & Filter Chip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _applyFilter(),
              decoration: InputDecoration(
                hintText: 'Cari tanggal (YYYY-MM-DD) atau nama...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _applyFilter();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Pilihan Kategori Chip: Semua, Masuk, Pulang
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _buildFilterChip('Semua', _allAbsensi.length),
                const SizedBox(width: 8),
                _buildFilterChip('Masuk', totalMasuk),
                const SizedBox(width: 8),
                _buildFilterChip('Pulang', totalPulang),
              ],
            ),
          ),

          const SizedBox(height: 8),
          const Divider(),

          // 3. Daftar Kartu Riwayat Absensi
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredAbsensi.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_toggle_off, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              _allAbsensi.isEmpty
                                  ? 'Belum ada catatan kehadiran'
                                  : 'Tidak ada data yang sesuai filter',
                              style: TextStyle(color: Colors.grey[600], fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDaftarHadir,
                        child: ListView.builder(
                          itemCount: _filteredAbsensi.length,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemBuilder: (context, index) {
                            final item = _filteredAbsensi[index];
                            final id = item[DatabaseHelper.columnId] as int;
                            final nama = item[DatabaseHelper.columnNama] as String? ?? '';
                            final tipe = item[DatabaseHelper.columnTipe] as String? ?? 'Masuk';
                            final tanggal = item[DatabaseHelper.columnTanggal] as String? ?? '';
                            final waktu = item[DatabaseHelper.columnWaktu] as String? ?? '';
                            final keterangan = item[DatabaseHelper.columnKeterangan] as String? ?? '';
                            final latitude = item[DatabaseHelper.columnLatitude];
                            final longitude = item[DatabaseHelper.columnLongitude];
                            final isSync = (item[DatabaseHelper.columnStatusSync] as int? ?? 0) == 1;

                            final isMasuk = tipe.toLowerCase() == 'masuk';

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _showDetailItem(item),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                child: Row(
                                  children: [
                                    // Ikon Bulat Tipe
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: isMasuk
                                          ? Colors.green.shade100
                                          : Colors.orange.shade100,
                                      child: Icon(
                                        isMasuk ? Icons.login_rounded : Icons.logout_rounded,
                                        color: isMasuk ? Colors.green : Colors.orange,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Detail Informasi
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              Text(
                                                'Absen $tipe',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              // Badge Status Sync
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: isSync
                                                      ? Colors.green.shade100
                                                      : Colors.amber.shade100,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  isSync ? 'Sudah Sync' : 'Lokal (SQLite)',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isSync
                                                        ? Colors.green.shade800
                                                        : Colors.amber.shade900,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (nama.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2),
                                              child: Text(
                                                nama,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.blueGrey[800],
                                                ),
                                              ),
                                            ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '$tanggal • $waktu WIB',
                                            style: TextStyle(
                                              fontSize: 13,
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
                                                    keterangan.isNotEmpty
                                                        ? keterangan
                                                        : (latitude != null && longitude != null
                                                            ? 'Koordinat: $latitude, $longitude'
                                                            : 'Lokasi tercatat saat presensi'),
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
                                    ),

                                    // Tombol Aksi: Hapus Riwayat Permanen (Absensi terkunci & tidak dapat diedit)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                      tooltip: 'Hapus Permanen',
                                      onPressed: () => _hapusItem(id),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                count,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int count) {
    final isSelected = _selectedFilter == label;
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedFilter = label;
            _applyFilter();
          });
        }
      },
    );
  }
}
