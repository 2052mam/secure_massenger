from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_cors import CORS
from flask_jwt_extended import JWTManager
from dotenv import load_dotenv
import os

load_dotenv()

db = SQLAlchemy()
migrate = Migrate()
jwt = JWTManager()

def create_app():
    app = Flask(__name__)

    app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'dev-secret-change-me')
    app.config['JWT_SECRET_KEY'] = os.getenv('JWT_SECRET_KEY', 'jwt-secret-change-me')
    app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL')
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    app.config['SQLALCHEMY_ENGINE_OPTIONS'] = {
        'pool_pre_ping': True,
        'pool_recycle': 280,
    }
    app.config['MAX_CONTENT_LENGTH'] = int(os.getenv('MAX_CONTENT_LENGTH', 50 * 1024 * 1024))
    app.config['UPLOAD_FOLDER'] = os.getenv('UPLOAD_FOLDER', 'uploads')
    app.config['ADMIN_SECRET_PATH'] = os.getenv('ADMIN_SECRET_PATH', 'sm-admin-x9k2p7')
    app.config['MAX_ACCOUNTS_PER_DEVICE'] = int(os.getenv('MAX_ACCOUNTS_PER_DEVICE', 3))

    os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

    db.init_app(app)
    migrate.init_app(app, db)
    jwt.init_app(app)
    CORS(app, resources={r"/api/*": {"origins": "*"}})

    from app.api.auth import auth_bp
    from app.api.users import users_bp
    from app.api.chats import chats_bp
    from app.api.messages import messages_bp
    from app.api.media import media_bp
    from app.api.admin_api import admin_api_bp
    from app.admin.routes import admin_web_bp

    app.register_blueprint(auth_bp, url_prefix='/api/v1/auth')
    app.register_blueprint(users_bp, url_prefix='/api/v1/users')
    app.register_blueprint(chats_bp, url_prefix='/api/v1/chats')
    app.register_blueprint(messages_bp, url_prefix='/api/v1/messages')
    app.register_blueprint(media_bp, url_prefix='/api/v1/media')
    app.register_blueprint(admin_api_bp, url_prefix='/api/v1/admin')
    app.register_blueprint(admin_web_bp)

    @app.route('/health')
    def health():
        return {'status': 'ok', 'polling': True}, 200

    return app
