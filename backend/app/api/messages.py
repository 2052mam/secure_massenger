from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.user import User, BlockList
from app.models.chat import Chat, ChatMember
from app.models.message import Message, MessageStatus, MessageReaction, PinnedMessage, MessageHide
from app.models.media import MediaFile
from app.models.audit import AuditLog
from datetime import datetime

messages_bp = Blueprint('messages', __name__)

def get_client_ip():
    return request.headers.get('X-Forwarded-For', request.remote_addr)


def user_in_chat(user_id, chat_id):
    return ChatMember.query.filter_by(
        chat_id=chat_id, user_id=user_id, is_deleted=False
    ).first() is not None


@messages_bp.route('/<chat_id>', methods=['GET'])
@jwt_required()
def get_messages(chat_id):
    """دریافت پیام‌ها + پشتیبانی از Polling با after_id یا since"""
    user_id = get_jwt_identity()
    if not user_in_chat(user_id, chat_id):
        return jsonify({'error': 'دسترسی ندارید'}), 403

    after_id = request.args.get('after_id')
    before_id = request.args.get('before_id')
    limit = min(int(request.args.get('limit', 50)), 100)

    hidden_ids = {h.message_id for h in MessageHide.query.filter_by(user_id=user_id).all()}
    query = Message.query.filter(
        Message.chat_id == chat_id,
        Message.is_deleted_for_all == False,
    )

    if after_id:
        after_msg = Message.query.get(after_id)
        if after_msg:
            query = query.filter(Message.created_at > after_msg.created_at)
    elif before_id:
        before_msg = Message.query.get(before_id)
        if before_msg:
            query = query.filter(Message.created_at < before_msg.created_at)

    messages = query.order_by(Message.created_at.desc()).limit(limit * 2).all()
    messages = [m for m in messages if m.id not in hidden_ids][:limit]
    messages.reverse()  # قدیمی به جدید

    result = []
    for msg in messages:
        # وضعیت خوانده شدن برای کاربر فعلی
        sender = User.query.get(msg.sender_id)

        # وضعیت تیک‌ها: برای پیام خودم، بالاترین وضعیت گیرندگان را نشان بده
        if msg.sender_id == user_id:
            statuses = MessageStatus.query.filter(
                MessageStatus.message_id == msg.id,
                MessageStatus.user_id != user_id,
            ).all()
            if any(s.status == 'read' for s in statuses):
                msg_status = 'read'
            elif any(s.status == 'delivered' for s in statuses):
                msg_status = 'delivered'
            else:
                msg_status = 'sent'
        else:
            st = MessageStatus.query.filter_by(message_id=msg.id, user_id=user_id).first()
            msg_status = st.status if st else 'delivered'

        media_url = None
        if msg.media_id:
            media_url = f'/api/v1/media/{msg.media_id}'

        item = {
            'id': msg.id,
            'chat_id': msg.chat_id,
            'sender_id': msg.sender_id,
            'sender': sender.to_dict() if sender else None,
            'message_type': msg.message_type,
            'content': msg.content,
            'media_id': msg.media_id,
            'media_url': media_url,
            'reply_to_id': msg.reply_to_id,
            'forwarded_from_id': msg.forwarded_from_id,
            'is_view_once': msg.is_view_once,
            'viewed_at': msg.viewed_at.isoformat() if msg.viewed_at else None,
            'is_edited': msg.is_edited,
            'created_at': msg.created_at.isoformat(),
            'status': msg_status,
        }
        result.append(item)

    return jsonify({'messages': result, 'has_more': len(messages) == limit}), 200


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

    return jsonify({
        'id': msg.id,
        'chat_id': msg.chat_id,
        'sender_id': msg.sender_id,
        'message_type': msg.message_type,
        'content': msg.content,
        'created_at': msg.created_at.isoformat(),
        'status': 'sent',
    }), 201


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
    chat_ids = [m.chat_id for m in ChatMember.query.filter_by(user_id=user_id, is_deleted=False).all()]

    if not chat_ids:
        return jsonify({'messages': [], 'chats_updated': []}), 200

    query = Message.query.filter(
        Message.chat_id.in_(chat_ids),
        Message.is_deleted == False
    )

    if since:
        try:
            since_dt = datetime.fromisoformat(since.replace('Z', '+00:00'))
            query = query.filter(Message.created_at > since_dt)
        except Exception:
            pass

    new_messages = query.order_by(Message.created_at.asc()).limit(limit).all()

    result_msgs = []
    for msg in new_messages:
        sender = User.query.get(msg.sender_id)
        result_msgs.append({
            'id': msg.id,
            'chat_id': msg.chat_id,
            'sender_id': msg.sender_id,
            'sender': sender.to_dict() if sender else None,
            'message_type': msg.message_type,
            'content': msg.content,
            'media_id': msg.media_id,
            'reply_to_id': msg.reply_to_id,
            'is_view_once': msg.is_view_once,
            'created_at': msg.created_at.isoformat(),
        })

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

    messages = Message.query.filter(
        Message.chat_id == chat_id,
        Message.is_deleted == False,
        Message.content.ilike(f'%{q}%')
    ).order_by(Message.created_at.desc()).limit(50).all()

    result = []
    for msg in messages:
        sender = User.query.get(msg.sender_id)
        result.append({
            'id': msg.id,
            'chat_id': msg.chat_id,
            'sender_id': msg.sender_id,
            'sender': sender.to_dict() if sender else None,
            'message_type': msg.message_type,
            'content': msg.content,
            'created_at': msg.created_at.isoformat(),
        })
    return jsonify({'messages': result}), 200


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
        chat = Chat.query.get(chat_id)
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

@messages_bp.route('/<message_id>/view-once', methods=['POST'])
@jwt_required()
def mark_view_once(message_id):
    user_id = get_jwt_identity()
    msg = Message.query.filter_by(id=message_id, is_deleted=False).first()
    if not msg:
        return jsonify({'error': 'پیام یافت نشد'}), 404
    if not msg.is_view_once:
        return jsonify({'error': 'این پیام view once نیست'}), 400
    msg.viewed_at = datetime.utcnow()
    db.session.commit()
    return jsonify({'ok': True}), 200

@messages_bp.route('/statuses', methods=['POST'])
@jwt_required()
def get_message_statuses():
    """گرفتن وضعیت فعلی چند پیام (برای آپدیت تیک‌ها به صورت real-time/polling)"""
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    message_ids = data.get('message_ids') or []
    if not message_ids:
        return jsonify({'statuses': {}}), 200

    result = {}
    for mid in message_ids:
        msg = Message.query.get(mid)
        if not msg:
            continue
        # فقط اجازه چک کردن وضعیت پیام‌های خودمون رو می‌دیم
        if msg.sender_id != user_id:
            continue
        if not user_in_chat(user_id, msg.chat_id):
            continue

        statuses = MessageStatus.query.filter(
            MessageStatus.message_id == mid,
            MessageStatus.user_id != user_id,
        ).all()
        if any(s.status == 'read' for s in statuses):
            result[mid] = 'read'
        elif any(s.status == 'delivered' for s in statuses):
            result[mid] = 'delivered'
        else:
            result[mid] = 'sent'

    return jsonify({'statuses': result}), 200
