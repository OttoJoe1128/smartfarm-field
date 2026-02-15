/// Saha varligi modeli - Agac, kuyu, sensor, yapi vb.
/// Hem yerel SQLite hem de backend ile senkronizasyon icin kullanilir
class FieldAsset {
  final String id;
  final String name;
  final String assetType;
  final double latitude;
  final double longitude;
  final double? altitude;
  final double gpsAccuracy;
  final String? photoLocalPath;
  final String? photoUrl;
  final String? treeSpecies;
  final int? treeAge;
  final double? treeHeight;
  final String? healthStatus;
  final String? notes;
  final bool iotConnected;
  final String? parcelId;
  final String? userId;
  final String syncStatus;
  final DateTime createdAt;
  final DateTime? syncedAt;

  const FieldAsset({
    required this.id,
    required this.name,
    required this.assetType,
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.gpsAccuracy,
    this.photoLocalPath,
    this.photoUrl,
    this.treeSpecies,
    this.treeAge,
    this.treeHeight,
    this.healthStatus,
    this.notes,
    this.iotConnected = false,
    this.parcelId,
    this.userId,
    this.syncStatus = SyncStatus.pendingSync,
    required this.createdAt,
    this.syncedAt,
  });

  /// SQLite Map'inden FieldAsset olustur
  factory FieldAsset.fromMap(Map<String, dynamic> map) {
    return FieldAsset(
      id: map['id'] as String,
      name: map['name'] as String,
      assetType: map['asset_type'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitude: map['altitude'] != null ? (map['altitude'] as num).toDouble() : null,
      gpsAccuracy: (map['gps_accuracy'] as num).toDouble(),
      photoLocalPath: map['photo_local_path'] as String?,
      photoUrl: map['photo_url'] as String?,
      treeSpecies: map['tree_species'] as String?,
      treeAge: map['tree_age'] as int?,
      treeHeight: map['tree_height'] != null ? (map['tree_height'] as num).toDouble() : null,
      healthStatus: map['health_status'] as String?,
      notes: map['notes'] as String?,
      iotConnected: (map['iot_connected'] as int?) == 1,
      parcelId: map['parcel_id'] as String?,
      userId: map['user_id'] as String?,
      syncStatus: map['sync_status'] as String? ?? SyncStatus.pendingSync,
      createdAt: DateTime.parse(map['created_at'] as String),
      syncedAt: map['synced_at'] != null ? DateTime.parse(map['synced_at'] as String) : null,
    );
  }

  /// FieldAsset'i SQLite Map'ine donustur
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'asset_type': assetType,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'gps_accuracy': gpsAccuracy,
      'photo_local_path': photoLocalPath,
      'photo_url': photoUrl,
      'tree_species': treeSpecies,
      'tree_age': treeAge,
      'tree_height': treeHeight,
      'health_status': healthStatus,
      'notes': notes,
      'iot_connected': iotConnected ? 1 : 0,
      'parcel_id': parcelId,
      'user_id': userId,
      'sync_status': syncStatus,
      'created_at': createdAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
    };
  }

  /// Backend API formatina donustur (add-asset endpointi ile uyumlu)
  Map<String, dynamic> toApiPayload() {
    final Map<String, dynamic> properties = {
      'iot_connected': iotConnected,
      'source': 'field_app',
      'user_id': userId,
      'gps_accuracy': gpsAccuracy,
    };
    if (treeSpecies != null) properties['tree_species'] = treeSpecies;
    if (treeAge != null) properties['tree_age'] = treeAge;
    if (treeHeight != null) properties['tree_height'] = treeHeight;
    if (healthStatus != null) properties['health_status'] = healthStatus;
    if (notes != null) properties['notes'] = notes;
    if (photoUrl != null) properties['photo_url'] = photoUrl;
    if (altitude != null) properties['altitude'] = altitude;
    if (parcelId != null) properties['parcel_id'] = parcelId;
    return {
      'name': name,
      'type': 'Point',
      'geometry': {
        'type': 'Point',
        'coordinates': [longitude, latitude],
      },
      'style': {
        'color': _getColorForType(assetType),
        'icon': _getIconForType(assetType),
      },
      'properties': properties,
    };
  }

  /// Kopya olustur (immutable guncelleme)
  FieldAsset copyWith({
    String? id,
    String? name,
    String? assetType,
    double? latitude,
    double? longitude,
    double? altitude,
    double? gpsAccuracy,
    String? photoLocalPath,
    String? photoUrl,
    String? treeSpecies,
    int? treeAge,
    double? treeHeight,
    String? healthStatus,
    String? notes,
    bool? iotConnected,
    String? parcelId,
    String? userId,
    String? syncStatus,
    DateTime? createdAt,
    DateTime? syncedAt,
  }) {
    return FieldAsset(
      id: id ?? this.id,
      name: name ?? this.name,
      assetType: assetType ?? this.assetType,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      photoLocalPath: photoLocalPath ?? this.photoLocalPath,
      photoUrl: photoUrl ?? this.photoUrl,
      treeSpecies: treeSpecies ?? this.treeSpecies,
      treeAge: treeAge ?? this.treeAge,
      treeHeight: treeHeight ?? this.treeHeight,
      healthStatus: healthStatus ?? this.healthStatus,
      notes: notes ?? this.notes,
      iotConnected: iotConnected ?? this.iotConnected,
      parcelId: parcelId ?? this.parcelId,
      userId: userId ?? this.userId,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  /// Senkronize edilmis mi kontrol
  bool get isSynced => syncStatus == SyncStatus.synced;

  /// Senkronizasyon bekliyor mu kontrol
  bool get isPendingSync => syncStatus == SyncStatus.pendingSync;

  /// Senkronizasyon basarisiz mi kontrol
  bool get isSyncFailed => syncStatus == SyncStatus.syncFailed;

  static String _getColorForType(String type) {
    switch (type) {
      case AssetType.agac:
        return '#4CAF50';
      case AssetType.kuyu:
        return '#2196F3';
      case AssetType.sensor:
        return '#FF9800';
      case AssetType.yapi:
        return '#795548';
      case AssetType.gunes:
        return '#FFC107';
      case AssetType.olcum:
        return '#9C27B0';
      default:
        return '#8BC34A';
    }
  }

  static String _getIconForType(String type) {
    switch (type) {
      case AssetType.agac:
        return 'park';
      case AssetType.kuyu:
        return 'water_drop';
      case AssetType.sensor:
        return 'sensors';
      case AssetType.yapi:
        return 'home';
      case AssetType.gunes:
        return 'solar_power';
      case AssetType.olcum:
        return 'straighten';
      default:
        return 'place';
    }
  }
}

/// Varlik tipleri sabitleri
class AssetType {
  AssetType._();
  static const String agac = 'agac';
  static const String kuyu = 'kuyu';
  static const String sensor = 'sensor';
  static const String yapi = 'yapi';
  static const String gunes = 'gunes';
  static const String olcum = 'olcum';

  static const List<String> all = [agac, kuyu, sensor, yapi, gunes, olcum];

  static String displayName(String type) {
    switch (type) {
      case agac:
        return 'Agac';
      case kuyu:
        return 'Kuyu';
      case sensor:
        return 'Sensor';
      case yapi:
        return 'Yapi';
      case gunes:
        return 'Gunes Paneli';
      case olcum:
        return 'Olcum Noktasi';
      default:
        return type;
    }
  }
}

/// Senkronizasyon durumlari
class SyncStatus {
  SyncStatus._();
  static const String pendingSync = 'pending_sync';
  static const String synced = 'synced';
  static const String syncFailed = 'sync_failed';
}

/// Saglik durumlari
class HealthStatus {
  HealthStatus._();
  static const String excellent = 'excellent';
  static const String good = 'good';
  static const String fair = 'fair';
  static const String poor = 'poor';

  static const List<String> all = [excellent, good, fair, poor];

  static String displayName(String status) {
    switch (status) {
      case excellent:
        return 'Mukemmel';
      case good:
        return 'Iyi';
      case fair:
        return 'Orta';
      case poor:
        return 'Kotu';
      default:
        return status;
    }
  }
}

/// Turkiye'de yaygin agac turleri
class TreeSpecies {
  TreeSpecies._();
  static const List<String> all = [
    'Zeytin',
    'Ceviz',
    'Badem',
    'Findik',
    'Elma',
    'Armut',
    'Kiraz',
    'Visne',
    'Erik',
    'Seftali',
    'Kayisi',
    'Nar',
    'Incir',
    'Portakal',
    'Limon',
    'Mandalina',
    'Uzum',
    'Fistik',
    'Kestane',
    'Dut',
    'Kavak',
    'Cinar',
    'Mese',
    'Cam',
    'Selvi',
  ];
}
