# C03l — checked retirement of narrowly owned history artifacts

Date: 2026-10-29 (Asia/Bangkok). Baseline: C03k working-tree source, build passed according to the user. HEAD remains `0c5de74d`; no separate C03k commit is inferred. Baseline normalized complete history source SHA-256: `b9f1354a2fa793ae8bf56f68907621c3309c8973941fa8d33ec3da55e67b5129`.
Status: **build passed according to the user before C03m; independent device qualification pending**.
User-passed normalized complete history source SHA-256: `76ef6fa6e9d4fa9f1a8ac983a6ed69a58f56c425ae2e7c2506b01bb1232355a3` (working tree; no separate commit inferred).
Finding: **P1-53 cleanup diagnostics and a safe ownership prerequisite for retention**. P1-50 console-log retention remains open.

## Change

Previously retirement trusted any path under the history root, used recursive-capable NSFileManager deletion and ignored its BOOL result. A malformed/stale claim could target a control file, directory or artifact still referenced by retained history; normal deletion failure was invisible.

Retirement now accepts only each retired run's exact standardized `runs/<sanitized-ID>.json`, `evidence/<sanitized-ID>.json` and `evidence/<sanitized-ID>.png` leaves. A set of all retained record/evidence path references protects shared leaves and sanitization aliases. Missing/non-string/outside-root claims are skipped, retaining external screenshot behavior. Other in-root claims report fixed `prune` / `artifacts` / `path_not_owned` diagnostics. Root and direct artifact parent must pass lstat as real directories.

Use nonrecursive POSIX unlink, which removes a leaf symlink without following its target and refuses directories. ENOENT is benign and EINTR retries are idempotent. Other unlink/probe failures report `remove_failed`; ordinary failure continues to other artifacts. Existing per-victim NS/C++ containment remains, plus containment around retained-reference preparation. Exceptions report `exception`; a victim's remaining artifacts may stay behind.

Cleanup still happens only after index ACK and marker clear, under the same monitor/flock. Cleanup failure preserves committed return/event/index state and the recovery gate. No additional IO occurs when no record is evicted; successful eviction adds bounded path/reference/parent validation. Shared rootfull/roothide and production TrollStore use this code; TouchPOC is excluded. No SDK/schema/event changes or real device files were touched.

## Verification

The source guard reverses only C03l and hashes the complete source against the user-passed C03k working tree. Prior C03k/C03j/C03i/C03h hash and earlier full frozen-source comparisons remain, so successful unrelated logic and earlier coordination are preserved. The public contract guard now recognizes the checked screenshot retirement entry.

The macOS actual-source fixture has a targeted unlink seam and real temporary files/flock. Fourteen public begin/finish eviction cases cover success, missing leaves, EINTR, EACCES, errors after unlink effect, and NS/C++ exceptions. They require committed index/return/event state, correct diagnostic counts, independent cleanup after normal syscall failure, lock release, clean marker and no subsequent orphan retry/recovery rescan. Focused ownership cases protect control files/directories/arbitrary leaves/outside files, cross-field retained references and colliding sanitized IDs; prove nonrecursive directory preservation and leaf-symlink target safety; and refuse an evidence-parent symlink. Existing frozen transaction/retention/recovery/marker cases remain.

All 65 workflow runners (36 source-contract, 29 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing, focused history guards/contracts and git diff --check pass on Windows. Sixteen artifact-only checks require CI outputs. New Foundation/POSIX/ARC/ASan/UBSan execution cannot run on this Windows host and remains pending macOS CI. Device stop/restart/disk-full/permissions and latency/RSS measurements remain separate.

## Remaining work

Cleanup is a single post-commit attempt. A process exit or failed unlink can leave orphans; no discovery/retry queue, crash-resumable cleanup, byte/time retention bound or fsync/power-loss guarantee is added. `_logs` uses runtime/helper IDs that can differ from the history run ID and remains untouched pending an explicit ownership contract. Retained index reconstruction, event delivery/replay, arbitrary external changes and other C03/outstanding C02 work remain open. This is not full P1-50/P1-53 closure. Cooperating filesystem actors must use the existing lock protocol; arbitrary external directory-swap races are outside its guarantees.
