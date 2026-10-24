# C02b3 — structured object batches

Date: 2026-10-24 (Asia/Bangkok). Baseline: `4d1ce08`; the user reported the C02b2 build passed before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.
Finding: **P0-13, ordinary object-batch portion**. RAW/mixed compatibility, other typed methods and helper transport remain separate paths/work.

## Result and scope

Root JS `batch` can prepare numeric tap/swipe/point-gesture requests and enter task 65 directly. The structured path shares the existing touch executors, avoids the aggregate request string, UTF-8 request buffer, CF stream, raw task dispatch, response vector and successful reply splitting. Public `{ok, raw, parts}` results and synchronous ordering remain.

The fast path requires object commands with string types. Tap/swipe durations must be absent or finite NSNumber values in `0..60000`; other representations/ranges use the original whole-batch wire path. This is a compatibility selection made before execution. Legacy batch tap/swipe durations were **not clamped** before NSString `intValue`, including overflow and string coercion; the new path does not redefine those cases. Any RAW string selects the original whole-batch path. There is no fallback/retry after an action starts. Production TrollStore and TouchPOC are unchanged.

## Validation, bounds and compatibility

- Preserve the 256-command JS limit. Shape/finite/point validation covers the complete batch before authorization or injection, including errors appearing after a valid prefix or an oversized prefix. This does not pre-reject all executor errors: invalid fingers/float-overflow coordinates still fail sequentially, after any earlier successful commands, matching task 65.
- Preserve old tap/swipe missing-coordinate/default-duration behavior, `%.2f` to float coordinate conversion, `%.0f` duration rounding and gesture duration/durationMs precedence, integer conversion and `0..60000` clamp. Bounded scalar formatting remains on the stack. Duration length accounting preserves the extra minus sign for negative zero.
- Count the equivalent ASCII command lengths, task-65 prefix and `||` separators against the existing 8192-character ingress limit. The ASCII structured path also satisfies the legacy 32 KiB byte/NUL rules. Saturating arithmetic handles overflow without allocation; after overflow, continue JS validation without retaining more plans, then return `input_too_large` before authorization/effects.
- Retain at most 256 request slots plus point vectors admitted under the equivalent input cap. Each current point plan is bounded by the existing 512-point limit. This bounds private preparation, not opaque Foundation/HID allocations or process RSS.
- Preserve the authorized empty-batch format error. RAW/mixed batches retain delimiter/prefix/NUL checks, aggregate UTF-16/UTF-8 limits and sequential parser errors. External RAW task 65, including task-10 ownership/cleanup, is unchanged.

## Execution and authority

The typed batch entry checks its count/kind allowlist, creates one noncapturing child call context preserving owner/token/deadline/output defaults, checks stop before and after the existing **task-65 license gate**, and invokes commands sequentially. It does not authorize each command as a separate task 62/63/64 call. Stop at the first executor failure; never execute a later command after that failure, cancellation or exception.

Each common executor owns its DOWN/UP lifecycle with finally cleanup. Cancellation/Objective-C/C++ exceptions on a later command release that command's touch before returning. Output/stop mapping uses the existing typed reply helper; output-cap failure can follow committed effects, as on the old bridge. Small control-error replies and cooperative/opaque latency limits remain those documented in C02b1/C02b2. No measured performance or hard completion deadline is claimed.

## Validation

- Windows: all **36 source-contract runners, 20 native runners and 528 TrollStore workflow source grep assertions** pass (16 artifact-only assertions require CI outputs). Portable coverage adds negative-zero duration byte accounting, exact/saturated batch-size limits, SIZE_MAX rejection and 10,000 size sequences of up to 256 commands, with MSVC `/W4 /WX`. The existing scalar parity, budget/cancellation, timeline and production touch checks remain.
- Existing native-budget runners extract the actual batch bridge, entry and required production helpers on every host. Source guards prevent raw dispatch/aggregate encoding/CF stream use in the structured branch, require the single task-65 gate and forbid YES/NO macro dependencies in the entry.
- The expanded macOS actual Foundation bridge/entry fixture compares 120 mixed object batches and boundary cases against a frozen legacy object encoder plus the actual RAW task-65 parser/executors. It checks exact replies/parts, frames/order/timestamps, empty/default/256-command batches, 8192/8193-character boundaries, shape errors after an oversized prefix, authorization denial/gate-time cancellation/pre-expiry, first failure, cancellation between/during commands, real deadline expiry, NS/C++ exceptions with UP, output limits and RAW/mixed/nonstandard-duration/NUL compatibility. Both workflows already run this fixture with strict warnings and ASan/UBSan.
- **The new Foundation/macOS cases and iOS builds were not run on this Windows host.** Actual Darwin scalar parity, HID behavior, allocations, latency and device qualification remain pending.

## Acceptance and next slice

Build rootfull/roothide in observe/enforced modes. Compare JS object batches and task-65 wire batches on device for order, coordinates, final-UP state and exact replies. Cover a late invalid command, denial/cancellation, empty/256-command batches, size boundaries, exceptions and successful recovery after each failure. Measure allocations and batch latency against C02b2 before claiming a performance gain.

Continue other measured P0-13 methods and P0-12 event-driven helper RPC, then P1-40 configuration snapshots and P1-41 byte-bounded dedupe. C01/C02 device acceptance remains open.

## CI correction - explicit Objective-C result type

TrollStore macOS CI rejected `auto result=invoke(normal,context).value` with `-Wauto-var-id`: the response value property is declared as `id`. The batch denial fixture now declares `NSDictionary *result` explicitly. Other auto declarations in this fixture resolve to concrete response/context types or C++ values. Production batch behavior, strict warnings and sanitizers are unchanged. Corrected macOS compilation/runtime and iOS builds remain pending; the Windows native-budget runner is rerun for portable coverage and fixture extraction.
