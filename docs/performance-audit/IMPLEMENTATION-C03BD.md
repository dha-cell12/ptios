# C03bd — Bounded, detached Run History status projections

Date: 2026-11-10 (Asia/Bangkok). Baseline: `e8a8a50d`; user reported C03bc built successfully and requested larger packages. Scope: P1-48/P1-51 status preparation shared by rootfull/roothide and production TrollStore. TouchPOC is excluded.

## Delivered together

Every history snapshot still takes the existing process monitor/shared file lock and performs the complete checked fresh index read. For an exact byte match and the same normalized requested limit, reuse a previously successful status projection. A hit skips index JSON parsing, schema/duplicate-ID validation and the repeated error/evidence/tail projection and failed-run scan. Only snapshot passes the optional private read context; begin/finish and their recovery/transaction paths retain their complete preceding read/validation behavior.

The memo stores one owned immutable byte key of at most2MiB, normalized limit, frozen projected rows and total/failed counts. It excludes diagnostics, root path and all other outward status fields. Those fields are assembled freshly by the existing status builder on every call. A matching file can therefore reuse rows while reporting a newly recorded persistence failure. Different bytes or limits miss; identical atomic replacements can hit only after their new checked read.

Freeze the projection with a bounded recursive copy and return a separate deep mutable copy on each hit. Arrays/dictionaries remain independently mutable, including nested extra/playback settings/evidence/tail fields. Strings and numbers use copy without JSON/property-list round trips, preserving uint64 values, negative zero and the exact UTF16 units produced by the existing formatter. Caller mutation of returned rows or preparation inputs cannot poison the retained projection.

Memo copying admits at most4096 nodes,128Ki UTF16 string/key units and depth32. These are memo eligibility limits, not new history or response limits. Unsupported/over-budget projections and larger indexes follow the complete uncached path. Nil/NS/C++ auxiliary copy failures clear the memo and preserve uncached snapshot behavior. Missing bootstrap is not cached. Read, schema, lock and terminal format errors clear memo state before returning the same failure envelope/diagnostics.

The memo mutex protects only shared-entry snapshots/replacement. Full comparison and graph copying happen outside that private mutex; replaced ARC payloads retire after unlocking it. A lookup retains an immutable entry while cloning, preventing reentry/replacement from mixing keys, rows or counts. A reader's bytes and limit must match that same entry. Existing process serialization remains; a cooperating writer may replace the file after read unlock, and an old projection is then paired only with its own old bytes, causing a miss on the next fresh read.

## Boundaries and costs

This removes repeated decode/validation/projection work for unchanged status content; it does not eliminate filesystem IO, shared-lock admission, index rewriting, cold recovery or history rendering for ineligible input. Warm copying is bounded but still runs during the checked-read phase under the file lock. The existing status-preparation stage remains after file unlock. Cold eligible reads retain their byte key through formatting, then either publish it with the frozen projection or release it before constructing outward metadata.

One active memo owns at most the admitted byte key and bounded logical graph. Foundation backing storage, allocator/container overhead, transitions, callers retaining results, active copies and the32-MiB reader/decoder are separate; this is not an overall RSS bound. Cold requests add a freeze pass, and alternating limits/changing input can receive no cache benefit. Device CPU, allocation, lock-time and latency improvements remain unmeasured.

No index/schema/status fields, retention rules, persisted authority, failure counter policy, event/marker/ACK ordering, public header or target dependencies change. Begin/finish never consume the memo. The original validator, projector, writer, recovery and diagnostic bodies remain available through complete source reversal. There is no stale-data or unlocked-read fallback and no repair on a read-only hit.

## Evidence

Portable production-budget coverage passes100000 independent node/unit/depth oracles, sticky refusal, exact4096/128Ki/depth32 boundaries and SIZE_MAX/zero cases. All90 workflow runner results (36 source/54 safety portable subsets),521 source assertions (16 artifact-only checks skipped), complete predecessor restoration, JavaScript syntax, six-file assertion macro preprocessing and diff whitespace pass on Windows.

The existing macOS Foundation/POSIX/ARC/ASan/UBSan executable gains the actual memo module and a frozen preceding snapshot. Older fault matrices explicitly run cold; new cases enable the real memo and expect129 fresh reads with one decode, full graph/count/limit parity, deep caller mutation isolation, fresh diagnostics and identical replacement hits. Nil/NS/C++ copy refusal, primed-cache read/lock/schema/type errors, missing bootstrap, byte/depth/node ineligibility and exact uint64/negative-zero/unpaired-UTF16 ownership are covered. Existing checked-read, lock, mutable-index, transaction, recovery and controlled MRC tests remain.

Native fixture extraction includes the new module before namespace-wrapped histories and supplies both current/preceding snapshots. It retains the original post-unlock preparation probe, so a cooperating replacement is still tested against one owned per-call graph. Three direct history consumers continue to resolve the inline module through their existing source/shared include paths; no implementation link dependency is added. Apple compilation/execution and device qualification require macOS CI and are not claimed from Windows results.
