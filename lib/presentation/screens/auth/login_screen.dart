import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/device_service.dart';
import '../../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';
import 'register_screen.dart';
import 'two_factor_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // مرحله اول: فقط ایمیل و پسورد → سرور می‌گوید 2FA لازم است
      final res = await ApiService().post('/auth/login', {
        'email': _emailCtrl.text.trim(),
        'password': _passwordCtrl.text,
        'device_info': await DeviceService.getDeviceInfo(),
      });

      if (!mounted) return;
      // اگر مستقیم توکن داد (نباید اتفاق بیفتد چون 2FA اجباری است)
      if (res['access_token'] != null) {
        await _saveSession(res);
        return;
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401 && e.message.contains('2FA')) {
        // برو صفحه 2FA
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TwoFactorScreen(
              email: _emailCtrl.text.trim(),
              password: _passwordCtrl.text,
              isLogin: true,
            ),
          ),
        );
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'خطا در ارتباط با سرور');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSession(Map<String, dynamic> res) async {
    final user = UserModel.fromJson(res['user'] as Map<String, dynamic>);
    await ref
        .read(authNotifierProvider.notifier)
        .setLoggedIn(
          user,
          res['access_token'] as String,
          res['refresh_token'] as String? ?? '',
        );
    // app.dart resets the auth route stack after the identity changes.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 72,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ورود به SecureMessenger',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ایمیل و رمز عبور خود را وارد کنید',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'ایمیل',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'ایمیل الزامی است';
                      if (!v.contains('@')) return 'ایمیل نامعتبر';
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
                    validator: (v) {
                      if (v == null || v.length < 8) return 'حداقل ۸ کاراکتر';
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
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
                          : const Text('ورود'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      );
                    },
                    child: const Text('حساب ندارید؟ ثبت‌نام کنید'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
