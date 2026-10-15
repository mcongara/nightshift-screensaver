#!/usr/bin/env python3
"""Local Claude hook collector and loopback screensaver bridge. No third-party packages."""
import argparse
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 47831
EVENTS = ("SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
          "PostToolUse", "PostToolUseFailure", "Notification", "Stop", "StopFailure", "SessionEnd")
ROOT = Path(os.environ.get("NIGHTSHIFT_DATA_DIR", str(Path.home() / "Library/Application Support/NightShift")))
DEFAULT_OPTIONS = {"brightness": 0.55, "showClock": True, "hideProjects": False, "keepAwake": True}


def validate_options(data):
    if not isinstance(data, dict) or set(data) != set(DEFAULT_OPTIONS):
        raise ValueError("invalid options")
    if any(type(data[key]) is not bool for key in ("showClock", "hideProjects", "keepAwake")):
        raise ValueError("invalid toggle")
    brightness = data["brightness"]
    if type(brightness) not in (float, int) or not math.isfinite(brightness) or not 0.15 <= brightness <= 1:
        raise ValueError("invalid brightness")
    return dict(data)


def preferences():
    try:
        return validate_options(json.loads((ROOT / "preferences.json").read_text()))
    except (OSError, ValueError, TypeError):
        return dict(DEFAULT_OPTIONS)


def save_preferences(data):
    options = validate_options(data)
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(dir=ROOT, prefix=".preferences-")
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(options, output)
        os.replace(temporary, ROOT / "preferences.json")
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    if not options["keepAwake"]:
        LEASE.close()
    return options


def clean(value, limit=100):
    return " ".join(str(value).split())[:limit]


def collect(payload, now=None):
    """Only store project basename + tool type, never prompts, commands or responses."""
    event = payload.get("hook_event_name")
    sid = payload.get("session_id")
    if event not in EVENTS or not isinstance(sid, str) or not sid or len(sid) > 256:
        return
    # Tool hooks also fire inside subagents; don't let their stop/permission state
    # overwrite the main conversation's state in this first version.
    if payload.get("agent_id"):
        return
    now = time.time() if now is None else now
    directory = ROOT / "sessions"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    key = hashlib.sha256(sid.encode()).hexdigest()
    path = directory / (key + ".json")
    with (directory / (key + ".lock")).open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            previous = json.loads(path.read_text())
        except (OSError, ValueError):
            previous = {}
        if event == "SessionEnd":
            path.unlink(missing_ok=True)
            return
        state = {
            "id": key[:12],
            "project": clean(Path(payload.get("cwd") or "Claude Code").name),
            "startedAt": previous.get("startedAt", now),
            "updatedAt": now,
            "status": previous.get("status", "idle"),
            "detail": previous.get("detail", "Session açıldı"),
        }
        tool = clean(payload.get("tool_name") or "Araç", 48)
        if event == "SessionStart":
            state.update(status="idle", detail="Session hazır")
        elif event == "UserPromptSubmit":
            state.update(status="working", detail="Düşünüyor", turnStartedAt=now)
        elif event == "PreToolUse":
            state.update(status="working", detail=tool + " çalışıyor")
        elif event == "PermissionRequest":
            state.update(status="approval", detail=tool + " için izin bekliyor")
        elif event == "PostToolUse":
            state.update(status="working", detail=tool + " tamamlandı")
        elif event == "PostToolUseFailure":
            state.update(status="working", detail=tool + " hata verdi · devam ediyor")
        elif event == "Stop":
            state.update(status="idle", detail="Yanıt tamamlandı")
        elif event == "StopFailure":
            state.update(status="error", detail="Yanıt hata ile durdu")
        elif event == "Notification":
            kind = payload.get("notification_type")
            if kind == "permission_prompt":
                state.update(status="approval", detail="İzin bekliyor")
            elif kind in ("idle_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input"):
                state.update(status="input", detail="Yanıtını bekliyor")
            else:
                return
        if "turnStartedAt" not in state and "turnStartedAt" in previous:
            state["turnStartedAt"] = previous["turnStartedAt"]
        fd, temporary = tempfile.mkstemp(dir=directory, prefix=".state-")
        try:
            with os.fdopen(fd, "w") as output:
                json.dump(state, output, ensure_ascii=False)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


def sessions(now=None):
    now = time.time() if now is None else now
    result = []
    for path in (ROOT / "sessions").glob("*.json"):
        try:
            state = json.loads(path.read_text())
            age = now - state["updatedAt"]
            if age > 86400:
                continue
            # Hooks are events, not heartbeats. A crashed terminal may never send
            # SessionEnd; explicitly show uncertainty rather than invent liveness.
            if age > 900:
                state.update(status="unknown", detail="Yeni sinyal yok · son durum bilinmiyor")
            result.append(state)
        except (OSError, ValueError, KeyError, TypeError):
            continue
    return sorted(result, key=lambda s: s["updatedAt"], reverse=True)[:30]


