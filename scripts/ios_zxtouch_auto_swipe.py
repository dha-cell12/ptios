#!/usr/bin/env python3
import argparse
import json
import socket
import struct
import time
from typing import Optional


MAGIC = b"ZXTP"
VERSION = 1
HEADER = struct.Struct(">4sBBI")


class ZXTouchSocket:
    def __init__(self, host: str, port: int, protocol: str = "auto", timeout: float = 3.0):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.protocol = protocol
        self.sock: Optional[socket.socket] = None
        self.next_id = 1
        self.touch_seq = 1

    def connect(self) -> None:
        if self.protocol in ("auto", "v1"):
            try:
                self.sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
                self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                self.sock.settimeout(0.7)
                self.protocol = "v1"
                self._send_v1(45, [])
                self._recv_v1()
                self.sock.settimeout(self.timeout)
                print("connected using ZXTP v1", flush=True)
                return
            except Exception as exc:
                print(f"v1 probe failed: {exc}", flush=True)
                try:
                    if self.sock:
                        self.sock.close()
                except Exception:
                    pass
                if self.protocol == "v1":
                    raise

        self.sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.sock.settimeout(self.timeout)
        self.protocol = "v0"
        print("connected using legacy v0", flush=True)

    def close(self) -> None:
        if self.sock:
            try:
                self.sock.close()
            except Exception:
                pass
            self.sock = None

    def send_touch(self, event_type: int, finger: int, x: float, y: float, ack: bool = False, log_ack: bool = False) -> None:
        payload = touch_payload(event_type, finger, x, y)
        if ack:
            seq = self.touch_seq
            self.touch_seq += 1
            started = time.perf_counter()
            if self.protocol == "v1":
                self._send_v1(61, [str(seq), payload])
                resp = self._recv_v1()
                ok = bool(resp.get("ok"))
                data = resp.get("data") or []
                if not ok:
                    raise RuntimeError(f"touch ack failed seq={seq}: {resp.get('error')}")
            else:
                self._send_v0(f"61{seq};;{payload}\r\n".encode("ascii"))
                line = self._recv_v0_line().decode("utf-8", errors="replace").strip()
                parts = line.split(";;")
                if len(parts) < 2 or parts[0] != "0" or parts[1] != str(seq):
                    raise RuntimeError(f"bad touch ack seq={seq}: {line}")
                data = parts[1:]
            elapsed_ms = (time.perf_counter() - started) * 1000.0
            if log_ack:
                dispatch_us = data[1] if len(data) > 1 else "?"
                print(f"ack event={event_type} seq={seq} latency_ms={elapsed_ms:.2f} dispatch_us={dispatch_us}", flush=True)
            return

        if self.protocol == "v1":
            self._send_v1(10, [payload])
        else:
            self._send_v0(f"10{payload}\r\n".encode("ascii"))

    def reconnect(self) -> None:
        protocol = self.protocol
        self.close()
        self.protocol = protocol
        self.connect()

    def reconnect_with_backoff(self, attempts: int, base_delay: float = 0.5, max_delay: float = 5.0) -> bool:
        for attempt in range(1, attempts + 1):
            try:
                self.reconnect()
                return True
            except OSError as exc:
                delay = min(max_delay, base_delay * attempt)
                print(f"reconnect attempt {attempt}/{attempts} failed: {exc}; wait {delay:.1f}s", flush=True)
                time.sleep(delay)
        return False

    def get_screen_size(self) -> tuple[float, float] | None:
        try:
            if self.protocol == "v1":
                self._send_v1(25, ["1"])
                resp = self._recv_v1()
                data = resp.get("data")
                if isinstance(data, list) and len(data) >= 2:
                    return float(data[0]), float(data[1])
                return None

            self._send_v0(b"25;;1\r\n")
            line = self._recv_v0_line().decode("utf-8", errors="replace").strip()
            parts = line.split(";;")
            if len(parts) >= 3 and parts[0] == "0":
                return float(parts[1]), float(parts[2])
        except Exception as exc:
            print(f"screen size query failed: {exc}", flush=True)
        return None

    def _send_v0(self, payload: bytes) -> None:
        assert self.sock is not None
        self.sock.sendall(payload)

    def _send_v1(self, task: int, args: list[str]) -> None:
        assert self.sock is not None
        body = json.dumps({"id": self.next_id, "task": task, "args": args}, ensure_ascii=True).encode("utf-8")
        self.next_id += 1
        self.sock.sendall(HEADER.pack(MAGIC, VERSION, 0, len(body)) + body)

    def _recv_exact(self, n: int) -> bytes:
        assert self.sock is not None
        data = bytearray()
        while len(data) < n:
            chunk = self.sock.recv(n - len(data))
            if not chunk:
                raise ConnectionError("socket closed")
            data.extend(chunk)
        return bytes(data)

    def _recv_v1(self) -> dict:
        header = self._recv_exact(HEADER.size)
        magic, version, _flags, length = HEADER.unpack(header)
        if magic != MAGIC or version != VERSION:
            raise RuntimeError("invalid v1 response")
        body = self._recv_exact(length)
        return json.loads(body.decode("utf-8"))

    def _recv_v0_line(self) -> bytes:
        assert self.sock is not None
        data = bytearray()
        while True:
            chunk = self.sock.recv(1)
            if not chunk:
                raise ConnectionError("socket closed")
            data.extend(chunk)
            if chunk == b"\n":
                return bytes(data)


