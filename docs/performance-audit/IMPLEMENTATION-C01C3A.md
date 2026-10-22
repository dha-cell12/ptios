# C01c3a — explicit frame-backed root Vision

Date: 2026-10-23 (Asia/Bangkok). Baseline: `5ae231b`; user reported the C01c2 build plus Vision SDK warning corrections passed before this slice.
Status: **source implemented; new macOS/iOS build and device qualification pending**.

## Scope

Rootfull/roothide Vision can now explicitly read an existing task-66 BGRA frame. This implements an opt-in reuse route for P1-28 and part of P1-39. Existing task-27 subtask 1 retains its capture/orientation behavior. Color already has explicit task-69 frame APIs; they are not duplicated here. Their remaining validation/scan budgets and modern Image.xm matching remain C01c3b. Upstream queue isolation and the rest of C01 are still open.

Production TrollStore OCR/color paths are unchanged. Subtask 5 is already its Vision bridge probe, so the new root route uses **subtask 6**. It is a root capability, not a cross-runtime selector. TouchPOC is excluded. Native JS `ocrFrame` remains its existing Tesseract route; this slice exposes Vision frame selection through the raw protocol and Python client.

## Protocol and freshness

The additive request is:

```text
276;;x,,y,,width,,height;;custom_words;;minimum_height;;level;;languages;;correct;;debug_path;;frame_id;;pixel|point;;max_age_ms
```

There must be exactly 11 fields after task 27, including subtask 6. The first eight fields have the same configuration meanings as legacy subtask 1. `frame_id` is a positive signed-32-bit handle; `max_age_ms` is an integer in 0..5000, with zero using the existing 1000 ms default. Both integer tokens are fully checked rather than accepting trailing junk or overflow. Coordinate mode must be exactly `pixel` or `point`.

Point coordinates multiply by the **stored frame scale**, then snap to the nearest integer pixel as existing frame adapters do. Negative/nonfinite ROI values fail. A snapped zero width/height extends to the remaining edge; positive oversized dimensions clip to the edge. Origins outside the canvas fail. C01c1 limits remain: 8192 per axis, at most 8,388,608 source pixels, at most 4,194,304 ROI pixels, two Vision contexts, eight-second cooperative request budget, bounded observations/output and inherited cancellation.

Results keep `text,,x,,y,,width,,height` observations joined with `;;`. Coordinates are absolute **stored-frame pixels**, including point-input calls. No age/engine fields are appended to observation lists. The frame canvas is authoritative: the adapter does not read the current device orientation or rotate that canvas a second time. Physical screen/orientation mapping still needs device qualification.

A missing, released, hard-expired, over-max-age or BGRA-less frame returns an explicit `-1;;vision_frame_*` error. There is **no capture fallback**. Hard TTL and max-age are checked at admission; an already-admitted immutable image remains valid if the store entry is later released/expired. A slow OCR can therefore finish after that admission age/TTL. This route describes an explicit snapshot, not a promise of fresh pixels at result time.

## Ownership and memory

`TLinkCreateVisionImageFromFrame` obtains one immutable shared snapshot under the existing short store queue boundary and validates source geometry/stride/payload length. Provider/image construction runs outside the store queue. It wraps the original BGRA storage in a CGDataProvider and CGImage using the same BGRA bitmap description as frame capture. No application-level pixel clone, gray conversion, bitmap render or screenshot is performed by this adapter.

The provider callback owns a shared reader. That reader retains the **whole original frame and its existing byte charge**, including any gray payload, until the final CG/CI/Vision owner releases it. Erasing/evicting/expiring the store entry cannot invalidate those bytes or prematurely free their reservation. Failed holder/provider/color-space/image creation drops any acquired ownership; cancellation after image creation releases the image before returning an error. The task's existing finally releases its owned image on success, error and exception.

The original B02 frame/image byte limits still account for retained readers. There is no second payload reservation for the provider because it holds the same original payload. CoreGraphics/CoreImage/Vision scratch, metadata and caches remain outside that private ledger. Source code establishes reuse of the application buffer, not zero framework allocations, a process-RSS bound or a measured latency/energy saving.

