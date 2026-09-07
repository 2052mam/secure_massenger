import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/api_constants.dart';
import '../../../data/services/storage_service.dart';
import 'dart:io';

import '../../../data/services/api_service.dart';
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
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _loading = true);
    try {
      final uploadRes = await ApiService().uploadFile(
        '/media/upload',
        File(picked.path),
      );
      final mediaId = uploadRes['id'] as String;
      final mediaId2 = uploadRes['id'] as String;
      final fullUrl = '${ApiConstants.baseUrl}/media/$mediaId2';
      await ApiService().put('/users/me', {'avatar_url': fullUrl});
      await ref.read(authNotifierProvider.notifier).checkSession();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('عکس پروفایل به‌روز شد')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService().put('/users/me', {
        'display_name': _nameCtrl.text.trim(),
        'username': _usernameCtrl.text.trim().toLowerCase(),
        'bio': _bioCtrl.text.trim(),
      });
      await ref.read(authNotifierProvider.notifier).checkSession();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('پروفایل ذخیره شد')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
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
                    CircleAvatar(
                      radius: 56,
                      backgroundImage: null,
                      foregroundImage: user?.avatarUrl != null
                          ? NetworkImage(
                              user!.avatarUrl!,
                              headers: {
                                'Authorization':
                                    'Bearer ${StorageService.getToken() ?? ""}',
                              },
                            )
                          : null,
                      child: user?.avatarUrl == null
                          ? Text(
                              user?.displayName.isNotEmpty == true
                                  ? user!.displayName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(fontSize: 36),
                            )
                          : null,
                    ),
                    if (_loading)
                      const Positioned.fill(child: CircularProgressIndicator())
                    else
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary,
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
