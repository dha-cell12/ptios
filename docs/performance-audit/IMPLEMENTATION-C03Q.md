# C03q — bounded journal file reads and encoded output

Date: 2026-10-29 (Asia/Bangkok). Baseline source: `a39ec7b7`, including C03p, build passed according to the user. Previous documentation/header edits remain in the working tree. Complete normalized event source SHA-256 before this stage: `6ccb48528fe7a59792a7f70c5a730598403476db99841aa6ea20efaeec73b020`.
Status: **build passed according to the user before C03r; committed at `0340a8e3`; independent device qualification pending**.
Finding: **C03/P1-54/P1-58 predecode journal admission**, without changing the retained JSON schema or publishing algorithm.

## Change

The checked reader still loaded the entire file through NSData before validating its 256-event shape, allowing an oversized or special file to allocate/read outside that event limit. Add a 4-MiB file admission limit and a descriptor-owned read helper under the existing flock.

Open read-only with O_NOFOLLOW|O_NONBLOCK. Only open errno ENOENT means genuine absence; all other open failures are read_failed. Require fstat regular type and nonnegative size, reject size above 4 MiB with event_journal_too_large before a journal buffer allocation or payload read. Symlinks (including dangling links), FIFO and directories are refused without following/blocking on their contents. Existing direct-root/lock checks are unchanged.

Allocate only the admitted length, read it in at most 64-KiB calls, retry EINTR and accumulate short reads. Early EOF/read error is read_failed. After the admitted bytes, probe at most one more byte: observed growth is read_failed, or too_large when already at the cap. The private descriptor closes in finally, including NS/C++ unwind. Cooperative atomic replacement leaves an already-open inode stable; arbitrary in-place mutations do not acquire a new consistency guarantee. Empty regular files still reach the existing invalid-JSON policy.

Remove the NSData NSError bootstrap classification because journal IO now uses checked POSIX open/read/stat. Share the same helper across publisher/status/poll through the existing checked reader. Fixed read_failed/too_large errors preserve journal/cursor and flow through C03n/o failure/cache handling. No repair/deletion or extra normal rewrite pass is introduced.

Cap encoded writer NSData at the same 4 MiB before attempting its atomic write. A larger encoded result returns the existing write_failed outcome with no write/hint or file replacement. Existing canonical 256 events with 4096-byte payloads and bounded metadata fit comfortably; externally added extension data can now require explicit maintenance before publishing. Valid files at the cap are readable. Preserve success fields, JSON encoding, retention, cursor, inode/permission/lock protocol, notification and best-effort caller behavior. Shared rootfull/roothide and production TrollStore are covered; TouchPOC is excluded.

## Verification

The safety guard removes only the bounded helper/constant, restores the previous NSData read block and removes the writer byte check, then hashes the complete source against `a39ec7b7`. Prior C03p/o/n full-file reverse/hash guards remain. Require nonfollowing/nonblocking regular-file admission, size validation before buffer allocation, 64-KiB reads/EINTR, one-byte probe, finally close and an encoded writer cap before atomic write.

The actual-source macOS fixture tracks separate journal/lock descriptors, real read bytes, buffer allocations and syscall boundaries. Existing semantic read-failure injection remains at the checked-data boundary; old Cocoa/POSIX/nil-NSError injections are replaced by the same generic failure outcomes, while new POSIX tests cover actual ENOENT/bootstrap and open/stat/read errors. No previous error/result assertions are relaxed. New cases cover a real sparse 4-MiB-plus-one file with zero journal buffer/payload reads, open/stat failures, negative reported size, early EOF/EIO, EINTR then short reads, NS/C++ exceptions after descriptor allocation and observed growth. Refusals must preserve files, avoid writes/hints and leave no journal/lock descriptors or poll leases.

A valid padded file exactly at 4 MiB must read through bounded chunks and EOF probe without rewrite. Real symlink/dangling/FIFO/directory paths must be rejected while target bytes/mode/children remain. A normal maximum-count/payload/token journal must still publish. Valid extension data filling the exact cap must be accepted for reading, then an oversized append must fail before atomic write and preserve the old file. Explicit repair resumes normal publication. The focused case runs after the existing read cases, restores the original journal and suppresses hints so original registration order and quiet-read counter checks remain isolated. All B06/C03n/o/p cases remain.

Windows validation passed: all 65 workflow runners, 521 source checks, focused event core/contract guards, expanded assert preprocessing and `git diff --check`; 16 artifact-only checks were skipped. New Foundation/POSIX/ARC/ASan/UBSan execution requires macOS CI, with device filesystem/IO/latency/RSS qualification separate.

## Remaining work

This bounds raw file/buffer bytes and encoded output, not total JSON graph/RSS or IO/CPU time. The writer still encodes before checking output, and arbitrary publisher payload serialization is not newly bounded here. Every publish still reads/validates/rewrites the whole journal. Deep/unusual valid JSON, device storage stalls and metadata cost need qualification. Missing-file epoch/cursor reuse, corrupt-file reconstruction, replay/fsync/power-loss ordering and other C03/outstanding work remain open. Full P1-54/P1-58 closure is not claimed.
