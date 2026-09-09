from flask import Blueprint, request, jsonify, current_app, send_from_directory
from flask_jwt_extended import jwt_required, get_jwt_identity
from werkzeug.utils import secure_filename
from app import db
from app.models.media import MediaFile
from app.models.message import Message
from app.models.audit import AuditLog
from datetime import datetime
import os
import uuid

media_bp = Blueprint('media', __name__)

ALLOWED_EXTENSIONS = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mov', 'webm', 'mp3', 'ogg', 'm4a', 'pdf', 'doc', 'docx', 'zip'}

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def get_media_type(ext):
    ext = ext.lower()
    if ext in {'jpg', 'jpeg', 'png', 'gif', 'webp'}:
        return 'image'
    if ext in {'mp4', 'mov', 'webm'}:
        return 'video'
    if ext in {'mp3', 'ogg', 'm4a'}:
        return 'audio'
    return 'document'


@media_bp.route('/upload', methods=['POST'])
@jwt_required()
def upload_media():
    user_id = get_jwt_identity()

    if 'file' not in request.files:
        return jsonify({'error': 'فایل ارسال نشده'}), 400

    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'نام فایل خالی است'}), 400

    if not allowed_file(file.filename):
        return jsonify({'error': 'نوع فایل مجاز نیست'}), 400

    original_name = secure_filename(file.filename)
    ext = original_name.rsplit('.', 1)[1].lower()
    stored_name = f"{uuid.uuid4().hex}.{ext}"
    upload_folder = current_app.config['UPLOAD_FOLDER']
    os.makedirs(upload_folder, exist_ok=True)
    file_path = os.path.abspath(os.path.join(upload_folder, stored_name))
    file.save(file_path)

    file_size = os.path.getsize(file_path)
    media_type = get_media_type(ext)

    media = MediaFile(
        uploader_id=user_id,
        original_name=original_name,
        stored_name=stored_name,
        mime_type=file.mimetype or f'application/{ext}',
        file_size=file_size,
        file_path=file_path,
        media_type=media_type,
    )
    db.session.add(media)
    db.session.add(AuditLog(
        actor_id=user_id, action='upload_media', entity_type='media', entity_id=media.id
    ))
    db.session.commit()

    return jsonify({
        'id': media.id,
        'original_name': media.original_name,
        'media_type': media.media_type,
        'file_size': media.file_size,
        'url': f'/api/v1/media/{media.id}',
    }), 201


@media_bp.route('/<media_id>', methods=['GET'])
@jwt_required()
def get_media(media_id):
    media = MediaFile.query.filter_by(id=media_id, is_deleted=False).first()
    if not media:
        return jsonify({'error': 'فایل یافت نشد'}), 404
    # Include deleted references: soft-deleting the message must not make its
    # ephemeral upload replayable through this generic, cacheable URL.
    if Message.query.filter_by(media_id=media_id, is_view_once=True).first():
        return jsonify({'error': 'عکس یک‌بارمصرف فقط از داخل پیام باز می‌شود'}), 403
    upload_folder = os.path.abspath(current_app.config['UPLOAD_FOLDER'])
    download = request.args.get('download') in ('1', 'true', 'yes')
    # Conditional responses explicitly preserve Range / Content-Range support
    # required by native voice/video players when seeking.
    return send_from_directory(
        upload_folder,
        media.stored_name,
        conditional=not download,
        as_attachment=download,
        download_name=media.original_name if download else None,
    )
