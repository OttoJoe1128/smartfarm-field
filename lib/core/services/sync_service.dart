import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../data/local/database_helper.dart';
import '../../data/models/field_asset.dart';
import '../../data/models/fault_record.dart';
import '../../data/remote/saha_api_service.dart';
import '../config/api_config.dart';

/// Senkronizasyon sonucu
class SyncResult {
  final int successCount;
  final int failedCount;
  final List<String> errors;
  final List<String> errorCodes;
  final int? serverVersion;

  const SyncResult({
    required this.successCount,
    required this.failedCount,
    this.errors = const [],
    this.errorCodes = const [],
    this.serverVersion,
  });
}

/// Varlik batch senkronizasyon sonucu
class BatchAssetSyncResult {
  final int successCount;
  final int failedCount;
  final List<String> errors;
  final List<String> errorCodes;
  final int? serverVersion;
  const BatchAssetSyncResult({
    required this.successCount,
    required this.failedCount,
    this.errors = const [],
    this.errorCodes = const [],
    this.serverVersion,
  });
}

/// Ariza senkronizasyon sonucu
class FaultSyncResult {
  final bool isSuccess;
  final String? errorCode;
  final String? errorMessage;
  final int? serverVersion;
  const FaultSyncResult({
    required this.isSuccess,
    this.errorCode,
    this.errorMessage,
    this.serverVersion,
  });
}

/// Canli event projection durumu
class LiveProjectionState {
  final bool isConnected;
  final int reconnectAttempt;
  final int alertCount;
  final DateTime? lastEventAt;
  final String? lastEventType;
  final Map<String, Map<String, dynamic>> telemetryByAssetId;
  final Map<String, int> alertCountByAssetId;
  const LiveProjectionState({
    required this.isConnected,
    required this.reconnectAttempt,
    required this.alertCount,
    this.lastEventAt,
    this.lastEventType,
    this.telemetryByAssetId = const <String, Map<String, dynamic>>{},
    this.alertCountByAssetId = const <String, int>{},
  });
}

/// Faz 3 onboarding durumu
class OnboardingState {
  final String deviceId;
  final String? telemetryPublishTopic;
  final String? commandSubscribeTopic;
  final String? apiKeyMasked;
  final int? wsHeartbeatTimeoutSeconds;
  final String? wsSchemaVersion;
  const OnboardingState({
    required this.deviceId,
    this.telemetryPublishTopic,
    this.commandSubscribeTopic,
    this.apiKeyMasked,
    this.wsHeartbeatTimeoutSeconds,
    this.wsSchemaVersion,
  });
}

