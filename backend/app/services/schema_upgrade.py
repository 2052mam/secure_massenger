"""Idempotent, additive upgrade for pre-migration installations (SQLite/MySQL).

Run with workers stopped and a database backup. Never drops or rewrites rows.
"""
from sqlalchemy import inspect, text
from app import db


def upgrade_schema():
    additions = {
        'users': {
            'allow_group_adds': 'BOOLEAN NOT NULL DEFAULT 1',
            'archive_pin_hash': 'VARCHAR(255) NULL',
            'archive_pin_updated_at': 'DATETIME NULL',
        },
        'chats': {
            'permissions': 'JSON NULL',
            'slow_mode_delay': 'INTEGER NOT NULL DEFAULT 0',
        },
        'chat_members': {
            'permissions': 'JSON NULL',
            'is_archived': 'BOOLEAN NOT NULL DEFAULT 0',
            'archived_at': 'DATETIME NULL',
            'pinned_at': 'DATETIME NULL',
        },
        'messages': {
            'is_spoiler': 'BOOLEAN NOT NULL DEFAULT 0',
            'is_scheduled': 'BOOLEAN NOT NULL DEFAULT 0',
            'scheduled_at': 'DATETIME NULL',
        },
    }
    with db.engine.begin() as connection:
        for table, columns in additions.items():
            inspector = inspect(connection)
            if not inspector.has_table(table):
                continue
            existing = {column['name'] for column in inspector.get_columns(table)}
            for column, definition in columns.items():
                if column not in existing:
                    connection.execute(text(f'ALTER TABLE {table} ADD COLUMN {column} {definition}'))

    # New, self contained tables (folders, profile albums, search history).
    # create_all only creates what is missing and never rewrites existing rows.
    from app.models.folder import ChatFolder, ChatFolderItem  # noqa: F401
    from app.models.profile import SearchHistory, UserPhoto  # noqa: F401

    db.metadata.create_all(bind=db.engine, tables=[
        ChatFolder.__table__, ChatFolderItem.__table__,
        UserPhoto.__table__, SearchHistory.__table__,
    ])
