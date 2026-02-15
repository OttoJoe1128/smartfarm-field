import 'dart:io';

/// API yapilandirma sabitleri
class ApiConfig {
  ApiConfig._();

  /// Backend sunucu adresi - ortama gore otomatik belirlenir
  ///
  /// Oncelik sirasi:
  /// 1. SMARTFARM_API_URL ortam degiskeni (varsa)
  /// 2. Android emulator: http://10.0.2.2:8000/api/v1
  /// 3. Fiziksel cihaz: http://192.168.1.x:8000/api/v1 (elle ayarlanmali)
  ///
  /// IDX uzerinde calisirken ortam degiskenini ayarlayin:
  ///   export SMARTFARM_API_URL=https://8000-xxx.cloudworkstations.dev/api/v1
  static String get baseUrl {
    // Ortam degiskeninden oku (IDX ve ozel durumlar icin)
    final String? envUrl = Platform.environment['SMARTFARM_API_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl;
    }
    // Varsayilan: Android emulator localhost adresi
    return _defaultBaseUrl;
  }

  /// Varsayilan backend adresi
  static const String _defaultBaseUrl = 'http://10.0.2.2:8000/api/v1';

  /// Baglanti zaman asimi (saniye)
  static const int connectTimeoutSeconds = 15;

  /// Yanit zaman asimi (saniye)
  static const int receiveTimeoutSeconds = 15;

  /// Sync ayarlari
  static const int syncIntervalSeconds = 30;
  static const int maxRetryCount = 3;
  static const int maxBatchSize = 5;

  /// GPS ayarlari
  static const double minimumAccuracyMeters = 15.0;
  static const double jumpDistanceWarningMeters = 50.0;
  static const double excellentAccuracyMeters = 2.0;
  static const double goodAccuracyMeters = 5.0;
  static const double fairAccuracyMeters = 10.0;
}