class WakeLease:
    """A short renewable lease survives missing ScreenSaverView.stopAnimation calls."""
    def __init__(self):
        self.expires = 0
        self.process = None
        self.created_at = 0
        self.lock = threading.Lock()

    def renew(self):
        with self.lock:
            self.expires = time.monotonic() + 12
            if self.process is None or self.process.poll() is not None or time.monotonic() - self.created_at >= 24:
                # A hard timeout also protects against a bridge crash. Normal
                # operation replaces the assertion before it expires.
                previous = self.process
                self.process = subprocess.Popen(["/usr/bin/caffeinate", "-di", "-t", "30"],
                                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self.created_at = time.monotonic()
                if previous and previous.poll() is None:
                    previous.terminate()

    def tick(self):
        with self.lock:
            if self.process and time.monotonic() > self.expires:
                self.process.terminate()
                self.process = None

    def close(self):
        with self.lock:
            self.expires = 0
            if self.process:
                self.process.terminate()
                self.process = None


LEASE = WakeLease()
LIFECYCLE = {"active": False, "updatedAt": 0, "event": "waitingForMonitor"}
DIAGNOSTICS = {"starts": 0, "wakeRenewals": 0, "lastWakeAt": None, "lastStopAt": None}


def screen_saver_active():
    return LIFECYCLE["active"] and time.monotonic() - LIFECYCLE["updatedAt"] < 10


def health():
    with LEASE.lock:
        awake = LEASE.process is not None and LEASE.process.poll() is None
    return {"awake": awake, "screensaverActive": screen_saver_active(), "lastLifecycleEvent": LIFECYCLE["event"], **DIAGNOSTICS}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def send(self, code, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/preferences":
            self.send(200, preferences())
            return
        if self.path == "/health":
            self.send(200, health())
            return
        if self.path != "/state":
            self.send(404, {"error": "not found"})
            return
        self.send(200, {"sessions": sessions(), "version": 1, "awake": health()["awake"], "preferences": preferences()})

    def do_POST(self):
        if self.path == "/preferences" and not self.headers.get("Origin") and self.headers.get("X-NightShift") == "saver-v1":
            try:
                count = int(self.headers.get("Content-Length", "0"))
                if not 0 < count <= 1024:
                    raise ValueError()
                self.send(200, save_preferences(json.loads(self.rfile.read(count))))
            except (ValueError, TypeError):
                self.send(400, {"error": "invalid preferences"})
            except OSError:
                self.send(500, {"error": "could not save preferences"})
            return
        # Only our native saver sends this custom header. No CORS support; reject
        # browser origins so a web page cannot silently hold the Mac awake.
        if self.path == "/lifecycle" and not self.headers.get("Origin") and self.headers.get("X-NightShift") == "monitor-v1":
            try:
                count = int(self.headers.get("Content-Length", "0"))
                if count <= 0 or count > 1024:
                    raise ValueError()
                data = json.loads(self.rfile.read(count))
                if not isinstance(data.get("active"), bool):
                    raise ValueError()
                if data["active"] and not LIFECYCLE["active"]:
                    DIAGNOSTICS["starts"] += 1
                if not data["active"] and LIFECYCLE["active"]:
                    DIAGNOSTICS["lastStopAt"] = time.time()
                LIFECYCLE.update(active=data["active"], updatedAt=time.monotonic(), event=clean(data.get("event"), 80))
                if not data["active"]:
                    LEASE.close()
                self.send(200, {"ok": True})
            except (ValueError, TypeError):
                self.send(400, {"error": "bad lifecycle"})
            return
        if self.path != "/presence" or self.headers.get("Origin") or self.headers.get("X-NightShift") != "saver-v1":
            self.send(403, {"error": "forbidden"})
            return
        if screen_saver_active() and preferences()["keepAwake"]:
            LEASE.renew()
            DIAGNOSTICS["wakeRenewals"] += 1
            DIAGNOSTICS["lastWakeAt"] = time.time()
        self.send(200, {"awake": health()["awake"]})


def serve(port):
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.daemon_threads = True
    monitor = None
    monitor_path = Path(__file__).resolve().with_name("NightShiftMonitor")
    if monitor_path.exists():
        monitor = subprocess.Popen([str(monitor_path)])
    def maintain():
        while True:
            time.sleep(1)
            LEASE.tick()
            if not screen_saver_active():
                LEASE.close()
    threading.Thread(target=maintain, daemon=True).start()
    try:
        server.serve_forever()
    finally:
        LEASE.close()
        if monitor:
            monitor.terminate()
        server.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("hook", "serve"))
    parser.add_argument("--port", type=int, default=PORT)
    args = parser.parse_args()
    if args.mode == "serve":
        serve(args.port)
    else:
        # Hooks must always be quiet and fail open. Any collector error must not
        # reject a prompt, authorize a tool or interfere with a user's workflow.
        try:
            data = sys.stdin.buffer.read(1_048_577)
            if len(data) <= 1_048_576:
                collect(json.loads(data))
        except Exception:
            pass
