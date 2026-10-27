# C02b24 — direct rootDir/currentDir/botPath queries

Date: 2026-10-27 (Asia/Bangkok). Baseline: `de4e01f`; the user reported C02b23 built successfully.
Status: **build reported passed by the user before C02b25 (`66bb60c`); independent device/performance qualification pending**.
Finding: **P0-13, task-44/45/46 path adapters**. Other native adapters, config invalidation and performance qualification remain open.

## Result and compatibility

The rootfull/roothide bridge calls TLinkExecuteNativePath directly for rootDir, currentDir and botPath. This removes the typed call's two-character RAW request formatting/encoding, processTaskWithContext dispatch, compatibility CF stream and native response-vector accumulation/copy. Ordinary replies build their compatibility fields without splitting/reparsing a successful response.

Preserve ok/raw/parts, the common path field and exactly the matching rootDir/currentDir/botPath alias. Method arguments remain ignored. RuntimeUtils and Common path constructors are unchanged: currentDir continues to return document root, and botPath retains the existing slash spelling. No path normalization, filesystem lookup, cache or new path-resolution policy is introduced. RAW task bodies remain unchanged and are checked against frozen source. Production TrollStore and TouchPOC execution source are unchanged; both build workflows run the shared suites.

Path and frontmost queries share C02b23's scalar formatter, now parameterized by metadata key, numeric conversion and optional alias. Frontmost still uses bundleId or intValue orientation; paths use the string and path alias. Preserve immutable snapshots, full-chunk wire output admission and the unusual-string compatibility branch for first-NUL termination, ;; splitting and newline trimming. Keep the old unencodable-UTF8 empty-writer fallback to 0 CRLF without metadata; that exceptional fixed fallback remains uncharged even under a tiny cap, as before.

Compatibility raw strings and Foundation UTF-8 formatting storage remain. The wire output budget is not a bound on provider NSString allocation or Foundation temporaries. No measured allocation, CPU, latency or RSS improvement is claimed.

## Authority and lifetime

The entry rejects task IDs outside 44/45/46 before calling any provider. Valid calls inherit the existing child context, owner fields, caller deadline and output settings with no response capture. Check stop before one ordinary task license gate, after the gate, after the selected provider and after formatting. Session automation/cleanup exemptions do not bypass the path-task gate. No C01-local timeout or compute admission is added.

NS/C++ exceptions normalize to native_exception; cancellation/deadline/output failures retain the existing normalized reply shape. Each query drains temporary objects in an autorelease pool while a strong result outside that pool keeps returned metadata alive. Provider strings are copied to immutable snapshots, and aliases retain the same resulting string after mutable input changes or pool teardown. Execution remains synchronous on the existing caller thread with cooperative limits for opaque license/provider work.

## Verification

All 62 workflow runners (36 source-contract, 26 native) and 521 direct workflow source-grep assertions pass on Windows; 16 artifact-only checks require CI outputs. Standards-conforming assert preprocessing passes existing fixtures plus the frontmost and three new path fixture files, with the existing rejecting negative control. git diff --check passes. These local results do not execute the new macOS fixture branches.

New macOS fixture coverage compiles the actual bridge fragments, task entry, context and response writer against controlled RuntimeUtils/license boundaries. It adds 120 ordinary frozen-adapter comparisons plus root/double-slash/relative/space/Unicode/empty/nil/NUL/delimiter/newline/encoding cases at ordinary, exact and one-byte-short output caps. It checks provider/task selection, exact path aliases, one license gate, denied owner exemption, pre/gate/read stop/deadline, NS/C++ faults, invalid task rejection, immutable/pool lifetime and zero typed RAW dispatch/response-vector capacity. Existing C02b23 cases also exercise the shared formatter refactor.

All-host guards check direct bridge entry, unchanged RAW bodies, one gate and stop ordering, no C01/RAW/CF stream in the new entry, macro-independent booleans and fixture dependency order for the shared scalar formatter. New Foundation/ARC/ASan/UBSan branches and iOS/device behavior cannot execute on this Windows host.

## Acceptance and remaining work

The user reported this checkpoint built successfully before C02b25. That report does not establish device or measured performance acceptance. The next checkpoint is documented in IMPLEMENTATION-C02B25.md.

Build rootfull/roothide variants and compare in-process/helper queries with RAW 44/45/46, including all path alias fields and the existing slash spelling. Exercise license denial/revocation, caller stop/deadline and output limits. Measure bridge cost separately from the unchanged backend. Continue other P0-13 adapters, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
