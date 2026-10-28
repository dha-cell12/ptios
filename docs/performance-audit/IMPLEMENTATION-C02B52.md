# C02b52 — direct screenshot file/region adapters

Date: 2026-10-28 (Asia/Bangkok). Baseline: `e782771`, containing C02b51; the user reported that build passed.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, screenshotTo/screenshotRegion, task 29 action 1**. C02 remains partial.

## Result and compatibility

Rootfull/roothide JS screenshotTo and screenshotRegion now call TLinkExecuteNativeScreenshotFile and the unchanged Screen screenShotToPath method directly. Ordinary calls avoid full RAW request assembly/encoding/splitting, processTaskWithContext, CF stream creation and response-vector accumulation/copy. Input admission, bounded formatting and JS reply/metadata decoding remain. No CPU, allocation, latency or RSS improvement has been measured. Production TrollStore and TouchPOC adapters are unchanged; shared safety checks remain in their workflows.

Keep complete JS validation, screenshotTo's default path/type handling, screenshotRegion's empty-path behavior, option defaults and original-coordinate metadata. Coordinates retain the %.0f -> Foundation floatValue round trip, including ties, signed zero, float precision loss/overflow and positive sizes rounding to zero. The direct entry does not clamp these into new geometry rules. The unchanged Screen backend still determines full-frame/empty/intersection behavior.

Admission counts the complete old task/payload against 8192 UTF-16 units and 32-KiB UTF-8 bytes/NUL/encoding before authority. Screenshot parsing uses UTF-8, preserving Unicode paths directly rather than using Foundation %s. Semicolon paths use a bounded compatibility field string/split to preserve overlapping delimiters, including trailing semicolons before coordinates. Ordinary paths keep structured fields. The direct field API also preserves internal delimiter behavior rejected by strict JS. Exact bare ACK, returned-path/error C-string rules and JS path/coordinate metadata remain.

Screen.xm and its full RAW parser/task handler are unchanged. Source guards compare the entire file capture/crop/keep/codec/write method with a frozen e782771 snapshot and retain the existing full parser/handler oracles. This checkpoint adds no new screenshot, image-format, directory, cache, Photos, TCC, geometry or filesystem policy. Action-4 owned capture and its lease/IPC/daemon routes remain unchanged.

## Authority, effects and lifetime

Each capture retains one ordinary task-29 gate with inherited owner/cancellation/deadline/output and response capture disabled. Owner authorization does not bypass the gate, and task 29 adds no C01-local timeout. Stop checks bracket the gate and follow the opaque Screen method. There is no allocation response floor, new queue/cancellation propagation, retry or rollback.

An unowned file write may complete before caller stop, output rejection or an escaping fault is reported. Preserve the file rather than deleting a user-selected path. NS/C++ exceptions escaping the direct entry normalize to native_exception; this does not promise new exception handling or interruption inside capture/codec/filesystem APIs. Snapshots and per-call pools retain provider/error/result lifetime. Existing owned capture continues enforcing its own distinct lease, cancellation and cleanup policy.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. Focused native-budget/extraction and owned-capture core/release checks pass. Sixteen artifact-only checks require CI outputs. New Foundation/ARC/sanitizer compilation/runtime cannot run on this host and remain pending macOS CI. Warnings and sanitizers remain enabled.

The new Foundation fixture compiles the actual capture parser, entry and complete JS branches against frozen parser/task/JS oracles. Its parser compile adapters omit album branches, which retain their separate suite; full frozen source equality guards those boundaries. An absent-owner fence retains action-4 rejection in this adapter; the separate owned-capture suite exercises real leases. Screen is a controlled boundary recording the exact path/CGRect and writing a real generated PNG only to a private temporary file. It does not implement or qualify real capture/crop/codec/keep/directory behavior. Cached PNG bytes make independent old/new write effects deterministic without claiming per-call image encoding coverage.

Coverage includes 160 full and 160 region calls; signed/half-tie/float-precision/overflow geometry; JS invalid/default/type/option behavior; empty/Unicode/semicolon paths and UTF-8/NUL/invalid UTF16; exact 8192/8193-unit admission and output limits; path/error/bare ACK and metadata behavior; ordinary authority/owner denial; pre/gate/provider cancellation/deadline; accepted writes before stop/output/NS/C++ failures; mutable path/result/error pool lifetime; direct-field delimiter compatibility; RAW malformed/capture/action-4 rejection; and 128 repeated private-file lifecycles. The existing capture, lease and album suites retain their separate coverage.

## Acceptance and remaining work

Build rootfull/roothide with C02b52 and compare typed/helper full/region capture against RAW task 29 action 1 using private output paths. Qualify real PNG/JPEG output, rounded region/intersection/full-frame behavior, keep-cache reuse, directory/write errors and capture/codec failures. Check accepted stop/output failure independently from file state. Recheck action-4 leases, daemon template capture and album isolation. Measure bridge costs separately from capture/crop/encoding/I/O. Other P0-13 adapters and metadata codecs/copies, P1-40 invalidation and P0-12 qualification/unknown-start cases remain open.
