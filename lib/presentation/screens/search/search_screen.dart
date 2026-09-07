import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/user_model.dart';
import '../../../data/services/api_service.dart';
import '../../providers/locale_provider.dart';
import '../chat/chat_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  List<UserModel> _users = [];
  List<Map<String, dynamic>> _channels = [];
  bool _loading = false;
  String? _error;

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() {
        _users = [];
        _channels = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService().get(
        '/users/search',
        query: {'q': q.trim()},
      );
      final list = (res['users'] as List? ?? [])
          .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final chans = (res['chats'] as List? ?? [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      setState(() {
        _users = list;
        _channels = chans;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _startChat(UserModel user) async {
    try {
      final res = await ApiService().post('/chats/private', {
        'user_id': user.id,
      });
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: res['chat_id'] as String,
            title: user.displayName,
            chatType: 'private',
          ),
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _joinChannel(Map<String, dynamic> ch) async {
    try {
      final chatId = ch['id'] as String;
      final title = ch['title'] as String? ?? '';
      // اول عضو بشو بعد برو تو
      try {
        await ApiService().post('/chats/$chatId/add-member', {
          'user_id': (await ApiService().get('/users/me'))['id'],
        });
      } catch (_) {
        // شاید قبلا عضو بودیم
      }
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ChatScreen(chatId: chatId, title: title, chatType: 'channel'),
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFa = ref.watch(localeProvider).languageCode == 'fa';
    return Scaffold(
      appBar: AppBar(title: Text(isFa ? 'جستجو' : 'Search')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _ctrl,
                onChanged: _search,
                decoration: InputDecoration(
                  hintText: isFa
                      ? 'جستجو کاربر یا کانال...'
                      : 'Search user or channel...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            Expanded(
              child: ListView(
                children: [
                  if (_users.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        isFa ? 'کاربران' : 'Users',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ..._users.map(
                      (u) => ListTile(
                        leading: CircleAvatar(
                          backgroundImage: u.avatarUrl != null
                              ? NetworkImage(u.avatarUrl!)
                              : null,
                          child: u.avatarUrl == null
                              ? Text(
                                  u.displayName.isNotEmpty
                                      ? u.displayName[0].toUpperCase()
                                      : '?',
                                )
                              : null,
                        ),
                        title: Text(u.displayName),
                        subtitle: Text('@${u.username}'),
                        trailing: const Icon(Icons.chat_bubble_outline),
                        onTap: () => _startChat(u),
                      ),
                    ),
                  ],
                  if (_channels.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        isFa ? 'کانال‌ها' : 'Channels',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ..._channels.map(
                      (ch) => ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.campaign),
                        ),
                        title: Text(ch['title'] ?? ''),
                        subtitle: ch['username'] != null
                            ? Text('@${ch['username']}')
                            : null,
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _joinChannel(ch),
                      ),
                    ),
                  ],
                  if (_users.isEmpty && _channels.isEmpty && !_loading)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          isFa
                              ? 'حداقل ۲ کاراکتر وارد کنید'
                              : 'Enter at least 2 characters',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
