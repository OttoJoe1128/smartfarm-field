import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/services/gps_service.dart';
import '../../core/theme/field_theme.dart';
import '../../data/local/database_helper.dart';
import '../../data/models/field_asset.dart';
import '../asset/varlik_ekleme_sayfasi.dart';
import '../asset/varlik_listesi_sayfasi.dart';
import '../sync/senkronizasyon_sayfasi.dart';

/// Ana saha harita ekrani
/// Tam ekran harita, GPS gostergesi ve hizli varlik ekleme
class SahaHaritaSayfasi extends StatefulWidget {
  final VoidCallback onLogout;

  const SahaHaritaSayfasi({super.key, required this.onLogout});

  @override
  State<SahaHaritaSayfasi> createState() => _SahaHaritaSayfasiState();
}

class _SahaHaritaSayfasiState extends State<SahaHaritaSayfasi> {
  final GpsService _gpsService = GpsService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final MapController _mapController = MapController();

  GpsPosition? _currentPosition;
  List<FieldAsset> _assets = [];
  int _pendingSyncCount = 0;
  String _selectedAssetType = AssetType.agac;
  bool _isGpsActive = false;
  int _currentNavIndex = 0;
  StreamSubscription<GpsPosition>? _gpsSubscription;

  @override
  void initState() {
    super.initState();
    _initializeGps();
    _loadAssets();
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    _gpsService.dispose();
    super.dispose();
  }

