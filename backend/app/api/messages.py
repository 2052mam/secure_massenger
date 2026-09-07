from flask import Blueprint, request, jsonify, current_app, send_from_directory
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.user import User, BlockList
from app.models.chat import Chat, ChatMember
from app.models.message import Message, MessageStatus, MessageReaction, PinnedMessage, MessageHide
from app.models.media import MediaFile
from app.models.audit import AuditLog
from datetime import datetime
from sqlalchemy import and_, or_
import os

from app.services.message_payloads import (
    serialize_messages, user_in_chat, visible_messages,
)

messages_bp = Blueprint('messages', __name__)

def get_client_ip():
    return request.headers.get('X-Forwarded-For', request.remote_addr)


@messages_bp.route('/<chat_id>', methods=['GET'])
@jwt_required()
def get_messages(chat_id):
    """Chronological history, incremental polling and direct reply navigation."""
    user_id = get_jwt_identity()
    if not user_in_chat(user_id, chat_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403

    try:
        limit = max(1, min(int(request.args.get('limit', 50)), 100))
    except (TypeError, ValueError):
        return jsonify({'error': 'limit نامعتبر است'}), 400

    after_id = request.args.get('after_id')
    before_id = request.args.get('before_id')
    from_id = request.args.get('from_id')
    if sum(bool(v) for v in (after_id, before_id, from_id)) > 1:
        return jsonify({'error': 'فقط یک نشانگر پیام مجاز است'}), 400
    cursor_id = after_id or before_id or from_id
    query = visible_messages(user_id).filter(Message.chat_id == chat_id)
    if cursor_id:
        # A cursor may have been deleted since the previous poll, but must
        # always belong to this chat. A reply jump must still be visible.
        cursor_query = query if from_id else Message.query.filter_by(chat_id=chat_id)
        cursor = cursor_query.filter(Message.id == cursor_id).first()
        if cursor is None:
            return jsonify({'error': 'پیام یافت نشد'}), 404
        if before_id:
            query = query.filter(or_(
                Message.created_at < cursor.created_at,
                and_(Message.created_at == cursor.created_at, Message.id < cursor.id),
            ))
        else:
            query = query.filter(or_(
                Message.created_at > cursor.created_at,
                and_(Message.created_at == cursor.created_at,
                     Message.id >= cursor.id if from_id else Message.id > cursor.id),
            ))

    # after_id must take the FIRST unseen page, not the last, or a busy chat
    # silently loses messages. The UUID breaks equal-timestamp ties.
    ascending = bool(after_id or from_id)
    ordering = (Message.created_at.asc(), Message.id.asc()) if ascending else (
        Message.created_at.desc(), Message.id.desc())
    rows = query.order_by(*ordering).limit(limit + 1).all()
    has_more = len(rows) > limit
    messages = rows[:limit]
    if not ascending:
        messages.reverse()
    return jsonify({
        'messages': serialize_messages(messages, user_id),
        'has_more': has_more,
    }), 200


@messages_bp.route('/', methods=['POST'])
@jwt_required()
def send_message():
    user_id = get_jwt_identity()
    data = request.get_json() or {}

    chat_id = data.get('chat_id')
    content = data.get('content')
    message_type = data.get('message_type', 'text')
    media_id = data.get('media_id')
    reply_to_id = data.get('reply_to_id')
    is_view_once = bool(data.get('is_view_once', False))

    if not chat_id:
        return jsonify({'error': 'chat_id الزامی است'}), 400

    if not user_in_chat(user_id, chat_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403

    if message_type == 'text' and not content:
        return jsonify({'error': 'متن پیام خالی است'}), 400

    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'دشن تفای تچ'}), 404

    if chat.chat_type == 'private':
        other_member = ChatMember.query.filter(
            ChatMember.chat_id == chat_id,
            ChatMember.user_id != user_id,
            ChatMember.is_deleted == False
        ).first()
        if other_member:
            is_blocked = BlockList.query.filter(
                ((BlockList.blocker_id == user_id) & (BlockList.blocked_id == other_member.user_id)) |
                ((BlockList.blocker_id == other_member.user_id) & (BlockList.blocked_id == user_id)),
                BlockList.is_deleted == False
            ).first()
            if is_blocked:
                return jsonify({'error': 'امکان ارسال پیام وجود ندارد'}), 403

    if reply_to_id:
        original = visible_messages(user_id).filter_by(
            id=reply_to_id, chat_id=chat_id
        ).first()
        if original is None:
            return jsonify({'error': 'پیام مرجع در این چت در دسترس نیست'}), 400

    if is_view_once and (message_type != 'image' or not media_id):
        return jsonify({'error': 'مشاهده یک‌باره فقط برای عکس مجاز است'}), 400
    if media_id:
        media = MediaFile.query.filter_by(
            id=media_id, uploader_id=user_id, is_deleted=False
        ).first()
        if media is None:
            return jsonify({'error': 'فایل در دسترس نیست'}), 403
        if is_view_once and media.media_type != 'image':
            return jsonify({'error': 'فایل باید عکس باشد'}), 400
        # Reusing an ephemeral upload as a normal message bypasses view-once.
        references = Message.query.filter_by(media_id=media_id)
        if references.filter_by(is_view_once=True).first() or (
            is_view_once and references.first()
        ):
            return jsonify({'error': 'این فایل قبلاً در پیام استفاده شده است'}), 400

    msg = Message(
        chat_id=chat_id,
        sender_id=user_id,
        message_type=message_type,
        content=content,
        media_id=media_id,
        reply_to_id=reply_to_id,
        is_view_once=is_view_once,
    )
    db.session.add(msg)
    db.session.flush()

    # وضعیت برای فرستنده
    db.session.add(MessageStatus(message_id=msg.id, user_id=user_id, status='sent'))

    # وضعیت برای بقیه اعضا
    members = ChatMember.query.filter_by(chat_id=chat_id, is_deleted=False).all()
    for m in members:
        if m.user_id != user_id:
            db.session.add(MessageStatus(
                message_id=msg.id, user_id=m.user_id, status='delivered',
                delivered_at=datetime.utcnow()
            ))

    chat.updated_at = datetime.utcnow()
    db.session.add(AuditLog(
        actor_id=user_id, action='send_message', entity_type='message', entity_id=msg.id,
        ip_address=get_client_ip()
    ))
    db.session.commit()

    return jsonify(serialize_messages([msg], user_id, status_override='sent')[0]), 201


