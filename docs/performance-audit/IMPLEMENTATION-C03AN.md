# C03an — Prepared JSON bytes through existing text writers

Date: 2026-11-08 (Asia/Bangkok). Baseline: `bfe45dcd`; user reported C03am build passed and requested a larger batch. Scope: P1-47 rootfull/roothide and helper writeJSON. Production TrollStore already writes serialized NSData directly and remains unchanged. TouchPOC excluded.

## Change

The root/helper serializer previously decoded JSON NSData into an NSString, then passed it through writeText, whose UTF8 writer encoded the string again. Add a private immutable NSString adapter retaining both the decoded string and an immutable copy of the serializer bytes. Its UTF8 size/data/write methods use those bytes; ordinary string primitives and other encodings use the decoded string. The snapshot copy protects against mutable NSData changes and normally retains an already immutable serializer result.

Only the JSON string constructor and private include change in each frontend. Root still constructs the same writeText child request and reenters the complete native gate/context/error path. Helper still delegates to its existing writeText method and preserves its two operation counts. Path resolution, parent creation, JSON and text limits, error priority/format, atomic flag and response fields retain their source. Raw writeText and the FileHandle APIs remain unchanged.

The adapter uses the original UTF8 decode; invalid data still reaches the existing `{}` fallback. If decoding changes the UTF8 byte count, such as a normalization of a BOM, construction returns the decoded string so its original writer behavior is retained. Non-UTF8 writes also delegate to that backing string. Data writer failure or NS/C++ exception is returned/propagated through existing code once, without retrying a partial effect.

The adapter is private to the root/helper translation units. No Makefile/source-target changes, public API, new request field, TLS handoff, cache or transport message are needed. String equality, copy, indexing and formatting continue to work for existing child-request consumers; retaining that argument also retains its encoded snapshot until it is released.

This avoids requiring another UTF8 encoding at the ordinary JSON writer, while preserving the decoded string for compatibility. It adds a small adapter object and retains the serializer data through the write. Foundation may already optimize parts of its former string writer; no device allocation, RSS or timing improvement is claimed. Disk IO remains synchronous.

## Validation

All **90 workflow runners** (36 source,54 safety portable subsets) and **521 workflow source assertions** pass on Windows;16 artifact-only assertions are skipped. Focused FileHandle/storage extraction, JavaScript syntax, eight native files' assertion macro boundaries and diff whitespace checks pass. Macro preprocessing does not establish Apple type correctness.

Freeze the exact preceding root/helper JSON-write regions. Only the constructor/include changes reverse to the complete prior files before the existing historical source checks. Guard the complete adapter too. The existing252 three-backend current/frozen storage reply/IO/count/error comparisons now exercise the new adapter in the current root/helper paths.

Extend the existing Foundation/POSIX/ARC/ASan/UBSan executable:

- 42 immediate-predecessor/current full reply/file/path/count/error comparisons, including valid/invalid objects, authority/path refusal and exact512-KiB admission boundaries.
- A Foundation-backed immutable NSData probe verifies that accepted root/helper writes call the retained serializer data writer once, with NSDataWritingAtomic and exact file bytes. Six actual child-path writer failures and NS/C++ unwinds verify no retry, unchanged helper counts, errors and committed file state.
- 1000 serialized Unicode/NUL/nested graph cases compare full NSString semantics, copy/mutable-copy, indexing, UTF8/UTF16/ASCII encoding and atomic/non-atomic real files. Empty, invalid UTF8 and BOM inputs also exercise construction/fallback.
- Mutable NSData edits cannot alter the held string or UTF8 snapshot. Explicit caller pools cover retained arguments, weak backing-data retirement and direct writer faults.
- Real directory/missing-parent failure codes/descriptions and overwritten-file mode/owner/group effects are compared with NSString's writer, including read-only files and both atomic choices.

**New Apple compilation and native execution require macOS CI.** The probe counts are controlled expectations, not device measurements. Full Foundation-internal allocation/IO behavior, adapter overhead and real-device qualification remain pending. P1-47 remains partial because one compatibility decode and the other synchronous storage operations remain.

## CI correction — invalid destination compatibility (2026-11-08)

CI reported a complete storage-operation parity failure for helper/backend 1, writeJSON, policy 2. This fixture returns `ok=YES` with no `path`; the adapter was still selecting NSData's UTF8 writer, while the complete predecessor selected NSString's writer. Dispatch nil, empty and non-string destinations to the original decoded NSString writer before any IO. Valid UTF8 paths keep the retained NSData path; non-UTF8 paths retain their existing NSString delegation. Never try another writer after failure/exception.

Freeze the entire preceding adapter and reverse exactly the new selection to its original guarded hash, without changing frontend/gate/error/count source. Keep strict reply/trace/file/error comparisons, add bounded expected/actual details, tighten the nil-target encoded-data writer count to zero, and add 16 native direct comparisons across four invalid target shapes, two atomic choices and UTF8/UTF16. Existing valid-data identity, write faults, directory/missing-parent errors and metadata effects stay enabled.

Windows source/portable FileHandle checks, five-file assertion macro preprocessing, JavaScript syntax and diff whitespace pass. This host cannot execute Foundation/ARC; corrected native parity and the new invalid-target matrix await macOS CI. No Apple build success is claimed.
