#!/usr/bin/env python3
import argparse
import socket
import time


def touch_payload(event_type: int, finger: int, x: float, y: float) -> bytes:
    xi = max(0, round(x * 10))
    yi = max(0, round(y * 10))
    body = f"1{event_type}{finger:02d}{xi:05d}{yi:05d}"
    return f"10{body}\r\n".encode("ascii")


def send(sock: socket.socket, payload: bytes) -> None:
    sock.sendall(payload)


def run_swipe(sock: socket.socket, args: argparse.Namespace) -> None:
    send(sock, touch_payload(1, 0, args.x, args.start_y))
    time.sleep(args.down_delay_ms / 1000.0)

    steps = max(1, args.steps)
    for i in range(1, steps + 1):
        t = i / steps
        y = args.start_y + (args.end_y - args.start_y) * t
        send(sock, touch_payload(2, 0, args.x, y))
        time.sleep(args.move_interval_ms / 1000.0)

    send(sock, touch_payload(0, 0, args.x, args.end_y))


def run_tap(sock: socket.socket, args: argparse.Namespace) -> None:
    send(sock, touch_payload(1, 0, args.x, args.tap_y))
    time.sleep(args.tap_hold_ms / 1000.0)
    send(sock, touch_payload(0, 0, args.x, args.tap_y))


def main() -> None:
    parser = argparse.ArgumentParser(description="Direct zxtouch auto swipe/tap test over TCP 6000")
    parser.add_argument("host", help="iPhone IP address")
    parser.add_argument("--port", type=int, default=6000)
    parser.add_argument("--mode", choices=("swipe", "tap"), default="swipe")
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--pause-ms", type=int, default=400)
    parser.add_argument("--x", type=float, default=200)
    parser.add_argument("--start-y", type=float, default=760)
    parser.add_argument("--end-y", type=float, default=180)
    parser.add_argument("--tap-y", type=float, default=400)
    parser.add_argument("--steps", type=int, default=12)
    parser.add_argument("--move-interval-ms", type=int, default=16)
    parser.add_argument("--down-delay-ms", type=int, default=30)
    parser.add_argument("--tap-hold-ms", type=int, default=80)
    args = parser.parse_args()

    with socket.create_connection((args.host, args.port), timeout=3) as sock:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        for i in range(args.count):
            if args.mode == "swipe":
                run_swipe(sock, args)
            else:
                run_tap(sock, args)
            print(f"{args.mode} {i + 1}/{args.count}", flush=True)
            time.sleep(args.pause_ms / 1000.0)


if __name__ == "__main__":
    main()
