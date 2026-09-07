from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.user import User, BlockList, UserDevice
from app.models.audit import AuditLog
from datetime import datetime
import re

users_bp = Blueprint('users', __name__)

def get_client_ip():
    return request.headers.get('X-Forwarded-For', request.remote_addr)

@users_bp.route('/me', methods=['GET'])
@jwt_required()
def get_me():
    user_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    return jsonify(user.to_dict(include_private=True)), 200


@users_bp.route('/me', methods=['PUT'])
@jwt_required()
def update_me():
    user_id = get_jwt_identity()
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404

    data = request.get_json() or {}
    if 'display_name' in data:
        user.display_name = data['display_name'].strip()[:100]
    if 'bio' in data:
        user.bio = data['bio'].strip()[:500] if data['bio'] else None
    if 'username' in data:
        new_username = data['username'].strip().lower()
        if not re.match(r'^[a-z0-9_]{3,30}$', new_username):
            return jsonify({'error': 'نام کاربری نامعتبر'}), 400
        existing = User.query.filter(User.username == new_username, User.id != user.id, User.is_deleted == False).first()
        if existing:
            return jsonify({'error': 'نام کاربری قبلاً گرفته شده'}), 409
        user.username = new_username
    if 'show_last_seen' in data:
        user.show_last_seen = bool(data['show_last_seen'])
    if 'show_profile_photo' in data:
        user.show_profile_photo = bool(data['show_profile_photo'])
    if 'show_bio' in data:
        user.show_bio = bool(data['show_bio'])
    if 'avatar_url' in data:
        user.avatar_url = data['avatar_url']

    user.updated_at = datetime.utcnow()
    db.session.add(AuditLog(
        actor_id=user.id, action='profile_update', entity_type='user', entity_id=user.id,
        ip_address=get_client_ip()
    ))
    db.session.commit()
    return jsonify(user.to_dict(include_private=True)), 200


@users_bp.route('/search', methods=['GET'])
@jwt_required()
def search_users():
    q = (request.args.get('q') or '').strip().lower()
    if len(q) < 2:
        return jsonify({'users': [], 'chats': []}), 200

    current_id = get_jwt_identity()

    users = User.query.filter(
        User.is_deleted == False,
        User.is_active == True,
        User.id != current_id,
        (User.username.ilike(f'%{q}%') | User.display_name.ilike(f'%{q}%'))
    ).limit(30).all()

    result_users = []
    for u in users:
        blocked = BlockList.query.filter(
            ((BlockList.blocker_id == current_id) & (BlockList.blocked_id == u.id)) |
            ((BlockList.blocker_id == u.id) & (BlockList.blocked_id == current_id)),
            BlockList.is_deleted == False
        ).first()
        if not blocked:
            result_users.append(u.to_dict())

    from app.models.chat import Chat
    chats = Chat.query.filter(
        Chat.is_deleted == False,
        Chat.is_public == True,
        Chat.chat_type == 'channel',
        (Chat.title.ilike(f'%{q}%') | Chat.username.ilike(f'%{q}%'))
    ).limit(20).all()

    result_chats = [{
        'id': c.id,
        'chat_type': c.chat_type,
        'title': c.title,
        'username': c.username,
        'avatar_url': c.avatar_url,
    } for c in chats]

    return jsonify({'users': result_users, 'chats': result_chats}), 200


@users_bp.route('/<user_id>', methods=['GET'])
@jwt_required()
def get_user(user_id):
    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404
    return jsonify(user.to_dict()), 200


@users_bp.route('/block/<user_id>', methods=['POST'])
@jwt_required()
def block_user(user_id):
    current_id = get_jwt_identity()
    if current_id == user_id:
        return jsonify({'error': 'نمی‌توانید خودتان را بلاک کنید'}), 400

    target = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not target:
        return jsonify({'error': 'کاربر یافت نشد'}), 404

    existing = BlockList.query.filter_by(blocker_id=current_id, blocked_id=user_id).first()
    if existing and not existing.is_deleted:
        return jsonify({'message': 'قبلاً بلاک شده'}), 200

    if existing:
        existing.is_deleted = False
        existing.deleted_at = None
    else:
        db.session.add(BlockList(blocker_id=current_id, blocked_id=user_id))

    db.session.add(AuditLog(
        actor_id=current_id, action='block_user', entity_type='user', entity_id=user_id,
        ip_address=get_client_ip()
    ))
    db.session.commit()
    return jsonify({'message': 'کاربر بلاک شد'}), 200


@users_bp.route('/unblock/<user_id>', methods=['POST'])
@jwt_required()
def unblock_user(user_id):
    current_id = get_jwt_identity()
    block = BlockList.query.filter_by(blocker_id=current_id, blocked_id=user_id, is_deleted=False).first()
    if not block:
        return jsonify({'message': 'بلاک نبود'}), 200

    block.is_deleted = True
    block.deleted_at = datetime.utcnow()
    db.session.add(AuditLog(
        actor_id=current_id, action='unblock_user', entity_type='user', entity_id=user_id,
        ip_address=get_client_ip()
    ))
    db.session.commit()
    return jsonify({'message': 'آنبلاک شد'}), 200


@users_bp.route('/online-status', methods=['POST'])
@jwt_required()
def update_online_status():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    is_online = bool(data.get('is_online', True))

    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404

    user.is_online = is_online
    user.last_seen = datetime.utcnow()
    db.session.commit()
    return jsonify({'ok': True}), 200


@users_bp.route('/blocked', methods=['GET'])
@jwt_required()
def get_blocked():
    current_id = get_jwt_identity()
    blocks = BlockList.query.filter_by(blocker_id=current_id, is_deleted=False).all()
    users = []
    for b in blocks:
        u = User.query.get(b.blocked_id)
        if u and not u.is_deleted:
            users.append(u.to_dict())
    return jsonify({'users': users}), 200
