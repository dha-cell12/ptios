# C02d1 — helper RPC identity and single response slot

Date: 2026-10-25 (Asia/Bangkok). Baseline: `aec9902`; the user reported C02c3 built successfully before this slice.
Status: **build reported passed by the user before C02d2 (`3e9f798`); device qualification pending**.
Finding: **P0-12 prerequisite: correlate ownership before native effects and concurrent/event transport**.

## Result and scope

The helper client correlates each parsed socket reply with its command and transport request UUID, checks the requested session, and pins the helper instance returned by a successful start. Later requests carry that helper ID; a restarted or different helper cannot silently satisfy the existing client's session traffic. A protocol error envelope is accepted only when it has the same correlation fields. A successful start must have a valid helper/session identity and matching payload activeSessionId before binding.

The root runtime validates the status envelope helper/session, payload active session and nested native request owner before invoking policy/native dispatch. Previously it inspected activeSessionId after dispatch, allowing an inconsistent or different-session status to reach native work first. A pending native request must belong to a running state and contain a bounded string request ID. Existing replay fingerprint/reservation/policy/native-license handling is unchanged.

The helper replaces its nativeResponses dictionary with one response slot coupled to the existing one pending request. Under rpcCondition, validate active/pending session, request ID, any supplied helper ID, result dictionary and cancellation state before publishing. The first accepted result wins. A duplicate while the slot is pending acknowledges without overwriting; a late reply after consumption/cleanup receives no_pending_native_rpc. Arbitrary unknown IDs cannot accumulate response entries.

This does not enable event transport yet. The server still handles clients serially; status polling remains every 200 ms and each command opens a new socket. Blocking socket I/O/deadlines, bounded concurrent admission, event waiting/cursors and reconnect recovery remain separate P0-12 work. No latency/CPU/wakeup improvement or device RSS reduction is claimed. Production TrollStore and TouchPOC source are unchanged; both build workflows run the new shared test runner.

## Ownership, cancellation and cleanup

Publish a pending request only if its session still equals the active session after acquiring the condition. Include helperInstanceId in new nested request snapshots. Worker consumption/timeout cleanup requires the same pending request and session; old session cleanup cannot erase a newer session's slot. Reset request/response together before starting a session. Reject a new start while the current session is stopping, and broadcast rpcCondition on stop so the pending native worker can wake without waiting for its five/seven-second RPC wait deadline. License cancellation retains its existing broadcast path.

Slot admission and first-result publication share one lock. Cleanup releases both the request and response. The native waiter remains serialized and uses the existing timeout accounting and NSCondition wait behavior. Other state/metrics fields still use their existing ownership model; this is not a complete server lifecycle synchronization rewrite.

The gate checks a received snapshot; it is not an atomic cross-process promise that the helper cannot stop or time out just after validation. A completed native effect cannot be undone by rejecting its late response. Existing cooperative native cancellation and the session replay fence remain necessary. Durable exactly-once recovery across crashes/new sessions is not introduced.

## Compatibility and boundaries

Protocol version 1.0 and existing command/result fields remain. Updated clients pin helper identity automatically after start; existing helper versions already return outer helper/session fields. Older nested requests may omit helperInstanceId because their outer response is still pinned. Older clients may omit the helper field on a native response, but must supply the exact current session and pending native request. A present-but-invalid or mismatched helper field is rejected. The server also rejects any command carrying a different helper ID.

Identity strings must contain 1..64 UTF-8 bytes, including embedded NUL in comparisons; generated UUIDs fit. Missing, numeric or oversized ownership fields cannot authorize native work. This enforces correlation, not peer authentication: Unix socket permissions/peer credentials, deadlines, transport framing and process-restart recovery are unchanged. The single slot bounds retained response count; exact parsed-JSON/RSS bounds still depend on the existing transport cap and Foundation representation.

## Validation

- A new portable runner exercises 100k matching/mismatching helper/session/request tuples, explicit legacy helper omission, empty and exact/oversized fields, and embedded NUL without prefix aliasing.
- A new macOS fixture compiles actual production admission, native waiter, scoped cleanup and error-envelope methods extracted from the helper server, together with the actual identity header and protocol serializer. It covers wrong helper/session/request, old-session cleanup, first-result preservation/duplicate acknowledgment, no-pending/stopped rejection and eight concurrent response contenders.
- One hundred real condition/worker lifecycles cover success, cancellation wakeup, consumed-request late replies and slot release; status/start/reply tests cover pre-dispatch ownership, command/request correlation, legacy nesting and inactive native requests. The client's socket loop and full JavaScriptCore/server lifecycle are not executed by this fixture. Foundation/ARC/sanitizer execution and iOS/device qualification await macOS CI on this Windows host.
- Source guards verify condition-protected admission/finally unlock, single-slot storage, matching cleanup, pre-dispatch runtime validation, client binding and stop broadcast, plus both workflow entries. All 59 workflow runners (36 source-contract, 23 native), 521 source-grep assertions, standards-conforming assert preprocessing and git diff --check pass on Windows; 16 artifact-only checks require CI outputs. Windows does not compile or run the Foundation methods.

## Acceptance and next slice

Run rootfull/roothide helper mode, force helper restart/session replacement and delay or duplicate native replies. Verify mismatched status cannot inject, duplicate results cannot replace the first result, late/unknown replies do not retain payloads, and stop drains the pending worker before a new session starts. Compare successful native replies and license/policy denial behavior with the previous build. Measure actual cancellation and cleanup on device.

Next P0-12 work: deadline-bounded socket framing/connect/read/write and bounded server client ownership before introducing concurrent event waits; preserve session/request correlation, replay retirement and no repeated native effects. P1-40 invalidation, remaining P0-13 adapters and C01/C02 device/performance acceptance remain open.

The user reported C02d1 build `3e9f798` passed before C02d2. The transport I/O deadline slice is tracked in `IMPLEMENTATION-C02D2.md`; no independent macOS/device execution was performed on this Windows host.
