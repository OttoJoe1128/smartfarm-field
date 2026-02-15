import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../../data/local/database_helper.dart';
import '../../data/models/field_asset.dart';
import '../../data/remote/saha_api_service.dart';
import '../config/api_config.dart';

/// Senkronizasyon sonucu
class SyncResult {
  final int successCount;
  final int failedCount;
  final List<String> errors;

  const SyncResult({
    required this.successCount,
    required this.failedCount,
    this.errors = const [],
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
      Duration(seconds: ApiConfig.syncIntervalSeconds),
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
    try {
      final bool isConnected = await _isOnline();
      if (!isConnected) {
        return const SyncResult(
          successCount: 0,
          failedCount: 0,
          errors: ['Internet baglantisi yok'],
        );
      }
      // Bekleyen ve basarisiz kayitlari getir
      final List<FieldAsset> pendingAssets =
          await _dbHelper.getAssetsBySyncStatus(SyncStatus.pendingSync);
      final List<FieldAsset> failedAssets =
          await _dbHelper.getAssetsBySyncStatus(SyncStatus.syncFailed);
      final List<FieldAsset> allToSync = [...pendingAssets, ...failedAssets];
      if (allToSync.isEmpty) {
        return const SyncResult(successCount: 0, failedCount: 0);
      }
      // Batch isleme - ayni anda max 5 kayit
      for (int i = 0; i < allToSync.length; i += ApiConfig.maxBatchSize) {
        final int end = (i + ApiConfig.maxBatchSize < allToSync.length)
            ? i + ApiConfig.maxBatchSize
            : allToSync.length;
        final List<FieldAsset> batch = allToSync.sublist(i, end);
        for (final FieldAsset asset in batch) {
          try {
            await _syncSingleAsset(asset);
            successCount++;
          } catch (e) {
            failedCount++;
            errors.add('${asset.name}: $e');
            debugPrint('Sync hatasi (${asset.id}): $e');
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
    );
    _syncResultController.add(result);
    return result;
  }

  /// Tek bir varligi senkronize et
  Future<void> _syncSingleAsset(FieldAsset asset) async {
    String? photoUrl;
    // 1. Fotograf varsa Firebase Storage'a yukle
    if (asset.photoLocalPath != null && asset.photoUrl == null) {
      photoUrl = await _uploadPhotoToFirebase(
        asset.photoLocalPath!,
        asset.id,
      );
    }
    // 2. Varlik verisini guncelle (foto URL ekle)
    final FieldAsset assetToSync = photoUrl != null
        ? asset.copyWith(photoUrl: photoUrl)
        : asset;
    // 3. Backend'e gonder
    final bool isSuccess = await _apiService.addAsset(assetToSync);
    if (isSuccess) {
      // 4. Basarili: sync_status = synced
      await _dbHelper.updateSyncStatus(
        asset.id,
        SyncStatus.synced,
        photoUrl: photoUrl,
      );
    } else {
      // 5. Basarisiz: retry mekanizmasi
      await _handleSyncFailure(asset);
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
