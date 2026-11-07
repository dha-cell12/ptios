# C03ao — Complete direct line buffer/result package

Date: 2026-11-08 (Asia/Bangkok). Baseline: `3bffe88a`; user reported C03an build passed and requested a larger batch. Scope: shared rootfull/roothide/helper/production TrollStore FileHandle, P1-43/P1-44. TouchPOC excluded.

## Delivered together

- Read each line chunk into the owned NSMutableData tail instead of an 8192-byte stack buffer followed by append. The checked core requests writable storage for each read and never retains a pointer across another grow. It keeps the preceding 1/128/8192-byte quantum, one-byte nonregular fallback, short/EINTR handling, EOF and invalid-result checks.
- Restore an over-read tail to the same descriptor before returning success. Check errors before trimming/publishing the committed prefix; no persistent unread cache survives. Preserve subsequent read/seek/write behavior and visibility of external file edits.
- Keep CR stripping and the existing EOF/truncation rule after successful byte trimming. All four public line entries use the same implementation: readLine(), read('*l'), readText('*l') and readBase64('*l'), including the 'line' alias.
- Construct the final mutable dictionary directly for each representation. Preserve keys, values, data/line object identity, result mutability and the legacy decode-before-base64 order. Text/base64 entries still skip the unused codec. The intermediate immutable result plus mutableCopy is no longer needed for line reads.
- Keep numeric/all reads, public headers and JS bindings, open/path/authority/limits, writes and descriptor cleanup unchanged. Existing scripts use the new line path automatically.

Growth happens before the next read, so allocation/null-buffer/grow-exception timing can differ from a former append failure after IO. The new null destination reports ENOMEM; exceptions propagate without replaying consumed bytes. A failed call publishes no prefix. This does not establish an overall IO-time bound or make pipe reads asynchronous.

The producer no longer performs the explicit staging append or intermediate result copy. NSMutableData can still allocate, move, zero-fill or retain capacity, and dictionary factories can allocate internally. Device CPU, allocations, peak RSS and latency remain unmeasured.

## Verification

All 90 workflow runners (36 source,54 safety portable subsets), focused FileHandle/core/extraction, JavaScript syntax, native assertion macro boundaries and diff whitespace pass on Windows. Apple native branches are skipped on this host. Source workflow assertions are recorded in STATE.md.

Freeze the exact preceding line implementation. Reversing the added include, result factory and line region reproduces the complete previous class before all historical guards. The direct core and factory are hash-guarded as complete regions. Native fixture generation also constructs the entire immediate-predecessor class with checked symbol renaming; its unchanged mode-plan factory is shared rather than redefining a private friend. Public headers and the physical-open body retain their existing guards.

The actual portable core executes 100,000 comparisons against the preceding chunk/append algorithm, including bytes, offsets, read/rewind counts, EOF, CR, limit and errors. Every grow moves storage while the previous allocation remains live, testing pointer invalidation and committed-prefix retention. Additional cases cover zero/SIZE_MAX limits, 512-KiB/chunk boundaries, short/EINTR reads, false/throwing rewind, null growth, invalid read sizes, missing errno and grow/read unwind. A 512-KiB line still takes 67 reads; syscall reduction belongs to the earlier chunking package, not this change.

Extend the existing Foundation/POSIX/JSCore/ARC/ASan/UBSan executable:

- 540 complete preceding/current result/offset/read/rewind comparisons across nine boundaries, three caps, four public entries and five IO scenarios. Instrument every new read destination against the current NSMutableData tail and offered size.
- Check held results after pools, mutable dictionary behavior and identical data/line references. Existing binary/Unicode/NUL/pipe/JSCore cases continue to exercise the new line path.
- Inject grow NS/C++ faults before the second read, verify the committed position and successful recovery, and retain default decode-before-base64 exception priority after tail rewind.
- Keep 3780 selected-representation comparisons using the immediate chunked predecessor for exact syscall counts. The original single-byte reader remains an independent full API/byte/position oracle; its read counts intentionally differ.

**New Apple compilation and native execution require macOS CI.** Macro preprocessing only checks assertion boundaries. Growth overhead, opaque Foundation behavior, blocking IO and device qualification remain open.
