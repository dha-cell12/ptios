#!/usr/bin/env python3
import argparse
import base64
import json
import socket
import struct
import time
from typing import Any


MAGIC = b"ZXTP"
VERSION = 1
HEADER = struct.Struct(">4sBBI")


class TLinkautoClient:
    def __init__(self, host: str, port: int, protocol: str, timeout: float):
        self.host = host
        self.port = port
        self.protocol = protocol
        self.timeout = timeout
        self.sock: socket.socket | None = None
        self.next_id = 1
        self.v0_buf = bytearray()

    def connect(self) -> None:
        if self.protocol in ("auto", "v1"):
            try:
                self.sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
                self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                self.sock.settimeout(min(self.timeout, 1.0))
                self.protocol = "v1"
                self.request(45)
                self.sock.settimeout(self.timeout)
                return
            except Exception:
                self.close()
                if self.protocol == "v1":
                    raise

        self.sock = socket.create_connection((self.host, self.port), timeout=self.timeout)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.sock.settimeout(self.timeout)
        self.protocol = "v0"

    def close(self) -> None:
        if self.sock:
            try:
                self.sock.close()
            except Exception:
                pass
        self.sock = None

    def request(self, task: int, *args: Any) -> dict[str, Any]:
        start = time.perf_counter()
        if self.protocol == "v1":
            self._send_v1(task, list(args))
            resp = self._recv_v1()
        else:
            payload = f"{task:02d}" + ";;".join(str(x) for x in args) + "\r\n"
            self._send(payload.encode("utf-8"))
            line = self._recv_v0_line().decode("utf-8", errors="replace").strip()
            parts = line.split(";;") if line else ["1", "empty_response"]
            ok = parts[0].startswith("0")
            resp = {"ok": ok, "data": parts[1:] if ok else [], "error": None if ok else ";;".join(parts[1:])}
        resp["roundtrip_ms"] = (time.perf_counter() - start) * 1000.0
        return resp

    def _send_v1(self, task: int, args: list[Any]) -> None:
        req_id = self.next_id
        self.next_id += 1
        body = json.dumps({"id": req_id, "task": int(task), "args": [str(x) for x in args]}, ensure_ascii=True).encode("utf-8")
        self._send(HEADER.pack(MAGIC, VERSION, 0, len(body)) + body)

    def _recv_v1(self) -> dict[str, Any]:
        header = self._recv_exact(HEADER.size)
        magic, version, _flags, length = HEADER.unpack(header)
        if magic != MAGIC or version != VERSION:
            raise RuntimeError("invalid ZXTP response header")
        body = self._recv_exact(length)
        return json.loads(body.decode("utf-8"))

    def _send(self, data: bytes) -> None:
        if not self.sock:
            raise RuntimeError("not connected")
        self.sock.sendall(data)

    def _recv_exact(self, n: int) -> bytes:
        if not self.sock:
            raise RuntimeError("not connected")
        out = bytearray()
        while len(out) < n:
            chunk = self.sock.recv(n - len(out))
            if not chunk:
                raise ConnectionError("socket closed")
            out.extend(chunk)
        return bytes(out)

    def _recv_v0_line(self) -> bytes:
        if not self.sock:
            raise RuntimeError("not connected")
        while True:
            nl = self.v0_buf.find(b"\n")
            if nl >= 0:
                line = bytes(self.v0_buf[: nl + 1])
                del self.v0_buf[: nl + 1]
                return line
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("socket closed")
            self.v0_buf.extend(chunk)


def b64_text(value: str) -> str:
    return base64.b64encode(value.encode("utf-8")).decode("ascii")


def decode_b64(value: Any) -> str:
    try:
        return base64.b64decode(str(value)).decode("utf-8", errors="replace")
    except Exception as exc:
        return f"<base64 decode failed: {exc}>"


def require_ok(resp: dict[str, Any], label: str) -> list[Any]:
    if not resp.get("ok"):
        raise RuntimeError(f"{label} failed: {resp.get('error') or resp}")
    data = resp.get("data") or []
    return data


def print_resp(label: str, resp: dict[str, Any], verbose: bool) -> None:
    status = "ok" if resp.get("ok") else "ERR"
    print(f"{label}: {status} roundtrip_ms={resp.get('roundtrip_ms', 0):.3f}")
    if verbose:
        print(f"  raw={resp}")


