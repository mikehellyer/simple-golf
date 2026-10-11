"""The Simple-Golf society server: a small JSON API.

Players create an account, then create or join societies (by invite code).
Society admins arrange tournaments: a course, a length, a date window and a
scoring rule (one round counts, or best of several). Members' practice and
tournament rounds are submitted as scorecards, kept for good, and used for
stats and leaderboards.

Run locally:  uvicorn simplegolf_server.app:app --reload
"""
from __future__ import annotations

import json
import os
import re
from datetime import date, datetime, timezone
from typing import Literal, Optional

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field, field_validator

from . import db as database
from . import security, stats

VERSION = "1.0.0"
# Game versions older than this are asked to update before using the society.
MIN_CLIENT = os.environ.get("SIMPLEGOLF_MIN_CLIENT", "0.3.0")

app = FastAPI(title="Simple-Golf society server", version=VERSION)
_conn = None
_throttle = security.LoginThrottle()


def conn():
    global _conn
    if _conn is None:
        _conn = database.connect()
    return _conn


def use_database(path: str) -> None:
    """Point the server at a database file (used by the tests)."""
    global _conn
    _conn = database.connect(path)


def now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def today() -> str:
    return datetime.now(timezone.utc).date().isoformat()


# --- Auth ------------------------------------------------------------------

USERNAME = re.compile(r"^[A-Za-z0-9_.-]{3,20}$")


class Credentials(BaseModel):
    username: str
    password: str = Field(min_length=6, max_length=128)


