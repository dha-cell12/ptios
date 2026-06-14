#!/usr/bin/env python3
import argparse
import json
import math
import socket
import statistics
import struct
import time
from pathlib import Path
from typing import Any


MAGIC = b"ZXTP"
VERSION = 1
HEADER = struct.Struct(">4sBBI")


class ZXTouchClient:
    def __init__(self, host: str, port: int, protocol: str, timeout: float):
        self.host = host
        self.port = port
        self.protocol = protocol
        self.timeout = timeout
        self.sock: socket.socket | None = None
        self.next_id = 1
        self.v0_buf = bytearray()
        self.touch_seq = 1

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
        if self.protocol == "v1":
            return self._request_v1(task, list(args))
        payload = f"{task:02d}" + ";;".join(str(x) for x in args) + "\r\n"
        self._send(payload.encode("utf-8"))
        line = self._recv_v0_line().decode("utf-8", errors="replace").strip()
        parts = line.split(";;") if line else ["1", "empty_response"]
        ok = parts[0].startswith("0")
        return {"ok": ok, "data": parts[1:] if ok else [], "error": None if ok else ";;".join(parts[1:])}

    def send_fire_and_forget(self, task: int, *args: Any) -> None:
        if self.protocol == "v1":
            self._send_v1(task, list(args))
            return
        payload = f"{task:02d}" + ";;".join(str(x) for x in args) + "\r\n"
        self._send(payload.encode("utf-8"))

    def touch_ack(self, event_type: int, finger: int, x: float, y: float) -> tuple[float | None, dict[str, Any]]:
        seq = self.touch_seq
        self.touch_seq += 1
        payload = touch_payload(event_type, finger, x, y)
        resp = self.request(61, seq, payload)
        dispatch_us = None
        data = resp.get("data") or []
        if resp.get("ok") and len(data) >= 2 and str(data[0]) == str(seq):
            try:
                dispatch_us = float(data[1])
            except ValueError:
                dispatch_us = None
        return dispatch_us, resp

    def _request_v1(self, task: int, args: list[Any]) -> dict[str, Any]:
        self._send_v1(task, args)
        return self._recv_v1()

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


def touch_payload(event_type: int, finger: int, x: float, y: float) -> str:
    xi = max(0, min(99999, round(x * 10)))
    yi = max(0, min(99999, round(y * 10)))
    return f"1{event_type}{finger:02d}{xi:05d}{yi:05d}"


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    pos = (len(ordered) - 1) * pct / 100.0
    lo = math.floor(pos)
    hi = math.ceil(pos)
    if lo == hi:
        return ordered[lo]
    return ordered[lo] * (hi - pos) + ordered[hi] * (pos - lo)


def summarize(name: str, values_ms: list[float], failures: int, extra: dict[str, Any] | None = None) -> dict[str, Any]:
    result = {
        "name": name,
        "count": len(values_ms),
        "failures": failures,
        "avg_ms": statistics.fmean(values_ms) if values_ms else 0.0,
        "p50_ms": percentile(values_ms, 50),
        "p95_ms": percentile(values_ms, 95),
        "p99_ms": percentile(values_ms, 99),
        "max_ms": max(values_ms) if values_ms else 0.0,
    }
    if extra:
        result.update(extra)
    return result


def print_summary(result: dict[str, Any]) -> None:
    print(f"\n[{result['name']}]")
    print(f"count={result['count']} failures={result['failures']}")
    print(
        "avg={avg_ms:.3f}ms p50={p50_ms:.3f}ms p95={p95_ms:.3f}ms "
        "p99={p99_ms:.3f}ms max={max_ms:.3f}ms".format(**result)
    )
    if "dispatch_avg_us" in result:
        print(
            "dispatch_avg={dispatch_avg_us:.1f}us dispatch_p95={dispatch_p95_us:.1f}us".format(**result)
        )


