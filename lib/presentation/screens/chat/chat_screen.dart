import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';

import '../../../data/models/message_model.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/storage_service.dart';
import '../../../data/services/voice_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_list_provider.dart';
import '../profile/user_profile_screen.dart';
import '../../widgets/media/video_message_player.dart';

import 'package:just_audio/just_audio.dart' as just_audio;

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String title;
  final String chatType;
  const ChatScreen({
    super.key,
    required this.chatId,
    required this.title,
    this.chatType = 'private',
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();
  final List<MessageModel> _messages = [];
  final VoiceService _voice = VoiceService();
  bool _loading = true;
  bool _sending = false;
  bool _searchMode = false;
  String? _error;
  Timer? _pollTimer;
  String? _lastMessageId;
  String? _currentUserId;
  MessageModel? _replyTo;
  Color? _bgColor;
  String? _bgImageUrl;
  bool _isRecording = false;
  String? _myRole;
  int _membersCount = 0;
  bool _isPublic = false;
  String? _chatUsername;
  String? _chatDescription;

  String _mediaFullUrl(String? mediaId, {String? existingUrl}) {
    if (existingUrl != null && existingUrl.isNotEmpty) {
      if (existingUrl.startsWith('http')) return existingUrl;
      final base = ApiConstants.baseUrl.replaceAll('/api/v1', '');
      return '$base$existingUrl';
    }
    if (mediaId == null || mediaId.isEmpty) return '';
    return '${ApiConstants.baseUrl}/media/$mediaId';
  }

  @override
  void initState() {
    super.initState();
    _currentUserId = StorageService.getUserId();
    _loadMessages();
    _startPolling();
    _markChatRead();
    _loadBackground();
    _loadChatInfo(); // این رو اضافه کن
  }

  Future<void> _loadBackground() async {
    try {
      final res = await ApiService().get('/chats/${widget.chatId}/background');
      final bg = res['background'] as Map<String, dynamic>?;
      if (bg == null) return;
      final type = bg['type'] as String?;
      final value = bg['value'] as String?;
      if (value == null || value.isEmpty) return;
      if (type == 'image') {
        if (mounted) setState(() => _bgImageUrl = value);
      } else if (type == 'color') {
        final hex = value.replaceFirst('#', '');
        final colorValue = int.tryParse(hex, radix: 16);
        if (colorValue != null && mounted) {
          setState(() => _bgColor = Color(colorValue | 0xFF000000));
        }
      }
    } catch (_) {}
  }

  Future<void> _loadChatInfo() async {
    try {
      final res = await ApiService().get('/chats/${widget.chatId}/info');
      if (mounted) {
        setState(() {
          _myRole = res['my_role'] as String?;
          _membersCount = res['members_count'] as int? ?? 0;
          _isPublic = res['is_public'] as bool? ?? false;
          _chatUsername = res['username'] as String?;
          _chatDescription = res['description'] as String?;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _voice.dispose();
    super.dispose();
  }

  Future<void> _markChatRead() async {
    if (!mounted) return;
    try {
      await ApiService().post('/messages/chat/${widget.chatId}/read', {});
      ref.read(chatListProvider.notifier).refresh();
    } catch (_) {}
  }

  Future<void> _loadMessages({String? query}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> res;
      if (query != null && query.length >= 2) {
        res = await ApiService().get(
          '/messages/search/${widget.chatId}',
          query: {'q': query},
        );
      } else {
        res = await ApiService().get('/messages/${widget.chatId}');
      }
      final list = (res['messages'] as List? ?? [])
          .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        if (list.isNotEmpty && query == null) _lastMessageId = list.last.id;
        _loading = false;
      });
      if (query == null) {
        _scrollToBottom();
        _markChatRead();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: ApiConstants.pollingIntervalSeconds),
      (_) {
        if (!_searchMode) {
          _pollNewMessages();
          _refreshMessageStatuses();
        }
      },
    );
  }

  Future<void> _refreshMessageStatuses() async {
    if (!mounted) return;
    final pendingIds = _messages
        .where((m) => m.senderId == _currentUserId && m.status != 'read')
        .map((m) => m.id)
        .toList();
    if (pendingIds.isEmpty) return;
    try {
      final res = await ApiService().post('/messages/statuses', {
        'message_ids': pendingIds,
      });
      final statuses = (res['statuses'] as Map<String, dynamic>? ?? {});
      if (statuses.isEmpty || !mounted) return;
      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          final m = _messages[i];
          final newStatus = statuses[m.id] as String?;
          if (newStatus != null && newStatus != m.status) {
            _messages[i] = m.copyWith(status: newStatus);
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _pollNewMessages() async {
    if (!mounted) return;
    try {
      final query = <String, String>{};
      if (_lastMessageId != null) query['after_id'] = _lastMessageId!;
      final res = await ApiService().get(
        '/messages/${widget.chatId}',
        query: query,
      );
      final list = (res['messages'] as List? ?? [])
          .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
          .toList();
      if (list.isNotEmpty && mounted) {
        setState(() {
          for (final m in list) {
            if (!_messages.any((x) => x.id == m.id)) {
              _messages.add(m);
            }
          }
          _lastMessageId = _messages.last.id;
        });
        _scrollToBottom();
        _markChatRead();
      }
    } catch (_) {}
  }

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final body = <String, dynamic>{
        'chat_id': widget.chatId,
        'content': text,
        'message_type': 'text',
      };
      if (_replyTo != null) body['reply_to_id'] = _replyTo!.id;
      final res = await ApiService().post('/messages/', body);
      final msg = MessageModel.fromJson(res);
      setState(() {
        _messages.add(msg);
        _lastMessageId = msg.id;
        _textCtrl.clear();
        _replyTo = null;
        _sending = false;
      });
      _scrollToBottom();
      ref.read(chatListProvider.notifier).refresh();
    } catch (e) {
      setState(() => _sending = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _pickAndSendMedia(
    ImageSource source, {
    bool isVideo = false,
    bool viewOnce = false,
  }) async {
    final picker = ImagePicker();
    final XFile? picked = isVideo
        ? await picker.pickVideo(source: source)
        : await picker.pickImage(
            source: source,
            maxWidth: 1600,
            imageQuality: 85,
          );
    if (picked == null) return;

    bool sendViewOnce = viewOnce;
    if (!isVideo) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.send),
                title: const Text('ارسال معمولی'),
                onTap: () => Navigator.pop(ctx, 'normal'),
              ),
              ListTile(
                leading: const Icon(Icons.timer, color: Colors.orange),
                title: const Text('ارسال تایم‌دار (View Once)'),
                onTap: () => Navigator.pop(ctx, 'once'),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('لغو'),
                onTap: () => Navigator.pop(ctx, 'cancel'),
              ),
            ],
          ),
        ),
      );
      if (choice == null || choice == 'cancel') return;
      sendViewOnce = choice == 'once';
    }

    setState(() => _sending = true);
    try {
      final upload = await ApiService().uploadFile(
        '/media/upload',
        File(picked.path),
      );
      final mediaId = upload['id'] as String;
      final mediaType =
          upload['media_type'] as String? ?? (isVideo ? 'video' : 'image');
      final body = <String, dynamic>{
        'chat_id': widget.chatId,
        'message_type': mediaType,
        'media_id': mediaId,
        'content': '',
        'is_view_once': sendViewOnce,
      };
      if (_replyTo != null) body['reply_to_id'] = _replyTo!.id;
      final res = await ApiService().post('/messages/', body);
      final msg = MessageModel.fromJson({
        ...res,
        'media_id': mediaId,
        'media_url': '/api/v1/media/$mediaId',
        'message_type': mediaType,
        'is_view_once': sendViewOnce,
      });
      setState(() {
        _messages.add(msg);
        _lastMessageId = msg.id;
        _replyTo = null;
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _sending = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _toggleVoiceRecord() async {
    if (_sending) return;
    if (_isRecording) {
      final file = await _voice.stopRecording();
      setState(() => _isRecording = false);
      if (file == null) return;
      setState(() => _sending = true);
      try {
        final upload = await ApiService().uploadFile('/media/upload', file);
        final mediaId = upload['id'] as String;
        final body = <String, dynamic>{
          'chat_id': widget.chatId,
          'message_type': 'voice',
          'media_id': mediaId,
          'content': '',
        };
        if (_replyTo != null) body['reply_to_id'] = _replyTo!.id;
        final res = await ApiService().post('/messages/', body);
        final msg = MessageModel.fromJson({
          ...res,
          'media_id': mediaId,
          'media_url': '/api/v1/media/$mediaId',
          'message_type': 'voice',
        });
        setState(() {
          _messages.add(msg);
          _lastMessageId = msg.id;
          _replyTo = null;
          _sending = false;
        });
        _scrollToBottom();
      } catch (e) {
        setState(() => _sending = false);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    } else {
      final ok = await _voice.startRecording();
      if (ok) {
        setState(() => _isRecording = true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('دسترسی میکروفون لازم است')),
        );
      }
    }
  }

  Future<void> _cancelVoiceRecord() async {
    await _voice.cancelRecording();
    setState(() => _isRecording = false);
  }

  Future<void> _deleteMessage(MessageModel msg, {required bool forAll}) async {
    try {
      await ApiService().post('/messages/${msg.id}/delete', {
        'for_all': forAll,
      });
      setState(() => _messages.removeWhere((m) => m.id == msg.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _clearHistory({required bool forAll}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(forAll ? 'حذف برای همه' : 'حذف فقط برای من'),
        content: Text(
          forAll
              ? 'پیام‌ها برای همه حذف می‌شوند.'
              : 'تاریخچه فقط برای شما پاک می‌شود.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لغو'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تایید'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService().post('/messages/chat/${widget.chatId}/clear', {
        'for_all': forAll,
      });
      setState(() => _messages.clear());
      ref.read(chatListProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _blockUser() async {
    _currentUserId ??= StorageService.getUserId();
    final other = _messages
        .where((m) => m.senderId != null && m.senderId != _currentUserId)
        .map((m) => m.senderId)
        .firstOrNull;
    if (other == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('کاربری برای بلاک یافت نشد')),
        );
      }
      return;
    }
    try {
      await ApiService().post('/users/block/$other', {});
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('کاربر بلاک شد')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _markViewOnce(MessageModel msg) async {
    if (!msg.isViewOnce || msg.viewedAt != null) return;
    try {
      await ApiService().post('/messages/${msg.id}/view-once', {});
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == msg.id);
        if (idx != -1) {
          _messages[idx] = msg.copyWith(viewedAt: DateTime.now());
        }
      });
    } catch (_) {}
  }

  void _showMessageActions(MessageModel msg) {
    final isMine = msg.senderId == _currentUserId;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('پاسخ'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _replyTo = msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text('فوروارد'),
              onTap: () {
                Navigator.pop(ctx);
                _forwardMessage(msg);
              },
            ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('حذف برای من'),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(msg, forAll: false);
                },
              ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text(
                  'حذف برای همه',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(msg, forAll: true);
                },
              ),
            if (!isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('حذف برای من'),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(msg, forAll: false);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('عکس از گالری'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendMedia(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('دوربین'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendMedia(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('ویدیو'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndSendMedia(ImageSource.gallery, isVideo: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setBackgroundImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (picked == null) return;
    try {
      final upload = await ApiService().uploadFile(
        '/media/upload',
        File(picked.path),
      );
      final mediaId = upload['id'] as String;
      final url = _mediaFullUrl(mediaId, existingUrl: null);
      await ApiService().post('/chats/${widget.chatId}/background', {
        'type': 'image',
        'value': url,
      });
      setState(() {
        _bgImageUrl = url;
        _bgColor = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('کب‌دنارگ میظنت دش')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _forwardMessage(MessageModel msg) async {
    final chatsRes = await ApiService().get('/chats/');
    final chats = (chatsRes['chats'] as List? ?? []);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView.builder(
        itemCount: chats.length,
        itemBuilder: (_, i) {
          final c = chats[i];
          final title =
              c['title'] as String? ??
              (c['other_user'] != null
                  ? c['other_user']['display_name'] as String? ?? 'چت'
                  : 'چت');
          return ListTile(
            title: Text(title),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await ApiService().post('/messages/${msg.id}/forward', {
                  'target_chat_id': c['id'],
                });
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('فوروارد شد')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            },
          );
        },
      ),
    );
  }

  void _showMoreMenu() {
    final isGroupOrChannel =
        widget.chatType == 'group' || widget.chatType == 'channel';
    final isAdmin = _myRole == 'owner' || _myRole == 'admin';
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (isGroupOrChannel) ...[
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('اطلاعات گروه/کانال'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showGroupInfoSheet();
                },
              ),
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('اعضا'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showMembersSheet();
                },
              ),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('لینک دعوت'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showInviteLink();
                  },
                ),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('ویرایش گروه/کانال'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditGroupSheet();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.orange),
                title: const Text(
                  'خروج از گروه',
                  style: TextStyle(color: Colors.orange),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _leaveGroup();
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('بک‌گراند تصویری'),
              onTap: () {
                Navigator.pop(ctx);
                _setBackgroundImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('جستجو در چت'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _searchMode = true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('پاک کردن تاریخچه برای من'),
              onTap: () {
                Navigator.pop(ctx);
                _clearHistory(forAll: false);
              },
            ),
            if (!isGroupOrChannel)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text(
                  'پاک کردن برای همه',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _clearHistory(forAll: true);
                },
              ),
            if (!isGroupOrChannel)
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text(
                  'بلاک کاربر',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _blockUser();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('خروج از گروه'),
        content: const Text('آیا مطمئن هستید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لغو'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService().post('/chats/${widget.chatId}/leave', {});
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _showInviteLink() async {
    try {
      final res = await ApiService().get('/chats/${widget.chatId}/invite-link');
      final link = res['invite_link'] as String? ?? '';
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('لینک دعوت'),
          content: SelectableText(
            link,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              child: const Text('بستن'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _showGroupInfoSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_chatUsername != null)
              Text(
                '@$_chatUsername',
                style: TextStyle(color: Colors.grey[600]),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.people, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Text('$_membersCount عضو'),
                const SizedBox(width: 16),
                Icon(
                  _isPublic ? Icons.lock_open : Icons.lock,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(_isPublic ? 'عمومی' : 'خصوصی'),
              ],
            ),
            if (_chatDescription != null && _chatDescription!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'توضیحات:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(_chatDescription!),
            ],
          ],
        ),
      ),
    );
  }

  void _showMembersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, sc) => _MembersSheet(
          chatId: widget.chatId,
          myRole: _myRole,
          scrollController: sc,
        ),
      ),
    );
  }

  void _showEditGroupSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EditGroupSheet(
        chatId: widget.chatId,
        currentTitle: widget.title,
        currentDescription: _chatDescription,
        currentUsername: _chatUsername,
        isPublic: _isPublic,
        myRole: _myRole,
        onSaved: () {
          _loadChatInfo();
        },
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authNotifierProvider);
    _currentUserId = auth.valueOrNull?.id ?? StorageService.getUserId();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _searchMode
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'جستجو...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onSubmitted: (q) => _loadMessages(query: q),
              )
            : InkWell(
                onTap: () {
                  final otherId = _messages
                      .where((m) => m.senderId != _currentUserId)
                      .map((m) => m.senderId)
                      .firstOrNull;
                  if (otherId != null) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => UserProfileScreen(userId: otherId),
                      ),
                    );
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'برای مشاهده پروفایل بزنید',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
        actions: [
          if (_searchMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() => _searchMode = false);
                _loadMessages();
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: _showMoreMenu,
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: _bgImageUrl == null
              ? (_bgColor ?? theme.scaffoldBackgroundColor)
              : null,
          image: _bgImageUrl != null
              ? DecorationImage(
                  image: CachedNetworkImageProvider(
                    _bgImageUrl!,
                    headers: StorageService.getToken() != null
                        ? {
                            'Authorization':
                                'Bearer ${StorageService.getToken()}',
                          }
                        : null,
                  ),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: SafeArea(
          child: Column(
            children: [
              if (_replyTo != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      const Icon(Icons.reply, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _replyTo!.content ?? _replyTo!.messageType,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _replyTo = null),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                            ElevatedButton(
                              onPressed: () => _loadMessages(),
                              child: const Text('تلاش مجدد'),
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'هنوز پیامی نیست',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMine = msg.senderId == _currentUserId;
                          return GestureDetector(
                            onLongPress: () => _showMessageActions(msg),
                            onTap: () {
                              if (msg.isViewOnce && msg.viewedAt == null) {
                                _markViewOnce(msg);
                              }
                            },
                            onHorizontalDragEnd: (d) {
                              if (d.primaryVelocity != null &&
                                  d.primaryVelocity! > 200) {
                                setState(() => _replyTo = msg);
                              }
                            },
                            child: _MessageBubble(
                              message: msg,
                              isMine: isMine,
                              mediaUrl: _mediaFullUrl(
                                msg.mediaId,
                                existingUrl: msg.mediaUrl,
                              ),
                              token: StorageService.getToken(),
                            ),
                          );
                        },
                      ),
              ),
              if (!_searchMode) _buildInputBar(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file_rounded),
              onPressed: _sending ? null : _showAttachMenu,
            ),
            Expanded(
              child: TextField(
                controller: _textCtrl,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(),
                decoration: InputDecoration(
                  hintText: 'پیام...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.scaffoldBackgroundColor,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                maxLines: 4,
                minLines: 1,
              ),
            ),
            IconButton(
              onPressed: _sending ? null : _toggleVoiceRecord,
              icon: Icon(
                _isRecording ? Icons.stop_circle : Icons.mic_rounded,
                color: _isRecording ? Colors.red : theme.colorScheme.primary,
              ),
            ),
            IconButton(
              onPressed: _sending ? null : _sendText,
              icon: _sending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.send_rounded, color: theme.colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final String mediaUrl;
  final String? token;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.mediaUrl,
    this.token,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isMine ? theme.colorScheme.primary : theme.cardColor;
    final fg = isMine ? Colors.white : theme.textTheme.bodyLarge?.color;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.replyToId != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(
                      color: isMine ? Colors.white60 : Colors.blue,
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  message.content != null ? 'ریپلای' : 'پیام',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (message.isViewOnce && message.viewedAt != null)
              Container(
                width: 220,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text(
                    'مشاهده شد',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              )
            else if (message.isViewOnce && message.viewedAt == null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer,
                      size: 16,
                      color: isMine ? Colors.white70 : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'View Once - برای مشاهده بزن',
                      style: TextStyle(
                        fontSize: 12,
                        color: isMine ? Colors.white70 : Colors.orange,
                      ),
                    ),
                  ],
                ),
              )
            else if (message.messageType == 'image' && mediaUrl.isNotEmpty)
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.black,
                      child: InteractiveViewer(
                        child: CachedNetworkImage(
                          imageUrl: mediaUrl,
                          httpHeaders: token != null
                              ? {'Authorization': 'Bearer $token'}
                              : null,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: mediaUrl,
                    httpHeaders: token != null
                        ? {'Authorization': 'Bearer $token'}
                        : null,
                    width: 220,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 220,
                      height: 160,
                      color: Colors.black12,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.broken_image, size: 48),
                  ),
                ),
              )
            else if (message.messageType == 'video' && mediaUrl.isNotEmpty)
              VideoMessagePlayer(
                url: mediaUrl,
                authToken: token,
                isMine: isMine,
              )
            else if (message.messageType == 'video')
              const Text('ویدیو')
            else if (message.messageType == 'voice' ||
                message.messageType == 'audio')
              _AudioPlayer(url: mediaUrl, token: token, fg: fg)
            else
              Text(
                message.content ?? '',
                style: TextStyle(color: fg, fontSize: 15, height: 1.35),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: isMine ? Colors.white70 : Colors.grey,
                    fontSize: 11,
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.status == 'read' ? Icons.done_all : Icons.done_all,
                    size: 16,
                    color: message.status == 'read'
                        ? const Color(0xFF4FC3F7)
                        : (message.status == 'delivered'
                              ? Colors.white70
                              : Colors.white54),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioPlayer extends StatefulWidget {
  final String url;
  final String? token;
  final Color? fg;
  const _AudioPlayer({required this.url, this.token, this.fg});

  @override
  State<_AudioPlayer> createState() => _AudioPlayerState();
}

class _AudioPlayerState extends State<_AudioPlayer> {
  late final just_audio.AudioPlayer _player;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player = just_audio.AudioPlayer();
    _player.playerStateStream.listen((s) {
      if (mounted) {
        setState(() => _playing = s.playing);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
      } else {
        if (_player.duration == null) {
          if (widget.url.isEmpty) return;
          await _player.setAudioSource(
            just_audio.AudioSource.uri(
              Uri.parse(widget.url),
              headers: widget.token != null
                  ? {'Authorization': 'Bearer ${widget.token}'}
                  : {},
            ),
          );
        }
        await _player.play();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطا در پخش صدا: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_playing ? Icons.pause : Icons.play_arrow, color: widget.fg),
          const SizedBox(width: 6),
          Text('پیام صوتی', style: TextStyle(color: widget.fg)),
        ],
      ),
    );
  }
}

class _MembersSheet extends StatefulWidget {
  final String chatId;
  final String? myRole;
  final ScrollController scrollController;
  const _MembersSheet({
    required this.chatId,
    this.myRole,
    required this.scrollController,
  });
  @override
  State<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<_MembersSheet> {
  List<dynamic> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().get('/chats/${widget.chatId}/members');
      setState(() {
        _members = res['members'] as List? ?? [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _promoteMember(String userId, String role) async {
    try {
      await ApiService().post('/chats/${widget.chatId}/promote', {
        'user_id': userId,
        'role': role,
      });
      _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _removeMember(String userId) async {
    try {
      await ApiService().post('/chats/${widget.chatId}/remove-member', {
        'user_id': userId,
      });
      _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'اعضا',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              itemCount: _members.length,
              itemBuilder: (_, i) {
                final m = _members[i];
                final role = m['role'] as String? ?? 'member';
                final isOwner = widget.myRole == 'owner';
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      (m['display_name'] as String? ?? '?').isNotEmpty
                          ? (m['display_name'] as String)[0].toUpperCase()
                          : '?',
                    ),
                  ),
                  title: Text(m['display_name'] as String? ?? ''),
                  subtitle: Text(_roleLabel(role)),
                  trailing: isOwner && role != 'owner'
                      ? PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'remove') {
                              _removeMember(m['id'] as String);
                            } else {
                              _promoteMember(m['id'] as String, v);
                            }
                          },
                          itemBuilder: (_) => [
                            if (role != 'admin')
                              const PopupMenuItem(
                                value: 'admin',
                                child: Text('ادمین کردن'),
                              ),
                            if (role == 'admin')
                              const PopupMenuItem(
                                value: 'member',
                                child: Text('حذف ادمین'),
                              ),
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text(
                                'حذف از گروه',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        )
                      : null,
                );
              },
            ),
          ),
      ],
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'مالک';
      case 'admin':
        return 'ادمین';
      default:
        return 'عضو';
    }
  }
}

class _EditGroupSheet extends StatefulWidget {
  final String chatId;
  final String currentTitle;
  final String? currentDescription;
  final String? currentUsername;
  final bool isPublic;
  final String? myRole;
  final VoidCallback onSaved;
  const _EditGroupSheet({
    required this.chatId,
    required this.currentTitle,
    this.currentDescription,
    this.currentUsername,
    required this.isPublic,
    this.myRole,
    required this.onSaved,
  });
  @override
  State<_EditGroupSheet> createState() => _EditGroupSheetState();
}

class _EditGroupSheetState extends State<_EditGroupSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _usernameCtrl;
  late bool _isPublic;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.currentTitle);
    _descCtrl = TextEditingController(text: widget.currentDescription ?? '');
    _usernameCtrl = TextEditingController(text: widget.currentUsername ?? '');
    _isPublic = widget.isPublic;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
      };
      if (widget.myRole == 'owner') {
        body['is_public'] = _isPublic;
        body['username'] = _usernameCtrl.text.trim().toLowerCase();
      }
      await ApiService().post('/chats/${widget.chatId}/update', body);
      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تغییرات ذخیره شد')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ویرایش',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'نام'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'توضیحات'),
          ),
          if (widget.myRole == 'owner') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(
                labelText: 'یوزرنیم',
                prefixText: '@',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('عمومی'),
              subtitle: const Text('هر کسی می‌تواند پیدا و عضو شود'),
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
              contentPadding: EdgeInsets.zero,
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('ذخیره'),
          ),
        ],
      ),
    );
  }
}
