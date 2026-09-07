import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/account_service.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../auth/login_screen.dart';

class AccountSwitcherScreen extends ConsumerStatefulWidget {
  const AccountSwitcherScreen({super.key});

  @override
  ConsumerState<AccountSwitcherScreen> createState() =>
      _AccountSwitcherScreenState();
}

class _AccountSwitcherScreenState extends ConsumerState<AccountSwitcherScreen> {
  List<SavedAccount> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AccountService.list();
    setState(() {
      _accounts = list;
      _loading = false;
    });
  }

  Future<void> _switchTo(SavedAccount acc) async {
    await StorageService.saveToken(acc.accessToken);
    await StorageService.saveRefreshToken(acc.refreshToken);
    await StorageService.saveUserId(acc.userId);
    ApiService().setToken(acc.accessToken);
    await AccountService.save(acc); // set active
    await ref.read(authNotifierProvider.notifier).checkSession();
    if (mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('سوییچ به @${acc.username}')));
    }
  }

  Future<void> _addAccount() async {
    // خروج نرم بدون پاک کردن لیست اکانت‌ها
    await StorageService.clearTokens();
    ApiService().setToken(null);
    ref.read(authNotifierProvider.notifier).setUser(null);
    // go to login - force null user
    await ref.read(authNotifierProvider.notifier).logoutKeepAccounts();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFa = ref.watch(localeProvider).languageCode == 'fa';

    return Scaffold(
      appBar: AppBar(title: Text(isFa ? 'مدیریت اکانت‌ها' : 'Accounts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ..._accounts.map(
                  (a) => ListTile(
                    leading: CircleAvatar(
                      backgroundImage: null,
                      foregroundImage:
                          a.avatarUrl != null && a.avatarUrl!.isNotEmpty
                          ? NetworkImage(
                              a.avatarUrl!,
                              headers: {
                                'Authorization': 'Bearer ${a.accessToken}',
                              },
                            )
                          : null,
                      child: a.avatarUrl == null || a.avatarUrl!.isEmpty
                          ? Text(
                              a.displayName.isNotEmpty
                                  ? a.displayName[0].toUpperCase()
                                  : '?',
                            )
                          : null,
                    ),
                    title: Text(a.displayName),
                    subtitle: Text('@${a.username}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.logout, size: 20),
                      onPressed: () async {
                        await AccountService.remove(a.userId);
                        _load();
                      },
                    ),
                    onTap: () => _switchTo(a),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text(isFa ? 'افزودن اکانت' : 'Add account'),
                  subtitle: Text(isFa ? 'حداکثر ۳ اکانت' : 'Max 3 accounts'),
                  onTap: _accounts.length >= 3
                      ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isFa ? 'حداکثر ۳ اکانت' : 'Max 3 accounts',
                              ),
                            ),
                          );
                        }
                      : _addAccount,
                ),
              ],
            ),
    );
  }
}
