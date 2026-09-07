import re
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.user import User, BlockList
from app.models.chat import Chat, ChatMember, ChatBackground
from app.models.message import Message, MessageStatus, PinnedMessage
from app.models.audit import AuditLog
from app.services.message_payloads import visible_messages
from datetime import datetime
import uuid

chats_bp = Blueprint('chats', __name__)

def get_client_ip():
    return request.headers.get('X-Forwarded-For', request.remote_addr)


@chats_bp.route('/', methods=['GET'])
@jwt_required()
def list_chats():
    """لیست چت‌های کاربر با آخرین پیام (برای Polling)"""
    user_id = get_jwt_identity()
    memberships = ChatMember.query.filter_by(user_id=user_id, is_deleted=False).all()

    result = []
    for m in memberships:
        chat = Chat.query.filter_by(id=m.chat_id, is_deleted=False).first()
        if not chat:
            continue

        visible = visible_messages(user_id).filter(Message.chat_id == chat.id)
        last_msg = visible.order_by(Message.created_at.desc(), Message.id.desc()).first()
        unread_query = visible.filter(Message.sender_id != user_id)
        if m.last_read_message_id:
            read_msg = db.session.get(Message, m.last_read_message_id)
            if read_msg and read_msg.chat_id == chat.id:
                unread_query = unread_query.filter(Message.created_at > read_msg.created_at)
        unread = unread_query.count()

        # برای چت خصوصی طرف مقابل را پیدا کن
        other_user = None
        title = chat.title
        avatar = chat.avatar_url
        if chat.chat_type == 'private':
            other_member = ChatMember.query.filter(
                ChatMember.chat_id == chat.id,
                ChatMember.user_id != user_id,
                ChatMember.is_deleted == False
            ).first()
            if other_member:
                other_user = User.query.filter_by(id=other_member.user_id, is_deleted=False).first()
                if other_user:
                    title = other_user.display_name
                    avatar = other_user.avatar_url if other_user.show_profile_photo else None

        result.append({
            'id': chat.id,
            'chat_type': chat.chat_type,
            'title': title,
            'username': chat.username,
            'avatar_url': avatar,
            'is_pinned': m.is_pinned,
            'is_muted': m.is_muted,
            'unread_count': unread,
            'last_message': {
                'id': last_msg.id if last_msg else None,
                'content': last_msg.content if last_msg else None,
                'message_type': last_msg.message_type if last_msg else None,
                'sender_id': last_msg.sender_id if last_msg else None,
                'created_at': last_msg.created_at.isoformat() if last_msg else None,
            } if last_msg else None,
            'updated_at': chat.updated_at.isoformat(),
            'other_user': other_user.to_dict() if other_user else None,
        })

    # مرتب‌سازی: پین‌شده‌ها اول، بعد بر اساس updated_at
    result.sort(key=lambda x: (not x['is_pinned'], x['updated_at']), reverse=True)
    return jsonify({'chats': result}), 200


@chats_bp.route('/private', methods=['POST'])
@jwt_required()
def create_private_chat():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    target_id = data.get('user_id')

    if not target_id or target_id == user_id:
        return jsonify({'error': 'کاربر هدف نامعتبر'}), 400

    target = User.query.filter_by(id=target_id, is_deleted=False).first()
    if not target:
        return jsonify({'error': 'کاربر یافت نشد'}), 404

    # چک بلاک
    blocked = BlockList.query.filter(
        ((BlockList.blocker_id == user_id) & (BlockList.blocked_id == target_id)) |
        ((BlockList.blocker_id == target_id) & (BlockList.blocked_id == user_id)),
        BlockList.is_deleted == False
    ).first()
    if blocked:
        return jsonify({'error': 'امکان ایجاد چت وجود ندارد'}), 403

    # چک وجود چت خصوصی قبلی
    existing = db.session.query(Chat).join(ChatMember).filter(
        Chat.chat_type == 'private',
        Chat.is_deleted == False,
        ChatMember.user_id == user_id,
        ChatMember.is_deleted == False
    ).all()

    for chat in existing:
        other = ChatMember.query.filter(
            ChatMember.chat_id == chat.id,
            ChatMember.user_id == target_id,
            ChatMember.is_deleted == False
        ).first()
        if other:
            return jsonify({'chat_id': chat.id, 'message': 'چت از قبل وجود دارد'}), 200

    chat = Chat(chat_type='private', created_by=user_id)
    db.session.add(chat)
    db.session.flush()

    db.session.add(ChatMember(chat_id=chat.id, user_id=user_id, role='member'))
    db.session.add(ChatMember(chat_id=chat.id, user_id=target_id, role='member'))
    db.session.add(AuditLog(actor_id=user_id, action='create_private_chat', entity_type='chat', entity_id=chat.id))
    db.session.commit()

    return jsonify({'chat_id': chat.id}), 201


