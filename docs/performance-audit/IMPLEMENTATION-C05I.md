# C05i — Resolve the secondary foreground symbol only on fallback

Date: 2026-11-05 (Asia/Bangkok). Baseline: `a66d740b`; user reported C05h build passed and requested continued implementation. Shared rootfull/roothide and production TrollStore AX foreground helper/cache; TouchPOC excluded. Continues C05/P1-61.

## Defer unused lookup

C05g reused foreground symbols and one pinned library handle, but its two-symbol cache eagerly retried a missing secondary symbol even when the first provider returned a nonempty bundle ID. Let that caller request the first symbol alone, then resolve the secondary slot only when its provider branch is reached.

The cache's load method gains an optional includeSecond argument, defaulting to true. Default callers keep the complete preceding handle/open/lookup sequence. A new loadSecond method reads the already pinned handle and resolves just its existing secondary atomic slot. Before a successful handle publication it returns null without opening or looking up anything. Successful secondary pointers stay published; null lookups remain retryable. No additional fields, handle references, locks or process-wide negative cache are introduced.

The foreground helper calls load with includeSecond=false. A successful first provider returns immediately. A missing first function, nil value or empty string reaches loadSecond and follows the same second-copy/server/legacy fallback as before. Every reached provider reads current values; no bundle or PID is cached. A secondary loader fault is now encountered only if that fallback is reached, so it cannot fail an otherwise successful first-provider read. Reached provider exceptions, CF ownership, Unicode/NUL/UTF8 parsing, fallback order and all foreground/PID/action/authority guard source remain unchanged.

This removes repeated missing-secondary discovery from the first-provider success path and also skips its initial unnecessary lookup. It does not eliminate retries when fallback is actually needed, change ordinary cache callers, memoize entitlement values or alter notifications, process/plist fallback, AX root/snapshot/string-output bounds or opaque RPC handling. C05/P1-61 remain partial; no device performance claim is made.

## Verification

Freeze the complete preceding foreground helper and cache header. Reverse only the first-only call/secondary branch and the optional cache argument/resolver, validate the complete C05h AX hash, then run the existing C05h/g/f/e/d/c/b/a restoration chain. Header reversal retains every preceding default-cache/borrowed-slot line. Reuse the existing symbol runner and both workflows; runner count remains 90.

Portable additions exercise 100k first-only calls with zero secondary lookups, 100k cached secondary calls, refusal before handle publication, missing/available recovery, missing primary with valid secondary, 32 eight-thread deferred publication races, a late failed lookup after another thread publishes, and lookup exception recovery. All preserve one pinned reference and zero additional opens/closes. Existing default-cache, cold-open race, reentry, borrowed-slot and entitlement checks remain enabled.

Extend the existing complete current/frozen Foundation/CF/ARC/ASan/UBSan foreground fixture, retaining its original pre-C05g oracle and adding the exact C05h helper. Ten thousand first-provider successes with an unavailable secondary expect zero current versus10k preceding secondary lookups, unchanged10k fresh provider calls and one pinned handle in both paths. Per-slot atomic counters avoid assumptions about Foundation string classes. Nil and empty first values must retry the missing secondary, recover when it appears, then reuse it while reading fresh values. NS/C++ secondary lookup faults must remain dormant during first-provider success, propagate when fallback is reached, and recover afterward. Existing 256 frozen value/provider-order/CF cases, three live routes, mutation/pool lifetime, provider faults and16k cold/warm concurrent calls remain enabled.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete staged AX/header restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. The extended Apple/iOS compilation and Foundation/ARC/sanitizer execution require macOS CI. Counts are controlled fixture expectations rather than real loader/RSS/device measurements; no real private foreground query or tap occurs.