def touch_payload(event_type: int, finger: int, x: float, y: float) -> str:
    xi = max(0, round(x * 10))
    yi = max(0, round(y * 10))
    return f"1{event_type}{finger:02d}{xi:05d}{yi:05d}"


def run_swipe_points(client: ZXTouchSocket, args: argparse.Namespace, start_y: float, end_y: float) -> None:
    client.send_touch(1, args.finger, args.x, start_y, args.ack, args.ack_log)
    args._gesture_active = True
    args._gesture_y = start_y
    time.sleep(args.down_delay_ms / 1000.0)

    steps = max(1, args.steps)
    for i in range(1, steps + 1):
        t = i / steps
        y = start_y + (end_y - start_y) * t
        client.send_touch(2, args.finger, args.x, y, args.ack_moves, args.ack_log_moves)
        args._gesture_y = y
        time.sleep(args.move_interval_ms / 1000.0)

    client.send_touch(0, args.finger, args.x, end_y, args.ack, args.ack_log)
    args._gesture_active = False


def run_swipe(client: ZXTouchSocket, args: argparse.Namespace) -> None:
    run_swipe_points(client, args, args.start_y, args.end_y)


def run_bounce(client: ZXTouchSocket, args: argparse.Namespace) -> None:
    run_swipe_points(client, args, args.start_y, args.end_y)
    time.sleep(args.bounce_gap_ms / 1000.0)
    run_swipe_points(client, args, args.end_y, args.start_y)


def run_pan(client: ZXTouchSocket, args: argparse.Namespace) -> None:
    # Keep one continuous finger down while moving up/down several times. This creates
    # sustained screen motion and stresses zxtouch without reconnecting the gesture.
    y = args.start_y
    client.send_touch(1, args.finger, args.x, y, args.ack, args.ack_log)
    args._gesture_active = True
    args._gesture_y = y
    time.sleep(args.down_delay_ms / 1000.0)

    direction = -1
    for cycle in range(args.pan_cycles):
        target = args.end_y if direction < 0 else args.start_y
        for i in range(1, max(1, args.steps) + 1):
            t = i / max(1, args.steps)
            next_y = y + (target - y) * t
            client.send_touch(2, args.finger, args.x, next_y, args.ack_moves, args.ack_log_moves)
            args._gesture_y = next_y
            time.sleep(args.move_interval_ms / 1000.0)
        y = target
        direction *= -1
        time.sleep(args.bounce_gap_ms / 1000.0)

    client.send_touch(0, args.finger, args.x, y, args.ack, args.ack_log)
    args._gesture_active = False


def run_tap(client: ZXTouchSocket, args: argparse.Namespace) -> None:
    client.send_touch(1, args.finger, args.x, args.tap_y, args.ack, args.ack_log)
    args._gesture_active = True
    args._gesture_y = args.tap_y
    time.sleep(args.tap_hold_ms / 1000.0)
    client.send_touch(0, args.finger, args.x, args.tap_y, args.ack, args.ack_log)
    args._gesture_active = False


def run_one(client: ZXTouchSocket, args: argparse.Namespace) -> None:
    if args.mode == "swipe":
        run_swipe(client, args)
    elif args.mode == "bounce":
        run_bounce(client, args)
    elif args.mode == "pan":
        run_pan(client, args)
    else:
        run_tap(client, args)


