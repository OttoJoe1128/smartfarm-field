import 'package:flutter_test/flutter_test.dart';
import 'package:smartfarm_field/data/models/fault_record.dart';

void main() {
  group('FaultRecord', () {
    test('toMap ve fromMap alanlari dogru cevrer', () {
      final DateTime inputCreatedAt = DateTime.parse('2026-03-16T10:00:00Z');
      final DateTime inputResolvedAt = DateTime.parse('2026-03-16T12:00:00Z');
      final FaultRecord inputKayit = FaultRecord(
        id: 'fault-1',
        assetId: 'asset-1',
        description: 'Sizinti var',
        severity: 'high',
        status: 'resolved',
        photoLocalPath: '/tmp/fault.jpg',
        photoUrl: 'https://cdn/fault.jpg',
        userId: 'operator-1',
        syncStatus: 'synced',
        createdAt: inputCreatedAt,
        resolvedAt: inputResolvedAt,
      );
      final Map<String, dynamic> actualMap = inputKayit.toMap();
      final FaultRecord actualDonusen = FaultRecord.fromMap(actualMap);
      expect(actualDonusen.id, inputKayit.id);
      expect(actualDonusen.assetId, inputKayit.assetId);
      expect(actualDonusen.description, inputKayit.description);
      expect(actualDonusen.severity, 'high');
      expect(actualDonusen.status, 'resolved');
      expect(actualDonusen.syncStatus, 'synced');
      expect(actualDonusen.createdAt.toIso8601String(), inputCreatedAt.toIso8601String());
      expect(actualDonusen.resolvedAt?.toIso8601String(), inputResolvedAt.toIso8601String());
    });
    test('toApiPayload zorunlu ve opsiyonel alanlari uretir', () {
      final FaultRecord inputKayit = FaultRecord(
        id: 'fault-2',
        assetId: 'asset-2',
        description: 'Basinc dusuk',
        severity: 'medium',
        status: 'open',
        userId: 'operator-2',
        photoUrl: 'https://cdn/fault-2.jpg',
        createdAt: DateTime.parse('2026-03-16T10:00:00Z'),
      );
      final Map<String, dynamic> actualPayload = inputKayit.toApiPayload();
      expect(actualPayload['asset_id'], 'asset-2');
      expect(actualPayload['description'], 'Basinc dusuk');
      expect(actualPayload['severity'], 'medium');
      expect(actualPayload['status'], 'open');
      expect(actualPayload['user_id'], 'operator-2');
      expect(actualPayload['photo_url'], 'https://cdn/fault-2.jpg');
    });
    test('copyWith sadece verilen alanlari gunceller', () {
      final FaultRecord inputKayit = FaultRecord(
        id: 'fault-3',
        assetId: 'asset-3',
        description: 'Ilk aciklama',
        createdAt: DateTime.parse('2026-03-16T10:00:00Z'),
      );
      final DateTime inputResolvedAt = DateTime.parse('2026-03-16T14:00:00Z');
      final FaultRecord actualKopya = inputKayit.copyWith(
        description: 'Guncel aciklama',
        status: 'resolved',
        resolvedAt: inputResolvedAt,
      );
      expect(actualKopya.id, 'fault-3');
      expect(actualKopya.assetId, 'asset-3');
      expect(actualKopya.description, 'Guncel aciklama');
      expect(actualKopya.status, 'resolved');
      expect(actualKopya.resolvedAt?.toIso8601String(), inputResolvedAt.toIso8601String());
    });
  });
}
