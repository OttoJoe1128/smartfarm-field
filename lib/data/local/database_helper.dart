import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/field_asset.dart';

/// SQLite veritabani yardimcisi
/// Offline-first mimari icin yerel veri saklama
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  static const String _databaseName = 'smartfarm_field.db';
  static const int _databaseVersion = 1;

  // Tablo adlari
  static const String tableFieldAssets = 'field_assets';
  static const String tableSyncQueue = 'sync_queue';

  /// Veritabanini getir (lazy initialization)
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// Veritabanini baslat
  Future<Database> _initDatabase() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Tablolari olustur
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableFieldAssets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        asset_type TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        altitude REAL,
        gps_accuracy REAL NOT NULL,
        photo_local_path TEXT,
        photo_url TEXT,
        tree_species TEXT,
        tree_age INTEGER,
        tree_height REAL,
        health_status TEXT,
        notes TEXT,
        iot_connected INTEGER DEFAULT 0,
        parcel_id TEXT,
        user_id TEXT,
        sync_status TEXT DEFAULT 'pending_sync',
        created_at TEXT NOT NULL,
        synced_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE $tableSyncQueue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_local_id TEXT NOT NULL,
        action TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (asset_local_id) REFERENCES $tableFieldAssets (id)
      )
    ''');
    // Indeksler
    await db.execute(
      'CREATE INDEX idx_field_assets_sync_status ON $tableFieldAssets (sync_status)',
    );
    await db.execute(
      'CREATE INDEX idx_field_assets_created_at ON $tableFieldAssets (created_at)',
    );
    await db.execute(
      'CREATE INDEX idx_sync_queue_asset ON $tableSyncQueue (asset_local_id)',
    );
  }

  /// Veritabani yukseltme (gelecek surumlere hazirlama)
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Gelecekte migration islemleri buraya eklenecek
  }

  // --- Field Assets CRUD ---

  /// Yeni varlik ekle
  Future<void> insertAsset(FieldAsset asset) async {
    final db = await database;
    await db.insert(
      tableFieldAssets,
      asset.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Varligi guncelle
  Future<void> updateAsset(FieldAsset asset) async {
    final db = await database;
    await db.update(
      tableFieldAssets,
      asset.toMap(),
      where: 'id = ?',
      whereArgs: [asset.id],
    );
  }

  /// Varligi sil
  Future<void> deleteAsset(String assetId) async {
    final db = await database;
    await db.delete(
      tableFieldAssets,
      where: 'id = ?',
      whereArgs: [assetId],
    );
    await db.delete(
      tableSyncQueue,
      where: 'asset_local_id = ?',
      whereArgs: [assetId],
    );
  }

  /// Tek varlik getir (ID ile)
  Future<FieldAsset?> getAssetById(String assetId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableFieldAssets,
      where: 'id = ?',
      whereArgs: [assetId],
    );
    if (maps.isEmpty) return null;
    return FieldAsset.fromMap(maps.first);
  }

  /// Tum varliklari getir (en yeni once)
  Future<List<FieldAsset>> getAllAssets() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableFieldAssets,
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => FieldAsset.fromMap(map)).toList();
  }

  /// Bugunun varliklarini getir
  Future<List<FieldAsset>> getTodayAssets() async {
    final db = await database;
    final String todayStart = DateTime.now()
        .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0)
        .toIso8601String();
    final List<Map<String, dynamic>> maps = await db.query(
      tableFieldAssets,
      where: 'created_at >= ?',
      whereArgs: [todayStart],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => FieldAsset.fromMap(map)).toList();
  }

  /// Senkronizasyon durumuna gore varliklari getir
  Future<List<FieldAsset>> getAssetsBySyncStatus(String syncStatus) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableFieldAssets,
      where: 'sync_status = ?',
      whereArgs: [syncStatus],
      orderBy: 'created_at ASC',
    );
    return maps.map((map) => FieldAsset.fromMap(map)).toList();
  }

  /// Senkronizasyon bekleyen varlik sayisi
  Future<int> getPendingSyncCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableFieldAssets WHERE sync_status = ?',
      [SyncStatus.pendingSync],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Senkronizasyon durumunu guncelle
  Future<void> updateSyncStatus(
    String assetId,
    String syncStatus, {
    String? photoUrl,
  }) async {
    final db = await database;
    final Map<String, dynamic> values = {
      'sync_status': syncStatus,
    };
    if (syncStatus == SyncStatus.synced) {
      values['synced_at'] = DateTime.now().toIso8601String();
    }
    if (photoUrl != null) {
      values['photo_url'] = photoUrl;
    }
    await db.update(
      tableFieldAssets,
      values,
      where: 'id = ?',
      whereArgs: [assetId],
    );
  }

  /// Varlik tipine gore filtrele
  Future<List<FieldAsset>> getAssetsByType(String assetType) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableFieldAssets,
      where: 'asset_type = ?',
      whereArgs: [assetType],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => FieldAsset.fromMap(map)).toList();
  }

  /// Senkronizasyon istatistikleri
  Future<Map<String, int>> getSyncStats() async {
    final db = await database;
    final pendingResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableFieldAssets WHERE sync_status = ?',
      [SyncStatus.pendingSync],
    );
    final syncedResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableFieldAssets WHERE sync_status = ?',
      [SyncStatus.synced],
    );
    final failedResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableFieldAssets WHERE sync_status = ?',
      [SyncStatus.syncFailed],
    );
    return {
      'pending': Sqflite.firstIntValue(pendingResult) ?? 0,
      'synced': Sqflite.firstIntValue(syncedResult) ?? 0,
      'failed': Sqflite.firstIntValue(failedResult) ?? 0,
    };
  }

  // --- Sync Queue ---

  /// Senkronizasyon kuyruğuna ekle
  Future<void> addToSyncQueue({
    required String assetLocalId,
    required String action,
    required String payloadJson,
  }) async {
    final db = await database;
    await db.insert(tableSyncQueue, {
      'asset_local_id': assetLocalId,
      'action': action,
      'payload_json': payloadJson,
      'retry_count': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Senkronizasyon kuyruğundaki bekleyen kayitlari getir
  Future<List<Map<String, dynamic>>> getPendingSyncQueueItems({
    int limit = 5,
  }) async {
    final db = await database;
    return await db.query(
      tableSyncQueue,
      where: 'retry_count < ?',
      whereArgs: [3],
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  /// Senkronizasyon kuyruğu kaydini sil (basarili sync sonrasi)
  Future<void> removeSyncQueueItem(int queueId) async {
    final db = await database;
    await db.delete(
      tableSyncQueue,
      where: 'id = ?',
      whereArgs: [queueId],
    );
  }

  /// Senkronizasyon kuyruğu hata sayacini artir
  Future<void> incrementSyncQueueRetry(int queueId, String error) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE $tableSyncQueue SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
      [error, queueId],
    );
  }

  /// Veritabanini kapat
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
