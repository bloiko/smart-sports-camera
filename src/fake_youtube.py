"""Fake Google sign-in + YouTube Live API for tests without Google and without the phone.

Stage 1 of docs/youtube-signin-and-ui-test-plan.md. Imitates the calls Follo makes:
- OAuth: GET /auth (redirects straight back with a code), POST /token (code or refresh grant);
- YouTube Data API v3: channels, liveStreams (list/insert), liveBroadcasts (list/insert/update/bind/transition).

Every request is recorded; GET /_log returns them as JSON, POST /_reset clears the state, POST /_fail?n=N makes the
next N YouTube calls fail with 503, POST /_revoke makes refresh tokens invalid (sign-in expired).
The ingest address handed out points at a local RTMP receiver (default rtmp://127.0.0.1:1935/live2).

Usage: python src/fake_youtube.py [--port 8765] [--ingest rtmp://127.0.0.1:1935/live2]
"""
import argparse
import secrets
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlencode, urlparse

LOCK = threading.Lock()
STATE = {}


def reset(ingest):
    STATE.clear()
    STATE.update(log=[], streams={}, broadcasts={}, tokens=set(), refresh=set(), n=0, ingest=ingest, fail=0, revoked=False)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, obj=None, headers=None):
        body = json.dumps(obj).encode() if obj is not None else b""
        self.send_response(code)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        if obj is not None:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def error(self, code, reason, message):
        self.send(code, {"error": {"code": code, "message": message, "errors": [{"reason": reason}]}})

    def handle_any(self, method):
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        form = {k: v[0] for k, v in parse_qs(raw.decode()).items()} if "urlencoded" in (self.headers.get("Content-Type") or "") else {}
        body = json.loads(raw) if raw and "json" in (self.headers.get("Content-Type") or "") else None
        with LOCK:
            if u.path == "/_log":
                return self.send(200, STATE["log"])
            if u.path == "/_reset":
                reset(STATE["ingest"])
                return self.send(200, {})
            if u.path == "/_fail":                 # the next N YouTube calls answer 503 (YouTube or the network is down)
                STATE["fail"] = int(q.get("n", "1"))
                return self.send(200, {})
            if u.path == "/_revoke":               # refresh tokens stop working (the 7-day Testing limit, or revoked access)
                STATE["revoked"] = True
                return self.send(200, {})
            STATE["log"].append({"method": method, "path": u.path, "query": q, "body": body, "form": {k: v for k, v in form.items() if k != "code_verifier"}})
            if u.path == "/auth":
                loc = q["redirect_uri"] + "?" + urlencode({"code": "fake-code", "state": q.get("state", "")})
                return self.send(302, None, {"Location": loc})
            if u.path == "/token":
                return self.token(form)
            if not u.path.startswith("/youtube/v3/"):
                return self.error(404, "notFound", u.path)
            if STATE["fail"] > 0:
                STATE["fail"] -= 1
                return self.error(503, "backendError", "Backend Error")
            if (self.headers.get("Authorization") or "").replace("Bearer ", "") not in STATE["tokens"]:
                return self.error(401, "authError", "Invalid Credentials")
            return self.api(method, u.path[len("/youtube/v3/"):], q, body or {})

    def token(self, form):
        STATE["n"] += 1
        access = "fake-access-%d" % STATE["n"]
        if form.get("grant_type") == "authorization_code":
            if form.get("code") != "fake-code" or not form.get("code_verifier"):
                return self.send(400, {"error": "invalid_grant"})
            refresh = "fake-refresh-%d" % STATE["n"]
            STATE["refresh"].add(refresh)
            STATE["tokens"].add(access)
            return self.send(200, {"access_token": access, "expires_in": 3599, "refresh_token": refresh, "token_type": "Bearer"})
        if form.get("grant_type") == "refresh_token":
            if STATE["revoked"]:
                return self.send(400, {"error": "invalid_grant", "error_description": "Token has been expired or revoked."})
            if form.get("refresh_token") not in STATE["refresh"] and not form.get("refresh_token", "").startswith("test-"):
                return self.send(400, {"error": "invalid_grant"})
            STATE["tokens"].add(access)
            return self.send(200, {"access_token": access, "expires_in": 3599, "token_type": "Bearer"})
        return self.send(400, {"error": "unsupported_grant_type"})

    def api(self, method, path, q, body):
        streams, broadcasts = STATE["streams"], STATE["broadcasts"]
        if path == "channels" and method == "GET":
            return self.send(200, {"items": [{"id": "UCfake", "snippet": {"title": "Test channel"}}]})
        if path == "videos" and method == "GET":
            b = broadcasts.get(q.get("id"))
            return self.send(200, {"items": [{"id": b["id"], "liveStreamingDetails": {"concurrentViewers": "3"}}] if b else []})
        if path == "liveStreams" and method == "GET":
            s = streams.get(q.get("id"))
            return self.send(200, {"items": [s] if s else []})
        if path == "liveStreams" and method == "POST":
            sid = "S%d" % (len(streams) + 1)
            streams[sid] = {"id": sid, "cdn": {"ingestionInfo": {"rtmpsIngestionAddress": STATE["ingest"], "ingestionAddress": STATE["ingest"], "streamName": "fake-key"}},
                            "contentDetails": body.get("contentDetails", {})}
            return self.send(200, streams[sid])
        if path == "liveBroadcasts" and method == "GET":
            b = broadcasts.get(q.get("id"))
            return self.send(200, {"items": [b] if b else []})
        if path == "liveBroadcasts" and method == "POST":
            bid = "B%d%s" % (len(broadcasts) + 1, secrets.token_hex(3))   # unique across server restarts, like real ids
            broadcasts[bid] = {"id": bid, "snippet": body.get("snippet", {}), "contentDetails": body.get("contentDetails", {}),
                               "status": {"privacyStatus": body["status"]["privacyStatus"], "lifeCycleStatus": "ready"}}
            return self.send(200, broadcasts[bid])
        if path == "liveBroadcasts" and method == "PUT":
            b = broadcasts.get(body.get("id"))
            if not b:
                return self.error(404, "liveBroadcastNotFound", "no such broadcast")
            b["status"]["privacyStatus"] = body["status"]["privacyStatus"]
            return self.send(200, b)
        if path == "liveBroadcasts/bind" and method == "POST":
            b = broadcasts.get(q.get("id"))
            if not b or q.get("streamId") not in streams:
                return self.error(404, "notFound", "broadcast or stream")
            b["streamId"] = q["streamId"]
            return self.send(200, b)
        if path == "liveBroadcasts/transition" and method == "POST":
            b = broadcasts.get(q.get("id"))
            if not b:
                return self.error(404, "liveBroadcastNotFound", "no such broadcast")
            b["status"]["lifeCycleStatus"] = q.get("broadcastStatus", "complete")
            return self.send(200, b)
        return self.error(404, "notFound", method + " " + path)

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

    def do_PUT(self):
        self.handle_any("PUT")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--ingest", default="rtmp://127.0.0.1:1935/live2")
    a = ap.parse_args()
    reset(a.ingest)
    print("fake YouTube on http://127.0.0.1:%d" % a.port, flush=True)
    ThreadingHTTPServer(("127.0.0.1", a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
