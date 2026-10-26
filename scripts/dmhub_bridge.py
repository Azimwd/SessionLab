"""Opt-in local SessionLab -> DMHub chat bridge. Python standard library only.

Requires a running DMHub desktop build with its local /mcp developer bridge.
See docs/DMHUB.md before enabling that bridge.
"""
import argparse
import json
import os
from pathlib import Path
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener


LOCAL_BRIDGE = "http://127.0.0.1:19876"


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None


OPENER = build_opener(NoRedirect)


def fetch_json(url, token=None, payload=None):
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    if payload is not None:
        headers["Content-Type"] = "application/json"
    req = Request(url, headers=headers,
                  data=json.dumps(payload).encode("utf-8") if payload is not None else None)
    with OPENER.open(req, timeout=8) as response:
        return json.load(response)


def chat_lua(message):
    """Byte literals prevent a name or spell title from injecting arbitrary Lua."""
    data = message.encode("utf-8")
    chunks = ["string.char(" + ",".join(map(str, data[i:i + 120])) + ")"
              for i in range(0, len(data), 120)]
    return "chat.Send(" + " .. ".join(chunks) + ")"


def save_cursor(path, cursor):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(str(cursor), encoding="ascii")
    temp.replace(path)


def main():
    parser = argparse.ArgumentParser(description="Send saved SessionLab rolls to DMHub's native chat")
    parser.add_argument("--url", default=os.environ.get("SESSIONLAB_URL", ""),
                        help="SessionLab public base URL, e.g. https://sessionlab.up.railway.app")
    parser.add_argument("--state", type=Path, default=Path.home() / ".sessionlab-dmhub-cursor")
    parser.add_argument("--from-beginning", action="store_true")
    parser.add_argument("--interval", type=float, default=3)
    args = parser.parse_args()
    token = os.environ.get("SESSIONLAB_DMHUB_TOKEN", "")
    url = args.url.rstrip("/")
    parsed = urlparse(url)
    if not token or not parsed.netloc or parsed.scheme not in ("http", "https"):
        parser.error("Set SESSIONLAB_DMHUB_TOKEN and --url (SESSIONLAB_URL)")
    if parsed.scheme != "https" and parsed.hostname not in ("localhost", "127.0.0.1"):
        parser.error("Remote SessionLab URLs must use HTTPS")
    if args.interval < 1:
        parser.error("--interval must be at least 1 second")
    try:
        with OPENER.open(LOCAL_BRIDGE + "/health", timeout=3) as response:
            if response.status != 200:
                raise RuntimeError("DMHub bridge returned a non-200 health response")
    except (HTTPError, URLError, OSError, RuntimeError) as exc:
        parser.error("DMHub local /health unavailable: " + str(exc))
    feed = url + "/api/integrations/dmhub/events/?cursor="
    if args.state.exists():
        cursor = int(args.state.read_text(encoding="ascii"))
    elif args.from_beginning:
        cursor = 0
    else:
        # Connect from now: never flood a new DMHub game with older campaigns' rolls.
        cursor = int(fetch_json(feed + "latest", token)["data"]["cursor"])
        save_cursor(args.state, cursor)
    print("SessionLab -> DMHub: started; event cursor", cursor, flush=True)
    while True:
        try:
            rows = fetch_json(feed + str(cursor), token)["data"]["events"]
            for row in rows:
                # Includes the stable event ID to identify a retry after a process crash.
                message = f"[SessionLab #{row['id']}] {row['text']}"
                response = fetch_json(LOCAL_BRIDGE + "/execute", payload={"code": chat_lua(message)})
                if isinstance(response, dict) and (response.get("error") or response.get("success") is False):
                    raise RuntimeError("DMHub rejected chat.Send: " + str(response)[:300])
                cursor = int(row["id"])
                save_cursor(args.state, cursor)
                print(message, flush=True)
        except (HTTPError, URLError, OSError, ValueError, KeyError, RuntimeError) as exc:
            print("Bridge retry:", exc, flush=True)
        time.sleep(args.interval)


if __name__ == "__main__":
    main()
