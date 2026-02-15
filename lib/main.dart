import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/sync_service.dart';
import 'core/theme/field_theme.dart';
import 'data/remote/saha_api_service.dart';
import 'features/auth/saha_giris_sayfasi.dart';
import 'features/map/saha_harita_sayfasi.dart';
import 'saha_firebase_options.dart';

/// Firebase baslatildi mi flag
bool _isFirebaseInitialized = false;

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('Flutter Error: ${details.exception}');
    };
    // Firebase baslat - hata olursa uygulama Firebase olmadan da calisir
    try {
      await Firebase.initializeApp(
        options: SahaFirebaseOptions.currentPlatform,
      );
      _isFirebaseInitialized = true;
      debugPrint('Firebase basariyla baslatildi');
    } catch (e) {
      _isFirebaseInitialized = false;
      debugPrint('Firebase init hatasi: $e');
      debugPrint('Uygulama Firebase olmadan devam edecek. '
          'Fotograf yukleme ve sync devre disi olabilir.');
    }
    runApp(const SmartFarmFieldApp());
  }, (Object error, StackTrace stack) {
    debugPrint('Zone Error: $error');
  });
}

/// SmartFarm Field Ana Uygulama
class SmartFarmFieldApp extends StatefulWidget {
  const SmartFarmFieldApp({super.key});

  @override
  State<SmartFarmFieldApp> createState() => _SmartFarmFieldAppState();
}

class _SmartFarmFieldAppState extends State<SmartFarmFieldApp> {
  bool _isLoggedIn = false;
  bool _isLoading = true;
  final SyncService _syncService = SyncService();

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  @override
  void dispose() {
    _syncService.dispose();
    super.dispose();
  }

  Future<void> _checkAuthStatus() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('access_token');
      if (token != null && token.isNotEmpty) {
        // Token var, backend'den dogrula
        final SahaApiService apiService = SahaApiService();
        final Map<String, dynamic>? user = await apiService.getCurrentUser();
        if (mounted) {
          setState(() {
            _isLoggedIn = user != null;
            _isLoading = false;
          });
          if (_isLoggedIn) {
            _syncService.startAutoSync();
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoggedIn = false;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Auth kontrol hatasi: $e');
      if (mounted) {
        setState(() {
          _isLoggedIn = false;
          _isLoading = false;
        });
      }
    }
  }

  void _handleLoginSuccess() {
    setState(() {
      _isLoggedIn = true;
    });
    _syncService.startAutoSync();
  }

  Future<void> _handleLogout() async {
    _syncService.stopAutoSync();
    final SahaApiService apiService = SahaApiService();
    await apiService.logout();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      setState(() {
        _isLoggedIn = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartFarm Field',
      debugShowCheckedModeBanner: false,
      theme: FieldTheme.lightTheme,
      home: _isLoading
          ? _buildSplashScreen()
          : _isLoggedIn
              ? SahaHaritaSayfasi(onLogout: _handleLogout)
              : SahaGirisSayfasi(onLoginSuccess: _handleLoginSuccess),
    );
  }

  Widget _buildSplashScreen() {
    return Scaffold(
      backgroundColor: FieldTheme.primaryGreen,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.terrain,
                size: 64,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'SmartFarm Field',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Saha Veri Toplama',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
