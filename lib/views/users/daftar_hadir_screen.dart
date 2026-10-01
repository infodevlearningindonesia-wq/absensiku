import 'package:flutter/material.dart';
import 'package:absensiku/database/db_helper.dart';
import 'package:absensiku/services/api_services.dart';
import 'package:absensiku/services/network_helper.dart';
import 'package:absensiku/services/pref_helper.dart';
import 'package:absensiku/views/users/maps_screen.dart';

class DaftarHadirScreen extends StatefulWidget {
  const DaftarHadirScreen({super.key});

  @override
  State<DaftarHadirScreen> createState() => _DaftarHadirScreenState();
}

class _DaftarHadirScreenState extends State<DaftarHadirScreen> {
  List<Map<String, dynamic>> _allAbsensi = [];
  List<Map<String, dynamic>> _filteredAbsensi = [];
  bool _isLoading = true;
  bool _isManualSyncing = false;

  // Filter Utama: 'Semua', 'Absensi', 'Masuk', 'Pulang', 'Izin', 'Sakit', 'Cuti', 'Dinas', 'Izin Biasa'
  String _selectedFilter = 'Semua';

  // Filter Tanggal: 'Semua', 'Hari Ini', '7 Hari', 'Bulan Ini', 'Kustom'
  String _dateFilter = 'Semua';
  DateTimeRange? _selectedDateRange;

  // Filter Status Sinkronisasi: 'Semua', 'Tersinkron', 'Lokal'
  String _selectedSyncFilter = 'Semua';

