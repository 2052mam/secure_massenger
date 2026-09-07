from flask import Blueprint, request, jsonify, current_app
from flask_jwt_extended import create_access_token, create_refresh_token, jwt_required, get_jwt_identity
from app import db
from app.models.user import User, UserDevice, UserSession
from app.models.audit import AuditLog
from datetime import datetime, timedelta
import re
import hashlib

auth_bp = Blueprint('auth', __name__)

def get_client_ip():
    return request.headers.get('X-Forwarded-For', request.remote_addr)

def create_device_fingerprint(data: dict) -> str:
    raw = f"{data.get('device_id','')}-{data.get('model','')}-{data.get('os','')}-{data.get('mac','')}"
    return hashlib.sha256(raw.encode()).hexdigest()

@auth_bp.route('/register', methods=['POST'])
def register():
    data = request.get_json() or {}
    email = (data.get('email') or '').strip().lower()
    password = data.get('password') or ''
    username = (data.get('username') or '').strip().lower()
    display_name = (data.get('display_name') or '').strip()
    device_info = data.get('device_info') or {}

    if not email or not password or not username or not display_name:
        return jsonify({'error': 'تمام فیلدها الزامی هستند'}), 400

    if not re.match(r'^[\w\.-]+@[\w\.-]+\.\w+$', email):
        return jsonify({'error': 'ایمیل نامعتبر است'}), 400

    if len(password) < 8:
        return jsonify({'error': 'رمز عبور باید حداقل ۸ کاراکتر باشد'}), 400

    if not re.match(r'^[a-z0-9_]{3,30}$', username):
        return jsonify({'error': 'نام کاربری فقط حروف کوچک، عدد و _ (۳ تا ۳۰ کاراکتر)'}), 400

    if User.query.filter_by(email=email, is_deleted=False).first():
        return jsonify({'error': 'این ایمیل قبلاً ثبت شده'}), 409

    if User.query.filter_by(username=username, is_deleted=False).first():
        return jsonify({'error': 'این نام کاربری قبلاً گرفته شده'}), 409

    fingerprint = create_device_fingerprint(device_info)
    mac = device_info.get('mac_address')

    # محدودیت ۳ اکانت روی هر دستگاه
    existing_devices = UserDevice.query.filter_by(
        device_fingerprint=fingerprint, is_deleted=False
    ).count()
    if existing_devices >= current_app.config['MAX_ACCOUNTS_PER_DEVICE']:
        return jsonify({
            'error': 'حداکثر ۳ اکانت روی این دستگاه مجاز است. حتی بعد از حذف اپلیکیشن این محدودیت برقرار است.'
        }), 403

    user = User(
        email=email,
        username=username,
        display_name=display_name,
    )
    user.set_password(password)
    secret = user.generate_totp_secret()
    db.session.add(user)
    db.session.flush()

    device = UserDevice(
        user_id=user.id,
        device_fingerprint=fingerprint,
        mac_address=mac,
        device_name=device_info.get('device_name'),
        device_model=device_info.get('model'),
        os_version=device_info.get('os'),
        app_version=device_info.get('app_version'),
        user_agent=request.headers.get('User-Agent'),
    )
    db.session.add(device)

    audit = AuditLog(
        actor_id=user.id,
        action='user_register',
        entity_type='user',
        entity_id=user.id,
        ip_address=get_client_ip(),
        user_agent=request.headers.get('User-Agent'),
        device_fingerprint=fingerprint,
    )
    db.session.add(audit)
    db.session.commit()

    totp_uri = user.get_totp_uri()

    return jsonify({
        'message': 'ثبت‌نام موفق. کلید 2FA را همین حالا در Google Authenticator ذخیره کنید. این کلید قابل بازیابی نیست.',
        'user_id': user.id,
        'totp_secret': secret,
        'totp_uri': totp_uri,
        'warning': 'کلید 2FA فقط یک‌بار نمایش داده می‌شود. حتماً آن را ذخیره کنید.',
    }), 201


