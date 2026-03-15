import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
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
  bool _isSyncing = false;
  bool _isAutoSyncEnabled = false;
  int? _lastServerVersion;
  int? get lastServerVersion => _lastServerVersion;

  /// Senkronizasyon durumu akisi
  final StreamController<SyncResult> _syncResultController =
      StreamController<SyncResult>.broadcast();
  Stream<SyncResult> get syncResultStream => _syncResultController.stream;

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
    _syncResultController.close();
  }
}
