import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/device_service.dart';
import 'two_factor_setup_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final deviceInfo = await DeviceService.getDeviceInfo();
      final res = await ApiService().post('/auth/register', {
        'email': _emailCtrl.text.trim().toLowerCase(),
        'password': _passwordCtrl.text,
        'username': _usernameCtrl.text.trim().toLowerCase(),
        'display_name': _displayNameCtrl.text.trim(),
        'device_info': deviceInfo,
      });

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TwoFactorSetupScreen(
            userId: res['user_id'] as String,
            totpSecret: res['totp_secret'] as String,
            totpUri: res['totp_uri'] as String,
            warning: res['warning'] as String? ?? '',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'خطا در ارتباط با سرور');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ثبت‌نام')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ایجاد حساب جدید',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'بعد از ثبت‌نام، فعال‌سازی Google Authenticator اجباری است.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _displayNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'نام نمایشی',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'حداقل ۲ کاراکتر'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'نام کاربری',
                    prefixIcon: Icon(Icons.alternate_email),
                    helperText: 'فقط حروف کوچک، عدد و _',
                  ),
                  validator: (v) {
                    if (v == null || v.length < 3) return 'حداقل ۳ کاراکتر';
                    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(v))
                      return 'فرمت نامعتبر';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'ایمیل',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    if (v == null || !v.contains('@')) return 'ایمیل نامعتبر';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'رمز عبور',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.length < 8) ? 'حداقل ۸ کاراکتر' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('ثبت‌نام و ادامه'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
