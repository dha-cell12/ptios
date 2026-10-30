# C04a — immutable per-process VPN entitlement memo

Date: 2026-10-30 (Asia/Bangkok). Baseline: `3ed8519e`, C03ab build passed according to the user. Complete normalized diagnostics source SHA-256 before this change: `7dcd41a5e6dde3988efb7525be61191d5e07e44c0fbc40d320c44d323ab3f7fb`.
Status: **user reported build passed at `08ddc0e9` before C04b; independent device qualification pending**.
Finding: **P1-62 repeated static entitlement queries**, partial C04 improvement. P0-19/P1-63 broker timeout/admission remain open.

## Change

Every VPN diagnostics snapshot previously created a SecTask and queried all ten current-process entitlements. Memoize successful reads of those fixed keys inside each process. Store an immutable deep copy of a present property-list value; store a distinct absence marker only when the provider returned neither value nor error. Each lookup still follows the existing normalization and produces the same diagnostics fields.

Do not memoize a query that returns a CFError, including a value accompanied by an error. Retry only unresolved keys on the next snapshot, using one new SecTask for that request. If task creation fails while keys remain unresolved, preserve the original wholly unavailable response instead of mixing cached fields into a successful probe. When all ten keys are resolved, skip SecTask creation and all ten entitlement queries. Cache-copy nil/NS/C++ failures preserve the current uncached value and leave that key available for retry. CF references returned to the original probe remain owned and are released by the existing cleanup.

Initialize the private memo once and serialize access/publication with its own monitor. There are at most ten retained values, not a general TTL or arbitrary-key cache; this is not a new byte/RSS bound. Normalized arrays and their strings are immutable snapshots so callers and mutable provider inputs cannot modify later results. Different processes own independent memos; a restarted executable starts empty. Requalification after changing process entitlements requires restarting the relevant process.

Leave framework/class availability, private ownership-marker checks, input runtime/backend/state fields, effective-connected values and generation timestamps on their existing paths. No connection, profile, license decision, credential, broker result, socket state or task authority is memoized. The complete remainder of the diagnostics file is protected by reversal against the frozen baseline. Shared rootfull/roothide and production TrollStore targets use this implementation; TouchPOC is excluded.

## Verification

Both build workflows run `check-vpn-diagnostics-cache-safety.mjs`. It verifies the complete prior source after reversing the memo and immutable-output changes, freezes the baseline by SHA-256, and checks the ten lookup sites, success-only publication, exception fallback and serialized public wrapper. Existing VPN P0–P5 gates remain.

On macOS the runner compiles extracted actual and frozen entitlement probes with Foundation/CoreFoundation, ARC and ASan/UBSan. Only SecTask and optional copy operations are controlled. The fixture covers 1,000 normalized input shapes, stable absence, cold/warm parity, 10,000 warm reads with no new task/query calls, ten independent error slots with/without returned values, task failure during a partial memo, recovery, nil/NS/C++ copy failures, retained immutable data across pools and provider mutation, rejected caller array mutation, and 8,000 concurrent public calls with one initial set of ten queries. Explicit CF ownership is balanced. No real entitlement or VPN state is changed. These are policy/ownership checks, not device performance measurements.

Windows verification: all 66 workflow runners (36 source checks, 30 safety runners) and 521 existing workflow source checks pass; sixteen artifact-only checks are skipped. Expanded assert preprocessing and `git diff --check` also pass. The new Foundation runtime is included in CI and was not executed on Windows.

## Remaining work

Provider errors may continue causing retries indefinitely; there is no failure backoff or claim that every process reaches a fully warm memo. Measure actual query/cache behavior and diagnostics latency on the device. This change does not address root synchronous IPC head-of-line blocking, end-to-end VPN deadlines, broker admission/coalescing, private polling or broader C04/C06 work. Framework capability caching and all dynamic state remain outside this memo.
