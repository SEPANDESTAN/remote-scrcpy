#!/usr/bin/env python3
"""Black-box launcher tests with real OpenSSH and real Android Platform Tools.

Run: REAL_ADB=/path/to/adb python3 tests/test_launcher_integration.py -v

Requires Python 3, Bash, OpenSSH client/server, root for the isolated sshd, and
loopback socket permission. All SSH keys/configuration/state are temporary.
Devices and scrcpy are simulated; no existing credentials or phones are used.
"""

from __future__ import annotations

import contextlib
import json
import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

from native_adb_fixture import NativeADBServer


ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = Path(os.environ.get("REMOTE_SCRCPY_LAUNCHER", ROOT / "remote-scrcpy.sh"))
REAL_ADB = os.environ.get("REAL_ADB", shutil.which("adb") or "")


def write_executable(path, source):
    path.write_text(source)
    path.chmod(0o700)


def unused_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


class LauncherIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.geteuid() != 0:
            raise unittest.SkipTest("isolated sshd fixture requires container root")
        if not REAL_ADB or not Path(REAL_ADB).is_file():
            raise unittest.SkipTest("set REAL_ADB to a real Android Platform Tools adb")
        for binary in ("bash", "ssh", "ssh-keygen", "sshd"):
            if not shutil.which(binary):
                raise unittest.SkipTest(f"missing {binary}")
        if not LAUNCHER.is_file():
            raise unittest.SkipTest(f"launcher has not been assembled: {LAUNCHER}")
        cls.temp = tempfile.TemporaryDirectory(prefix="scrcpy-native-tests-")
        cls.work = Path(cls.temp.name)
        cls.events_path = cls.work / "events.jsonl"
        cls.adb_events = cls.work / "adb-events.jsonl"
        cls.ssh_events = cls.work / "ssh-events.jsonl"
        cls.fail_start_marker = cls.work / "fail-start"
        cls.tools_dir = cls.work / "tools with spaces"
        cls.tools_dir.mkdir()
        cls.tmp_dir = cls.work / "session-state"
        cls.tmp_dir.mkdir()
        cls.server = NativeADBServer()
        cls.server_thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.server_thread.start()
        cls.sshd = None
        cls.runtime_created = None
        cls.processes = []
        try:
            runtime = Path("/run/sshd")
            try:
                runtime.mkdir(mode=0o755)
                state = runtime.stat()
                cls.runtime_created = (state.st_dev, state.st_ino)
            except FileExistsError:
                if not runtime.is_dir():
                    raise RuntimeError("/run/sshd exists and is not a directory")
            cls.configure_tools()
            cls.configure_ssh()
        except BaseException:
            cls.tearDownClass()
            raise

    @classmethod
    def configure_tools(cls):
        real_ssh = shutil.which("ssh")
        ssh_wrapper = cls.tools_dir / "ssh"
        write_executable(ssh_wrapper, f'''#!{sys.executable}
import json, os, subprocess, sys
arguments = sys.argv[1:]
def record(phase, **fields):
    row = {{'phase': phase, 'pid': os.getpid(), 'args': arguments, **fields}}
    descriptor = os.open({str(cls.ssh_events)!r}, os.O_CREAT | os.O_WRONLY | os.O_APPEND, 0o600)
    try:
        os.write(descriptor, (json.dumps(row) + '\\n').encode())
    finally:
        os.close(descriptor)
record('call')
# Record whether a port was actually acquired. Everything else is a direct
# exec of real OpenSSH so authentication and master process behavior are intact.
if any(arguments[index:index + 2] == ['-O', 'forward'] for index in range(len(arguments))):
    result = subprocess.run([{real_ssh!r}, *arguments])
    record('forward_result', returncode=result.returncode)
    sys.exit(result.returncode if result.returncode >= 0 else 128 - result.returncode)
os.execv({real_ssh!r}, [{real_ssh!r}, *arguments])
''')
        cls.local_adb = cls.tools_dir / "local adb"
        cls.remote_adb = cls.tools_dir / "remote adb's tool"
        for role, path in (("local", cls.local_adb), ("remote", cls.remote_adb)):
            source = f'''#!{sys.executable}
import json, os, sys
from pathlib import Path
with open({str(cls.adb_events)!r}, 'a') as log:
    log.write(json.dumps({{'role': {role!r}, 'args': sys.argv[1:],
                          'endpoint': os.environ.get('ADB_SERVER_SOCKET')}}) + '\\n')
if {role!r} == 'remote' and 'start-server' in sys.argv and Path({str(cls.fail_start_marker)!r}).exists():
    print('simulated remote ADB startup failure', file=sys.stderr)
    sys.exit(19)
os.execv({REAL_ADB!r}, [{REAL_ADB!r}, *sys.argv[1:]])
'''
            write_executable(path, source)
        cls.scrcpy = cls.tools_dir / "scrcpy"
        write_executable(cls.scrcpy, "#!/bin/sh\nexec " + shlex.quote(sys.executable) +
                         " " + shlex.quote(str(Path(__file__).with_name("fake_scrcpy.py"))) + " \"$@\"\n")
        # Never pass the developer's launcher configuration to the launcher under
        # test: everything it needs is passed as an option or set explicitly below.
        cls.base_env = {name: value for name, value in os.environ.items()
                        if not name.startswith("REMOTE_SCRCPY_")}
        for name in ("ADB_SERVER_SOCKET", "ANDROID_SERIAL", "ADB", "REMOTE_ADB", "ADB_PORT",
                     "NO_COLOR"):
            cls.base_env.pop(name, None)
        cls.base_env.update(SCRCPY=str(cls.scrcpy), SCRCPY_TEST_EVENTS=str(cls.events_path),
                            TMPDIR=str(cls.tmp_dir), ADB_MDNS_AUTO_CONNECT="0")
        cls.base_env["PATH"] = str(cls.tools_dir) + os.pathsep + cls.base_env.get("PATH", "")

    @classmethod
    def configure_ssh(cls):
        client_key, host_key = cls.work / "client-key", cls.work / "host-key"
        for path in (client_key, host_key):
            subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(path)],
                           check=True, capture_output=True)
        authorized = cls.work / "authorized-keys"
        authorized.write_text(client_key.with_suffix(".pub").read_text())
        cls.ssh_port = unused_port()
        config = cls.work / "sshd-config"
        config.write_text("\n".join([
            f"Port {cls.ssh_port}", "ListenAddress 127.0.0.1", f"HostKey {host_key}",
            f"PidFile {cls.work / 'sshd.pid'}", f"AuthorizedKeysFile {authorized}",
            "StrictModes no", "PasswordAuthentication no", "KbdInteractiveAuthentication no",
            "UsePAM no", "PermitRootLogin prohibit-password", "PubkeyAuthentication yes",
            "AllowUsers root", "AllowTcpForwarding yes", "X11Forwarding no",
            "PrintMotd no", "LogLevel ERROR", "",
        ]))
        cls.client_config = cls.work / "ssh-config"
        cls.client_config.write_text("\n".join([
            "Host fixture alpha beta", "    HostName 127.0.0.1", "    User root",
            f"    Port {cls.ssh_port}", f"    IdentityFile {client_key}",
            "    IdentitiesOnly yes", "    BatchMode yes", "    StrictHostKeyChecking no",
            "    UserKnownHostsFile /dev/null", "    GlobalKnownHostsFile /dev/null",
            "    LogLevel ERROR", "Host *", "    ConnectTimeout 4", "",
        ]))
        cls.sshd_log = open(cls.work / "sshd.log", "w+")
        cls.sshd = subprocess.Popen([shutil.which("sshd"), "-D", "-e", "-f", str(config)],
                                   stdin=subprocess.DEVNULL, stdout=cls.sshd_log,
                                   stderr=cls.sshd_log, start_new_session=True)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if cls.sshd.poll() is not None:
                cls.sshd_log.seek(0)
                raise RuntimeError("isolated sshd failed: " + cls.sshd_log.read())
            try:
                with socket.create_connection(("127.0.0.1", cls.ssh_port), timeout=0.1):
                    break
            except OSError:
                time.sleep(0.03)
        result = subprocess.run(["ssh", "-F", str(cls.client_config), "fixture", "true"],
                                capture_output=True, text=True, timeout=8)
        if result.returncode:
            raise RuntimeError("isolated SSH authentication failed: " + result.stderr)

    @classmethod
    def tearDownClass(cls):
        for process in getattr(cls, "processes", []):
            if process.poll() is None:
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGTERM)
                with contextlib.suppress(subprocess.TimeoutExpired):
                    process.wait(timeout=2)
                if process.poll() is None:
                    with contextlib.suppress(ProcessLookupError):
                        os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=2)
        if getattr(cls, "sshd", None):
            with contextlib.suppress(ProcessLookupError):
                os.killpg(cls.sshd.pid, signal.SIGTERM)
            with contextlib.suppress(subprocess.TimeoutExpired):
                cls.sshd.wait(timeout=3)
        if getattr(cls, "server", None):
            cls.server.reset()
            cls.server.shutdown()
            cls.server.server_close()
        if getattr(cls, "sshd_log", None):
            cls.sshd_log.close()
        if getattr(cls, "runtime_created", None):
            # Remove only the empty directory this fixture created, never an
            # existing SSH runtime directory or one replaced during the run.
            with contextlib.suppress(OSError):
                runtime = Path("/run/sshd")
                state = runtime.stat()
                if (state.st_dev, state.st_ino) == cls.runtime_created:
                    runtime.rmdir()
        if getattr(cls, "temp", None):
            cls.temp.cleanup()

    def setUp(self):
        self.server.reset()
        self.events_path.write_text("")
        self.adb_events.write_text("")
        self.ssh_events.write_text("")
        self.fail_start_marker.unlink(missing_ok=True)
        self.env = dict(self.base_env)

    def command(self, positional=("fixture", "SERIAL_A"), options=(), scrcpy=()):
        command = ["bash", str(LAUNCHER), "--ssh-config", str(self.client_config),
                   "--adb", str(self.local_adb)]
        # Exercise the plain interface's actual default; no UI flag is needed.
        if "--remote-adb" not in options:
            command.extend(["--remote-adb", str(self.remote_adb)])
        if "--adb-port" not in options:
            command.extend(["--adb-port", str(self.server.server_address[1])])
        command.extend([*options, *positional])
        if scrcpy:
            command.extend(["--", *scrcpy])
        return command

    def run_cli(self, positional=("fixture", "SERIAL_A"), options=(), scrcpy=(), timeout=20):
        return subprocess.run(self.command(positional, options, scrcpy), input="", env=self.env,
                              capture_output=True, text=True, timeout=timeout)

    def start_cli(self, positional=("fixture", "SERIAL_A"), options=(), scrcpy=()):
        process = subprocess.Popen(self.command(positional, options, scrcpy), env=self.env,
                                   stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
        self.processes.append(process)
        return process

    def run_tty(self, positional, input_bytes, options=(), timeout=20):
        master, slave = pty.openpty()
        process = subprocess.Popen(self.command(positional, options), env=self.env,
                                   stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
        self.processes.append(process)
        os.close(slave)
        output = bytearray()
        try:
            os.write(master, input_bytes)
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], 0.05)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output.extend(chunk)
                if process.poll() is not None:
                    break
            process.wait(timeout=2)
            return subprocess.CompletedProcess(process.args, process.returncode,
                                               output.decode(errors="replace"), "")
        finally:
            os.close(master)

    def events(self, kind=None, adb=False):
        rows = [json.loads(line) for line in (self.adb_events if adb else self.events_path).read_text().splitlines()]
        return [row for row in rows if kind is None or row.get("kind") == kind]

    def wait_event(self, kind, count=1, timeout=12):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            rows = self.events(kind)
            if len(rows) >= count:
                return rows
            time.sleep(0.03)
        self.fail(f"No {kind!r} event: {self.events()}")

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assert_closed(self, require_forwards=True):
        ports = set()
        control_paths = set()
        successful_forward_count = 0
        for row in [json.loads(line) for line in self.ssh_events.read_text().splitlines()]:
            arguments = row["args"]
            for index, argument in enumerate(arguments):
                if argument == "-S" and index + 1 < len(arguments):
                    control_paths.add(Path(arguments[index + 1]))
                elif argument.startswith("-S") and len(argument) > 2:
                    control_paths.add(Path(argument[2:]))
            if row["phase"] != "forward_result" or row["returncode"]:
                continue
            for index, argument in enumerate(arguments):
                if argument == "-L" and index + 1 < len(arguments):
                    forwarding = arguments[index + 1]
                elif argument.startswith("-L") and len(argument) > 2:
                    forwarding = argument[2:]
                else:
                    continue
                # The launcher explicitly binds numeric IPv4 loopback. Obtain
                # the local port from the real SSH invocation, even when ADB
                # startup/version checks fail before any ordinary client runs.
                ports.add(int(forwarding.split(":")[1]))
                successful_forward_count += 1
        if require_forwards:
            self.assertGreater(successful_forward_count, 0,
                               "cleanup verification must observe an acquired SSH forward")
            self.assertTrue(control_paths, "cleanup verification must observe an SSH control path")
        for row in self.events():
            if row.get("adb_endpoint"):
                ports.add(int(row["adb_endpoint"].rsplit(":", 1)[1]))
            if row.get("local_video_port"):
                ports.add(row["local_video_port"])
        for row in self.events(adb=True):
            if row.get("role") == "local" and row.get("endpoint"):
                ports.add(int(row["endpoint"].rsplit(":", 1)[1]))
        ports.discard(self.server.server_address[1])
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            open_ports = []
            for port in ports:
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.05):
                        open_ports.append(port)
                except OSError:
                    pass
            remaining_paths = [str(path) for path in control_paths
                               if path.exists() or path.parent.exists()]
            if not open_ports and not remaining_paths:
                return
            time.sleep(0.03)
        self.fail(f"SSH resources leaked: listeners={open_ports}, control paths/directories={remaining_paths}")

    def test_explicit_device_runs_through_real_adb_and_ssh(self):
        result = self.run_cli()
        self.assert_success(result)
        self.assertEqual(self.events("scrcpy_connected")[0]["serial"], "SERIAL_A")
        self.assertTrue(self.server.media_connections)
        self.assertFalse(self.server.forwards)
        self.assert_closed()

    def test_two_sessions_use_independent_ports_and_devices(self):
        first = self.start_cli(scrcpy=("--fake-hold=1.0",))
        second = self.start_cli(("fixture", "SERIAL_B"), scrcpy=("--fake-hold=1.0",))
        self.wait_event("scrcpy_connected", 2)
        for process in (first, second):
            stdout, stderr = process.communicate(timeout=20)
            self.assertEqual(process.returncode, 0, stdout + stderr)
        rows = self.events("scrcpy_connected")
        self.assertEqual({row["serial"] for row in rows}, {"SERIAL_A", "SERIAL_B"})
        for field in ("remote_port", "local_video_port", "adb_endpoint"):
            self.assertEqual(len({row[field] for row in rows}), 2, field)
        self.assertFalse(self.server.forwards)
        self.assert_closed()

    def test_host_only_always_prompts_even_for_one_online_device(self):
        self.server.devices = [("SERIAL_A", "device", "Alpha_Phone")]
        result = self.run_tty(("fixture",), b"1\n")
        self.assert_success(result)
        self.assertIn("SERIAL_A", result.stdout)
        self.assertRegex(result.stdout.lower(), r"select|choose|device.*number")
        self.assert_closed()

    def test_host_and_device_menus_reject_bad_device_input(self):
        result = self.run_tty((), b"1\ninvalid\n9999999999999999999999999999\n0\n2\n")
        self.assert_success(result)
        self.assertEqual(self.events("scrcpy_started")[0]["serial"], "SERIAL_B")
        self.assertIn("fixture", result.stdout)
        self.assertIn("SERIAL_A", result.stdout)
        self.assert_closed()

    def test_host_flag_skips_host_menu_and_serial_flag_skips_device_menu(self):
        result = self.run_cli((), ("--host", "fixture", "--serial", "SERIAL_B"))
        self.assert_success(result)
        self.assertEqual(self.events("scrcpy_started")[0]["serial"], "SERIAL_B")
        self.assert_closed()

    def test_missing_arguments_without_tty_fail_without_starting_scrcpy(self):
        for positional in ((), ("fixture",)):
            with self.subTest(positional=positional):
                result = self.run_cli(positional, ("--non-interactive",))
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.events("scrcpy_started"))
        self.assert_closed(require_forwards=False)

    def test_terminal_eof_is_a_clean_cancellation(self):
        result = self.run_tty(("fixture",), b"\x04")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.events("scrcpy_started"))
        self.assertFalse(self.server.forwards)
        self.assert_closed()

    def test_lists_have_no_scrcpy_or_forwarding_side_effects(self):
        result = self.run_cli((), ("--list-hosts",))
        self.assert_success(result)
        self.assertIn("fixture", result.stdout)
        self.assertFalse(self.events(adb=True))
        result = self.run_cli(("fixture",), ("--list-devices",))
        self.assert_success(result)
        self.assertIn("SERIAL_A", result.stdout)
        self.assertIn("SERIAL_B", result.stdout)
        self.assertFalse(self.events("scrcpy_started"))
        self.assertFalse(self.server.forwards)
        self.assert_closed()

    def test_unavailable_devices_are_visible_and_not_selectable(self):
        self.server.devices = [("SERIAL_A", "offline", "Offline_Phone"),
                               ("SERIAL_B", "unauthorized", "Locked_Phone")]
        result = self.run_cli(("fixture",), ("--list-devices",))
        self.assert_success(result)
        self.assertIn("offline", result.stdout)
        self.assertIn("unauthorized", result.stdout)
        for serial in ("SERIAL_A", "SERIAL_B", "MISSING"):
            result = self.run_cli(("fixture", serial))
            self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.events("scrcpy_started"))
        self.assert_closed()

    def test_arguments_are_literal_and_numeric_serials_are_exact(self):
        sentinel = self.work / "SHOULD_NOT_EXIST"
        serial = "12345678901234567890"
        self.server.devices = [(serial, "device", "Numeric_Phone"),
                               ("12345678901234567891", "device", "Other_Phone")]
        title = f"literal $(touch {sentinel}); * $HOME 'quotes'"
        result = self.run_cli(("fixture", serial), scrcpy=("--window-title", title))
        self.assert_success(result)
        event = self.events("scrcpy_started")[0]
        self.assertEqual(event["serial"], serial)
        self.assertEqual(event["args"][event["args"].index("--window-title") + 1], title)
        self.assertFalse(sentinel.exists())
        self.assert_closed()

    def test_remote_adb_path_and_serial_shell_metacharacters_are_not_executed(self):
        sentinel = self.work / "SERIAL_MUST_NOT_EXECUTE"
        serial = f"phone_$(touch${{IFS}}{sentinel})"
        self.server.devices = [(serial, "device", "Literal_Serial")]
        result = self.run_cli(("fixture", serial))
        self.assert_success(result)
        self.assertEqual(self.events("scrcpy_started")[0]["serial"], serial)
        self.assertFalse(sentinel.exists())
        self.assert_closed()

    def test_scrcpy_failure_preserves_exit_status_and_cleans_reservation(self):
        result = self.run_cli(scrcpy=("--fake-exit-before-forward=17",))
        self.assertEqual(result.returncode, 17, result.stdout + result.stderr)
        self.assertFalse(self.server.forwards)
        self.assert_closed()

    def test_cleanup_does_not_delete_another_sessions_reassigned_mapping(self):
        result = self.run_cli(scrcpy=("--fake-reassign-before-exit=SERIAL_B",))
        self.assertEqual(result.returncode, 17, result.stdout + result.stderr)
        self.assertEqual(len(self.server.forwards), 1)
        mapping = next(iter(self.server.forwards.values()))
        self.assertEqual(mapping.serial, "SERIAL_B")
        self.assertEqual(mapping.target, "localabstract:another_session_owns_this")
        self.assert_closed()

    def test_terminal_sigint_keeps_transport_alive_for_child_cleanup(self):
        process = self.start_cli(scrcpy=("--fake-hold=60",))
        self.wait_event("scrcpy_connected")
        os.killpg(process.pid, signal.SIGINT)
        stdout, stderr = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 130, stdout + stderr)
        self.assertTrue(self.events("scrcpy_finished")[0]["adb_available"], stdout + stderr)
        self.assertFalse(self.server.forwards)
        self.assert_closed()

    def test_process_group_sigterm_cleans_unused_reservation(self):
        process = self.start_cli(scrcpy=("--fake-before-forward-wait=60",))
        self.wait_event("scrcpy_started")
        os.killpg(process.pid, signal.SIGTERM)
        stdout, stderr = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 143, stdout + stderr)
        self.assertFalse(self.server.forwards)
        self.assert_closed()

    def test_sigterm_sent_only_to_wrapper_cleans_its_child_and_reservation(self):
        process = self.start_cli(scrcpy=("--fake-before-forward-wait=60",))
        self.wait_event("scrcpy_started")
        process.send_signal(signal.SIGTERM)
        stdout, stderr = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 143, stdout + stderr)
        self.assertFalse(self.server.forwards)
        self.assert_closed()

    def test_protocol_mismatch_fails_before_real_adb_can_kill_daemon(self):
        self.server.protocol = 42
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertRegex((result.stdout + result.stderr).lower(), r"protocol|version")
        self.assertNotIn("host:kill", self.server.requests)
        self.assertNotIn("host:devices-l", self.server.requests)
        self.assertFalse(self.events("scrcpy_started"))
        self.assert_closed()

    def test_malformed_protocol_response_never_restarts_daemon(self):
        self.server.version_response = b"OKAY000400"
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse([row for row in self.events(adb=True) if "start-server" in row["args"]])
        self.assertNotIn("host:kill", self.server.requests)
        self.assertFalse(self.events("scrcpy_started"))
        self.assert_closed()

    def test_failed_remote_startup_cleans_transport(self):
        self.fail_start_marker.touch()
        port = unused_port()
        result = self.run_cli(options=("--adb-port", str(port)))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("simulated remote ADB startup failure", result.stdout + result.stderr)
        self.assertFalse(self.events("scrcpy_started"))
        self.assert_closed()

    def test_real_adb_daemon_can_be_started_through_the_launcher(self):
        port = unused_port()
        isolated_state = self.work / "real-adb-state"
        isolated_state.mkdir(exist_ok=True)
        wrapper = self.tools_dir / "real isolated remote adb"
        write_executable(wrapper, "#!/bin/sh\n" +
                         "export ANDROID_USER_HOME=" + shlex.quote(str(isolated_state)) + "\n" +
                         "if [ \"$1\" = start-server ]; then\n" +
                         "    exec " + shlex.quote(REAL_ADB) +
                         " --one-device SCRCPY_TEST_NO_PHYSICAL_DEVICE \"$@\"\nfi\n" +
                         "exec " + shlex.quote(REAL_ADB) + " \"$@\"\n")
        endpoint = f"tcp:127.0.0.1:{port}"
        direct_env = {**self.env, "ADB_SERVER_SOCKET": endpoint,
                      "ANDROID_USER_HOME": str(isolated_state)}
        try:
            result = self.run_cli(("fixture",),
                                  ("--adb-port", str(port), "--remote-adb", str(wrapper), "--list-devices"))
            self.assert_success(result)
            query = subprocess.run([REAL_ADB, "devices"], env=direct_env,
                                   text=True, capture_output=True, timeout=5)
            self.assertEqual(query.returncode, 0, result.stdout + result.stderr + query.stderr)
            self.assertIn("List of devices attached", query.stdout)
            self.assertNotIn("cannot start server on remote host", result.stderr)
            self.assertFalse(self.events("scrcpy_started"))
            self.assert_closed()
        finally:
            subprocess.run([REAL_ADB, "kill-server"], env=direct_env,
                           text=True, capture_output=True, timeout=5)

    def test_conflicting_arguments_and_managed_options_fail(self):
        for options, scrcpy in ((("--host", "elsewhere"), ()),
                               ((), ("--serial=SERIAL_B",)),
                               ((), ("--tunnel-port=12345",)),
                               ((), ("--kill-adb-on-close",))):
            with self.subTest(options=options, scrcpy=scrcpy):
                result = self.run_cli(options=options, scrcpy=scrcpy)
                self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.events("scrcpy_started"))


if __name__ == "__main__":
    unittest.main()