@auth_bp.route('/verify-2fa', methods=['POST'])
def verify_2fa_register():
    """بعد از ثبت‌نام باید کد 2FA را وارد کند تا اکانت فعال شود"""
    data = request.get_json() or {}
    user_id = data.get('user_id')
    code = data.get('code')

    user = User.query.filter_by(id=user_id, is_deleted=False).first()
    if not user:
        return jsonify({'error': 'کاربر یافت نشد'}), 404

    if not user.verify_totp(code):
        return jsonify({'error': 'کد 2FA نامعتبر است'}), 401

    # ایجاد نشست
    access = create_access_token(identity=user.id, expires_delta=timedelta(hours=24))
    refresh = create_refresh_token(identity=user.id, expires_delta=timedelta(days=30))

    session = UserSession(
        user_id=user.id,
        refresh_token=refresh,
        ip_address=get_client_ip(),
        expires_at=datetime.utcnow() + timedelta(days=30),
    )
    db.session.add(session)
    db.session.commit()

    return jsonify({
        'access_token': access,
        'refresh_token': refresh,
        'user': user.to_dict(include_private=True),
    }), 200


@auth_bp.route('/login', methods=['POST'])
def login():
    data = request.get_json() or {}
    email = (data.get('email') or '').strip().lower()
    password = data.get('password') or ''
    code = data.get('totp_code')
    device_info = data.get('device_info') or {}

    user = User.query.filter_by(email=email, is_deleted=False).first()
    if not user or not user.check_password(password):
        return jsonify({'error': 'ایمیل یا رمز عبور اشتباه است'}), 401

    if not user.is_active:
        return jsonify({'error': 'اکانت غیرفعال است'}), 403

    if not code:
        return jsonify({'error': 'کد 2FA الزامی است', 'require_2fa': True}), 401

    if not user.verify_totp(code):
        return jsonify({'error': 'کد 2FA نامعتبر است'}), 401

    fingerprint = create_device_fingerprint(device_info)

    # چک محدودیت دستگاه
    device = UserDevice.query.filter_by(
        user_id=user.id, device_fingerprint=fingerprint, is_deleted=False
    ).first()

    if not device:
        count = UserDevice.query.filter_by(user_id=user.id, is_deleted=False).count()
        if count >= current_app.config['MAX_ACCOUNTS_PER_DEVICE']:
            return jsonify({'error': 'حداکثر ۳ دستگاه برای این اکانت مجاز است'}), 403

        device = UserDevice(
            user_id=user.id,
            device_fingerprint=fingerprint,
            mac_address=device_info.get('mac_address'),
            device_name=device_info.get('device_name'),
            device_model=device_info.get('model'),
            os_version=device_info.get('os'),
            app_version=device_info.get('app_version'),
            user_agent=request.headers.get('User-Agent'),
        )
        db.session.add(device)

    device.last_active = datetime.utcnow()
    user.is_online = True
    user.last_seen = datetime.utcnow()

    access = create_access_token(identity=user.id, expires_delta=timedelta(hours=24))
    refresh = create_refresh_token(identity=user.id, expires_delta=timedelta(days=30))

    session = UserSession(
        user_id=user.id,
        device_id=device.id,
        refresh_token=refresh,
        ip_address=get_client_ip(),
        expires_at=datetime.utcnow() + timedelta(days=30),
    )
    db.session.add(session)

    audit = AuditLog(
        actor_id=user.id,
        action='user_login',
        entity_type='user',
        entity_id=user.id,
        ip_address=get_client_ip(),
        device_fingerprint=fingerprint,
    )
    db.session.add(audit)
    db.session.commit()

    return jsonify({
        'access_token': access,
        'refresh_token': refresh,
        'user': user.to_dict(include_private=True),
    }), 200


@auth_bp.route('/logout', methods=['POST'])
@jwt_required()
def logout():
    user_id = get_jwt_identity()
    user = User.query.get(user_id)
    if user:
        user.is_online = False
        user.last_seen = datetime.utcnow()
        db.session.commit()
    return jsonify({'message': 'خروج موفق'}), 200


@auth_bp.route('/refresh', methods=['POST'])
@jwt_required(refresh=True)
def refresh():
    user_id = get_jwt_identity()
    access = create_access_token(identity=user_id, expires_delta=timedelta(hours=24))
    return jsonify({'access_token': access}), 200
