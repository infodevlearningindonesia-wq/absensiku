import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:absensiku/services/network_helper.dart';

// COMENT YANG LAUNCHER
// import 'package:url_launcher/url_launcher.dart';

/// Screen utama untuk menampilkan Peta dan lokasi pengguna (Google Maps Asli)
class GoogleMapsScreenDay19 extends StatefulWidget {
  const GoogleMapsScreenDay19({super.key});

  @override
  State<GoogleMapsScreenDay19> createState() => _GoogleMapsScreenDay19State();
}

class _GoogleMapsScreenDay19State extends State<GoogleMapsScreenDay19> {
  // Instance untuk melakukan reverse geocoding (koordinat -> nama alamat)
  final Geocoding geocoding = Geocoding();

  // Controller untuk mengontrol tampilan kamera pada Google Maps Asli
  GoogleMapController? _mapController;

  // Set Marker untuk menampilkan pin lokasi pengguna pada Google Maps
  Set<Marker> _markers = {};

  // Menyimpan posisi geografis (latitude & longitude) perangkat saat ini
  Position? _currentPosition;

  // Menyimpan teks alamat lengkap hasil konversi dari koordinat
  String _currentAddress = "Mencari Lokasi...";

  // Status koneksi internet
  bool _isOnline = true;
  bool _isCheckingConnection = false;

  // Lokasi default (misal: Indramayu/Jakarta) jika lokasi perangkat belum didapatkan
  final LatLng _defaultLocation = const LatLng(-6.2000, 108.8166666);

  @override
  void initState() {
    super.initState();
    // Memeriksa izin akses lokasi dan mengambil posisi saat screen pertama kali dimuat
    _checkPermissionsAndGetLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  /// Memeriksa status GPS/Layanan Lokasi serta meminta izin akses lokasi ke pengguna
  Future<void> _checkPermissionsAndGetLocation() async {
    setState(() {
      _isCheckingConnection = true;
    });

    final online = await NetworkHelper.hasInternetConnection();
    if (!mounted) return;
    if (!online) {
      setState(() {
        _isOnline = false;
        _isCheckingConnection = false;
        _currentAddress = "Anda sedang offline. Peta Google Maps dan geolokasi membutuhkan koneksi internet aktif.";
      });
      NetworkHelper.showOfflineDialog(
        context,
        featureName: 'Peta Lokasi Google Maps',
      );
      return;
    }

    setState(() {
      _isOnline = true;
      _isCheckingConnection = false;
    });

    bool serviceEnabled;
    LocationPermission permission;

    // 1. Cek apakah layanan GPS pada perangkat dalam kondisi aktif
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _currentAddress = "Layanan lokasi dinonaktifkan.";
      });
      return;
    }

    // 2. Cek status izin akses lokasi aplikasi
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // Minta izin ke pengguna jika belum diizinkan
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _currentAddress = "Izin lokasi ditolak.";
        });
        return;
      }
    }

    // 3. Jika izin ditolak secara permanen oleh pengguna
    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _currentAddress = "Izin lokasi ditolak permanen.";
      });
      return;
    }

    // 4. Jika semua izin terpenuhi, ambil posisi lokasi saat ini
    await _getCurrentLocation();
  }

  /// Mengambil titik koordinat (Latitude & Longitude) terbaru dari GPS perangkat
  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final currentLatLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentPosition = position;
        _markers = {
          Marker(
            markerId: const MarkerId('currentLocation'),
            position: currentLatLng,
            infoWindow: const InfoWindow(title: 'Lokasi Anda Saat Ini'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
          ),
        };
      });

      log('Posisi terkini: ${_currentPosition.toString()}');

      // Perbarui posisi marker dan gerakkan kamera peta ke lokasi pengguna
      _updateMarkerAndCamera(position);

      // Konversi koordinat menjadi nama alamat jalan
      await _getAddressFromLatLng(position);
    } catch (e) {
      log("Error getting location: $e");
    }
  }

  /// Memperbarui pin marker di peta dan menganimasikan gerak kamera ke koordinat terkini
  void _updateMarkerAndCamera(Position position) {
    final currentLatLng = LatLng(position.latitude, position.longitude);
    try {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: currentLatLng, zoom: 16.0),
        ),
      );
    } catch (_) {}
  }

  /// Melakukan Reverse Geocoding (mengubah latitude & longitude menjadi alamat lengkap)
  Future<void> _getAddressFromLatLng(Position position) async {
    try {
      List<Placemark> placemarks = await geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        log(place.toString());

        // Susun teks alamat dari komponen street, subLocality, locality, dsb.
        setState(() {
          _currentAddress =
              "${place.street}, ${place.subLocality}, ${place.locality}, ${place.postalCode}, ${place.country}";
        });
      }
    } catch (e) {
      log("Error getting address: $e");
    }
  }

  /*
  // COMENT YANG LAUNCHER
  /// Membuka lokasi pengguna saat ini di aplikasi Google Maps eksternal
  Future<void> _openInGoogleMaps() async {
    if (_currentPosition == null) return;

    final double lat = _currentPosition!.latitude;
    final double lng = _currentPosition!.longitude;
    final Uri googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );

    try {
      if (!await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication)) {
        throw Exception('Tidak dapat membuka Google Maps');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal membuka Google Maps: $e")),
      );
    }
  }
  */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Expanded(
              child: Text(
                'Peta Lokasi Presensi',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location_rounded),
            tooltip: 'Perbarui Lokasi',
            onPressed: _checkPermissionsAndGetLocation,
          ),
        ],
      ),
      body: !_isOnline
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28.0),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.cloud_off_rounded,
                          size: 54,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Peta Membutuhkan Internet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Fitur Google Maps & pencarian alamat akurat membutuhkan sambungan internet aktif.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: _isCheckingConnection
                              ? null
                              : _checkPermissionsAndGetLocation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          icon: _isCheckingConnection
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            _isCheckingConnection
                                ? 'Memeriksa...'
                                : 'Coba Sambungkan',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Stack(
              children: [
                // Widget utama Peta Google Maps Asli
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition != null
                        ? LatLng(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                          )
                        : _defaultLocation,
                    zoom: 15.0,
                  ),
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                  },
                  markers: _markers,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),

                // Card melayang di bagian bawah untuk menampilkan informasi alamat
                Positioned(
                  bottom: 20,
                  left: 16,
                  right: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A)
                              .withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Color(0xFF2563EB),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Lokasi Terdeteksi",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  if (_currentPosition != null)
                                    Text(
                                      '${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: _checkPermissionsAndGetLocation,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.refresh_rounded,
                                  color: Color(0xFF2563EB),
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(context).size.height * 0.18,
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              _currentAddress,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF334155),
                                height: 1.45,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
