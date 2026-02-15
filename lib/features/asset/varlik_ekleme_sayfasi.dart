import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/services/camera_service.dart';
import '../../core/services/gps_service.dart';
import '../../core/theme/field_theme.dart';
import '../../data/local/database_helper.dart';
import '../../data/models/field_asset.dart';

/// Varlik ekleme ekrani
/// GPS konumu otomatik alinir, fotograf cekilir, form doldurulur
class VarlikEklemeSayfasi extends StatefulWidget {
  final double latitude;
  final double longitude;
  final double? altitude;
  final double gpsAccuracy;
  final String initialAssetType;

  const VarlikEklemeSayfasi({
    super.key,
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.gpsAccuracy,
    this.initialAssetType = AssetType.agac,
  });

  @override
  State<VarlikEklemeSayfasi> createState() => _VarlikEklemeSayfasiState();
}

class _VarlikEklemeSayfasiState extends State<VarlikEklemeSayfasi> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final CameraService _cameraService = CameraService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _treeAgeController = TextEditingController();
  final TextEditingController _treeHeightController = TextEditingController();

  late String _selectedAssetType;
  String? _selectedTreeSpecies;
  String? _selectedHealthStatus;
  String? _photoLocalPath;
  bool _isSaving = false;
  bool _iotConnected = false;

  @override
  void initState() {
    super.initState();
    _selectedAssetType = widget.initialAssetType;
    _nameController.text = _generateDefaultName();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _treeAgeController.dispose();
    _treeHeightController.dispose();
    super.dispose();
  }

  String _generateDefaultName() {
    final DateTime now = DateTime.now();
    final String typeDisplay = AssetType.displayName(_selectedAssetType);
    return '$typeDisplay ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _handleCapturePhoto() async {
    final CapturedPhoto? photo = await _cameraService.capturePhoto(
      latitude: widget.latitude,
      longitude: widget.longitude,
    );
    if (photo != null && mounted) {
      setState(() {
        _photoLocalPath = photo.localPath;
      });
    }
  }

  Future<void> _handleSave() async {
    if (_nameController.text.trim().isEmpty) {
      _showSnackBar('Lutfen bir isim giriniz', isError: true);
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('user_id');
      final FieldAsset asset = FieldAsset(
        id: const Uuid().v4(),
        name: _nameController.text.trim(),
        assetType: _selectedAssetType,
        latitude: widget.latitude,
        longitude: widget.longitude,
        altitude: widget.altitude,
        gpsAccuracy: widget.gpsAccuracy,
        photoLocalPath: _photoLocalPath,
        treeSpecies: _selectedAssetType == AssetType.agac ? _selectedTreeSpecies : null,
        treeAge: _selectedAssetType == AssetType.agac && _treeAgeController.text.isNotEmpty
            ? int.tryParse(_treeAgeController.text)
            : null,
        treeHeight: _selectedAssetType == AssetType.agac && _treeHeightController.text.isNotEmpty
            ? double.tryParse(_treeHeightController.text)
            : null,
        healthStatus: _selectedHealthStatus,
        notes: _notesController.text.isNotEmpty ? _notesController.text.trim() : null,
        iotConnected: _iotConnected,
        userId: userId,
        syncStatus: SyncStatus.pendingSync,
        createdAt: DateTime.now(),
      );
      await _dbHelper.insertAsset(asset);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _showSnackBar('Kayit hatasi: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? FieldTheme.errorRed : FieldTheme.successGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Varlik Ekle'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _handleSave,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: FieldTheme.textOnPrimary,
                    ),
                  )
                : const Text(
                    'Kaydet',
                    style: TextStyle(
                      color: FieldTheme.textOnPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGpsInfo(),
            const SizedBox(height: 16),
            _buildPhotoSection(),
            const SizedBox(height: 16),
            _buildAssetTypeSelector(),
            const SizedBox(height: 16),
            _buildNameField(),
            if (_selectedAssetType == AssetType.agac) ...[
              const SizedBox(height: 16),
              _buildTreeDetails(),
            ],
            const SizedBox(height: 16),
            _buildHealthSelector(),
            const SizedBox(height: 16),
            _buildNotesField(),
            const SizedBox(height: 16),
            _buildIotToggle(),
            const SizedBox(height: 32),
            _buildSaveButton(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsInfo() {
    final GpsAccuracyLevel level =
        GpsService.calculateAccuracyLevel(widget.gpsAccuracy);
    final Color accuracyColor = _getAccuracyColor(level);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accuracyColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accuracyColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.gps_fixed, color: accuracyColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Konum: ${widget.latitude.toStringAsFixed(6)}, ${widget.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hassasiyet: ${widget.gpsAccuracy.toStringAsFixed(1)}m (${GpsService.accuracyLevelDisplayName(level)})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: accuracyColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fotograf',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _handleCapturePhoto,
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: FieldTheme.backgroundLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FieldTheme.dividerColor),
            ),
            child: _photoLocalPath != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(_photoLocalPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return const Center(
                              child: Icon(Icons.image, size: 48, color: FieldTheme.textSecondary),
                            );
                          },
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.black54,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
                              onPressed: _handleCapturePhoto,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt, size: 48, color: FieldTheme.textSecondary),
                      SizedBox(height: 8),
                      Text(
                        'Fotograf Cek',
                        style: TextStyle(
                          fontSize: 16,
                          color: FieldTheme.textSecondary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Opsiyonel - atlamak icin bos birakin',
                        style: TextStyle(
                          fontSize: 12,
                          color: FieldTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildAssetTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Varlik Tipi',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AssetType.all.map((String type) {
            final bool isSelected = type == _selectedAssetType;
            return ChoiceChip(
              label: Text(
                AssetType.displayName(type),
                style: TextStyle(
                  color: isSelected ? FieldTheme.textOnPrimary : FieldTheme.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              avatar: Icon(
                _getIconForType(type),
                color: isSelected ? FieldTheme.textOnPrimary : FieldTheme.primaryGreen,
                size: 20,
              ),
              selected: isSelected,
              selectedColor: FieldTheme.primaryGreen,
              backgroundColor: FieldTheme.backgroundLight,
              onSelected: (bool selected) {
                setState(() {
                  _selectedAssetType = type;
                  _nameController.text = _generateDefaultName();
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      style: const TextStyle(fontSize: 16),
      decoration: const InputDecoration(
        labelText: 'Varlik Adi',
        prefixIcon: Icon(Icons.label_outline),
      ),
    );
  }

  Widget _buildTreeDetails() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Agac Detaylari',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            // Tur secimi
            DropdownButtonFormField<String>(
              value: _selectedTreeSpecies,
              decoration: const InputDecoration(
                labelText: 'Agac Turu',
                prefixIcon: Icon(Icons.eco),
              ),
              items: TreeSpecies.all.map((String species) {
                return DropdownMenuItem<String>(
                  value: species,
                  child: Text(species),
                );
              }).toList(),
              onChanged: (String? value) {
                setState(() {
                  _selectedTreeSpecies = value;
                });
              },
            ),
            const SizedBox(height: 12),
            // Yas ve boy yan yana
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _treeAgeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Yas (yil)',
                      prefixIcon: Icon(Icons.calendar_today),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _treeHeightController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Boy (m)',
                      prefixIcon: Icon(Icons.height),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Saglik Durumu',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: HealthStatus.all.map((String status) {
            final bool isSelected = status == _selectedHealthStatus;
            return ChoiceChip(
              label: Text(
                HealthStatus.displayName(status),
                style: TextStyle(
                  color: isSelected ? FieldTheme.textOnPrimary : FieldTheme.textPrimary,
                ),
              ),
              selected: isSelected,
              selectedColor: _getHealthColor(status),
              backgroundColor: FieldTheme.backgroundLight,
              onSelected: (bool selected) {
                setState(() {
                  _selectedHealthStatus = selected ? status : null;
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesController,
      maxLines: 3,
      style: const TextStyle(fontSize: 16),
      decoration: const InputDecoration(
        labelText: 'Notlar (opsiyonel)',
        prefixIcon: Icon(Icons.note_alt_outlined),
        alignLabelWithHint: true,
      ),
    );
  }

  Widget _buildIotToggle() {
    return SwitchListTile(
      title: const Text('IoT Baglantisi'),
      subtitle: const Text('Bu varliga IoT sensor bagli mi?'),
      value: _iotConnected,
      activeColor: FieldTheme.primaryGreen,
      onChanged: (bool value) {
        setState(() {
          _iotConnected = value;
        });
      },
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _handleSave,
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FieldTheme.textOnPrimary,
                ),
              )
            : const Icon(Icons.save),
        label: Text(
          _isSaving ? 'Kaydediliyor...' : 'Kaydet ve Haritaya Don',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }

  Color _getAccuracyColor(GpsAccuracyLevel level) {
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

  Color _getHealthColor(String status) {
    switch (status) {
      case HealthStatus.excellent:
        return FieldTheme.gpsExcellent;
      case HealthStatus.good:
        return FieldTheme.gpsGood;
      case HealthStatus.fair:
        return FieldTheme.gpsFair;
      case HealthStatus.poor:
        return FieldTheme.gpsPoor;
      default:
        return FieldTheme.textSecondary;
    }
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
