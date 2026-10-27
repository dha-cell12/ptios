# C02b23 — direct frontmost app ID and orientation queries

Date: 2026-10-27 (Asia/Bangkok). Baseline: `c3f2443`; the user reported C02d12 built successfully.
Status: **build reported passed by the user before C02b24 (`de4e01f`); device qualification pending**.
Finding: **P0-13, frontMostAppId/orientation adapters**. Other native adapters, config invalidation and performance qualification remain open.

## Result and compatibility

The rootfull/roothide bridge calls a direct task-34/35 entry for frontMostAppId and orientation. These calls no longer format/encode a two-character RAW request, dispatch through processTaskWithContext, allocate the compatibility CF stream or accumulate/copy a native response vector. The ordinary success path constructs raw/parts and bundleId or the Foundation intValue orientation directly, without splitting/reparsing the reply. Method arguments remain ignored as before.

Keep the existing Process functions and their execution thread, including the SpringBoard app-ID fallback and string-valued orientation backend. The two RAW task branches are unchanged and checked against frozen source bodies. Helper-driven calls that reach this bridge use the same new entry; production TrollStore and TouchPOC execution source are unchanged. Both production workflows run the shared suites.

The result still carries exact ok/raw/parts plus bundleId or value. Copy the backend value into an immutable snapshot before building the response. A per-query autorelease pool drains Process/formatting temporaries; a strong result outside that pool retains the compatibility fields for the caller.

Unusual backend strings take a compatibility path preserving notifyClient's first-NUL boundary, newline trimming and ;; splitting. Empty/nil, embedded NUL/delimiters, trailing Unicode newlines and Foundation integer conversion retain their old meanings. If the formatted string cannot produce UTF-8, preserve the old empty-writer fallback to 0 CRLF, without adding bundleId/value. That fixed fallback was uncharged by the old writer; this slice preserves that exceptional behavior even with a tiny cap. Normal results admit their complete wire bytes against the existing output budget.

Compatibility raw strings and Foundation UTF-8 formatting storage remain. The output budget is a wire-byte policy, not a bound on backend NSString allocation or internal Foundation temporaries. This slice makes no measured allocation, latency, CPU or RSS claim.

## Context, license and failures

Reject task IDs other than 34/35 before entering the provider. A valid call uses the existing child context with a noncapturing budget, caller deadline/output settings and owner metadata. It does not add a C01-local timeout or a compute admission. Check stop before exactly one ordinary task license gate, after that gate, after the Process query and after result construction. Session automation/cleanup exemptions do not bypass the task-34/35 gate.

Cancellation/deadline/output failures retain normalized compatibility errors. Backend or formatter NS/C++ exceptions return native_exception, with TLS/budget scope and the query pool released. Process/private API and license work remain cooperative/nonpreemptible, matching the existing thread/authority boundary; no hard completion deadline is introduced. No frame/image/touch resource is created by these queries.

## Verification

- All 62 workflow runners (36 source-contract, 26 native) pass on Windows after a focused rerun of touch safety. Its first TrollStore link attempt hit Windows LNK1104 on the reused temporary executable after the root test passed; a fresh rerun passes both injectors without source or warning-policy changes. Native-budget checks were repeated after final pool changes.
- All 521 direct workflow source-grep assertions pass; 16 artifact-only checks require CI outputs. Standards-conforming assert preprocessing passes existing fixtures and all three new frontmost fixture files, with the existing rejecting negative control. git diff --check passes.
- All-host guards verify direct bridge calls, unchanged frozen RAW bodies, one task gate with stop checks, noncapturing context, no C01 timeout/RAW dispatch/CF stream in the entry, macro-independent booleans and cold-only reply splitting.
- The macOS fixture compiles the actual bridge fragments, task entry, context and response writer against controlled Process/license boundaries. It adds 160 ordinary comparisons with frozen adapters, plus nil/empty/Unicode/NUL/delimiter/newline/large signed numeric/encoding edges at normal, exact and one-byte-short caps. It checks task-34/35 authority, denied owner exemption, pre/gate/read stop/deadline, NS/C++ faults, mutable-provider snapshots, pool lifetime, invalid task rejection and zero typed RAW calls/response-vector capacity.
- Those new Foundation/ARC/ASan/UBSan cases cannot execute on this Windows host. Actual macOS/iOS builds, real foreground/orientation behavior and device performance remain pending.

## Acceptance and remaining work

The user reported build `de4e01f` passed before the next path-adapter slice, `IMPLEMENTATION-C02B24.md`. This records the user report without independent device/performance qualification on this host.

Build rootfull/roothide variants, compare JS/helper queries with RAW task 34/35 through foreground changes, SpringBoard fallback and portrait/landscape rotation. Exercise license denial/revocation, caller cancellation/deadline and output limits. Measure bridge allocations/time separately from Process/private API cost. Continue the other P0-13 adapters, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
