# C02c3 — bounded streaming helper RPC fingerprints

Date: 2026-10-25 (Asia/Bangkok). Baseline: `af250da`; the user reported the corrected C02c2 build passed before this slice.
Status: **build reported passed by the user before C02d1 (`aec9902`); device qualification pending**.
Finding: **P1-41, application-owned fingerprint buffer removed; Foundation allocation/latency qualification remains**.

## Result and scope

Helper request fingerprints now send sorted JSON through a synchronous NSOutputStream into an incremental SHA-256 context. The application no longer calls dataWithJSONObject or constructs a complete NSData/NSString for argument fingerprinting. The sink stores only digest state and counters, borrows the serializer's current bytes for the duration of write, and never owns a payload buffer. Native task policy, request identity reservation, response serialization, replay limits and retirement behavior are unchanged.

The production implementation lives in shared/TLinkHelperRPCFingerprint.mm and is linked into pccontrol and the macOS helper replay test. A separate portable header owns the byte/update policy. Production TrollStore and TouchPOC source are unchanged; both existing CI workflows continue running the helper replay safety runner.

This changes the application's sink, not Foundation's JSON implementation. Foundation may allocate temporary strings, sorted key collections or even a complete internal serialization buffer before writing. No bound on Foundation internals, total process peak memory, parser depth, CPU time or a measured RSS reduction is claimed. It remains a synchronous full traversal on every new or duplicate poll. The input argument graph and cached reply serialization also still exist. Supported-OS allocation profiling is required before calling P1-41 fully qualified.

## Compatibility and limits

Use NSJSONWritingSortedKeys exactly as C02c2 did, and hash the bytes supplied by the same Foundation JSON serializer. Successful output is intended to produce exactly the same 32-byte digest as one-shot SHA-256 of the former sorted JSON data. Arrays, scalar number encoding, dictionary key order, escaping, Unicode and embedded NUL therefore continue following Foundation JSON behavior rather than a new custom JSON encoding.

The feed admits at most 1 MiB, checked with subtraction before processing each write. A write exceeding the remaining limit rejects the entire write; no partial oversize prefix is accepted as a successful fingerprint. SIZE_MAX input lengths reject before pointer arithmetic. Digest updates are at most 4096 bytes and use the input synchronously without copying it. Invalid pointers, failed update callbacks and exceeded limits make the feed terminal. Empty or already-finalized feeds cannot finalize again.

Open the stream before calling writeJSONObject, check the serializer's positive byte count against the sink's accepted bytes, and publish the candidate digest only after SHA finalization succeeds. Exceptions, encoding errors and oversized output return false; they do not publish a partial digest or invoke native execution. Always close in finally. The internal stream uses no run-loop scheduling or asynchronous writes. Optional stats report this sink's accepted bytes, writes, updates and failure state, without claiming to measure Foundation allocations.

The stream API is documented by Apple as [NSJSONSerialization writeJSONObject:toStream:options:error:](https://developer.apple.com/documentation/foundation/jsonserialization/writejsonobject(_:to:options:error:)); actual SDK and serializer behavior is exercised by the new macOS fixture rather than assumed from the portable tests.

## Validation

- The portable helper replay runner adds 100k chunk-partition comparisons against an independent byte hash oracle. Boundaries cover exact 1-MiB input, 4096-byte updates, one extra byte, SIZE_MAX rejection, null input/update callback, update failure after a completed chunk, empty input and calls after finalization. Existing 100k replay FIFO/ledger tests remain.
- The expanded macOS fixture compares 1500 real stream fingerprints against the previous one-shot Foundation JSON + SHA result, including sorted nested dictionaries, large integers, fractional values, booleans/null, escapes, Unicode and embedded NUL. Exact 1-MiB output and oversize/non-JSON/NaN/infinity failures verify accepted counts and unchanged caller digest on failure. The existing known SHA vector and replay/native-effect tests remain.
- Source guards require stream serialization, the bounded digest feed, finally-close and production Makefile linkage, and reject application-owned full JSON/memory-stream buffering in the fingerprint implementation. The same runner now links the actual shared .mm on macOS. Actual Foundation/ASan/UBSan and iOS execution remain pending on this Windows host.
- All 58 workflow runners (36 source-contract, 22 native), 521 source-grep assertions, standards-conforming assert preprocessing and git diff --check pass on Windows; 16 artifact-only checks need CI outputs. Windows does not compile or execute the Foundation stream.

## Acceptance and next work

Run both rootfull/roothide builds and the macOS fixture. Compare old/new digests on actual helper traffic, especially screenshot/OCR argument mixes and boundary escapes, then confirm replay/collision/retired identity behavior. Use Allocations and latency traces to determine whether supported Foundation versions internally buffer the entire JSON and whether the application sink reduces transient retention. Do not infer device RSS savings from sink byte counters.

Continue P0-12 event-driven helper transport with session/request ownership, reconnect ordering and no repeated effects; P1-40 asynchronous/memory-only invalidation; remaining P0-13 adapters; and P1-41 Foundation/device allocation qualification. C01/C02 performance/device acceptance remains open.

The user reported C02c3 build `aec9902` passed before C02d1. No independent macOS/device run was performed on this Windows host. The helper identity/response-slot prerequisite is tracked in `IMPLEMENTATION-C02D1.md`.
