# C02c2 — byte-bounded helper RPC replay and session identity fence

Date: 2026-10-25 (Asia/Bangkok). Baseline: `904e7ca`; the user reported C02c1 built successfully before this slice.
Status: **source implemented; new Foundation/macOS/iOS CI and device qualification pending**.
Finding: **P1-41, retained replay/fingerprint storage addressed; streaming fingerprint work remains**.

## Result and scope

The root helper RPC bridge now retains serialized JSON replay bytes rather than 256 arbitrary Foundation result graphs. The FIFO has both a 256-result ceiling and a 4-MiB serialized-payload ceiling, with at most 1 MiB per serialized result. Argument identities retain a 32-byte SHA-256 digest instead of the complete JSON NSString. Object keys are sorted before hashing, making equivalent dictionary insertion orders match. Array order, JSON scalar types and method identity remain significant.

This bounds retained replay payload, not total RSS or transient serialization/parser/native output allocation. Argument JSON is still serialized to a temporary NSData (accepted up to 1 MiB) before hashing; it is not incremental hashing. Every polled duplicate still fingerprints its arguments, and the existing 200-ms status polling/fresh-socket transport remains. No device latency, CPU or RSS improvement is claimed. Production TrollStore/TouchPOC source is unchanged; both CI workflows run the new shared runner.

## Avoiding repeated effects after eviction

Reserve the request ID, method and digest before invoking policy/native execution. A matching cached request returns the stored wire result without invoking policy/native work again. Changing method or arguments for an existing ID returns the existing collision error and requestId. Identical in-flight reentry returns an explicit in-flight error. JSON snapshots prevent later mutation of a returned dictionary from modifying future replay.

Eviction frees only the serialized reply. A compact identity record stays until session cleanup. A matching retired ID returns `native RPC replay unavailable; request already handled`, never a second execution. This intentionally replaces the previous behavior that could execute an old ID again after the 256-entry FIFO forgot it. A retry after eviction can receive an error rather than the original success, so callers must not treat this as permission to resubmit the same side effect under a new ID.

The identity ledger has independent ceilings of 8192 IDs and 1 MiB of summed ID/method/digest bytes, whichever fills first. IDs must contain 1..64 UTF-8 bytes and methods 1..128 bytes; embedded NUL remains part of identity. Existing UUID request IDs fit these limits. Once the ledger fills, new IDs fail before execution with `native RPC session identity limit reached`; existing records can still replay or report collision/retirement. No identity is silently discarded to admit more work. A new session clears both ledger and replies. These limits bound collection sizes and content lengths; allocator/container overhead is additional.

The current five-minute session limit and 200-ms polling make the identity ceiling above ordinary sequential session throughput; this is not a capacity guarantee for a future event-driven transport. P0-12 must revisit session sequencing/acknowledgment and ledger retirement without reopening repeated effects. This remains a process-local, session-local fence, not durable exactly-once execution across runtime crashes or a new session.

## Failure and policy behavior

New requests retain the existing allowlist/admin configuration policy and native task/license checks. A policy denial is cached like other results; changing policy does not reauthorize an old request ID. Replay counters and blocked counters remain, with decision/retained-byte/identity counts in the existing RPC log. The cache has the same single session-owner access model as its predecessor; it adds no independent cross-thread API.

Empty/oversized IDs, invalid/oversized argument JSON and unsupported method identity fail before native work. NS/C++ execution exceptions and invalid/oversized result encodings produce small replayable errors after reserving identity. Result limits do not roll back an already completed native effect. Session-start and finally cleanup reset the cache; owned image/frame cleanup remains in place. Transport envelope capacity, session authentication/reconnect and late-response behavior are separate P0-12 work.

## Validation

- Windows: new portable runner passes 100k variable-size FIFO cases against an independent queue oracle, byte/count eviction, exact metadata accounting, pending/collision/retired states, zero/oversized response handling, 256 one-MiB response attempts held to 4 MiB, full 8192-ID admission fencing and session reset.
- The macOS fixture compiles the actual production header/dispatcher with ARC, Foundation, CommonCrypto and ASan/UBSan. Cases cover a known SHA-256 vector, dictionary key order, scalar types/Unicode/NUL, exact argument bounds, wire snapshot mutation/pool lifetime, reentry, policy denial replay, byte eviction without repeated effects, identity exhaustion and NS/C++/encoding/oversize failures. Actual Foundation execution is pending CI on this Windows host.
- Source guards check runtime integration, reservation before execute, both reset paths, removal of the former unbounded cache and both workflow entries. All 58 workflow runners (36 source-contract, 22 native), 521 source-grep assertions and standards-conforming assert preprocessing pass on Windows. Sixteen artifact-only checks require CI outputs. These checks do not compile or run Foundation on Windows.

## Acceptance and next work

Build rootfull/roothide in helper modes. Drop the first response to a native side effect and verify the retry replays once; exceed the byte window and confirm an old ID reports unavailable without repeating the effect. Verify collisions, exceptions, policy denials, session reset and cleanup. Measure retained bytes/RSS and encode/decode costs separately from polling delay under real screenshot/OCR/result mixes. Qualify CommonCrypto/JSON behavior on supported iOS versions.

Continue P0-12 event-driven helper transport with session/request ownership and reconnect ordering, remaining P0-13 adapters, P1-40 asynchronous/memory-only invalidation and P1-41 streaming fingerprints. C01/C02 performance/device acceptance remains open.
