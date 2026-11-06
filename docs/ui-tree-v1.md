# TLinkauto UI Tree v1

UI Tree v1 adds a shared, private-AXRuntime accessibility snapshot to the rootfull and TrollStore runtimes. It is additive: legacy tasks and Smart Wait v1 visual locators keep their existing wire responses.

## Runtime routes

- Rootfull and roothide TCP UI-tree requests enter through `tlinkautod`, then tasks `77`–`81` execute in the SpringBoard script bridge. In-process scripts use the same shared core there. Other TCP tasks keep their existing routing.
- The SpringBoard bridge reads its own `_accessibilityFrontMostApplication` (the same in-process route as task `34`) and resolves that application's PID before querying AX. A nil foreground result fails closed during transitions. The daemon-side `AXSpringBoardServer.focusedAppPID` and SpringBoardServices paths remain for other callers, but are not the UI-tree TCP route on roothide. Task `77` exposes `foreground_probe` and reports `service=springboard_script_bridge`. Roothide retains the `rootfull` wire runtime marker.
- TrollStore TCP requests and scripts run in `streamd`. `StreamControl.app` may remain in the background while the target application is foreground.
- TrollStore foreground discovery uses resolver v12. Its normal path dynamically loads `AXSpringBoardServer`, reads `focusedAppPID` (with `topEventPidOverride` as a filtered fallback), maps that one PID to its application bundle and validates only that AX tree. The direct PID is authoritative: after an app switch it is observed twice, and a temporarily unavailable AX tree is retried on that same PID after 35 ms and 90 ms. If the tree is still unavailable the resolver reports `ui_ax_springboard_target_not_ready`/`transitioning`; it never lets a stale MRU candidate replace a valid direct PID. Screenshot fingerprints are skipped on this path and remain confined to the v10 compatibility fallback, which is entered only when the private server, selector or PID mapping is unavailable. Candidates must be visible application bundles; hidden/background services such as `assistivetouchd` and TLink's hosted UI service are rejected. Diagnostics expose direct resolver state, PID values, retry count and duration.
- The accepted context carries a monotonic `generation`, `state`, `verification_count`, and resolver timing. The cache is scoped to verified state rather than an unconditional time window; task 81 still revalidates context before injecting input.
- `TLinkUIService` is not used. UI Tree does not create a scene or window.

The first contract is a flat accessibility snapshot because numeric AX attribute `3015` does not expose a proven, stable parent/child relationship. Hierarchy is deliberately reported as unavailable.

## Tasks

All request objects use base64-encoded UTF-8 JSON and successful responses contain base64-encoded UTF-8 JSON.

- `77`: capability and entitlement diagnostics.
- `78`: foreground snapshot.
- `79`: foreground selector lookup.
- `80`: element hit-test using `{ "x": 10, "y": 20 }`.
- `81`: context-validated selector lookup and native tap.

Tasks 77-81 require the `automation` license feature. Task 81 rechecks foreground bundle ID and PID before injecting the tap. It fails with `ui_context_changed` instead of tapping a stale coordinate.
Task 81 also rejects any selector result whose snapshot is `partial` or `truncated` (or lacks those completeness flags) with `ui_snapshot_incomplete`. Read-only tasks 78/79 still return the incomplete result and its diagnostics. `waitUntilElementGone` treats an incomplete result as inconclusive: it retries under Smart Wait's bounded timeout instead of reporting that the element disappeared.
For dense screens, callers may raise `maxElements` (up to 1,000) and `queryTimeoutMs` (up to 3,000) in Smart Wait options. If every read remains incomplete, disappearance times out with `lastError=ui_snapshot_incomplete`.

Selectors support `text`, `identifier`, `role`, `index`, `visibleOnly`, `clickableOnly`, `caseSensitive`, and `match` (`contains`, `exact`, or `prefix`). Snake-case option aliases are accepted.
Every find or tap selector must contain a non-empty `text`, `identifier`, or `role`; an index by itself is rejected so an empty selector can never tap the first element accidentally.

AX frames and activation points use UIKit points. Task 81 converts the selected activation point to TLink's native-pixel HID coordinate space immediately before dispatch.

## Limits and safety