def measure(name: str, count: int, fn) -> dict[str, Any]:
    values: list[float] = []
    failures = 0
    extras: dict[str, Any] = {}
    dispatch_values: list[float] = []
    for _ in range(count):
        started = time.perf_counter()
        try:
            ret = fn()
            elapsed = (time.perf_counter() - started) * 1000.0
            values.append(elapsed)
            if isinstance(ret, dict):
                extras.update(ret.get("extra", {}))
                if ret.get("dispatch_us") is not None:
                    dispatch_values.append(float(ret["dispatch_us"]))
        except Exception as exc:
            failures += 1
            if failures <= 5:
                print(f"{name} failed: {exc}")
    if dispatch_values:
        extras["dispatch_avg_us"] = statistics.fmean(dispatch_values)
        extras["dispatch_p95_us"] = percentile(dispatch_values, 95)
    return summarize(name, values, failures, extras)


def require_ok(resp: dict[str, Any]) -> list[Any]:
    if not resp.get("ok"):
        raise RuntimeError(resp.get("error") or resp)
    data = resp.get("data") or []
    return data if isinstance(data, list) else [data]


def parse_rgb_response(resp: dict[str, Any]) -> tuple[int, int, int]:
    data = require_ok(resp)
    if len(data) < 3:
        raise RuntimeError(f"bad RGB response: {resp}")
    return int(float(data[0])), int(float(data[1])), int(float(data[2]))


def run_touch_suite(client: ZXTouchClient, args: argparse.Namespace) -> list[dict[str, Any]]:
    x, y = args.x, args.y
    pause = max(0.0, args.pause_ms / 1000.0)
    results = []

    def raw_touch() -> None:
        client.send_fire_and_forget(10, touch_payload(1, args.finger, x, y))
        client.send_fire_and_forget(10, touch_payload(0, args.finger, x, y))
        if pause:
            time.sleep(pause)

    def touch_ack() -> dict[str, Any]:
        dispatch_us, _ = client.touch_ack(1, args.finger, x, y)
        client.touch_ack(0, args.finger, x, y)
        if pause:
            time.sleep(pause)
        return {"dispatch_us": dispatch_us}

    def native_tap() -> None:
        resp = client.request(62, x, y, args.tap_ms, args.finger)
        if not resp.get("ok"):
            raise RuntimeError(resp.get("error"))
        if pause:
            time.sleep(pause)

    results.append(measure("task10_raw_touch_send_only", args.count, raw_touch))
    results.append(measure("task61_touch_ack", args.count, touch_ack))
    results.append(measure("task62_native_tap", args.count, native_tap))
    return results


def run_gesture_suite(client: ZXTouchClient, args: argparse.Namespace) -> list[dict[str, Any]]:
    results = []
    x1, y1, x2, y2 = args.x, args.swipe_start_y, args.x, args.swipe_end_y
    duration = args.swipe_ms
    steps = args.steps

    def pc_moves() -> None:
        client.send_fire_and_forget(10, touch_payload(1, args.finger, x1, y1))
        for i in range(1, steps):
            t = i / float(steps)
            y = y1 + (y2 - y1) * t
            client.send_fire_and_forget(10, touch_payload(2, args.finger, x1, y))
            if duration > 0:
                time.sleep(duration / steps / 1000.0)
        client.send_fire_and_forget(10, touch_payload(0, args.finger, x2, y2))

    def native_swipe() -> None:
        resp = client.request(63, x1, y1, x2, y2, duration, args.finger, steps)
        if not resp.get("ok"):
            raise RuntimeError(resp.get("error"))

    def native_gesture() -> None:
        points = []
        for i in range(steps + 1):
            t = i / float(steps)
            y = y1 + (y2 - y1) * t
            points.append(f"{x1:.1f},{y:.1f}")
        resp = client.request(64, args.finger, duration, "|".join(points))
        if not resp.get("ok"):
            raise RuntimeError(resp.get("error"))

    results.append(measure("pc_streamed_moves_task10", args.gesture_count, pc_moves))
    results.append(measure("task63_native_swipe", args.gesture_count, native_swipe))
    results.append(measure("task64_native_gesture", args.gesture_count, native_gesture))
    return results


