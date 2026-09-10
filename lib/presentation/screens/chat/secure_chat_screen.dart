import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/message_model.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/screen_privacy_service.dart';
import '../../../data/services/storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_list_provider.dart';
import '../../widgets/chat/message_text.dart';

/// Secure chat mode — a separate black-theme page for the same chat.
/// While open:
///  - FLAG_SECURE blocks screenshots / screen recording (Android).
///  - No forward, download/save, copy or share actions exist.
///  - Media is rendered from memory only (no disk cache).
/// On exit the in-memory session is erased and the previous (old) chat
/// screen underneath is restored untouched.
class SecureChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String title;
  const SecureChatScreen({super.key, required this.chatId, required this.title});

  @override
  ConsumerState<SecureChatScreen> createState() => _SecureChatScreenState();
}

class _SecureChatScreenState extends ConsumerState<SecureChatScreen> {
  late ApiService _api;
  final List<MessageModel> _messages = [];
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  String? _currentUserId;
  Timer? _pollTimer;
  Future<void> Function()? _releasePrivacy;

  @override
  void initState() {
    super.initState();
    final session = ref.read(authenticatedSessionProvider);
    _api = session.api;
    _currentUserId = session.user.id;
    _init();
  }

  Future<void> _init() async {
    try {
      _releasePrivacy = await ScreenPrivacyService.acquire();
    } catch (_) {}
    await _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    // Erase the secure session from memory; releasing the privacy lease
    // restores the previous screen state (the old chat underneath).
    _messages.clear();
    _releasePrivacy?.call();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.get('/messages/${widget.chatId}');
      if (!mounted) return;
      final list = (res['messages'] as List? ?? [])
          .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        _loading = false;
      });
      _scrollToBottom();
      _markRead();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString(), _loading = false);
    }
  }

  Future<void> _poll() async {
    if (!mounted || _loading) return;
    try {
      final res = await _api.get('/messages/${widget.chatId}');
      if (!mounted) return;
      final list = (res['messages'] as List? ?? [])
          .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final known = _messages.map((m) => m.id).toSet();
      final fresh = list.where((m) => !known.contains(m.id)).toList();
      if (fresh.isNotEmpty) {
        setState(() => _messages.addAll(fresh));
        _scrollToBottom();
        _markRead();
      }
    } catch (_) {}
  }

  Future<void> _markRead() async {
    try {
      await _api.post('/messages/chat/${widget.chatId}/read', {});
      if (mounted) ref.read(chatListProvider.notifier).refresh();
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    try {
      final res = await _api.post('/messages/', {
        'chat_id': widget.chatId,
        'message_type': 'text',
        'content': text,
        'is_secure': true,
      });
      if (!mounted) return;
      if (res['message'] != null) {
        setState(() => _messages.add(MessageModel.fromJson(res['message'] as Map<String, dynamic>)));
        _scrollToBottom();
      } else {
        await _poll();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteForMe(MessageModel msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('حذف پیام', style: TextStyle(color: Colors.white)),
        content: const Text('این پیام از گفتگوی امن پاک شود؟',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لغو')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.post('/messages/${msg.id}/delete', {});
      if (mounted) setState(() => _messages.removeWhere((m) => m.id == msg.id));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Only action allowed in secure mode: delete. No forward/copy/download/share.
  void _showSecureMenu(MessageModel msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.shield_outlined, color: Colors.greenAccent, size: 18),
                SizedBox(width: 8),
                Text('حالت امن: فوروارد، کپی و دانلود غیرفعال است',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('حذف پیام', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteForMe(msg);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _endSession() async {
    final erase = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('پایان گفتگوی امن', style: TextStyle(color: Colors.white)),
        content: const Text(
          'نشست امن از حافظه پاک می‌شود و به گفتگوی عادی برمی‌گردید. گفتگوی قبلی دست‌نخورده باقی می‌ماند.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ماندن')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('پاک‌سازی و خروج'),
          ),
        ],
      ),
    );
    if (erase == true && mounted) {
      // Erase in-memory session, release FLAG_SECURE, restore old chat.
      setState(_messages.clear);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endSession();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _endSession,
          ),
          title: Row(children: [
            const Icon(Icons.lock, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: const TextStyle(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const Text('گفتگوی امن • ضد اسکرین‌شات',
                      style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
                ],
              ),
            ),
          ]),
          actions: [
            IconButton(
              tooltip: 'پایان گفتگوی امن',
              icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
              onPressed: _endSession,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: Colors.green.withValues(alpha: 0.12),
                child: const Row(children: [
                  Icon(Icons.shield_outlined, color: Colors.greenAccent, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'اسکرین‌شات، فوروارد، کپی و دانلود در این صفحه غیرفعال است',
                      style: TextStyle(color: Colors.greenAccent, fontSize: 11),
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                    : _error != null
                        ? Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                              const SizedBox(height: 8),
                              FilledButton(onPressed: _load, child: const Text('تلاش مجدد')),
                            ]),
                          )
                        : _messages.isEmpty
                            ? const Center(
                                child: Text('پیامی نیست',
                                    style: TextStyle(color: Colors.white38)),
                              )
                            : ListView.builder(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.all(12),
                                itemCount: _messages.length,
                                itemBuilder: (_, i) => _SecureBubble(
                                  message: _messages[i],
                                  isMine: _messages[i].senderId == _currentUserId,
                                  onLongPress: () => _showSecureMenu(_messages[i]),
                                ),
                              ),
              ),
              Container(
                color: Colors.grey.shade950,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 4,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: 'پیام امن...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white10,
                        border: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(20)),
                            borderSide: BorderSide.none),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.greenAccent,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.black),
                      onPressed: _send,
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecureBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final VoidCallback onLongPress;
  const _SecureBubble({required this.message, required this.isMine, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final bg = isMine ? const Color(0xFF1B5E20) : const Color(0xFF212121);
    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isMine ? 14 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 14),
            ),
            border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MessageText(
                text: message.displayText.isEmpty ? _nonTextLabel(message) : message.displayText,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
              ),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock, size: 10, color: Colors.greenAccent),
                const SizedBox(width: 4),
                Text(
                  _time(message.createdAt),
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  String _nonTextLabel(MessageModel m) {
    if (m.isEncrypted) return '🔒 پیام رمزدار (در گفتگوی عادی باز کنید)';
    switch (m.messageType) {
      case 'image':
        return '📷 عکس (نمایش رسانه در گفتگوی امن غیرفعال است)';
      case 'video':
        return '🎬 ویدیو (نمایش رسانه در گفتگوی امن غیرفعال است)';
      case 'voice':
        return '🎤 ویس (پخش رسانه در گفتگوی امن غیرفعال است)';
      case 'audio':
      case 'music':
        return '🎵 موسیقی (پخش رسانه در گفتگوی امن غیرفعال است)';
      case 'gif':
        return '🎞 گیف (نمایش رسانه در گفتگوی امن غیرفعال است)';
      case 'location':
        return '📍 موقعیت مکانی (در گفتگوی عادی باز کنید)';
      default:
        return '📎 فایل (دانلود در گفتگوی امن غیرفعال است)';
    }
  }

  String _time(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
