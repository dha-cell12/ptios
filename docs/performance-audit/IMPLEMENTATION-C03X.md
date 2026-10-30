# C03x — descriptor-bounded failure console tail

Date: 2026-10-30 (Asia/Bangkok). Baseline: `e6b1580a`, C03w build passed according to the user. Complete normalized `shared/TLinkRunHistory.mm` SHA-256: `6534189312096e6ebd45383b63b0a57b7c90efa5787eb2b3387e52adfe102727`.
Status: **source implemented; new Foundation/POSIX/ARC/ASan/UBSan cases pending macOS CI; device IO qualification pending**.
Finding: **P1-49 failure-evidence preparation**, partial improvement.

## Problem and change

The 256-KiB console-tail limit was based on pathname metadata obtained before opening NSFileHandle. A replacement could supply another file's size, and readDataToEndOfFile could include later growth beyond the intended window. Large or actively growing logs could therefore allocate/read more than the documented tail cap.

Open the leaf once with O_RDONLY|O_NOFOLLOW|O_NONBLOCK, then fstat that descriptor and admit only positive-size regular files. Fix a window ending at that observed size, starting at max(0, size minus 256 KiB). Allocate at most that many bytes and pread at most 64 KiB per syscall, handling EINTR and short reads. Appends cannot extend the window; pathname replacement after admission does not replace the open descriptor. An error or early EOF discards the incomplete tail. Finally closes the descriptor on ordinary returns, NS exceptions and C++ unwind.

Keep UTF8 decoding, newline splitting, redaction, final-50-line and 1,000-character rules exactly as before. Preserve invalid UTF8's empty-tail behavior, including a multibyte sequence cut by the window boundary. Empty/missing/inaccessible/nonregular/symlink leaves produce an empty best-effort tail. NS exceptions still produce an empty tail; C++ exceptions retain preparation's existing propagation behavior. A failed run can still persist its original error with an empty tail. Supplied nonempty log lines continue to bypass file IO. Preparation remains outside the file lock; no lock/marker/index/recovery/event/schema or SDK changes.

The helper is shared by rootfull/roothide and production TrollStore; the latter normally supplies its in-memory tail. TouchPOC is excluded.

## Verification

Replace only the console-tail function with its frozen predecessor and hash the entire source against the user-passed C03w baseline. Keep all earlier complete-source comparisons. Guards require same-descriptor metadata, a fixed bounded buffer/window, chunked pread/EINTR, finally close and no pathname size lookup/read-to-end call. The runtime adapter compiles the actual changed source, with separate instrumentation for console descriptors, allocations and payload bytes.

New actual/frozen Foundation cases compare stable files at 0/1/256-KiB-minus-one/exact/plus-one/larger lengths, redaction/Unicode/newlines, invalid UTF8 and a cut multibyte character. Count actual bytes and require no more than 256 KiB. Inject open/stat/read/EOF, short reads/EINTR, NS/C++ allocation/read failures and require descriptor release. Real file operations append 2 MiB after fstat, replace the pathname or truncate the admitted file; verify the frozen window/descriptor or empty incomplete result. Refuse symlink/FIFO/directory/missing leaves before buffer/payload reads. Public failed finish tests preserve persisted redacted tail and original-error ACK with empty tails on IO/NS failures; supplied lines bypass the reader.

Windows validation passed: all 65 workflow runners (36 source, 29 native), 521 workflow source checks, focused complete-source/history guards/contracts, expanded assert preprocessing including the new fixture and `git diff --check`. Sixteen artifact-only checks were skipped. New Foundation/POSIX/ARC/sanitizer execution requires macOS CI; device IO/RSS/latency measurements remain pending.

## Limits and remaining work

The cap covers bytes in this fallback read/buffer, not every NSString/array/JSON producer or process RSS. The window is not an immutable snapshot: an in-place rewrite can mix bytes, and a truncation may yield an empty tail. No filesystem deadline, repeated-EINTR bound, fsync, ancestor-directory pinning or new durability guarantee is added. Whole-index rewriting, status caching, external log retention and other C03 work remain separate.