@chats_bp.route('/group', methods=['POST'])
@jwt_required()
def create_group():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    title = (data.get('title') or '').strip()
    member_ids = data.get('member_ids') or []
    description = data.get('description')

    if not title or len(title) < 2:
        return jsonify({'error': 'عنوان گروه الزامی است'}), 400

    chat = Chat(
        chat_type='group',
        title=title,
        description=description,
        created_by=user_id,
        is_public=False
    )
    db.session.add(chat)
    db.session.flush()

    db.session.add(ChatMember(chat_id=chat.id, user_id=user_id, role='owner'))
    for mid in member_ids:
        if mid != user_id:
            u = User.query.filter_by(id=mid, is_deleted=False).first()
            if u:
                db.session.add(ChatMember(chat_id=chat.id, user_id=mid, role='member'))

    db.session.add(AuditLog(actor_id=user_id, action='create_group', entity_type='chat', entity_id=chat.id))
    db.session.commit()
    return jsonify({'chat_id': chat.id, 'title': title}), 201


@chats_bp.route('/channel', methods=['POST'])
@jwt_required()
def create_channel():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    title = (data.get('title') or '').strip()
    username = (data.get('username') or '').strip().lower()
    description = data.get('description')
    is_public = bool(data.get('is_public', True))

    if not title:
        return jsonify({'error': 'عنوان کانال الزامی است'}), 400

    if username:
        if not re.match(r'^[a-z0-9_]{3,30}$', username):
            return jsonify({'error': 'نام کاربری کانال نامعتبر'}), 400
        if Chat.query.filter_by(username=username, is_deleted=False).first():
            return jsonify({'error': 'این نام کاربری کانال قبلاً گرفته شده'}), 409

    chat = Chat(
        chat_type='channel',
        title=title,
        username=username or None,
        description=description,
        created_by=user_id,
        is_public=is_public
    )
    db.session.add(chat)
    db.session.flush()
    db.session.add(ChatMember(chat_id=chat.id, user_id=user_id, role='owner'))
    db.session.add(AuditLog(actor_id=user_id, action='create_channel', entity_type='chat', entity_id=chat.id))
    db.session.commit()
    return jsonify({'chat_id': chat.id, 'title': title, 'username': username}), 201


@chats_bp.route('/<chat_id>/members', methods=['GET'])
@jwt_required()
def get_members(chat_id):
    user_id = get_jwt_identity()
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'دسترسی ندارید'}), 403

    members = ChatMember.query.filter_by(chat_id=chat_id, is_deleted=False).all()
    result = []
    for m in members:
        u = User.query.get(m.user_id)
        if u and not u.is_deleted:
            d = u.to_dict()
            d['role'] = m.role
            d['joined_at'] = m.joined_at.isoformat()
            result.append(d)
    return jsonify({'members': result}), 200


@chats_bp.route('/<chat_id>/pin', methods=['POST'])
@jwt_required()
def pin_chat(chat_id):
    user_id = get_jwt_identity()
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'دسترسی ندارید'}), 403
    member.is_pinned = True
    db.session.commit()
    return jsonify({'ok': True}), 200


@chats_bp.route('/<chat_id>/unpin', methods=['POST'])
@jwt_required()
def unpin_chat(chat_id):
    user_id = get_jwt_identity()
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'دسترسی ندارید'}), 403
    member.is_pinned = False
    db.session.commit()
    return jsonify({'ok': True}), 200


