# C03am — Explicit FileHandle read representations

Date: 2026-11-08 (Asia/Bangkok). Baseline: `0bca11b8`; user reported build passed and requested a larger implementation batch. Scope: P1-44 shared FileHandle in rootfull/roothide, helper and production TrollStore. TouchPOC excluded.

## Delivered together

- Add `readText(request)` and `readBase64(request)` to the shared JS object, with native entry methods on the shared handle. Both accept the existing full-file, byte-count and line requests. Omitted/null JS input retains the full-read default.
- Reuse one numeric/all reader and one line reader for all representations. Keep descriptor synchronization, readable/closed checks, exact error priority, transfer limit, direct-fill/chunk/rewind behavior, file-position effects, CR stripping, EOF and truncation semantics. Legacy line dispatch still honors the existing `readLine` entry.
- Text reads produce the existing UTF8 `data`/`encoding` result, and `line` for line requests, without producing base64. Invalid UTF8 retains the existing empty text and binary encoding indication; no replacement-character or implicit fallback policy is added.
- Base64 reads produce `base64` and `encoding: base64`, without decoding UTF8 or returning `data`/`line`. Empty input follows the same explicit representation. Byte-count and line consumption are identical to the prior reader, including binary line CR/newline handling.
- Keep the original `read`/`readLine` response formatter intact. Existing callers still receive both text and base64; adopting the new methods is explicit. The original JS bindings, shared physical-open body, frontend path/authority/mode gates, handle limits, writes, close and session cleanup remain unchanged.
- Scope new callbacks and reader preparation with the same normal operation pools. Codec or syscall exceptions retain their propagation and consumed-byte effects. There is no replay, seek-back after formatter failure, retry or new buffering cache.
- Document payload shapes, invalid text and byte-count behavior, usage and older-build feature detection in `docs/tlinkauto-js-runtime.md`.

The change removes the unused explicit conversion on opted-in reads. It does not make disk IO asynchronous, remove the underlying NSData, change the 512-KiB limit or automatically migrate existing scripts. No allocation/RSS/CPU/latency improvement has been measured on a device.

## Verification

Freeze the exact previous read region and header. Check complete current implementation/header hashes, every inserted region and changed read region; reversing only these changes reproduces the complete user-passed C03al class/header before all previous historical guards run. The original physical-open body and three frontend sources remain covered by their existing complete guards. Current native formatter extraction checks both UTF8 and base64 seams on Windows as well as macOS.

All 90 workflow runners (36 source, 54 safety portable subsets) and 521 source assertions pass on Windows; 16 artifact-only assertions are skipped. Focused FileHandle checks include existing 100k descriptor-owner and 10k direct read/write/line oracles. Assertion macro boundaries across six touched native files pass; this is preprocessing, not Apple type checking. JavaScript syntax, workflow assertions and the broader workflow runner results are recorded in STATE.md. Apple branches are skipped on this host.

Extend the existing Foundation/POSIX/JSCore/ARC/ASan/UBSan executable, without adding a workflow runner:

- 3,780 current comparisons against projections of the complete frozen reader across five byte inputs, three caps, twelve requests, seven IO/state scenarios and three representations. Compare full result graphs, offsets and read/rewind counts. Inputs include empty, invalid UTF8, embedded NUL, Unicode, CRLF and over-512-KiB data; scenarios include short/EINTR reads, EIO, nonregular fallback, rewind failure, write-only and closed handles.
- Instrument the actual two formatter paths. Successful legacy reads must call both codecs; text/base64 must call only their chosen codec; failed reads call neither. An unused codec configured to throw must have no effect.
- Chosen-codec NS/C++ exceptions after IO preserve the consumed position and permit recovery; actual syscall exceptions precede all codecs. Explicit MRC owners cover normal formatter retirement and outer-pool exceptional cleanup, with held result graphs surviving return.
- Real pipe line/full reads preserve CR/newline/EOF behavior without seeking. Real JSCore invokes both emitted methods with omitted/undefined/null/zero/count/line/full/invalid inputs, retains the handle beyond object-creation pools and closes all descriptors across 64 lifecycles.
- Existing complete legacy/current mixed-operation, frontend/mode/authority, file payload, constructor, binding, IO fault and pool tests remain.

**New Apple compilation and native execution require macOS CI.** These are controlled codec-call/resource expectations, not measured Foundation internals, device throughput or peak memory. Two added binding closures and legacy forwarding also have unmeasured cost. Script adoption and device qualification remain open; P1-44 has an explicit efficient path while its compatibility path intentionally retains both representations.
