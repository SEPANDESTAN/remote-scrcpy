#!/usr/bin/env python3
"""Hardware stand-in: uses real adb, then verifies bytes through the media tunnel.

The stand-in reserves/rebinds/removes forwarding exactly at the relevant scrcpy
lifecycle boundaries. It deliberately does not simulate video rendering.
"""

import json
import os
import signal
import socket
import subprocess
import sys
import time
import uuid


def emit(kind, **fields):
    row = {"kind": kind, "pid": os.getpid(), "time": time.time(), **fields}
    descriptor = os.open(os.environ["SCRCPY_TEST_EVENTS"],
                         os.O_CREAT | os.O_WRONLY | os.O_APPEND, 0o600)
    try:
        os.write(descriptor, (json.dumps(row) + "\n").encode())
    finally:
        os.close(descriptor)


def option(args, name, default=None):
    for index, value in enumerate(args):
        if value == name and index + 1 < len(args):
            return args[index + 1]
        if value.startswith(name + "="):
            return value.split("=", 1)[1]
    return default


def main(args):
    if args == ["--version"]:
        print("scrcpy 5.0.1-fixture")
        return 0
    serial = option(args, "--serial", option(args, "-s"))
    remote_port = int(option(args, "--port", "0"))
    local_port = int(option(args, "--tunnel-port", str(remote_port)))
    host = option(args, "--tunnel-host", "127.0.0.1")
    target = "localabstract:scrcpy_test_" + uuid.uuid4().hex
    fields = {"args": args, "serial": serial, "remote_port": remote_port,
              "local_video_port": local_port,
              "adb_endpoint": os.environ.get("ADB_SERVER_SOCKET")}
    emit("scrcpy_started", **fields)

    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)

    def adb(*command, selected=serial):
        return subprocess.run([os.environ["ADB"], "-s", selected, *command],
                              text=True, capture_output=True, timeout=8)

    time.sleep(float(option(args, "--fake-before-forward-wait", "0")))
    early = option(args, "--fake-exit-before-forward")
    if early is not None:
        return int(early)
    if "--force-adb-forward" not in args:
        raise RuntimeError("expected --force-adb-forward")
    result = adb("forward", f"tcp:{remote_port}", target)
    if result.returncode:
        raise RuntimeError(result.stderr)
    reassigned = option(args, "--fake-reassign-before-exit")
    if reassigned:
        result = adb("forward", f"tcp:{remote_port}",
                     "localabstract:another_session_owns_this", selected=reassigned)
        if result.returncode:
            raise RuntimeError(result.stderr)
        return 17
    try:
        with socket.create_connection((host, local_port), timeout=8) as connection:
            line = bytearray()
            while not line.endswith(b"\n"):
                raw = connection.recv(1)
                if not raw:
                    raise RuntimeError("media tunnel closed before greeting")
                line.extend(raw)
            greeting = json.loads(line)
            if greeting["serial"] != serial or greeting["target"] != target:
                raise RuntimeError(f"media tunnel reached the wrong device: {greeting}")
            marker = ("media-probe:" + serial).encode()
            connection.sendall(marker)
            received = bytearray()
            while len(received) < len(marker):
                raw = connection.recv(len(marker) - len(received))
                if not raw:
                    raise RuntimeError("media tunnel closed during probe")
                received.extend(raw)
            if received != marker:
                raise RuntimeError("media tunnel corrupted the probe")
            # Real scrcpy closes its ADB listener after its streams connect.
            result = adb("forward", "--remove", f"tcp:{remote_port}")
            if result.returncode:
                raise RuntimeError(result.stderr)
            emit("scrcpy_connected", **fields, greeting=greeting)
            print(f"fixture scrcpy connected: {serial}", flush=True)
            time.sleep(float(option(args, "--fake-hold", "0.05")))
        return int(option(args, "--fake-exit-code", "0"))
    finally:
        # Confirms SSH survives a terminal interrupt until scrcpy can finish.
        result = adb("forward", "--list")
        emit("scrcpy_finished", serial=serial, adb_available=result.returncode == 0)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as error:
        print(f"scrcpy test stand-in: {error}", file=sys.stderr)
        sys.exit(76)
