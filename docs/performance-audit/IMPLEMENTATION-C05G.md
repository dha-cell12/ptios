# C05g — Reuse foreground helper symbols and its library handle

Date: 2026-11-05 (Asia/Bangkok). Baseline: `c1d48cb4`; user reported C05f build passed and requested continued implementation. Shared rootfull/roothide and production TrollStore AX foreground fallback helper; TouchPOC excluded. Continues C05/P1-61.

## Foreground discovery

TLinkAXFrontmostBundleID previously opened SpringBoardServices on every call without closing that reference, then resolved foreground functions again. Reuse the C05a two-symbol cache for the two copy functions. Pin one successful library reference for this helper's process lifetime; concurrent surplus opens are closed by the existing atomic cache. Failed opens and missing symbols remain retryable.

Resolve server-port and legacy foreground symbols lazily when the copy providers yield no nonempty bundle ID. A small fixed-name Symbol slot publishes successful pointers atomically and retries null lookups. These two slots borrow the already pinned handle: no second library open, independent handle ownership or close operation. Each slot is scoped to one fixed library/name, and the caller must retain that library for all uses. Keep the existing two-symbol cache implementation unchanged under a full header restoration guard.

The copy cache resolves both copy symbols when consulted, including retrying a missing second symbol even if the first provider subsequently succeeds. This differs from the old conditional loader lookup order; foreground provider invocation order remains first copy, second copy, then server/legacy fallback. Missing secondary symbols can therefore still incur repeated dlsym calls. No cache lock is held through loader/provider callbacks. Successful pointers stay cached for the process lifetime, matching the existing C05a assumption about library symbols.

Read current foreground values on every call. Preserve nil/empty handling, Unicode/NUL behavior, immutable copies of returned CF strings, exact CFRelease behavior, legacy UTF8 parsing and NS/C++ exception behavior. Cache neither a bundle ID nor a PID. The complete in-process/direct/process-scan precedence, PID validation and Task foreground/completeness/action/authority guards retain their preceding source. No active app, lock state or entitlement policy is changed.

This bounds this helper's successful loader references and removes repeated successful symbol discovery. It does not change process enumeration/plist fallback, direct AX selectors, task queue/cancellation, persistent notify/SecTask/value probes or the root/snapshot/string-output issues. The pinned reference remains until process exit; no device performance claim is made. C05/P1-61 remain partial.

## Verification

Freeze the preceding complete helper and two-symbol header. Reverse only loader/symbol substitutions, validate the complete C05f AX hash, then continue the existing C05f/e/d/c/b/a restoration chain. Strip only the added Symbol class to validate the entire preceding header. Reuse the existing symbol safety runner and both workflows; runner count remains 90.

Portable tests add null-handle refusal, missing lookup retry, instance isolation, 100k warm borrowed-symbol reads, 32 eight-thread cold races and 320k warm concurrent reads, late failed lookup after another publication, reentry and lookup unwind. Borrowed symbol slots perform zero opens/closes. Existing cache cold-open/loser-close/race/retry tests remain enabled.

Add a separate complete current/frozen helper Foundation/CF/ARC/ASan/UBSan executable to the same runner. The loader and private providers are controlled; strings, mutable source copies, CF ownership and Foundation decoding are real. Native expectations cover 256 output/provider-order/CF parity cases, missing/empty/Unicode/NUL/invalid-UTF8 values, copy and legacy fallback, 10k fresh reads on each of three routes, successful and missing symbol publication/recovery, held output after source mutation/pool exit, provider/loader NS/C++ faults and 16k cold/warm concurrent reads. Count fake opens/references rather than opening private libraries: one pinned foreground handle versus 10k preceding references per warm route. Copy/legacy provider calls still occur on every read. These are controlled operation counts, not OS-loader/RSS/device measurements.

Windows validation: all **90 workflow runners** (36 source, 54 safety), **521 existing source checks**, complete staged AX/header restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. The new Foundation/ARC/sanitizer executable and Apple/iOS compilation require macOS CI. No real private foreground query or tap occurs in the fixture; device qualification remains pending.
