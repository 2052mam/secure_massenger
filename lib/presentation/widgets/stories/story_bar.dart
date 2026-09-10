import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/story_model.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../screens/stories/story_viewer_screen.dart';
import '../../screens/stories/story_create_screen.dart';

final storyFeedProvider =
    StateNotifierProvider.autoDispose<StoryFeedNotifier, AsyncValue<List<StoryGroup>>>((ref) {
  final session = ref.watch(authenticatedSessionProvider);
  return StoryFeedNotifier(api: session.api, enabled: session.userId != null);
});

class StoryFeedNotifier extends StateNotifier<AsyncValue<List<StoryGroup>>> {
  StoryFeedNotifier({required this.api, required bool enabled})
      : _enabled = enabled,
        super(const AsyncValue.loading()) {
    if (enabled) {
      refresh();
      _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh(silent: true));
    }
  }

  final ApiService api;
  final bool _enabled;
  Timer? _timer;

  Future<void> refresh({bool silent = false}) async {
    if (!_enabled) return;
    if (!silent) state = const AsyncValue.loading();
    try {
      final res = await api.get('/stories/');
      final groups = (res['groups'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(StoryGroup.fromJson)
          .toList();
      if (mounted) state = AsyncValue.data(groups);
    } catch (e, st) {
      if (mounted && !silent) state = AsyncValue.error(e, st);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Telegram-like story tray shown on top of the chat list.
class StoryBar extends ConsumerWidget {
  const StoryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(storyFeedProvider);
    final myId = ref.watch(authNotifierProvider).valueOrNull?.id;
    return feed.when(
      loading: () => const SizedBox(height: 86, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
      error: (_, __) => const SizedBox.shrink(),
      data: (groups) {
        if (groups.isEmpty) {
          return _EmptyTray(onAdd: () => _openCreate(context, ref));
        }
        return Container(
          height: 96,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: groups.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              if (i == 0) {
                final mine = groups.where((g) => g.user.id == myId).toList();
                final hasMine = mine.isNotEmpty;
                return _StoryAvatar(
                  label: 'استوری من',
                  imageUrl: hasMine ? mine.first.user.avatarUrl : null,
                  displayName: hasMine ? mine.first.user.displayName : '',
                  hasUnseen: false,
                  isMine: true,
                  onTap: () => _openCreate(context, ref),
                  onView: hasMine ? () => _openViewer(context, ref, groups, 0) : null,
                );
              }
              final g = groups[i - 1];
              if (g.user.id == myId) return const SizedBox.shrink();
              return _StoryAvatar(
                label: g.user.displayName,
                imageUrl: g.user.avatarUrl,
                displayName: g.user.displayName,
                hasUnseen: g.hasUnseen,
                onTap: () => _openViewer(context, ref, groups, i - 1),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openCreate(BuildContext context, WidgetRef ref) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const StoryCreateScreen()),
    );
    if (created == true) ref.read(storyFeedProvider.notifier).refresh();
  }

  Future<void> _openViewer(BuildContext context, WidgetRef ref, List<StoryGroup> groups, int index) async {
    final visible = groups.where((g) => g.stories.isNotEmpty).toList();
    if (visible.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryViewerScreen(groups: visible, initialGroupIndex: index.clamp(0, visible.length - 1)),
      ),
    );
    ref.read(storyFeedProvider.notifier).refresh(silent: true);
  }
}

class _EmptyTray extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyTray({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        _StoryAvatar(label: 'استوری من', displayName: '', isMine: true, hasUnseen: false, onTap: onAdd),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('هنوز استوری نیست. اولین استوری را منتشر کنید!',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
      ]),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  final String label;
  final String? imageUrl;
  final String displayName;
  final bool hasUnseen;
  final bool isMine;
  final VoidCallback onTap;
  final VoidCallback? onView;
  const _StoryAvatar({
    required this.label,
    this.imageUrl,
    required this.displayName,
    required this.hasUnseen,
    this.isMine = false,
    required this.onTap,
    this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final ring = hasUnseen ? Colors.blue : Colors.grey.withValues(alpha: 0.35);
    return GestureDetector(
      onTap: isMine && onView != null ? onView : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                width: 58,
                height: 58,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: isMine ? Colors.grey.withValues(alpha: 0.35) : ring, width: 2.5)),
                child: CircleAvatar(
                  backgroundImage: imageUrl != null
                      ? NetworkImage(imageUrl!, headers: {
                          'Authorization': 'Bearer ${StorageService.getToken() ?? ""}',
                        })
                      : null,
                  child: imageUrl == null
                      ? Text(displayName.isNotEmpty ? displayName[0] : '+',
                          style: const TextStyle(fontWeight: FontWeight.w700))
                      : null,
                ),
              ),
              if (isMine)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: onTap,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                      child: const Icon(Icons.add, size: 12, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 64,
            child: Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }
}