class Registration(Credentials):
    display_name: str = Field(min_length=1, max_length=12)

    @field_validator("username")
    @classmethod
    def valid_username(cls, v: str) -> str:
        if not USERNAME.match(v):
            raise ValueError("3-20 letters, digits, dots, dashes or underscores")
        return v

    @field_validator("display_name")
    @classmethod
    def tidy_name(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("a display name is required")
        return v


def current_user(authorization: str = Header(default="")) -> dict:
    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise HTTPException(401, "Please sign in.")
    row = conn().execute(
        "SELECT u.id, u.username, u.display_name FROM sessions s JOIN users u ON u.id = s.user_id "
        "WHERE s.token_hash = ?", (security.token_hash(token),)).fetchone()
    if row is None:
        raise HTTPException(401, "Your session has expired; please sign in again.")
    conn().execute("UPDATE sessions SET last_used = ? WHERE token_hash = ?",
                   (now(), security.token_hash(token)))
    conn().commit()
    return dict(row)


def _session_for(user_id: int) -> str:
    token = security.new_token()
    with database.transaction(conn()) as c:
        c.execute("INSERT INTO sessions VALUES (?, ?, ?, ?)", (security.token_hash(token), user_id, now(), now()))
    return token


@app.get("/api/v1/health")
def health() -> dict:
    return {"ok": True, "version": VERSION, "min_client": MIN_CLIENT}


@app.post("/api/v1/auth/register")
def register(body: Registration) -> dict:
    exists = conn().execute("SELECT 1 FROM users WHERE username = ?", (body.username,)).fetchone()
    if exists:
        raise HTTPException(409, "That username is taken.")
    with database.transaction(conn()) as c:
        cur = c.execute("INSERT INTO users (username, display_name, password_hash, created) VALUES (?, ?, ?, ?)",
                        (body.username, body.display_name, security.hash_password(body.password), now()))
    user_id = cur.lastrowid
    return {"token": _session_for(user_id), "user": _user(user_id)}


@app.post("/api/v1/auth/login")
def login(body: Credentials) -> dict:
    if _throttle.blocked(body.username):
        raise HTTPException(429, "Too many attempts; try again in 15 minutes.")
    row = conn().execute("SELECT id, password_hash FROM users WHERE username = ?", (body.username,)).fetchone()
    if row is None or not security.check_password(body.password, row["password_hash"]):
        _throttle.failed(body.username)
        raise HTTPException(401, "Wrong username or password.")
    _throttle.succeeded(body.username)
    return {"token": _session_for(row["id"]), "user": _user(row["id"])}


@app.post("/api/v1/auth/logout")
def logout(authorization: str = Header(default="")) -> dict:
    token = authorization.removeprefix("Bearer ").strip()
    with database.transaction(conn()) as c:
        c.execute("DELETE FROM sessions WHERE token_hash = ?", (security.token_hash(token),))
    return {"ok": True}


def _user(user_id: int) -> dict:
    row = conn().execute("SELECT id, username, display_name FROM users WHERE id = ?", (user_id,)).fetchone()
    return dict(row)


@app.get("/api/v1/me")
def me(user: dict = Depends(current_user)) -> dict:
    societies = conn().execute(
        "SELECT s.id, s.name, m.role FROM memberships m JOIN societies s ON s.id = m.society_id "
        "WHERE m.user_id = ? ORDER BY s.name", (user["id"],)).fetchall()
    return {"user": user, "societies": [dict(s) for s in societies]}


# --- Societies -------------------------------------------------------------

class NewSociety(BaseModel):
    name: str = Field(min_length=2, max_length=40)


class JoinRequest(BaseModel):
    invite_code: str


class RoleChange(BaseModel):
    role: Literal["admin", "member"]


def membership(society_id: int, user: dict, admin: bool = False) -> dict:
    row = conn().execute("SELECT role FROM memberships WHERE society_id = ? AND user_id = ?",
                         (society_id, user["id"])).fetchone()
    if row is None:
        raise HTTPException(404, "You're not a member of that society.")
    if admin and row["role"] != "admin":
        raise HTTPException(403, "Only the society's admins can do that.")
    return dict(row)


@app.post("/api/v1/societies")
def create_society(body: NewSociety, user: dict = Depends(current_user)) -> dict:
    with database.transaction(conn()) as c:
        cur = c.execute("INSERT INTO societies (name, invite_code, created_by, created) VALUES (?, ?, ?, ?)",
                        (body.name.strip(), security.new_invite_code(), user["id"], now()))
        c.execute("INSERT INTO memberships VALUES (?, ?, 'admin', ?)", (cur.lastrowid, user["id"], now()))
    return society(cur.lastrowid, user)


@app.post("/api/v1/societies/join")
def join_society(body: JoinRequest, user: dict = Depends(current_user)) -> dict:
    row = conn().execute("SELECT id FROM societies WHERE invite_code = ?",
                         (body.invite_code.strip().upper(),)).fetchone()
    if row is None:
        raise HTTPException(404, "No society has that invite code.")
    with database.transaction(conn()) as c:
        c.execute("INSERT OR IGNORE INTO memberships VALUES (?, ?, 'member', ?)", (row["id"], user["id"], now()))
    return society(row["id"], user)


@app.get("/api/v1/societies/{society_id}")
def society(society_id: int, user: dict = Depends(current_user)) -> dict:
    mine = membership(society_id, user)
    s = conn().execute("SELECT id, name, invite_code, created FROM societies WHERE id = ?", (society_id,)).fetchone()
    members = []
    for m in conn().execute(
            "SELECT u.id, u.display_name, m.role, m.joined FROM memberships m JOIN users u ON u.id = m.user_id "
            "WHERE m.society_id = ? ORDER BY u.display_name", (society_id,)).fetchall():
        rounds = conn().execute("SELECT * FROM rounds WHERE society_id = ? AND user_id = ?",
                                (society_id, m["id"])).fetchall()
        summary = stats.summarise(rounds)
        members.append({**dict(m), "rounds": summary["rounds"], "scoring_average": summary["scoring_average"]})
    return {**dict(s), "role": mine["role"], "members": members, "tournaments": _tournaments(society_id, user)}


@app.post("/api/v1/societies/{society_id}/invite")
def new_invite(society_id: int, user: dict = Depends(current_user)) -> dict:
    membership(society_id, user, admin=True)
    code = security.new_invite_code()
    with database.transaction(conn()) as c:
        c.execute("UPDATE societies SET invite_code = ? WHERE id = ?", (code, society_id))
    return {"invite_code": code}


@app.put("/api/v1/societies/{society_id}/members/{member_id}")
def change_role(society_id: int, member_id: int, body: RoleChange, user: dict = Depends(current_user)) -> dict:
    membership(society_id, user, admin=True)
    if body.role == "member" and _admin_count(society_id) == 1 and _role(society_id, member_id) == "admin":
        raise HTTPException(409, "A society needs at least one admin.")
    with database.transaction(conn()) as c:
        cur = c.execute("UPDATE memberships SET role = ? WHERE society_id = ? AND user_id = ?",
                        (body.role, society_id, member_id))
    if cur.rowcount == 0:
        raise HTTPException(404, "That person isn't a member.")
    return {"ok": True}


@app.delete("/api/v1/societies/{society_id}/members/{member_id}")
def remove_member(society_id: int, member_id: int, user: dict = Depends(current_user)) -> dict:
    """Admins can remove anyone; members can remove themselves (leave)."""
    membership(society_id, user, admin=member_id != user["id"])
    if _role(society_id, member_id) == "admin" and _admin_count(society_id) == 1:
        others = conn().execute("SELECT COUNT(*) FROM memberships WHERE society_id = ?", (society_id,)).fetchone()[0]
        if others > 1:
            raise HTTPException(409, "Make someone else an admin before the last admin leaves.")
    with database.transaction(conn()) as c:
        c.execute("DELETE FROM memberships WHERE society_id = ? AND user_id = ?", (society_id, member_id))
    return {"ok": True}


def _role(society_id: int, user_id: int) -> Optional[str]:
    row = conn().execute("SELECT role FROM memberships WHERE society_id = ? AND user_id = ?",
                         (society_id, user_id)).fetchone()
    return row["role"] if row else None


def _admin_count(society_id: int) -> int:
    return conn().execute("SELECT COUNT(*) FROM memberships WHERE society_id = ? AND role = 'admin'",
                          (society_id,)).fetchone()[0]


# --- Tournaments -----------------------------------------------------------

class NewTournament(BaseModel):
    name: str = Field(min_length=2, max_length=50)
    course: dict
    course_code: str = Field(min_length=3, max_length=20000)
    holes: Literal[3, 9, 18]
    scoring: Literal["single", "best"]
    starts: date
    ends: date


def _status(t) -> str:
    if today() < t["starts"]:
        return "upcoming"
    if today() > t["ends"]:
        return "finished"
    return "open"


def _tournaments(society_id: int, user: dict) -> list[dict]:
    out = []
    for t in conn().execute("SELECT * FROM tournaments WHERE society_id = ? ORDER BY starts DESC, id DESC",
                            (society_id,)).fetchall():
        played = conn().execute("SELECT COUNT(*) FROM rounds WHERE tournament_id = ? AND user_id = ?",
                                (t["id"], user["id"])).fetchone()[0]
        entrants = conn().execute("SELECT COUNT(DISTINCT user_id) FROM rounds WHERE tournament_id = ?",
                                  (t["id"],)).fetchone()[0]
        out.append(_tournament_dict(t) | {"my_rounds": played, "entrants": entrants,
                                           "can_play": _status(t) == "open" and (t["scoring"] == "best" or played == 0)})
    return out


def _tournament_dict(t) -> dict:
    return {"id": t["id"], "name": t["name"], "course": json.loads(t["course_json"]),
            "course_code": t["course_code"], "holes": t["holes"], "scoring": t["scoring"],
            "starts": t["starts"], "ends": t["ends"], "status": _status(t)}


@app.post("/api/v1/societies/{society_id}/tournaments")
def create_tournament(society_id: int, body: NewTournament, user: dict = Depends(current_user)) -> dict:
    membership(society_id, user, admin=True)
    if body.ends < body.starts:
        raise HTTPException(422, "The tournament must end on or after its start date.")
    with database.transaction(conn()) as c:
        cur = c.execute(
            "INSERT INTO tournaments (society_id, name, course_json, course_code, holes, scoring, starts, ends, "
            "created_by, created) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (society_id, body.name.strip(), json.dumps(body.course), body.course_code, body.holes, body.scoring,
             body.starts.isoformat(), body.ends.isoformat(), user["id"], now()))
    return tournament(cur.lastrowid, user)


