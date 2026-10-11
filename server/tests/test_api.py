from datetime import date, timedelta

import pytest
from fastapi.testclient import TestClient

from simplegolf_server import app as server


@pytest.fixture()
def client(tmp_path):
    server.use_database(str(tmp_path / "test.db"))
    server._throttle = server.security.LoginThrottle()
    return TestClient(server.app)


def signup(client, username, name=None):
    r = client.post("/api/v1/auth/register",
                    json={"username": username, "password": "secret123", "display_name": name or username.title()})
    assert r.status_code == 200, r.text
    return {"Authorization": "Bearer " + r.json()["token"]}


def card(society_id, holes=3, tournament_id=None, code="SG-ABC", strokes=None):
    strokes = strokes or [4] * holes
    return {"society_id": society_id, "tournament_id": tournament_id, "course_name": "Test course",
            "course_code": code, "pars": [4] * holes, "strokes": strokes, "putts": [2] * holes,
            "fairways": [1] * holes, "greens": [True] * holes, "drives": [230.0] * holes}


def tournament_body(scoring="single", starts=None, ends=None, holes=3, code="SG-ABC"):
    starts = starts or date.today()
    ends = ends or starts + timedelta(days=6)
    return {"name": "Weekly medal", "course": {"name": "Test", "seed": 1, "edits": {}}, "course_code": code,
            "holes": holes, "scoring": scoring, "starts": starts.isoformat(), "ends": ends.isoformat()}


def test_health(client):
    assert client.get("/api/v1/health").json()["ok"]


def test_register_login_and_bad_password(client):
    signup(client, "mike")
    assert client.post("/api/v1/auth/register",
                       json={"username": "MIKE", "password": "secret123", "display_name": "x"}).status_code == 409
    assert client.post("/api/v1/auth/login", json={"username": "mike", "password": "wrongpass"}).status_code == 401
    ok = client.post("/api/v1/auth/login", json={"username": "Mike", "password": "secret123"})
    assert ok.status_code == 200 and ok.json()["user"]["display_name"] == "Mike"


def test_login_throttle(client):
    signup(client, "mike")
    for _ in range(8):
        client.post("/api/v1/auth/login", json={"username": "mike", "password": "wrongpass"})
    r = client.post("/api/v1/auth/login", json={"username": "mike", "password": "secret123"})
    assert r.status_code == 429


def test_requires_sign_in_and_logout(client):
    assert client.get("/api/v1/me").status_code == 401
    h = signup(client, "mike")
    assert client.get("/api/v1/me", headers=h).status_code == 200
    client.post("/api/v1/auth/logout", headers=h)
    assert client.get("/api/v1/me", headers=h).status_code == 401


def test_societies_invites_and_roles(client):
    mike, ana = signup(client, "mike"), signup(client, "ana")
    s = client.post("/api/v1/societies", json={"name": "Friday Four"}, headers=mike).json()
    assert s["role"] == "admin" and s["invite_code"].startswith("SG-")
    assert client.get(f"/api/v1/societies/{s['id']}", headers=ana).status_code == 404
    joined = client.post("/api/v1/societies/join", json={"invite_code": s["invite_code"].lower()}, headers=ana)
    assert joined.status_code == 200 and joined.json()["role"] == "member"
    assert [x["name"] for x in client.get("/api/v1/me", headers=ana).json()["societies"]] == ["Friday Four"]
    # Members can't do admin things.
    assert client.post(f"/api/v1/societies/{s['id']}/invite", headers=ana).status_code == 403
    assert client.post("/api/v1/societies/join", json={"invite_code": "SG-NOPE00"}, headers=ana).status_code == 404
    # The last admin can't step down or leave while others remain.
    mike_id = client.get("/api/v1/me", headers=mike).json()["user"]["id"]
    assert client.put(f"/api/v1/societies/{s['id']}/members/{mike_id}", json={"role": "member"},
                      headers=mike).status_code == 409
    assert client.delete(f"/api/v1/societies/{s['id']}/members/{mike_id}", headers=mike).status_code == 409
    new_code = client.post(f"/api/v1/societies/{s['id']}/invite", headers=mike).json()["invite_code"]
    assert new_code != s["invite_code"]