def run_screenshot_suite(client: ZXTouchClient, args: argparse.Namespace) -> list[dict[str, Any]]:
    results = []
    remote_dir = args.remote_tmp.rstrip("/")

    def shot_png() -> dict[str, Any]:
        path = f"{remote_dir}/zxtouch_bench.png"
        resp = client.request(29, 1, path)
        if not resp.get("ok"):
            raise RuntimeError(resp.get("error"))
        return {"extra": {"last_png_path": path}}

    def shot_jpg() -> dict[str, Any]:
        path = f"{remote_dir}/zxtouch_bench.jpg"
        resp = client.request(29, 1, path)
        if not resp.get("ok"):
            raise RuntimeError(resp.get("error"))
        return {"extra": {"last_jpg_path": path}}

    results.append(measure("task29_screenshot_png", args.screenshot_count, shot_png))
    results.append(measure("task29_screenshot_jpg", args.screenshot_count, shot_jpg))
    return results


def run_match_suite(client: ZXTouchClient, args: argparse.Namespace) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    color_x = args.color_x if args.color_x is not None else args.x
    color_y = args.color_y if args.color_y is not None else args.y

    sampled = parse_rgb_response(client.request(23, color_x, color_y))
    red, green, blue = sampled
    tolerance = max(0, min(255, args.color_tolerance))
    red_min, red_max = max(0, red - tolerance), min(255, red + tolerance)
    green_min, green_max = max(0, green - tolerance), min(255, green + tolerance)
    blue_min, blue_max = max(0, blue - tolerance), min(255, blue + tolerance)
    if args.debug:
        print(f"sampled color at ({color_x},{color_y}) r={red} g={green} b={blue} tolerance={tolerance}")

    def color_pick() -> dict[str, Any]:
        resp = client.request(23, color_x, color_y)
        data = parse_rgb_response(resp)
        if args.debug:
            return {"extra": {"last_rgb": list(data)}}
        return {}

    def color_search_single() -> dict[str, Any]:
        resp = client.request(
            28,
            1,
            args.color_region_x,
            args.color_region_y,
            args.color_region_w,
            args.color_region_h,
            red_min,
            red_max,
            green_min,
            green_max,
            blue_min,
            blue_max,
            args.color_skip,
        )
        data = require_ok(resp)
        return {"extra": {"last_color_search": data}}

    def color_is_colors() -> dict[str, Any]:
        table = f"{int(color_x)},,{int(color_y)},,{red},,{green},,{blue}"
        resp = client.request(28, 2, table, 1, tolerance)
        data = require_ok(resp)
        return {"extra": {"last_is_colors": data}}

    def color_find_multi_point() -> dict[str, Any]:
        table = f"0,,0,,{red},,{green},,{blue}"
        resp = client.request(
            28,
            3,
            args.color_region_x,
            args.color_region_y,
            args.color_region_w,
            args.color_region_h,
            table,
            1,
            tolerance,
            args.color_skip,
        )
        data = require_ok(resp)
        return {"extra": {"last_find_multi": data}}

    results.append(measure("task23_color_pick", args.match_count, color_pick))
    results.append(measure("task28_color_search_single", args.match_count, color_search_single))
    results.append(measure("task28_color_is_colors", args.match_count, color_is_colors))
    results.append(measure("task28_color_find_multi_point", args.match_count, color_find_multi_point))

    if not args.template_path:
        print("\n[match image] skipped: pass --template-path <path_on_ios> to benchmark task21/task48/task49")
        return results

    template_path = args.template_path

    def legacy_template_match() -> dict[str, Any]:
        resp = client.request(21, template_path, args.match_max_try, args.match_acceptable, args.match_scale_ratio)
        data = require_ok(resp)
        return {"extra": {"last_task21": data}}

    image_id: str | None = None
    try:
        load_resp = client.request(48, 2, template_path)
        load_data = require_ok(load_resp)
        if len(load_data) < 1:
            raise RuntimeError(f"bad image object response: {load_resp}")
        image_id = str(load_data[0])
        if args.debug:
            print(f"loaded template image object id={image_id} data={load_data}")

        def find_image_object() -> dict[str, Any]:
            resp = client.request(
                49,
                image_id,
                args.match_region_x,
                args.match_region_y,
                args.match_region_w,
                args.match_region_h,
                args.match_acceptable,
                args.match_scale_min,
                args.match_scale_max,
                args.match_scale_step,
                args.match_pixel_skip,
            )
            data = require_ok(resp)
            return {"extra": {"last_task49": data}}

        results.append(measure("task21_template_match_legacy", args.image_match_count, legacy_template_match))
        results.append(measure("task49_find_image_cached_template", args.image_match_count, find_image_object))
    finally:
        if image_id:
            try:
                client.request(48, 3, image_id)
            except Exception as exc:
                if args.debug:
                    print(f"failed to release image object {image_id}: {exc}")

    return results


