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
      NetworkHelper.showOfflineDialog(context, featureName: 'Peta Lokasi Google Maps');
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
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
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
          CameraPosition(
            target: currentLatLng,
            zoom: 16.0,
          ),
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
      appBar: AppBar(title: const Text('Peta Lokasi Presensi')),
      body: !_isOnline
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.cloud_off_rounded,
                        size: 72,
                        color: Colors.red.shade400,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Peta Tidak Tersedia Saat Offline',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Fitur Google Maps dan pelacakan GPS akurat membutuhkan sambungan internet aktif seperti aplikasi online lainnya.',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _isCheckingConnection ? null : _checkPermissionsAndGetLocation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _isCheckingConnection
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(_isCheckingConnection ? 'Memeriksa...' : 'Coba Lagi'),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                // Widget utama Peta Google Maps Asli
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition != null
                        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                        : _defaultLocation,
                    zoom: 15.0,
                  ),
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                  },
                  markers: _markers,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                  mapToolbarEnabled: false,
                ),

          // Card melayang di bagian bawah untuk menampilkan informasi alamat (aman dari overflow & overlap)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            "Alamat Anda Saat Ini:",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.my_location, color: Colors.blueAccent),
                          tooltip: 'Perbarui Lokasi',
                          onPressed: _checkPermissionsAndGetLocation,
                        ),
                      ],
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.22,
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          _currentAddress,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    /*
                    // COMENT YANG LAUNCHER
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _openInGoogleMaps,
                        icon: const Icon(Icons.navigation, size: 18),
                        label: const Text("Buka di Google Maps"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    */
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}