def test_practice_rounds_and_stats(client):
    mike = signup(client, "mike")
    s = client.post("/api/v1/societies", json={"name": "Club"}, headers=mike).json()
    r = client.post("/api/v1/rounds", json=card(s["id"], strokes=[3, 4, 6]), headers=mike)
    assert r.status_code == 200 and r.json()["kind"] == "practice"
    bad = card(s["id"])
    bad["putts"] = [5, 5, 5]
    assert client.post("/api/v1/rounds", json=bad, headers=mike).status_code == 422
    me = client.get("/api/v1/me", headers=mike).json()["user"]
    st = client.get(f"/api/v1/societies/{s['id']}/members/{me['id']}/stats", headers=mike).json()
    assert st["practice"]["rounds"] == 1 and st["practice"]["birdies"] == 1 and st["practice"]["doubles"] == 1
    assert st["tournament"]["rounds"] == 0
    full = client.get(f"/api/v1/rounds/{r.json()['id']}", headers=mike).json()
    assert full["strokes"] == [3, 4, 6] and full["total"] == 13


def test_single_round_tournament(client):
    mike, ana = signup(client, "mike"), signup(client, "ana")
    s = client.post("/api/v1/societies", json={"name": "Club"}, headers=mike).json()
    client.post("/api/v1/societies/join", json={"invite_code": s["invite_code"]}, headers=ana)
    assert client.post(f"/api/v1/societies/{s['id']}/tournaments", json=tournament_body(),
                       headers=ana).status_code == 403
    t = client.post(f"/api/v1/societies/{s['id']}/tournaments", json=tournament_body(), headers=mike).json()
    assert t["status"] == "open" and t["can_play"]
    assert client.post("/api/v1/rounds", json=card(s["id"], tournament_id=t["id"], strokes=[5, 4, 4]),
                       headers=mike).status_code == 200
    assert client.post("/api/v1/rounds", json=card(s["id"], tournament_id=t["id"]),
                       headers=mike).status_code == 409
    assert client.post("/api/v1/rounds", json=card(s["id"], tournament_id=t["id"], code="SG-OTHER"),
                       headers=ana).status_code == 409
    client.post("/api/v1/rounds", json=card(s["id"], tournament_id=t["id"], strokes=[3, 4, 4]), headers=ana)
    board = client.get(f"/api/v1/tournaments/{t['id']}", headers=mike).json()
    assert [e["display_name"] for e in board["leaderboard"]] == ["Ana", "Mike"]
    assert board["leaderboard"][0]["to_par"] == -1 and not board["can_play"]


def test_best_of_tournament_and_windows(client):
    mike = signup(client, "mike")
    s = client.post("/api/v1/societies", json={"name": "Club"}, headers=mike).json()
    t = client.post(f"/api/v1/societies/{s['id']}/tournaments", json=tournament_body("best"), headers=mike).json()
    for strokes in ([5, 5, 5], [4, 3, 4], [6, 6, 6]):
        assert client.post("/api/v1/rounds", json=card(s["id"], tournament_id=t["id"], strokes=strokes),
                           headers=mike).status_code == 200
    board = client.get(f"/api/v1/tournaments/{t['id']}", headers=mike).json()
    assert board["leaderboard"][0]["total"] == 11 and board["leaderboard"][0]["rounds"] == 3 and board["can_play"]
    past = tournament_body(starts=date.today() - timedelta(days=10), ends=date.today() - timedelta(days=3))
    old = client.post(f"/api/v1/societies/{s['id']}/tournaments", json=past, headers=mike).json()
    assert old["status"] == "finished"
    assert client.post("/api/v1/rounds", json=card(s["id"], tournament_id=old["id"]), headers=mike).status_code == 409
    future = tournament_body(starts=date.today() + timedelta(days=2))
    soon = client.post(f"/api/v1/societies/{s['id']}/tournaments", json=future, headers=mike).json()
    assert soon["status"] == "upcoming"
    rounds = client.get(f"/api/v1/societies/{s['id']}/rounds?kind=tournament", headers=mike).json()["rounds"]
    assert len(rounds) == 3 and rounds[0]["tournament"] == "Weekly medal"
