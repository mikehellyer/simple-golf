"""Passwords, session tokens and invite codes, using only the standard library.

Passwords are hashed with scrypt and a per-user salt. Session tokens are
random 256-bit values; only their SHA-256 hash is stored, so a copy of the
database can't be used to sign in as anyone.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import time

# scrypt cost: ~16 MB and a few tens of milliseconds per hash.
_N, _R, _P = 2**14, 8, 1
INVITE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O or 1/I


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=_N, r=_R, p=_P, dklen=32)
    return "scrypt$%s$%s" % (base64.b64encode(salt).decode(), base64.b64encode(digest).decode())


def check_password(password: str, stored: str) -> bool:
    try:
        scheme, salt_b64, digest_b64 = stored.split("$")
    except ValueError:
        return False
    if scheme != "scrypt":
        return False
    digest = hashlib.scrypt(password.encode(), salt=base64.b64decode(salt_b64), n=_N, r=_R, p=_P, dklen=32)
    return hmac.compare_digest(digest, base64.b64decode(digest_b64))


def new_token() -> str:
    return secrets.token_urlsafe(32)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def new_invite_code() -> str:
    return "SG-" + "".join(secrets.choice(INVITE_ALPHABET) for _ in range(6))


class LoginThrottle:
    """Slows down password guessing: after too many failures for a username
    in a short window, further attempts are refused until it passes."""

    def __init__(self, limit: int = 8, window_seconds: float = 900.0):
        self.limit = limit
        self.window = window_seconds
        self._failures: dict[str, list[float]] = {}

    def blocked(self, username: str) -> bool:
        now = time.monotonic()
        recent = [t for t in self._failures.get(username.lower(), []) if now - t < self.window]
        self._failures[username.lower()] = recent
        return len(recent) >= self.limit

    def failed(self, username: str) -> None:
        self._failures.setdefault(username.lower(), []).append(time.monotonic())

    def succeeded(self, username: str) -> None:
        self._failures.pop(username.lower(), None)
