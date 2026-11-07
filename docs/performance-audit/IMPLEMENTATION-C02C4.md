# C02c4 — Owned helper RPC replay payloads and identity encoding

Date: 2026-11-08 (Asia/Bangkok). Baseline: `713cbb74`; user reported C03ap build passed and requested a larger batch. Scope: P1-41 rootfull/roothide helper native RPC replay. Production TrollStore and TouchPOC source are unchanged; both workflows retain the existing replay runner.

## Delivered together

- Store completed replies in immutable shared string owners. A replay lookup returns an owned snapshot, so eviction, session reset or cache destruction cannot invalidate an admitted reader. Pending/collision/unavailable decisions, FIFO order and all logical byte/count/identity limits remain.
- Prepare the new owner before evicting another reply. The identity is already terminal at this point; a failed owner allocation cannot cause its native effect to execute again. Payload preparation adds a control block; no device allocation/latency reduction is claimed.
- Construct replay NSData with the no-copy initializer and a deallocator block retaining the immutable owner. The producer no longer explicitly copies the entire cached reply into another NSData. The block never frees the borrowed string pointer directly and never references the cache/context. Foundation may choose its own storage strategy.
- Encode requestId and method once each into owned NSData; obtain bytes and lengths from the same objects instead of pairing borrowed UTF8String pointers with separately encoded lengths. Preserve embedded NUL and the existing 64/128-byte core fences, now checked before copying oversized keys. Valid wire strings retain their decisions and errors. Arbitrary concurrent native argument mutation is not a new supported contract.
- Treat nil/empty result serialization as invalid. If even the error result cannot be serialized, retire the identity with no replay payload instead of constructing a string from a nil byte pointer. Retries receive unavailable and do not repeat the effect.

The dispatch signature, sorted streaming SHA fingerprint, policy/native callback, response graphs and reset points retain their source. Quotas remain 4 MiB/256 stored replies, 1 MiB per reply, 8192 identities and the existing identity-byte bound. Held NSData/lookup snapshots can outlive cache retirement; their memory is caller-owned, outside the cache's logical charges, as retained copies were before. This is not a process RSS bound or a thread-safe cache API: only immutable snapshots may be read independently.

## Verification

All 90 workflow runners (36 source,54 safety portable subsets) and 521 source assertions pass on Windows; 16 artifact-only assertions are skipped. Focused replay/fingerprint, generated fixtures, JavaScript syntax, six-file assertion macro preprocessing and diff whitespace checks pass. Apple native branches are skipped on this host.

Freeze the complete preceding header and guard complete old/current hashes. Compile it under checked symbol/guard renaming as an independent oracle; the fingerprint implementation and runtime source remain unchanged. Temp and shared include paths are explicit for both portable and native fixture compilers.

The actual portable core adds 100,000 complete preceding/current decision, byte/count/identity comparisons; 10,000 held-reader eviction/reset lifecycles; cache destruction; immutable element checks; and eight threads reading held snapshots across 80,000 iterations with no final owners. Earlier 100,000 FIFO and fingerprint-feed oracles, 4-MiB limits and 8192-ID tests remain.

Extend the existing Foundation/CommonCrypto/ARC/ASan/UBSan executable:

- 216 complete preceding/current reply/decision/quota comparisons, including Unicode, NUL, UTF16 and UTF8 byte limits, replay and method/argument collisions.
- NSString probes expect one encoding per identity field and zero borrowed UTF8String calls, versus one of each previously. A controlled identity mutation after encoding verifies consistent owned key bytes; encoding failure refuses without an effect.
- Hold NSData beyond parsing while the parser hook clears the cache or performs nested execution that evicts the current reply. Validate bytes/results after retirement and release, allowing Foundation's copied-storage behavior too.
- Nil/throwing view factory and NS/C++ parser faults preserve quota and execution count; ordinary replay recovers. Nil/empty serialization leaves an unavailable identity without repeated execution.

**New Apple compilation and native execution require macOS CI.** Macro preprocessing does not check Apple types. Shared-owner/control-block overhead, Foundation copies/parser allocations and device CPU/RSS/latency remain unmeasured. P1-41 remains partial/device qualification pending.
