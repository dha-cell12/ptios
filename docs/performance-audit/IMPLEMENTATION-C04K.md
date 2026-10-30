# C04k — reuse the completed immutable entitlement probe

Date: 2026-10-31 (Asia/Bangkok). Baseline: `3813fafc`; the user reported the preceding build passed, including C04j and the diagnostics fixture SDK type correction. Complete normalized diagnostics baseline SHA-256: `269f402b73560ed3736d0b9df803f96c2684b6cbfbda59a2203d480e56e5fb1e`.

Status: source implemented; expanded Foundation/ARC/sanitizer runtime pending macOS CI and independent device qualification.

## Change

C04a memoized ten successful entitlement values, but every warm public probe still retained/released those CF values and rebuilt normalized arrays, copied strings, calculated flags and constructed a dictionary. Keep one completed immutable entitlement dictionary under the same existing cache monitor. Return it directly on later calls. Publish it only after all ten keys have resolved successfully, including successful absence. An unresolved provider error or optional deep-copy failure continues through the existing retry path; task creation failure during partial initialization retains the old unavailable response.

The dictionary literal and normalized nested arrays/strings are already immutable. Holding the result therefore needs no additional copy or fallible publication adapter. Only this entitlement result is reused. The complete framework/private compatibility probe, ownership marker, state/backend/broker/profile data, generated timestamp, outer snapshot, base64 encoding, task gates and authority code remain unchanged. Entitlement changes still require a process restart under C04a's existing policy. The shared implementation applies to rootfull/roothide and production TrollStore; TouchPOC is excluded.

## Verification

The existing diagnostics runner now hashes a complete C04k baseline and reverses only the public wrapper to reproduce it. The original complete C04a reversal remains in place. All three current/previous/original extraction paths are checked on every host, including the fixture-private SecTask type mapping, before macOS compilation.

Extend the actual-source Foundation fixture with cold concurrent publication, 10k warm reads of the same immutable object, caller-pool lifetime and rejected dictionary/array mutation. A separate instance starts with ten provider errors and missing values, resolves keys incrementally, checks unavailable task creation and nil/NS/C++ copy failures, then verifies completed reuse even after the provider becomes unavailable. Compare complete fields with the original implementation while retrying. Existing 1000 normalization shapes, absence, raw-value ownership and error cases remain.

Instrument the fixture's existing explicit CF retain adapter. For a cold public read followed by 8k concurrent reads, expect only the initial task/value retains. Compare 64 warm reads through the actual preceding C04a wrapper (640 retained value reads) with the completed wrapper (zero warm CF value retains). This is a synthetic operation-count assertion awaiting macOS execution, not a measured device CPU, latency, allocation or memory result. ARC still owns returned dictionaries normally.

Windows source, portable and workflow validation is recorded in STATE.md. Expanded Foundation/GCD/ARC/ASan/UBSan execution requires macOS CI. No real entitlement, NetworkExtension, VPN profile, radio or license state is changed by the fixture. Missing callbacks, manager cancellation/coalescing, direct/private callers, CF preemption and device qualification remain open; this does not close all of C04/P1-62/P1-63.
