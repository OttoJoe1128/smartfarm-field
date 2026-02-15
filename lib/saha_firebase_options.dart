// SmartFarm Field - Firebase yapilandirmasi
// NOT: Bu dosya gercek degerlerle guncellenmeli.
// Gercek konfigurasyonu almak icin:
//   cd smartfarm_field && flutterfire configure
// veya Firebase Console'dan google-services.json indirip
//   android/app/ klasorune yerlestiriniz.
//
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// SmartFarm Field [FirebaseOptions]
/// Ayni Firebase projesi kullanilir (farm-3aa9a)
class SahaFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'SmartFarm Field sadece Android platformunda calisir.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'SmartFarm Field sadece Android platformunda calisir. '
          'Mevcut platform: $defaultTargetPlatform',
        );
    }
  }

  // TODO: flutterfire configure calistirildiktan sonra
  // asagidaki degerleri gercek degerlerle degistirin.
  // Firebase Console > Project Settings > General > Your apps > Android
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAsTm5vl_OT7r1X23QT3nw0i4lrUKZ5JVk',
    appId: '1:344171333900:android:PLACEHOLDER_APP_ID',
    messagingSenderId: '344171333900',
    projectId: 'farm-3aa9a',
    storageBucket: 'farm-3aa9a.firebasestorage.app',
  );
}
