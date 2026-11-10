import concurrent.futures
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import threading
import urllib.request
import urllib.error
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "bridge"))
import nightshift as bridge
spec = importlib.util.spec_from_file_location("installer", REPO / "scripts/install.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = patch.object(bridge, "ROOT", Path(self.temp.name))
        self.root.start()

    def tearDown(self):
        self.root.stop()
        self.temp.cleanup()

    def event(self, name, sid="one", now=100, **extras):
        bridge.collect({"session_id": sid, "cwd": "/some/private/project", "hook_event_name": name,
                        "prompt": "SECRET", "tool_input": {"command": "SECRET"}, **extras}, now=now)

    def state(self, now=100):
        return bridge.sessions(now=now)[0]

    def test_lifecycle_and_privacy(self):
        self.event("SessionStart")
        self.assertEqual(self.state()["status"], "idle")
        self.event("UserPromptSubmit", now=101)
        self.assertEqual(self.state(101)["status"], "working")
        self.event("PermissionRequest", now=102, tool_name="Bash")
        self.assertEqual(self.state(102)["status"], "approval")
        self.event("PostToolUse", now=103, tool_name="Bash")
        self.assertEqual(self.state(103)["status"], "working")
        self.event("Stop", now=104)
        self.assertEqual(self.state(104)["detail"], "Yanıt tamamlandı")
        self.assertNotIn("SECRET", json.dumps(self.state(104)))
        self.assertEqual(self.state(104)["startedAt"], 100)
        self.event("SessionEnd", now=105)
        self.assertEqual(bridge.sessions(105), [])

    def test_stale_session_is_unknown_not_running(self):
        self.event("UserPromptSubmit")
        self.assertEqual(self.state(1001)["status"], "unknown")
        self.assertEqual(self.state(100 + 3 * 60 * 60)["status"], "unknown")
        self.assertEqual(bridge.sessions(100 + 3 * 60 * 60 + 1), [])

    def test_subagent_does_not_overwrite_root(self):
        self.event("UserPromptSubmit")
        self.event("Stop", agent_id="child")
        self.assertEqual(self.state()["status"], "working")

    def test_notification_and_failure(self):
        self.event("Notification", notification_type="permission_prompt")
        self.assertEqual(self.state()["status"], "approval")
        self.event("Notification", notification_type="auth_success")
        self.assertEqual(self.state()["status"], "approval")
        self.event("StopFailure")
        self.assertEqual(self.state()["status"], "error")

    def test_concurrent_sessions_and_atomic_same_session(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            list(pool.map(lambda i: self.event("PreToolUse", sid=str(i % 4), tool_name="Read"), range(100)))
        self.assertEqual(len(bridge.sessions(100)), 4)

    def test_hook_fails_open_and_quiet(self):
        result = subprocess.run([sys.executable, str(REPO / "bridge/nightshift.py"), "hook"],
                                input="not json", capture_output=True, text=True)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))

    def test_merge_is_idempotent_and_preserves_other_hooks(self):
        original = {"model": "example", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo mine"}]}]}}
        command = "python nightshift.py hook " + installer.MARKER
        merged = installer.merge_settings(original, command)
        self.assertEqual(installer.merge_settings(merged, command), merged)
        self.assertEqual(installer.merge_settings(merged), original)
        self.assertEqual(original["hooks"]["Stop"][0]["hooks"][0]["command"], "echo mine")

    def test_power_lease_expires_without_stop_callback(self):
        with patch.object(bridge.subprocess, "Popen") as popen, patch.object(bridge.time, "monotonic", return_value=100):
            popen.return_value.poll.return_value = None
            lease = bridge.WakeLease()
            lease.renew()
            self.assertEqual(lease.expires, 112)
            self.assertIn("30", popen.call_args.args[0])
        with patch.object(bridge.time, "monotonic", return_value=113):
            lease.tick()
            popen.return_value.terminate.assert_called_once()
            self.assertIsNone(lease.process)

    def test_power_assertion_replaced_before_timeout(self):
        with patch.object(bridge.subprocess, "Popen") as popen, patch.object(bridge.time, "monotonic", return_value=100):
            first = popen.return_value
            first.poll.return_value = None
            lease = bridge.WakeLease()
            lease.renew()
        with patch.object(bridge.subprocess, "Popen") as popen, patch.object(bridge.time, "monotonic", return_value=125):
            popen.return_value.poll.return_value = None
            lease.renew()
            popen.assert_called_once()
            first.terminate.assert_called_once()
            self.assertEqual(lease.created_at, 125)

    def test_options_persist_and_reject_invalid_values(self):
        options = {**bridge.DEFAULT_OPTIONS, "brightness": 0.25, "hideProjects": True, "showClock": False}
        bridge.save_preferences(options)
        self.assertEqual(bridge.preferences(), options)
        for invalid in ({**options, "brightness": float("nan")}, {**options, "keepAwake": "false"},
                        {**options, "brightness": 3}, {"brightness": 0.5}):
            with self.assertRaises(ValueError):
                bridge.save_preferences(invalid)
            self.assertEqual(bridge.preferences(), options)

    def test_disable_awake_closes_lease_and_blocks_other_views(self):
        server = bridge.ThreadingHTTPServer(("127.0.0.1", 0), bridge.Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        url = f"http://127.0.0.1:{server.server_port}"
        try:
            with patch.dict(bridge.LIFECYCLE, {"active": True, "updatedAt": bridge.time.monotonic()}), \
                    patch.object(bridge.LEASE, "renew") as renew, patch.object(bridge.LEASE, "close") as close:
                options = {**bridge.DEFAULT_OPTIONS, "keepAwake": False}
                request = urllib.request.Request(url + "/preferences", data=json.dumps(options).encode(),
                                                headers={"X-NightShift": "saver-v1"})
                with urllib.request.urlopen(request) as response:
                    self.assertFalse(json.load(response)["keepAwake"])
                close.assert_called_once()
                presence = urllib.request.Request(url + "/presence", data=b"", headers={"X-NightShift": "saver-v1"})
                with urllib.request.urlopen(presence):
                    pass
                renew.assert_not_called()
                with urllib.request.urlopen(url + "/state") as response:
                    self.assertEqual(json.load(response)["preferences"], options)
        finally:
            server.shutdown()
            server.server_close()

    def test_loopback_http_state_and_browser_protection(self):
        self.event("UserPromptSubmit", now=bridge.time.time())
        server = bridge.ThreadingHTTPServer(("127.0.0.1", 0), bridge.Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f"http://127.0.0.1:{server.server_port}"
        try:
            with urllib.request.urlopen(url + "/state") as response:
                self.assertEqual(json.load(response)["sessions"][0]["status"], "working")
            with patch.object(bridge.LEASE, "renew") as renew:
                with patch.dict(bridge.LIFECYCLE, {"active": False, "updatedAt": bridge.time.monotonic()}):
                    request = urllib.request.Request(url + "/presence", data=b"",
                                                    headers={"X-NightShift": "saver-v1"})
                    with urllib.request.urlopen(request):
                        pass
                    renew.assert_not_called()
                bridge.LIFECYCLE.update(active=True, updatedAt=bridge.time.monotonic())
                request = urllib.request.Request(url + "/presence", data=b"",
                                                headers={"X-NightShift": "saver-v1"})
                with urllib.request.urlopen(request) as response:
                    self.assertIn("awake", json.load(response))
                renew.assert_called_once()
                with patch.object(bridge.LEASE, "close") as close:
                    lifecycle = urllib.request.Request(url + "/lifecycle", data=b'{"active":false,"event":"didstop"}',
                                                       headers={"X-NightShift": "monitor-v1"})
                    with urllib.request.urlopen(lifecycle):
                        pass
                    close.assert_called_once()
                    self.assertFalse(bridge.screen_saver_active())
                request.add_header("Origin", "https://example.com")
                with self.assertRaises(urllib.error.HTTPError) as error:
                    urllib.request.urlopen(request)
                self.assertEqual(error.exception.code, 403)
                error.exception.close()
                renew.assert_called_once()
        finally:
            server.shutdown()
            server.server_close()


class MachineTests(unittest.TestCase):
    CONFIG = {"host": "work-mac", "name": "Makine"}

    def status(self, **peer):
        base = {"HostName": "Work Mac", "DNSName": "work-mac.tail.ts.net.", "Online": True, "Active": True,
                "CurAddr": "10.0.0.2:41641", "Relay": "fra"}
        return {"BackendState": "Running", "Peer": {"key": {**base, **peer}}}

    def test_online_regardless_of_route_or_traffic(self):
        online = {"name": "Makine", "online": True}
        self.assertEqual(bridge.machine_status(self.status(), self.CONFIG), online)
        self.assertEqual(bridge.machine_status(self.status(CurAddr=""), self.CONFIG), online)
        self.assertEqual(bridge.machine_status(self.status(Active=False), self.CONFIG), online)

    def test_offline_when_peer_down_missing_or_tailscale_stopped(self):
        offline = {"name": "Makine", "online": False}
        self.assertEqual(bridge.machine_status(self.status(Online=False), self.CONFIG), offline)
        self.assertEqual(bridge.machine_status({"BackendState": "Running", "Peer": {}}, self.CONFIG), offline)
        self.assertEqual(bridge.machine_status({**self.status(), "BackendState": "Stopped"}, self.CONFIG), offline)

    def test_config_is_optional_and_validated(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(bridge, "ROOT", Path(temp)):
            self.assertIsNone(bridge.machine_config())
            (Path(temp) / "machine.json").write_text('{"name": "Makine"}')
            self.assertIsNone(bridge.machine_config())
            (Path(temp) / "machine.json").write_text('{"host": "work-mac"}')
            self.assertEqual(bridge.machine_config(), {"host": "work-mac", "name": "work-mac"})

    def test_watch_hides_unknown_and_stale_state(self):
        watch = bridge.MachineWatch()
        result = subprocess.CompletedProcess([], 0, stdout=json.dumps(self.status()))
        with patch.object(bridge, "machine_config", return_value=self.CONFIG):
            with patch.object(bridge.subprocess, "run", return_value=result) as run:
                watch.refresh()
            self.assertTrue(watch.current()["online"])
            # launchd sets no TERM; without it the binary tries to open the GUI.
            self.assertIn("TERM", run.call_args.kwargs["env"])
            with patch.object(bridge.subprocess, "run", side_effect=OSError):
                watch.refresh()
            self.assertIsNone(watch.current())
            with patch.object(bridge.subprocess, "run", return_value=result):
                watch.refresh()
            watch.checked -= bridge.MachineWatch.STALE_AFTER + 1
            self.assertIsNone(watch.current())


class LaunchAgentTests(unittest.TestCase):
    def test_runtime_uses_system_python_that_survives_homebrew_upgrades(self):
        ok = subprocess.CompletedProcess([], 0)
        with patch.object(installer.subprocess, "run", return_value=ok):
            self.assertEqual(installer.runtime_path(), "/usr/bin/python3")

    def test_runtime_falls_back_when_system_python_is_unusable(self):
        # Without Command Line Tools /usr/bin/python3 is only an installer stub.
        for outcome in (subprocess.CompletedProcess([], 1), OSError()):
            with patch.object(installer.subprocess, "run", side_effect=[outcome]), \
                 patch.object(installer.sys, "executable", "/opt/homebrew/bin/python3.15"):
                self.assertEqual(installer.runtime_path(), "/opt/homebrew/bin/python3.15")

    def test_stop_waits_until_launchd_drops_the_job(self):
        calls = []
        lookups = iter([0, 0, 113])
        def run(command, **kwargs):
            calls.append(command[1])
            code = next(lookups) if command[1] == "print" else 0
            return subprocess.CompletedProcess(command, code)
        with patch.object(installer.subprocess, "run", run), patch.object(installer.time, "sleep"):
            installer.stop_bridge("gui/501", Path("bridge.plist"))
        self.assertEqual(calls, ["bootout", "print", "print", "print"])

    def test_start_retries_transient_bootstrap_failure(self):
        codes = iter([5, 5, 0])
        def run(command, **kwargs):
            return subprocess.CompletedProcess(command, next(codes), "", "Bootstrap failed: 5")
        with patch.object(installer.subprocess, "run", run), patch.object(installer.time, "sleep") as sleep:
            result = installer.start_bridge("gui/501", Path("bridge.plist"))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(sleep.call_count, 2)

    def test_start_reports_persistent_failure(self):
        def run(command, **kwargs):
            return subprocess.CompletedProcess(command, 5, "", "Bootstrap failed: 5")
        with patch.object(installer.subprocess, "run", run), patch.object(installer.time, "sleep"):
            result = installer.start_bridge("gui/501", Path("bridge.plist"), attempts=3)
        self.assertEqual(result.returncode, 5)


if __name__ == "__main__":
    unittest.main()
