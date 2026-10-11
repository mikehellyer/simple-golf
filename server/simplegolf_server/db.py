"""SQLite storage for the Simple-Golf society server.

One small file holds everything: accounts, sessions, societies and their
members, tournaments, and every submitted scorecard. Scorecard details
(per-hole strokes, putts and so on) are stored as JSON arrays.
"""
from __future__ import annotations

import os
import sqlite3
from contextlib import contextmanager
from typing import Iterator

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY,
    username TEXT NOT NULL UNIQUE COLLATE NOCASE,
    display_name TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    created TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created TEXT NOT NULL,
    last_used TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS societies (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    invite_code TEXT NOT NULL UNIQUE,
    created_by INTEGER NOT NULL REFERENCES users(id),
    created TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS memberships (
    society_id INTEGER NOT NULL REFERENCES societies(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('admin', 'member')),
    joined TEXT NOT NULL,
    PRIMARY KEY (society_id, user_id)
);
CREATE TABLE IF NOT EXISTS tournaments (
    id INTEGER PRIMARY KEY,
    society_id INTEGER NOT NULL REFERENCES societies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    course_json TEXT NOT NULL,
    course_code TEXT NOT NULL,
    holes INTEGER NOT NULL,
    scoring TEXT NOT NULL CHECK (scoring IN ('single', 'best')),
    starts TEXT NOT NULL,
    ends TEXT NOT NULL,
    created_by INTEGER NOT NULL REFERENCES users(id),
    created TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS rounds (
    id INTEGER PRIMARY KEY,
    society_id INTEGER NOT NULL REFERENCES societies(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tournament_id INTEGER REFERENCES tournaments(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('practice', 'tournament')),
    course_name TEXT NOT NULL,
    course_code TEXT NOT NULL,
    holes INTEGER NOT NULL,
    pars_json TEXT NOT NULL,
    strokes_json TEXT NOT NULL,
    putts_json TEXT NOT NULL,
    fairways_json TEXT NOT NULL,
    gir_json TEXT NOT NULL,
    drives_json TEXT NOT NULL,
    total INTEGER NOT NULL,
    par_total INTEGER NOT NULL,
    played_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS rounds_by_member ON rounds (society_id, user_id);
CREATE INDEX IF NOT EXISTS rounds_by_tournament ON rounds (tournament_id);
"""


def database_path() -> str:
    return os.environ.get("SIMPLEGOLF_DB", "simplegolf.db")


def connect(path: str | None = None) -> sqlite3.Connection:
    conn = sqlite3.connect(path or database_path(), check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.executescript(SCHEMA)
    return conn


@contextmanager
def transaction(conn: sqlite3.Connection) -> Iterator[sqlite3.Connection]:
    """Commit on success, roll back on any error."""
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
