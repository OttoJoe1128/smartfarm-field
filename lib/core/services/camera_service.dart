import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Kamera ve fotograf servisi
/// Saha fotograflari cekme, yerel kaydetme ve EXIF geotagging
class CameraService {
  final ImagePicker _imagePicker = ImagePicker();

  /// Kameradan fotograf cek ve kaydet
  /// GPS koordinatlarini dosya adina gomer
  Future<CapturedPhoto?> capturePhoto({
    double? latitude,
    double? longitude,
  }) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (image == null) return null;
      final String savedPath = await _savePhotoLocally(
        image,
        latitude: latitude,
        longitude: longitude,
      );
      return CapturedPhoto(
        localPath: savedPath,
        latitude: latitude,
        longitude: longitude,
        capturedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Fotograf cekme hatasi: $e');
      return null;
    }
  }

  /// Galeriden fotograf sec ve kaydet
  Future<CapturedPhoto?> pickFromGallery({
    double? latitude,
    double? longitude,
  }) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (image == null) return null;
      final String savedPath = await _savePhotoLocally(
        image,
        latitude: latitude,
        longitude: longitude,
      );
      return CapturedPhoto(
        localPath: savedPath,
        latitude: latitude,
        longitude: longitude,
        capturedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('Galeri secim hatasi: $e');
      return null;
    }
  }

  /// Fotografi yerel dosya sistemine kaydet
  /// Dosya adi formatı: field_YYYYMMDD_HHmmss_lat_lon.jpg
  Future<String> _savePhotoLocally(
    XFile image, {
    double? latitude,
    double? longitude,
  }) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory photoDir = Directory(p.join(appDir.path, 'field_photos'));
    if (!await photoDir.exists()) {
      await photoDir.create(recursive: true);
    }
    final DateTime now = DateTime.now();
    final String timestamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    String fileName = 'field_$timestamp';
    if (latitude != null && longitude != null) {
      final String latStr = latitude.toStringAsFixed(6).replaceAll('.', '_');
      final String lonStr = longitude.toStringAsFixed(6).replaceAll('.', '_');
      fileName = '${fileName}_${latStr}_$lonStr';
    }
    fileName = '$fileName.jpg';
    final String savedPath = p.join(photoDir.path, fileName);
    final File sourceFile = File(image.path);
    await sourceFile.copy(savedPath);
    return savedPath;
  }

  /// Thumbnail olustur (liste gorunumu icin)
  /// Dosya adinin sonuna _thumb ekler
  Future<String?> createThumbnail(String originalPath) async {
    try {
      final File originalFile = File(originalPath);
      if (!await originalFile.exists()) return null;
      final String extension = p.extension(originalPath);
      final String baseName = p.basenameWithoutExtension(originalPath);
      final String dirPath = p.dirname(originalPath);
      final String thumbnailPath = p.join(dirPath, '${baseName}_thumb$extension');
      // Basit kopya - Flutter'da image paketleriyle resize yapilabilir
      await originalFile.copy(thumbnailPath);
      return thumbnailPath;
    } catch (e) {
      debugPrint('Thumbnail olusturma hatasi: $e');
      return null;
    }
  }

  /// Yerel fotograf dosyasini sil
  Future<bool> deletePhoto(String photoPath) async {
    try {
      final File file = File(photoPath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Fotograf silme hatasi: $e');
      return false;
    }
  }

  /// Fotograf dosyasinin var olup olmadigini kontrol et
  Future<bool> photoExists(String photoPath) async {
    return File(photoPath).exists();
  }

  /// Tum yerel fotograflarin toplam boyutunu hesapla (MB)
  Future<double> calculateTotalPhotoSize() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory photoDir = Directory(p.join(appDir.path, 'field_photos'));
      if (!await photoDir.exists()) return 0.0;
      int totalBytes = 0;
      await for (final FileSystemEntity entity in photoDir.list()) {
        if (entity is File) {
          totalBytes += await entity.length();
        }
      }
      return totalBytes / (1024 * 1024); // MB
    } catch (e) {
      debugPrint('Dosya boyutu hesaplama hatasi: $e');
      return 0.0;
    }
  }
}

/// Cekilmis fotograf verisi
class CapturedPhoto {
  final String localPath;
  final double? latitude;
  final double? longitude;
  final DateTime capturedAt;

  const CapturedPhoto({
    required this.localPath,
    this.latitude,
    this.longitude,
    required this.capturedAt,
  });
}