@messages_bp.route('/<message_id>/read', methods=['POST'])
@jwt_required()
def mark_read(message_id):
    user_id = get_jwt_identity()
    status = MessageStatus.query.filter_by(message_id=message_id, user_id=user_id).first()
    if status:
        status.status = 'read'
        status.read_at = datetime.utcnow()
        db.session.commit()

        # آپدیت last_read در ChatMember
        msg = Message.query.get(message_id)
        if msg:
            member = ChatMember.query.filter_by(chat_id=msg.chat_id, user_id=user_id).first()
            if member:
                member.last_read_message_id = message_id
                db.session.commit()

    return jsonify({'ok': True}), 200


@messages_bp.route('/<message_id>/delete', methods=['POST'])
@jwt_required()
def delete_message(message_id):
    """حذف یک‌طرفه یا دوطرفه"""
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    for_all = bool(data.get('for_all', False))

    msg = Message.query.filter_by(id=message_id, is_deleted=False).first()
    if not msg:
        return jsonify({'error': 'پیام یافت نشد'}), 404

    if not user_in_chat(user_id, msg.chat_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403

    if for_all:
        if msg.sender_id != user_id:
            member = ChatMember.query.filter_by(chat_id=msg.chat_id, user_id=user_id).first()
            if not member or member.role not in ('owner', 'admin'):
                return jsonify({'error': 'مجوز حذف برای همه را ندارید'}), 403
        msg.is_deleted_for_all = True
        msg.is_deleted = True
        msg.deleted_at = datetime.utcnow()
        msg.deleted_by = user_id
    else:
        # حذف یک‌طرفه واقعی با MessageHide
        existing_hide = MessageHide.query.filter_by(message_id=message_id, user_id=user_id).first()
        if not existing_hide:
            db.session.add(MessageHide(message_id=message_id, user_id=user_id))

    db.session.add(AuditLog(
        actor_id=user_id, action='delete_message_for_all' if for_all else 'delete_message',
        entity_type='message', entity_id=message_id, ip_address=get_client_ip()
    ))
    db.session.commit()
    return jsonify({'ok': True, 'for_all': for_all}), 200


@messages_bp.route('/<message_id>/forward', methods=['POST'])
@jwt_required()
def forward_message(message_id):
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    target_chat_id = data.get('target_chat_id')

    if not target_chat_id:
        return jsonify({'error': 'چت مقصد الزامی است'}), 400

    original = Message.query.filter_by(id=message_id, is_deleted=False).first()
    if not original:
        return jsonify({'error': 'پیام یافت نشد'}), 404

    if not user_in_chat(user_id, original.chat_id) or not visible_messages(user_id).filter_by(id=message_id).first():
        return jsonify({'error': 'دسترسی به پیام ندارید'}), 403
    if original.is_view_once or (original.media_id and Message.query.filter_by(
        media_id=original.media_id, is_view_once=True
    ).first()):
        return jsonify({'error': 'عکس یک‌بارمصرف قابل فوروارد نیست'}), 403

    if not user_in_chat(user_id, target_chat_id):
        return jsonify({'error': 'دسترسی به چت مقصد ندارید'}), 403

    new_msg = Message(
        chat_id=target_chat_id,
        sender_id=user_id,
        message_type=original.message_type,
        content=original.content,
        media_id=original.media_id,
        forwarded_from_id=original.id,
        forwarded_from_chat_id=original.chat_id,
    )
    db.session.add(new_msg)
    db.session.flush()

    db.session.add(MessageStatus(message_id=new_msg.id, user_id=user_id, status='sent'))
    members = ChatMember.query.filter_by(chat_id=target_chat_id, is_deleted=False).all()
    for m in members:
        if m.user_id != user_id:
            db.session.add(MessageStatus(message_id=new_msg.id, user_id=m.user_id, status='delivered', delivered_at=datetime.utcnow()))

    Chat.query.filter_by(id=target_chat_id).update({'updated_at': datetime.utcnow()})
    db.session.commit()

    return jsonify({'id': new_msg.id, 'chat_id': target_chat_id}), 201


@messages_bp.route('/<message_id>/pin', methods=['POST'])
@jwt_required()
def pin_message(message_id):
    user_id = get_jwt_identity()
    msg = Message.query.filter_by(id=message_id, is_deleted=False).first()
    if not msg or not user_in_chat(user_id, msg.chat_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403

    existing = PinnedMessage.query.filter_by(chat_id=msg.chat_id, message_id=message_id, is_deleted=False).first()
    if existing:
        return jsonify({'message': 'قبلاً پین شده'}), 200

    db.session.add(PinnedMessage(chat_id=msg.chat_id, message_id=message_id, pinned_by=user_id))
    db.session.commit()
    return jsonify({'ok': True}), 200


@messages_bp.route('/poll', methods=['GET'])
@jwt_required()
def poll_updates():
    """
    Endpoint اصلی Polling
    کلاینت هر چند ثانیه این را صدا می‌زند و after timestamp یا last_event_id می‌دهد
    """
    user_id = get_jwt_identity()
    since = request.args.get('since')  # ISO datetime
    limit = min(int(request.args.get('limit', 50)), 100)

    # چت‌هایی که کاربر عضو است
    chat_ids = [m.chat_id for m in ChatMember.query.join(Chat).filter(
        ChatMember.user_id == user_id, ChatMember.is_deleted.is_(False),
        Chat.is_deleted.is_(False),
    ).all()]

    if not chat_ids:
        return jsonify({'messages': [], 'chats_updated': []}), 200

    query = visible_messages(user_id).filter(Message.chat_id.in_(chat_ids))

    if since:
        try:
            since_dt = datetime.fromisoformat(since.replace('Z', '+00:00'))
            query = query.filter(Message.created_at > since_dt)
        except Exception:
            pass

    new_messages = query.order_by(Message.created_at.asc()).limit(limit).all()

    result_msgs = serialize_messages(new_messages, user_id)

    return jsonify({
        'messages': result_msgs,
        'server_time': datetime.utcnow().isoformat(),
    }), 200


@messages_bp.route('/search/<chat_id>', methods=['GET'])
@jwt_required()
def search_in_chat(chat_id):
    """جستجو داخل پیام‌های یک چت"""
    user_id = get_jwt_identity()
    if not user_in_chat(user_id, chat_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403

    q = (request.args.get('q') or '').strip()
    if len(q) < 2:
        return jsonify({'messages': []}), 200

    messages = visible_messages(user_id).filter(
        Message.chat_id == chat_id, Message.content.ilike(f'%{q}%')
    ).order_by(Message.created_at.desc()).limit(50).all()

    return jsonify({'messages': serialize_messages(messages, user_id)}), 200


@messages_bp.route('/chat/<chat_id>/clear', methods=['POST'])
@jwt_required()
def clear_chat_history(chat_id):
    """حذف تاریخچه پیام‌ها (یک‌طرفه یا دوطرفه)"""
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    for_all = bool(data.get('for_all', False))

    if not user_in_chat(user_id, chat_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403

    if for_all:
        member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
        chat = db.session.get(Chat, chat_id)
        if chat and chat.chat_type == 'private':
            pass  # در خصوصی هر طرف می‌تواند برای همه پاک کند (مثل تلگرام با محدودیت)
        elif not member or member.role not in ('owner', 'admin'):
            return jsonify({'error': 'مجوز حذف برای همه را ندارید'}), 403

        Message.query.filter_by(chat_id=chat_id).update({
            'is_deleted_for_all': True,
            'is_deleted': True,
            'deleted_at': datetime.utcnow(),
            'deleted_by': user_id,
        }, synchronize_session=False)
    else:
        # یک‌طرفه: فقط برای این کاربر با MessageHide
        msgs = Message.query.filter_by(chat_id=chat_id, is_deleted_for_all=False).all()
        for msg in msgs:
            exists = MessageHide.query.filter_by(message_id=msg.id, user_id=user_id).first()
            if not exists:
                db.session.add(MessageHide(message_id=msg.id, user_id=user_id))

    db.session.add(AuditLog(
        actor_id=user_id,
        action='clear_chat_for_all' if for_all else 'clear_chat',
        entity_type='chat',
        entity_id=chat_id,
        ip_address=get_client_ip()
    ))
    db.session.commit()
    return jsonify({'ok': True, 'for_all': for_all}), 200


@messages_bp.route('/chat/<chat_id>/read', methods=['POST'])
@jwt_required()
def mark_chat_read(chat_id):
    """وقتی کاربر وارد چت می‌شود همه پیام‌های خوانده‌نشده را سین بزن"""
    user_id = get_jwt_identity()
    if not user_in_chat(user_id, chat_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403

    # همه وضعیت‌های این کاربر در این چت را read کن
    msg_ids = [m.id for m in Message.query.filter_by(chat_id=chat_id, is_deleted=False).all()]
    # if msg_ids:
    #     MessageStatus.query.filter(
    #         MessageStatus.message_id.in_(msg_ids),
    #         MessageStatus.user_id == user_id,
    #     ).update({
    #         'status': 'read',
    #         'read_at': datetime.utcnow(),
    #     }, synchronize_session=False)
    if msg_ids:
        existing_statuses = MessageStatus.query.filter(
            MessageStatus.message_id.in_(msg_ids),
            MessageStatus.user_id == user_id,
            MessageStatus.status != 'read',
        ).all()

        for s in existing_statuses:
            s.status = 'read'
            s.read_at = datetime.utcnow()

        # برای پیام‌هایی که status ندارن بساز
        existing_ids = {s.message_id for s in existing_statuses}
        all_statuses = MessageStatus.query.filter(
            MessageStatus.message_id.in_(msg_ids),
            MessageStatus.user_id == user_id,
        ).all()
        existing_all_ids = {s.message_id for s in all_statuses}
        for mid in msg_ids:
            if mid not in existing_all_ids:
                db.session.add(MessageStatus(
                    message_id=mid,
                    user_id=user_id,
                    status='read',
                    read_at=datetime.utcnow(),
                    delivered_at=datetime.utcnow(),
                ))
            
        # last_read را به آخرین پیام ببر
        last = Message.query.filter_by(chat_id=chat_id, is_deleted=False).order_by(Message.created_at.desc()).first()
        member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
        if member and last:
            member.last_read_message_id = last.id

    db.session.commit()
    return jsonify({'ok': True}), 200

def view_once_message(message_id, user_id):
    msg = visible_messages(user_id).filter_by(id=message_id).first()
    if msg is None:
        return None, (jsonify({'error': 'پیام یافت نشد'}), 404)
    if not user_in_chat(user_id, msg.chat_id) or msg.sender_id == user_id:
        return None, (jsonify({'error': 'فقط گیرنده می‌تواند عکس را باز کند'}), 403)
    if not msg.is_view_once or msg.message_type != 'image':
        return None, (jsonify({'error': 'این پیام عکس یک‌بارمصرف نیست'}), 400)
    if msg.viewed_at is not None:
        return None, (jsonify({'error': 'عکس قبلاً مشاهده شده است'}), 410)
    return msg, None


@messages_bp.route('/<message_id>/view-once/media', methods=['GET'])
@jwt_required()
def get_view_once_media(message_id):
    """Load into memory first; failed downloads/decodes do not consume the photo.

    Clients may reveal these bytes only after winning the atomic POST below.
    The ordinary media URL never serves a view-once upload.
    """
    msg, error = view_once_message(message_id, get_jwt_identity())
    if error is not None:
        return error
    media = MediaFile.query.filter_by(id=msg.media_id, is_deleted=False).first()
    if media is None:
        return jsonify({'error': 'فایل یافت نشد'}), 404
    response = send_from_directory(
        os.path.abspath(current_app.config['UPLOAD_FOLDER']), media.stored_name,
        conditional=False, etag=False, max_age=0,
    )
    response.headers['Cache-Control'] = 'private, no-store, max-age=0'
    response.headers['Pragma'] = 'no-cache'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    return response


@messages_bp.route('/<message_id>/view-once', methods=['POST'])
@jwt_required()
def mark_view_once(message_id):
    user_id = get_jwt_identity()
    msg, error = view_once_message(message_id, user_id)
    if error is not None:
        return error
    viewed_at = datetime.utcnow()
    # A conditional UPDATE works on both MySQL and SQLite. Two devices cannot
    # both win the claim, even when their preceding downloads overlap.
    updated = Message.query.filter_by(
        id=message_id, is_deleted=False, is_deleted_for_all=False,
        is_view_once=True, viewed_at=None,
    ).update({'viewed_at': viewed_at}, synchronize_session=False)
    if updated != 1:
        db.session.rollback()
        return jsonify({'error': 'عکس قبلاً مشاهده شده است'}), 410
    db.session.add(AuditLog(
        actor_id=user_id, action='view_once_opened', entity_type='message',
        entity_id=message_id, ip_address=get_client_ip(),
    ))
    db.session.commit()
    return jsonify({'ok': True, 'viewed_at': viewed_at.isoformat()}), 200


@messages_bp.route('/statuses', methods=['POST'])
@jwt_required()
def get_message_statuses():
    """Reconcile loaded messages over HTTP, including read and received ones.

    Deletion is state, not a new message: after_id polling alone cannot deliver
    it. Clients send bounded batches of loaded IDs (and quoted original IDs).
    This also works after missed polls, without clocks or a schema migration.
    The existing statuses/viewed_at fields remain backwards compatible.
    """
    user_id = get_jwt_identity()
    data = request.get_json()
    if data is None:
        data = {}
    if not isinstance(data, dict):
        return jsonify({'error': 'درخواست نامعتبر است'}), 400
    message_ids = data.get('message_ids', [])
    if (not isinstance(message_ids, list) or len(message_ids) > 100
            or any(not isinstance(mid, str) or not mid or len(mid) > 36
                   for mid in message_ids)):
        return jsonify({'error': 'حداکثر ۱۰۰ شناسه پیام معتبر مجاز است'}), 400

    chat_id = data.get('chat_id')
    if chat_id is not None:
        if not isinstance(chat_id, str) or not user_in_chat(user_id, chat_id):
            return jsonify({'error': 'دسترسی ندارید'}), 403

    # Membership is checked BEFORE exposing even a deleted ID. Never reveal
    # existence, read receipts or view-once state from an unrelated chat.
    query = Message.query.join(Chat, Message.chat_id == Chat.id).join(
        ChatMember, ChatMember.chat_id == Chat.id
    ).filter(
        Message.id.in_(message_ids),
        ChatMember.user_id == user_id,
        ChatMember.is_deleted.is_(False),
        Chat.is_deleted.is_(False),
        Chat.is_deleted_for_all.is_(False),
    )
    if chat_id is not None:
        query = query.filter(Message.chat_id == chat_id)
    messages = query.all()
    hidden_ids = {row.message_id for row in MessageHide.query.filter(
        MessageHide.user_id == user_id,
        MessageHide.message_id.in_([msg.id for msg in messages]),
    ).all()}
    deleted_ids = {msg.id for msg in messages
                   if msg.is_deleted or msg.is_deleted_for_all
                   or msg.id in hidden_ids}
    visible = [msg for msg in messages if msg.id not in deleted_ids]
    sent_ids = [msg.id for msg in visible if msg.sender_id == user_id]
    statuses = {mid: 'sent' for mid in sent_ids}
    rank = {'sent': 0, 'delivered': 1, 'read': 2}
    for status in MessageStatus.query.filter(
        MessageStatus.message_id.in_(sent_ids),
        MessageStatus.user_id != user_id,
    ).all():
        previous = statuses[status.message_id]
        if rank.get(status.status, 0) > rank[previous]:
            statuses[status.message_id] = status.status

    return jsonify({
        'statuses': statuses,
        'viewed_at': {msg.id: msg.viewed_at.isoformat() if msg.viewed_at else None
                      for msg in visible if msg.is_view_once},
        'deleted_ids': sorted(deleted_ids),
    }), 200
