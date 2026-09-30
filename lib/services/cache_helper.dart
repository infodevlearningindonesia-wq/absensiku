import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class CleanCacheResult {
  final bool success;
  final String freedSizeFormatted;
  final int filesDeletedCount;
  final String message;

  CleanCacheResult({
    required this.success,
    required this.freedSizeFormatted,
    required this.filesDeletedCount,
    required this.message,
  });
}

class AppCacheHelper {
  /// Menghitung total ukuran cache perangkat dan APK
  static Future<int> getCacheSizeBytes() async {
    int totalBytes = 0;

    try {
      // 1. Direktori Temporary / Cache Perangkat
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        totalBytes += await _getDirSize(tempDir);
      }

      // 2. Direktori Cache Aplikasi
      try {
        final appCacheDir = await getApplicationCacheDirectory();
        if (appCacheDir.existsSync()) {
          totalBytes += await _getDirSize(appCacheDir);
        }
      } catch (_) {}
    } catch (_) {}

    return totalBytes;
  }

  /// Menghitung ukuran direktori secara rekursif
  static Future<int> _getDirSize(Directory dir) async {
    int size = 0;
    try {
      if (!dir.existsSync()) return 0;
      final entities = dir.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
          try {
            size += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return size;
  }

  /// Format ukuran byte ke string terbaca (KB / MB)
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// Ambil ukuran cache dalam bentuk teks ringkas (contoh: "14.5 MB")
  static Future<String> getFormattedCacheSize() async {
    final bytes = await getCacheSizeBytes();
    return formatBytes(bytes);
  }

  /// Proses Pembersih Menyeluruh untuk Cache Perangkat, Memori, & APK
  static Future<CleanCacheResult> cleanAllCache() async {
    int totalFreedBytes = 0;
    int deletedCount = 0;

    try {
      // 1. Bersihkan Image Cache Memori Flutter
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // 2. Bersihkan Temporary Directory Perangkat
      try {
        final tempDir = await getTemporaryDirectory();
        if (tempDir.existsSync()) {
          final entities = tempDir.listSync(recursive: false, followLinks: false);
          for (final entity in entities) {
            try {
              if (entity is File) {
                final len = await entity.length();
                await entity.delete();
                totalFreedBytes += len;
                deletedCount++;
              } else if (entity is Directory) {
                final dirSize = await _getDirSize(entity);
                await entity.delete(recursive: true);
                totalFreedBytes += dirSize;
                deletedCount++;
              }
            } catch (_) {}
          }
        }
      } catch (_) {}

      // 3. Bersihkan Application Cache Directory
      try {
        final appCacheDir = await getApplicationCacheDirectory();
        if (appCacheDir.existsSync()) {
          final entities = appCacheDir.listSync(recursive: false, followLinks: false);
          for (final entity in entities) {
            try {
              if (entity is File) {
                final len = await entity.length();
                await entity.delete();
                totalFreedBytes += len;
                deletedCount++;
              } else if (entity is Directory) {
                final dirSize = await _getDirSize(entity);
                await entity.delete(recursive: true);
                totalFreedBytes += dirSize;
                deletedCount++;
              }
            } catch (_) {}
          }
        }
      } catch (_) {}

      final formattedSize = formatBytes(totalFreedBytes);

      return CleanCacheResult(
        success: true,
        freedSizeFormatted: formattedSize,
        filesDeletedCount: deletedCount,
        message: totalFreedBytes > 0
            ? 'Berhasil membersihkan $formattedSize ruang penyimpanan dari cache perangkat & APK.'
            : 'Cache perangkat dan APK sudah dalam kondisi bersih optimal.',
      );
    } catch (e) {
      return CleanCacheResult(
        success: false,
        freedSizeFormatted: '0 KB',
        filesDeletedCount: deletedCount,
        message: 'Gagal membersihkan sebagian cache: $e',
      );
    }
  }
}
