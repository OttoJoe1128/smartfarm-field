import 'package:flutter_test/flutter_test.dart';
import 'package:smartfarm_field/data/models/field_asset.dart';

void main() {
  group('FieldAsset', () {
    test('toMap ve fromMap alanlari dogru cevrer', () {
      final DateTime inputCreatedAt = DateTime.parse('2026-03-16T10:00:00Z');
      final DateTime inputSyncedAt = DateTime.parse('2026-03-16T11:00:00Z');
      final FieldAsset inputVarlik = FieldAsset(
        id: 'asset-1',
        name: 'Ornek Agac',
        assetType: AssetType.agac,
        latitude: 40.1,
        longitude: 29.2,
        altitude: 123.4,
        gpsAccuracy: 3.5,
        photoLocalPath: '/tmp/agac.jpg',
        photoUrl: 'https://cdn/ornek.jpg',
        treeSpecies: 'Zeytin',
        treeAge: 8,
        treeHeight: 2.2,
        healthStatus: HealthStatus.good,
        notes: 'Test notu',
        iotConnected: true,
        parcelId: 'parcel-1',
        userId: 'user-1',
        syncStatus: SyncStatus.synced,
        createdAt: inputCreatedAt,
        syncedAt: inputSyncedAt,
      );
      final Map<String, dynamic> actualMap = inputVarlik.toMap();
      final FieldAsset actualDonusen = FieldAsset.fromMap(actualMap);
      expect(actualDonusen.id, inputVarlik.id);
      expect(actualDonusen.name, inputVarlik.name);
      expect(actualDonusen.assetType, inputVarlik.assetType);
      expect(actualDonusen.latitude, inputVarlik.latitude);
      expect(actualDonusen.longitude, inputVarlik.longitude);
      expect(actualDonusen.gpsAccuracy, inputVarlik.gpsAccuracy);
      expect(actualDonusen.iotConnected, true);
      expect(actualDonusen.syncStatus, SyncStatus.synced);
      expect(actualDonusen.createdAt.toIso8601String(), inputCreatedAt.toIso8601String());
      expect(actualDonusen.syncedAt?.toIso8601String(), inputSyncedAt.toIso8601String());
    });
    test('toApiPayload geometry ve style alanlarini dogru uretir', () {
      final FieldAsset inputVarlik = FieldAsset(
        id: 'asset-2',
        name: 'Kuyu 1',
        assetType: AssetType.kuyu,
        latitude: 10.0,
        longitude: 20.0,
        gpsAccuracy: 4.0,
        createdAt: DateTime.parse('2026-03-16T10:00:00Z'),
      );
      final Map<String, dynamic> actualPayload = inputVarlik.toApiPayload();
      expect(actualPayload['name'], 'Kuyu 1');
      expect(actualPayload['type'], 'Point');
      expect(actualPayload['geometry']['type'], 'Point');
      expect(actualPayload['geometry']['coordinates'], <double>[20.0, 10.0]);
      expect(actualPayload['style']['color'], '#2196F3');
      expect(actualPayload['style']['icon'], 'water_drop');
      expect(actualPayload['properties']['source'], 'field_app');
      expect(actualPayload['properties']['iot_connected'], false);
    });
    test('copyWith sadece verilen alanlari gunceller', () {
      final FieldAsset inputVarlik = FieldAsset(
        id: 'asset-3',
        name: 'Sensor 1',
        assetType: AssetType.sensor,
        latitude: 41.0,
        longitude: 30.0,
        gpsAccuracy: 2.0,
        syncStatus: SyncStatus.pendingSync,
        createdAt: DateTime.parse('2026-03-16T10:00:00Z'),
      );
      final FieldAsset actualKopya = inputVarlik.copyWith(
        name: 'Sensor 1 Guncel',
        syncStatus: SyncStatus.syncFailed,
      );
      expect(actualKopya.id, 'asset-3');
      expect(actualKopya.name, 'Sensor 1 Guncel');
      expect(actualKopya.assetType, AssetType.sensor);
      expect(actualKopya.syncStatus, SyncStatus.syncFailed);
    });
    test('senkron durum getterlari dogru calisir', () {
      final FieldAsset inputBekleyen = FieldAsset(
        id: 'asset-4',
        name: 'Bekleyen',
        assetType: AssetType.olcum,
        latitude: 1,
        longitude: 1,
        gpsAccuracy: 1,
        syncStatus: SyncStatus.pendingSync,
        createdAt: DateTime.parse('2026-03-16T10:00:00Z'),
      );
      final FieldAsset inputBasarili = inputBekleyen.copyWith(syncStatus: SyncStatus.synced);
      final FieldAsset inputHatali = inputBekleyen.copyWith(syncStatus: SyncStatus.syncFailed);
      expect(inputBekleyen.isPendingSync, true);
      expect(inputBekleyen.isSynced, false);
      expect(inputBekleyen.isSyncFailed, false);
      expect(inputBasarili.isSynced, true);
      expect(inputHatali.isSyncFailed, true);
    });
  });
}
