import 'package:flutter/material.dart';
import '../../core/services/sync_service.dart';
import '../../core/theme/field_theme.dart';
import '../../data/local/database_helper.dart';

/// Senkronizasyon durumu ve kontrol ekrani
/// Bekleyen, senkronize edilmis ve basarisiz kayitlarin yonetimi
class SenkronizasyonSayfasi extends StatefulWidget {
  final VoidCallback? onSyncComplete;

  const SenkronizasyonSayfasi({super.key, this.onSyncComplete});

  @override
  State<SenkronizasyonSayfasi> createState() => _SenkronizasyonSayfasiState();
}

class _SenkronizasyonSayfasiState extends State<SenkronizasyonSayfasi> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();

  Map<String, int> _syncStats = {'pending': 0, 'synced': 0, 'failed': 0};
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isAutoSyncEnabled = true;
  String? _lastSyncTime;
  String? _syncMessage;

  @override
  void initState() {
    super.initState();
    _loadSyncStats();
  }

  Future<void> _loadSyncStats() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final Map<String, int> stats = await _dbHelper.getSyncStats();
      if (mounted) {
        setState(() {
          _syncStats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleManualSync() async {
    setState(() {
      _isSyncing = true;
      _syncMessage = null;
    });
    try {
      final SyncResult result = await _syncService.syncNow();
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _lastSyncTime = _formatTime(DateTime.now());
          _syncMessage = 'Senkronizasyon tamamlandi: '
              '${result.successCount} basarili, '
              '${result.failedCount} basarisiz';
        });
        await _loadSyncStats();
        widget.onSyncComplete?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncMessage = 'Senkronizasyon hatasi: $e';
        });
      }
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Senkronizasyon'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSyncStats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSyncStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSyncOverview(),
                    const SizedBox(height: 24),
                    _buildSyncButton(),
                    const SizedBox(height: 16),
                    if (_syncMessage != null) _buildSyncMessage(),
                    const SizedBox(height: 24),
                    _buildAutoSyncToggle(),
                    const SizedBox(height: 24),
                    _buildSyncInfo(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSyncOverview() {
    final int total = _syncStats['pending']! + _syncStats['synced']! + _syncStats['failed']!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Senkronizasyon Durumu',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildStatCard(
              'Bekleyen',
              _syncStats['pending']!,
              FieldTheme.syncPending,
              Icons.schedule,
            ),
            const SizedBox(width: 8),
            _buildStatCard(
              'Senkronize',
              _syncStats['synced']!,
              FieldTheme.syncDone,
              Icons.check_circle,
            ),
            const SizedBox(width: 8),
            _buildStatCard(
              'Basarisiz',
              _syncStats['failed']!,
              FieldTheme.syncFailed,
              Icons.error,
            ),
          ],
        ),
        if (total > 0) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total > 0 ? _syncStats['synced']! / total : 0,
              minHeight: 8,
              backgroundColor: FieldTheme.dividerColor,
              valueColor: const AlwaysStoppedAnimation<Color>(FieldTheme.syncDone),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_syncStats['synced']}/$total senkronize edildi',
            style: const TextStyle(
              fontSize: 14,
              color: FieldTheme.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatCard(String label, int count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncButton() {
    final bool hasPending = (_syncStats['pending'] ?? 0) > 0 ||
        (_syncStats['failed'] ?? 0) > 0;
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        onPressed: hasPending && !_isSyncing ? _handleManualSync : null,
        icon: _isSyncing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FieldTheme.textOnPrimary,
                ),
              )
            : const Icon(Icons.sync, size: 24),
        label: Text(
          _isSyncing
              ? 'Senkronize Ediliyor...'
              : hasPending
                  ? 'Simdi Senkronize Et'
                  : 'Tum Veriler Guncel',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildSyncMessage() {
    final bool isError = _syncMessage?.contains('hata') ?? false;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError
            ? FieldTheme.errorRed.withValues(alpha: 0.1)
            : FieldTheme.successGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError
              ? FieldTheme.errorRed.withValues(alpha: 0.3)
              : FieldTheme.successGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? FieldTheme.errorRed : FieldTheme.successGreen,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _syncMessage!,
              style: TextStyle(
                color: isError ? FieldTheme.errorRed : FieldTheme.successGreen,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoSyncToggle() {
    return Card(
      child: SwitchListTile(
        title: const Text('Otomatik Senkronizasyon'),
        subtitle: Text(
          _isAutoSyncEnabled
              ? 'Baglanti mevcut oldugunda otomatik senkronize eder'
              : 'Manuel senkronizasyon gerekir',
        ),
        value: _isAutoSyncEnabled,
        activeColor: FieldTheme.primaryGreen,
        onChanged: (bool value) {
          setState(() {
            _isAutoSyncEnabled = value;
          });
          if (value) {
            _syncService.startAutoSync();
          } else {
            _syncService.stopAutoSync();
          }
        },
      ),
    );
  }

  Widget _buildSyncInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bilgi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.schedule, 'Son senkronizasyon',
                _lastSyncTime ?? 'Henuz yapilmadi'),
            const Divider(),
            _buildInfoRow(Icons.wifi, 'Senkronizasyon yontemi',
                'WiFi veya Mobil Veri'),
            const Divider(),
            _buildInfoRow(Icons.repeat, 'Otomatik tekrar',
                'Basarisiz kayitlar 3 kez denenir'),
            const Divider(),
            _buildInfoRow(Icons.batch_prediction, 'Toplu gonderi',
                'Ayni anda max 5 kayit'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: FieldTheme.textSecondary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: FieldTheme.textSecondary,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
