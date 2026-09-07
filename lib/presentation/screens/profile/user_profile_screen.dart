import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/user_model.dart';
import '../../../data/services/api_service.dart';
import '../../providers/locale_provider.dart';
import '../../../data/services/storage_service.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  UserModel? _user;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _checkBlocked();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().get('/users/${widget.userId}');
      setState(() {
        _user = UserModel.fromJson(res);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _block() async {
    try {
      await ApiService().post('/users/block/${widget.userId}', {});
      if (mounted) {
        setState(() => _isBlocked = true);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('ربراک کالب دش')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _unblock() async {
    try {
      await ApiService().post('/users/unblock/${widget.userId}', {});
      if (mounted) {
        setState(() => _isBlocked = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('کالبنآ دش')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  bool _isBlocked = false;

  Future<void> _checkBlocked() async {
    try {
      final res = await ApiService().get('/users/blocked');
      final users = res['users'] as List? ?? [];
      setState(() {
        _isBlocked = users.any((u) => u['id'] == widget.userId);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isFa = ref.watch(localeProvider).languageCode == 'fa';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(isFa ? 'پروفایل' : 'Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          : _user == null
          ? const Center(child: Text('یافت نشد'))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 56,
                    backgroundColor: theme.colorScheme.primary.withValues(
                      alpha: 0.15,
                    ),
                    backgroundImage: null,
                    foregroundImage:
                        _user!.avatarUrl != null && _user!.avatarUrl!.isNotEmpty
                        ? NetworkImage(
                            _user!.avatarUrl!,
                            headers: {
                              'Authorization':
                                  'Bearer ${StorageService.getToken() ?? ""}',
                            },
                          )
                        : null,
                    child: _user!.avatarUrl == null || _user!.avatarUrl!.isEmpty
                        ? Text(
                            _user!.displayName.isNotEmpty
                                ? _user!.displayName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 40,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    _user!.displayName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    '@${_user!.username}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 15),
                  ),
                ),
                if (_user!.bio != null && _user!.bio!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_user!.bio!),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(
                    _user!.isOnline ? Icons.circle : Icons.circle_outlined,
                    color: _user!.isOnline ? Colors.green : Colors.grey,
                    size: 16,
                  ),
                  title: Text(
                    _user!.isOnline
                        ? (isFa ? 'آنلاین' : 'Online')
                        : (isFa ? 'آفلاین' : 'Offline'),
                  ),
                  subtitle: _user!.lastSeen != null && !_user!.isOnline
                      ? Text(
                          '${isFa ? 'آخرین بازدید' : 'Last seen'}: ${_user!.lastSeen}',
                        )
                      : null,
                ),
                const Divider(),
                ListTile(
                  leading: Icon(
                    _isBlocked ? Icons.lock_open : Icons.block,
                    color: Colors.red,
                  ),
                  title: Text(
                    _isBlocked ? 'آنبلاک' : 'بلاک',
                    style: const TextStyle(color: Colors.red),
                  ),
                  onTap: _isBlocked ? _unblock : _block,
                ),
                // ListTile(
                //   leading: const Icon(Icons.block, color: Colors.red),
                //   title: Text(isFa ? 'بلاک کردن' : 'Block', style: const TextStyle(color: Colors.red)),
                //   onTap: _block,
                // ),
              ],
            ),
    );
  }
}
