import '../../core/utils/api_datetime.dart';
import '../models/message_model.dart';
import '../models/reply_preview_model.dart';

/// A bounded /messages/statuses response. Missing fields keep older servers
/// compatible, though live deletion requires the updated backend.
class MessageSyncResult {
  final Set<String> deletedIds;
  final Map<String, String> statuses;
  final Map<String, DateTime> viewedAt;

  /// Ids of the currently pinned messages of the chat, newest first. Null on
  /// an older server that does not report pins at all.
  final List<String>? pinnedIds;

  const MessageSyncResult({
    this.deletedIds = const {},
    this.statuses = const {},
    this.viewedAt = const {},
    this.pinnedIds,
  });

  factory MessageSyncResult.fromJson(Map<String, dynamic> json) {
    final statuses = json['statuses'] as Map<String, dynamic>? ?? {};
    final views = json['viewed_at'] as Map<String, dynamic>? ?? {};
    final pinned = json['pinned_ids'] as List?;
    return MessageSyncResult(
      pinnedIds: pinned?.whereType<String>().toList(),
      deletedIds: (json['deleted_ids'] as List? ?? [])
          .whereType<String>()
          .toSet(),
      statuses: {
        for (final entry in statuses.entries)
          if (entry.value is String) entry.key: entry.value as String,
      },
      viewedAt: {
        for (final entry in views.entries)
          if (entry.value is String &&
              parseApiDateTime(entry.value as String) != null)
            entry.key: parseApiDateTime(entry.value as String)!,
      },
    );
  }
}

/// Tombstones last as long as the chat screen. A delayed history/send/poll
/// response cannot bring back a message (or quoted content) already removed.
class MessageReconciler {
  final Set<String> _unavailableIds = {};

  bool isUnavailable(String id) => _unavailableIds.contains(id);

  void remove(Iterable<String> ids) => _unavailableIds.addAll(ids);

  static String newestStatus(String previous, String? incoming) {
    const rank = {'sent': 0, 'delivered': 1, 'read': 2};
    return (rank[incoming] ?? -1) > (rank[previous] ?? 0)
        ? incoming!
        : previous;
  }

  List<MessageModel> reconcile(
    Iterable<MessageModel> messages, {
    MessageSyncResult? update,
  }) {
    if (update != null) remove(update.deletedIds);
    final pinned = update?.pinnedIds == null
        ? null
        : update!.pinnedIds!.toSet();
    return [
      for (final message in messages)
        if (!isUnavailable(message.id))
          message.copyWith(
            status: newestStatus(message.status, update?.statuses[message.id]),
            viewedAt: message.viewedAt ?? update?.viewedAt[message.id],
            isPinned: pinned == null
                ? message.isPinned
                : pinned.contains(message.id),
            replyTo:
                message.replyToId != null && isUnavailable(message.replyToId!)
                ? ReplyPreviewModel.unavailable(message.replyToId!)
                : null,
          ),
    ];
  }

  /// Include received/read messages, old pages, search results and originals
  /// outside the visible page. An unread-outgoing-only poll misses deletions.
  List<List<String>> batches(
    Iterable<MessageModel> messages, {
    MessageModel? selectedReply,
  }) {
    final ids = <String>{};
    for (final message in messages) {
      if (!isUnavailable(message.id)) ids.add(message.id);
      final replyId = message.replyToId;
      if (replyId != null && !isUnavailable(replyId)) ids.add(replyId);
    }
    if (selectedReply != null && !isUnavailable(selectedReply.id)) {
      ids.add(selectedReply.id);
    }
    final list = ids.toList();
    return [
      for (var start = 0; start < list.length; start += 100)
        list.sublist(
          start,
          start + 100 > list.length ? list.length : start + 100,
        ),
    ];
  }
}
