import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'main_shell.dart';

import '../../../data/services/storage_service.dart';

import '../../providers/chat_list_provider.dart';
import '../../providers/locale_provider.dart';
import '../../../data/models/chat_model.dart';
import '../../../data/services/api_service.dart';
import '../chat/chat_screen.dart';
import '../../widgets/chat/chat_avatar.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  @override
  Widget build(BuildContext context) {
    final chatsAsync = ref.watch(chatListProvider);
    final locale = ref.watch(localeProvider);
    final isFa = locale.languageCode == 'fa';
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          isFa ? 'پیام‌رسان' : 'Messenger',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {
              ref.read(shellIndexProvider.notifier).state = 1;
            },
            tooltip: isFa ? 'جستجو' : 'Search',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) => _onMenu(v, isFa),
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'saved',
                child: Text(isFa ? 'پیام‌های ذخیره‌شده' : 'Saved Messages'),
              ),
              PopupMenuItem(
                value: 'group',
                child: Text(isFa ? 'گروه جدید' : 'New Group'),
              ),
              PopupMenuItem(
                value: 'channel',
                child: Text(isFa ? 'کانال جدید' : 'New Channel'),
              ),
              PopupMenuItem(
                value: 'support',
                child: Text(isFa ? 'پشتیبانی' : 'Support'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: chatsAsync.when(
          data: (chats) {
            if (chats.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 72,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isFa ? 'هنوز گفتگویی ندارید' : 'No conversations yet',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isFa
                          ? 'از تب جستجو کاربر پیدا کنید'
                          : 'Find users from the Search tab',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () => ref.read(chatListProvider.notifier).refresh(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: chats.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  indent: 76,
                  color: Colors.grey.withValues(alpha: 0.15),
                ),
                itemBuilder: (context, index) {
                  final chat = chats[index];
                  return _ChatTile(chat: chat, isFa: isFa)
                      .animate()
                      .fadeIn(duration: 280.ms, delay: (20 * (index % 12)).ms)
                      .slideX(begin: 0.05, curve: Curves.easeOut);
                },
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isFa ? 'خطا در بارگذاری' : 'Failed to load',
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () =>
                      ref.read(chatListProvider.notifier).refresh(),
                  child: Text(isFa ? 'تلاش مجدد' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
      // بدون FloatingActionButton مداد
    );
  }

  Future<void> _onMenu(String value, bool isFa) async {
    try {
      if (value == 'saved') {
        final res = await ApiService().post('/chats/saved', {});
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatId: res['chat_id'] as String,
              title: isFa ? 'پیام‌های ذخیره‌شده' : 'Saved Messages',
              chatType: 'saved',
            ),
          ),
        );
      } else if (value == 'support') {
        final res = await ApiService().post('/chats/support', {});
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chatId: res['chat_id'] as String,
              title: isFa ? 'پشتیبانی' : 'Support',
              chatType: 'support',
            ),
          ),
        );
      } else if (value == 'group') {
        await _createGroupDialog(isFa);
      } else if (value == 'channel') {
        await _createChannelDialog(isFa);
      }
      ref.read(chatListProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _createGroupDialog(bool isFa) async {
    final titleCtrl = TextEditingController();
    final List<String> selectedIds = [];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFa ? 'گروه جدید' : 'New Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: isFa ? 'نام گروه' : 'Group name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isFa ? 'لغو' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isFa ? 'ایجاد' : 'Create'),
          ),
        ],
      ),
    );
    if (ok == true && titleCtrl.text.trim().isNotEmpty) {
      final res = await ApiService().post('/chats/group', {
        'title': titleCtrl.text.trim(),
        'member_ids': selectedIds,
      });
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: res['chat_id'] as String,
            title: titleCtrl.text.trim(),
            chatType: 'group',
          ),
        ),
      );
    }
  }

  Future<void> _createChannelDialog(bool isFa) async {
    final titleCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFa ? 'کانال جدید' : 'New Channel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: isFa ? 'عنوان کانال' : 'Channel title',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: userCtrl,
              decoration: InputDecoration(
                labelText: isFa
                    ? 'نام کاربری کانال (اختیاری)'
                    : 'Username (optional)',
                prefixText: '@',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isFa ? 'لغو' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isFa ? 'ایجاد' : 'Create'),
          ),
        ],
      ),
    );
    if (ok == true && titleCtrl.text.trim().isNotEmpty) {
      final body = <String, dynamic>{
        'title': titleCtrl.text.trim(),
        'is_public': true,
      };
      if (userCtrl.text.trim().isNotEmpty) {
        body['username'] = userCtrl.text.trim().toLowerCase();
      }
      final res = await ApiService().post('/chats/channel', body);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: res['chat_id'] as String,
            title: titleCtrl.text.trim(),
            chatType: 'channel',
          ),
        ),
      );
    }
  }
}

class _ChatTile extends StatelessWidget {
  final ChatModel chat;
  final bool isFa;

  const _ChatTile({required this.chat, required this.isFa});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = chat.lastMessage;
    String subtitle = '';
    if (last != null) {
      if (last.messageType == 'image') {
        subtitle = isFa ? '📷 عکس' : '📷 Photo';
      } else if (last.messageType == 'video') {
        subtitle = isFa ? '🎥 ویدیو' : '🎥 Video';
      } else if (last.messageType == 'voice') {
        subtitle = isFa ? '🎤 پیام صوتی' : '🎤 Voice message';
      } else {
        subtitle = last.content ?? '';
      }
    }

    String timeStr = '';
    if (last?.createdAt != null) {
      timeago.setLocaleMessages('fa', timeago.FaMessages());
      final localTime = last!.createdAt!.toLocal();
      timeStr = timeago.format(localTime, locale: isFa ? 'fa' : 'en');
    }

    final isOnline =
        chat.otherUser?.isOnline == true &&
        (chat.otherUser?.showLastSeen ?? true);
    final avatarUrl = chat.chatType == 'private'
        ? (chat.otherUser?.showProfilePhoto == true
              ? chat.otherUser?.avatarUrl
              : null)
        : chat.avatarUrl;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                chatId: chat.id,
                title: chat.displayTitle,
                chatType: chat.chatType,
                otherUser: chat.otherUser,
                avatarUrl: chat.avatarUrl,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Stack(
                children: [
                  ChatAvatar(
                    title: chat.displayTitle,
                    url: avatarUrl,
                    token: StorageService.getToken(),
                    radius: 28,
                  ),
                  if (chat.chatType == 'private' && isOnline)
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (chat.isPinned)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.push_pin_rounded,
                              size: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        Expanded(
                          child: Text(
                            chat.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: chat.unreadCount > 0
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: chat.unreadCount > 0
                                ? theme.colorScheme.primary
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                              fontWeight: chat.unreadCount > 0
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (chat.unreadCount > 0)
                          Container(
                            margin: const EdgeInsets.only(right: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              chat.unreadCount > 99
                                  ? '99+'
                                  : '${chat.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
