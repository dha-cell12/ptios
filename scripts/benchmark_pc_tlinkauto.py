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


class TLinkautoClient:
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
    metric_keys = [
        "native_total_avg_ms",
        "capture_wall_avg_ms",
        "capture_avg_ms",
        "bgra_avg_ms",
        "gray_avg_ms",
        "release_wall_avg_ms",
        "release_avg_ms",
        "scenario_total_avg_ms",
        "checks_total_avg_ms",
        "checks_native_total_avg_ms",
        "image_match_total_avg_ms",
        "image_match_each_avg_ms",
        "image1_match_avg_ms",
        "image2_match_avg_ms",
        "match_avg_ms",
        "color_scan_avg_ms",
        "scan_avg_ms",
        "ipc_overhead_est_avg_ms",
    ]
    shown = [k for k in metric_keys if k in result]
    if shown:
        print(" ".join(f"{k}={result[k]:.3f}" for k in shown))
    if "found_rate" in result:
        print(
            "found_rate={found_rate:.2f} score_avg={score_avg:.4f} score_min={score_min:.4f} score_max={score_max:.4f}".format(**result)
        )
    if "text_count_avg" in result:
        print("text_count_avg={text_count_avg:.1f} chars_avg={chars_avg:.1f}".format(**result))
    if "language_count" in result:
        print(f"language_count={result['language_count']}")


def measure(name: str, count: int, fn) -> dict[str, Any]:
    values: list[float] = []
    failures = 0
    extras: dict[str, Any] = {}
    dispatch_values: list[float] = []
    metric_values: dict[str, list[float]] = {}
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
                metrics = ret.get("metrics")
                if isinstance(metrics, dict):
                    for key, value in metrics.items():
                        if value is None:
                            continue
                        metric_values.setdefault(key, []).append(float(value))
        except Exception as exc:
            failures += 1
            if failures <= 5:
                print(f"{name} failed: {exc}")
    if dispatch_values:
        extras["dispatch_avg_us"] = statistics.fmean(dispatch_values)
        extras["dispatch_p95_us"] = percentile(dispatch_values, 95)
    for key, values in metric_values.items():
        extras[f"{key}_avg_ms"] = statistics.fmean(values)
        extras[f"{key}_p95_ms"] = percentile(values, 95)
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


def frame_capture_metrics(data: list[Any], roundtrip_ms: float | None = None) -> dict[str, float]:
    metrics: dict[str, float] = {}
    try:
        metrics["capture"] = float(data[10])
        metrics["bgra"] = float(data[11])
        metrics["gray"] = float(data[12])
        metrics["native_total"] = float(data[13])
    except (IndexError, TypeError, ValueError):
        return metrics
    if roundtrip_ms is not None:
        metrics["ipc_overhead_est"] = max(0.0, roundtrip_ms - metrics.get("native_total", 0.0))
    return metrics


def color_frame_metrics(data: list[Any], native_total_index: int = -1, roundtrip_ms: float | None = None) -> dict[str, float]:
    metrics: dict[str, float] = {}
    try:
        native_total = float(data[native_total_index])
    except (IndexError, TypeError, ValueError):
        return metrics
    metrics["native_total"] = native_total
    metrics["scan"] = native_total
    if roundtrip_ms is not None:
        metrics["ipc_overhead_est"] = max(0.0, roundtrip_ms - native_total)
    return metrics


def image_frame_metrics(data: list[Any], roundtrip_ms: float | None = None) -> dict[str, float]:
    metrics: dict[str, float] = {}
    try:
        match_ms = float(data[-2])
        native_total = float(data[-1])
    except (IndexError, TypeError, ValueError):
        return metrics
    metrics["match"] = match_ms
    metrics["native_total"] = native_total
    if roundtrip_ms is not None:
        metrics["ipc_overhead_est"] = max(0.0, roundtrip_ms - native_total)
    return metrics


def frame_batch_metrics(data: list[Any], roundtrip_ms: float | None = None) -> dict[str, float]:
    metrics: dict[str, float] = {}
    try:
        results = str(data[0])
        native_total = float(data[-1])
    except (IndexError, TypeError, ValueError):
        return metrics
    image_matches: list[float] = []
    color_scan = 0.0
    for op in results.split("@@"):
        if op.startswith("img:"):
            fields = op[4:].split(",")
            try:
                image_matches.append(float(fields[-1]))
            except (IndexError, ValueError):
                pass
        elif op.startswith("pick_many:"):
            try:
                color_scan += float(op.rsplit(",", 1)[1])
            except (IndexError, ValueError):
                pass
    metrics["native_total"] = native_total
    metrics["checks_native_total"] = native_total
    metrics["image_match_total"] = sum(image_matches)
    metrics["image_match_each"] = (sum(image_matches) / len(image_matches)) if image_matches else 0.0
    metrics["color_scan"] = color_scan
    if len(image_matches) >= 1:
        metrics["image1_match"] = image_matches[0]
    if len(image_matches) >= 2:
        metrics["image2_match"] = image_matches[1]
    if roundtrip_ms is not None:
        metrics["ipc_overhead_est"] = max(0.0, roundtrip_ms - native_total)
    return metrics


def ocr_result_stats(data: list[Any]) -> dict[str, float]:
    text_count = 0
    char_count = 0
    for item in data:
        if not item:
            continue
        text = str(item).split(",,", 1)[0]
        if text:
            text_count += 1
            char_count += len(text)
    return {"text_count": float(text_count), "chars": float(char_count)}


