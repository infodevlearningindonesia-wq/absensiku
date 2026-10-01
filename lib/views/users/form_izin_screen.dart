import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:absensiku/database/db_helper.dart';
import 'package:absensiku/services/dio_system.dart';
import 'package:absensiku/services/network_helper.dart';
import 'package:absensiku/services/pref_helper.dart';

class FormIzinScreen extends StatefulWidget {
  final bool isBottomSheet;
  final ScrollController? scrollController;

  const FormIzinScreen({
    super.key,
    this.isBottomSheet = false,
    this.scrollController,
  });

  static Future<bool?> show(BuildContext context) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const FormIzinScreen(),
      ),
    );
  }

  static Future<bool?> showAsBottomSheet(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.90,
        minChildSize: 0.50,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, scrollController) {
          return FormIzinScreen(
            isBottomSheet: true,
            scrollController: scrollController,
          );
        },
      ),
    );
  }

  @override
  State<FormIzinScreen> createState() => _FormIzinScreenState();
}

class _FormIzinScreenState extends State<FormIzinScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _alasanController = TextEditingController();
  final Geocoding _geocoding = Geocoding();

  String _jenisIzin = 'Izin'; // 'Izin', 'Sakit', 'Cuti', 'Dinas Luar'
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _isLocating = true;

  Position? _currentPosition;
  String _currentAddress = 'Mencari lokasi saat ini...';
  int? _userId;
  String _userName = 'Pengguna';

  final List<Map<String, dynamic>> _kategoriList = [
    {
      'label': 'Izin',
      'icon': Icons.assignment_turned_in_rounded,
      'color': const Color(0xFF2563EB), // Biru
      'desc': 'Izin keperluan pribadi / keluarga',
    },
    {
      'label': 'Sakit',
      'icon': Icons.medical_services_rounded,
      'color': const Color(0xFFDC2626), // Merah
      'desc': 'Tidak dapat hadir karena sakit',
    },
    {
      'label': 'Cuti',
      'icon': Icons.beach_access_rounded,
      'color': const Color(0xFFD97706), // Amber
      'desc': 'Pengajuan cuti kerja / tahunan',
    },
    {
      'label': 'Dinas Luar',
      'icon': Icons.business_center_rounded,
      'color': const Color(0xFF059669), // Hijau
      'desc': 'Tugas atau dinas di luar kantor',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadUserAndLocation();
  }

  @override
  void dispose() {
    _alasanController.dispose();
    super.dispose();
  }

  Future<void> _loadUserAndLocation() async {
    final name = await PrefHelper.getUserName();
    final id = await PrefHelper.getUserId();
    if (mounted) {
      setState(() {
        _userName = name;
        _userId = id;
      });
    }

    try {
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isServiceEnabled) {
        if (mounted) {
          setState(() {
            _isLocating = false;
            _currentAddress = 'Layanan lokasi (GPS) nonaktif.';
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 7),
          ),
        );

        String addr = 'Lokasi (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})';
        try {
          final placemarks = await _geocoding.placemarkFromCoordinates(
            pos.latitude,
            pos.longitude,
          );
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            final thoroughfare = p.thoroughfare ?? '';
            final subLocality = p.subLocality ?? '';
            final locality = p.locality ?? '';
            final subAdmin = p.subAdministrativeArea ?? '';
            final parts = [thoroughfare, subLocality, locality, subAdmin]
                .where((s) => s.isNotEmpty)
                .toList();
            if (parts.isNotEmpty) {
              addr = parts.join(', ');
            }
          }
        } catch (_) {}

        if (mounted) {
          setState(() {
            _currentPosition = pos;
            _currentAddress = addr;
            _isLocating = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLocating = false;
            _currentAddress = 'Izin lokasi tidak diberikan.';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLocating = false;
          _currentAddress = 'Lokasi default (Indonesia)';
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _getDateSqlString(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 60)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2563EB),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submitFormIzin() async {
    // 1. Validasi Wajib Isi Alasan Izin
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final alasan = _alasanController.text.trim();
    if (alasan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alasan izin wajib diisi!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final now = DateTime.now();
    final tanggalStr = _getDateSqlString(_selectedDate);
    final waktuStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    final lat = _currentPosition?.latitude ?? -6.200000;
    final lon = _currentPosition?.longitude ?? 106.816666;
    final fullKeterangan = '[$_jenisIzin] $alasan';

    bool apiSuccess = false;
    String? apiId;
    String? responseMsg;

    // 2. Coba kirim ke server API (Endpoint Check-In dengan status Izin)
    final isOnline = await NetworkHelper.hasInternetConnection();
    if (isOnline) {
      try {
        final token = await PrefHelper.getToken();
        if (token != null && token.isNotEmpty) {
          final dio = createDioClient();
          final payload = {
            'status': 'izin',
            'alasan_izin': alasan,
            'izin': fullKeterangan,
            'check_in_lat': lat,
            'check_in_lng': lon,
            'check_in_address': _currentAddress,
            'latitude': lat,
            'longitude': lon,
            'address': _currentAddress,
            'keterangan': fullKeterangan,
            'date': tanggalStr,
            'time': waktuStr,
          };

          final res = await dio.post(
            '/api/absen/check-in',
            data: payload,
          );

          if (res.statusCode == 200 || res.statusCode == 201) {
            apiSuccess = true;
            if (res.data is Map) {
              responseMsg = res.data['message']?.toString();
              if (res.data['data'] is Map && res.data['data']['id'] != null) {
                apiId = res.data['data']['id']?.toString();
              }
            }
          }
        }
      } catch (e) {
        apiSuccess = false;
      }
    }

    // JIKA GA ONLINE, SIMPAN KE SHARED PREFERENCES (Offline Fallback)
    if (!apiSuccess) {
      await PrefHelper.saveOfflineAbsensi({
        DatabaseHelper.columnApiId: null,
        DatabaseHelper.columnUserId: _userId,
        DatabaseHelper.columnNama: _userName,
        DatabaseHelper.columnTanggal: tanggalStr,
        DatabaseHelper.columnWaktu: waktuStr,
        DatabaseHelper.columnTipe: 'Izin',
        DatabaseHelper.columnKeterangan: fullKeterangan,
        DatabaseHelper.columnLatitude: lat,
        DatabaseHelper.columnLongitude: lon,
      });
    }

    // 3. Simpan ke database SQLite lokal
    await DatabaseHelper.instance.insertAbsensi({
      DatabaseHelper.columnApiId: apiId,
      DatabaseHelper.columnUserId: _userId,
      DatabaseHelper.columnNama: _userName,
      DatabaseHelper.columnTanggal: tanggalStr,
      DatabaseHelper.columnWaktu: waktuStr,
      DatabaseHelper.columnTipe: 'Izin',
      DatabaseHelper.columnKeterangan: fullKeterangan,
      DatabaseHelper.columnLatitude: lat,
      DatabaseHelper.columnLongitude: lon,
      DatabaseHelper.columnStatusSync: apiSuccess ? 1 : 0,
    });

    if (!mounted) return;
    setState(() => _isLoading = false);

    // 4. Tampilkan dialog sukses
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pengajuan Izin Berhasil',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pengajuan $_jenisIzin Anda telah berhasil dicatat.',
              style: const TextStyle(fontSize: 14, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Jenis: $_jenisIzin', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('• Tanggal: ${_formatDate(_selectedDate)}', style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 4),
                  Text('• Alasan: $alasan', style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 4),
                  Text(
                    apiSuccess ? '• Status Server: Tersinkronisasi' : '• Status Server: Disimpan Lokal (Offline)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: apiSuccess ? Colors.green.shade700 : Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ),
            if (responseMsg != null && responseMsg.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                responseMsg,
                style: const TextStyle(fontSize: 11.5, color: Colors.blueAccent, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context, true);
              },
              child: const Text('Selesai', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formContent = SingleChildScrollView(
      controller: widget.scrollController,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: widget.isBottomSheet ? 10 : 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit_note_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Form Pengajuan Izin',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Isi alasan izin dengan jelas dan lengkap.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 1. Pilih Jenis Izin
            const Text(
              'Pilih Jenis Izin',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.2,
              ),
              itemCount: _kategoriList.length,
              itemBuilder: (context, index) {
                final cat = _kategoriList[index];
                final isSelected = _jenisIzin == cat['label'];
                final color = cat['color'] as Color;

                return InkWell(
                  onTap: () {
                    setState(() {
                      _jenisIzin = cat['label'] as String;
                    });
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? color.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? color : const Color(0xFFE2E8F0),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          cat['icon'] as IconData,
                          color: isSelected ? color : Colors.grey[600],
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                cat['label'] as String,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isSelected ? color : const Color(0xFF1E293B),
                                ),
                              ),
                              Text(
                                cat['desc'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // 2. Tanggal Izin
            const Text(
              'Tanggal Izin',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 20, color: Color(0xFF2563EB)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _formatDate(_selectedDate),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 3. Alasan Izin (Wajib Isi)
            const Row(
              children: [
                Text(
                  'Alasan / Keterangan Izin',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                SizedBox(width: 4),
                Text(
                  '* (Wajib)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _alasanController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Contoh: Izin tidak hadir karena ada urusan keluarga mendesak / kontrol kesehatan.',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.8),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.redAccent),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Alasan izin wajib diisi!';
                }
                if (val.trim().length < 3) {
                  return 'Alasan izin terlalu pendek (minimal 3 karakter)';
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            // 4. Lokasi Terdeteksi
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_rounded, size: 20, color: Color(0xFF64748B)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lokasi Saat Pengajuan:',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isLocating ? 'Mendeteksi lokasi...' : _currentAddress,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // 5. Tombol Submit
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _submitFormIzin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(
                  _isLoading ? 'Mengirim Pengajuan...' : 'Kirim Pengajuan Izin',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.isBottomSheet) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag Handle Bar
            Center(
              child: Container(
                width: 48,
                height: 5,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            // Header Title Bar with Close Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: Color(0xFF2563EB), size: 24),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Pengajuan Izin / Sakit',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey, size: 22),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: formContent),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Row(
          children: [
            Expanded(
              child: Text(
                'Pengajuan Izin / Sakit',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        centerTitle: true,
      ),
      body: formContent,
    );
  }
}
