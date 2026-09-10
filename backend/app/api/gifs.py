from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from app import db
from app.models.gif import SavedGif
from app.models.user import User

gifs_bp = Blueprint('gifs', __name__)

# Telegram-like GIF: we provide curated trending GIFs from public CDNs
# In production you'd proxy Giphy/Tenor; here we curate a static pool for demo
TRENDING_GIFS = [
    {'id': 'cat_work', 'title': 'Cat Working', 'url': 'https://media.giphy.com/media/JIX9t2j0ZTN9S/giphy.gif', 'preview': 'https://media.giphy.com/media/JIX9t2j0ZTN9S/200.gif'},
    {'id': 'dance_meme', 'title': 'Dance', 'url': 'https://media.giphy.com/media/3o7abKhOpu0NwenH3O/giphy.gif', 'preview': 'https://media.giphy.com/media/3o7abKhOpu0NwenH3O/200.gif'},
    {'id': 'laugh', 'title': 'Laugh', 'url': 'https://media.giphy.com/media/l0MYt5jPR6QX5pnqM/giphy.gif', 'preview': 'https://media.giphy.com/media/l0MYt5jPR6QX5pnqM/200.gif'},
    {'id': 'wow', 'title': 'Wow', 'url': 'https://media.giphy.com/media/1oIAU4oBO360QUE0I/giphy.gif', 'preview': 'https://media.giphy.com/media/1oIAU4oBO360QUE0I/200.gif'},
    {'id': 'heart', 'title': 'Heart', 'url': 'https://media.giphy.com/media/26tknCqiJrBQG6bxC/giphy.gif', 'preview': 'https://media.giphy.com/media/26tknCqiJrBQG6bxC/200.gif'},
    {'id': 'party', 'title': 'Party', 'url': 'https://media.giphy.com/media/26n6G8lRMH5ECdr6M/giphy.gif', 'preview': 'https://media.giphy.com/media/26n6G8lRMH5ECdr6M/200.gif'},
    {'id': 'clap', 'title': 'Clap', 'url': 'https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.gif', 'preview': 'https://media.giphy.com/media/3o7btPCcdNniyf0ArS/200.gif'},
    {'id': 'cry', 'title': 'Cry', 'url': 'https://media.giphy.com/media/ISOckXUybVfQ4/giphy.gif', 'preview': 'https://media.giphy.com/media/ISOckXUybVfQ4/200.gif'},
    {'id': 'angry', 'title': 'Angry', 'url': 'https://media.giphy.com/media/11StaZ9BmnhXGE/giphy.gif', 'preview': 'https://media.giphy.com/media/11StaZ9BmnhXGE/200.gif'},
    {'id': 'persian_hello', 'title': 'سلام', 'url': 'https://media.giphy.com/media/xT5LMHxhOfscxPfIfm/giphy.gif', 'preview': 'https://media.giphy.com/media/xT5LMHxhOfscxPfIfm/200.gif'},
    {'id': 'thanks', 'title': 'Thanks', 'url': 'https://media.giphy.com/media/3o6ZsUJ44ffpnAW7Dy/giphy.gif', 'preview': 'https://media.giphy.com/media/3o6ZsUJ44ffpnAW7Dy/200.gif'},
    {'id': 'sleep', 'title': 'Sleep', 'url': 'https://media.giphy.com/media/3o7btPCcdNniyf0ArS/giphy.gif', 'preview': 'https://media.giphy.com/media/3o7btPCcdNniyf0ArS/200.gif'},
    {'id': 'iran_flag', 'title': 'Iran', 'url': 'https://media.giphy.com/media/l4pTdcifPZLpDjL1e/giphy.gif', 'preview': 'https://media.giphy.com/media/l4pTdcifPZLpDjL1e/200.gif'},
    {'id': 'love_u', 'title': 'Love You', 'url': 'https://media.giphy.com/media/26BRuo6sLetdllPAQ/giphy.gif', 'preview': 'https://media.giphy.com/media/26BRuo6sLetdllPAQ/200.gif'},
    {'id': 'happy', 'title': 'Happy', 'url': 'https://media.giphy.com/media/3o7abA4a0QCmZpV3sI/giphy.gif', 'preview': 'https://media.giphy.com/media/3o7abA4a0QCmZpV3sI/200.gif'},
    {'id': 'sad', 'title': 'Sad', 'url': 'https://media.giphy.com/media/l0MYEqEzwMWFCg8rm/giphy.gif', 'preview': 'https://media.giphy.com/media/l0MYEqEzwMWFCg8rm/200.gif'},
]

