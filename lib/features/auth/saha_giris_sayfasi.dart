import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/field_theme.dart';
import '../../data/remote/saha_api_service.dart';

/// Saha uygulamasi giris ekrani
/// Buyuk butonlar ve basit tasarim - saha kosullarinda kullanim icin
class SahaGirisSayfasi extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const SahaGirisSayfasi({super.key, required this.onLoginSuccess});

  @override
  State<SahaGirisSayfasi> createState() => _SahaGirisSayfasiState();
}

class _SahaGirisSayfasiState extends State<SahaGirisSayfasi> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final SahaApiService _apiService = SahaApiService();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final Map<String, dynamic> response = await _apiService.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', response['access_token'] as String);
      await prefs.setString('refresh_token', response['refresh_token'] as String);
      final Map<String, dynamic> user =
          response['user'] as Map<String, dynamic>;
      await prefs.setString('user_id', user['id'] as String);
      await prefs.setString('user_role', user['role'] as String);
      await prefs.setString('user_name', user['username'] as String);
      await prefs.setString('user_email', user['email'] as String);
      if (mounted) {
        widget.onLoginSuccess();
      }
    } catch (e) {
      setState(() {
        _errorMessage = _parseLoginError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _parseLoginError(dynamic error) {
    final String message = error.toString();
    if (message.contains('401') || message.contains('Gecersiz')) {
      return 'Gecersiz e-posta veya sifre';
    }
    if (message.contains('network') || message.contains('SocketException')) {
      return 'Baglanti hatasi. Internet baglantinizi kontrol edin.';
    }
    if (message.contains('timeout')) {
      return 'Sunucu yanit vermiyor. Daha sonra tekrar deneyin.';
    }
    return 'Giris yapilamadi. Lutfen tekrar deneyin.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLogo(),
                  const SizedBox(height: 48),
                  _buildEmailField(),
                  const SizedBox(height: 16),
                  _buildPasswordField(),
                  if (_errorMessage != null) _buildErrorMessage(),
                  const SizedBox(height: 32),
                  _buildLoginButton(),
                  const SizedBox(height: 16),
                  _buildInfoText(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: FieldTheme.primaryGreen,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.terrain,
            size: 48,
            color: FieldTheme.textOnPrimary,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'SmartFarm Field',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: FieldTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Saha Veri Toplama',
          style: TextStyle(
            fontSize: 16,
            color: FieldTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      style: const TextStyle(fontSize: 18),
      decoration: const InputDecoration(
        labelText: 'E-posta',
        prefixIcon: Icon(Icons.email_outlined, size: 28),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      ),
      validator: (String? value) {
        if (value == null || value.trim().isEmpty) {
          return 'E-posta adresi giriniz';
        }
        if (!value.contains('@')) {
          return 'Gecerli bir e-posta adresi giriniz';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: !_isPasswordVisible,
      textInputAction: TextInputAction.done,
      style: const TextStyle(fontSize: 18),
      decoration: InputDecoration(
        labelText: 'Sifre',
        prefixIcon: const Icon(Icons.lock_outlined, size: 28),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        suffixIcon: IconButton(
          icon: Icon(
            _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
            size: 28,
          ),
          onPressed: () {
            setState(() {
              _isPasswordVisible = !_isPasswordVisible;
            });
          },
        ),
      ),
      validator: (String? value) {
        if (value == null || value.isEmpty) {
          return 'Sifre giriniz';
        }
        return null;
      },
      onFieldSubmitted: (_) => _handleLogin(),
    );
  }

  Widget _buildErrorMessage() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: FieldTheme.errorRed.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FieldTheme.errorRed.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: FieldTheme.errorRed),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                  color: FieldTheme.errorRed,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        child: _isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FieldTheme.textOnPrimary,
                ),
              )
            : const Text(
                'Giris Yap',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _buildInfoText() {
    return const Text(
      'Hesabiniz yoksa yoneticinizle iletisime gecin',
      style: TextStyle(
        fontSize: 14,
        color: FieldTheme.textSecondary,
      ),
      textAlign: TextAlign.center,
    );
  }
}
