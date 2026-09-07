import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_constants.dart';
import '../../data/models/chat_model.dart';
import '../../data/services/api_service.dart';
import 'auth_provider.dart';

final chatListProvider =
    StateNotifierProvider.autoDispose<
      ChatListNotifier,
      AsyncValue<List<ChatModel>>
    >((ref) {
      final session = ref.watch(authenticatedSessionProvider);
      return ChatListNotifier(
        api: session.api,
        enabled: session.userId != null,
      );
    });

class ChatListNotifier extends StateNotifier<AsyncValue<List<ChatModel>>> {
  ChatListNotifier({ApiService? api, bool enabled = true})
    : _api = api ?? ApiService(),
      _enabled = enabled,
      super(enabled ? const AsyncValue.loading() : const AsyncValue.data([])) {
    if (enabled) {
      unawaited(loadChats());
      _pollTimer = Timer.periodic(
        const Duration(seconds: ApiConstants.pollingIntervalSeconds),
        (_) => loadChats(),
      );
    }
  }

  final ApiService _api;
  final bool _enabled;
  Timer? _pollTimer;
  Future<void>? _loading;

  Future<void> loadChats() {
    if (!mounted || !_enabled) return Future<void>.value();
    // Polling and a read/send/delete refresh can happen together. Share the
    // request rather than allowing an older response to replace newer state.
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      final res = await _api.get('/chats/');
      if (!mounted) return;
      final list = (res['chats'] as List? ?? [])
          .map((e) => ChatModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(list);
    } catch (error, stack) {
      if (!mounted) return;
      // Do not flash an error/loading screen on each background poll.
      if (!state.hasValue) state = AsyncValue.error(error, stack);
    }
  }

  Future<void> refresh() => loadChats();

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
