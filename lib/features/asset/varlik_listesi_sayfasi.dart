import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/field_theme.dart';
import '../../data/local/database_helper.dart';
import '../../data/models/field_asset.dart';

/// Varlik listesi ekrani
/// Bugun eklenen varliklar, filtreleme, silme ve duzenleme
class VarlikListesiSayfasi extends StatefulWidget {
  final VoidCallback? onAssetChanged;

  const VarlikListesiSayfasi({super.key, this.onAssetChanged});

  @override
  State<VarlikListesiSayfasi> createState() => _VarlikListesiSayfasiState();
}

class _VarlikListesiSayfasiState extends State<VarlikListesiSayfasi> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<FieldAsset> _assets = [];
  bool _isLoading = true;
  String? _filterType;
  String? _filterSyncStatus;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    setState(() {
      _isLoading = true;
    });
    try {
      List<FieldAsset> assets;
      if (_filterType != null) {
        assets = await _dbHelper.getAssetsByType(_filterType!);
      } else if (_filterSyncStatus != null) {
        assets = await _dbHelper.getAssetsBySyncStatus(_filterSyncStatus!);
      } else {
        assets = await _dbHelper.getTodayAssets();
      }
      if (mounted) {
        setState(() {
          _assets = assets;
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

  Future<void> _handleDeleteAsset(FieldAsset asset) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Varligi Sil'),
          content: Text('${asset.name} varligini silmek istediginize emin misiniz?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Iptal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: FieldTheme.errorRed),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );
    if (confirm == true) {
      await _dbHelper.deleteAsset(asset.id);
      await _loadAssets();
      widget.onAssetChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Varlik silindi'),
            backgroundColor: FieldTheme.successGreen,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Varlik Listesi'),
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (String value) {
              setState(() {
                if (value == 'all') {
                  _filterType = null;
                  _filterSyncStatus = null;
                } else if (value.startsWith('type_')) {
                  _filterType = value.replaceFirst('type_', '');
                  _filterSyncStatus = null;
                } else if (value.startsWith('sync_')) {
                  _filterSyncStatus = value.replaceFirst('sync_', '');
                  _filterType = null;
                }
              });
              _loadAssets();
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'all',
                child: Text('Tumu (Bugun)'),
              ),
              const PopupMenuDivider(),
              ...AssetType.all.map((String type) {
                return PopupMenuItem<String>(
                  value: 'type_$type',
                  child: Text('Tip: ${AssetType.displayName(type)}'),
                );
              }),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'sync_${SyncStatus.pendingSync}',
                child: Text('Bekleyen'),
              ),
              const PopupMenuItem<String>(
                value: 'sync_${SyncStatus.synced}',
                child: Text('Senkronize'),
              ),
              const PopupMenuItem<String>(
                value: 'sync_${SyncStatus.syncFailed}',
                child: Text('Basarisiz'),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _assets.isEmpty
              ? _buildEmptyState()
              : _buildAssetList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: FieldTheme.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'Henuz varlik eklenmemis',
            style: TextStyle(
              fontSize: 18,
              color: FieldTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Harita ekraninda "+" butonuna basarak\nvarlik ekleyebilirsiniz',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: FieldTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetList() {
    return RefreshIndicator(
      onRefresh: _loadAssets,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _assets.length,
        itemBuilder: (BuildContext context, int index) {
          return _buildAssetCard(_assets[index]);
        },
      ),
    );
  }

  Widget _buildAssetCard(FieldAsset asset) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: _buildAssetLeading(asset),
        title: Text(
          asset.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${AssetType.displayName(asset.assetType)}'
              '${asset.treeSpecies != null ? ' - ${asset.treeSpecies}' : ''}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              '${asset.latitude.toStringAsFixed(5)}, ${asset.longitude.toStringAsFixed(5)} '
              '(${asset.gpsAccuracy.toStringAsFixed(1)}m)',
              style: const TextStyle(fontSize: 12, color: FieldTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            _buildSyncBadge(asset),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: FieldTheme.errorRed),
          onPressed: () => _handleDeleteAsset(asset),
        ),
      ),
    );
  }

  Widget _buildAssetLeading(FieldAsset asset) {
    if (asset.photoLocalPath != null) {
      final File photoFile = File(asset.photoLocalPath!);
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Image.file(
            photoFile,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildAssetIcon(asset),
          ),
        ),
      );
    }
    return _buildAssetIcon(asset);
  }

  Widget _buildAssetIcon(FieldAsset asset) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: FieldTheme.primaryGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _getIconForType(asset.assetType),
        color: FieldTheme.primaryGreen,
        size: 28,
      ),
    );
  }

  Widget _buildSyncBadge(FieldAsset asset) {
    Color badgeColor;
    String badgeText;
    IconData badgeIcon;
    switch (asset.syncStatus) {
      case SyncStatus.synced:
        badgeColor = FieldTheme.syncDone;
        badgeText = 'Senkronize';
        badgeIcon = Icons.check_circle;
        break;
      case SyncStatus.syncFailed:
        badgeColor = FieldTheme.syncFailed;
        badgeText = 'Basarisiz';
        badgeIcon = Icons.error;
        break;
      default:
        badgeColor = FieldTheme.syncPending;
        badgeText = 'Bekliyor';
        badgeIcon = Icons.schedule;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, size: 14, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            badgeText,
            style: TextStyle(fontSize: 12, color: badgeColor, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  IconData _getIconForType(String type) {
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
}
