import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/chat_model.dart';
import '../../data/services/api_service.dart';
import '../../core/constants/api_constants.dart';

final chatListProvider = StateNotifierProvider<ChatListNotifier, AsyncValue<List<ChatModel>>>((ref) {
  return ChatListNotifier();
});

class ChatListNotifier extends StateNotifier<AsyncValue<List<ChatModel>>> {
  ChatListNotifier() : super(const AsyncValue.loading()) {
    loadChats();
    _startPolling();
  }

  Timer? _pollTimer;
  DateTime? _lastPollTime;

  Future<void> loadChats() async {
    try {
      final res = await ApiService().get('/chats/');
      final list = (res['chats'] as List? ?? [])
          .map((e) => ChatModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
      _lastPollTime = DateTime.now().toUtc();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: ApiConstants.pollingIntervalSeconds),
      (_) => _poll(),
    );
  }

  // Future<void> _poll() async {
  //   if (state is! AsyncData) return;
  //   try {
  //     final since = _lastPollTime?.toIso8601String();
  //     final res = await ApiService().get(
  //       '/messages/poll',
  //       query: since != null ? {'since': since} : null,
  //     );
  //     _lastPollTime = DateTime.now().toUtc();

  //     final newMessages = res['messages'] as List? ?? [];
  //     if (newMessages.isNotEmpty) {
  //       // رفرش لیست چت برای به‌روزرسانی آخرین پیام و unread
  //       await loadChats();
  //     }
  //   } catch (_) {
  //     // silent fail for polling
  //   }
  // }

  Future<void> _poll() async {
    try {
      await loadChats();
    } catch (_) {
      // silent fail
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await loadChats();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
