import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/api_config.dart';
import '../models/field_asset.dart';

/// Saha uygulamasi Backend API istemcisi
/// Mevcut auth sistemi ile uyumlu JWT tabanli iletisim
class SahaApiService {
  late final Dio _dio;

  SahaApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: Duration(seconds: ApiConfig.connectTimeoutSeconds),
      receiveTimeout: Duration(seconds: ApiConfig.receiveTimeoutSeconds),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));
  }

  /// Her istekte Authorization header ekle
  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('access_token');
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  /// 401 hatasi icin token yenileme
  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    if (error.response?.statusCode == 401) {
      final bool isRefreshed = await _tryRefreshToken();
      if (isRefreshed) {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final String? newToken = prefs.getString('access_token');
        error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
        final Response<dynamic> response = await _dio.fetch(error.requestOptions);
        return handler.resolve(response);
      }
    }
    handler.next(error);
  }

  /// Token yenileme
  Future<bool> _tryRefreshToken() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? refreshToken = prefs.getString('refresh_token');
      if (refreshToken == null) return false;
      final Response<dynamic> response = await Dio(BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
      )).post('/auth/refresh', data: {'refresh_token': refreshToken});
      final Map<String, dynamic> data = response.data as Map<String, dynamic>;
      await prefs.setString('access_token', data['access_token'] as String);
      await prefs.setString('refresh_token', data['refresh_token'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- Auth ---

  /// Email/sifre ile giris
  Future<Map<String, dynamic>> login(String email, String password) async {
    final Response<dynamic> response = await _dio.post(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    return response.data as Map<String, dynamic>;
  }

  /// Mevcut kullanici bilgisi
  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final Response<dynamic> response = await _dio.get('/auth/me');
      return response.data as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Cikis
  Future<void> logout() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? refreshToken = prefs.getString('refresh_token');
      if (refreshToken != null) {
        await _dio.post('/auth/logout', data: {'refresh_token': refreshToken});
      }
    } catch (_) {
      // Logout hatasi onemli degil
    }
  }

  // --- GIS Asset ---

  /// Tek varlik ekle
  Future<bool> addAsset(FieldAsset asset) async {
    try {
      final Response<dynamic> response = await _dio.post(
        '/gis/add-asset',
        data: asset.toApiPayload(),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Asset ekleme hatasi: $e');
      return false;
    }
  }

  /// Toplu varlik ekle (batch)
  Future<Map<String, dynamic>> batchAddAssets(List<FieldAsset> assets) async {
    try {
      final List<Map<String, dynamic>> payloads =
          assets.map((FieldAsset a) => a.toApiPayload()).toList();
      final Response<dynamic> response = await _dio.post(
        '/gis/batch-add-assets',
        data: {'assets': payloads},
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Batch asset ekleme hatasi: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// Fotografi Firebase Storage'a yukle
  /// Not: Gercek Firebase Storage upload'u sync_service icerisinde yapilir
  /// Bu method sadece API uzerinden dosya yukleme alternatifi icin
  Future<String?> uploadPhoto(File file, String assetId) async {
    try {
      final String fileName = file.path.split('/').last;
      final FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: fileName),
        'asset_id': assetId,
      });
      final Response<dynamic> response = await _dio.post(
        '/gis/upload-photo',
        data: formData,
      );
      return (response.data as Map<String, dynamic>)['url'] as String?;
    } catch (e) {
      debugPrint('Fotograf yukleme hatasi: $e');
      return null;
    }
  }

  /// Harita verilerini getir
  Future<List<dynamic>> getMapData() async {
    try {
      final Response<dynamic> response = await _dio.get('/gis/map');
      return response.data as List<dynamic>;
    } catch (e) {
      debugPrint('Harita verisi alma hatasi: $e');
      return [];
    }
  }
}
