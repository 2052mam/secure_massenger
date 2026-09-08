"""Idempotent, additive upgrade for pre-migration installations (SQLite/MySQL).

Run with workers stopped and a database backup. Never drops or rewrites rows.
"""
from sqlalchemy import inspect, text
from app import db


def upgrade_schema():
    additions = {
        'users': {'allow_group_adds': 'BOOLEAN NOT NULL DEFAULT 1'},
        'chats': {'permissions': 'JSON NULL'},
        'chat_members': {'permissions': 'JSON NULL'},
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
