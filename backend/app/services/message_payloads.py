"""Shared, non-recursive message payloads for send, history, search and polling."""

from app.services.timestamps import utc_iso

from app import db
from app.models.chat import Chat, ChatMember
from app.models.message import Message, MessageHide, MessageStatus, PinnedMessage
from app.models.user import User


def user_in_chat(user_id, chat_id):
    return db.session.query(ChatMember.id).join(Chat).filter(
        ChatMember.chat_id == chat_id,
        ChatMember.user_id == user_id,
        ChatMember.is_deleted.is_(False),
        Chat.is_deleted.is_(False),
        Chat.is_deleted_for_all.is_(False),
    ).first() is not None


def visible_messages(user_id):
    """Soft-deleted/locally hidden messages must not reappear through replies."""
    hidden = db.session.query(MessageHide.message_id).filter_by(user_id=user_id)
    return Message.query.filter(
        Message.is_deleted.is_(False),
        Message.is_deleted_for_all.is_(False),
        Message.is_scheduled.is_(False),
        ~Message.id.in_(hidden),
    )


def serialize_messages(messages, user_id, status_override=None):
    if not messages:
        return []

    # Batch related records: a page of replies must not cause N+1 lookups.
    reply_ids = {m.reply_to_id for m in messages if m.reply_to_id}
    originals = {
        m.id: m for m in visible_messages(user_id).filter(
            Message.id.in_(reply_ids)
        ).all()
    } if reply_ids else {}
    sender_ids = {m.sender_id for m in messages} | {
        m.sender_id for m in originals.values()
    }
    senders = {
        u.id: u for u in User.query.filter(User.id.in_(sender_ids)).all()
    }
    statuses = {}
    if status_override is None:
        for status in MessageStatus.query.filter(
            MessageStatus.message_id.in_([m.id for m in messages])
        ).all():
            statuses.setdefault(status.message_id, []).append(status)

    chats = {c.id: c for c in Chat.query.filter(Chat.id.in_({m.chat_id for m in messages})).all()}
    # One batched lookup keeps the pinned flag free of N+1 queries.
    pinned_ids = {row.message_id for row in PinnedMessage.query.filter(
        PinnedMessage.message_id.in_([m.id for m in messages]),
        PinnedMessage.is_deleted.is_(False),
    ).all()}
    # Telegram-like reactions: batch load reactions per message
    from app.models.message import MessageReaction
    reaction_rows = MessageReaction.query.filter(
        MessageReaction.message_id.in_([m.id for m in messages]),
        MessageReaction.is_deleted.is_(False),
    ).all()
    reactions_by_msg = {}
    for r in reaction_rows:
        reactions_by_msg.setdefault(r.message_id, []).append(r)
    result = []
    for msg in messages:
        sender = senders.get(msg.sender_id)
        chat = chats[msg.chat_id]
        broadcast = chat.chat_type == 'channel'
        channel_sender = {'id': chat.id, 'username': chat.username or '',
                          'display_name': chat.title or 'Channel', 'avatar_url': chat.avatar_url,
                          'is_online': False} if broadcast else None
        reply = None
        if msg.reply_to_id:
            original = originals.get(msg.reply_to_id)
            # Also protects old/corrupt cross-chat reply references.
            if original is None or original.chat_id != msg.chat_id:
                reply = {'id': msg.reply_to_id, 'is_unavailable': True}
            else:
                author = senders.get(original.sender_id)
                reply = {
                    'id': original.id,
                    'sender_id': chat.id if broadcast else original.sender_id,
                    'sender_name': chat.title if broadcast else author.display_name if author else None,
                    'message_type': original.message_type,
                    'content': (original.content or '')[:240]
                    if not original.is_view_once else None,
                    'is_view_once': original.is_view_once,
                    'is_spoiler': bool(original.is_spoiler),
                    'is_unavailable': False,
                    # Never include a thumbnail or caption for ephemeral media.
                    'media_url': f'/api/v1/media/{original.media_id}'
                    if original.media_id and original.message_type == 'image'
                    and not original.is_view_once else None,
                }

        message_statuses = statuses.get(msg.id, [])
        if status_override is not None:
            status = status_override
        elif msg.sender_id == user_id:
            recipient_statuses = [s.status for s in message_statuses
                                  if s.user_id != user_id]
            status = ('read' if 'read' in recipient_statuses else
                      'delivered' if 'delivered' in recipient_statuses else 'sent')
        else:
            status = next((s.status for s in message_statuses
                           if s.user_id == user_id), 'delivered')

        # Reactions summary for this message
        reactions = reactions_by_msg.get(msg.id, [])
        # group by emoji
        emoji_counts = {}
        me_emojis = set()
        for rr in reactions:
            emoji_counts[rr.emoji] = emoji_counts.get(rr.emoji, 0) + 1
            if rr.user_id == user_id:
                me_emojis.add(rr.emoji)
        reactions_summary = [
            {'emoji': e, 'count': c, 'me': e in me_emojis}
            for e, c in sorted(emoji_counts.items(), key=lambda x: -x[1])
        ]

        result.append({
            'id': msg.id,
            'chat_id': msg.chat_id,
            'sender_id': chat.id if broadcast else msg.sender_id,
            'sender': channel_sender if broadcast else sender.to_dict() if sender else None,
            'message_type': msg.message_type,
            'content': msg.content,
            'media_id': msg.media_id,
            'media_url': f'/api/v1/media/{msg.media_id}'
            if msg.media_id and not msg.is_view_once else None,
            'reply_to_id': msg.reply_to_id,
            'reply_to': reply,
            'forwarded_from_id': msg.forwarded_from_id,
            'is_view_once': msg.is_view_once,
            'is_spoiler': bool(msg.is_spoiler),
            'is_scheduled': bool(msg.is_scheduled),
            'scheduled_at': utc_iso(msg.scheduled_at) if msg.scheduled_at else None,
            'is_pinned': msg.id in pinned_ids,
            'viewed_at': utc_iso(msg.viewed_at) if msg.viewed_at else None,
            'is_edited': msg.is_edited,
            'created_at': utc_iso(msg.created_at),
            'status': status,
            'reactions': reactions_summary,
        })
    return result
