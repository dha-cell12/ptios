# C03a — chunked FileHandle readLine without a persistent tail cache

Date: 2026-10-29 (Asia/Bangkok). Baseline: `94634ed3`, containing C02b56; the user reported that build passed.
Status: **user reported corrected build `208bf6a0` passed before C03b; independent device/performance qualification pending**.
Finding: **P1-43**. C03 begins; C02's remaining metadata/invalidation/qualification work stays open.

## Result and scope

The shared TLinkJSFileHandle readLine implementation reads regular seekable files in chunks instead of one read syscall and append per byte. This shared source is linked by rootfull/roothide pccontrol, the JavaScript helper and production TrollStore streamd. TouchPOC remains excluded.

Choose chunking once when opening a readable descriptor: fstat must identify a regular file, and a zero-offset SEEK_CUR probe must succeed. Detection failure and nonregular/nonseekable descriptors retain the byte-at-a-time path; write-only handles skip the probes. No open flags, modes, permissions, aliases, handle limits or caller policies change.

Use a fixed 8192-byte stack buffer. Start with one byte so an empty LF line requires no speculative tail; then read up to 128 bytes, progressing to 8192 for longer lines. Each read remains capped by the remaining transfer limit. Find LF in the returned chunk and rewind any unused tail before appending bytes to the result. No unread bytes or decoded text are cached across calls.

The portable fixture's 512-KiB line uses **67 read callbacks instead of 524,289**. These are controlled read-call counts, excluding once-open probes; they are not device latency, total syscall, physical disk I/O, CPU or RSS measurements. Very short nonempty lines followed by more data can add a tail seek; supported-device workload profiling remains necessary.

## Contract and errors

Preserve all response fields: data, line, base64, bytes, encoding, eof and truncated. The text/base64 dual representation from P1-44 remains. Strip the final CR exactly as before, including the historical limit-boundary effect on truncated. Do not consume an LF beyond a full transfer limit or probe EOF after LF or an exact-size read. Empty-line/EOF and malformed UTF8/binary behavior stay unchanged.

On success the descriptor points just after the consumed LF, or after the consumed limited/EOF data. Existing readRequest, seek, tell, write, append, flush, close, JavaScript bindings and their synchronization remain unchanged. Discarding readahead means subsequent operations see fresh file data after external edits, truncation or growth. Neither implementation supplies a snapshot across concurrent external modifications during a single call.

Keep partial-read and EINTR handling. A failed tail rewind returns file_read_failed with the saved errno, rather than acknowledging a partial line after losing its logical boundary. The failed read may already have advanced the descriptor, as failed I/O can consume data; callers can explicitly seek to recover. No implicit retry/replay of that failed line is added. Restore the tail before invoking the append callback so an append exception cannot leave the descriptor beyond the consumed delimiter. Existing blocking-read and interruption policies are unchanged.

## Verification

Both workflows run the new check-file-handle-safety runner. All **63 workflow runners** (36 source-contract, 27 native), 521 existing source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The focused portable/FileHandle source check passes. Sixteen artifact-only checks require CI outputs. New macOS/Foundation/ARC/POSIX/JavaScriptCore/ASan/UBSan compilation/runtime cannot run on this host and remain pending CI; warnings, assertions and sanitizers remain enabled.

The always-host guard reconstructs the complete frozen 94634ed3 FileHandle source after removing only the new include/private selection flag, once-open probes and replacement read loop. This verifies that result formatting, all other operations and JS bindings stay unchanged.

The portable suite compares the new production core with an independent byte-reader oracle over 10,000 randomized byte/position/EOF/CR/limit/error cases and repeated lines, plus explicit 128/8192 transition boundaries. Cover short reads, EINTR, byte-position I/O faults, nonregular byte fallback, failed rewind, append unwind, impossible oversized read counts and zero limit. It also checks the long-line read-count reduction.

The new macOS fixture compiles the complete actual and frozen classes, their real Foundation encoders and JS bindings. Both operate on private temporary files through recorded POSIX boundaries. Compare full replies, contents and positions while mixing line/byte/all reads, seek/tell, write, flush, append and close across all twelve canonical modes and transfer limits. Cover UTF8/binary/CR/EOF, long lines, short/EINTR/EIO reads, failed stat/seek-probe fallback, a real pipe, external pwrite/truncate/growth, rewind failure/recovery, actual JavaScriptCore calls and 128 repeated balanced descriptor lifecycles. No user file is accessed by these fixtures.

## Acceptance and remaining work

CI correction at baseline `8a44fbd1`: Clang rejected the intentionally invalid NSNumber array literal in the older compatibility-batch fixture because the call's NSArray<NSString *> parameter context typed the literal. Store that literal in a raw NSArray local before calling the API so the existing invalid_payload and no-gate/no-touch runtime assertions remain exercised. Keep the public API, production code and -Werror checks unchanged. An always-host guard requires this probe shape; focused Windows native-budget/extraction and assert checks pass, while corrected macOS compilation/runtime remains pending CI.

Build rootfull/roothide, helper and TrollStore. Run mixed readLine/read/seek/write/append scripts against disposable files, including transfer boundaries and changes between calls. Profile realistic line-length distributions, read/seek counts, throughput and per-handle stack cost on devices.

C03's bounded logger, history/config lock and persistence work, log retention, durability/error/recovery, status snapshots and other codecs remain open. C02 still has metadata copies, synchronous P1-40 invalidation and P0-12/device/performance qualification. This checkpoint does not close either group.
