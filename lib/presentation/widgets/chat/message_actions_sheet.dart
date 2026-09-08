import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/message_model.dart';
import 'chat_labels.dart';

class MessageActionsSheet extends StatelessWidget {
  const MessageActionsSheet({
    super.key,
    required this.message,
    required this.canDeleteForAll,
    this.canReply = true,
    this.canPin = false,
    required this.onReply,
    required this.onForward,
    required this.onDelete,
    this.onTogglePin,
  });

  final MessageModel message;
  final bool canDeleteForAll;
  final bool canReply;

  /// Pinning is allowed for private chats and for group/channel members with
  /// the pin right. Several messages can stay pinned at the same time.
  final bool canPin;
  final VoidCallback onReply;
  final VoidCallback onForward;
  final ValueChanged<bool> onDelete;
  final ValueChanged<bool>? onTogglePin;

  Future<void> _copy(BuildContext context) async {
    final text = message.copyableText;
    if (text == null) return;
    final labels = ChatLabels.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Copy only the exact body/caption, not the author, quote or timestamp.
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(labels.copied)));
    } catch (_) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(labels.copyFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = ChatLabels.of(context);
    void closeAndRun(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canReply)
              ListTile(
                leading: const Icon(Icons.reply),
                title: Text(labels.reply),
                onTap: () => closeAndRun(onReply),
              ),
            if (message.copyableText != null)
              ListTile(
                key: const ValueKey('copy-message'),
                leading: const Icon(Icons.copy_outlined),
                title: Text(labels.copy),
                onTap: () => _copy(context),
              ),
            if (canPin && onTogglePin != null)
              ListTile(
                key: const ValueKey('pin-message'),
                leading: Icon(
                  message.isPinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                ),
                title: Text(
                  message.isPinned ? labels.unpinMessage : labels.pinMessage,
                ),
                onTap: () =>
                    closeAndRun(() => onTogglePin!(!message.isPinned)),
              ),
            if (!message.isViewOnce)
              ListTile(
                leading: const Icon(Icons.forward),
                title: Text(labels.forward),
                onTap: () => closeAndRun(onForward),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(labels.deleteForMe),
              onTap: () => closeAndRun(() => onDelete(false)),
            ),
            if (canDeleteForAll)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: Text(
                  labels.deleteForAll,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () => closeAndRun(() => onDelete(true)),
              ),
          ],
        ),
      ),
    );
  }
}
