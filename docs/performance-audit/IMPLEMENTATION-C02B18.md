# C02b18 — structured frame capture input and publication rollback

Date: 2026-10-25 (Asia/Bangkok). Baseline: `62a9c90`; the user reported C02b17 built successfully before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.
Finding: **P0-13, captureFrame input portion**. Response parsing, image creation/other adapters and helper transport/config/dedupe remain open.

## Result and scope

Root captureFrame prepares a structured channel/TTL/owner request and calls one licensed task-66 entry. RAW and typed callers share the same capture, pixel/memory admission, BGRA/gray conversion, owner assignment, store publication and legacy body formatter. This avoids the full input task string, RAW dispatch, CF reply stream and captured response vector for this method.

The legacy fourteen-field body, fifteen reply parts and JS metadata enrichment remain. The task still builds and parses its compatibility reply, and JS still reads the metadata columns; this slice does not remove response parsing. The bounded owner-suffix formatter/parser also remains to preserve sanitation, delimiter overlap, truncation and actual UTF-8/NUL behavior. The original wire request fits within 313 UTF-16 units under the existing owner caps, below the 8192-unit/32-KiB admission ceilings.

Production TrollStore and TouchPOC source are unchanged. No measured allocation/latency/RSS improvement or new capture backend is claimed.

## Policy and compatibility

- Keep option intValue conversions/defaults. Gray and BGRA are interpreted as nonzero booleans; requesting neither still produces both. TTL <= 0 uses 1000 ms and values above 5000 ms clamp to 5000 ms. RAW retains longLongValue parsing and its compute admission before parsing. Numeric callers share the same two-request compute gate and normalized policy.
- Keep default empty session/run and legacy runtime, including missing/empty owner fields and trailing whitespace. Input validation examines the actual encoded suffix bytes before the license gate. Prefix fields are bounded ASCII; the owner fields retain the existing 96-unit cap.
- Keep frame geometry/stride/scale, pixel and memory limits, immutable publication/count eviction, monotonic TTL/expiry and the published legacy wall timestamp. Gray-only capture keeps its historical format/stride fields. Capture and conversion paths remain shared; no extra screenshot is taken.
- Keep fourteen body fields and their order/precision: ID, geometry, scale, pixel/BGRA labels, channel flags, wall timestamp and four timing columns. The controlled-clock fixture compares all body columns except the distinct monotonically assigned IDs, plus stored owner/TTL/channel metadata.

## Authority, output and transfer of ownership

The typed entry creates the same ordinary caller child budget and enforces stop and the 1024-byte creation-response floor before exactly one task-66 license gate, followed by another stop check. Task 66 retains its caller timeout; this slice adds no C01-local timeout. It keeps owner/token/output limits and uses no response capture sink.

The core reports the newly published ID directly, before formatting its successful body. The task commits only after its compatibility result is constructed and the final output/stop check passes. Cancellation, expiry, output overflow or an NS/C++ fault after publication therefore attempts direct cleanup in finally. Cleanup uses the existing exempt context, even after the ordinary call has stopped. It targets only this call's ID; IDs are not reused, so owner-token formatting cannot make it remove another allocation. If the ID has already expired or been evicted, cleanup is a harmless no-op.

This also covers late exceptions/oversized replies where recovering the ID from a wire buffer could fail. Cleanup failures are contained as in the previous best-effort rollback path; ordinary active expiry remains a fallback. No rollback of unrelated capture/engine state or hard completion guarantee is claimed. Capture/render/CV and owner-queue operations remain opaque/cooperative and can overrun the caller before the final check.

## Validation

- All 56 workflow runners pass on Windows: 36 source-contract and 20 native runners. The event runner initially hit EPERM deleting its already-passed executable; rerunning that runner succeeds without source changes. All 521 direct workflow source-grep commands pass; 16 artifact-only checks require CI outputs.
- Portable storage coverage adds 100k TTL normalization cases and exact zero/one/5000/5001/saturated boundaries. Existing frame/image release, geometry/ledger, 20k storage lifecycle and 8 x 10k reservation cases remain.
- The actual Foundation bridge/entry fixture adds 160 frozen pre-C02b18 JS/RAW comparisons for flags, TTL, owner sanitation/encoding/truncation and exact metadata/results/tracking. It also checks capture/store errors, one task-66 gate, caller deadline, gate-time cancellation/expiry, the 1024-byte floor, NS/C++ faults before/after publication and rollback on cancellation/expiry/output overflow. Success keeps the published frame; failed publication transfer leaves no live fixture allocation.
- The actual capture/store fixture adds 48 frozen handler versus numeric comparisons with controlled elapsed/wall clocks and distinct real store IDs. It uses real CoreGraphics image/provider ownership, doubled Screen/renderer/CV, and tests compute busy, capture failure, pixel/memory rejection, render/gray failure and failed publication with zero final image resources/charges. It does not qualify real OpenCV conversion or display capture.
- All-host fixture extraction includes the actual owner/parser/core and checks entry dependencies, publication cleanup and macro-independent booleans. The matcher fixture now ends before the adjacent numeric capture adapter, with a guard against importing capture types/helpers. Standards-conforming assert preprocessing passes the existing fixtures and the new capture fixture, with a rejecting negative control.
- **New Foundation/macOS execution, ASan/UBSan, iOS builds, real capture/OpenCV and device measurements were not run on this Windows host.** The expanded branches await macOS CI/device qualification.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare JS captureFrame with RAW task 66 for gray/BGRA/default flags, TTL boundaries, owner encoding, geometry/metadata and capture/store failures. Exercise cancellation/deadline during capture, late publication faults, low/overflowing output budgets and concurrent release/expiry/eviction. Verify no failed call leaves an owned published frame and existing readers remain valid; measure bridge cost separately from capture/conversion and memory pressure.

Continue remaining P0-13 creation/response/other adapters, P0-12 event-driven helper RPC, P1-40 policy snapshots and P1-41 byte-bounded dedupe. C01/C02 performance/device acceptance remains open.
