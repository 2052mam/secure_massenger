import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../data/services/api_service.dart';
import '../../../data/models/user_model.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';

class TwoFactorSetupScreen extends ConsumerStatefulWidget {
  final String userId;
  final String totpSecret;
  final String totpUri;
  final String warning;

  const TwoFactorSetupScreen({
    super.key,
    required this.userId,
    required this.totpSecret,
    required this.totpUri,
    required this.warning,
  });

  @override
  ConsumerState<TwoFactorSetupScreen> createState() =>
      _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends ConsumerState<TwoFactorSetupScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
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
      final res = await ApiService().post('/auth/verify-2fa', {
        'user_id': widget.userId,
        'code': _codeCtrl.text.trim(),
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
      if (mounted) setState(() => _error = 'خطا در تأیید کد');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فعال‌سازی امنیت دو مرحله‌ای'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.warning.isNotEmpty
                            ? widget.warning
                            : 'کلید 2FA فقط یک‌بار نمایش داده می‌شود و قابل بازیابی نیست. حتماً آن را در Google Authenticator ذخیره کنید.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'QR کد را با Google Authenticator اسکن کنید',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: widget.totpUri,
                  version: QrVersions.auto,
                  size: 200,
                ),
              ),
              const SizedBox(height: 16),
              const Text('یا کلید را دستی وارد کنید:'),
              const SizedBox(height: 8),
              SelectableText(
                widget.totpSecret,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.totpSecret));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('کلید کپی شد')));
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('کپی کلید'),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(
                  labelText: 'کد ۶ رقمی',
                  counterText: '',
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                  onPressed: _loading ? null : _verify,
                  child: _loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('تأیید و ورود'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
