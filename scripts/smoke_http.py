"""Disposable local smoke test through the REAL reverse proxy. No browser auth bypass.
Run after migrations, seed and starting the local frontend/backend. Creates a random
local QA account/campaign; never use against a shared or production database.
"""

import http.cookiejar, json, secrets, sys, urllib.request, urllib.error, uuid
from urllib.parse import urlsplit

base = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:5173").rstrip("/")
if urlsplit(base).hostname not in ["localhost", "127.0.0.1"]:
    raise SystemExit("Only a disposable local environment is allowed")
jar = http.cookiejar.CookieJar()
session = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
csrf = ""


def api(path, body=None, key=None, method=None):
    global csrf
    if body is not None and not csrf:
        csrf = api("/auth/csrf/")["csrfToken"]
    headers = {"Content-Type": "application/json", "Origin": base}
    if body is not None:
        headers.update(
            {"X-CSRFToken": csrf, "Idempotency-Key": key or str(uuid.uuid4())}
        )
    req = urllib.request.Request(
        base + "/api" + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers=headers,
        method=method or ("POST" if body is not None else "GET"),
    )
    try:
        with session.open(req, timeout=25) as r:
            result = json.load(r)
            if result.get("error"):
                raise AssertionError(result["error"])
            return result["data"]
    except urllib.error.HTTPError as exc:
        raise AssertionError(f"{path}: HTTP {exc.code}: {exc.read().decode()[:500]}")


api(
    "/auth/register/",
    {
        "email": "qa-" + secrets.token_hex(6) + "@sessionlab.test",
        "password": secrets.token_urlsafe(30),
        "first_name": "QA",
    },
)
csrf = ""
assert api("/auth/me/")["first_name"] == "QA"
c = api("/campaigns/", {"name": "HTTP smoke QA"})["id"]
suffix = f"?campaign={c}"
char = api(
    "/characters/" + suffix,
    {"campaign": c, "name": "Mira", "character_class": "Bard", "level": 3},
)
s = api(f"/campaigns/{c}/sessions/", {"name": "Smoke session"})
api(f"/sessions/{s['id']}/start/" + suffix, {})
rollurl = f"/sessions/{s['id']}/effects/roll/" + suffix
key = str(uuid.uuid4())
payload = {"character": char["id"]}
roll = api(rollurl, payload, key)
assert api(rollurl, payload, key) == roll
assert api("/history/effects/" + suffix)["results"][0]["id"] == roll["id"]
quest = api(f"/sessions/{s['id']}/quests/roll/" + suffix, payload)
api(
    f"/quest-assignments/{quest['id']}/submit/" + suffix,
    {"evidence": "QA action completed"},
)
api(f"/dm/actions/quest/{quest['id']}/" + suffix, {"approve": True})
assert (
    float(api("/casino/wallet/" + suffix)["balance"])
    == 100 + quest["snapshot"]["reward"]
)
for game in [
    "roulette",
    "slots",
    "dice",
    "coin",
    "lucky-wheel",
    "blackjack",
    "higher-lower",
]:
    payload = (
        {
            "bets": [
                {"kind": "red", "amount": 1},
                {"kind": "number", "value": 0, "amount": 1},
            ]
        }
        if game == "roulette"
        else {"stake": 1, "choice": "heads" if game == "coin" else "seven"}
    )
    r = api(f"/casino/{game}/rounds/" + suffix, payload)
    if r["status"] == "active":
        action = (
            "stand"
            if game == "blackjack"
            else "lower"
            if r["result"]["current"]["rank"] == 14
            else "higher"
        )
        r = api(f"/casino/rounds/{r['id']}/actions/" + suffix, {"action": action})
    assert r["status"] == "completed" and "private_state" not in r
assert len(api("/casino/stats/" + suffix)) == 7
assert api("/casino/rounds/" + suffix + "&status=active")["count"] == 0
api(f"/sessions/{s['id']}/finish/" + suffix, {})
assert api("/history/effects/" + suffix)["results"][0]["status"] == "expired"
api("/auth/logout/", {})
print(
    "PASS: live HTTP endpoint → Django; CSRF/session registration, campaign, character, session, persistent effect/retry, verified quest/reward, all 7 games, stats, expiry, logout."
)
