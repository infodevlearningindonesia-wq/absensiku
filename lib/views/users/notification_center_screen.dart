import 'package:flutter/material.dart';
import 'package:absensiku/models/notification_item.dart';
import 'package:absensiku/services/notification_helper.dart';
import 'package:absensiku/services/network_helper.dart';
import 'package:absensiku/database/db_helper.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NotificationCenterScreen(),
      ),
    );
  }

  static Future<void> showAsBottomSheet(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => const _NotificationCenterBottomSheetContent(),
    );
  }

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  List<NotificationItem> _notifications = [];
  bool _isLoading = true;
  String _selectedFilter = 'all'; // 'all', 'unread', 'presensi', 'network_sync'

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    final list = await AppNotificationHelper.getNotificationHistory();
    if (mounted) {
      setState(() {
        _notifications = list;
        _isLoading = false;
      });
    }

    // Otomatis tandai semua notifikasi sebagai sudah dibaca saat membuka riwayat (seperti YouTube)
    await AppNotificationHelper.markAllAsRead();
  }

  List<NotificationItem> get _filteredNotifications {
    switch (_selectedFilter) {
      case 'unread':
        return _notifications.where((item) => !item.isRead).toList();
      case 'system':
        return _notifications
            .where((item) =>
                item.category == 'system' ||
                item.category == 'network_online' ||
                item.category == 'network_offline' ||
                item.category == 'sync')
            .toList();
      case 'entry_update':
        return _notifications
            .where((item) =>
                item.category == 'login' ||
                item.category == 'update')
            .toList();
      default:
        return _notifications;
    }
  }

  int get _unreadCount => _notifications.where((item) => !item.isRead).length;

  Future<void> _markAsRead(NotificationItem item) async {
    if (!item.isRead) {
      await AppNotificationHelper.markAsRead(item.id);
      setState(() {
        final index = _notifications.indexWhere((n) => n.id == item.id);
        if (index != -1) {
          _notifications[index] = _notifications[index].copyWith(isRead: true);
        }
      });
    }
  }

  Future<void> _markAllAsRead() async {
    await AppNotificationHelper.markAllAsRead();
    setState(() {
      _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Semua notifikasi telah ditandai sebagai dibaca'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteNotification(NotificationItem item) async {
    await AppNotificationHelper.deleteNotification(item.id);
    setState(() {
      _notifications.removeWhere((n) => n.id == item.id);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Notifikasi dihapus'),
          action: SnackBarAction(
            label: 'Urungkan',
            onPressed: () async {
              await AppNotificationHelper.addNotificationHistory(item);
              _loadNotifications();
            },
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _confirmClearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Hapus Riwayat?'),
          ],
        ),
        content: const Text(
          'Semua riwayat notifikasi sebelumnya akan dihapus secara permanen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus Semua'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AppNotificationHelper.clearNotificationHistory();
      setState(() {
        _notifications.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Riwayat notifikasi berhasil dikosongkan')),
        );
      }
    }
  }

  void _showNotificationDetail(NotificationItem item) {
    _markAsRead(item);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.60,
        minChildSize: 0.40,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                controller: scrollController,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: item.color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(item.iconData, color: item.color, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.timeAgoFormatted,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    Text(
                      item.message,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _deleteNotification(item);
                          },
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                          label: const Text('Hapus', style: TextStyle(color: Colors.redAccent)),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Tutup'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredNotifications;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Notifikasi', style: TextStyle(fontWeight: FontWeight.bold)),
            if (_unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        elevation: 0,
        actions: [
          if (_notifications.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onSelected: (val) {
                if (val == 'read_all') {
                  _markAllAsRead();
                } else if (val == 'clear_all') {
                  _confirmClearAll();
                } else if (val == 'test_notif') {
                  _sendTestNotification();
                }
              },
              itemBuilder: (ctx) => [
                if (_unreadCount > 0)
                  const PopupMenuItem(
                    value: 'read_all',
                    child: Row(
                      children: [
                        Icon(Icons.done_all_rounded, size: 20, color: Colors.blueAccent),
                        SizedBox(width: 10),
                        Text('Tandai semua dibaca'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'test_notif',
                  child: Row(
                    children: [
                      Icon(Icons.notifications_active_outlined, size: 20, color: Colors.amber),
                      SizedBox(width: 10),
                      Text('Kirim Notifikasi Uji'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.redAccent),
                      SizedBox(width: 10),
                      Text('Hapus semua riwayat', style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              child: Column(
                children: [
                  // Filter Chips (YouTube style: Semua, Belum Dibaca, Presensi, Jaringan & Sync)
                  _buildFilterChips(),

                  // List Notifikasi
                  Expanded(
                    child: filtered.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) => const Divider(
                              height: 1,
                              thickness: 0.8,
                              indent: 72,
                              color: Color(0xFFE2E8F0),
                            ),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              return _buildNotificationTile(item);
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildChip(
              label: 'Semua',
              value: 'all',
              count: _notifications.length,
            ),
            const SizedBox(width: 8),
            _buildChip(
              label: 'Belum Dibaca',
              value: 'unread',
              count: _unreadCount,
              badgeColor: Colors.redAccent,
            ),
            const SizedBox(width: 8),
            _buildChip(
              label: 'Informasi Sistem',
              value: 'system',
            ),
            const SizedBox(width: 8),
            _buildChip(
              label: 'Masuk & Update',
              value: 'entry_update',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required String value,
    int? count,
    Color? badgeColor,
  }) {
    final isSelected = _selectedFilter == value;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = value;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.grey.shade300,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : (badgeColor ?? Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : (badgeColor != null ? Colors.white : Colors.black87),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationTile(NotificationItem item) {
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.redAccent,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 24),
            SizedBox(width: 6),
            Text(
              'Hapus',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      onDismissed: (direction) {
        _deleteNotification(item);
      },
      child: Material(
        color: item.isRead ? Colors.transparent : Colors.blue.withValues(alpha: 0.05),
        child: InkWell(
          onTap: () => _showNotificationDetail(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar / Icon Notifikasi (seperti thumbnail / icon YouTube)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(item.iconData, color: item.color, size: 22),
                ),
                const SizedBox(width: 14),

                // Konten Notifikasi
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight:
                                    item.isRead ? FontWeight.w600 : FontWeight.bold,
                                color: item.isRead ? Colors.black87 : const Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.timeAgoFormatted,
                            style: TextStyle(
                              fontSize: 11,
                              color: item.isRead ? Colors.grey[500] : Colors.blueAccent,
                              fontWeight:
                                  item.isRead ? FontWeight.normal : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.message,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: item.isRead ? Colors.grey[700] : Colors.black87,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Indikator Belum Dibaca (Titik Biru seperti YouTube/Gmail)
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!item.isRead)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6, bottom: 4),
                        decoration: const BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                        ),
                      )
                    else
                      const SizedBox(height: 18),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, size: 16, color: Colors.grey[400]),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onSelected: (val) {
                        if (val == 'toggle_read') {
                          if (item.isRead) {
                            // Tandai belum dibaca
                            final updated = item.copyWith(isRead: false);
                            AppNotificationHelper.addNotificationHistory(updated);
                            _loadNotifications();
                          } else {
                            _markAsRead(item);
                          }
                        } else if (val == 'delete') {
                          _deleteNotification(item);
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'toggle_read',
                          child: Row(
                            children: [
                              Icon(
                                item.isRead
                                    ? Icons.mark_email_unread_outlined
                                    : Icons.mark_email_read_outlined,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(item.isRead
                                  ? 'Tandai belum dibaca'
                                  : 'Tandai sudah dibaca'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                              SizedBox(width: 8),
                              Text('Hapus notifikasi ini',
                                  style: TextStyle(color: Colors.redAccent)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  size: 48,
                  color: Colors.blueAccent,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _selectedFilter == 'unread'
                    ? 'Tidak Ada Notifikasi Belum Dibaca'
                    : 'Belum Ada Notifikasi',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _selectedFilter == 'unread'
                    ? 'Semua pemberitahuan telah Anda baca.'
                    : 'Riwayat aktivitas saat masuk, informasi sistem, status jaringan, dan pembaruan aplikasi akan tersimpan di sini.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _sendTestNotification,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Kirim Notifikasi Uji'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sendTestNotification() {
    AppNotificationHelper.showNotification(
      title: 'Uji Notifikasi Absensiku',
      message: 'Pemberitahuan berhasil dikirim dan tersimpan di riwayat!',
      icon: Icons.notifications_active_rounded,
      backgroundColor: const Color(0xFF1E293B),
      iconColor: Colors.amberAccent,
      category: 'system',
    );
    _loadNotifications();
  }
}

/// Konten BottomSheet Interaktif (Pusat Notifikasi Cepat)
class _NotificationCenterBottomSheetContent extends StatefulWidget {
  const _NotificationCenterBottomSheetContent();

  @override
  State<_NotificationCenterBottomSheetContent> createState() =>
      _NotificationCenterBottomSheetContentState();
}

class _NotificationCenterBottomSheetContentState
    extends State<_NotificationCenterBottomSheetContent> {
  List<NotificationItem> _recentNotifications = [];
  bool _isLoading = true;
  bool _isOnline = true;
  int _unsyncedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final isOnline = await NetworkHelper.hasInternetConnection();
    final notifs = await AppNotificationHelper.getNotificationHistory();
    final unsynced = await DatabaseHelper.instance.getUnsyncedAbsensi();

    if (mounted) {
      setState(() {
        _isOnline = isOnline;
        _recentNotifications = notifs;
        _unsyncedCount = unsynced.length;
        _isLoading = false;
      });
    }

    // Otomatis tandai semua notifikasi sebagai sudah dibaca saat membuka riwayat (seperti YouTube)
    await AppNotificationHelper.markAllAsRead();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.50,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle Bar
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),

                // Header BottomSheet
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.notifications_active,
                            color: Colors.blueAccent, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pusat Notifikasi & Riwayat',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Riwayat notifikasi & status jaringan terkini',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Status Bar Singkat (Online/Offline & Sync)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      // Status Jaringan
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _isOnline ? Colors.green.shade50 : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _isOnline ? Colors.green.shade200 : Colors.red.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isOnline ? Icons.wifi : Icons.wifi_off,
                                size: 16,
                                color: _isOnline ? Colors.green.shade700 : Colors.red.shade700,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _isOnline ? 'Online' : 'Offline',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _isOnline
                                        ? Colors.green.shade900
                                        : Colors.red.shade900,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Status Antrean Sync
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.cloud_done_rounded,
                                  size: 16, color: Colors.blueAccent),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _unsyncedCount == 0 ? 'Cloud Sinkron' : '$_unsyncedCount Belum',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueAccent,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Header Section Riwayat
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Riwayat Pemberitahuan',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF475569),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          NotificationCenterScreen.show(context);
                        },
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Lihat Semua',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent,
                              ),
                            ),
                            Icon(Icons.chevron_right, size: 16, color: Colors.blueAccent),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 16),

                // List Notifikasi Terbaru (Scrollable with scrollController)
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _recentNotifications.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.notifications_none,
                                        size: 40, color: Colors.grey[400]),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Belum ada riwayat notifikasi',
                                      style: TextStyle(fontSize: 13, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _recentNotifications.length > 5
                                  ? 5
                                  : _recentNotifications.length,
                              separatorBuilder: (ctx, i) => const Divider(
                                height: 1,
                                thickness: 0.7,
                                indent: 56,
                                color: Color(0xFFF1F5F9),
                              ),
                              itemBuilder: (ctx, i) {
                                final item = _recentNotifications[i];
                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () async {
                                    if (!item.isRead) {
                                      await AppNotificationHelper.markAsRead(item.id);
                                      _loadData();
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 10),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: item.color.withValues(alpha: 0.12),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(item.iconData,
                                              color: item.color, size: 18),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      item.title,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: item.isRead
                                                            ? FontWeight.w600
                                                            : FontWeight.bold,
                                                        color: Colors.black87,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Text(
                                                    item.timeAgoFormatted,
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      color: Colors.grey[500],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                item.message,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[700],
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!item.isRead)
                                          Container(
                                            width: 7,
                                            height: 7,
                                            margin: const EdgeInsets.only(
                                                left: 6, top: 6),
                                            decoration: const BoxDecoration(
                                              color: Colors.blueAccent,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),

                // Tombol Uji Notifikasi & Buka Pengaturan
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            AppNotificationHelper.showNotification(
                              title: 'Uji Notifikasi Absensiku',
                              message: 'Layanan notifikasi perangkat berjalan lancar!',
                              icon: Icons.notifications_active_rounded,
                              backgroundColor: const Color(0xFF1E293B),
                              iconColor: Colors.amberAccent,
                              category: 'system',
                            );
                            _loadData();
                          },
                          icon: const Icon(Icons.notifications_active_outlined, size: 16),
                          label: const Text('Uji Notif', style: TextStyle(fontSize: 12.5)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            NotificationCenterScreen.show(context);
                          },
                          icon: const Icon(Icons.inbox_rounded, size: 16),
                          label: const Text('Buka Semua Riwayat',
                              style: TextStyle(fontSize: 12.5)),
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
    );
  }
}
