# C03ap — Event direct final buffer and JSON lifetime

Date: 2026-11-08 (Asia/Bangkok). Baseline: `1d0e30da`; user reported C03ao build passed and requested a larger batch. Scope: P1-56 shared legacy event wire for rootfull/roothide, production TrollStore, remote forwarding and synchronous wrappers. TouchPOC excluded.

## Delivered together

- Compute the exact padded-base64 length plus the five framing bytes with checked size arithmetic before allocation. Reject an unusable output before any prefix is written.
- Allocate one explicit final NSMutableData buffer and write `0;;`, unwrapped base64 and CRLF directly into its storage. Remove the intermediate Foundation base64 NSData and its append into a growing response.
- Capture the serializer byte count once and retain its NSData throughout the synchronous encode. The input and output spans are distinct; the core owns no memory, retains no pointers and performs no IO.
- Add a normal call pool around serialization and framing. Returned mutable NSData remains owned across the pool; unreturned JSON and temporary objects retire with ordinary success/nil/empty returns. Exceptions propagate through the existing caller policy; independent exceptional pool draining is not assumed.
- Keep the exact previous shared helper as an executable Foundation oracle. No serializer options, error framing, journal/schema/authority/admission/cancellation/socket source or public API changes are made.

Nil/empty JSON keeps the existing error path. Allocation/refused-capacity failures also return nil to the existing root/TrollStore wrappers without publishing partial success. There is no retry and no new application payload/frame limit: the previous maximum batch and over-one-MiB extension behavior remain covered. The JSON-v1 success envelope keeps its existing Foundation string encoder and fields.

This removes one explicit full base64 NSData and its append copy from the legacy producer. The complete JSON NSData and final wire buffer still exist; NSMutableData zero-fill/growth and Foundation internals can allocate. The scalar encoder may have different CPU throughput from Foundation's optimized base64 implementation. No measured device speedup, RSS reduction or whole-operation bound is claimed.

## Verification

All **90 workflow runners** (36 source,54 safety portable subsets) have passing Windows results. **521 source assertions** pass with16 artifact-only checks skipped. Final focused event/core/extraction, JavaScript syntax, seven-file assertion macro preprocessing and diff whitespace checks pass. Apple native branches are skipped on this host.

The previous helper equals exact HEAD. Check complete previous/current header and complete core hashes before the historical source tests. Production consumers and the socket transport fixture compile as Objective-C++ with ARC; no build-target changes are needed.

The actual portable encoder passes:

- 100,000 independent bit-accumulator oracles, every single-byte value and all65,536 double-byte inputs, plus known empty/f/fo/foo/foobar padding vectors.
- Exact-output canaries and short-capacity/null/overflow rejection without writing a prefix. The maximal accepted input is checked independently against the SIZE_MAX framing formula; failed size calculations preserve their out parameter.
- 4-KiB,128-KiB and over-one-MiB payloads, preserving unwrapped output and all tail residues.

Extend the existing Foundation/POSIX/GCD/ARC/ASan/UBSan event executable:

- 1000 exact-byte comparisons with the preceding Foundation NSData encoder using arbitrary byte inputs and padding residues. Assert one explicit final allocation/encode on nonempty input and retained mutable output identity.
- Controlled nil/short/NS/C++ output construction faults. Short output stays untouched and is discarded; root/TrollStore return their existing error bytes, and failed normal buffers retire.
- Old/current success/nil/empty lifetime matrices over32 calls with explicit MRC owner probes. Current ordinary calls leave zero pending probes; the preceding helper defers its probes until the caller pool. Held/weak output checks cover use after the helper and final owner release.
- Retain all earlier256 full JSON wire comparisons, Unicode/NUL/errors, maximum32 payloads, over-one-MiB extension, synchronous/remote forwarding and actual socket delivery tests.

**New Apple compilation and native execution require macOS CI.** Macro preprocessing only checks assertion boundaries. The probes demonstrate controlled call/resource expectations, not Foundation allocation counts or device performance. Full journal rewriting, JSON serialization cost, transport qualification and CPU/RSS/latency measurement remain open.
