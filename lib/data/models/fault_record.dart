/// Ariza kaydi modeli
class FaultRecord {
  final String id;
  final String assetId;
  final String description;
  final String severity; // low, medium, high, critical
  final String status; // open, in_progress, resolved
  final String? photoLocalPath;
  final String? photoUrl;
  final String? userId;
  final String syncStatus;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const FaultRecord({
    required this.id,
    required this.assetId,
    required this.description,
    this.severity = 'medium',
    this.status = 'open',
    this.photoLocalPath,
    this.photoUrl,
    this.userId,
    this.syncStatus = 'pending_sync', // SyncStatus.pendingSync
    required this.createdAt,
    this.resolvedAt,
  });

  /// SQLite Map'inden FaultRecord olustur
  factory FaultRecord.fromMap(Map<String, dynamic> map) {
    return FaultRecord(
      id: map['id'] as String,
      assetId: map['asset_id'] as String,
      description: map['description'] as String,
      severity: map['severity'] as String,
      status: map['status'] as String,
      photoLocalPath: map['photo_local_path'] as String?,
      photoUrl: map['photo_url'] as String?,
      userId: map['user_id'] as String?,
      syncStatus: map['sync_status'] as String? ?? 'pending_sync',
      createdAt: DateTime.parse(map['created_at'] as String),
      resolvedAt: map['resolved_at'] != null ? DateTime.parse(map['resolved_at'] as String) : null,
    );
  }

  /// FaultRecord'u SQLite Map'ine donustur
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'asset_id': assetId,
      'description': description,
      'severity': severity,
      'status': status,
      'photo_local_path': photoLocalPath,
      'photo_url': photoUrl,
      'user_id': userId,
      'sync_status': syncStatus,
      'created_at': createdAt.toIso8601String(),
      'resolved_at': resolvedAt?.toIso8601String(),
    };
  }

  /// Backend API formatina donustur
  Map<String, dynamic> toApiPayload() {
    final Map<String, dynamic> payload = {
      'asset_id': assetId,
      'description': description,
      'severity': severity,
      'status': status,
      'user_id': userId,
      'created_at': createdAt.toIso8601String(),
    };
    if (photoUrl != null) payload['photo_url'] = photoUrl;
    if (resolvedAt != null) payload['resolved_at'] = resolvedAt!.toIso8601String();
    
    return payload;
  }

  /// Kopya olustur
  FaultRecord copyWith({
    String? id,
    String? assetId,
    String? description,
    String? severity,
    String? status,
    String? photoLocalPath,
    String? photoUrl,
    String? userId,
    String? syncStatus,
    DateTime? createdAt,
    DateTime? resolvedAt,
  }) {
    return FaultRecord(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      description: description ?? this.description,
      severity: severity ?? this.severity,
      status: status ?? this.status,
      photoLocalPath: photoLocalPath ?? this.photoLocalPath,
      photoUrl: photoUrl ?? this.photoUrl,
      userId: userId ?? this.userId,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
    );
  }
}
