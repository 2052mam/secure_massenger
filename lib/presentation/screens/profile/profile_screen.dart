import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/api_constants.dart';
import '../../widgets/chat/chat_avatar.dart';
import 'dart:io';

import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authNotifierProvider).valueOrNull;
    if (user != null) {
      _nameCtrl.text = user.displayName;
      _usernameCtrl.text = user.username;
      _bioCtrl.text = user.bio ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_loading || _saving) return;
    final api = ref.read(authenticatedSessionProvider).api;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _loading = true);
    try {
      final uploadRes = await api.uploadFile(
        '/media/upload',
        File(picked.path),
      );
      final mediaId = uploadRes['id'] as String;
      final fullUrl = '${ApiConstants.baseUrl}/media/$mediaId';
      await api.put('/users/me', {'avatar_url': fullUrl});
      if (!mounted) return;
      await ref.read(authNotifierProvider.notifier).checkSession();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('عکس پروفایل به‌روز شد')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeAvatar() async {
    if (_loading || _saving) return;
    final isFa = ref.read(localeProvider).languageCode == 'fa';
    final api = ref.read(authenticatedSessionProvider).api;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFa ? 'حذف عکس پروفایل؟' : 'Remove profile photo?'),
        content: Text(
          isFa
              ? 'پروفایل شما بدون عکس نمایش داده می‌شود.'
              : 'Your profile will be shown without a photo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isFa ? 'لغو' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isFa ? 'حذف' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await api.put('/users/me', {'avatar_url': null});
      if (!mounted) return;
      await ref.read(authNotifierProvider.notifier).checkSession();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_loading || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(authenticatedSessionProvider).api.put('/users/me', {
        'display_name': _nameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim().toLowerCase(),
        'bio': _bioCtrl.text.trim(),
      });
      if (!mounted) return;
      await ref.read(authNotifierProvider.notifier).checkSession();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('پروفایل ذخیره شد')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFa = ref.watch(localeProvider).languageCode == 'fa';
    final user = ref.watch(authNotifierProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(isFa ? 'ویرایش پروفایل' : 'Edit Profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isFa ? 'ذخیره' : 'Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              GestureDetector(
                onTap: _loading ? null : _pickAvatar,
                child: Stack(
                  children: [
                    ChatAvatar(
                      radius: 56,
                      title: user?.displayName ?? '?',
                      url: user?.avatarUrl,
                      token: ref.watch(authenticatedSessionProvider).token,
                    ),
                    if (_loading)
                      const Positioned.fill(child: CircularProgressIndicator())
                    else
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          child: const Icon(
                            Icons.camera_alt,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (user?.avatarUrl?.isNotEmpty == true)
                TextButton.icon(
                  key: const ValueKey('remove-profile-photo'),
                  onPressed: _loading || _saving ? null : _removeAvatar,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    isFa ? 'حذف عکس پروفایل' : 'Remove profile photo',
                  ),
                ),
              const SizedBox(height: 32),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: isFa ? 'نام نمایشی' : 'Display Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _usernameCtrl,
                decoration: InputDecoration(
                  labelText: isFa ? 'نام کاربری' : 'Username',
                  prefixText: '@',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _bioCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: isFa ? 'بایو' : 'Bio',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
