# C01d2a — owned temporary screenshot cleanup

Date: 2026-10-23 (Asia/Bangkok). Baseline: `eec10d2`; the user reported the corrected C01d1 build passed before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.

## Race and scope

Root daemon task 21 previously requested ordinary screenshot action 1, then removed the screenshot after matching or IPC failure. If CFMessagePort timed out before SpringBoard finished encoding/writing, the daemon could remove a nonexistent file and SpringBoard could publish it afterward. There was no remaining owner to clean that late PNG. The old helper also used recursive NSFileManager removal on the returned path.

This slice adds explicit ownership for task-21 temporary screenshots in rootfull/roothide. Production TrollStore behavior and TouchPOC are unchanged. The regression runner runs in both workflows because both already validate shared/root contracts. C01 remains open; queue isolation is a separate C01d2b slice.

## Lifecycle and private protocol

1. The daemon generates `/tmp/tlinkautod_capture_<UUID>.png` and exclusively creates a zero-byte, mode-0600 `.lease` sibling before entering IPC. A preexisting output or marker fails admission.
2. Task 21 sends private screenshot **action 4** through C01d1's bounded CF message ID 3. Its existing absolute deadline remains in force. Public screenshot actions 1–3 keep their existing protocol.
3. The receiver accepts only the exact UUID-shaped path and a regular, zero-byte, single-link marker owned by root or the receiver's effective UID, with no group/world permission bits. It snapshots the marker's device/inode and supplies a scoped receiver to the raw screenshot handler. An unscoped action 4, extra ROI fields, mismatched path, missing/replaced marker or expired budget fails before publication.
4. The owned route uses the existing retained screen image/capture, but bypasses the keep-PNG file-copy shortcut. It rechecks lease liveness after opaque capture and before encoding, validates at most 8,388,608 source pixels before encoding; at most 32 MiB of encoded output may enter its writer. It does not create arbitrary parent directories.
5. The writer opens exclusively with `O_EXCL|O_NOFOLLOW|O_CLOEXEC`, mode 0600, and writes in chunks of at most 64 KiB. Marker identity and budget are checked before and between writes and after close. Partial writes and EINTR are handled; short/error/zero writes and close failure discard the owned output. Receiver cleanup checks the created output's device/inode.
6. The daemon accepts an empty successful path as its requested path for compatibility; a different returned path is an error. Its `@finally` and RAII backup remove the marker first, then unlink only the request's private output name after success, matching failure, timeout or exception. The marker remains live through matching, so a successful screenshot is not removed while the matcher reads it.
7. If daemon cleanup happens before a delayed write starts, the writer refuses it. If cleanup races an open write, the client unlinks the name and the receiver's later checkpoint discards its own unfinished/late output. Cleanup uses POSIX `unlink`; it never traverses or recursively removes a returned directory.

There are no added worker pools, recurring timers or directory scans. The existing FIFO, engine concurrency and CF waiting model remain unchanged. Daemon and SpringBoard must be deployed coherently: an older receiver rejects unknown action 4, with no unbounded action-1 fallback. An old daemon continues to use action 1 and does not gain this ownership protocol.

## Limits and remaining work

Cancellation is cooperative. UIKit capture/PNG encoding, filesystem calls and synchronous IPC can still overrun the deadline before returning to a checkpoint. The pixel/output limits do not bound all temporary UIKit/encoder memory or process RSS. A marker does not interrupt an opaque operation; it prevents late output publication and gives the writer a cleanup decision afterward.

The protocol covers normal completion, timeout, cancellation and stack unwinding while cleanup executes. Process termination before daemon cleanup can leave a marker/output; no crash-recovery scavenger is added here. POSIX removal is best effort if the filesystem itself rejects unlink. Device testing must confirm rootfull/roothide permissions and the marker's visibility across the two processes. Namespace identity checks are ownership guards, not a claim of atomic defense against a privileged process deliberately replacing files between syscalls.

C01d2b still needs to address unrelated synchronous owner-queue interference without reordering effects or admitting detached unbounded work. Vendor/capture preemption and crash-retention policy remain explicitly unqualified. No measured CPU/energy/latency saving or hard response SLA is claimed.

## Validation

- Windows aggregate: all 36 source-contract runners, 20 native runners and 528 TrollStore workflow source assertions pass.
- Portable native harness: 100,000 cancel/commit lifecycles; cancellation before open, during write and after commit; partial/EINTR/error/zero/close failures; inherited cancellation/deadline; encoded-size rejection; marker and output identity replacement; no live test descriptors/files.
- macOS fixture: extracts the actual daemon task/helper/path generator, CF callback, raw screenshot handler and write adapter. It uses real Foundation, POSIX files and ImageIO PNG encode/decode with controlled UIKit capture and matcher boundaries. Cases cover success, matcher error/C++ exception, direct receiver Objective-C exception unwinding, foreign reply rejection, missing private scope, symlink/hard-link markers, nonrecursive directory handling, 64 concurrent cancellation/write races and transport timeout while the actual callback is paused in capture.
- The late-result case returns the daemon's transport failure first, verifies marker/output cleanup, resumes capture and verifies no output is published afterward. Exceptions are not propagated across libdispatch boundaries by the fixture.
- Both production workflows run `check-owned-capture-safety.mjs`; the existing socket fixture imports the new callback dependency explicitly. Strict warnings, ASan and UBSan remain enabled for macOS.
- **The macOS fixture and final iOS builds were not run on this Windows host.** Actual UIKit capture, real OpenCV behavior, device permissions and performance remain pending.

Device acceptance: exercise task 21 against a warm/cold capture, kept screen, timeout while capture/encoding runs, disconnect during matching, normal/error paths and service restart. Inspect only the test request's UUID marker/PNG after late work finishes. Verify legacy screenshot actions and successful task-21 reply fields, then measure opaque overrun separately from cleanup correctness.