@app.get("/api/v1/tournaments/{tournament_id}")
def tournament(tournament_id: int, user: dict = Depends(current_user)) -> dict:
    t = conn().execute("SELECT * FROM tournaments WHERE id = ?", (tournament_id,)).fetchone()
    if t is None:
        raise HTTPException(404, "No such tournament.")
    membership(t["society_id"], user)
    entries: dict[int, dict] = {}
    for r in conn().execute(
            "SELECT r.id, r.user_id, r.total, r.par_total, r.played_at, u.display_name FROM rounds r "
            "JOIN users u ON u.id = r.user_id WHERE r.tournament_id = ? ORDER BY r.id", (tournament_id,)).fetchall():
        e = entries.get(r["user_id"])
        to_par = r["total"] - r["par_total"]
        if e is None:
            entries[r["user_id"]] = {"user_id": r["user_id"], "display_name": r["display_name"], "rounds": 1,
                                     "total": r["total"], "to_par": to_par, "round_id": r["id"]}
            continue
        e["rounds"] += 1
        # Best-of keeps the lowest round; ties keep the earlier one.
        if t["scoring"] == "best" and to_par < e["to_par"]:
            e.update(total=r["total"], to_par=to_par, round_id=r["id"])
    board = sorted(entries.values(), key=lambda e: (e["to_par"], e["round_id"]))
    position = 0
    for i, e in enumerate(board):
        if i == 0 or e["to_par"] != board[i - 1]["to_par"]:
            position = i + 1
        e["position"] = position
    mine = sum(1 for _ in conn().execute("SELECT 1 FROM rounds WHERE tournament_id = ? AND user_id = ?",
                                         (tournament_id, user["id"])))
    return _tournament_dict(t) | {"leaderboard": board, "my_rounds": mine,
                                  "can_play": _status(t) == "open" and (t["scoring"] == "best" or mine == 0)}


