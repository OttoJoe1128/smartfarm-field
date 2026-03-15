import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/api_config.dart';
import '../models/field_asset.dart';
import '../models/fault_record.dart';
import '../models/parcel.dart';

/// Standart API yanit modeli
class ApiYanit {
  final bool isSuccess;
  final String status;
  final String? errorCode;
  final String? message;
  final int? version;
  final dynamic data;
  const ApiYanit({
    required this.isSuccess,
    required this.status,
    this.errorCode,
    this.message,
    this.version,
    this.data,
  });
  Map<String, dynamic> toMap() {
    return {
      'is_success': isSuccess,
      'status': status,
      'error_code': errorCode,
      'message': message,
      'version': version,
      'data': data,
    };
  }
}

/// Saha uygulamasi Backend API istemcisi
/// Mevcut auth sistemi ile uyumlu JWT tabanli iletisim
class SahaApiService {
  late final Dio _dio;

  SahaApiService() {
    final String resolvedUrl = ApiConfig.baseUrl;
    debugPrint('SahaApiService: Backend URL = $resolvedUrl');
    _dio = Dio(BaseOptions(
      baseUrl: resolvedUrl,
      connectTimeout: const Duration(seconds: ApiConfig.connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: ApiConfig.receiveTimeoutSeconds),
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
      final ApiYanit apiYanit = _parseApiYanit(response);
      return apiYanit.isSuccess;
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
      return _parseApiYanit(response).toMap();
    } catch (e) {
      debugPrint('Batch asset ekleme hatasi: $e');
      return _buildErrorYanit(error: e, fallbackCode: 'BATCH_SYNC_ERROR').toMap();
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
      final ApiYanit apiYanit = _parseApiYanit(response);
      if (!apiYanit.isSuccess) {
        return null;
      }
      if (apiYanit.data is Map<String, dynamic>) {
        return (apiYanit.data as Map<String, dynamic>)['url'] as String?;
      }
      if (response.data is Map<String, dynamic>) {
        return (response.data as Map<String, dynamic>)['url'] as String?;
      }
      return null;
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

  // --- Fault Reporting ---

  /// Ariza kaydi olustur
  Future<Map<String, dynamic>> addFaultRecord(FaultRecord fault) async {
    try {
      final Response<dynamic> response = await _dio.post(
        '/gis/add-fault',
        data: fault.toApiPayload(),
      );
      return _parseApiYanit(response).toMap();
    } catch (e) {
      debugPrint('Ariza kaydi ekleme hatasi: $e');
      return _buildErrorYanit(error: e, fallbackCode: 'ADD_FAULT_ERROR').toMap();
    }
  }

  /// Ariza kaydini cozuldu olarak isaretle
  Future<Map<String, dynamic>> resolveFaultRecord(FaultRecord fault) async {
    try {
      final Response<dynamic> response = await _dio.post(
        '/gis/resolve-fault',
        data: {
          'fault_id': fault.id,
          'asset_id': fault.assetId,
          'status': 'resolved',
          'resolved_at': (fault.resolvedAt ?? DateTime.now()).toIso8601String(),
        },
      );
      return _parseApiYanit(response).toMap();
    } catch (e) {
      debugPrint('Ariza cozme hatasi: $e');
      return _buildErrorYanit(
        error: e,
        fallbackCode: 'RESOLVE_FAULT_ERROR',
      ).toMap();
    }
  }

  // --- Parcel ---

  /// Kullaniciya ait parselleri getir
  Future<List<Parcel>> getUserParcels() async {
    try {
      final Response<dynamic> response = await _dio.get('/gis/parcels');
      final List<dynamic> data = response.data as List<dynamic>;
      return data.map((json) => Parcel.fromMap(json)).toList();
    } catch (e) {
      debugPrint('Parsel verisi alma hatasi: $e');
      return [];
    }
  }

  ApiYanit _parseApiYanit(Response<dynamic> response) {
    final int statusCode = response.statusCode ?? 0;
    final bool isHttpSuccess = statusCode >= 200 && statusCode < 300;
    final dynamic body = response.data;
    if (body is Map<String, dynamic>) {
      final String statusText = (body['status'] as String?) ?? (isHttpSuccess ? 'ok' : 'error');
      final String? errorCodeText = (body['error_code'] as String?) ?? (body['code'] as String?);
      final String? messageText = body['message'] as String?;
      final int? versionValue = body['version'] is int ? body['version'] as int : null;
      final dynamic dataNode = body.containsKey('data') ? body['data'] : body;
      return ApiYanit(
        isSuccess: statusText == 'ok' && isHttpSuccess,
        status: statusText,
        errorCode: errorCodeText,
        message: messageText,
        version: versionValue,
        data: dataNode,
      );
    }
    if (body is List) {
      return ApiYanit(
        isSuccess: isHttpSuccess,
        status: isHttpSuccess ? 'ok' : 'error',
        version: null,
        data: body,
      );
    }
    return ApiYanit(
      isSuccess: isHttpSuccess,
      status: isHttpSuccess ? 'ok' : 'error',
      version: null,
      data: body,
    );
  }

  ApiYanit _buildErrorYanit({
    required Object error,
    required String fallbackCode,
  }) {
    if (error is DioException) {
      final int statusCode = error.response?.statusCode ?? 0;
      String? errorCodeText;
      String? messageText;
      final dynamic body = error.response?.data;
      if (body is Map<String, dynamic>) {
        errorCodeText = (body['error_code'] as String?) ?? (body['code'] as String?);
        messageText = body['message'] as String?;
      }
      return ApiYanit(
        isSuccess: false,
        status: 'error',
        errorCode: errorCodeText ?? (statusCode > 0 ? 'HTTP_$statusCode' : fallbackCode),
        message: messageText ?? error.message,
      );
    }
    return ApiYanit(
      isSuccess: false,
      status: 'error',
      errorCode: fallbackCode,
      message: error.toString(),
    );
  }
}
