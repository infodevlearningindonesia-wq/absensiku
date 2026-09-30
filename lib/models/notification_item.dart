import 'package:flutter/material.dart';

class NotificationItem {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final String category; // 'presensi_masuk', 'presensi_keluar', 'network_online', 'network_offline', 'sync', 'reminder', 'system'
  final bool isRead;
  final int? iconCodePoint;
  final int? colorValue;

  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    this.category = 'system',
    this.isRead = false,
    this.iconCodePoint,
    this.colorValue,
  });

  IconData get iconData {
    switch (category) {
      case 'login':
        return Icons.verified_user_rounded;
      case 'update':
        return Icons.system_update_rounded;
      case 'presensi_masuk':
        return Icons.login_rounded;
      case 'presensi_keluar':
        return Icons.logout_rounded;
      case 'network_online':
        return Icons.wifi_rounded;
      case 'network_offline':
        return Icons.wifi_off_rounded;
      case 'sync':
        return Icons.cloud_done_rounded;
      case 'reminder':
        return Icons.access_time_filled_rounded;
      default:
        if (iconCodePoint != null) {
          // ignore: non_const_argument_for_const_parameter
          return IconData(iconCodePoint!, fontFamily: 'MaterialIcons');
        }
        return Icons.notifications_rounded;
    }
  }

  Color get color {
    if (colorValue != null) {
      return Color(colorValue!);
    }
    switch (category) {
      case 'login':
        return const Color(0xFF0D9488); // Teal
      case 'update':
        return const Color(0xFF8B5CF6); // Purple
      case 'presensi_masuk':
        return const Color(0xFF10B981); // Emerald Green
      case 'presensi_keluar':
        return const Color(0xFFF59E0B); // Amber Orange
      case 'network_online':
        return const Color(0xFF059669); // Dark Green
      case 'network_offline':
        return const Color(0xFFEF4444); // Red
      case 'sync':
        return const Color(0xFF3B82F6); // Blue
      case 'reminder':
        return const Color(0xFF8B5CF6); // Purple
      default:
        return const Color(0xFF6366F1); // Indigo
    }
  }

  String get timeAgoFormatted {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 45) {
      return 'Baru saja';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} mnt lalu';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} jam lalu';
    } else if (difference.inDays == 1) {
      final hour = timestamp.hour.toString().padLeft(2, '0');
      final minute = timestamp.minute.toString().padLeft(2, '0');
      return 'Kemarin, $hour:$minute WIB';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} hr lalu';
    } else {
      final day = timestamp.day.toString().padLeft(2, '0');
      final monthNames = [
        'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
        'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
      ];
      final month = monthNames[timestamp.month - 1];
      final year = timestamp.year;
      final hour = timestamp.hour.toString().padLeft(2, '0');
      final minute = timestamp.minute.toString().padLeft(2, '0');
      return '$day $month $year • $hour:$minute';
    }
  }

  NotificationItem copyWith({
    String? id,
    String? title,
    String? message,
    DateTime? timestamp,
    String? category,
    bool? isRead,
    int? iconCodePoint,
    int? colorValue,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      category: category ?? this.category,
      isRead: isRead ?? this.isRead,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'category': category,
      'isRead': isRead,
      'iconCodePoint': iconCodePoint,
      'colorValue': colorValue,
    };
  }

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      category: json['category'] as String? ?? 'system',
      isRead: json['isRead'] as bool? ?? false,
      iconCodePoint: json['iconCodePoint'] as int?,
      colorValue: json['colorValue'] as int?,
    );
  }
}
