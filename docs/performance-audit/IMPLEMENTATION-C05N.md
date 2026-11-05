# C05n — Bound process-local AX query admission

Date: 2026-11-05 (Asia/Bangkok). Baseline: `ddb423ce`; user reported C05m build passed and requested continued implementation. Shared rootfull/roothide and production TrollStore snapshot/find/hit-test entries; TouchPOC excluded. Continues C05/P1-59.

## Eight synchronous query slots

Snapshot, find and hit-test now share one process-local eight-slot admission state. Acquire a stack lease after the preceding public validation/stop gates and before owner enqueue; find also acquires before building its query options. The lease stays charged while dispatch_sync waits, while the serial owner runs and through public result handling. Scope exit releases it once on normal/early return or unwind. No queued block captures the stack lease, and no per-call heap owner, timer or worker is added.

Overflow returns ui_ax_busy with partial=true/retryable=true before queue/native work. A refused lease cannot retire another caller's slot. An already stopped caller still receives cancellation first; existing find selector and hit-test request validation retain their precedence. Admitted query order, caller/local deadlines, cancellation gates, CF ownership and foreground/action/authority behavior retain their preceding source.

The state uses an atomic bounded counter and idempotent lease release. Its static lifetime covers synchronous callers. Advertise additive Task-77 max_pending_queries=8, document the shared limit in the public header/UI Tree v1 contract and update its manifest/check. Capability/foreground probes, private internal helpers and other processes do not share these slots. Task81 uses the find slot for target resolution; its subsequent mutation guards remain unchanged.

The limit bounds these public AX call scopes, not transport clients, external result retention or every process workload. An expired caller already waiting in dispatch_sync remains charged until its queued call retires; capacity is not recycled while that job still exists. This does not preempt a held owner, cancel an opaque RPC, add coalescing/reentry support, tune throughput for devices or automatically retry busy requests. Root/selector/string-output memory and device qualification remain open. C05/P1-59 remain partial; eight is a design bound, not a measured device optimum.

## Verification

Source guards require exactly three admissions at their specified public boundaries, one shared state and one advertised limit. Strip only those additions and validate the complete C05m AX hash before the preceding C05m/l/k/j/i/h/g/f/e/d/c/b/a chain. Public signatures are unchanged. Reuse the snapshot runner/workflows; runner count remains90, with a second portable executable in the existing runner.

Portable production-state/lease tests cover eight-slot saturation/ninth refusal, denied-owner isolation, replacement/recovery, scope/C++ unwind, state isolation,100k sequential lifecycles,160k concurrent attempts and concurrent duplicate release, with zero final charges. A static assertion fixes the UI Tree v1 limit at eight.

Extend the attribute Foundation/CF/CoreGraphics/ARC/ASan/UBSan executable with actual snapshot/find/hit-test entries sharing the production state. Manual saturation verifies uniform busy/error flags, no rejected dispatch/native work, validation/cancellation precedence, recovery with seven other held leases and CF balance. Controlled inline delivery checks NS/C++ lock/preparation/hit error/unwind retirement; it does not qualify exception propagation across real GCD boundaries.

Sixteen real serial-GCD/eight-thread cycles hold the first operation in its root setter with an owned CF root. Seven other mixed calls queue behind it. Each public method must reject an additional call without enqueue while all eight slots remain owned. Release the owner, drain all eight actual entries and require zero charges, balanced CF/value owners and retired source arrays. AX/screen/clock/providers remain controlled; no real private framework, service or app is controlled. The queue is real, but device IPC/preemption/throughput remain unqualified.

Existing ordinary/frozen query/hit-test cases remain enabled. Capability comparison explicitly adds only max_pending_queries=8 to its frozen expected graph and continues full comparison of all preceding fields. UI Tree v1 source checks require the new limit/error marker.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, staged AX/header restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Portable admission and existing100k window cases pass. Extended Apple/iOS compilation and Foundation/ARC/sanitizer execution require macOS CI. Device qualification remains pending.