  // Pengurutan: 'Terbaru', 'Terlama'
  String _sortOrder = 'Terbaru';

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
    final userName = await PrefHelper.getUserName();
    final data = await DatabaseHelper.instance.getAllAbsensi(userId: userId, userName: userName);

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
        final userName = await PrefHelper.getUserName();
        final refreshed = await DatabaseHelper.instance.getAllAbsensi(userId: userId, userName: userName);
        setState(() {
          _allAbsensi = refreshed;
          _applyFilter();
        });
      }
    } catch (_) {}
  }

  Future<void> _manualSyncCloud() async {
    if (_isManualSyncing) return;
    setState(() => _isManualSyncing = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Menyinkronkan data dengan Cloud API...')),
          ],
        ),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final result = await AppApiService.autoSyncAllData();
      final pendingCount = result['pendingSynced'] as int? ?? 0;
      final apiCount = result['apiItemsSynced'] as int? ?? 0;
      final total = pendingCount + apiCount;

      final userId = await PrefHelper.getUserId();
      final userName = await PrefHelper.getUserName();
      final refreshed = await DatabaseHelper.instance.getAllAbsensi(userId: userId, userName: userName);
      if (mounted) {
        setState(() {
          _allAbsensi = refreshed;
          _applyFilter();
        });

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.cloud_done_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    total > 0
                        ? 'Sinkronisasi berhasil! $total catatan diperbarui ke Cloud API.'
                        : 'Semua data telah sinkron dengan Cloud API & SharedPreferences.',
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline: Data tetap tersimpan aman di SharedPreferences & lokal.'),
            backgroundColor: Color(0xFFEA580C),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isManualSyncing = false);
      }
    }
  }

  // Helper Pendeteksi Tipe
  bool _isIzinTipe(String tipe, [String keterangan = '']) {
    final t = tipe.toLowerCase();
    final k = keterangan.toLowerCase();
    return t.contains('izin') ||
        t.contains('ijin') ||
        t.contains('sakit') ||
        t.contains('cuti') ||
        t.contains('dinas') ||
        t.contains('dispensasi') ||
        k.contains('[izin]') ||
        k.contains('[sakit]') ||
        k.contains('[cuti]') ||
        k.contains('[dinas');
  }

  bool _isSakitTipe(String tipe, [String keterangan = '']) {
    final t = tipe.toLowerCase();
    final k = keterangan.toLowerCase();
    return t.contains('sakit') || k.contains('[sakit]');
  }

  bool _isCutiTipe(String tipe, [String keterangan = '']) {
    final t = tipe.toLowerCase();
    final k = keterangan.toLowerCase();
    return t.contains('cuti') || k.contains('[cuti]');
  }

  bool _isDinasTipe(String tipe, [String keterangan = '']) {
    final t = tipe.toLowerCase();
    final k = keterangan.toLowerCase();
    return t.contains('dinas') || k.contains('[dinas');
  }

  bool _isIzinBiasaTipe(String tipe, [String keterangan = '']) {
    if (!_isIzinTipe(tipe, keterangan)) return false;
    return !_isSakitTipe(tipe, keterangan) &&
        !_isCutiTipe(tipe, keterangan) &&
        !_isDinasTipe(tipe, keterangan);
  }

  bool _isMasukTipe(String tipe, [String keterangan = '']) {
    if (_isIzinTipe(tipe, keterangan)) return false;
    final t = tipe.toLowerCase();
    return t == 'masuk' || t.contains('in');
  }

  bool _isPulangTipe(String tipe, [String keterangan = '']) {
    if (_isIzinTipe(tipe, keterangan)) return false;
    final t = tipe.toLowerCase();
    return t == 'pulang' || t == 'keluar' || t.contains('out');
  }

  DateTime? _parseTanggal(String? tanggalStr) {
    if (tanggalStr == null || tanggalStr.trim().isEmpty) return null;
    final cleaned = tanggalStr.trim();
    try {
      return DateTime.parse(cleaned);
    } catch (_) {
      try {
        final parts = cleaned.split(RegExp(r'[-/.]'));
        if (parts.length == 3) {
          if (parts[0].length == 4) {
            return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          } else if (parts[2].length == 4) {
            return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          }
        }
      } catch (_) {}
    }
    return null;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDateShort(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTanggalIndo(String rawDate) {
    final dt = _parseTanggal(rawDate);
    if (dt == null) return rawDate;
    const months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  int get _activeFilterCount {
    int count = 0;
    if (_selectedFilter != 'Semua') count++;
    if (_dateFilter != 'Semua') count++;
    if (_selectedSyncFilter != 'Semua') count++;
    if (_sortOrder != 'Terbaru') count++;
    return count;
  }

  String get _dateFilterLabel {
    if (_dateFilter == 'Hari Ini') return 'Hari Ini';
    if (_dateFilter == '7 Hari') return '7 Hari Terakhir';
    if (_dateFilter == 'Bulan Ini') return 'Bulan Ini';
    if (_dateFilter == 'Kustom' && _selectedDateRange != null) {
      return '${_formatDateShort(_selectedDateRange!.start)} - ${_formatDateShort(_selectedDateRange!.end)}';
    }
    return 'Semua Waktu';
  }

  void _resetFilters() {
    setState(() {
      _selectedFilter = 'Semua';
      _dateFilter = 'Semua';
      _selectedDateRange = null;
      _selectedSyncFilter = 'Semua';
      _sortOrder = 'Terbaru';
      _searchController.clear();
      _applyFilter();
    });
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase().trim();
    final now = DateTime.now();

    setState(() {
      _filteredAbsensi = _allAbsensi.where((item) {
        final tipe = (item[DatabaseHelper.columnTipe] as String? ?? '').toLowerCase();
        final tanggalStr = (item[DatabaseHelper.columnTanggal] as String? ?? '').toLowerCase();
        final waktuStr = (item[DatabaseHelper.columnWaktu] as String? ?? '').toLowerCase();
        final nama = (item[DatabaseHelper.columnNama] as String? ?? '').toLowerCase();
        final keterangan = (item[DatabaseHelper.columnKeterangan] as String? ?? '').toLowerCase();
        final isSync = (item[DatabaseHelper.columnStatusSync] as int? ?? 0) == 1;

        final isIzin = _isIzinTipe(tipe, keterangan);
        final isSakit = _isSakitTipe(tipe, keterangan);
        final isCuti = _isCutiTipe(tipe, keterangan);
        final isDinas = _isDinasTipe(tipe, keterangan);
        final isIzinBiasa = _isIzinBiasaTipe(tipe, keterangan);
        final isMasuk = _isMasukTipe(tipe, keterangan);
        final isPulang = _isPulangTipe(tipe, keterangan);
        final isAbsensi = isMasuk || isPulang;

        // 1. Filter Kategori Tipe
        bool matchesType = true;
        switch (_selectedFilter) {
          case 'Absensi':
            matchesType = isAbsensi;
            break;
          case 'Masuk':
            matchesType = isMasuk;
            break;
          case 'Pulang':
            matchesType = isPulang;
            break;
          case 'Izin':
          case 'Semua Izin':
            matchesType = isIzin;
            break;
          case 'Sakit':
            matchesType = isSakit;
            break;
          case 'Cuti':
            matchesType = isCuti;
            break;
          case 'Dinas':
            matchesType = isDinas;
            break;
          case 'Izin Biasa':
            matchesType = isIzinBiasa;
            break;
          case 'Semua':
          default:
            matchesType = true;
            break;
        }
        if (!matchesType) return false;

        // 2. Filter Status Sinkronisasi
        if (_selectedSyncFilter == 'Tersinkron' && !isSync) return false;
        if (_selectedSyncFilter == 'Lokal' && isSync) return false;

        // 3. Filter Rentang Tanggal
        if (_dateFilter != 'Semua') {
          final itemDate = _parseTanggal(tanggalStr);
          if (itemDate == null) return false;

          if (_dateFilter == 'Hari Ini') {
            if (!_isSameDay(itemDate, now)) return false;
          } else if (_dateFilter == '7 Hari') {
            final today = DateTime(now.year, now.month, now.day);
            final sevenDaysAgo = today.subtract(const Duration(days: 6));
            final itemDay = DateTime(itemDate.year, itemDate.month, itemDate.day);
            if (itemDay.isBefore(sevenDaysAgo) || itemDay.isAfter(today)) return false;
          } else if (_dateFilter == 'Bulan Ini') {
            if (itemDate.year != now.year || itemDate.month != now.month) return false;
          } else if (_dateFilter == 'Kustom' && _selectedDateRange != null) {
            final start = DateTime(
              _selectedDateRange!.start.year,
              _selectedDateRange!.start.month,
              _selectedDateRange!.start.day,
            );
            final end = DateTime(
              _selectedDateRange!.end.year,
              _selectedDateRange!.end.month,
              _selectedDateRange!.end.day,
            );
            final itemDay = DateTime(itemDate.year, itemDate.month, itemDate.day);
            if (itemDay.isBefore(start) || itemDay.isAfter(end)) return false;
          }
        }

        // 4. Filter Pencarian Teks
        if (query.isNotEmpty) {
          final matchesQuery = tanggalStr.contains(query) ||
              waktuStr.contains(query) ||
              nama.contains(query) ||
              tipe.contains(query) ||
              keterangan.contains(query);
          if (!matchesQuery) return false;
        }

        return true;
      }).toList();

      // 5. Pengurutan (Sorting)
      _filteredAbsensi.sort((a, b) {
        final tglA = a[DatabaseHelper.columnTanggal]?.toString() ?? '';
        final tglB = b[DatabaseHelper.columnTanggal]?.toString() ?? '';
        final wktA = a[DatabaseHelper.columnWaktu]?.toString() ?? '';
        final wktB = b[DatabaseHelper.columnWaktu]?.toString() ?? '';

        final cmpTgl = tglA.compareTo(tglB);
        int cmp = cmpTgl != 0 ? cmpTgl : wktA.compareTo(wktB);
        if (cmp == 0) {
          final idA = a[DatabaseHelper.columnId] as int? ?? 0;
          final idB = b[DatabaseHelper.columnId] as int? ?? 0;
          cmp = idA.compareTo(idB);
        }
        return _sortOrder == 'Terlama' ? cmp : -cmp;
      });
    });
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: _selectedDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
      helpText: 'PILIH RENTANG TANGGAL PRESENSI',
      cancelText: 'BATAL',
      confirmText: 'PILIH',
      saveText: 'TERAPKAN',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2563EB),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _dateFilter = 'Kustom';
        _selectedDateRange = picked;
        _applyFilter();
      });
    }
  }

  // Modal Filter Lengkap (Upgrade Filter)
  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 12,
                bottom: MediaQuery.of(modalContext).padding.bottom + 20,
              ),
              child: SingleChildScrollView(
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
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Header Modal
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.tune_rounded,
                            color: Color(0xFF2563EB),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Filter & Urutan',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                'Sesuaikan tampilan riwayat presensi',
                                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _resetFilters();
                            setModalState(() {});
                            Navigator.pop(ctx);
                          },
                          child: const Text(
                            'Reset Semua',
                            style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 16),

                    // 1. Kategori Kehadiran
                    _buildSectionHeader('Kategori Kehadiran', Icons.category_rounded),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterOptionChip(
                          label: 'Semua Kategori',
                          isSelected: _selectedFilter == 'Semua',
                          onTap: () {
                            setModalState(() => _selectedFilter = 'Semua');
                            setState(() {
                              _selectedFilter = 'Semua';
                              _applyFilter();
                            });
                          },
                        ),
                        _buildFilterOptionChip(
                          label: 'Absensi (Semua)',
                          isSelected: _selectedFilter == 'Absensi',
                          onTap: () {
                            setModalState(() => _selectedFilter = 'Absensi');
                            setState(() {
                              _selectedFilter = 'Absensi';
                              _applyFilter();
                            });
                          },
                        ),
                        _buildFilterOptionChip(
                          label: 'Absen Masuk',
                          icon: Icons.login_rounded,
                          activeColor: const Color(0xFF059669),
                          isSelected: _selectedFilter == 'Masuk',
                          onTap: () {
                            setModalState(() => _selectedFilter = 'Masuk');
                            setState(() {
                              _selectedFilter = 'Masuk';
                              _applyFilter();
                            });
                          },
                        ),
                        _buildFilterOptionChip(
                          label: 'Absen Pulang',
                          icon: Icons.logout_rounded,
                          activeColor: const Color(0xFFEA580C),
                          isSelected: _selectedFilter == 'Pulang',
                          onTap: () {
                            setModalState(() => _selectedFilter = 'Pulang');
                            setState(() {
                              _selectedFilter = 'Pulang';
                              _applyFilter();
                            });
                          },
                        ),
                        _buildFilterOptionChip(
                          label: 'Semua Izin',
                          icon: Icons.event_note_rounded,
                          activeColor: const Color(0xFF7C3AED),
                          isSelected: _selectedFilter == 'Izin',
                          onTap: () {
                            setModalState(() => _selectedFilter = 'Izin');
                            setState(() {
                              _selectedFilter = 'Izin';
                              _applyFilter();
                            });
                          },
                        ),
                        _buildFilterOptionChip(
                          label: 'Izin Sakit',
                          icon: Icons.medical_services_rounded,
                          activeColor: const Color(0xFFE11D48),
                          isSelected: _selectedFilter == 'Sakit',
                          onTap: () {
                            setModalState(() => _selectedFilter = 'Sakit');
                            setState(() {
                              _selectedFilter = 'Sakit';
                              _applyFilter();
                            });
                          },
                        ),
                        _buildFilterOptionChip(
                          label: 'Cuti',
                          icon: Icons.beach_access_rounded,
                          activeColor: const Color(0xFF0284C7),
                          isSelected: _selectedFilter == 'Cuti',
                          onTap: () {
                            setModalState(() => _selectedFilter = 'Cuti');
                            setState(() {
                              _selectedFilter = 'Cuti';
                              _applyFilter();
                            });
                          },
                        ),
                        _buildFilterOptionChip(
                          label: 'Dinas',
                          icon: Icons.badge_rounded,
                          activeColor: const Color(0xFF4F46E5),
                          isSelected: _selectedFilter == 'Dinas',
                          onTap: () {
                            setModalState(() => _selectedFilter = 'Dinas');
                            setState(() {
                              _selectedFilter = 'Dinas';
                              _applyFilter();
                            });
                          },
                        ),
                        _buildFilterOptionChip(
                          label: 'Izin Biasa',
                          activeColor: const Color(0xFF7C3AED),
                          isSelected: _selectedFilter == 'Izin Biasa',
                          onTap: () {
                            setModalState(() => _selectedFilter = 'Izin Biasa');
                            setState(() {
                              _selectedFilter = 'Izin Biasa';
                              _applyFilter();
                            });
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // 2. Rentang Tanggal
                    _buildSectionHeader('Rentang Waktu', Icons.calendar_month_rounded),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterOptionChip(
                          label: 'Semua Waktu',
                          isSelected: _dateFilter == 'Semua',
                          onTap: () {
                            setModalState(() {
                              _dateFilter = 'Semua';
                              _selectedDateRange = null;
                            });
                            setState(() {
                              _dateFilter = 'Semua';
                              _selectedDateRange = null;
                              _applyFilter();
                            });
                          },
                        ),
                        _buildFilterOptionChip(
                          label: 'Hari Ini',
                          isSelected: _dateFilter == 'Hari Ini',
                          onTap: () {
                            setModalState(() {
                              _dateFilter = 'Hari Ini';
                              _selectedDateRange = null;
                            });
                            setState(() {
                              _dateFilter = 'Hari Ini';
                              _selectedDateRange = null;
                              _applyFilter();
                            });
                          },
                        ),
                        _buildFilterOptionChip(
                          label: '7 Hari Terakhir',
                          isSelected: _dateFilter == '7 Hari',
                          onTap: () {
                            setModalState(() {
                              _dateFilter = '7 Hari';
                              _selectedDateRange = null;
                            });
                            setState(() {
                              _dateFilter = '7 Hari';
                              _selectedDateRange = null;
                              _applyFilter();
                            });
                          },
                        ),
                        _buildFilterOptionChip(
                          label: 'Bulan Ini',
                          isSelected: _dateFilter == 'Bulan Ini',
                          onTap: () {
                            setModalState(() {
                              _dateFilter = 'Bulan Ini';
                              _selectedDateRange = null;
                            });
                            setState(() {
                              _dateFilter = 'Bulan Ini';
                              _selectedDateRange = null;
                              _applyFilter();
                            });
                          },
                        ),
                        _buildFilterOptionChip(
                          label: _dateFilter == 'Kustom' && _selectedDateRange != null
                              ? '${_formatDateShort(_selectedDateRange!.start)} - ${_formatDateShort(_selectedDateRange!.end)}'
                              : 'Pilih Rentang...',
                          icon: Icons.date_range_rounded,
                          isSelected: _dateFilter == 'Kustom',
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _pickCustomDateRange();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // 3. Status Sinkronisasi
                    _buildSectionHeader('Status Sinkronisasi', Icons.cloud_outlined),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFilterOptionChip(
                            label: 'Semua',
                            isSelected: _selectedSyncFilter == 'Semua',
                            onTap: () {
                              setModalState(() => _selectedSyncFilter = 'Semua');
                              setState(() {
                                _selectedSyncFilter = 'Semua';
                                _applyFilter();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildFilterOptionChip(
                            label: 'Cloud API',
                            icon: Icons.cloud_done_rounded,
                            activeColor: const Color(0xFF059669),
                            isSelected: _selectedSyncFilter == 'Tersinkron',
                            onTap: () {
                              setModalState(() => _selectedSyncFilter = 'Tersinkron');
                              setState(() {
                                _selectedSyncFilter = 'Tersinkron';
                                _applyFilter();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildFilterOptionChip(
                            label: 'Lokal',
                            icon: Icons.cloud_upload_outlined,
                            activeColor: const Color(0xFFD97706),
                            isSelected: _selectedSyncFilter == 'Lokal',
                            onTap: () {
                              setModalState(() => _selectedSyncFilter = 'Lokal');
                              setState(() {
                                _selectedSyncFilter = 'Lokal';
                                _applyFilter();
                              });
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // 4. Urutan Catatan
                    _buildSectionHeader('Urutkan Berdasarkan Waktu', Icons.sort_rounded),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFilterOptionChip(
                            label: 'Terbaru Dulu',
                            icon: Icons.arrow_downward_rounded,
                            isSelected: _sortOrder == 'Terbaru',
                            onTap: () {
                              setModalState(() => _sortOrder = 'Terbaru');
                              setState(() {
                                _sortOrder = 'Terbaru';
                                _applyFilter();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildFilterOptionChip(
                            label: 'Terlama Dulu',
                            icon: Icons.arrow_upward_rounded,
                            isSelected: _sortOrder == 'Terlama',
                            onTap: () {
                              setModalState(() => _sortOrder = 'Terlama');
                              setState(() {
                                _sortOrder = 'Terlama';
                                _applyFilter();
                              });
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Tombol Terapkan
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          'Terapkan Filter (${_filteredAbsensi.length} Catatan)',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF334155),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterOptionChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
    Color activeColor = const Color(0xFF2563EB),
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? activeColor : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? activeColor : const Color(0xFF64748B),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? activeColor : const Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // READ (R): Tampilkan Detail Lengkap Catatan Kehadiran
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

    final isIzin = _isIzinTipe(tipe, keterangan);
    final isMasuk = _isMasukTipe(tipe, keterangan);

    final IconData headerIcon;
    final Color headerColor;
    final String dialogTitle;

    if (isIzin) {
      headerIcon = Icons.event_note_rounded;
      headerColor = const Color(0xFF7C3AED);
      dialogTitle = 'Detail Pengajuan $tipe';
    } else if (isMasuk) {
      headerIcon = Icons.login_rounded;
      headerColor = const Color(0xFF059669);
      dialogTitle = 'Detail Absen Masuk';
    } else {
      headerIcon = Icons.logout_rounded;
      headerColor = const Color(0xFFEA580C);
      dialogTitle = 'Detail Absen Pulang';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: headerColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(headerIcon, color: headerColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dialogTitle,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _formatTanggalIndo(tanggal),
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailInfoRow('Nama Pegawai', nama),
              _buildDetailInfoRow(
                isIzin ? 'Waktu Pengajuan' : 'Waktu Presensi',
                '$tanggal • $waktu WIB',
              ),
              _buildDetailInfoRow(
                'Kategori Data',
                isIzin ? 'Pengajuan Perizinan / Cuti ($tipe)' : 'Presensi Kehadiran ($tipe)',
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status Sinkronisasi',
                      style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSync ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSync ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSync ? Icons.cloud_done_rounded : Icons.cloud_upload_outlined,
                            size: 13,
                            color: isSync ? const Color(0xFF059669) : const Color(0xFFD97706),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isSync
                                ? 'Tersinkron ke Cloud API'
                                : 'Tersimpan di Penyimpanan Lokal (Offline)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSync ? const Color(0xFF059669) : const Color(0xFFD97706),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (lat != null && lon != null) ...[
                _buildDetailInfoRow('Koordinat GPS', '$lat, $lon'),
                const SizedBox(height: 2),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      side: const BorderSide(color: Color(0xFF2563EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const GoogleMapsScreenDay19()),
                      );
                    },
                    icon: const Icon(Icons.map_outlined, size: 17),
                    label: const Text('Buka di Peta (Google Maps)', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _buildDetailInfoRow(
                isIzin ? 'Alasan & Keterangan Izin' : 'Keterangan / Lokasi',
                keterangan.isNotEmpty ? keterangan : '-',
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isIzin ? const Color(0xFFF5F3FF) : Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isIzin ? const Color(0xFFDDD6FE) : Colors.amber.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isIzin ? Icons.verified_user_outlined : Icons.lock_outline,
                      size: 18,
                      color: isIzin ? const Color(0xFF7C3AED) : Colors.brown,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isIzin
                            ? 'Catatan pengajuan izin ini tercatat resmi di database dan terenkripsi untuk integritas riwayat.'
                            : 'Catatan presensi kehadiran bersifat resmi & terkunci otomatis (tidak dapat diedit demi integritas data presensi).',
                        style: TextStyle(
                          fontSize: 11,
                          color: isIzin ? const Color(0xFF6B21A8) : Colors.brown,
                          fontWeight: FontWeight.w500,
                        ),
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
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Tutup')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _hapusItem(id, item: item);
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Hapus Catatan')),
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

  // DELETE (D): Hapus 1 riwayat secara PERMANEN
  Future<void> _hapusItem(int id, {Map<String, dynamic>? item}) async {
    final isOnline = await NetworkHelper.hasInternetConnection();
    if (!mounted) return;
    if (!isOnline) {
      NetworkHelper.showOfflineDialog(context, featureName: 'Hapus Riwayat Presensi');
      return;
    }

    final targetItem = item ??
        _allAbsensi.firstWhere(
          (e) => e[DatabaseHelper.columnId] == id,
          orElse: () => <String, dynamic>{},
        );

    final tipe = targetItem[DatabaseHelper.columnTipe]?.toString() ?? 'Presensi';
    final tanggal = targetItem[DatabaseHelper.columnTanggal]?.toString() ?? '-';
    final waktu = targetItem[DatabaseHelper.columnWaktu]?.toString() ?? '-';
    final keterangan = targetItem[DatabaseHelper.columnKeterangan]?.toString() ?? '-';
    final isIzin = _isIzinTipe(tipe, keterangan);
    final isMasuk = _isMasukTipe(tipe, keterangan);

    final IconData deleteIcon;
    final Color deleteColor;
    final Color deleteBgColor;
    final Color deleteBorderColor;
    final String deleteTitle;
    final String badgeLabel;

    if (isIzin) {
      deleteIcon = Icons.event_busy_rounded;
      deleteColor = const Color(0xFF7C3AED);
      deleteBgColor = const Color(0xFFF5F3FF);
      deleteBorderColor = const Color(0xFFDDD6FE);
      deleteTitle = 'Hapus Pengajuan $tipe?';
      badgeLabel = 'Pengajuan Izin';
    } else if (isMasuk) {
      deleteIcon = Icons.login_rounded;
      deleteColor = const Color(0xFF059669);
      deleteBgColor = const Color(0xFFECFDF5);
      deleteBorderColor = const Color(0xFFA7F3D0);
      deleteTitle = 'Hapus Absen Masuk?';
      badgeLabel = 'Absen Masuk';
    } else {
      deleteIcon = Icons.logout_rounded;
      deleteColor = const Color(0xFFEA580C);
      deleteBgColor = const Color(0xFFFFF7ED);
      deleteBorderColor = const Color(0xFFFED7AA);
      deleteTitle = 'Hapus Absen Pulang?';
      badgeLabel = 'Absen Pulang';
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: deleteBgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: deleteBorderColor),
              ),
              child: Icon(deleteIcon, color: deleteColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                deleteTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: deleteBgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: deleteBorderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: deleteColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badgeLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          waktu.contains('WIB') ? waktu : '$waktu WIB',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isIzin ? 'Tanggal Izin: $tanggal' : 'Tanggal Presensi: $tanggal',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    if (keterangan.isNotEmpty && keterangan != '-') ...[
                      const SizedBox(height: 3),
                      Text(
                        isIzin ? 'Alasan: $keterangan' : 'Lokasi: $keterangan',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isIzin
                    ? 'Catatan pengajuan izin ini akan dihapus secara permanen.\n\n'
                        '• Data perizinan yang dihapus tidak dapat dipulihkan.\n'
                        '• Riwayat sinkronisasi lokal dan cloud akan dibersihkan.'
                    : 'Catatan kehadiran ini akan dihapus secara permanen.\n\n'
                        '• Data yang dihapus tidak akan muncul kembali.\n'
                        '• Akun Anda yang sedang login tetap aktif.',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ],
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
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Hapus $tipe'),
                  ),
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
    if (apiId != null &&
        apiId.isNotEmpty &&
        apiId != '0' &&
        apiId != 'null') {
      try {
        await AppApiService.deleteAbsensiFromApi(apiId);
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
              child: Text('Catatan Absen $tipe berhasil dihapus secara permanen.'),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _loadDaftarHadir();
  }

  // DELETE (D): Hapus semua riwayat secara PERMANEN
  Future<void> _hapusSemua() async {
    final isOnline = await NetworkHelper.hasInternetConnection();
    if (!mounted) return;
    if (!isOnline) {
      NetworkHelper.showOfflineDialog(context, featureName: 'Hapus Semua Riwayat');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 8),
            Expanded(child: Text('Kosongkan Semua Riwayat?')),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Seluruh data kehadiran akan dihapus secara permanen.\n\n'
            '• Data yang dihapus tidak akan muncul kembali.\n'
            '• Akun Anda yang sedang login tetap aktif.',
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
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Hapus Semua')),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final userId = await PrefHelper.getUserId();
    final userName = await PrefHelper.getUserName();
    final itemsToDelete = await DatabaseHelper.instance.getAllAbsensi(userId: userId, userName: userName);
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
            Icon(Icons.check_circle_rounded, color: Color(0xFF059669)),
            SizedBox(width: 8),
            Expanded(child: Text('Penghapusan Berhasil')),
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
      final t = item[DatabaseHelper.columnTipe] as String? ?? '';
      final k = item[DatabaseHelper.columnKeterangan] as String? ?? '';
      return _isMasukTipe(t, k);
    }).length;

    final totalPulang = _allAbsensi.where((item) {
      final t = item[DatabaseHelper.columnTipe] as String? ?? '';
      final k = item[DatabaseHelper.columnKeterangan] as String? ?? '';
      return _isPulangTipe(t, k);
    }).length;

    final totalIzin = _allAbsensi.where((item) {
      final t = item[DatabaseHelper.columnTipe] as String? ?? '';
      final k = item[DatabaseHelper.columnKeterangan] as String? ?? '';
      return _isIzinTipe(t, k);
    }).length;

    final totalAbsensi = totalMasuk + totalPulang;

    // Menentukan status sub-kategori saat ini
    final isAbsensiCategoryActive = _selectedFilter == 'Absensi' ||
        _selectedFilter == 'Masuk' ||
        _selectedFilter == 'Pulang';

    final isIzinCategoryActive = _selectedFilter == 'Izin' ||
        _selectedFilter == 'Semua Izin' ||
        _selectedFilter == 'Sakit' ||
        _selectedFilter == 'Cuti' ||
        _selectedFilter == 'Dinas' ||
        _selectedFilter == 'Izin Biasa';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          children: [
            const Text(
              'Daftar Kehadiran',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF0F172A),
              ),
            ),
            Text(
              '${_filteredAbsensi.length} dari ${_allAbsensi.length} catatan tersimpan',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isManualSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                    ),
                  )
                : const Icon(Icons.cloud_sync_outlined),
            tooltip: 'Sinkronisasi Cloud API',
            onPressed: _isManualSyncing ? null : _manualSyncCloud,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Muat Ulang',
            onPressed: _loadDaftarHadir,
          ),
          if (_allAbsensi.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Hapus Semua',
              onPressed: _hapusSemua,
            ),
        ],
      ),
      body: Column(
        children: [
          // 1. Ringkasan Statistik Kartu (4 Kategori Interaktif Modern)
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 10.0),
            child: Row(
              children: [
                _buildSummaryCard(
                  title: 'Semua',
                  count: '${_allAbsensi.length}',
                  icon: Icons.apps_rounded,
                  color: const Color(0xFF2563EB),
                  isSelected: _selectedFilter == 'Semua',
                  onTap: () {
                    setState(() {
                      _selectedFilter = 'Semua';
                      _applyFilter();
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildSummaryCard(
                  title: 'Masuk',
                  count: '$totalMasuk',
                  icon: Icons.login_rounded,
                  color: const Color(0xFF059669),
                  isSelected: _selectedFilter == 'Masuk',
                  onTap: () {
                    setState(() {
                      _selectedFilter = 'Masuk';
                      _applyFilter();
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildSummaryCard(
                  title: 'Pulang',
                  count: '$totalPulang',
                  icon: Icons.logout_rounded,
                  color: const Color(0xFFEA580C),
                  isSelected: _selectedFilter == 'Pulang',
                  onTap: () {
                    setState(() {
                      _selectedFilter = 'Pulang';
                      _applyFilter();
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildSummaryCard(
                  title: 'Izin',
                  count: '$totalIzin',
                  icon: Icons.event_note_rounded,
                  color: const Color(0xFF7C3AED),
                  isSelected: isIzinCategoryActive,
                  onTap: () {
                    setState(() {
                      _selectedFilter = 'Izin';
                      _applyFilter();
                    });
                  },
                ),
              ],
            ),
          ),

          // 2. Bar Pencarian & Tombol Filter Canggih
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                // Input Pencarian
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => _applyFilter(),
                      decoration: InputDecoration(
                        hintText: 'Cari tanggal, nama, atau keterangan...',
                        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                                onPressed: () {
                                  _searchController.clear();
                                  _applyFilter();
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Tombol Buka Filter Lengkap (dengan Badge Notifikasi Filter Aktif)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _showFilterBottomSheet,
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _activeFilterCount > 0 ? const Color(0xFFEFF6FF) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _activeFilterCount > 0 ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                          width: _activeFilterCount > 0 ? 1.5 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 19,
                            color: _activeFilterCount > 0
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF475569),
                          ),
                          if (_activeFilterCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: Color(0xFF2563EB),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$_activeFilterCount',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 3. Tab Kategori Utama (Semua, Absensi, Izin)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                _buildExpandedFilterTab(
                  label: 'Semua',
                  count: _allAbsensi.length,
                  icon: Icons.apps_rounded,
                  activeColor: const Color(0xFF2563EB),
                  isSelected: _selectedFilter == 'Semua',
                  onTap: () {
                    setState(() {
                      _selectedFilter = 'Semua';
                      _applyFilter();
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildExpandedFilterTab(
                  label: 'Absensi',
                  count: totalAbsensi,
                  icon: Icons.how_to_reg_rounded,
                  activeColor: const Color(0xFF0284C7),
                  isSelected: isAbsensiCategoryActive,
                  onTap: () {
                    setState(() {
                      _selectedFilter = 'Absensi';
                      _applyFilter();
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildExpandedFilterTab(
                  label: 'Izin',
                  count: totalIzin,
                  icon: Icons.event_note_rounded,
                  activeColor: const Color(0xFF7C3AED),
                  isSelected: isIzinCategoryActive,
                  onTap: () {
                    setState(() {
                      _selectedFilter = 'Izin';
                      _applyFilter();
                    });
                  },
                ),
              ],
            ),
          ),

          // 4. Sub-Filter Dinamis (Untuk Absensi atau Izin)
          if (isAbsensiCategoryActive) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  _buildSubFilterTab(
                    label: 'Semua Absensi',
                    count: totalAbsensi,
                    icon: Icons.done_all_rounded,
                    activeColor: const Color(0xFF0284C7),
                    isSelected: _selectedFilter == 'Absensi',
                    onTap: () {
                      setState(() {
                        _selectedFilter = 'Absensi';
                        _applyFilter();
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildSubFilterTab(
                    label: 'Masuk',
                    count: totalMasuk,
                    icon: Icons.login_rounded,
                    activeColor: const Color(0xFF059669),
                    isSelected: _selectedFilter == 'Masuk',
                    onTap: () {
                      setState(() {
                        _selectedFilter = 'Masuk';
                        _applyFilter();
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildSubFilterTab(
                    label: 'Pulang',
                    count: totalPulang,
                    icon: Icons.logout_rounded,
                    activeColor: const Color(0xFFEA580C),
                    isSelected: _selectedFilter == 'Pulang',
                    onTap: () {
                      setState(() {
                        _selectedFilter = 'Pulang';
                        _applyFilter();
                      });
                    },
                  ),
                ],
              ),
            ),
          ] else if (isIzinCategoryActive) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  _buildPillFilterTab(
                    label: 'Semua Izin',
                    icon: Icons.event_note_rounded,
                    activeColor: const Color(0xFF7C3AED),
                    isSelected: _selectedFilter == 'Izin' || _selectedFilter == 'Semua Izin',
                    onTap: () {
                      setState(() {
                        _selectedFilter = 'Izin';
                        _applyFilter();
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildPillFilterTab(
                    label: 'Sakit',
                    icon: Icons.medical_services_rounded,
                    activeColor: const Color(0xFFE11D48),
                    isSelected: _selectedFilter == 'Sakit',
                    onTap: () {
                      setState(() {
                        _selectedFilter = 'Sakit';
                        _applyFilter();
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildPillFilterTab(
                    label: 'Cuti',
                    icon: Icons.beach_access_rounded,
                    activeColor: const Color(0xFF0284C7),
                    isSelected: _selectedFilter == 'Cuti',
                    onTap: () {
                      setState(() {
                        _selectedFilter = 'Cuti';
                        _applyFilter();
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildPillFilterTab(
                    label: 'Dinas',
                    icon: Icons.badge_rounded,
                    activeColor: const Color(0xFF4F46E5),
                    isSelected: _selectedFilter == 'Dinas',
                    onTap: () {
                      setState(() {
                        _selectedFilter = 'Dinas';
                        _applyFilter();
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildPillFilterTab(
                    label: 'Izin Biasa',
                    icon: Icons.note_alt_outlined,
                    activeColor: const Color(0xFF7C3AED),
                    isSelected: _selectedFilter == 'Izin Biasa',
                    onTap: () {
                      setState(() {
                        _selectedFilter = 'Izin Biasa';
                        _applyFilter();
                      });
                    },
                  ),
                ],
              ),
            ),
          ],

          // 5. Active Filters Strip (Tag Filter Aktif: Tanggal, Sync, Urutan)
          if (_dateFilter != 'Semua' ||
              _selectedSyncFilter != 'Semua' ||
              _sortOrder != 'Terbaru') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Tag Tanggal
                    if (_dateFilter != 'Semua')
                      _buildActiveFilterChip(
                        icon: Icons.calendar_today_rounded,
                        text: _dateFilterLabel,
                        onDelete: () {
                          setState(() {
                            _dateFilter = 'Semua';
                            _selectedDateRange = null;
                            _applyFilter();
                          });
                        },
                      ),

                    // Tag Status Sync
                    if (_selectedSyncFilter != 'Semua')
                      _buildActiveFilterChip(
                        icon: _selectedSyncFilter == 'Tersinkron'
                            ? Icons.cloud_done_rounded
                            : Icons.cloud_upload_outlined,
                        text: _selectedSyncFilter == 'Tersinkron' ? 'Tersinkron Cloud' : 'Lokal Offline',
                        onDelete: () {
                          setState(() {
                            _selectedSyncFilter = 'Semua';
                            _applyFilter();
                          });
                        },
                      ),

                    // Tag Sort Order
                    if (_sortOrder != 'Terbaru')
                      _buildActiveFilterChip(
                        icon: Icons.arrow_upward_rounded,
                        text: 'Urutan: Terlama',
                        onDelete: () {
                          setState(() {
                            _sortOrder = 'Terbaru';
                            _applyFilter();
                          });
                        },
                      ),

                    // Tombol Reset Cepat
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _resetFilters,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(
                          'Reset',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // 6. Daftar Kartu Riwayat Presensi & Perizinan
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF2563EB),
                    ),
                  )
                : _filteredAbsensi.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Icon(
                                  _selectedFilter == 'Izin'
                                      ? Icons.event_busy_rounded
                                      : (_selectedFilter == 'Masuk'
                                          ? Icons.login_rounded
                                          : (_selectedFilter == 'Pulang'
                                              ? Icons.logout_rounded
                                              : Icons.history_toggle_off_rounded)),
                                  size: 40,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _allAbsensi.isEmpty
                                    ? 'Belum ada catatan presensi'
                                    : 'Tidak ada data presensi yang sesuai',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF334155),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _allAbsensi.isEmpty
                                    ? 'Riwayat kehadiran dan pengajuan izin Anda akan muncul di sini.'
                                    : 'Coba ubah kata kunci pencarian atau sesuaikan opsi filter Anda.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              if (_activeFilterCount > 0 || _searchController.text.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF2563EB),
                                    side: const BorderSide(color: Color(0xFF2563EB)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: _resetFilters,
                                  icon: const Icon(Icons.refresh_rounded, size: 16),
                                  label: const Text('Reset Semua Filter'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        color: const Color(0xFF2563EB),
                        onRefresh: _loadDaftarHadir,
                        child: ListView.builder(
                          itemCount: _filteredAbsensi.length,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

                            final isIzin = _isIzinTipe(tipe, keterangan);
                            final isMasuk = _isMasukTipe(tipe, keterangan);

                            final Color itemBgColor;
                            final Color itemBorderColor;
                            final Color itemColor;
                            final IconData itemIcon;
                            final String titleText;
                            final String badgeCategory;

                            if (isIzin) {
                              final isSakit = _isSakitTipe(tipe, keterangan);
                              final isCuti = _isCutiTipe(tipe, keterangan);
                              final isDinas = _isDinasTipe(tipe, keterangan);

                              if (isSakit) {
                                itemBgColor = const Color(0xFFFFF1F2);
                                itemBorderColor = const Color(0xFFFECDD3);
                                itemColor = const Color(0xFFE11D48);
                                itemIcon = Icons.medical_services_rounded;
                                titleText = 'Izin Sakit';
                                badgeCategory = 'Sakit';
                              } else if (isCuti) {
                                itemBgColor = const Color(0xFFF0F9FF);
                                itemBorderColor = const Color(0xFFBAE6FD);
                                itemColor = const Color(0xFF0284C7);
                                itemIcon = Icons.beach_access_rounded;
                                titleText = 'Pengajuan Cuti';
                                badgeCategory = 'Cuti';
                              } else if (isDinas) {
                                itemBgColor = const Color(0xFFEEF2FF);
                                itemBorderColor = const Color(0xFFC7D2FE);
                                itemColor = const Color(0xFF4F46E5);
                                itemIcon = Icons.badge_rounded;
                                titleText = 'Perjalanan Dinas';
                                badgeCategory = 'Dinas';
                              } else {
                                itemBgColor = const Color(0xFFF5F3FF);
                                itemBorderColor = const Color(0xFFDDD6FE);
                                itemColor = const Color(0xFF7C3AED);
                                itemIcon = Icons.event_note_rounded;
                                titleText = 'Pengajuan Izin';
                                badgeCategory = 'Izin';
                              }
                            } else if (isMasuk) {
                              itemBgColor = const Color(0xFFECFDF5);
                              itemBorderColor = const Color(0xFFA7F3D0);
                              itemColor = const Color(0xFF059669);
                              itemIcon = Icons.login_rounded;
                              titleText = 'Absen Masuk';
                              badgeCategory = 'Masuk';
                            } else {
                              itemBgColor = const Color(0xFFFFF7ED);
                              itemBorderColor = const Color(0xFFFED7AA);
                              itemColor = const Color(0xFFEA580C);
                              itemIcon = Icons.logout_rounded;
                              titleText = 'Absen Pulang';
                              badgeCategory = 'Pulang';
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => _showDetailItem(item),
                                  child: Padding(
                                    padding: const EdgeInsets.all(13.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Ikon Squircle Tipe
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: itemBgColor,
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(color: itemBorderColor),
                                          ),
                                          child: Icon(
                                            itemIcon,
                                            color: itemColor,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),

                                        // Detail Informasi
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  Text(
                                                    titleText,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14.5,
                                                      color: Color(0xFF0F172A),
                                                    ),
                                                  ),
                                                  // Badge Kategori
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: itemBgColor,
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: itemBorderColor),
                                                    ),
                                                    child: Text(
                                                      badgeCategory,
                                                      style: TextStyle(
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.w700,
                                                        color: itemColor,
                                                      ),
                                                    ),
                                                  ),
                                                  // Badge Status Sinkronisasi
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2.5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: isSync
                                                          ? const Color(0xFFECFDF5)
                                                          : const Color(0xFFFFFBEB),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: isSync
                                                            ? const Color(0xFFA7F3D0)
                                                            : const Color(0xFFFDE68A),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          isSync
                                                              ? Icons.cloud_done_rounded
                                                              : Icons.cloud_upload_outlined,
                                                          size: 11,
                                                          color: isSync
                                                              ? const Color(0xFF059669)
                                                              : const Color(0xFFD97706),
                                                        ),
                                                        const SizedBox(width: 3),
                                                        Text(
                                                          isSync ? 'Tersinkron' : 'Lokal',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w700,
                                                            color: isSync
                                                                ? const Color(0xFF059669)
                                                                : const Color(0xFFD97706),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (nama.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 2),
                                                  child: Text(
                                                    nama,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: Color(0xFF334155),
                                                    ),
                                                  ),
                                                ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.access_time_rounded,
                                                    size: 13,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      '${_formatTanggalIndo(tanggal)} • $waktu WIB',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Color(0xFF64748B),
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF8FAFC),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      isIzin
                                                          ? Icons.edit_note_rounded
                                                          : Icons.location_on_rounded,
                                                      size: 14,
                                                      color: isIzin ? itemColor : const Color(0xFFEF4444),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        keterangan.isNotEmpty
                                                            ? keterangan
                                                            : (isIzin
                                                                ? 'Pengajuan perizinan tercatat'
                                                                : (latitude != null && longitude != null
                                                                    ? 'Koordinat: $latitude, $longitude'
                                                                    : 'Lokasi tercatat saat presensi')),
                                                        style: const TextStyle(
                                                          fontSize: 11.5,
                                                          fontWeight: FontWeight.w500,
                                                          color: Color(0xFF334155),
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (latitude != null && longitude != null) ...[
                                                      const SizedBox(width: 4),
                                                      const Icon(
                                                        Icons.map_outlined,
                                                        size: 13,
                                                        color: Color(0xFF2563EB),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Tombol Aksi: Hapus Riwayat
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            color: Color(0xFFEF4444),
                                            size: 20,
                                          ),
                                          tooltip: 'Hapus Catatan',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _hapusItem(id, item: item),
                                        ),
                                      ],
                                    ),
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

  Widget _buildActiveFilterChip({
    required IconData icon,
    required String text,
    required VoidCallback onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF2563EB)),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E40AF),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onDelete,
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 13, color: Color(0xFF2563EB)),
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
    VoidCallback? onTap,
    bool isSelected = false,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.08) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? color : const Color(0xFFE2E8F0),
                width: isSelected ? 1.6 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? color.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    count,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? color : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? color : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedFilterTab({
    required String label,
    required int count,
    required IconData icon,
    required Color activeColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected ? activeColor : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? activeColor : const Color(0xFFCBD5E1),
                width: isSelected ? 1.6 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: isSelected ? Colors.white : activeColor,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : const Color(0xFF334155),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.25)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubFilterTab({
    required String label,
    required int count,
    required IconData icon,
    required Color activeColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected ? activeColor.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? activeColor : const Color(0xFFE2E8F0),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 13,
                  color: isSelected ? activeColor : const Color(0xFF64748B),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? activeColor : const Color(0xFF475569),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? activeColor.withValues(alpha: 0.15)
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? activeColor : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPillFilterTab({
    required String label,
    required IconData icon,
    required Color activeColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? activeColor : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? activeColor : const Color(0xFF64748B),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? activeColor : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
