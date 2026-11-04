# C05a — Reuse AX lock and Security symbol lookups

Date: 2026-11-04 (Asia/Bangkok). Baseline: `c7ef1d62`; user reported C06ad build passed and requested continued implementation. Shared AX backend in rootfull/roothide and production TrollStore; TouchPOC excluded. Source files were externally committed as `6148fc53` during validation; the agent did not create that commit.

## Fixed symbols, fresh state

P1-61 identifies repeated loader work in AX lock/capability probes. Each TLinkAXLockState previously opened SpringBoardServices and resolved two symbols. Every TLinkAXEntitlementValue opened Security and resolved two symbols; a capability snapshot calls that helper three times. Successful dlopen references were never closed, so those calls also accumulated loader references.

Use two process-local caches with fixed library/symbol names. Pin one successful loader reference per cache and publish each successful symbol atomically. A missing library or symbol is retried by a later call; a partial discovery retries only the missing symbol. Already resolved symbols remain stable for the process lifetime. The pinned handle prevents unloading the library behind the pointers; dynamic replacement/interposition of an already resolved symbol is outside this contract.

Do not hold a cache lock across dlopen/dlsym: loader initialization can call application code or acquire loader locks. Concurrent cold callers may open/resolve the same library; only one handle reference wins publication and each losing successful open is balanced with dlclose. A late failed lookup cannot erase another caller's successful publication. Reentry and exceptions cannot leave a single-flight gate stuck because there is no such gate. Failed probes can still repeat loader work, and a cold concurrent burst can duplicate discovery; there is no new admission or time bound.

Every call still reads both notify flags and invokes the resolved SpringBoard lock functions. Every entitlement call still creates its SecTask, reads the requested value, releases task/error references and returns the original value/alias. Missing/null/error values are not memoized. Lock OR/fallback/passcode rules, NS exception handling and result fields retain their preceding source. This adds no private API, entitlement/authority change, cached lock/foreground state or persistent notification token.

Other SpringBoard foreground symbol lookups, Security task/value calls, notify registration churn, AX traversal/selector/output budgets and device qualification remain open. This is a partial P1-61/C05 implementation; it does not complete P0-20 or claim measured latency/RSS/power gains.

## Verification

Freeze the complete preceding lock/entitlement helpers. Source reversal permits only the loader/cache substitutions plus the header include and verifies the full preceding AX SHA-256, preserving all serialization, traversal, foreground/action and task behavior. Both production workflows add check-ax-symbol-cache-safety.mjs.

Portable tests exercise the actual C++11 cache: 100k warm reads; library/partial-symbol failure and recovery; 64 eight-thread cold races with 640k subsequent concurrent warm reads; exactly one pinned reference/seven loser closes per forced cold race; a stale failed lookup; independent instances; loader reentry and lookup exception recovery. These execute on Windows with strict MSVC C++14 (its minimum selectable mode); macOS CI compiles the code as C++11, matching the root target.

The native fixture compiles complete current/frozen helpers with controlled loader/notify/private providers and real Foundation/CF values. It compares 32 lock-state/exception combinations and seven entitlement/failure shapes. Ten thousand changing lock and entitlement reads must retain all provider calls but reduce opens per library from 10,000 to one and lookups from 20,000 to two. Other cases cover missing/partial symbol retry, task failure recovery, absent/error/mutable entitlement values and aliases, cross-pool return ownership, lock-provider exception recovery and 8k concurrent warm reads. No real lock state, Security task, entitlement or private framework is probed by this fixture; native assertions remain CI expectations rather than device measurements.

Windows validation: all **89 workflow runners** (36 source, 53 safety), **521 existing source checks**, full preceding AX hash, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Sixteen artifact-only checks skipped. Foundation/CF/ARC/ASan/UBSan execution and iOS builds require macOS CI; real dyld/private-framework/device qualification remains pending.