def main() -> None:
    parser = argparse.ArgumentParser(description="Direct zxtouch auto swipe/tap test over TCP 6000")
    parser.add_argument("host", help="iPhone IP address")
    parser.add_argument("--port", type=int, default=6000)
    parser.add_argument("--protocol", choices=("auto", "v0", "v1"), default="v0")
    parser.add_argument("--mode", choices=("swipe", "bounce", "pan", "tap"), default="swipe")
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--pause-ms", type=int, default=400)
    parser.add_argument("--finger", type=int, default=1)
    parser.add_argument("--x", type=float, default=200)
    parser.add_argument("--start-y", type=float)
    parser.add_argument("--end-y", type=float)
    parser.add_argument("--tap-y", type=float)
    parser.add_argument("--steps", type=int, default=12)
    parser.add_argument("--move-interval-ms", type=int, default=16)
    parser.add_argument("--down-delay-ms", type=int, default=30)
    parser.add_argument("--tap-hold-ms", type=int, default=80)
    parser.add_argument("--bounce-gap-ms", type=int, default=120)
    parser.add_argument("--pan-cycles", type=int, default=4, help="Up/down cycles inside one continuous pan gesture")
    parser.add_argument("--reconnect-each", action="store_true", help="Open a fresh TCP session for each gesture")
    parser.add_argument("--max-retries", type=int, default=20, help="Reconnect retries after socket errors")
    parser.add_argument("--stop-on-error", action="store_true", help="Stop instead of retrying socket errors")
    parser.add_argument("--ack", action="store_true", help="Use TASK_PERFORM_TOUCH_ACK for DOWN/UP")
    parser.add_argument("--ack-moves", action="store_true", help="Also wait for ACK on every MOVE")
    parser.add_argument("--ack-log", action="store_true", help="Log ACK latency for DOWN/UP")
    parser.add_argument("--ack-log-moves", action="store_true", help="Log ACK latency for MOVE commands")
    parser.add_argument("--no-recover-up", action="store_true", help="Do not send UP after reconnecting from a mid-gesture error")
    args = parser.parse_args()
    args._gesture_active = False
    args._gesture_y = 0.0

    client = ZXTouchSocket(args.host, args.port, args.protocol)
    client.connect()
    try:
        screen = client.get_screen_size()
        if screen:
            width, height = screen
            print(f"screen size {width:.0f}x{height:.0f}", flush=True)
            if args.x == 200:
                args.x = width / 2
            if args.start_y is None:
                args.start_y = height * 0.85
            if args.end_y is None:
                args.end_y = height * 0.25
            if args.tap_y is None:
                args.tap_y = height * 0.5
        else:
            if args.start_y is None:
                args.start_y = 600
            if args.end_y is None:
                args.end_y = 180
            if args.tap_y is None:
                args.tap_y = 400

        print(
            f"mode={args.mode} finger={args.finger} x={args.x:.1f} start_y={args.start_y:.1f} end_y={args.end_y:.1f} tap_y={args.tap_y:.1f}",
            flush=True,
        )
        i = 0
        retries = 0
        while i < args.count:
            try:
                if args.reconnect_each and i > 0:
                    client.reconnect()
                run_one(client, args)
                i += 1
                retries = 0
                print(f"{args.mode} {i}/{args.count}", flush=True)
                time.sleep(args.pause_ms / 1000.0)
            except (ConnectionError, ConnectionAbortedError, ConnectionResetError, BrokenPipeError, OSError) as exc:
                retries += 1
                print(f"socket error after {args.mode} {i + 1}/{args.count}: {exc}; reconnect {retries}/{args.max_retries}", flush=True)
                if args.stop_on_error or retries > args.max_retries:
                    raise
                if not client.reconnect_with_backoff(args.max_retries):
                    raise
                if args._gesture_active and not args.no_recover_up:
                    try:
                        print(f"sending recovery UP at y={args._gesture_y:.1f}", flush=True)
                        client.send_touch(0, args.finger, args.x, args._gesture_y, args.ack, args.ack_log)
                    except Exception as recover_exc:
                        print(f"recovery UP failed: {recover_exc}", flush=True)
                    args._gesture_active = False
    finally:
        client.close()


if __name__ == "__main__":
    main()