@app.delete("/api/v1/tournaments/{tournament_id}")
def delete_tournament(tournament_id: int, user: dict = Depends(current_user)) -> dict:
    t = conn().execute("SELECT society_id FROM tournaments WHERE id = ?", (tournament_id,)).fetchone()
    if t is None:
        raise HTTPException(404, "No such tournament.")
    membership(t["society_id"], user, admin=True)
    with database.transaction(conn()) as c:
        c.execute("DELETE FROM tournaments WHERE id = ?", (tournament_id,))
    return {"ok": True}


# --- Rounds ----------------------------------------------------------------

class NewRound(BaseModel):
    society_id: int
    tournament_id: Optional[int] = None
    course_name: str = Field(max_length=80)
    course_code: str = Field(max_length=20000)
    pars: list[int]
    strokes: list[int]
    putts: list[int]
    fairways: list[int]
    greens: list[bool]
    drives: list[float]

    @field_validator("pars")
    @classmethod
    def valid_pars(cls, v: list[int]) -> list[int]:
        if not 1 <= len(v) <= 18 or any(p not in (3, 4, 5) for p in v):
            raise ValueError("pars must be 3, 4 or 5, for 1-18 holes")
        return v


@app.post("/api/v1/rounds")
def submit_round(body: NewRound, user: dict = Depends(current_user)) -> dict:
    membership(body.society_id, user)
    n = len(body.pars)
    for name in ("strokes", "putts", "fairways", "greens", "drives"):
        if len(getattr(body, name)) != n:
            raise HTTPException(422, f"{name} must have one entry per hole.")
    if any(not 1 <= s <= 20 for s in body.strokes) or any(not 0 <= p <= s for p, s in zip(body.putts, body.strokes)):
        raise HTTPException(422, "Those scores don't add up.")
    if any(f not in (-1, 0, 1) for f in body.fairways) or any(not 0 <= d <= 600 for d in body.drives):
        raise HTTPException(422, "Invalid fairway or drive figures.")
    kind = "practice"
    if body.tournament_id is not None:
        t = conn().execute("SELECT * FROM tournaments WHERE id = ? AND society_id = ?",
                           (body.tournament_id, body.society_id)).fetchone()
        if t is None:
            raise HTTPException(404, "No such tournament in this society.")
        if _status(t) != "open":
            raise HTTPException(409, "That tournament isn't open for entries.")
        if n != t["holes"] or body.course_code != t["course_code"]:
            raise HTTPException(409, "That round wasn't played on the tournament course.")
        played = conn().execute("SELECT COUNT(*) FROM rounds WHERE tournament_id = ? AND user_id = ?",
                                (t["id"], user["id"])).fetchone()[0]
        if t["scoring"] == "single" and played:
            raise HTTPException(409, "You've already played your round in this tournament.")
        kind = "tournament"
    with database.transaction(conn()) as c:
        cur = c.execute(
            "INSERT INTO rounds (society_id, user_id, tournament_id, kind, course_name, course_code, holes, "
            "pars_json, strokes_json, putts_json, fairways_json, gir_json, drives_json, total, par_total, played_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (body.society_id, user["id"], body.tournament_id, kind, body.course_name, body.course_code, n,
             json.dumps(body.pars), json.dumps(body.strokes), json.dumps(body.putts), json.dumps(body.fairways),
             json.dumps(body.greens), json.dumps(body.drives), sum(body.strokes), sum(body.pars), now()))
    return {"id": cur.lastrowid, "kind": kind}


