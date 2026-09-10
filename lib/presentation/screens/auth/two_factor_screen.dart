import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/device_service.dart';
import '../../../data/models/user_model.dart';
import '../../providers/auth_provider.dart';

class TwoFactorScreen extends ConsumerStatefulWidget {
  final String email;
  final String password;
  final bool isLogin;

  const TwoFactorScreen({
    super.key,
    required this.email,
    required this.password,
    this.isLogin = true,
  });

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (_codeCtrl.text.trim().length != 6) {
      setState(() => _error = 'کد ۶ رقمی وارد کنید');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ApiService().post('/auth/login', {
        'email': widget.email,
        'password': widget.password,
        'totp_code': _codeCtrl.text.trim(),
        'device_info': await DeviceService.getDeviceInfo(),
      });

      if (!mounted) return;
      final user = UserModel.fromJson(res['user'] as Map<String, dynamic>);
      await ref
          .read(authNotifierProvider.notifier)
          .setLoggedIn(
            user,
            res['access_token'] as String,
            res['refresh_token'] as String? ?? '',
          );

      // The session-keyed app Navigator now owns the transition to chats.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'خطا در ورود');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تأیید دو مرحله‌ای')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.security, size: 64, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                'کد Google Authenticator را وارد کنید',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, letterSpacing: 10),
                decoration: const InputDecoration(
                  labelText: 'کد ۶ رقمی',
                  counterText: '',
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
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
                      : const Text('تأیید'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