def capture_frame(client: ZXTouchClient, gray: int = 1, bgra: int = 1, ttl_ms: int = 1000) -> tuple[str, list[Any]]:
    resp = client.request(66, gray, bgra, ttl_ms)
    data = require_ok(resp)
    if len(data) < 1:
        raise RuntimeError(f"bad frame capture response: {resp}")
    return str(data[0]), data


def release_frame(client: ZXTouchClient, frame_id: str) -> None:
    try:
        client.request(67, frame_id)
    except Exception:
        pass


def load_template_object(client: ZXTouchClient, template_path: str) -> str:
    resp = client.request(48, 2, template_path)
    data = require_ok(resp)
    if len(data) < 1:
        raise RuntimeError(f"bad image object response: {resp}")
    return str(data[0])


def release_template_object(client: ZXTouchClient, image_id: str) -> None:
    try:
        client.request(48, 3, image_id)
    except Exception:
        pass


def run_frame_suite(client: ZXTouchClient, args: argparse.Namespace) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    color_x = args.color_x if args.color_x is not None else args.x
    color_y = args.color_y if args.color_y is not None else args.y
    sampled = parse_rgb_response(client.request(23, color_x, color_y))
    red, green, blue = sampled
    tolerance = max(0, min(255, args.color_tolerance))
    red_min, red_max = max(0, red - tolerance), min(255, red + tolerance)
    green_min, green_max = max(0, green - tolerance), min(255, green + tolerance)
    blue_min, blue_max = max(0, blue - tolerance), min(255, blue + tolerance)
    if args.debug:
        print(f"frame suite sampled color at ({color_x},{color_y}) r={red} g={green} b={blue}")

    def frame_capture_bgra() -> dict[str, Any]:
        fid, data = capture_frame(client, gray=0, bgra=1, ttl_ms=args.frame_ttl_ms)
        release_frame(client, fid)
        return {"extra": {"last_frame_bgra": data}}

    def frame_capture_gray() -> dict[str, Any]:
        fid, data = capture_frame(client, gray=1, bgra=0, ttl_ms=args.frame_ttl_ms)
        release_frame(client, fid)
        return {"extra": {"last_frame_gray": data}}

    def frame_capture_both() -> dict[str, Any]:
        fid, data = capture_frame(client, gray=1, bgra=1, ttl_ms=args.frame_ttl_ms)
        release_frame(client, fid)
        return {"extra": {"last_frame_both": data}}

    results.append(measure("task66_frame_capture_bgra", args.frame_count, frame_capture_bgra))
    results.append(measure("task66_frame_capture_gray", args.frame_count, frame_capture_gray))
    results.append(measure("task66_frame_capture_bgra_gray", args.frame_count, frame_capture_both))

    def color_pick_in_frame() -> dict[str, Any]:
        fid, _ = capture_frame(client, gray=0, bgra=1, ttl_ms=args.frame_ttl_ms)
        try:
            resp = client.request(69, fid, "pick", color_x, color_y, "pixel", args.frame_max_age_ms)
            data = require_ok(resp)
            return {"extra": {"last_color_pick_frame": data}}
        finally:
            release_frame(client, fid)

    def color_search_in_frame() -> dict[str, Any]:
        fid, _ = capture_frame(client, gray=0, bgra=1, ttl_ms=args.frame_ttl_ms)
        try:
            resp = client.request(
                69,
                fid,
                "search_single",
                args.color_region_x,
                args.color_region_y,
                args.color_region_w,
                args.color_region_h,
                red_min,
                red_max,
                green_min,
                green_max,
                blue_min,
                blue_max,
                args.color_skip,
                "pixel",
                args.frame_max_age_ms,
            )
            data = require_ok(resp)
            return {"extra": {"last_color_search_frame": data}}
        finally:
            release_frame(client, fid)

    def is_colors_in_frame() -> dict[str, Any]:
        fid, _ = capture_frame(client, gray=0, bgra=1, ttl_ms=args.frame_ttl_ms)
        try:
            table = f"{int(color_x)},,{int(color_y)},,{red},,{green},,{blue}"
            resp = client.request(69, fid, "is_colors", table, 1, tolerance, "pixel", args.frame_max_age_ms)
            data = require_ok(resp)
            return {"extra": {"last_is_colors_frame": data}}
        finally:
            release_frame(client, fid)

    def find_multi_in_frame() -> dict[str, Any]:
        fid, _ = capture_frame(client, gray=0, bgra=1, ttl_ms=args.frame_ttl_ms)
        try:
            table = f"0,,0,,{red},,{green},,{blue}"
            resp = client.request(
                69,
                fid,
                "find_multi_point",
                args.color_region_x,
                args.color_region_y,
                args.color_region_w,
                args.color_region_h,
                table,
                1,
                tolerance,
                args.color_skip,
                "pixel",
                args.frame_max_age_ms,
            )
            data = require_ok(resp)
            return {"extra": {"last_find_multi_frame": data}}
        finally:
            release_frame(client, fid)

    results.append(measure("task69_color_pick_in_frame_with_capture", args.frame_count, color_pick_in_frame))
    results.append(measure("task69_color_search_in_frame_with_capture", args.frame_count, color_search_in_frame))
    results.append(measure("task69_is_colors_in_frame_with_capture", args.frame_count, is_colors_in_frame))
    results.append(measure("task69_find_multi_point_in_frame_with_capture", args.frame_count, find_multi_in_frame))

    def scenario_10_color_picks_old() -> None:
        for _ in range(10):
            parse_rgb_response(client.request(23, color_x, color_y))

    def scenario_10_color_picks_frame() -> dict[str, Any]:
        fid, _ = capture_frame(client, gray=0, bgra=1, ttl_ms=args.frame_ttl_ms)
        try:
            last = []
            for _ in range(10):
                last = require_ok(client.request(69, fid, "pick", color_x, color_y, "pixel", args.frame_max_age_ms))
            return {"extra": {"last_10_color_frame": last}}
        finally:
            release_frame(client, fid)

    results.append(measure("scenario_10_color_picks_old", args.scenario_count, scenario_10_color_picks_old))
    results.append(measure("scenario_10_color_picks_frame", args.scenario_count, scenario_10_color_picks_frame))

    if not args.template_path:
        print("\n[frame image] skipped: pass --template-path <path_on_ios> to benchmark task68 image in frame")
        return results

    image_id: str | None = None
    try:
        image_id = load_template_object(client, args.template_path)
        if args.debug:
            print(f"loaded template image object for frame suite id={image_id}")

        def find_image_in_frame() -> dict[str, Any]:
            fid, _ = capture_frame(client, gray=1, bgra=0, ttl_ms=args.frame_ttl_ms)
            try:
                resp = client.request(
                    68,
                    fid,
                    image_id,
                    args.match_region_x,
                    args.match_region_y,
                    args.match_region_w,
                    args.match_region_h,
                    args.match_acceptable,
                    args.match_scale_min,
                    args.match_scale_max,
                    args.match_scale_step,
                    args.match_pixel_skip,
                    "pixel",
                    args.frame_max_age_ms,
                )
                data = require_ok(resp)
                return {"extra": {"last_find_image_frame": data}}
            finally:
                release_frame(client, fid)

        def scenario_2_image_5_color_frame() -> dict[str, Any]:
            fid, _ = capture_frame(client, gray=1, bgra=1, ttl_ms=args.frame_ttl_ms)
            try:
                last_img = []
                for _ in range(2):
                    last_img = require_ok(client.request(
                        68,
                        fid,
                        image_id,
                        args.match_region_x,
                        args.match_region_y,
                        args.match_region_w,
                        args.match_region_h,
                        args.match_acceptable,
                        args.match_scale_min,
                        args.match_scale_max,
                        args.match_scale_step,
                        args.match_pixel_skip,
                        "pixel",
                        args.frame_max_age_ms,
                    ))
                last_color = []
                for _ in range(5):
                    last_color = require_ok(client.request(69, fid, "pick", color_x, color_y, "pixel", args.frame_max_age_ms))
                return {"extra": {"last_scenario_image": last_img, "last_scenario_color": last_color}}
            finally:
                release_frame(client, fid)

        results.append(measure("task68_find_image_in_frame_with_capture", args.image_match_count, find_image_in_frame))
        results.append(measure("scenario_2_image_5_color_frame", args.scenario_count, scenario_2_image_5_color_frame))
    finally:
        if image_id:
            release_template_object(client, image_id)

    return results


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark zxtouch command latency from PC")
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, default=6000)
    parser.add_argument("--protocol", choices=["auto", "v1", "v0"], default="auto")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--suite", choices=["touch", "gesture", "screenshot", "match", "frame", "all"], default="all")
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--gesture-count", type=int, default=20)
    parser.add_argument("--screenshot-count", type=int, default=10)
    parser.add_argument("--x", type=float, default=120.0)
    parser.add_argument("--y", type=float, default=300.0)
    parser.add_argument("--swipe-start-y", type=float, default=500.0)
    parser.add_argument("--swipe-end-y", type=float, default=200.0)
    parser.add_argument("--finger", type=int, default=0)
    parser.add_argument("--tap-ms", type=int, default=50)
    parser.add_argument("--swipe-ms", type=int, default=300)
    parser.add_argument("--steps", type=int, default=20)
    parser.add_argument("--pause-ms", type=float, default=10.0)
    parser.add_argument("--remote-tmp", default="/tmp")
    parser.add_argument("--json-out", default="")
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--match-count", type=int, default=50)
    parser.add_argument("--image-match-count", type=int, default=20)
    parser.add_argument("--template-path", default="", help="Template path on the iOS device for task21/task48/task49")
    parser.add_argument("--match-region-x", type=int, default=0)
    parser.add_argument("--match-region-y", type=int, default=0)
    parser.add_argument("--match-region-w", type=int, default=0)
    parser.add_argument("--match-region-h", type=int, default=0)
    parser.add_argument("--match-acceptable", type=float, default=0.8)
    parser.add_argument("--match-max-try", type=int, default=2)
    parser.add_argument("--match-scale-ratio", type=float, default=0.8)
    parser.add_argument("--match-scale-min", type=float, default=1.0)
    parser.add_argument("--match-scale-max", type=float, default=1.0)
    parser.add_argument("--match-scale-step", type=float, default=0.1)
    parser.add_argument("--match-pixel-skip", type=int, default=0)
    parser.add_argument("--color-x", type=float, default=None)
    parser.add_argument("--color-y", type=float, default=None)
    parser.add_argument("--color-region-x", type=int, default=0)
    parser.add_argument("--color-region-y", type=int, default=0)
    parser.add_argument("--color-region-w", type=int, default=0)
    parser.add_argument("--color-region-h", type=int, default=0)
    parser.add_argument("--color-tolerance", type=int, default=10)
    parser.add_argument("--color-skip", type=int, default=0)
    parser.add_argument("--frame-count", type=int, default=30)
    parser.add_argument("--frame-ttl-ms", type=int, default=1000)
    parser.add_argument("--frame-max-age-ms", type=int, default=1000)
    parser.add_argument("--scenario-count", type=int, default=10)
    args = parser.parse_args()

    client = ZXTouchClient(args.host, args.port, args.protocol, args.timeout)
    client.connect()
    print(f"connected host={args.host}:{args.port} protocol={client.protocol}")

    all_results: list[dict[str, Any]] = []
    try:
        if args.suite in ("touch", "all"):
            all_results.extend(run_touch_suite(client, args))
        if args.suite in ("gesture", "all"):
            all_results.extend(run_gesture_suite(client, args))
        if args.suite in ("screenshot", "all"):
            all_results.extend(run_screenshot_suite(client, args))
        if args.suite in ("match", "all"):
            all_results.extend(run_match_suite(client, args))
        if args.suite in ("frame", "all"):
            all_results.extend(run_frame_suite(client, args))
    finally:
        client.close()

    for result in all_results:
        print_summary(result)

    if args.json_out:
        out = {"host": args.host, "port": args.port, "protocol": client.protocol, "results": all_results}
        Path(args.json_out).write_text(json.dumps(out, indent=2), encoding="utf-8")
        print(f"\nwrote {args.json_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
