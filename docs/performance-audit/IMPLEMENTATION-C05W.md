# C05w — Bounded owned JSON storage and immutable transfer

Date: 2026-11-06 (Asia/Bangkok). Baseline: `2e1e077b`; user reported C05v build passed and requested continued implementation. Continues C05/P1-60 in the shared helper used by four rootfull/roothide/production TrollStore UI codecs. TouchPOC excluded.

## Storage and publication

Replace the stream's NSMutableData payload with a move-only C++11 buffer. Append complete external chunks after the existing hard quota, captured caller-stop and remaining-output checks. Grow requested capacity geometrically from 128 bytes, clamping the final request to 786426 bytes. Reject overflow or allocation failure without losing the previous pointer; failure remains terminal. A failed realloc leaves its old allocation owned until close/unwind.

After the existing writer/status/count/error checks, seal and move the buffer into a shared owner. Create immutable NSData with `initWithBytesNoCopy:length:deallocator:` instead of explicitly copying NSMutableData. The deallocator captures a local shared owner by value, without retaining the stream, budget or resulting NSData. Its buffer has no NSData back-reference. Release is idempotent; stream close also releases any prefix that was never transferred, while scalar diagnostic counts remain available.

The [Apple NSData deallocator initializer](https://developer.apple.com/documentation/foundation/nsdata/init(bytesnocopy:length:deallocator:)?language=objc) supplies the ownership boundary. Do not assume a particular Foundation class or internal storage representation. Nil/wrong-length construction is refused; NS/C++ failures propagate after finally-close. Existing post-construction stop and post-pool output checks can discard a late result. No failed prefix is returned, no caller output is reserved, and the final codec/sink gates remain.

Public APIs, protocol limits, four codec sources and all query/action/authority/tap ordering remain unchanged. A stop/output failure cannot roll back a committed action. This adds no socket/session budget binding or preemption inside Foundation.

## Scope and cost

The cap applies to the requested capacity of this raw application buffer. A realloc may transiently hold old and new storage; allocator metadata, shared-owner/control-block overhead, the Foundation encoder/NSData implementation, base64/final wire, input graphs/provider/root/error data and whole-operation/global RSS are outside it. Geometric spare capacity may exceed the logical byte count and may exceed a smaller native remaining-output allowance; accepted bytes still obey that allowance. No universal zero-copy, lower RSS, lower latency or throughput improvement is claimed. Shared ownership and allocation bookkeeping add work. C05/P1-60 remain partial.

## Verification

Freeze the complete preceding C05v writer and require its exact hash/reversal before the existing writer/task/server/AX restoration chains. Retain the same 90 workflow runners.

Portable tests exercise 20000 exact-byte/chunk/move/seal/idempotent-release lifecycles, exact maximum requested capacity, one-byte overflow, size_t extremes, initial/growing allocation failure with preserved pointer/count, and C++ resize unwind. All traced buffers retire to zero.

Extend the existing Foundation/CoreFoundation/ARC/ASan/UBSan executable with actual NSData creation/deallocation over traced raw allocations: 128 held-result/pool lifecycles, immutable bytes after source retirement, terminal sealed publication, nil/wrong-length construction, NS/C++ factory faults, post-adoption cancellation and factory discard. Check stream/owner retirement after normal caller pool drain. Compare 64 Unicode/nested decoded graphs per unchanged codec route against the complete C05v producer. Existing quota/output/stop/exception/boundary tests now exercise the new storage; existing held-result tests also require native budgets to retire independently.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete writer/task/server/AX restoration, frozen writer identity, native alias/fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Apple/iOS compilation and Foundation/ARC/ASan/UBSan execution require macOS CI. Real transport/private AX/UI effects and device performance/memory qualification remain pending.

Follow-up (2026-11-07): correct the ownership fixture's caller-pool retirement boundary around NSData byte reads and add explicit MRC lifetime extension plus phase/condition/stderr diagnostics. Production ownership is unchanged. The reported SIGABRT excerpt omitted its assertion; see `FIX-AX-JSON-OWNERSHIP-LIFETIME.md` for scope, evidence and native validation limits.