The helper briefly uses the existing two-slot image compute gate for lookup/provider preparation; the existing Vision context spans parsing, frame admission, request execution, extraction and optional debug output. Synchronous store/opaque framework work can still overrun the cooperative deadline. No hard eight-second TCP completion guarantee or new worker-queue isolation is claimed.

## Python usage

`TLinkauto.ocr_from_frame(frame_id, region=(0,0,0,0), coord="pixel", max_age_ms=1000, ...)` sends task 27.6. Its recognition options match `ocr(...)`, and it returns the same `(ok, observations/error)` convention. It uses the existing v0/v1 transport and validates the five-field observation shape. It does not create or release a frame for the caller.

Example with explicit low-level capture/release (rootfull/roothide):

```python
from tlinkauto import datahandler

client.s.send(datahandler.format_socket_data(66, 0, 1, 5000))
ok, captured = datahandler.decode_socket_data(client.s.recv(1024))
if not ok:
    raise RuntimeError(captured)
frame_id = int(captured[0])
try:
    # Other task-69 color checks may use this same frame_id/canvas.
    ok, text = client.ocr_from_frame(
        frame_id, region=(10, 20, 200, 100), max_age_ms=5000,
        languages=["en-US"])
finally:
    client.s.send(datahandler.format_socket_data(67, frame_id))
    client.s.recv(1024)
```

Choose TTL/max-age deliberately; admission after expiry fails and the caller decides whether to capture another frame. A frame created with gray only cannot serve this BGRA provider route.

## Validation and pending acceptance

Windows validation passes **36 source-contract runners, 17 native runners A01–C01c3a and 528 TrollStore source grep assertions**. The new portable suite covers strict frame/age fields, 100,000 pixel/point/round/clip plans, geometry/resource boundaries and immutable charged-reader semantics. Python tests use the actual client and transport with fragmented socket responses, verifying exact v0/v1 requests, observation fields, errors and input validation.

The macOS image-storage fixture now compiles the actual provider against the actual store/payload/dispatch core. Real CoreGraphics data verifies bytes and retained ownership after store release, final charge cleanup, failed provider/image creation, max-age rejection/recovery and missing BGRA. Its existing OpenCV storage double remains; the new provider accesses BGRA vector storage.

The macOS Vision fixture compiles the actual provider and task/manager against the actual payload type with a controlled snapshot lookup, clock and Vision execution. It checks point-to-pixel ROI, unchanged observation fields, no capture or live orientation lookup, reader retention when the entry is removed during manager initialization, missing/invalid/stale frame errors and zero final frame charges. The production store queue itself is exercised by the separate image-storage fixture. Real OCR accuracy and UIKit debug rendering are not exercised by these doubles.

**The expanded macOS fixtures and iOS build have not run on this Windows host.** Required acceptance:

1. Build rootfull/roothide and run both workflow suites with strict warnings/sanitizers. Verify a failed provider/image creation does not leak frame charges and subsequent requests recover.
2. Capture task 66 with BGRA enabled; use that ID for task 69 and task 27.6. Compare text boxes to known frame patterns at @2x/@3x and every orientation. Confirm point input resolves using captured scale and output always remains in frame pixels. Rotate the device after capture and verify the chosen canvas remains consistent.
3. Exercise max-age/TTL boundaries, released/missing IDs, gray-only frames, integer/ROI errors and admission contention. Check no hidden screenshot fallback and no added response metadata. Verify task-27 subtask 1 still invokes its prior fresh-capture path.
4. Release/expire a frame while Vision is running. The admitted snapshot must remain valid and charged; after reader cleanup, charges must return to the store's remaining live payloads. Measure this with Allocations/VM Tracker, not only map entry counts.
5. Measure capture-once/color/OCR workflows versus repeated task-27 captures with the same images and settings. Record accuracy, latency, RSS/CPU/energy and cooperative-deadline overrun before claiming performance gains.

Next: C01c3b remaining frame-color validation/scan budgets and modern image matcher preparation/scale/work budgets. The whole C01 group remains open.
