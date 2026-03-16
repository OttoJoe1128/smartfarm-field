import 'package:flutter/material.dart';
import '../../core/services/sync_service.dart';
import '../../core/theme/field_theme.dart';
import '../../data/local/database_helper.dart';
import '../../data/models/field_asset.dart';

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
  List<FieldAsset> _allAssets = <FieldAsset>[];
  String? _selectedAssetIdForDevice;
  OnboardingState? _onboardingState;
  List<Map<String, dynamic>> _alerts = <Map<String, dynamic>>[];
  bool _isLifecycleLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSyncStats();
    _loadPhaseThreeData();
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

  Future<void> _loadPhaseThreeData() async {
    final List<FieldAsset> assets = await _dbHelper.getAllAssets();
    final Map<String, dynamic> alertsResponse = await _syncService.listAlerts();
    final List<Map<String, dynamic>> alertItems =
        ((alertsResponse['data'] as Map<String, dynamic>?)?['items'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            <Map<String, dynamic>>[];
    if (!mounted) {
      return;
    }
    setState(() {
      _allAssets = assets;
      if (_selectedAssetIdForDevice == null && assets.isNotEmpty) {
        _selectedAssetIdForDevice = assets.first.id;
      }
      _alerts = alertItems;
    });
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

  Future<void> _handleRegisterDevice() async {
    if (_selectedAssetIdForDevice == null || _selectedAssetIdForDevice!.isEmpty) {
      setState(() {
        _syncMessage = 'Onboarding icin once bir varlik secin';
      });
      return;
    }
    setState(() {
      _isLifecycleLoading = true;
    });
    try {
      final OnboardingState onboardingState =
          await _syncService.registerOrRefreshDevice(
        assetId: _selectedAssetIdForDevice!,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _onboardingState = onboardingState;
        _syncMessage = 'Cihaz kaydi guncellendi';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncMessage = 'Cihaz kayit hatasi: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLifecycleLoading = false;
        });
      }
    }
  }

  Future<void> _handleRotateKey() async {
    setState(() {
      _isLifecycleLoading = true;
    });
    try {
      final OnboardingState onboardingState = await _syncService.rotateDeviceKey();
      if (!mounted) {
        return;
      }
      setState(() {
        _onboardingState = onboardingState;
        _syncMessage = 'Cihaz anahtari yenilendi';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncMessage = 'Rotate-key hatasi: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLifecycleLoading = false;
        });
      }
    }
  }

  Future<void> _handleAckAlert(Map<String, dynamic> alert) async {
    final String alertId =
        (alert['alert_id'] as String?) ?? (alert['id'] as String?) ?? '';
    if (alertId.isEmpty) {
      return;
    }
    setState(() {
      _isLifecycleLoading = true;
    });
    final Map<String, dynamic> response = await _syncService.ackAlert(
      alertId: alertId,
      operator: 'field_user',
    );
    await _loadPhaseThreeData();
    if (!mounted) {
      return;
    }
    setState(() {
      _isLifecycleLoading = false;
      _syncMessage = (response['status'] as String?) == 'ok'
          ? 'Alarm onaylandi'
          : 'Alarm ack hatasi: ${response['error_code'] ?? response['message']}';
    });
  }

  Future<void> _handleCloseAlert(Map<String, dynamic> alert) async {
    final String alertId =
        (alert['alert_id'] as String?) ?? (alert['id'] as String?) ?? '';
    if (alertId.isEmpty) {
      return;
    }
    final TextEditingController reasonController = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Alarm Kapat'),
          content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(
              labelText: 'Kapatma nedeni',
              hintText: 'Ornek: Sahada kontrol edildi',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Iptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kapat'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _isLifecycleLoading = true;
    });
    final Map<String, dynamic> response = await _syncService.closeAlert(
      alertId: alertId,
      operator: 'field_user',
      reason: reasonController.text.trim(),
    );
    reasonController.dispose();
    await _loadPhaseThreeData();
    if (!mounted) {
      return;
    }
    setState(() {
      _isLifecycleLoading = false;
      _syncMessage = (response['status'] as String?) == 'ok'
          ? 'Alarm kapatildi'
          : 'Alarm close hatasi: ${response['error_code'] ?? response['message']}';
    });
  }

  Future<void> _runE2ESmokeTest() async {
    setState(() {
      _isLifecycleLoading = true;
      _syncMessage = 'E2E smoke test calisiyor...';
    });
    final Map<String, dynamic> result = await _syncService.runPhaseThreeE2ESmoke();
    await _loadPhaseThreeData();
    if (!mounted) {
      return;
    }
    setState(() {
      _isLifecycleLoading = false;
      _syncMessage = (result['status'] as String?) == 'ok'
          ? 'E2E smoke basarili: ${result['ws_event_type']} (${result['ws_schema_version']})'
          : 'E2E smoke hatasi: ${result['error_code'] ?? result['message']}';
    });
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
                    _buildOnboardingCard(),
                    const SizedBox(height: 24),
                    _buildWebSocketOpsCard(),
                    const SizedBox(height: 24),
                    _buildAlarmLifecycleCard(),
                    const SizedBox(height: 24),
                    _buildE2EAutomationCard(),
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
        activeThumbColor: FieldTheme.primaryGreen,
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

  Widget _buildOnboardingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Onboarding UX',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedAssetIdForDevice,
              items: _allAssets.map((FieldAsset asset) {
                return DropdownMenuItem<String>(
                  value: asset.id,
                  child: Text('${asset.name} (${asset.id.substring(0, 6)})'),
                );
              }).toList(),
              onChanged: (String? value) {
                setState(() {
                  _selectedAssetIdForDevice = value;
                });
              },
              decoration: const InputDecoration(
                labelText: 'Onboarding Varligi',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _isLifecycleLoading ? null : _handleRegisterDevice,
                  icon: const Icon(Icons.device_hub),
                  label: const Text('Device Register'),
                ),
                OutlinedButton.icon(
                  onPressed: _isLifecycleLoading ? null : _handleRotateKey,
                  icon: const Icon(Icons.vpn_key),
                  label: const Text('Rotate Key'),
                ),
              ],
            ),
            if (_onboardingState != null) ...[
              const SizedBox(height: 12),
              Text('Device ID: ${_onboardingState!.deviceId}'),
              Text('Pub Topic: ${_onboardingState!.telemetryPublishTopic ?? '-'}'),
              Text('Sub Topic: ${_onboardingState!.commandSubscribeTopic ?? '-'}'),
              Text('Api Key: ${_onboardingState!.apiKeyMasked ?? '-'}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWebSocketOpsCard() {
    final bool connected = _syncService.isLiveStreamActive;
    final String reconnectHint = _syncService.wsReconnectHint ?? '-';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WS Operasyonel Davranis',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Text('Schema Version: ${_syncService.wsSchemaVersion}'),
            Text('Heartbeat Timeout: ${_syncService.wsHeartbeatTimeoutSeconds}s'),
            Text('Reconnect Hint: $reconnectHint'),
            Text('Baglanti: ${connected ? 'Aktif' : 'Pasif'}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _isLifecycleLoading
                      ? null
                      : () => _syncService.startLiveEventStream(),
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('WS Baslat'),
                ),
                OutlinedButton.icon(
                  onPressed: _isLifecycleLoading
                      ? null
                      : () => _syncService.stopLiveEventStream(),
                  icon: const Icon(Icons.stop_circle),
                  label: const Text('WS Durdur'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmLifecycleCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Alarm Lifecycle (ack/close)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            if (_alerts.isEmpty)
              const Text('Aktif alarm yok')
            else
              ..._alerts.take(5).map((Map<String, dynamic> alert) {
                final String alertId =
                    (alert['alert_id'] as String?) ?? (alert['id'] as String?) ?? '-';
                final String level = (alert['level'] as String?) ?? '-';
                final String status = (alert['status'] as String?) ?? '-';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: FieldTheme.backgroundLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Alarm: $alertId'),
                      Text('Seviye: $level | Durum: $status'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _isLifecycleLoading
                                ? null
                                : () => _handleAckAlert(alert),
                            child: const Text('Ack'),
                          ),
                          ElevatedButton(
                            onPressed: _isLifecycleLoading
                                ? null
                                : () => _handleCloseAlert(alert),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildE2EAutomationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Telemetry -> WS -> UI E2E',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            const Text(
              'Tek tus ile telemetry ingest, ws event alimi ve UI badge projection kontrolu yapar.',
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLifecycleLoading ? null : _runE2ESmokeTest,
                icon: const Icon(Icons.science),
                label: const Text('E2E Smoke Testi Calistir'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