@gifs_bp.route('/trending', methods=['GET'])
@jwt_required(optional=True)
def trending():
    q = (request.args.get('q') or '').strip().lower()
    limit = min(int(request.args.get('limit', 20)), 50)
    if q:
        filtered = [g for g in TRENDING_GIFS if q in g['title'].lower() or q in g['id']]
        return jsonify({'gifs': filtered[:limit], 'total': len(filtered)}), 200
    return jsonify({'gifs': TRENDING_GIFS[:limit], 'total': len(TRENDING_GIFS)}), 200

@gifs_bp.route('/search', methods=['GET'])
@jwt_required(optional=True)
def search():
    q = (request.args.get('q') or '').strip().lower()
    if not q or len(q) < 1:
        return trending()
    limit = min(int(request.args.get('limit', 20)), 50)
    filtered = [g for g in TRENDING_GIFS if q in g['title'].lower() or q in g['id'] or q in g['url'].lower()]
    # If no match, return trending as fallback (like Telegram shows suggestions)
    if not filtered:
        filtered = TRENDING_GIFS
    return jsonify({'gifs': filtered[:limit], 'total': len(filtered)}), 200

@gifs_bp.route('/saved', methods=['GET'])
@jwt_required()
def list_saved():
    user_id = get_jwt_identity()
    gifs = SavedGif.query.filter_by(user_id=user_id, is_deleted=False).order_by(SavedGif.created_at.desc()).all()
    return jsonify({'gifs': [g.to_dict() for g in gifs]}), 200

@gifs_bp.route('/save', methods=['POST'])
@jwt_required()
def save_gif():
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    gif_url = (data.get('gif_url') or data.get('url') or '').strip()
    media_id = data.get('media_id')
    external_id = data.get('external_id') or data.get('id')
    title = (data.get('title') or '').strip()[:200]
    preview_url = (data.get('preview_url') or data.get('preview') or '').strip()
    if not gif_url and not media_id:
        return jsonify({'error': 'gif_url یا media_id الزامی است'}), 400
    # Prevent duplicates
    existing = None
    if media_id:
        existing = SavedGif.query.filter_by(user_id=user_id, media_id=media_id, is_deleted=False).first()
    elif gif_url:
        existing = SavedGif.query.filter_by(user_id=user_id, gif_url=gif_url, is_deleted=False).first()
    if existing:
        return jsonify({'gif': existing.to_dict(), 'message': 'قبلاً ذخیره شده'}), 200
    # Limit saved gifs
    count = SavedGif.query.filter_by(user_id=user_id, is_deleted=False).count()
    if count >= 200:
        return jsonify({'error': 'حداکثر ۲۰۰ گیف ذخیره می‌شود'}), 400
    gif = SavedGif(user_id=user_id, gif_url=gif_url or None, media_id=media_id, external_id=external_id, title=title or None, preview_url=preview_url or None)
    db.session.add(gif)
    db.session.commit()
    return jsonify({'gif': gif.to_dict()}), 201

@gifs_bp.route('/saved/<gif_id>', methods=['DELETE', 'POST'])
@jwt_required()
def unsave_gif(gif_id):
    user_id = get_jwt_identity()
    gif = SavedGif.query.filter_by(id=gif_id, user_id=user_id, is_deleted=False).first()
    if not gif:
        # also try by gif_url
        gif = SavedGif.query.filter_by(gif_url=gif_id, user_id=user_id, is_deleted=False).first()
    if not gif:
        return jsonify({'error': 'گیف یافت نشد'}), 404
    gif.is_deleted = True
    db.session.commit()
    return jsonify({'ok': True}), 200

@gifs_bp.route('/make', methods=['POST'])
@jwt_required()
def make_gif():
    # Telegram "make GIF": user sends video and marks as GIF
    # Here we accept media_id of video and return gif-like message handling
    # For now just proxy to media upload handling; gif creation is client-side trimming
    user_id = get_jwt_identity()
    data = request.get_json() or {}
    media_id = data.get('media_id')
    if not media_id:
        return jsonify({'error': 'media_id الزامی است'}), 400
    from app.models.media import MediaFile
    media = MediaFile.query.filter_by(id=media_id, uploader_id=user_id, is_deleted=False).first()
    if not media:
        return jsonify({'error': 'فایل یافت نشد'}), 404
    # In Telegram, video becomes looped animation. We'll just confirm.
    return jsonify({'ok': True, 'media_id': media_id, 'gif_url': f'/api/v1/media/{media_id}', 'message': 'گیف ساخته شد - به عنوان انیمیشن ارسال کنید'}), 200