def run_once(client: TLinkautoClient, args: argparse.Namespace, iteration: int) -> dict[str, Any]:
    cap = client.request(66, args.capture_gray, args.capture_bgra, args.ttl_ms)
    print_resp(f"capture[{iteration}]", cap, args.verbose)
    cap_data = require_ok(cap, "capture")
    if len(cap_data) < 4:
        raise RuntimeError(f"capture response too short: {cap_data}")

    frame_id = str(cap_data[0])
    frame_w = int(float(cap_data[1]))
    frame_h = int(float(cap_data[2]))
    print(f"  frame_id={frame_id} size={frame_w}x{frame_h}")

    whitelist_b64 = b64_text(args.whitelist) if args.whitelist else ""
    ocr = None
    try:
        ocr = client.request(
            91,
            frame_id,
            args.x,
            args.y,
            args.w,
            args.h,
            args.lang,
            args.oem,
            args.psm,
            whitelist_b64,
            args.scale_up,
            args.threshold_mode,
            args.coord,
            args.max_age_ms,
        )
        print_resp(f"ocr[{iteration}]", ocr, args.verbose)
        ocr_data = require_ok(ocr, "ocr")
        if len(ocr_data) < 6:
            raise RuntimeError(f"ocr response too short: {ocr_data}")

        text = decode_b64(ocr_data[0])
        result = {
            "text": text,
            "confidence": float(ocr_data[1]),
            "frame_age_ms": float(ocr_data[2]),
            "ocr_ms": float(ocr_data[3]),
            "preprocess_ms": float(ocr_data[4]),
            "native_total_ms": float(ocr_data[5]),
            "roundtrip_ms": float(ocr.get("roundtrip_ms", 0.0)),
        }
        print(f"  text={result['text']!r}")
        print(
            "  confidence={confidence:.2f} frame_age_ms={frame_age_ms:.0f} "
            "ocr_ms={ocr_ms:.3f} preprocess_ms={preprocess_ms:.3f} "
            "native_total_ms={native_total_ms:.3f} roundtrip_ms={roundtrip_ms:.3f}".format(**result)
        )
        return result
    finally:
        rel = client.request(67, frame_id)
        print_resp(f"release[{iteration}]", rel, args.verbose)


def main() -> int:
    parser = argparse.ArgumentParser(description="Debug TLinkauto task 91 Tesseract OCR against a captured frame.")
    parser.add_argument("--host", required=True, help="iPhone IP address")
    parser.add_argument("--port", type=int, default=6000)
    parser.add_argument("--protocol", choices=["auto", "v0", "v1"], default="auto")
    parser.add_argument("--timeout", type=float, default=15.0)
    parser.add_argument("--x", type=int, required=True)
    parser.add_argument("--y", type=int, required=True)
    parser.add_argument("--w", type=int, required=True)
    parser.add_argument("--h", type=int, required=True)
    parser.add_argument("--coord", choices=["pixel", "point"], default="point")
    parser.add_argument("--lang", default="vie")
    parser.add_argument("--oem", type=int, default=1, help="1=LSTM-only")
    parser.add_argument("--psm", type=int, default=7, help="6=single_block, 7=single_line, 8=single_word")
    parser.add_argument("--whitelist", default="")
    parser.add_argument("--scale-up", type=int, default=2)
    parser.add_argument("--threshold-mode", type=int, default=0, help="0=none, 1=binary/Otsu, 2=adaptive")
    parser.add_argument("--ttl-ms", type=int, default=3000)
    parser.add_argument("--max-age-ms", type=int, default=3000)
    parser.add_argument("--capture-gray", type=int, default=1)
    parser.add_argument("--capture-bgra", type=int, default=0)
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--check-langs", action="store_true", help="Run 91check_langs before OCR")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    client = TLinkautoClient(args.host, args.port, args.protocol, args.timeout)
    client.connect()
    print(f"connected protocol={client.protocol} host={args.host}:{args.port}")
    try:
        if args.check_langs:
            langs = client.request(91, "check_langs")
            print_resp("check_langs", langs, args.verbose)
            data = require_ok(langs, "check_langs")
            if len(data) >= 2 and str(data[0]) == "check_langs":
                print(f"  langs={decode_b64(data[1])}")
            else:
                print(f"  data={data}")

        results = []
        for i in range(args.count):
            results.append(run_once(client, args, i + 1))

        if len(results) > 1:
            avg_ocr = sum(x["ocr_ms"] for x in results) / len(results)
            avg_pre = sum(x["preprocess_ms"] for x in results) / len(results)
            avg_rt = sum(x["roundtrip_ms"] for x in results) / len(results)
            print(f"summary count={len(results)} avg_ocr_ms={avg_ocr:.3f} avg_preprocess_ms={avg_pre:.3f} avg_roundtrip_ms={avg_rt:.3f}")
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