def parse_float_list(text: str) -> list[float]:
    return [float(x.strip()) for x in text.split(",") if x.strip()]


def parse_int_list(text: str) -> list[int]:
    return [int(x.strip()) for x in text.split(",") if x.strip()]


def parse_region_specs(
    text: str,
    frame_w: int,
    frame_h: int,
    args: argparse.Namespace,
    found_box: tuple[int, int, int, int] | None = None,
) -> list[tuple[str, int, int, int, int]]:
    specs: list[tuple[str, int, int, int, int]] = []
    for raw in text.split(","):
        name = raw.strip().lower()
        if not name:
            continue
        if name == "full":
            specs.append(("full", 0, 0, 0, 0))
        elif name == "custom":
            specs.append(("custom", args.match_region_x, args.match_region_y, args.match_region_w, args.match_region_h))
        elif name.endswith("%"):
            pct = max(1.0, min(100.0, float(name[:-1]))) / 100.0
            w = max(1, int(frame_w * pct))
            h = max(1, int(frame_h * pct))
            x = max(0, (frame_w - w) // 2)
            y = max(0, (frame_h - h) // 2)
            specs.append((name, x, y, w, h))
        elif name.startswith("found_pad_"):
            if found_box is None:
                raise ValueError(f"{raw} requires a successful full-screen probe")
            pad = max(0, int(float(name.removeprefix("found_pad_"))))
            x, y, w, h = padded_box(found_box, frame_w, frame_h, pad)
            specs.append((name, x, y, w, h))
        elif ":" in name:
            label, coords = name.split(":", 1)
            vals = [int(float(x)) for x in coords.split("/") if x]
            if len(vals) != 4:
                raise ValueError(f"bad region spec: {raw}; expected label:x/y/w/h")
            specs.append((label, vals[0], vals[1], vals[2], vals[3]))
        else:
            raise ValueError(f"unknown region spec: {raw}")
    return specs or [("full", 0, 0, 0, 0)]


def padded_box(box: tuple[int, int, int, int], frame_w: int, frame_h: int, pad: int) -> tuple[int, int, int, int]:
    fx, fy, fw, fh = box
    x = max(0, fx - pad)
    y = max(0, fy - pad)
    right = min(frame_w, fx + fw + pad)
    bottom = min(frame_h, fy + fh + pad)
    return x, y, max(1, right - x), max(1, bottom - y)


def run_touch_suite(client: TLinkautoClient, args: argparse.Namespace) -> list[dict[str, Any]]:
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


def run_gesture_suite(client: TLinkautoClient, args: argparse.Namespace) -> list[dict[str, Any]]:
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


def run_screenshot_suite(client: TLinkautoClient, args: argparse.Namespace) -> list[dict[str, Any]]:
    results = []
    remote_dir = args.remote_tmp.rstrip("/")

    def shot_png() -> dict[str, Any]:
        path = f"{remote_dir}/TLinkauto_bench.png"
        resp = client.request(29, 1, path)
        if not resp.get("ok"):
            raise RuntimeError(resp.get("error"))
        return {"extra": {"last_png_path": path}}

    def shot_jpg() -> dict[str, Any]:
        path = f"{remote_dir}/TLinkauto_bench.jpg"
        resp = client.request(29, 1, path)
        if not resp.get("ok"):
            raise RuntimeError(resp.get("error"))
        return {"extra": {"last_jpg_path": path}}

    results.append(measure("task29_screenshot_png", args.screenshot_count, shot_png))
    results.append(measure("task29_screenshot_jpg", args.screenshot_count, shot_jpg))
    return results


def run_match_suite(client: TLinkautoClient, args: argparse.Namespace) -> list[dict[str, Any]]:
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


def capture_frame(client: TLinkautoClient, gray: int = 1, bgra: int = 1, ttl_ms: int = 1000) -> tuple[str, list[Any]]:
    resp = client.request(66, gray, bgra, ttl_ms)
    data = require_ok(resp)
    if len(data) < 1:
        raise RuntimeError(f"bad frame capture response: {resp}")
    return str(data[0]), data


def release_frame(client: TLinkautoClient, frame_id: str) -> None:
    try:
        client.request(67, frame_id)
    except Exception:
        pass


def load_template_object(client: TLinkautoClient, template_path: str) -> str:
    resp = client.request(48, 2, template_path)
    data = require_ok(resp)
    if len(data) < 1:
        raise RuntimeError(f"bad image object response: {resp}")
    return str(data[0])


def release_template_object(client: TLinkautoClient, image_id: str) -> None:
    try:
        client.request(48, 3, image_id)
    except Exception:
        pass


def timed_request(client: TLinkautoClient, task: int, *args: Any) -> tuple[dict[str, Any], float]:
    started = time.perf_counter()
    resp = client.request(task, *args)
    return resp, (time.perf_counter() - started) * 1000.0


def run_frame_suite(client: TLinkautoClient, args: argparse.Namespace) -> list[dict[str, Any]]:
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
        resp, rt_ms = timed_request(client, 66, 0, 1, args.frame_ttl_ms)
        data = require_ok(resp)
        fid = str(data[0])
        release_frame(client, fid)
        return {"extra": {"last_frame_bgra": data}, "metrics": frame_capture_metrics(data, rt_ms)}

    def frame_capture_gray() -> dict[str, Any]:
        resp, rt_ms = timed_request(client, 66, 1, 0, args.frame_ttl_ms)
        data = require_ok(resp)
        fid = str(data[0])
        release_frame(client, fid)
        return {"extra": {"last_frame_gray": data}, "metrics": frame_capture_metrics(data, rt_ms)}

    def frame_capture_both() -> dict[str, Any]:
        resp, rt_ms = timed_request(client, 66, 1, 1, args.frame_ttl_ms)
        data = require_ok(resp)
        fid = str(data[0])
        release_frame(client, fid)
        return {"extra": {"last_frame_both": data}, "metrics": frame_capture_metrics(data, rt_ms)}

    results.append(measure("task66_frame_capture_bgra", args.frame_count, frame_capture_bgra))
    results.append(measure("task66_frame_capture_gray", args.frame_count, frame_capture_gray))
    results.append(measure("task66_frame_capture_bgra_gray", args.frame_count, frame_capture_both))

    def color_pick_in_frame() -> dict[str, Any]:
        fid, _ = capture_frame(client, gray=0, bgra=1, ttl_ms=args.frame_ttl_ms)
        try:
            resp, rt_ms = timed_request(client, 69, fid, "pick", color_x, color_y, "pixel", args.frame_max_age_ms)
            data = require_ok(resp)
            return {"extra": {"last_color_pick_frame": data}, "metrics": color_frame_metrics(data, -1, rt_ms)}
        finally:
            release_frame(client, fid)

    def color_search_in_frame() -> dict[str, Any]:
        fid, _ = capture_frame(client, gray=0, bgra=1, ttl_ms=args.frame_ttl_ms)
        try:
            resp, rt_ms = timed_request(
                client,
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
            return {"extra": {"last_color_search_frame": data}, "metrics": color_frame_metrics(data, -1, rt_ms)}
        finally:
            release_frame(client, fid)

    def is_colors_in_frame() -> dict[str, Any]:
        fid, _ = capture_frame(client, gray=0, bgra=1, ttl_ms=args.frame_ttl_ms)
        try:
            table = f"{int(color_x)},,{int(color_y)},,{red},,{green},,{blue}"
            resp, rt_ms = timed_request(client, 69, fid, "is_colors", table, 1, tolerance, "pixel", args.frame_max_age_ms)
            data = require_ok(resp)
            return {"extra": {"last_is_colors_frame": data}, "metrics": color_frame_metrics(data, -1, rt_ms)}
        finally:
            release_frame(client, fid)

    def find_multi_in_frame() -> dict[str, Any]:
        fid, _ = capture_frame(client, gray=0, bgra=1, ttl_ms=args.frame_ttl_ms)
        try:
            table = f"0,,0,,{red},,{green},,{blue}"
            resp, rt_ms = timed_request(
                client,
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
            return {"extra": {"last_find_multi_frame": data}, "metrics": color_frame_metrics(data, -1, rt_ms)}
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

    def scenario_10_color_picks_frame_many() -> dict[str, Any]:
        fid, _ = capture_frame(client, gray=0, bgra=1, ttl_ms=args.frame_ttl_ms)
        try:
            points = "|".join(f"{color_x},{color_y}" for _ in range(10))
            resp, rt_ms = timed_request(client, 69, fid, "pick_many", points, "pixel", args.frame_max_age_ms)
            data = require_ok(resp)
            return {"extra": {"last_10_color_frame_many": data}, "metrics": color_frame_metrics(data, -1, rt_ms)}
        finally:
            release_frame(client, fid)

    results.append(measure("scenario_10_color_picks_old", args.scenario_count, scenario_10_color_picks_old))
    results.append(measure("scenario_10_color_picks_frame", args.scenario_count, scenario_10_color_picks_frame))
    results.append(measure("scenario_10_color_picks_frame_many", args.scenario_count, scenario_10_color_picks_frame_many))

    if not args.template_path:
        print("\n[frame image] skipped: pass --template-path <path_on_ios> to benchmark task68 image in frame")
        return results

    image_id: str | None = None
    try:
        image_id = load_template_object(client, args.template_path)
        if args.debug:
            print(f"loaded template image object for frame suite id={image_id}")

        fixed_region: tuple[int, int, int, int] | None = None
        probe_fid, probe_frame = capture_frame(client, gray=1, bgra=0, ttl_ms=args.frame_ttl_ms)
        try:
            probe_w = int(float(probe_frame[1]))
            probe_h = int(float(probe_frame[2]))
            probe_data = require_ok(client.request(
                68,
                probe_fid,
                image_id,
                0,
                0,
                0,
                0,
                args.match_acceptable,
                args.image_tune_fixed_scale,
                args.image_tune_fixed_scale,
                1.0,
                args.image_tune_fixed_skip,
                "pixel",
                args.frame_max_age_ms,
            ))
            if int(float(probe_data[0])) >= 0 and int(float(probe_data[1])) >= 0:
                fixed_region = padded_box(
                    (
                        int(float(probe_data[0])),
                        int(float(probe_data[1])),
                        int(float(probe_data[2])),
                        int(float(probe_data[3])),
                    ),
                    probe_w,
                    probe_h,
                    args.image_tune_fixed_pad,
                )
                if args.debug:
                    print(
                        "frame suite fixed image region="
                        f"{fixed_region[0]},{fixed_region[1]},{fixed_region[2]},{fixed_region[3]} "
                        f"skip={args.image_tune_fixed_skip} scale={args.image_tune_fixed_scale}"
                    )
            elif args.debug:
                print(f"frame suite fixed image region skipped: probe not found data={probe_data}")
        finally:
            release_frame(client, probe_fid)

        def find_image_in_frame() -> dict[str, Any]:
            fid, _ = capture_frame(client, gray=1, bgra=0, ttl_ms=args.frame_ttl_ms)
            try:
                resp, rt_ms = timed_request(
                    client,
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
                return {"extra": {"last_find_image_frame": data}, "metrics": image_frame_metrics(data, rt_ms)}
            finally:
                release_frame(client, fid)

        def scenario_2_image_5_color_old() -> dict[str, Any]:
            last_img = []
            for _ in range(2):
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
                last_img = require_ok(resp)
            last_color = []
            for _ in range(5):
                last_color = list(parse_rgb_response(client.request(23, color_x, color_y)))
            return {"extra": {"last_old_scenario_image": last_img, "last_old_scenario_color": last_color}}

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

        def scenario_2_image_5_color_frame_many() -> dict[str, Any]:
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
                points = "|".join(f"{color_x},{color_y}" for _ in range(5))
                last_color = require_ok(client.request(69, fid, "pick_many", points, "pixel", args.frame_max_age_ms))
                return {"extra": {"last_scenario_many_image": last_img, "last_scenario_many_color": last_color}}
            finally:
                release_frame(client, fid)

        def run_fixed_frame_checks(fid: str) -> tuple[dict[str, Any], dict[str, float]]:
            if fixed_region is None:
                raise RuntimeError("fixed image region unavailable; full-screen probe did not find template")
            fx, fy, fw, fh = fixed_region
            last_img: list[Any] = []
            image_match_total = 0.0
            image_native_total = 0.0
            image_matches: list[float] = []
            for _ in range(args.fixed_scenario_image_count):
                data = require_ok(client.request(
                    68,
                    fid,
                    image_id,
                    fx,
                    fy,
                    fw,
                    fh,
                    args.match_acceptable,
                    args.image_tune_fixed_scale,
                    args.image_tune_fixed_scale,
                    1.0,
                    args.image_tune_fixed_skip,
                    "pixel",
                    args.frame_max_age_ms,
                ))
                last_img = data
                m = image_frame_metrics(data)
                match_ms = m.get("match", 0.0)
                image_matches.append(match_ms)
                image_match_total += match_ms
                image_native_total += m.get("native_total", 0.0)

            last_color: list[Any] = []
            color_native_total = 0.0
            if args.fixed_scenario_color_count > 0:
                points = "|".join(f"{color_x},{color_y}" for _ in range(args.fixed_scenario_color_count))
                last_color = require_ok(client.request(69, fid, "pick_many", points, "pixel", args.frame_max_age_ms))
                color_metrics = color_frame_metrics(last_color)
                color_native_total = color_metrics.get("native_total", 0.0)

            metrics = {
                "checks_native_total": image_native_total + color_native_total,
                "image_match_total": image_match_total,
                "image_match_each": image_match_total / args.fixed_scenario_image_count if args.fixed_scenario_image_count > 0 else 0.0,
                "color_scan": color_native_total,
            }
            if len(image_matches) >= 1:
                metrics["image1_match"] = image_matches[0]
            if len(image_matches) >= 2:
                metrics["image2_match"] = image_matches[1]

            extra = {
                "fixed_region": [fx, fy, fw, fh],
                "image_checks": args.fixed_scenario_image_count,
                "color_picks": args.fixed_scenario_color_count,
                "last_fixed_scenario_image": last_img,
                "last_fixed_scenario_color": last_color,
            }
            return extra, metrics

        def build_fixed_frame_batch_ops(image_count: int | None = None, color_count: int | None = None) -> str:
            if fixed_region is None:
                raise RuntimeError("fixed image region unavailable; full-screen probe did not find template")
            fx, fy, fw, fh = fixed_region
            image_count = args.fixed_scenario_image_count if image_count is None else image_count
            color_count = args.fixed_scenario_color_count if color_count is None else color_count
            ops: list[str] = []
            for _ in range(image_count):
                ops.append(
                    "img,{image_id},{x},{y},{w},{h},{acceptable},{scale},{skip}".format(
                        image_id=image_id,
                        x=fx,
                        y=fy,
                        w=fw,
                        h=fh,
                        acceptable=args.match_acceptable,
                        scale=args.image_tune_fixed_scale,
                        skip=args.image_tune_fixed_skip,
                    )
                )
            if color_count > 0:
                points = "|".join(f"{color_x}:{color_y}" for _ in range(color_count))
                ops.append(f"pick_many,{points}")
            return "@@".join(ops)

        def measure_fixed_frame_checks_only() -> dict[str, Any]:
            values: list[float] = []
            failures = 0
            extras: dict[str, Any] = {}
            metric_values: dict[str, list[float]] = {}
            for _ in range(args.scenario_count):
                fid = ""
                try:
                    fid, _ = capture_frame(client, gray=1, bgra=1, ttl_ms=args.frame_ttl_ms)
                    started = time.perf_counter()
                    extra, metrics = run_fixed_frame_checks(fid)
                    elapsed = (time.perf_counter() - started) * 1000.0
                    values.append(elapsed)
                    extras.update(extra)
                    metrics["checks_total"] = elapsed
                    for key, value in metrics.items():
                        metric_values.setdefault(key, []).append(value)
                except Exception as exc:
                    failures += 1
                    if args.debug:
                        print(f"fixed-frame checks-only failed: {exc}")
                finally:
                    if fid:
                        release_frame(client, fid)
            for key, vals in metric_values.items():
                if vals:
                    extras[f"{key}_avg_ms"] = statistics.fmean(vals)
                    extras[f"{key}_p95_ms"] = percentile(vals, 95)
            extras["frame_pre_captured"] = True
            return summarize("scenario_fixed_frame_checks_only", values, failures, extras)

        def scenario_fixed_frame_full_lifecycle() -> dict[str, Any]:
            fid = ""
            scenario_started = time.perf_counter()
            capture_wall_ms = 0.0
            release_wall_ms = 0.0
            try:
                capture_resp, capture_wall_ms = timed_request(client, 66, 1, 1, args.frame_ttl_ms)
                capture_data = require_ok(capture_resp)
                fid = str(capture_data[0])
                extra, metrics = run_fixed_frame_checks(fid)
                release_started = time.perf_counter()
                client.request(67, fid)
                release_wall_ms = (time.perf_counter() - release_started) * 1000.0
                fid = ""
                scenario_total_ms = (time.perf_counter() - scenario_started) * 1000.0
                capture_metrics = frame_capture_metrics(capture_data)
                metrics.update({
                    "capture_wall": capture_wall_ms,
                    "capture": capture_metrics.get("capture", 0.0),
                    "bgra": capture_metrics.get("bgra", 0.0),
                    "gray": capture_metrics.get("gray", 0.0),
                    "release_wall": release_wall_ms,
                    "release": release_wall_ms,
                    "scenario_total": scenario_total_ms,
                })
                return {
                    "extra": extra,
                    "metrics": metrics,
                }
            finally:
                if fid:
                    release_frame(client, fid)

        def measure_fixed_frame_batch_checks_only() -> dict[str, Any]:
            values: list[float] = []
            failures = 0
            extras: dict[str, Any] = {}
            metric_values: dict[str, list[float]] = {}
            ops = build_fixed_frame_batch_ops()
            for _ in range(args.scenario_count):
                fid = ""
                try:
                    fid, _ = capture_frame(client, gray=1, bgra=1, ttl_ms=args.frame_ttl_ms)
                    resp, elapsed = timed_request(client, 70, fid, ops, "pixel", args.frame_max_age_ms)
                    data = require_ok(resp)
                    values.append(elapsed)
                    extras.update({
                        "fixed_region": list(fixed_region) if fixed_region else [],
                        "image_checks": args.fixed_scenario_image_count,
                        "color_picks": args.fixed_scenario_color_count,
                        "last_fixed_batch": data,
                    })
                    metrics = frame_batch_metrics(data, elapsed)
                    metrics["checks_total"] = elapsed
                    for key, value in metrics.items():
                        metric_values.setdefault(key, []).append(value)
                except Exception as exc:
                    failures += 1
                    if args.debug:
                        print(f"fixed-frame batch checks-only failed: {exc}")
                finally:
                    if fid:
                        release_frame(client, fid)
            for key, vals in metric_values.items():
                if vals:
                    extras[f"{key}_avg_ms"] = statistics.fmean(vals)
                    extras[f"{key}_p95_ms"] = percentile(vals, 95)
            extras["frame_pre_captured"] = True
            return summarize("scenario_fixed_frame_batch_checks_only", values, failures, extras)

        def scenario_fixed_frame_batch_full_lifecycle() -> dict[str, Any]:
            fid = ""
            scenario_started = time.perf_counter()
            capture_wall_ms = 0.0
            ops = build_fixed_frame_batch_ops()
            try:
                capture_resp, capture_wall_ms = timed_request(client, 66, 1, 1, args.frame_ttl_ms)
                capture_data = require_ok(capture_resp)
                fid = str(capture_data[0])
                resp, checks_wall_ms = timed_request(client, 70, fid, ops, "pixel", args.frame_max_age_ms, 1)
                data = require_ok(resp)
                fid = ""
                scenario_total_ms = (time.perf_counter() - scenario_started) * 1000.0
                capture_metrics = frame_capture_metrics(capture_data)
                metrics = frame_batch_metrics(data, checks_wall_ms)
                metrics.update({
                    "checks_total": checks_wall_ms,
                    "capture_wall": capture_wall_ms,
                    "capture": capture_metrics.get("capture", 0.0),
                    "bgra": capture_metrics.get("bgra", 0.0),
                    "gray": capture_metrics.get("gray", 0.0),
                    "release_wall": 0.0,
                    "release": 0.0,
                    "scenario_total": scenario_total_ms,
                })
                return {
                    "extra": {
                        "fixed_region": list(fixed_region) if fixed_region else [],
                        "image_checks": args.fixed_scenario_image_count,
                        "color_picks": args.fixed_scenario_color_count,
                        "auto_release": 1,
                        "last_fixed_batch": data,
                    },
                    "metrics": metrics,
                }
            finally:
                if fid:
                    release_frame(client, fid)

        def measure_fixed_frame_batch_scale(image_count: int, color_count: int) -> dict[str, Any]:
            values: list[float] = []
            failures = 0
            extras: dict[str, Any] = {
                "image_checks": image_count,
                "color_picks": color_count,
            }
            metric_values: dict[str, list[float]] = {}
            ops = build_fixed_frame_batch_ops(image_count, color_count)
            for _ in range(args.scenario_count):
                fid = ""
                scenario_started = time.perf_counter()
                try:
                    capture_resp, capture_wall_ms = timed_request(client, 66, 1, 1, args.frame_ttl_ms)
                    capture_data = require_ok(capture_resp)
                    fid = str(capture_data[0])
                    resp, checks_wall_ms = timed_request(client, 70, fid, ops, "pixel", args.frame_max_age_ms, 1)
                    data = require_ok(resp)
                    fid = ""
                    scenario_total_ms = (time.perf_counter() - scenario_started) * 1000.0
                    values.append(scenario_total_ms)
                    extras.update({
                        "fixed_region": list(fixed_region) if fixed_region else [],
                        "auto_release": 1,
                        "last_fixed_batch_scale": data,
                    })
                    capture_metrics = frame_capture_metrics(capture_data)
                    metrics = frame_batch_metrics(data, checks_wall_ms)
                    metrics.update({
                        "checks_total": checks_wall_ms,
                        "capture_wall": capture_wall_ms,
                        "capture": capture_metrics.get("capture", 0.0),
                        "bgra": capture_metrics.get("bgra", 0.0),
                        "gray": capture_metrics.get("gray", 0.0),
                        "release_wall": 0.0,
                        "release": 0.0,
                        "scenario_total": scenario_total_ms,
                    })
                    for key, value in metrics.items():
                        metric_values.setdefault(key, []).append(value)
                except Exception as exc:
                    failures += 1
                    if args.debug:
                        print(f"fixed-frame batch scale failed images={image_count} colors={color_count}: {exc}")
                finally:
                    if fid:
                        release_frame(client, fid)
            for key, vals in metric_values.items():
                if vals:
                    extras[f"{key}_avg_ms"] = statistics.fmean(vals)
                    extras[f"{key}_p95_ms"] = percentile(vals, 95)
            name = f"scenario_fixed_frame_batch_scale_i{image_count}_c{color_count}"
            return summarize(name, values, failures, extras)

        results.append(measure("task68_find_image_in_frame_with_capture", args.image_match_count, find_image_in_frame))
        results.append(measure("scenario_2_image_5_color_old", args.scenario_count, scenario_2_image_5_color_old))
        results.append(measure("scenario_2_image_5_color_frame", args.scenario_count, scenario_2_image_5_color_frame))
        results.append(measure("scenario_2_image_5_color_frame_many", args.scenario_count, scenario_2_image_5_color_frame_many))
        if fixed_region is not None:
            results.append(measure_fixed_frame_checks_only())
            results.append(measure("scenario_fixed_frame_full_lifecycle", args.scenario_count, scenario_fixed_frame_full_lifecycle))
            results.append(measure_fixed_frame_batch_checks_only())
            results.append(measure("scenario_fixed_frame_batch_full_lifecycle", args.scenario_count, scenario_fixed_frame_batch_full_lifecycle))
            image_counts = parse_int_list(args.fixed_scenario_image_counts) if args.fixed_scenario_image_counts else []
            color_counts = parse_int_list(args.fixed_scenario_color_counts) if args.fixed_scenario_color_counts else []
            if image_counts or color_counts:
                if not image_counts:
                    image_counts = [args.fixed_scenario_image_count]
                if not color_counts:
                    color_counts = [args.fixed_scenario_color_count]
                for image_count in image_counts:
                    for color_count in color_counts:
                        results.append(measure_fixed_frame_batch_scale(max(0, image_count), max(0, color_count)))
    finally:
        if image_id:
            release_template_object(client, image_id)

    return results


def run_image_tune_suite(client: TLinkautoClient, args: argparse.Namespace) -> list[dict[str, Any]]:
    if not args.template_path:
        raise RuntimeError("--suite image-tune requires --template-path <path_on_ios>")

    image_id = load_template_object(client, args.template_path)
    results: list[dict[str, Any]] = []
    try:
        frame_id, frame_data = capture_frame(client, gray=1, bgra=0, ttl_ms=5000)
        try:
            frame_w = int(float(frame_data[1]))
            frame_h = int(float(frame_data[2]))
            skips = parse_int_list(args.image_tune_skips)
            scales = parse_float_list(args.image_tune_scales)
            if not skips:
                skips = [0, 1, 2, 3, 4]
            if not scales:
                scales = [1.0]
            if args.debug:
                print(f"image-tune frame_id={frame_id} frame={frame_w}x{frame_h} template_id={image_id}")

            found_box: tuple[int, int, int, int] | None = None
            probe_resp = client.request(
                68,
                frame_id,
                image_id,
                0,
                0,
                0,
                0,
                args.match_acceptable,
                scales[0],
                scales[0],
                1.0,
                skips[0],
                "pixel",
                5000,
            )
            probe_data = require_ok(probe_resp)
            if int(float(probe_data[0])) >= 0 and int(float(probe_data[1])) >= 0:
                found_box = (
                    int(float(probe_data[0])),
                    int(float(probe_data[1])),
                    int(float(probe_data[2])),
                    int(float(probe_data[3])),
                )
                if args.debug:
                    print(f"image-tune found probe box={found_box} score={probe_data[6]}")
            elif "found_pad_" in args.image_tune_regions.lower():
                raise RuntimeError(f"found_pad_N requires a successful full-screen probe: {probe_data}")

            regions = parse_region_specs(args.image_tune_regions, frame_w, frame_h, args, found_box)
        finally:
            release_frame(client, frame_id)

        for region_name, rx, ry, rw, rh in regions:
            for skip in skips:
                for scale in scales:
                    values: list[float] = []
                    match_values: list[float] = []
                    scores: list[float] = []
                    failures = 0
                    found_count = 0
                    last_data: list[Any] = []
                    config_frame_id, _ = capture_frame(client, gray=1, bgra=0, ttl_ms=5000)
                    if args.debug:
                        print(f"image-tune config frame_id={config_frame_id} region={region_name} skip={skip} scale={scale}")
                    try:
                        for _ in range(args.image_tune_count):
                            started = time.perf_counter()
                            try:
                                resp = client.request(
                                    68,
                                    config_frame_id,
                                    image_id,
                                    rx,
                                    ry,
                                    rw,
                                    rh,
                                    args.match_acceptable,
                                    scale,
                                    scale,
                                    1.0,
                                    skip,
                                    "pixel",
                                    5000,
                                )
                                elapsed = (time.perf_counter() - started) * 1000.0
                                data = require_ok(resp)
                                last_data = data
                                values.append(elapsed)
                                try:
                                    score = float(data[6])
                                    scores.append(score)
                                    if int(float(data[0])) >= 0 and int(float(data[1])) >= 0:
                                        found_count += 1
                                except (IndexError, ValueError):
                                    pass
                                m = image_frame_metrics(data, elapsed)
                                if "match" in m:
                                    match_values.append(m["match"])
                            except Exception as exc:
                                failures += 1
                                if failures <= 3:
                                    print(f"image-tune failed region={region_name} skip={skip} scale={scale}: {exc}")
                    finally:
                        release_frame(client, config_frame_id)
                    region_pixels = (rw if rw > 0 else frame_w) * (rh if rh > 0 else frame_h)
                    name = f"image_tune_region={region_name}_skip={skip}_scale={scale:.2f}"
                    extra = {
                        "region_name": region_name,
                        "region_x": rx,
                        "region_y": ry,
                        "region_w": rw if rw > 0 else frame_w,
                        "region_h": rh if rh > 0 else frame_h,
                        "region_pixels": region_pixels,
                        "pixel_skip": skip,
                        "scale_min": scale,
                        "scale_max": scale,
                        "found_count": found_count,
                        "found_rate": (found_count / len(values)) if values else 0.0,
                        "score_avg": statistics.fmean(scores) if scores else 0.0,
                        "score_p50": percentile(scores, 50) if scores else 0.0,
                        "score_min": min(scores) if scores else 0.0,
                        "score_max": max(scores) if scores else 0.0,
                        "match_avg_ms": statistics.fmean(match_values) if match_values else 0.0,
                        "match_p95_ms": percentile(match_values, 95) if match_values else 0.0,
                        "last_task68": last_data,
                    }
                    results.append(summarize(name, values, failures, extra))

        if found_box is not None:
            fixed_x, fixed_y, fixed_w, fixed_h = padded_box(found_box, frame_w, frame_h, args.image_tune_fixed_pad)
            fixed_values: list[float] = []
            fixed_match_values: list[float] = []
            fixed_scores: list[float] = []
            fixed_failures = 0
            fixed_found_count = 0
            fixed_last_data: list[Any] = []
            if args.debug:
                print(
                    "image-tune practical fixed_region="
                    f"{fixed_x},{fixed_y},{fixed_w},{fixed_h} skip={args.image_tune_fixed_skip} "
                    f"scale={args.image_tune_fixed_scale}"
                )
            for _ in range(args.image_tune_count):
                practical_frame_id = ""
                started = time.perf_counter()
                try:
                    practical_frame_id, _ = capture_frame(client, gray=1, bgra=0, ttl_ms=5000)
                    resp = client.request(
                        68,
                        practical_frame_id,
                        image_id,
                        fixed_x,
                        fixed_y,
                        fixed_w,
                        fixed_h,
                        args.match_acceptable,
                        args.image_tune_fixed_scale,
                        args.image_tune_fixed_scale,
                        1.0,
                        args.image_tune_fixed_skip,
                        "pixel",
                        5000,
                    )
                    elapsed = (time.perf_counter() - started) * 1000.0
                    data = require_ok(resp)
                    fixed_last_data = data
                    fixed_values.append(elapsed)
                    try:
                        score = float(data[6])
                        fixed_scores.append(score)
                        if int(float(data[0])) >= 0 and int(float(data[1])) >= 0:
                            fixed_found_count += 1
                    except (IndexError, ValueError):
                        pass
                    m = image_frame_metrics(data, elapsed)
                    if "match" in m:
                        fixed_match_values.append(m["match"])
                except Exception as exc:
                    fixed_failures += 1
                    if fixed_failures <= 3:
                        print(f"image-tune practical fixed-region failed: {exc}")
                finally:
                    if practical_frame_id:
                        release_frame(client, practical_frame_id)
            results.append(
                summarize(
                    "scenario_image_fixed_region_capture_match",
                    fixed_values,
                    fixed_failures,
                    {
                        "region_name": f"found_pad_{args.image_tune_fixed_pad}",
                        "region_x": fixed_x,
                        "region_y": fixed_y,
                        "region_w": fixed_w,
                        "region_h": fixed_h,
                        "region_pixels": fixed_w * fixed_h,
                        "pixel_skip": args.image_tune_fixed_skip,
                        "scale_min": args.image_tune_fixed_scale,
                        "scale_max": args.image_tune_fixed_scale,
                        "found_count": fixed_found_count,
                        "found_rate": (fixed_found_count / len(fixed_values)) if fixed_values else 0.0,
                        "score_avg": statistics.fmean(fixed_scores) if fixed_scores else 0.0,
                        "score_p50": percentile(fixed_scores, 50) if fixed_scores else 0.0,
                        "score_min": min(fixed_scores) if fixed_scores else 0.0,
                        "score_max": max(fixed_scores) if fixed_scores else 0.0,
                        "match_avg_ms": statistics.fmean(fixed_match_values) if fixed_match_values else 0.0,
                        "match_p95_ms": percentile(fixed_match_values, 95) if fixed_match_values else 0.0,
                        "last_task68": fixed_last_data,
                    },
                )
            )
    finally:
        release_template_object(client, image_id)
    return results


def run_ocr_suite(client: TLinkautoClient, args: argparse.Namespace) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    region = (args.ocr_region_x, args.ocr_region_y, args.ocr_region_w, args.ocr_region_h)
    rect_data = ",,".join(str(int(x)) for x in region)
    custom_words = ",,".join(x.strip() for x in args.ocr_custom_words.split(",") if x.strip())
    languages = ",,".join(x.strip() for x in args.ocr_languages.split(",") if x.strip())
    levels = []
    if args.ocr_level in ("accurate", "both"):
        levels.append(("accurate", 0))
    if args.ocr_level in ("fast", "both"):
        levels.append(("fast", 1))

    for label, level in levels:
        try:
            data = require_ok(client.request(27, 2, level))
            results.append(
                summarize(
                    f"ocr_supported_languages_{label}",
                    [],
                    0,
                    {
                        "language_count": len(data),
                        "languages": data,
                    },
                )
            )
            if args.debug:
                print(f"ocr {label} supported_languages={','.join(str(x) for x in data)}")
        except Exception as exc:
            results.append(summarize(f"ocr_supported_languages_{label}", [], 1, {"error": str(exc)}))

        values: list[float] = []
        failures = 0
        text_counts: list[float] = []
        chars: list[float] = []
        last_data: list[Any] = []
        for i in range(args.ocr_count):
            debug_path = ""
            if args.ocr_debug_image_path:
                suffix = f"-{label}-{i}.jpg" if args.ocr_count > 1 else ""
                debug_path = args.ocr_debug_image_path + suffix
            started = time.perf_counter()
            try:
                data = require_ok(
                    client.request(
                        27,
                        1,
                        rect_data,
                        custom_words,
                        args.ocr_min_height,
                        level,
                        languages,
                        args.ocr_auto_correct,
                        debug_path,
                    )
                )
                elapsed = (time.perf_counter() - started) * 1000.0
                values.append(elapsed)
                last_data = data
                stats = ocr_result_stats(data)
                text_counts.append(stats["text_count"])
                chars.append(stats["chars"])
            except Exception as exc:
                failures += 1
                if failures <= 3:
                    print(f"ocr {label} failed: {exc}")
        region_name = "full" if region[2] <= 0 or region[3] <= 0 else f"{region[0]}_{region[1]}_{region[2]}_{region[3]}"
        results.append(
            summarize(
                f"ocr_{label}_region_{region_name}",
                values,
                failures,
                {
                    "ocr_level": label,
                    "ocr_region": list(region),
                    "ocr_languages": [x for x in args.ocr_languages.split(",") if x.strip()],
                    "ocr_auto_correct": args.ocr_auto_correct,
                    "ocr_min_height": args.ocr_min_height,
                    "text_count_avg": statistics.fmean(text_counts) if text_counts else 0.0,
                    "chars_avg": statistics.fmean(chars) if chars else 0.0,
                    "last_ocr_result": last_data,
                },
            )
        )
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark TLinkauto command latency from PC")
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, default=6000)
    parser.add_argument("--protocol", choices=["auto", "v1", "v0"], default="auto")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--suite", choices=["touch", "gesture", "screenshot", "match", "frame", "image-tune", "ocr", "all"], default="all")
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
    parser.add_argument("--image-tune-count", type=int, default=5)
    parser.add_argument("--image-tune-regions", default="full,50%,25%,custom", help="Comma list: full, custom, 50%%, found_pad_100, or label:x/y/w/h")
    parser.add_argument("--image-tune-skips", default="0,1,2,3,4")
    parser.add_argument("--image-tune-scales", default="1.0")
    parser.add_argument("--image-tune-fixed-pad", type=int, default=50)
    parser.add_argument("--image-tune-fixed-skip", type=int, default=1)
    parser.add_argument("--image-tune-fixed-scale", type=float, default=1.0)
    parser.add_argument("--fixed-scenario-image-count", type=int, default=2)
    parser.add_argument("--fixed-scenario-color-count", type=int, default=5)
    parser.add_argument("--fixed-scenario-image-counts", default="", help="Optional comma list for task70 scale benchmark, e.g. 1,2,3,5")
    parser.add_argument("--fixed-scenario-color-counts", default="", help="Optional comma list for task70 scale benchmark, e.g. 0,5,10")
    parser.add_argument("--ocr-count", type=int, default=5)
    parser.add_argument("--ocr-region-x", type=int, default=0)
    parser.add_argument("--ocr-region-y", type=int, default=0)
    parser.add_argument("--ocr-region-w", type=int, default=0)
    parser.add_argument("--ocr-region-h", type=int, default=0)
    parser.add_argument("--ocr-level", choices=["fast", "accurate", "both"], default="both")
    parser.add_argument("--ocr-languages", default="", help="Comma list, e.g. en-US,vi-VN. Empty lets Vision choose.")
    parser.add_argument("--ocr-custom-words", default="")
    parser.add_argument("--ocr-min-height", default="")
    parser.add_argument("--ocr-auto-correct", type=int, default=0)
    parser.add_argument("--ocr-debug-image-path", default="")
    args = parser.parse_args()

    client = TLinkautoClient(args.host, args.port, args.protocol, args.timeout)
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
        if args.suite == "image-tune" or (args.suite == "all" and args.template_path):
            all_results.extend(run_image_tune_suite(client, args))
        if args.suite in ("ocr", "all"):
            all_results.extend(run_ocr_suite(client, args))
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
