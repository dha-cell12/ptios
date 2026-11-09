# C03ax — Completed console log retention

Date: 2026-11-09 (Asia/Bangkok). Baseline: `5531db13`; user reported the latest build passed and requested larger implementation packages. Scope: P1-50 for the production root/roothide runtime core and JavaScript helper. TouchPOC is excluded. Production TrollStore's common debug backend keeps its separately implemented C03aw policy.

## Terminal ownership and integration

Previously `_logs/<UUID>.log` and `_logs/<UUID>-helper.log` accumulated across runs. Each writer already rotates its active file, but history retirement only owns history artifacts; it cannot safely infer ownership of arbitrary console paths.

Add one header-only retention module, shared by both writers. Root calls completion only after `finishConsoleLogging` has closed admission and synchronously drained accepted disk/system work. Helper owns a scoped completion after creating its headers; its synchronous log writes and terminal summary precede scope retirement, including early return and C++ unwind. Mark the final pathname's inode rather than an initial descriptor, because ordinary rotation can replace the initial inode during execution. No run-long descriptor, timer, queue, framework or linked implementation is added.

Only completed UUID-shaped `.log` / `-helper.log` leaves in a direct `_logs` directory can be marked. Latest files are never eligible. A regular, single-link file owned by the current effective UID, without group/world write permission, is checked through `openat`/`fstat`/`fstatat` with no-follow flags and a nonblocking exclusive lock. Its completion xattr contains a version and its device/inode identity. A copied xattr on a different inode does not prove completion. Marking is best effort, and retention allocation/IO failures cannot throw through the logger's business result.

Writers must never append after completion or reuse a completed UUID. Existing root generation/admission and helper synchronous execution provide this boundary. Unmarked active/legacy files remain outside cleanup. A fatal process exit, cleanup not reached, unsupported xattrs or refused permissions can leave an unmarked file; no startup/orphan migration is attempted.

## Selection and retirement

On completion, scan the direct log directory once with a fresh enumeration offset. Stop after 4096 non-dot entries; an incomplete or failed enumeration removes nothing. Collect only UUID leaves with a matching device/inode proof, ownership/mode/link checks and matching pathname metadata. Candidate storage is bounded by that scan count, and no file payload is read.

Keep the 50 newest eligible files by modification seconds, nanoseconds and then lexical filename. Root/helper logs share this selection when their effective UID is the same. Different owners, active logs, unmarked legacy files and files with invalid proofs are excluded. The target is completed files per directory/UID, not a global disk-byte/RSS quota. Wall-clock changes affect mtime ordering; this is not execution-order retention.

For each older candidate, reopen relative to the held directory, acquire an exclusive nonblocking lock, and recheck device/inode/size/mtime/ctime, proof, permissions, link count and pathname identity. Unlink exactly that leaf with `unlinkat(...,0)`. No recursive delete, path-prefix sweep, index rewrite or history artifact cleanup is performed. Busy/changed/missing/refused files are skipped; cooperating concurrent cleaners converge on the same newest set without waiting on each other.

This is best-effort retention. Concurrent completions and skipped victims can temporarily exceed 50 until a later completion. Old unmarked logs and directories exceeding the scan cap require separate migration/cleanup; they are preserved. Locks coordinate cooperating cleaners, not arbitrary file mutations after the last pathname check. The proof is a cooperation marker, not a secret or authorization credential. No arbitrary-race, power-loss or durability guarantee is added.

Retention is independent of the global 50-record history. History JSON, failure tail/evidence and latest files remain unchanged; older history console-path references can refer to logs retired under this separate file policy. The sweep adds bounded discovery/metadata work to terminal cleanup and still performs synchronous opaque filesystem calls. Device termination latency, xattr support, IO, CPU and memory require measurement.

## Regression coverage

Exact full-source reversal/hash guards recover both preceding root core and helper files by removing only the new include and terminal hook. Compose these reversals with existing console-vector and storage guards; all prior logger, file, helper, HID and authority checks remain. Existing build targets and public headers are unchanged. The existing console workflow invokes the retention runner, keeping the workflow runner count unchanged.

Portable tests execute 100000 independent UUID/refusal, permutation/mtime/nanosecond/tie-order, big-endian identity proof and seven-field change cases. The existing console/vector/admission/production logger tests remain enabled.

The macOS C++/POSIX/ASan/UBSan fixture uses only a private temporary tree and real xattr, openat/stat, flock, unlinkat, directory enumeration and disposable children. Cases cover 100 completed root/helper files retaining exactly the newest 50, active/legacy/latest preservation, scan-cap refusal, busy locks, replacements/appends/marker changes, hardlinks/symlinks/FIFOs/directories, foreign/copied proofs, unsafe modes, parent symlink/scope refusal, eight concurrent cleaners and 128 normal/throwing completion scopes with balanced fixture descriptors. Existing Foundation/GCD/JSCore tests still exercise the unchanged logger drain/lifecycle behavior; actual application hooks/device cleanup require qualification.

Validation: all90 workflow runners have passing Windows results (36 source,54 safety portable subsets). The first console run passed its assertions but hit a transient Windows executable-unlink EPERM; its focused rerun passed after bounded cleanup retry. All521 workflow source assertions pass (16 artifact-only checks require CI outputs), along with JavaScript syntax and five-file assertion macro preprocessing. Corrected/native Apple compilation/execution, xattr/filesystem behavior on root/roothide and device performance remain pending CI/device qualification. P1-50 remains partial for unmarked legacy/orphan files, alternate legacy runtime and global byte/age policies.
