# Stream RTC Control v2

Status: implemented for the existing desktop bridge and TrollStore `streamd`
transport. Direct WebRTC inside the iPhone runtime is explicitly deferred.

The media path remains:

```text
iPhone streamd -> TCP ZXH2 (7003/7006) -> desktop bridge -> WebRTC peer
```

This phase improves that path without adding a WebRTC framework, ICE/TURN
client, or a new foreground requirement to the iPhone binary.

## Source timing

The bridge derives `Sample.duration` from consecutive ZXH2
`capture_start_us` values instead of desktop TCP packet-arrival time. Valid
source deltas are bounded and smoothed; missing, reversed, or implausible
timestamps fail back to the previous duration and increment a diagnostic
counter. This prevents network burst/jitter from being converted into RTP
playback jitter.

ZXH2 capture, capture-done, encode-done, and device-send fields are also
parsed by both LAN and remote bridge paths. The device pipeline duration is
fed into adaptive-streaming health feedback.

## Receiver feedback

The desktop WebRTC sender reads compound RTCP and recognizes:

- PSFB PLI (`PT=206`, `FMT=1`);
- PSFB FIR (`PT=206`, `FMT=4`).

Requests are rate-limited to one source action per 250 ms, then sent through
licensed task `93` using schema `stream_control_v2` and action
`force_keyframe`. `streamd` keeps a per-port atomic bit and forces the next
VideoToolbox frame on that port to be a keyframe. Counters appear in task `60`
and task `93 status`.

Once per second, the bridge submits task `94` feedback with source
`rtc_bridge_v1`: observed FPS/bitrate, timestamp fallback count, device
pipeline latency, and stall state. The existing bounded hysteresis and thermal
ceiling remain authoritative.

For remote WSS sessions, the iPhone pump now respects the requested profile:
`lan` uses 7003 and `wan` uses 7006. This matches the desktop profile/port
selection instead of always opening 7006.

## Runtime controls and benchmark

Task `93` supports `force_keyframe`, `set_capture_mode`, and `status`.
`set_capture_mode` exists for controlled device A/B qualification and accepts
`legacy`, `accelerated`, or `auto`. The comparison command is documented in
`stream-capture-pipeline-v2.md` and implemented by
`scripts/Compare-TLinkStreamCapturePipeline.ps1`.

Task `97` publishes:

```text
streamControlTask=93
streamControlSchema=stream_control_v2
streamControlActions=force_keyframe,set_capture_mode,status
streamRTCPFeedback=pli_fir_to_task93_v1
streamRTCHealthFeedback=task94_rtc_bridge_v1
streamRTPTimestamp=zxh2_capture_start_delta_v1
```

## Deferred scope

Direct WebRTC on iPhone is not part of v2. A future phase can evaluate it only
after the current bridge path has device evidence for A/B capture cost, RTP
timing, keyframe recovery, long-session memory, and thermal behavior.
