import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

const [bridge, h264, server, capture, remote, adaptive, policyRaw, benchmark, doc, build, troll] =
  await Promise.all([
    read("bridge-rs-new/src/main.rs"),
    read("stream-app/streamd/H264Stream.mm"),
    read("stream-app/streamd/POCSocketServer.mm"),
    read("stream-app/streamd/StreamCaptureSource.mm"),
    read("stream-app/streamd/RemoteBridgeAgent.mm"),
    read("shared/TLinkAdaptiveStreaming.mm"),
    read("license-task-policy.json"),
    read("scripts/Compare-TLinkStreamCapturePipeline.ps1"),
    read("docs/stream-rtc-control-v2.md"),
    read(".github/workflows/build.yml"),
    read(".github/workflows/stream-app.yml"),
  ]);

const policy = JSON.parse(policyRaw);
assert.ok(policy.task_features.stream.includes(93));
assert.match(server, /\{93, "stream"\}/);
assert.match(server, /TLinkH264HandleStreamControl/);
assert.match(server, /streamControlTask=93/);
assert.match(server, /streamRTPTimestamp=zxh2_capture_start_delta_v1/);

assert.match(h264, /gForceKeyframeMask/);
assert.match(h264, /force_keyframe/);
assert.match(h264, /kVTEncodeFrameOptionKey_ForceKeyFrame/);
assert.match(h264, /SCSetCapturePipelineMode/);
assert.match(capture, /coregraphics_legacy_per_frame_surface/);
assert.match(capture, /@"total_metrics"/);

assert.match(bridge, /fn rtcp_keyframe_requests/);
assert.match(bridge, /PictureLossIndication/);
assert.match(bridge, /FullIntraRequest/);
assert.match(bridge, /request_source_keyframe/);
assert.match(bridge, /task_line\(93/);
assert.match(bridge, /rtc_feedback_loop/);
assert.match(bridge, /"source": "rtc_bridge_v1"/);
assert.match(bridge, /rtc_source_sample_duration_us/);
assert.match(bridge, /capture_start_us/);
assert.doesNotMatch(bridge, /let mut last_frame_at: Option<Instant>/);

assert.match(remote, /streamPort = \[_profile isEqualToString:@"lan"\] \? 7003 : 7006/);
assert.match(adaptive, /isEqualToString:@"rtc_bridge_v1"/);

assert.match(benchmark, /set_capture_mode/);
assert.match(benchmark, /legacy/);
assert.match(benchmark, /accelerated/);
assert.match(benchmark, /total_p95/);
assert.match(benchmark, /pass_comparable/);
assert.match(doc, /Direct WebRTC inside the iPhone runtime is explicitly deferred/);
assert.match(build, /check-stream-rtc-control-v2\.mjs/);
assert.match(troll, /check-stream-rtc-control-v2\.mjs/);

console.log("Stream RTC Control v2 OK: source timing, PLI/FIR keyframes, RTC health feedback, remote profile and legacy/v2 benchmark wired");
