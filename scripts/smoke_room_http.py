"""Live HTTP/CSRF/SSE check. Creates QA accounts in a disposable local DB only.

Usage: python scripts/smoke_room_http.py http://localhost:5173
The URL may point to Vite's proxy or directly to a local Django test server.
"""

import concurrent.futures
import http.cookiejar
import json
import secrets
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
from urllib.parse import urlsplit

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:5173").rstrip("/")
if urlsplit(BASE).hostname not in ["localhost", "127.0.0.1"]:
    raise SystemExit("Only a disposable local environment is allowed")


class Browser:
    def __init__(self):
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())
        )
        self.csrf = ""

    def call(self, path, body=None, method=None, key=None, expected=200):
        if body is not None and not self.csrf:
            self.csrf = self.call("/auth/csrf/")["csrfToken"]
        headers = {"Content-Type": "application/json", "Origin": BASE}
        if body is not None:
            headers.update(
                {"X-CSRFToken": self.csrf, "Idempotency-Key": key or str(uuid.uuid4())}
            )
        req = urllib.request.Request(
            BASE + "/api" + path,
            data=json.dumps(body).encode() if body is not None else None,
            method=method or ("GET" if body is None else "POST"),
            headers=headers,
        )
        try:
            response = self.opener.open(req, timeout=25)
        except urllib.error.HTTPError as exc:
            response = exc
        with response:
            data = json.load(response)
            assert response.code == expected, (path, response.code, data)
            return data.get("data")

    def register(self, name):
        self.email = f"room-qa-{secrets.token_hex(6)}@sessionlab.test"
        self.password = secrets.token_urlsafe(30)
        self.call(
            "/auth/register/",
            {"email": self.email, "password": self.password, "first_name": name},
        )
        self.csrf = ""


master, player, spectator, other_tab = Browser(), Browser(), Browser(), Browser()
master.register("Master QA")
player.register("Player QA")
spectator.register("Spectator QA")
campaign = master.call("/campaigns/", {"name": "Live room HTTP QA"}, expected=201)
cid, suffix = campaign["id"], f"?campaign={campaign['id']}"
for browser in [player, spectator]:
    browser.call("/campaigns/join/", {"code": campaign["invite_code"]})
char = player.call(
    "/characters/" + suffix, {"name": "Mira", "campaign": cid, "level": 5}
)
charpath = f"/characters/{char['id']}"
session = master.call(f"/campaigns/{cid}/sessions/", {"name": "Shared table"})
master.call(f"/sessions/{session['id']}/start/" + suffix, {})
sheet = player.call(charpath + "/sheet/" + suffix)
sheet = player.call(
    charpath + "/sheet/" + suffix,
    {
        "version": sheet["version"],
        "notes": "PRIVATE SHEET NOTE",
        "hp_current": 20,
        "hp_max": 20,
        "abilities": {"str": 10, "dex": 14, "con": 12, "int": 18, "wis": 10, "cha": 10},
        "slots": {str(i): {"max": 2 if i == 1 else 0, "used": 0} for i in range(1, 10)},
    },
    method="PATCH",
)
spectator.call(charpath + "/sheet/" + suffix, expected=403)
party = spectator.call("/room/" + suffix)
assert party["party"][0]["hp_current"] == 20 and "PRIVATE SHEET NOTE" not in json.dumps(
    party
)
assert master.call(charpath + "/sheet/" + suffix)["notes"] == "PRIVATE SHEET NOTE"

# The second account subscribes before the master changes the room.
ready = threading.Event()


def wait_for_revision():
    req = urllib.request.Request(
        BASE + f"/api/campaigns/{cid}/stream/?after={party['revision']}"
    )
    with player.opener.open(req, timeout=10) as stream:
        assert stream.headers["Content-Type"] == "text/event-stream"
        ready.set()
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            line = stream.readline().decode().strip()
            if line.startswith("data:"):
                return json.loads(line[5:])["revision"]
        raise AssertionError("No committed change notification received")


with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    received = pool.submit(wait_for_revision)
    assert ready.wait(5), "SSE stream did not open"
    master.call("/room/rolls/" + suffix, {"formula": "2d6+3", "visibility": "public"})
    assert received.result(timeout=10) > party["revision"]
assert player.call("/room/events/" + suffix)["count"] == 1

master.call("/room/rolls/" + suffix, {"formula": "1d20", "visibility": "dm"})
assert player.call("/room/events/" + suffix)["count"] == 1
assert master.call("/room/events/" + suffix)["count"] == 2

spell = player.call(
    charpath + "/abilities/" + suffix,
    {
        "kind": "spell",
        "name": "Three sparks",
        "level": 1,
        "ability": "int",
        "dice": "1d4+1",
        "roll_count": 3,
        "resolution": "automatic",
    },
)
other_tab.call("/auth/login/", {"email": player.email, "password": player.password})
other_tab.csrf = ""
# Bootstrap outside the race; both requests then use a valid authenticated CSRF token.
for browser in [player, other_tab]:
    browser.csrf = browser.call("/auth/csrf/")["csrfToken"]
key, barrier = str(uuid.uuid4()), threading.Barrier(2)


def cast(browser):
    barrier.wait(timeout=5)
    return browser.call(
        f"/abilities/{spell['id']}/use/" + suffix, {"slot_level": 1}, key=key
    )


with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    a, b = list(pool.map(cast, [player, other_tab]))
assert a == b and len(a["payload"]["parts"]) == 3
assert player.call(charpath + "/sheet/" + suffix)["slots"]["1"]["used"] == 1
assert player.call("/room/events/" + suffix)["count"] == 2

player.call("/room/rolls/" + suffix, {"kind": "initiative", "character": char["id"]})
tracker = master.call("/room/" + suffix)["initiative"]
tracker = master.call(
    "/room/initiative/" + suffix,
    {
        "version": tracker["version"],
        "action": "add",
        "name": "Hidden enemy",
        "initiative": 100,
        "hidden": True,
    },
)
master.call(
    "/room/initiative/" + suffix, {"version": tracker["version"], "action": "start"}
)
public = player.call("/room/" + suffix)
assert "Hidden enemy" not in json.dumps(public) and public["initiative"]["hidden_turn"]
player.call(
    "/room/initiative/" + suffix, {"version": 0, "action": "next"}, expected=403
)
player.call(charpath + "/resources/" + suffix, {"action": "damage", "amount": 3})
assert master.call("/room/" + suffix)["party"][0]["hp_current"] == 17
for browser in [master, player, spectator, other_tab]:
    browser.call("/auth/logout/", {})
print(
    "PASS: real HTTP sessions/CSRF; three accounts; SSE change received; private sheets/hidden rolls; concurrent spell retry debits one slot; shared HP/initiative; player permissions; logout."
)