  Future<void> _initializeGps() async {
    try {
      final bool hasPermission = await _gpsService.hasPermission();
      if (!hasPermission) {
        await _gpsService.requestPermission();
      }
      await _gpsService.startHighAccuracyTracking();
      _gpsSubscription = _gpsService.positionStream.listen((GpsPosition pos) {
        if (mounted) {
          setState(() {
            _currentPosition = pos;
            _isGpsActive = true;
          });
        }
      });
      // Ilk konum al
      final GpsPosition initialPosition = await _gpsService.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = initialPosition;
          _isGpsActive = true;
        });
        _mapController.move(
          LatLng(initialPosition.latitude, initialPosition.longitude),
          17,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGpsActive = false;
        });
        _showSnackBar('GPS hatasi: $e', isError: true);
      }
    }
  }

  Future<void> _loadAssets() async {
    final List<FieldAsset> assets = await _dbHelper.getTodayAssets();
    final int pendingCount = await _dbHelper.getPendingSyncCount();
    if (mounted) {
      setState(() {
        _assets = assets;
        _pendingSyncCount = pendingCount;
      });
    }
  }

  Future<void> _handleAddAsset() async {
    if (_currentPosition == null) {
      _showSnackBar('GPS sinyali bekleniyor...', isError: true);
      return;
    }
    if (!GpsService.isAccuracySufficient(_currentPosition!.accuracy)) {
      final bool shouldProceed = await _showAccuracyWarning();
      if (!shouldProceed) return;
    }
    if (!mounted) return;
    final bool? result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (BuildContext context) => VarlikEklemeSayfasi(
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
          altitude: _currentPosition!.altitude,
          gpsAccuracy: _currentPosition!.accuracy,
          initialAssetType: _selectedAssetType,
        ),
      ),
    );
    if (result == true) {
      await _loadAssets();
      if (mounted) {
        _showSnackBar('Varlik basariyla eklendi');
      }
    }
  }

  Future<bool> _showAccuracyWarning() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Dusuk GPS Hassasiyeti'),
          content: Text(
            'Mevcut hassasiyet: ${_currentPosition!.accuracy.toStringAsFixed(1)}m\n\n'
            'Hassasiyet 15m\'den fazla. Konum bilgisi yanlis olabilir.\n'
            'Yine de devam etmek istiyor musunuz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Iptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Devam Et'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? FieldTheme.errorRed : FieldTheme.successGreen,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentNavIndex,
        children: [
          _buildMapView(),
          VarlikListesiSayfasi(onAssetChanged: _loadAssets),
          SenkronizasyonSayfasi(onSyncComplete: _loadAssets),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildMapView() {
    return Stack(
      children: [
        _buildMap(),
        _buildGpsIndicator(),
        _buildTopBar(),
        _buildAssetTypeSelector(),
        _buildAddButton(),
      ],
    );
  }

  Widget _buildMap() {
    final LatLng center = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(39.9334, 32.8597); // Ankara varsayilan

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 17,
        maxZoom: 22,
        minZoom: 3,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.smartfarmxr.smartfarm_field',
        ),
        // Mevcut konum marker
        if (_currentPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                ),
                width: 40,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: FieldTheme.primaryGreen.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(color: FieldTheme.primaryGreen, width: 3),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.my_location,
                      color: FieldTheme.primaryGreen,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        // Eklenmis varlik markerlari
        MarkerLayer(
          markers: _assets.map((FieldAsset asset) {
            return Marker(
              point: LatLng(asset.latitude, asset.longitude),
              width: 36,
              height: 36,
              child: _buildAssetMarker(asset),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAssetMarker(FieldAsset asset) {
    final Color markerColor = asset.isSynced
        ? FieldTheme.syncDone
        : asset.isSyncFailed
            ? FieldTheme.syncFailed
            : FieldTheme.syncPending;
    return Container(
      decoration: BoxDecoration(
        color: markerColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          _getIconForAssetType(asset.assetType),
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildGpsIndicator() {
    final Color indicatorColor = !_isGpsActive
        ? FieldTheme.gpsPoor
        : _currentPosition != null
            ? _getGpsColor(_currentPosition!.accuracyLevel)
            : FieldTheme.gpsPoor;
    final String accuracyText = _currentPosition != null
        ? '${_currentPosition!.accuracy.toStringAsFixed(1)}m'
        : 'Bekleniyor...';
    return Positioned(
      top: MediaQuery.of(context).padding.top + 80,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: FieldTheme.backgroundWhite,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: indicatorColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'GPS: $accuracyText',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: Row(
        children: [
          // Profil / Cikis butonu
          Container(
            decoration: BoxDecoration(
              color: FieldTheme.backgroundWhite,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.person, color: FieldTheme.primaryGreen),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (String value) {
                if (value == 'logout') {
                  widget.onLogout();
                }
              },
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: FieldTheme.errorRed),
                      SizedBox(width: 8),
                      Text('Cikis Yap'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Konuma git butonu
          Container(
            decoration: BoxDecoration(
              color: FieldTheme.backgroundWhite,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.my_location, color: FieldTheme.primaryGreen),
              onPressed: () {
                if (_currentPosition != null) {
                  _mapController.move(
                    LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    ),
                    17,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetTypeSelector() {
    return Positioned(
      bottom: 100,
      left: 16,
      right: 80,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: FieldTheme.backgroundWhite,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: AssetType.all.map((String type) {
            final bool isSelected = type == _selectedAssetType;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: FilterChip(
                label: Text(
                  AssetType.displayName(type),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? FieldTheme.textOnPrimary : FieldTheme.textPrimary,
                  ),
                ),
                avatar: Icon(
                  _getIconForAssetType(type),
                  size: 18,
                  color: isSelected ? FieldTheme.textOnPrimary : FieldTheme.primaryGreen,
                ),
                selected: isSelected,
                selectedColor: FieldTheme.primaryGreen,
                backgroundColor: FieldTheme.backgroundLight,
                onSelected: (bool selected) {
                  setState(() {
                    _selectedAssetType = type;
                  });
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return Positioned(
      bottom: 100,
      right: 16,
      child: FloatingActionButton.large(
        onPressed: _handleAddAsset,
        backgroundColor: FieldTheme.primaryGreen,
        heroTag: 'add_asset',
        child: const Icon(Icons.add, size: 36, color: Colors.white),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentNavIndex,
      onTap: (int index) {
        setState(() {
          _currentNavIndex = index;
        });
        if (index == 0) {
          _loadAssets();
        }
      },
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.map),
          label: 'Harita',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.list_alt),
          label: 'Liste',
        ),
        BottomNavigationBarItem(
          icon: Badge(
            isLabelVisible: _pendingSyncCount > 0,
            label: Text(
              '$_pendingSyncCount',
              style: const TextStyle(fontSize: 10),
            ),
            child: const Icon(Icons.sync),
          ),
          label: 'Senkronizasyon',
        ),
      ],
    );
  }

  IconData _getIconForAssetType(String type) {
    switch (type) {
      case AssetType.agac:
        return Icons.park;
      case AssetType.kuyu:
        return Icons.water_drop;
      case AssetType.sensor:
        return Icons.sensors;
      case AssetType.yapi:
        return Icons.home;
      case AssetType.gunes:
        return Icons.solar_power;
      case AssetType.olcum:
        return Icons.straighten;
      default:
        return Icons.place;
    }
  }

  Color _getGpsColor(GpsAccuracyLevel level) {
    switch (level) {
      case GpsAccuracyLevel.excellent:
        return FieldTheme.gpsExcellent;
      case GpsAccuracyLevel.good:
        return FieldTheme.gpsGood;
      case GpsAccuracyLevel.fair:
        return FieldTheme.gpsFair;
      case GpsAccuracyLevel.poor:
        return FieldTheme.gpsPoor;
    }
  }
}