@chats_bp.route('/<chat_id>/background', methods=['POST'])
@jwt_required()
def set_background(chat_id):
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    bg_type = data.get('type', 'color')
    value = data.get('value')
    if not value:
        return jsonify({'error': 'مقدار بک‌گراند الزامی است'}), 400

    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'دسترسی ندارید'}), 403

    member.custom_background = value
    existing = ChatBackground.query.filter_by(chat_id=chat_id, user_id=user_id).first()
    if existing:
        existing.background_type = bg_type
        existing.value = value
    else:
        db.session.add(ChatBackground(chat_id=chat_id, user_id=user_id, background_type=bg_type, value=value))
    db.session.commit()
    return jsonify({'ok': True}), 200

@chats_bp.route('/<chat_id>/background', methods=['GET'])
@jwt_required()
def get_background(chat_id):
    user_id = get_jwt_identity()
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'یسرتسد دیرادن'}), 403
    bg = ChatBackground.query.filter_by(chat_id=chat_id, user_id=user_id).first()
    if not bg:
        return jsonify({'background': None}), 200
    return jsonify({'background': {'type': bg.background_type, 'value': bg.value}}), 200


@chats_bp.route('/support', methods=['POST'])
@jwt_required()
def get_or_create_support():
    """چت با پشتیبانی"""
    user_id = get_jwt_identity()
    # پیدا کردن یا ساخت چت پشتیبانی
    support_user = User.query.filter_by(is_support=True, is_deleted=False).first()
    if not support_user:
        # اگر کاربر پشتیبانی وجود ندارد، یکی بساز (در migration یا seed)
        return jsonify({'error': 'پشتیبانی در دسترس نیست'}), 503

    # مشابه create_private_chat
    existing = db.session.query(Chat).join(ChatMember).filter(
        Chat.chat_type == 'support',
        Chat.is_deleted == False,
        ChatMember.user_id == user_id
    ).first()
    if existing:
        return jsonify({'chat_id': existing.id}), 200

    chat = Chat(chat_type='support', title='پشتیبانی', created_by=user_id)
    db.session.add(chat)
    db.session.flush()
    db.session.add(ChatMember(chat_id=chat.id, user_id=user_id, role='member'))
    db.session.add(ChatMember(chat_id=chat.id, user_id=support_user.id, role='admin'))
    db.session.commit()
    return jsonify({'chat_id': chat.id}), 201


@chats_bp.route('/<chat_id>/delete', methods=['POST'])
@jwt_required()
def delete_chat(chat_id):
    """حذف یک‌طرفه یا دوطرفه کل چت"""
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    for_all = bool(data.get('for_all', False))

    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'دسترسی ندارید'}), 403

    if for_all:
        chat = Chat.query.get(chat_id)
        if not chat:
            return jsonify({'error': 'چت یافت نشد'}), 404
        if chat.chat_type in ('group', 'channel') and member.role not in ('owner', 'admin'):
            return jsonify({'error': 'فقط ادمین/مالک می‌تواند برای همه حذف کند'}), 403
        chat.is_deleted = True
        chat.is_deleted_for_all = True
        chat.deleted_at = datetime.utcnow()
        chat.deleted_by = user_id
        # soft delete all members
        ChatMember.query.filter_by(chat_id=chat_id).update({
            'is_deleted': True,
            'deleted_at': datetime.utcnow(),
            'deleted_by': user_id,
        })
    else:
        member.is_deleted = True
        member.deleted_at = datetime.utcnow()
        member.deleted_by = user_id

    db.session.add(AuditLog(
        actor_id=user_id,
        action='delete_chat_for_all' if for_all else 'delete_chat',
        entity_type='chat',
        entity_id=chat_id,
        ip_address=get_client_ip()
    ))
    db.session.commit()
    return jsonify({'ok': True, 'for_all': for_all}), 200