/// Offline-first senkronizasyon motoru
/// Baglanti durumunu dinler, toplu senkronizasyon yapar, hata yonetimi saglar
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SahaApiService _apiService = SahaApiService();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _autoSyncTimer;
  Timer? _liveReconnectTimer;
  Timer? _wsHeartbeatPingTimer;
  WebSocket? _liveWebSocket;
  bool _isSyncing = false;
  bool _isAutoSyncEnabled = false;
  bool _isLiveStreamActive = false;
  bool _shouldKeepLiveStream = false;
  int? _lastServerVersion;
  int _liveReconnectAttempt = 0;
  DateTime? _lastLiveEventAt;
  String? _lastLiveEventType;
  String _wsSchemaVersion = 'ws.live.telemetry.v1';
  int _wsHeartbeatTimeoutSeconds = 30;
  String? _wsReconnectHint;
  final List<Map<String, dynamic>> _liveAlerts = <Map<String, dynamic>>[];
  final Map<String, Map<String, dynamic>> _telemetryByAssetId =
      <String, Map<String, dynamic>>{};
  final Map<String, int> _alertCountByAssetId = <String, int>{};
  int? get lastServerVersion => _lastServerVersion;
  bool get isLiveStreamActive => _isLiveStreamActive;
  String get wsSchemaVersion => _wsSchemaVersion;
  int get wsHeartbeatTimeoutSeconds => _wsHeartbeatTimeoutSeconds;
  String? get wsReconnectHint => _wsReconnectHint;

  /// Senkronizasyon durumu akisi
  final StreamController<SyncResult> _syncResultController =
      StreamController<SyncResult>.broadcast();
  Stream<SyncResult> get syncResultStream => _syncResultController.stream;
  final StreamController<Map<String, dynamic>> _liveEventController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get liveEventStream => _liveEventController.stream;
  final StreamController<LiveProjectionState> _liveProjectionController =
      StreamController<LiveProjectionState>.broadcast();
  Stream<LiveProjectionState> get liveProjectionStream =>
      _liveProjectionController.stream;
  LiveProjectionState get liveProjectionSnapshot => LiveProjectionState(
        isConnected: _isLiveStreamActive,
        reconnectAttempt: _liveReconnectAttempt,
        alertCount: _liveAlerts.length,
        lastEventAt: _lastLiveEventAt,
        lastEventType: _lastLiveEventType,
        telemetryByAssetId: Map<String, Map<String, dynamic>>.from(
          _telemetryByAssetId,
        ),
        alertCountByAssetId: Map<String, int>.from(_alertCountByAssetId),
      );

  /// Otomatik senkronizasyonu baslat
  void startAutoSync() {
    _isAutoSyncEnabled = true;
    _startConnectivityListener();
    _startPeriodicSync();
  }

  /// Otomatik senkronizasyonu durdur
  void stopAutoSync() {
    _isAutoSyncEnabled = false;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// Baglanti durumu dinleyicisi
  void _startConnectivityListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final bool isConnected = results.any(
          (ConnectivityResult r) =>
              r == ConnectivityResult.wifi || r == ConnectivityResult.mobile,
        );
        if (isConnected && _isAutoSyncEnabled) {
          debugPrint('Baglanti algilandi, senkronizasyon baslatiliyor...');
          syncNow();
        }
      },
    );
  }

  /// Periyodik senkronizasyon (her 30 saniyede bir)
  void _startPeriodicSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(
      const Duration(seconds: ApiConfig.syncIntervalSeconds),
      (_) async {
        if (_isAutoSyncEnabled && !_isSyncing) {
          final bool isConnected = await _isOnline();
          if (isConnected) {
            syncNow();
          }
        }
      },
    );
  }

  /// Internet baglantisi var mi kontrol et
  Future<bool> _isOnline() async {
    final List<ConnectivityResult> results =
        await _connectivity.checkConnectivity();
    return results.any(
      (ConnectivityResult r) =>
          r == ConnectivityResult.wifi || r == ConnectivityResult.mobile,
    );
  }

  /// Manuel senkronizasyon tetikle
  Future<SyncResult> syncNow() async {
    if (_isSyncing) {
      return const SyncResult(successCount: 0, failedCount: 0);
    }
    _isSyncing = true;
    int successCount = 0;
    int failedCount = 0;
    final List<String> errors = [];
    final List<String> errorCodes = [];
    int? currentServerVersion = _lastServerVersion;
    try {
      final bool isConnected = await _isOnline();
      if (!isConnected) {
        return const SyncResult(
          successCount: 0,
          failedCount: 0,
          errors: ['Internet baglantisi yok'],
          errorCodes: ['NO_INTERNET'],
        );
      }
      // Bekleyen ve basarisiz kayitlari getir
      final List<FieldAsset> pendingAssets =
          await _dbHelper.getAssetsBySyncStatus(SyncStatus.pendingSync);
      final List<FieldAsset> failedAssets =
          await _dbHelper.getAssetsBySyncStatus(SyncStatus.syncFailed);
      final List<FieldAsset> allToSync = [...pendingAssets, ...failedAssets];
      if (allToSync.isNotEmpty) {
        // Batch isleme - ayni anda max 5 kayit
        for (int i = 0; i < allToSync.length; i += ApiConfig.maxBatchSize) {
          final int end = (i + ApiConfig.maxBatchSize < allToSync.length)
              ? i + ApiConfig.maxBatchSize
              : allToSync.length;
          final List<FieldAsset> batch = allToSync.sublist(i, end);
          final BatchAssetSyncResult batchResult = await _syncAssetBatch(batch);
          successCount += batchResult.successCount;
          failedCount += batchResult.failedCount;
          errors.addAll(batchResult.errors);
          errorCodes.addAll(batchResult.errorCodes);
          if (batchResult.serverVersion != null) {
            currentServerVersion = batchResult.serverVersion;
          }
        }
      }

      // ----------------------------------------------------------------------
      // Ariza Kayitlari Senkronizasyonu
      // ----------------------------------------------------------------------
      final List<FaultRecord> pendingFaults =
          await _dbHelper.getFaultsBySyncStatus(SyncStatus.pendingSync);
      final List<FaultRecord> failedFaults =
          await _dbHelper.getFaultsBySyncStatus(SyncStatus.syncFailed);
      final List<FaultRecord> allFaultsToSync = [...pendingFaults, ...failedFaults];

      if (allFaultsToSync.isNotEmpty) {
        debugPrint('Senkronize edilecek ariza kaydi sayisi: ${allFaultsToSync.length}');
        for (final FaultRecord fault in allFaultsToSync) {
          try {
            final FaultSyncResult faultResult = await _syncSingleFaultRecord(fault);
            if (faultResult.isSuccess) {
              successCount++;
            } else {
              failedCount++;
              errors.add('Ariza (${fault.description}): ${faultResult.errorMessage ?? 'Bilinmeyen hata'}');
              if (faultResult.errorCode != null) {
                errorCodes.add(faultResult.errorCode!);
              }
            }
            if (faultResult.serverVersion != null) {
              currentServerVersion = faultResult.serverVersion;
            }
          } catch (err) {
            failedCount++;
            errors.add('Ariza (${fault.description}): $err');
            errorCodes.add('FAULT_SYNC_EXCEPTION');
            debugPrint('Ariza sync hatasi (${fault.id}): $err');
          }
        }
      }
    } catch (e) {
      debugPrint('Genel sync hatasi: $e');
      errors.add('Genel hata: $e');
    } finally {
      _isSyncing = false;
    }
    final SyncResult result = SyncResult(
      successCount: successCount,
      failedCount: failedCount,
      errors: errors,
      errorCodes: errorCodes,
      serverVersion: currentServerVersion,
    );
    _lastServerVersion = currentServerVersion;
    _syncResultController.add(result);
    return result;
  }

  /// Varliklari toplu olarak senkronize et
  Future<BatchAssetSyncResult> _syncAssetBatch(List<FieldAsset> batch) async {
    final List<FieldAsset> assetsToSync = [];
    final Map<String, String> photoUrlsByAssetId = <String, String>{};
    for (final FieldAsset asset in batch) {
      String? photoUrl;
      if (asset.photoLocalPath != null && asset.photoUrl == null) {
        photoUrl = await _uploadPhotoToFirebase(asset.photoLocalPath!, asset.id);
      }
      final FieldAsset updatedAsset = photoUrl != null
          ? asset.copyWith(photoUrl: photoUrl)
          : asset;
      if (photoUrl != null) {
        photoUrlsByAssetId[asset.id] = photoUrl;
      }
      assetsToSync.add(updatedAsset);
    }
    final Map<String, dynamic> response = await _apiService.batchAddAssets(assetsToSync);
    final bool isBatchSuccess = (response['status'] as String?) == 'ok';
    if (isBatchSuccess) {
      for (final FieldAsset asset in batch) {
        await _dbHelper.updateSyncStatus(
          asset.id,
          SyncStatus.synced,
          photoUrl: photoUrlsByAssetId[asset.id],
        );
      }
      return BatchAssetSyncResult(
        successCount: batch.length,
        failedCount: 0,
        serverVersion: response['version'] as int?,
      );
    }
    for (final FieldAsset asset in batch) {
      await _handleSyncFailure(asset);
    }
    final String message = (response['message'] as String?) ?? 'Batch sync basarisiz';
    final String errorCode = (response['error_code'] as String?) ?? 'BATCH_SYNC_FAILED';
    return BatchAssetSyncResult(
      successCount: 0,
      failedCount: batch.length,
      errors: <String>['Batch sync hatasi: $message'],
      errorCodes: <String>[errorCode],
      serverVersion: response['version'] as int?,
    );
  }

  /// Tek bir ariza kaydini senkronize et
  Future<FaultSyncResult> _syncSingleFaultRecord(FaultRecord fault) async {
    String? photoUrl;
    // 1. Fotograf varsa Firebase Storage'a yukle
    if (fault.photoLocalPath != null && fault.photoUrl == null) {
      photoUrl = await _uploadPhotoToFirebase(
        fault.photoLocalPath!,
        'fault_${fault.id}', // Dosya ismine prefix ekle veya farkli klasor kullanilabilir
      );
    }

    // 2. Varlik verisini guncelle (foto URL ekle)
    final FaultRecord faultToSync = photoUrl != null
        ? fault.copyWith(photoUrl: photoUrl)
        : fault;

    // 3. Backend'e gonder
    final Map<String, dynamic> response = faultToSync.status == 'resolved'
        ? await _apiService.resolveFaultRecord(faultToSync)
        : await _apiService.addFaultRecord(faultToSync);
    bool isSuccess = (response['status'] as String?) == 'ok';
    if (!isSuccess &&
        faultToSync.status == 'resolved' &&
        (response['error_code'] as String?) == 'HTTP_404') {
      final Map<String, dynamic> fallbackResponse = await _apiService.addFaultRecord(faultToSync);
      isSuccess = (fallbackResponse['status'] as String?) == 'ok';
      if (isSuccess) {
        response.addAll(fallbackResponse);
      }
    }

    if (isSuccess) {
      // 4. Basarili: sync_status = synced
      await _dbHelper.updateFaultSyncStatus(
        fault.id,
        SyncStatus.synced,
        photoUrl: photoUrl,
      );
      return FaultSyncResult(
        isSuccess: true,
        serverVersion: response['version'] as int?,
      );
    } else {
      // 5. Basarisiz: Basitce syncFailed olarak isaretle
      // (Ileride gelismis retry kuyrugu eklenebilir)
      await _dbHelper.updateFaultSyncStatus(
        fault.id,
        SyncStatus.syncFailed,
      );
      return FaultSyncResult(
        isSuccess: false,
        errorCode: (response['error_code'] as String?) ?? 'FAULT_SYNC_FAILED',
        errorMessage: response['message'] as String?,
        serverVersion: response['version'] as int?,
      );
    }
  }

  /// Firebase Storage'a fotograf yukle
  Future<String?> _uploadPhotoToFirebase(
    String localPath,
    String assetId,
  ) async {
    try {
      final File file = File(localPath);
      if (!await file.exists()) {
        debugPrint('Fotograf dosyasi bulunamadi: $localPath');
        return null;
      }
      final String fileName = localPath.split('/').last;
      final Reference storageRef = FirebaseStorage.instance
          .ref()
          .child('field_photos')
          .child(assetId)
          .child(fileName);
      final UploadTask uploadTask = storageRef.putFile(file);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Firebase Storage yukleme hatasi: $e');
      return null;
    }
  }

  /// Senkronizasyon basarisizligini yonet
  Future<void> _handleSyncFailure(FieldAsset asset) async {
    // Sync queue'dan retry bilgisini kontrol et
    final List<Map<String, dynamic>> queueItems =
        await _dbHelper.getPendingSyncQueueItems();
    final matchingItems = queueItems.where(
      (Map<String, dynamic> item) => item['asset_local_id'] == asset.id,
    );
    if (matchingItems.isEmpty) {
      // Ilk basarisizlik - kuyruğa ekle
      await _dbHelper.addToSyncQueue(
        assetLocalId: asset.id,
        action: 'create',
        payloadJson: '{}',
      );
    } else {
      final Map<String, dynamic> queueItem = matchingItems.first;
      final int retryCount = queueItem['retry_count'] as int;
      if (retryCount >= ApiConfig.maxRetryCount) {
        // Maksimum deneme sayisina ulasildi
        await _dbHelper.updateSyncStatus(asset.id, SyncStatus.syncFailed);
      } else {
        await _dbHelper.incrementSyncQueueRetry(
          queueItem['id'] as int,
          'Senkronizasyon basarisiz',
        );
      }
    }
  }

  /// Servisi temizle
  void dispose() {
    stopAutoSync();
    stopLiveEventStream();
    _syncResultController.close();
    _liveEventController.close();
    _liveProjectionController.close();
  }

  /// Faz 3 icin onboarding ve kontrat metadata hazirligi
  Future<Map<String, dynamic>> executePhaseThreeReadiness() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('field_device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString('field_device_id', deviceId);
    }
    final Map<String, dynamic> contractResponse = await _apiService.getContracts();
    final bool isSuccess = (contractResponse['status'] as String?) == 'ok';
    if (!isSuccess) {
      return {
        'status': 'error',
        'error_code': contractResponse['error_code'] ?? 'CONTRACT_DISCOVERY_ERROR',
        'message': contractResponse['message'] ?? 'Kontratlar alinmadi',
      };
    }
    final int? versionValue = contractResponse['version'] as int?;
    final Map<String, dynamic> contractData = _extractContractData(contractResponse);
    final Map<String, dynamic> wsSchema =
        (contractData['ws_live_schema'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    _wsSchemaVersion = (wsSchema['version'] as String?) ?? _wsSchemaVersion;
    _wsHeartbeatTimeoutSeconds =
        (wsSchema['heartbeat_timeout_seconds'] as int?) ?? _wsHeartbeatTimeoutSeconds;
    _wsReconnectHint = wsSchema['reconnect_hint'] as String? ?? _wsReconnectHint;
    _lastServerVersion = versionValue ?? _lastServerVersion;
    await prefs.setString('field_ws_url', _apiService.buildLiveWebSocketUrl());
    await prefs.setString('field_ws_schema_version', _wsSchemaVersion);
    await prefs.setInt('field_ws_heartbeat_timeout', _wsHeartbeatTimeoutSeconds);
    await prefs.setString('field_ws_reconnect_hint', _wsReconnectHint ?? '');
    if (versionValue != null) {
      await prefs.setInt('field_server_version', versionValue);
    }
    return {
      'status': 'ok',
      'device_id': deviceId,
      'server_version': _lastServerVersion,
      'ws_url': _apiService.buildLiveWebSocketUrl(),
      'ws_schema_version': _wsSchemaVersion,
      'ws_heartbeat_timeout_seconds': _wsHeartbeatTimeoutSeconds,
      'ws_reconnect_hint': _wsReconnectHint,
    };
  }

  /// Canli veri omurgasi icin WebSocket baglantisini baslat
  Future<void> startLiveEventStream() async {
    if (_isLiveStreamActive) {
      return;
    }
    _shouldKeepLiveStream = true;
    _liveReconnectTimer?.cancel();
    _liveReconnectTimer = null;
    _liveReconnectAttempt = 0;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? accessToken = prefs.getString('access_token');
    if (accessToken == null || accessToken.isEmpty) {
      final Map<String, dynamic> errorEvent = {
        'type': 'error',
        'error_code': 'MISSING_ACCESS_TOKEN',
        'message': 'Canli stream icin access token bulunamadi',
      };
      _liveEventController.add(errorEvent);
      _processLiveEvent(errorEvent);
      return;
    }
    await _connectLiveStream(accessToken);
  }

  /// Canli veri WebSocket baglantisini durdur
  Future<void> stopLiveEventStream() async {
    _shouldKeepLiveStream = false;
    _liveReconnectTimer?.cancel();
    _liveReconnectTimer = null;
    _wsHeartbeatPingTimer?.cancel();
    _wsHeartbeatPingTimer = null;
    if (_liveWebSocket != null) {
      await _liveWebSocket!.close();
      _liveWebSocket = null;
    }
    _isLiveStreamActive = false;
    _emitLiveProjection();
  }

  Future<void> _connectLiveStream(String accessToken) async {
    final String wsUrl = _apiService.buildLiveWebSocketUrl();
    try {
      _liveWebSocket = await WebSocket.connect(
        wsUrl,
        headers: <String, dynamic>{'Authorization': 'Bearer $accessToken'},
      );
      _isLiveStreamActive = true;
      _liveReconnectAttempt = 0;
      _emitLiveProjection();
      _startHeartbeatPingLoop();
      _liveWebSocket!.listen(
        (dynamic rawEvent) {
          if (rawEvent is! String) {
            return;
          }
          try {
            final dynamic decoded = jsonDecode(rawEvent);
            if (decoded is Map<String, dynamic>) {
              _liveEventController.add(decoded);
              _processLiveEvent(decoded);
            }
          } catch (_) {
            final Map<String, dynamic> errorEvent = {
              'type': 'error',
              'error_code': 'LIVE_STREAM_DECODE_ERROR',
              'message': 'Canli event decode edilemedi',
            };
            _liveEventController.add(errorEvent);
            _processLiveEvent(errorEvent);
          }
        },
        onDone: () {
          _isLiveStreamActive = false;
          _wsHeartbeatPingTimer?.cancel();
          _wsHeartbeatPingTimer = null;
          _emitLiveProjection();
          _scheduleLiveReconnect();
        },
        onError: (Object err) {
          _isLiveStreamActive = false;
          _wsHeartbeatPingTimer?.cancel();
          _wsHeartbeatPingTimer = null;
          final Map<String, dynamic> errorEvent = {
            'type': 'error',
            'error_code': 'LIVE_STREAM_ERROR',
            'message': err.toString(),
          };
          _liveEventController.add(errorEvent);
          _processLiveEvent(errorEvent);
          _scheduleLiveReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _isLiveStreamActive = false;
      final Map<String, dynamic> errorEvent = {
        'type': 'error',
        'error_code': 'LIVE_STREAM_CONNECT_FAILED',
        'message': e.toString(),
      };
      _liveEventController.add(errorEvent);
      _processLiveEvent(errorEvent);
      _scheduleLiveReconnect();
    }
  }

  void _scheduleLiveReconnect() {
    if (!_shouldKeepLiveStream) {
      return;
    }
    _liveReconnectTimer?.cancel();
    _liveReconnectAttempt += 1;
    final int waitSeconds = _calculateReconnectDelaySeconds(_liveReconnectAttempt);
    _emitLiveProjection();
    _liveReconnectTimer = Timer(Duration(seconds: waitSeconds), () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? accessToken = prefs.getString('access_token');
      if (accessToken == null || accessToken.isEmpty) {
        return;
      }
      await _connectLiveStream(accessToken);
    });
  }

  int _calculateReconnectDelaySeconds(int attempt) {
    if (attempt <= 1) {
      return 2;
    }
    if (attempt == 2) {
      return 4;
    }
    if (attempt == 3) {
      return 8;
    }
    if (attempt == 4) {
      return 16;
    }
    return 30;
  }

  void _processLiveEvent(Map<String, dynamic> eventPayload) {
    _lastLiveEventAt = DateTime.now();
    _lastLiveEventType = eventPayload['type'] as String?;
    final String eventType = _lastLiveEventType ?? '';
    if (eventType == 'telemetry') {
      final String assetId = (eventPayload['asset_id'] as String?) ?? '';
      if (assetId.isNotEmpty) {
        final Map<String, dynamic> telemetryNode = {
          'asset_id': assetId,
          'device_id': eventPayload['device_id'],
          'metrics': eventPayload['metrics'],
          'measured_at': eventPayload['measured_at'],
          'received_at': _lastLiveEventAt?.toIso8601String(),
        };
        _telemetryByAssetId[assetId] = telemetryNode;
      }
      final dynamic alertsNode = eventPayload['alerts'];
      if (alertsNode is List) {
        for (final dynamic alertItem in alertsNode) {
          if (alertItem is Map<String, dynamic>) {
            final Map<String, dynamic> normalizedAlert =
                Map<String, dynamic>.from(alertItem);
            _liveAlerts.add(normalizedAlert);
            final String alertAssetId = (normalizedAlert['asset_id'] as String?) ?? '';
            if (alertAssetId.isNotEmpty) {
              final int currentCount = _alertCountByAssetId[alertAssetId] ?? 0;
              _alertCountByAssetId[alertAssetId] = currentCount + 1;
            }
          }
        }
        if (_liveAlerts.length > 200) {
          _liveAlerts.removeRange(0, _liveAlerts.length - 200);
        }
      }
    }
    if (eventType == 'error') {
      _isLiveStreamActive = false;
    }
    if (eventType == 'schema_mismatch') {
      _isLiveStreamActive = false;
      _shouldKeepLiveStream = false;
      _wsHeartbeatPingTimer?.cancel();
      _wsHeartbeatPingTimer = null;
      _liveReconnectTimer?.cancel();
      _liveReconnectTimer = null;
      _wsReconnectHint = eventPayload['reconnect_hint'] as String? ?? _wsReconnectHint;
    }
    if (eventType == 'heartbeat_timeout') {
      _isLiveStreamActive = false;
      _wsHeartbeatPingTimer?.cancel();
      _wsHeartbeatPingTimer = null;
      _wsReconnectHint = eventPayload['reconnect_hint'] as String? ?? _wsReconnectHint;
    }
    _emitLiveProjection();
  }

  void _emitLiveProjection() {
    if (_liveProjectionController.isClosed) {
      return;
    }
    _liveProjectionController.add(
      LiveProjectionState(
        isConnected: _isLiveStreamActive,
        reconnectAttempt: _liveReconnectAttempt,
        alertCount: _liveAlerts.length,
        lastEventAt: _lastLiveEventAt,
        lastEventType: _lastLiveEventType,
        telemetryByAssetId: Map<String, Map<String, dynamic>>.from(
          _telemetryByAssetId,
        ),
        alertCountByAssetId: Map<String, int>.from(_alertCountByAssetId),
      ),
    );
  }

  void _startHeartbeatPingLoop() {
    _wsHeartbeatPingTimer?.cancel();
    _wsHeartbeatPingTimer = null;
    if (_liveWebSocket == null || !_isLiveStreamActive) {
      return;
    }
    final int pingIntervalSeconds = (_wsHeartbeatTimeoutSeconds / 2).floor();
    final int safeInterval = pingIntervalSeconds < 3 ? 3 : pingIntervalSeconds;
    _wsHeartbeatPingTimer = Timer.periodic(
      Duration(seconds: safeInterval),
      (_) async {
        if (_liveWebSocket == null || !_isLiveStreamActive) {
          return;
        }
        final Map<String, dynamic> pingPayload = {
          'type': 'ping',
          'schema_version': _wsSchemaVersion,
          'sent_at': DateTime.now().toIso8601String(),
        };
        try {
          _liveWebSocket!.add(jsonEncode(pingPayload));
        } catch (e) {
          final Map<String, dynamic> errorEvent = {
            'type': 'error',
            'error_code': 'LIVE_STREAM_PING_FAILED',
            'message': e.toString(),
          };
          _liveEventController.add(errorEvent);
          _processLiveEvent(errorEvent);
        }
      },
    );
  }

  Map<String, dynamic> _extractContractData(Map<String, dynamic> contractResponse) {
    final dynamic dataNode = contractResponse['data'];
    if (dataNode is Map<String, dynamic>) {
      return dataNode;
    }
    return contractResponse;
  }

  Future<OnboardingState> registerOrRefreshDevice({
    required String assetId,
    String model = 'field-mobile',
    String firmwareVersion = 'phase3',
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('field_device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString('field_device_id', deviceId);
    }
    final Map<String, dynamic> response = await _apiService.registerIotDevice(
      assetId: assetId,
      deviceId: deviceId,
      model: model,
      firmwareVersion: firmwareVersion,
    );
    final Map<String, dynamic> dataNode =
        (response['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> deviceNode =
        (dataNode['device'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> topicPolicy =
        (deviceNode['topic_policy'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String? rawApiKey = deviceNode['api_key'] as String?;
    final String? apiKeyMasked = rawApiKey == null || rawApiKey.length < 8
        ? rawApiKey
        : '${rawApiKey.substring(0, 4)}***${rawApiKey.substring(rawApiKey.length - 4)}';
    return OnboardingState(
      deviceId: (deviceNode['device_id'] as String?) ?? deviceId,
      telemetryPublishTopic: topicPolicy['telemetry_publish_topic'] as String?,
      commandSubscribeTopic: topicPolicy['command_subscribe_topic'] as String?,
      apiKeyMasked: apiKeyMasked,
      wsHeartbeatTimeoutSeconds: _wsHeartbeatTimeoutSeconds,
      wsSchemaVersion: _wsSchemaVersion,
    );
  }

  Future<OnboardingState> rotateDeviceKey() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? deviceId = prefs.getString('field_device_id');
    if (deviceId == null || deviceId.isEmpty) {
      throw StateError('Cihaz id bulunamadi');
    }
    final Map<String, dynamic> response = await _apiService.rotateIotDeviceKey(deviceId);
    final Map<String, dynamic> dataNode =
        (response['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> deviceNode =
        (dataNode['device'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final Map<String, dynamic> topicPolicy =
        (deviceNode['topic_policy'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String? rawApiKey = deviceNode['api_key'] as String?;
    final String? apiKeyMasked = rawApiKey == null || rawApiKey.length < 8
        ? rawApiKey
        : '${rawApiKey.substring(0, 4)}***${rawApiKey.substring(rawApiKey.length - 4)}';
    return OnboardingState(
      deviceId: (deviceNode['device_id'] as String?) ?? deviceId,
      telemetryPublishTopic: topicPolicy['telemetry_publish_topic'] as String?,
      commandSubscribeTopic: topicPolicy['command_subscribe_topic'] as String?,
      apiKeyMasked: apiKeyMasked,
      wsHeartbeatTimeoutSeconds: _wsHeartbeatTimeoutSeconds,
      wsSchemaVersion: _wsSchemaVersion,
    );
  }

  Future<Map<String, dynamic>> ackAlert({
    required String alertId,
    required String operator,
  }) async {
    return _apiService.ackIotAlert(alertId: alertId, operator: operator);
  }

  Future<Map<String, dynamic>> closeAlert({
    required String alertId,
    required String operator,
    required String reason,
  }) async {
    return _apiService.closeIotAlert(
      alertId: alertId,
      operator: operator,
      reason: reason,
    );
  }

  Future<Map<String, dynamic>> listAlerts() async {
    return _apiService.listIotAlerts();
  }

  Future<Map<String, dynamic>> runPhaseThreeE2ESmoke() async {
    final List<FieldAsset> assets = await _dbHelper.getAllAssets();
    if (assets.isEmpty) {
      return {
        'status': 'error',
        'error_code': 'NO_ASSET_FOR_E2E',
        'message': 'E2E smoke testi icin once en az bir varlik olusturun',
      };
    }
    final String assetId = assets.first.id;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String deviceId = prefs.getString('field_device_id') ?? const Uuid().v4();
    await prefs.setString('field_device_id', deviceId);
    final Completer<Map<String, dynamic>> wsCompleter =
        Completer<Map<String, dynamic>>();
    final StreamSubscription<Map<String, dynamic>> wsSubscription =
        liveEventStream.listen((Map<String, dynamic> event) {
      final String type = (event['type'] as String?) ?? '';
      final String eventAssetId = (event['asset_id'] as String?) ?? '';
      if (type == 'telemetry' && eventAssetId == assetId && !wsCompleter.isCompleted) {
        wsCompleter.complete(event);
      }
    });
    try {
      await startLiveEventStream();
      final Map<String, dynamic> telemetryResponse =
          await _apiService.ingestTelemetry(
        assetId: assetId,
        deviceId: deviceId,
        metrics: <String, dynamic>{'temperature': 22.1, 'humidity': 51.2},
      );
      final bool telemetryOk = (telemetryResponse['status'] as String?) == 'ok';
      if (!telemetryOk) {
        return {
          'status': 'error',
          'error_code':
              telemetryResponse['error_code'] ?? 'E2E_TELEMETRY_FAILED',
          'message':
              telemetryResponse['message'] ?? 'Telemetry ingest basarisiz',
        };
      }
      Map<String, dynamic>? wsEvent;
      try {
        wsEvent = await wsCompleter.future.timeout(
          const Duration(seconds: 12),
        );
      } catch (_) {
        wsEvent = null;
      }
      if (wsEvent == null) {
        return {
          'status': 'error',
          'error_code': 'E2E_WS_EVENT_TIMEOUT',
          'message': 'Telemetry event ws/live uzerinden alinamadi',
        };
      }
      return {
        'status': 'ok',
        'asset_id': assetId,
        'device_id': deviceId,
        'ws_event_type': wsEvent['type'],
        'ws_schema_version': wsEvent['schema_version'],
      };
    } finally {
      await wsSubscription.cancel();
    }
  }
}
