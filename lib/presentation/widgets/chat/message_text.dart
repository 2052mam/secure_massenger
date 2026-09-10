import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/chat_invite_link.dart';

/// Link taps coexist with the chat's long-press menu and swipe-to-reply.
class MessageText extends StatefulWidget {
  const MessageText({
    super.key,
    required this.text,
    this.style,
    this.linkColor,
    this.onInviteTap,
  });

  final String text;
  final TextStyle? style;
  final Color? linkColor;
  final ValueChanged<ChatInviteLink>? onInviteTap;

  @override
  State<MessageText> createState() => _MessageTextState();
}

class _MessageTextState extends State<MessageText> {
  final List<TapGestureRecognizer> _recognizers = [];
  List<ChatInviteMatch> _links = [];

  @override
  void initState() {
    super.initState();
    _updateLinks();
  }

  @override
  void didUpdateWidget(covariant MessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _updateLinks();
  }

  void _updateLinks() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    _links = ChatInviteLink.findIn(widget.text).toList();
    for (final match in _links) {
      _recognizers.add(
        TapGestureRecognizer()
          ..onTap = () => widget.onInviteTap?.call(match.link),
      );
    }
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_links.isEmpty || widget.onInviteTap == null) {
      return Text(widget.text, style: widget.style);
    }
    final spans = <TextSpan>[];
    var position = 0;
    for (var i = 0; i < _links.length; i++) {
      final match = _links[i];
      if (position < match.start) {
        spans.add(TextSpan(text: widget.text.substring(position, match.start)));
      }
      spans.add(
        TextSpan(
          text: widget.text.substring(match.start, match.end),
          style: TextStyle(
            color: widget.linkColor ?? Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: _recognizers[i],
        ),
      );
      position = match.end;
    }
    if (position < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(position)));
    }
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}
