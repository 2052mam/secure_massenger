from app.services.timestamps import utc_iso
from app import db
from datetime import datetime, timedelta
from werkzeug.security import generate_password_hash, check_password_hash
import pyotp
import uuid

class User(db.Model):
    __tablename__ = 'users'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    email = db.Column(db.String(255), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    username = db.Column(db.String(50), unique=True, nullable=False, index=True)
    display_name = db.Column(db.String(100), nullable=False)
    bio = db.Column(db.Text, nullable=True)
    avatar_url = db.Column(db.String(500), nullable=True)
    
    # 2FA
    totp_secret = db.Column(db.String(32), nullable=False)
    is_2fa_enabled = db.Column(db.Boolean, default=True, nullable=False)
    
    # Privacy
    is_online = db.Column(db.Boolean, default=False)
    last_seen = db.Column(db.DateTime, default=datetime.utcnow)
    show_last_seen = db.Column(db.Boolean, default=True)  # Ghost mode = False
    show_profile_photo = db.Column(db.Boolean, default=True)
    show_bio = db.Column(db.Boolean, default=True)
    
    allow_group_adds = db.Column(db.Boolean, nullable=False, default=True, server_default=db.true())

    # Status
    is_active = db.Column(db.Boolean, default=True)
    is_admin = db.Column(db.Boolean, default=False)
    is_support = db.Column(db.Boolean, default=False)
    
    # Soft Delete
    is_deleted = db.Column(db.Boolean, default=False, index=True)
    deleted_at = db.Column(db.DateTime, nullable=True)
    deleted_by = db.Column(db.String(36), nullable=True)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    devices = db.relationship('UserDevice', backref='user', lazy='dynamic')
    sessions = db.relationship('UserSession', backref='user', lazy='dynamic')

    def set_password(self, password: str):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password: str) -> bool:
        return check_password_hash(self.password_hash, password)

    def generate_totp_secret(self):
        self.totp_secret = pyotp.random_base32()
        return self.totp_secret

    def get_totp_uri(self):
        return pyotp.totp.TOTP(self.totp_secret).provisioning_uri(
            name=self.email, issuer_name='SecureMessenger'
        )

    def verify_totp(self, code: str) -> bool:
        totp = pyotp.TOTP(self.totp_secret)
        return totp.verify(code, valid_window=2)  # ±60s برای ناهمزمانی ساعت سرور/گوشی (تهران)

    def to_dict(self, include_private=False):
        # A killed/offline app cannot send a final offline request. Expire its
        # heartbeat instead of leaving the profile online indefinitely.
        online = bool(self.is_online and self.last_seen and
                      timedelta(0) <= datetime.utcnow() - self.last_seen < timedelta(seconds=60))
        data = {
            'id': self.id,
            'username': self.username,
            'display_name': self.display_name,
            'bio': self.bio if self.show_bio else None,
            'avatar_url': self.avatar_url if self.show_profile_photo else None,
            'is_online': online if self.show_last_seen else False,
            'last_seen': utc_iso(self.last_seen) if self.show_last_seen and self.last_seen else None,
            'created_at': utc_iso(self.created_at),
        }
        if include_private:
            data.update({
                'email': self.email,
                'avatar_url': self.avatar_url,
                'bio': self.bio,
                'allow_group_adds': self.allow_group_adds,
                'show_last_seen': self.show_last_seen,
                'show_profile_photo': self.show_profile_photo,
                'show_bio': self.show_bio,
                'is_2fa_enabled': self.is_2fa_enabled,
            })
        return data


class UserDevice(db.Model):
    __tablename__ = 'user_devices'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)
    
    device_fingerprint = db.Column(db.String(255), nullable=False, index=True)
    mac_address = db.Column(db.String(64), nullable=True)
    device_name = db.Column(db.String(150), nullable=True)
    device_model = db.Column(db.String(150), nullable=True)
    os_version = db.Column(db.String(100), nullable=True)
    app_version = db.Column(db.String(50), nullable=True)
    user_agent = db.Column(db.Text, nullable=True)
    
    is_active = db.Column(db.Boolean, default=True)
    last_active = db.Column(db.DateTime, default=datetime.utcnow)
    
    # Soft Delete
    is_deleted = db.Column(db.Boolean, default=False)
    deleted_at = db.Column(db.DateTime, nullable=True)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    __table_args__ = (
        db.Index('idx_device_fingerprint', 'device_fingerprint'),
        db.UniqueConstraint('user_id', 'device_fingerprint', name='uq_user_device'),
    )


class UserSession(db.Model):
    __tablename__ = 'user_sessions'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)
    device_id = db.Column(db.String(36), db.ForeignKey('user_devices.id'), nullable=True)
    
    refresh_token = db.Column(db.String(512), unique=True, nullable=False)
    ip_address = db.Column(db.String(45), nullable=True)
    is_active = db.Column(db.Boolean, default=True)
    
    expires_at = db.Column(db.DateTime, nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    last_used = db.Column(db.DateTime, default=datetime.utcnow)


class BlockList(db.Model):
    __tablename__ = 'block_list'

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    blocker_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)
    blocked_id = db.Column(db.String(36), db.ForeignKey('users.id'), nullable=False, index=True)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    # Soft Delete (unblock)
    is_deleted = db.Column(db.Boolean, default=False)
    deleted_at = db.Column(db.DateTime, nullable=True)

    __table_args__ = (
        db.UniqueConstraint('blocker_id', 'blocked_id', name='uq_block'),
    )