def _round_summary(r) -> dict:
    return {"id": r["id"], "user_id": r["user_id"], "display_name": r["display_name"], "kind": r["kind"],
            "tournament_id": r["tournament_id"], "tournament": r["tournament_name"], "course_name": r["course_name"],
            "holes": r["holes"], "total": r["total"], "par_total": r["par_total"], "played_at": r["played_at"]}


@app.get("/api/v1/societies/{society_id}/rounds")
def list_rounds(society_id: int, member: Optional[int] = None, kind: Optional[str] = None,
                limit: int = 50, user: dict = Depends(current_user)) -> dict:
    membership(society_id, user)
    sql = ("SELECT r.*, u.display_name, t.name AS tournament_name FROM rounds r JOIN users u ON u.id = r.user_id "
           "LEFT JOIN tournaments t ON t.id = r.tournament_id WHERE r.society_id = ?")
    args: list = [society_id]
    if member is not None:
        sql += " AND r.user_id = ?"
        args.append(member)
    if kind in ("practice", "tournament"):
        sql += " AND r.kind = ?"
        args.append(kind)
    sql += " ORDER BY r.id DESC LIMIT ?"
    args.append(max(1, min(limit, 200)))
    return {"rounds": [_round_summary(r) for r in conn().execute(sql, args).fetchall()]}


@app.get("/api/v1/rounds/{round_id}")
def get_round(round_id: int, user: dict = Depends(current_user)) -> dict:
    r = conn().execute(
        "SELECT r.*, u.display_name, t.name AS tournament_name FROM rounds r JOIN users u ON u.id = r.user_id "
        "LEFT JOIN tournaments t ON t.id = r.tournament_id WHERE r.id = ?", (round_id,)).fetchone()
    if r is None:
        raise HTTPException(404, "No such round.")
    membership(r["society_id"], user)
    return _round_summary(r) | {
        "course_code": r["course_code"], "pars": json.loads(r["pars_json"]), "strokes": json.loads(r["strokes_json"]),
        "putts": json.loads(r["putts_json"]), "fairways": json.loads(r["fairways_json"]),
        "greens": json.loads(r["gir_json"]), "drives": json.loads(r["drives_json"])}


@app.get("/api/v1/societies/{society_id}/members/{member_id}/stats")
def member_stats(society_id: int, member_id: int, user: dict = Depends(current_user)) -> dict:
    membership(society_id, user)
    if _role(society_id, member_id) is None:
        raise HTTPException(404, "That person isn't a member.")
    out = {}
    for kind in ("practice", "tournament"):
        rows = conn().execute("SELECT * FROM rounds WHERE society_id = ? AND user_id = ? AND kind = ?",
                              (society_id, member_id, kind)).fetchall()
        out[kind] = stats.summarise(rows)
    return {"member": _user(member_id) | {"role": _role(society_id, member_id)}, **out}
