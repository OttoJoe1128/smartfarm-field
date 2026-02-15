/// API yapilandirma sabitleri
class ApiConfig {
  ApiConfig._();

  /// Backend sunucu adresi
  /// Gelistirme ortaminda yerel IP kullanilir
  /// Uretim ortaminda gercek sunucu adresi kullanilir
  static const String baseUrl = 'http://10.0.2.2:8000/api/v1';

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
