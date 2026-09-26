import 'dart:io';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkHelper {
  // Cek apakah perangkat terhubung ke Wi-Fi / Data Seluler (Hardware Level)
  static Future<bool> isConnectedToNetwork() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  // Cek apakah perangkat terhubung ke internet aktif
  static Future<bool> hasInternetConnection() async {
    // 0. Cek level hardware konektivitas (Wi-Fi / Seluler)
    final hasHardwareConn = await isConnectedToNetwork();
    if (!hasHardwareConn) {
      return false;
    }

    // 1. Cek DNS lookup google.com
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(milliseconds: 2000));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {}

    // 2. Fallback langsung ke IP DNS Publik Cloudflare (1.1.1.1)
    try {
      final socket = await Socket.connect(
        '1.1.1.1',
        53,
        timeout: const Duration(milliseconds: 2000),
      );
      socket.destroy();
      return true;
    } catch (_) {}

    // 3. Fallback langsung ke IP DNS Publik Google (8.8.8.8)
    try {
      final socket2 = await Socket.connect(
        '8.8.8.8',
        53,
        timeout: const Duration(milliseconds: 2000),
      );
      socket2.destroy();
      return true;
    } catch (_) {}

    // Jika hardware Wi-Fi / Seluler aktif namun probe timeout (misal background mode), anggap terhubung
    return hasHardwareConn;
  }

  // Tampilkan Dialog saat fitur membutuhkan koneksi internet (Fitur mati saat offline)
  static void showOfflineDialog(BuildContext context, {String featureName = 'Fitur ini'}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.wifi_off, color: Colors.red, size: 26),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tidak Ada Internet',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$featureName memerlukan koneksi internet aktif.',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            const SizedBox(height: 8),
            const Text(
              'Aplikasi saat ini dalam mode offline. Harap periksa jaringan Wi-Fi atau data seluler Anda untuk menggunakan fitur ini.',
              style: TextStyle(fontSize: 12.5, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Mengerti'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Widget Banner Offline yang dapat disematkan di atas layar
  static Widget buildOfflineBanner({VoidCallback? onRetry}) {
    return Container(
      width: double.infinity,
      color: Colors.red.shade700,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Mode Offline • Fitur online dinonaktifkan',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Coba Lagi',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
