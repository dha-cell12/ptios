# C03b — bounded disk-console log admission and run retirement

Date: 2026-10-29 (Asia/Bangkok). Baseline: `208bf6a0`, containing C03a and the compatibility-batch fixture correction; the user reported that build passed.
Status: **user reported build `cf7ed56d` passed before C03c; independent device/performance qualification pending**.
Finding: **P1-42, bounded disk-log queue slice**. C03 remains partial.

## Result and scope

The rootfull/roothide in-process TLinkJSRuntimeCore disk logger admits at most 64 simultaneous reservations across formatting, queued and executing writes. Each reserves a maximum 16-KiB encoded line: at most 1 MiB of admitted encoded payload per runtime instance. Reserve before message conversion; when full, drop the newest disk-log attempt immediately. One lifetime budget survives run changes, so old provisional formatters remain charged.

Bound message prefixes to 4096 UTF16 units and level prefixes to 64, preserving a complete surrogate pair at the cut. Escape CR as before; append a [truncated] marker when the message is cut. Count level/message truncation once per admitted entry. Encode the completed line once and share the immutable NSData between runId.log and latest.log, instead of encoding separately for each path. Reject encoding failure or an encoded line above 16 KiB. Local producer and worker autorelease pools retire temporary formatting/file objects.

These are application-owned admission/payload limits, not a total process RSS or Foundation allocation guarantee. Upstream JavaScript argument formatting, original caller-owned strings, NSObject description code, paths, block/object metadata and temporary prefix/string representations still exist. Production TrollStore and helper logger implementations are unchanged; both workflows run the shared regression runner. TouchPOC remains excluded.

## Ordering, retirement and failures

Queue publication shares the state lock used to close admission. Finish closes admission before its existing synchronous serial-queue drain. Logs committed before closing are attempted in order before the drain completes. A formatter that started earlier must recheck the run generation before enqueueing; an old formatter cannot write after finish or into a later run. Provisional formatting is not awaited by the disk drain; its lifetime reservation remains charged until it returns. Ordinary calls after admission closes are ignored.

Retain the completed run's paths after cleanup for history/failure evidence. Clear paths only before preparing the next run, so a directory-creation failure cannot reuse the previous run's files. The history source guard is now scoped to completed-run cleanup instead of banning resets everywhere; that invariant remains enforced.

Lifetime counters expose accepted, dropped, truncated, writeFailures, pending lines/reserved bytes and peak/cap values through currentConsoleLogStats. Failed writes count once per accepted entry when either path fails. Each path is attempted independently; NS/C++ writer failures are contained and the reservation is always released. Formatter faults also retire provisional charges. Ordinary timestamp/run/level/message bytes, CR behavior, two-file ordering and the existing greater-than-512-KiB rotation threshold remain. No new fsync, durable acknowledgment or file-retention policy is introduced.

After draining, a bounded warning footer and one NSLog report lifetime drop/truncation/write-failure totals when nonzero. Totals are cumulative for that runtime object and are a snapshot at the drain; a still-running provisional formatter may report its discard later. Footer I/O is best effort and its failures are not counted as accepted-entry write failures. The footer is a separate bounded allocation after the committed queue drains, outside the 64-entry accounting.

Intentional contract changes under pressure are explicit disk-log dropping, long-line truncation and visible totals. Logger backend faults no longer escape GCD; they do not replace script errors/results. Ordinary supported logs stay compatible. This does not bound disk-operation duration or make finish asynchronous.

## Verification

All 64 workflow runners (36 source-contract, 28 native) have passed on Windows, along with 521 direct workflow source-grep checks, expanded standards-conforming assert preprocessing and git diff --check. The initial sweep passed 63 runners and found the old whole-file history path-reset guard; after scoping it to run cleanup, the focused history runner passes. Focused console-log budget/source checks pass. Sixteen artifact-only checks require CI outputs. New macOS/Foundation/ARC/GCD/ASan/UBSan execution remains pending; warnings and sanitizers stay enabled.

Portable tests cover the 64-entry/1-MiB reservations, saturation/drop, duplicate and stale release, 100,000 lifecycles, 8 x 10,000 concurrent admissions and 100,000 UTF16 cut boundaries with zero final pending charges. Source guards retain preparation/header behavior except the intentional fresh-path reset, reconstruct the original file writer after adapting its shared data/status interface, and require publication/drain/generation/pool integration. The original synchronous per-call NSLog callback remains guarded unchanged.

The macOS fixture compiles actual logging methods and the frozen 208bf6a0 formatter/writer. It compares 164 ordinary entries and existing rotation bytes on real private temporary files with a fixed clock. It exercises a held GCD queue, 64-slot saturation and rejection before description, surrogate-safe truncation, mutable input snapshots, NS/C++ seek/write/close and formatter faults, closed admission, a paused producer crossing finish/reopen, eight concurrent producers, summary/counter behavior and failed-directory stale-path prevention. Real Foundation file wrappers track balanced handles; no real script runs in this fixture.

## Acceptance and remaining work

Build rootfull/roothide and run controlled high-volume logging with slow storage. Check drops/truncation/counters, ordinary two-file ordering, stop/restart isolation, failure-evidence paths and I/O recovery. Measure retained payload and RSS separately from upstream JS formatting, Foundation and system logging.

The original per-call synchronous NSLog, per-entry metadata/open/write/close for two paths and lack of batch coalescing remain P1-42 work. P1-50 run-log retention, persistence/history locks, status snapshots, commit/recovery and the other C03 tasks remain open. C02's remaining invalidation/metadata/qualification work is also open. No device CPU/latency/RSS improvement is claimed.