@chats_bp.route('/saved', methods=['POST'])
@jwt_required()
def get_or_create_saved_messages():
    """پیام‌های ذخیره‌شده (چت با خود)"""
    user_id = get_jwt_identity()

    # پیدا کردن چت saved موجود
    existing = db.session.query(Chat).join(ChatMember).filter(
        Chat.chat_type == 'saved',
        Chat.is_deleted == False,
        ChatMember.user_id == user_id,
        ChatMember.is_deleted == False,
    ).first()

    if existing:
        return jsonify({'chat_id': existing.id, 'title': 'Saved Messages'}), 200

    chat = Chat(
        chat_type='saved',
        title='Saved Messages',
        created_by=user_id,
    )
    db.session.add(chat)
    db.session.flush()
    db.session.add(ChatMember(chat_id=chat.id, user_id=user_id, role='owner'))
    db.session.add(AuditLog(actor_id=user_id, action='create_saved_messages', entity_type='chat', entity_id=chat.id))
    db.session.commit()
    return jsonify({'chat_id': chat.id, 'title': 'Saved Messages'}), 201

@chats_bp.route('/<chat_id>/add-member', methods=['POST'])
@jwt_required()
def add_member(chat_id):
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    target_id = data.get('user_id')
    member = ChatMember.query.filter_by(
        chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    if not member or member.role not in ('owner', 'admin'):
        # برای کانال/گروه public اجازه عضویت آزاد
        if not (chat.is_public and chat.chat_type in ('channel', 'group')):
            return jsonify({'error': 'دسترسی ندارید'}), 403
        # اگه خودش داره عضو میشه اجازه بده
        if target_id != user_id:
            return jsonify({'error': 'دسترسی ندارید'}), 403
    target_user = User.query.filter_by(id=target_id, is_deleted=False, is_active=True).first()
    if target_user is None:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    existing = ChatMember.query.filter_by(chat_id=chat_id, user_id=target_id).first()
    if existing and not existing.is_deleted:
        return jsonify({'message': 'قبلاً عضو است'}), 200
    is_admin = member and member.role in ('owner', 'admin')
    if (existing and existing.deleted_by and existing.deleted_by != target_id
            and not is_admin):
        return jsonify({'error': 'امکان عضویت وجود ندارد'}), 403
    role = ('owner' if chat.created_by == target_id else
            'subscriber' if chat.chat_type == 'channel' else 'member')
    if existing:
        existing.is_deleted = False
        existing.deleted_at = None
        existing.deleted_by = None
        existing.joined_at = datetime.utcnow()
        existing.role = role
    else:
        db.session.add(ChatMember(chat_id=chat_id, user_id=target_id, role=role))
    db.session.commit()
    return jsonify({'ok': True}), 201

@chats_bp.route('/<chat_id>/remove-member', methods=['POST'])
@jwt_required()
def remove_member(chat_id):
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    target_id = data.get('user_id')
    member = ChatMember.query.filter_by(
        chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member or member.role not in ('owner', 'admin'):
        return jsonify({'error': 'دسترسی ندارید'}), 403
    target = ChatMember.query.filter_by(
        chat_id=chat_id, user_id=target_id, is_deleted=False).first()
    if target:
        target.is_deleted = True
        target.deleted_at = datetime.utcnow()
        target.deleted_by = user_id
        db.session.commit()
    return jsonify({'ok': True}), 200

@chats_bp.route('/<chat_id>/leave', methods=['POST'])
@jwt_required()
def leave_chat(chat_id):
    user_id = get_jwt_identity()
    member = ChatMember.query.filter_by(
        chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member:
        return jsonify({'error': 'عضو نیستید'}), 403
    member.is_deleted = True
    member.deleted_at = datetime.utcnow()
    member.deleted_by = user_id
    db.session.commit()
    return jsonify({'ok': True}), 200

@chats_bp.route('/<chat_id>/promote', methods=['POST'])
@jwt_required()
def promote_member(chat_id):
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    target_id = data.get('user_id')
    new_role = data.get('role', 'admin')
    member = ChatMember.query.filter_by(
        chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member or member.role != 'owner':
        return jsonify({'error': 'فقط مالک می‌تواند نقش بدهد'}), 403
    target = ChatMember.query.filter_by(
        chat_id=chat_id, user_id=target_id, is_deleted=False).first()
    if not target:
        return jsonify({'error': 'عضو یافت نشد'}), 404
    target.role = new_role
    db.session.commit()
    return jsonify({'ok': True}), 200

@chats_bp.route('/<chat_id>/info', methods=['GET'])
@jwt_required()
def get_chat_info(chat_id):
    user_id = get_jwt_identity()
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member and not chat.is_public:
        return jsonify({'error': 'دسترسی ندارید'}), 403
    # The header must work before either participant has sent a message.
    # Use the same privacy-filtered user serializer as profiles and the list.
    other_user = None
    if member and chat.chat_type in ('private', 'support'):
        other_user = User.query.join(ChatMember, ChatMember.user_id == User.id).filter(
            ChatMember.chat_id == chat_id,
            ChatMember.user_id != user_id,
            ChatMember.is_deleted.is_(False),
            User.is_deleted.is_(False),
        ).first()
    members_count = ChatMember.query.filter_by(chat_id=chat_id, is_deleted=False).count()
    my_role = member.role if member else None
    return jsonify({
        'id': chat.id,
        'chat_type': chat.chat_type,
        'title': chat.title,
        'username': chat.username,
        'description': chat.description,
        'avatar_url': chat.avatar_url,
        'is_public': chat.is_public,
        'created_by': chat.created_by,
        'members_count': members_count,
        'my_role': my_role,
        'other_user': other_user.to_dict() if other_user else None,
        'created_at': chat.created_at.isoformat(),
    }), 200


@chats_bp.route('/<chat_id>/update', methods=['POST'])
@jwt_required()
def update_chat(chat_id):
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member or member.role not in ('owner', 'admin'):
        return jsonify({'error': 'دسترسی ندارید'}), 403
    if 'title' in data and data['title']:
        chat.title = data['title'].strip()[:200]
    if 'description' in data:
        chat.description = data['description']
    if 'avatar_url' in data:
        chat.avatar_url = data['avatar_url']
    if 'is_public' in data and member.role == 'owner':
        chat.is_public = bool(data['is_public'])
    if 'username' in data and member.role == 'owner':
        new_username = (data['username'] or '').strip().lower()
        if new_username:
            if not re.match(r'^[a-z0-9_]{3,30}$', new_username):
                return jsonify({'error': 'یوزرنیم نامعتبر'}), 400
            existing = Chat.query.filter(
                Chat.username == new_username,
                Chat.id != chat_id,
                Chat.is_deleted == False
            ).first()
            if existing:
                return jsonify({'error': 'این یوزرنیم قبلاً گرفته شده'}), 409
            chat.username = new_username
        else:
            chat.username = None
    db.session.add(AuditLog(actor_id=user_id, action='update_chat', entity_type='chat', entity_id=chat_id))
    db.session.commit()
    return jsonify({'ok': True}), 200


@chats_bp.route('/<chat_id>/invite-link', methods=['GET'])
@jwt_required()
def get_invite_link(chat_id):
    user_id = get_jwt_identity()
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member or member.role not in ('owner', 'admin'):
        return jsonify({'error': 'دسترسی ندارید'}), 403
    if chat.chat_type not in ('group', 'channel'):
        return jsonify({'error': 'این چت لینک دعوت ندارد'}), 400
    from app.services.chat_invites import create_invite_link
    link = create_invite_link(chat)
    return jsonify({'invite_link': link, 'chat_id': chat_id}), 200


@chats_bp.route('/join/<chat_id>', methods=['POST'])
@jwt_required()
def join_by_link(chat_id):
    user_id = get_jwt_identity()
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    if not chat.is_public:
        return jsonify({'error': 'این گروه/کانال خصوصی است'}), 403
    existing = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if existing:
        return jsonify({'chat_id': chat_id, 'message': 'قبلاً عضو هستید'}), 200
    db.session.add(ChatMember(chat_id=chat_id, user_id=user_id, role='member'))
    db.session.commit()
    return jsonify({'chat_id': chat_id, 'ok': True}), 201


@chats_bp.route('/<chat_id>/set-permissions', methods=['POST'])
@jwt_required()
def set_permissions(chat_id):
    """تنظیم دسترسی‌های گروه - فقط owner"""
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    chat = Chat.query.filter_by(id=chat_id, is_deleted=False).first()
    if not chat:
        return jsonify({'error': 'چت یافت نشد'}), 404
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id, is_deleted=False).first()
    if not member or member.role != 'owner':
        return jsonify({'error': 'فقط مالک می‌تواند دسترسی‌ها را تغییر دهد'}), 403
    # ذخیره در description به صورت JSON ساده
    import json
    perms = {}
    if 'members_can_send' in data:
        perms['members_can_send'] = bool(data['members_can_send'])
    if 'members_can_add_members' in data:
        perms['members_can_add_members'] = bool(data['members_can_add_members'])
    # ذخیره در extra_data چت
    try:
        existing = json.loads(chat.description or '{}')
        if isinstance(existing, dict) and '__perms' in existing:
            existing['__perms'] = perms
            chat.description = json.dumps(existing, ensure_ascii=False)
    except Exception:
        pass
    db.session.commit()
    return jsonify({'ok': True, 'permissions': perms}), 200


def _invite_chat_for_request():
    """Resolve a bearer invite without granting access merely by previewing it."""
    from app.services.chat_invites import InvalidInvite, resolve_invite

    user = User.query.filter_by(id=get_jwt_identity(), is_deleted=False,
                                is_active=True).first()
    if user is None:
        return None, (jsonify({'error': 'دسترسی ندارید'}), 403)
    data = request.get_json() or {}
    if not isinstance(data, dict):
        return None, (jsonify({'error': 'درخواست نامعتبر است'}), 400)
    try:
        chat = resolve_invite(data.get('invite_link'))
    except InvalidInvite:
        return None, (jsonify({'error': 'لینک دعوت نامعتبر است یا دیگر در دسترس نیست'}), 404)
    member = ChatMember.query.filter_by(chat_id=chat.id, user_id=user.id).first()
    if (member and member.is_deleted and member.deleted_by
            and member.deleted_by != user.id):
        return None, (jsonify({'error': 'امکان عضویت با این لینک وجود ندارد'}), 403)
    return chat, None


def _invite_preview(chat, user_id):
    member = ChatMember.query.filter_by(chat_id=chat.id, user_id=user_id,
                                       is_deleted=False).first()
    return {
        'id': chat.id,
        'chat_type': chat.chat_type,
        'title': chat.title,
        'description': chat.description,
        'avatar_url': chat.avatar_url,
        'members_count': ChatMember.query.filter_by(chat_id=chat.id, is_deleted=False).count(),
        'is_member': member is not None,
    }


@chats_bp.route('/invite-preview', methods=['POST'])
@jwt_required()
def preview_invite():
    chat, error = _invite_chat_for_request()
    if error is not None:
        return error
    return jsonify(_invite_preview(chat, get_jwt_identity())), 200


@chats_bp.route('/join', methods=['POST'])
@jwt_required()
def join_by_invite():
    from sqlalchemy.exc import IntegrityError

    chat, error = _invite_chat_for_request()
    if error is not None:
        return error
    user_id = get_jwt_identity()
    chat_id = chat.id
    member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id).with_for_update().first()
    if member and not member.is_deleted:
        return jsonify(_invite_preview(chat, user_id)), 200

    role = ('owner' if chat.created_by == user_id else
            'subscriber' if chat.chat_type == 'channel' else 'member')
    if member:
        # Reuse the soft-deleted row (uq_chat_member), never insert a duplicate
        # or restore a former admin's privileges after leaving.
        member.is_deleted = False
        member.deleted_at = None
        member.deleted_by = None
        member.joined_at = datetime.utcnow()
        member.role = role
    else:
        db.session.add(ChatMember(chat_id=chat_id, user_id=user_id, role=role))
    db.session.add(AuditLog(
        actor_id=user_id, action='join_chat_by_invite', entity_type='chat',
        entity_id=chat_id, ip_address=get_client_ip(),
    ))
    try:
        db.session.commit()
    except IntegrityError:
        # A repeated tap / second device may have inserted the same membership
        # while this request was in flight. Success is idempotent.
        db.session.rollback()
        member = ChatMember.query.filter_by(chat_id=chat_id, user_id=user_id,
                                           is_deleted=False).first()
        if member is None:
            raise
    return jsonify(_invite_preview(chat, user_id)), 200
