"""Small native ADB-protocol fixture for the real adb client.

Only the remote devices and their media sockets are simulated. Tests exercise
the installed ADB executable and actual SSH transport. This is not an Android
emulator and cannot validate screen capture, encoding, decoding, or input.
"""

import json
import socket
import socketserver
import struct
import threading


def recv_exact(connection, length):
    data = bytearray()
    while len(data) < length:
        chunk = connection.recv(length - len(data))
        if not chunk:
            raise EOFError
        data.extend(chunk)
    return bytes(data)


def payload(value):
    raw = value.encode()
    return f"{len(raw):04x}".encode() + raw


class MediaForward:
    def __init__(self, owner, serial, target, port=0):
        self.owner, self.serial, self.target = owner, serial, target
        self.listener = socket.socket()
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(("127.0.0.1", port))
        self.listener.listen(8)
        self.listener.settimeout(0.1)
        self.port = self.listener.getsockname()[1]
        self.closed = threading.Event()
        self.thread = threading.Thread(target=self.accept, daemon=True)
        self.thread.start()

    def accept(self):
        while not self.closed.is_set():
            try:
                connection, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                return
            threading.Thread(target=self.echo, args=(connection,), daemon=True).start()

    def echo(self, connection):
        greeting = {"serial": self.serial, "target": self.target, "port": self.port}
        with self.owner.lock:
            self.owner.media_connections.append(greeting)
        with connection:
            try:
                connection.sendall((json.dumps(greeting) + "\n").encode())
                while True:
                    raw = connection.recv(65536)
                    if not raw:
                        return
                    connection.sendall(raw)
            except OSError:
                return

    def close(self):
        self.closed.set()
        self.listener.close()
        self.thread.join(timeout=1)


class NativeADBServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self):
        self.lock = threading.RLock()
        self.protocol = 41
        self.version_response = None
        self.devices = []
        self.forwards = {}
        self.requests = []
        self.media_connections = []
        super().__init__(("127.0.0.1", 0), NativeADBHandler)
        self.reset()

    def reset(self):
        with self.lock:
            for forwarding in self.forwards.values():
                forwarding.close()
            self.forwards.clear()
            self.requests.clear()
            self.media_connections.clear()
            self.protocol = 41
            self.version_response = None
            self.devices = [("SERIAL_A", "device", "Alpha_Phone"),
                            ("SERIAL_B", "device", "Beta_Phone")]

    def selected(self, serial):
        matches = [row for row in self.devices if row[0] == serial]
        if not matches:
            raise ValueError(f"device '{serial}' not found")
        if matches[0][1] != "device":
            raise ValueError(f"device {matches[0][1]}")
        return serial

    def command(self, command, serial):
        with self.lock:
            self.requests.append(command)
            if command == "host:version":
                return (self.version_response if self.version_response is not None
                        else b"OKAY" + payload(f"{self.protocol:04x}")), serial, False
            if command == "host:kill":
                return b"FAIL" + payload("TEST FAILURE: refusing daemon termination"), serial, False
            if command == "host:devices-l" or command == "host:devices":
                rows = [f"{s}\t{state} product:test model:{model} device:test transport_id:{i}"
                        for i, (s, state, model) in enumerate(self.devices, 1)]
                return b"OKAY" + payload("\n".join(rows) + ("\n" if rows else "")), serial, False
            if command.startswith("host-serial:") and command.endswith(":features"):
                self.selected(command[len("host-serial:"):-len(":features")])
                return b"OKAY" + payload(""), serial, False
            if command.startswith("host:tport:serial:"):
                serial = self.selected(command[len("host:tport:serial:"):])
                return b"OKAY" + struct.pack("<Q", 1), serial, True
            if command == "host:list-forward":
                rows = [f"{f.serial} tcp:{p} {f.target}" for p, f in sorted(self.forwards.items())]
                return b"OKAY" + payload("\n".join(rows) + ("\n" if rows else "")), serial, False
            if command.startswith("host:forward:"):
                self.selected(serial)
                value = command[len("host:forward:"):]
                norebind = value.startswith("norebind:")
                if norebind:
                    value = value[len("norebind:"):]
                source, target = value.split(";", 1)
                port = int(source.removeprefix("tcp:"))
                if port in self.forwards:
                    if norebind:
                        raise ValueError("cannot rebind existing socket")
                    self.forwards[port].serial, self.forwards[port].target = serial, target
                else:
                    forwarding = MediaForward(self, serial, target, port)
                    port = forwarding.port
                    self.forwards[port] = forwarding
                return b"OKAYOKAY" + payload(str(port)), serial, False
            if command.startswith("host:killforward:tcp:"):
                port = int(command.removeprefix("host:killforward:tcp:"))
                forwarding = self.forwards.pop(port, None)
                if forwarding:
                    forwarding.close()
                return b"OKAYOKAY", serial, False
            raise ValueError(f"unsupported test ADB service: {command}")


class NativeADBHandler(socketserver.BaseRequestHandler):
    def handle(self):
        serial = None
        self.request.settimeout(5)
        try:
            while True:
                size = int(recv_exact(self.request, 4), 16)
                command = recv_exact(self.request, size).decode()
                try:
                    response, serial, again = self.server.command(command, serial)
                except (ValueError, OSError) as error:
                    response, again = b"FAIL" + payload(str(error)), False
                self.request.sendall(response)
                if not again:
                    return
        except (EOFError, OSError, ValueError):
            return