- Default 250 elements; hard maximum 1,000.
- Snapshot/find/tap snapshots limit each accepted row's label, value, identifier and role to 65,536 UTF-8 bytes. Task 77 advertises `max_snapshot_string_utf8_bytes=65536`. Oversize strings or unrepresentable conservative JSON/base64 estimates return `ui_response_too_large` with `partial=true`; text is not silently truncated. The existing caller output budget may reject smaller results. Filtered rows are not admitted. UTF-16 length is checked first to avoid a full encoding-size scan of an obviously oversized string. This does not bound provider-owned AX strings/root materialization or arbitrary result metadata.
- Task 80 hit-test uses the same per-field text cap and checked conservative output estimate. Task 77 advertises `max_hit_test_string_utf8_bytes=65536`. Field oversize returns `ui_response_too_large` with `partial=true` while the caller budget remains live; text is not truncated. Output-budget overflow retains the native stop reason and existing public stop/error translation. Conservative metadata allowance can reject a compact reply under a small output budget, including a reply with no found element.
- Legacy UI-task success replies (including capability Task 77) have a hard 1,048,576-byte wire ceiling, advertised as `hard_max_success_wire_bytes`. The codec checks the exact JSON/base64/framing size before base64 and selects `ui_response_too_large` on refusal. Bound native output budgets can reject smaller replies and retain their existing overflow/stop handling. The synchronous JSON writer separately caps its accepted-byte buffer at 786,426 bytes (`hard_max_json_bytes`); it never returns a rejected partial prefix. Foundation internal allocations and failed-operation error lines remain outside these application buffer/success-wire caps. Output failure does not undo a committed Task 81 tap or trigger a retry.
- Snapshot/find/hit-test share at most eight running or queued calls per process. Overflow returns `ui_ax_busy` with `partial=true` and `retryable=true` before owner enqueue; callers choose whether to retry. Task 77 advertises `max_pending_queries=8`. Capability/foreground probes and separate processes do not share this count. Admitted calls stay serialized and retain their existing deadlines.
- `max_scanned_elements` / `maxScannedElements` independently bounds serialized source nodes, including filtered and invalid nodes. Default 4,096; values clamp to 1–16,384. Set it in snapshot options or a find/tap/Smart Wait selector. Task 77 advertises `default_max_scanned_elements` and `hard_max_scanned_elements`.
- Reaching the scan limit with unvisited source nodes returns a partial/truncated snapshot; read-only lookup cannot establish exhaustive absence and Task 81 refuses the incomplete result. Fully consuming a source exactly equal to the limit can still be complete. `maxElements` continues to limit returned rows. The initial AX root-array query still materializes the source list before traversal.
- When a native caller budget is bound, JSON serialization checks that captured budget before work and at stream/publication/return boundaries. Observed cancellation/deadline selects `ui_cancelled_or_timed_out` without base64; output-limit refusal keeps its size classification. Reentrant TLS scopes do not replace the captured caller. This does not add an absent socket/session budget binding or preempt Foundation between callbacks.
- With a bound native budget, each JSON prefix is projected to its success-wire size before buffer append, then checked again before publication/return. Parent response bytes count against remaining allowance. This reserves no output; final wire/sink admission still applies. Early size failure can precede later JSON validation errors.
- The JSON stream's raw buffer caps requested capacity at 786,426 bytes and transfers sealed ownership to immutable NSData without an explicit payload copy. Close releases any untransferred prefix. This does not cap transient realloc overlap, allocator/Foundation overhead or whole-operation RSS; device memory/performance qualification remains pending.
- The four legacy success codecs also recheck the captured native caller after base64 and after final response construction, before notify/return. An observed stop refuses late success; output consumed meanwhile is checked against the original wire projection. These checks reserve no output and cannot prevent a later stop or competing producer after the final check. Opaque Foundation work and transport delivery remain outside this guarantee.
- Base64 and final response construction have separate autorelease pools; strong results survive normal drain and the existing stop/output gates run afterward. Root obtains UTF-8 after the formatting pool while retaining its response through synchronous notify. This narrows temporary retention, without bounding Foundation/UTF-8/transport internals or qualifying a device memory/performance gain.
- Root result/capability codecs scope UTF-8 conversion, the final gate and synchronous notify together in an additional pool. No borrowed pointer escapes it; normal completion/refusal drains pending temporaries before return. This does not bound a blocking transport or retract bytes already accepted by notify if the caller stops during later pool drain.
- Default query deadline 1,500 ms; hard maximum 3,000 ms.
- Screen-off and locked-device requests fail closed.
- Logs contain status and counters only; element labels and values are not logged by the UI-tree core or the rootfull/roothide SpringBoard IPC bridge.
- The snapshot reports `partial`, `truncated`, serialization failures, duration, and foreground context changes.

## JavaScript

```javascript
const tree = device.uiTree({ visibleOnly: true, maxElements: 250, maxScannedElements: 4096 });
const login = device.uiFind({ identifier: "login.button", match: "exact" });
const ready = device.waitForElement(
  { text: "Login", role: "button", clickableOnly: true },
  { timeoutMs: 5000, intervalMs: 250 }
);
if (ready.ok) device.tapElement({ text: "Login", role: "button", clickableOnly: true });
```

Use `scripts/Test-TLinkUITree.ps1` for TrollStore qualification. For rootfull or roothide, use the TCP UI tasks through `scripts/Test-TLinkJailbreakUITree.ps1`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Test-TLinkJailbreakUITree.ps1 `
  -HostIP "192.168.1.244" -Runtime rootfull `
  -ExpectedBundle "com.apple.Preferences" -Text "Settings" -RequireMatch `
  -RepeatCount 10
```

Change `-Runtime` to `roothide` for a device running the Roothide package. Both packages report `runtime=rootfull` and `service=springboard_script_bridge` in task 77; the TCP protocol cannot prove which package was installed. The script reports this distinction as `requested_package_runtime` and `package_runtime_verified=false`. To test task 80, add `-AtX` and `-AtY` in UIKit points. Task 81 runs only with explicit `-Tap`, a selector, and `-ExpectedBundle`; the selector must resolve to one clickable element.

Promotion from `experimental` requires UIKit, SwiftUI, WebView, rotation, lock-state, app-switch race, and repeated-snapshot soak testing on both runtimes.
