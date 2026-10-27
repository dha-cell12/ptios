# C02b37 — direct device info and battery queries

Date: 2026-10-28 (Asia/Bangkok). Baseline: `aed36da`, containing the corrected C02b36 fixture; the user reported that build passed.
Status: **user reported build success before C02b38; independent device/performance qualification pending**.
Finding: **P0-13, task-25 selectors 30/31 adapters**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide info and batteryInfo bridge branches call TLinkExecuteNativeDeviceInfo with numeric selectors 30 and 31. Their ignored JS arguments, metadata parsing, field-count checks and result augmentation remain unchanged and are checked against frozen bridge fragments. The numeric entry accepts only those selectors; other values fail before license or provider work. A static assertion protects their fixed contract values.

DeviceInfo exposes getDeviceInfoForTask. The RAW wrapper retains its original %s/semicolon-pair split/intValue parsing, then delegates to the shared numeric core. The entire selector body and modelName/uname helper remain unchanged and are checked against frozen source. Screen selectors and unknown-selector RAW error behavior retain their existing contract; they are not exposed through this typed entry.

Keep repeated UIDevice currentDevice/property calls and their ordering, uname machine formatting, nil/description behavior, UUID description and multipart response fields. Battery queries still enable monitoring before reading state/level and leave it enabled. Keep signed state formatting and the exact float-cast, multiply-by-100 and %f conversion before JS intValue/doubleValue metadata conversion. No caching, monitoring rollback, main-thread marshalling, new uname error policy or precision changes are introduced.

The typed path removes full RAW request formatting/encoding, processTaskWithContext dispatch, the backend request parser, compatibility CF stream and response-vector accumulation/copy. The existing Reply formatter keeps bounded raw/parts without adding query fields, including first-NUL truncation, delimiter shifts, newline trimming and unusual-response fallback. Backend multipart assembly and JS metadata parsing/dictionary copy remain.

Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites. No measured CPU, allocation, latency or RSS improvement is claimed.

## Authority and lifetime

One ordinary task-25 license gate precedes provider access. The child context inherits caller owner fields, deadline and output settings with response capture disabled. Check stop before/after the gate, after the opaque provider call and after bounded reply formatting. Owner automation authorization does not bypass the gate. No C01-local timeout, cleanup exemption, compute admission or automatic retry is added.

UIDevice/uname calls remain synchronous and cooperative. Caller stop/deadline during accepted provider work is observed on return; battery monitoring may already be enabled when cancellation, output rejection or a later boundary exception is reported. No rollback is added. NS/C++ exceptions escaping the provider normalize to native_exception. Output caps bound wire admission rather than provider/Foundation temporary allocations. Existing post-entry JS metadata conversion remains unchanged.

Per-call pools drain temporaries while retaining the raw result outside the pool. The bridge retains decoded metadata across provider/context/pool teardown. NSError writeback lifetime is covered on the existing RAW unknown-selector path. No new public nullable-error contract is claimed for that unchanged path.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. New Foundation/ARC/ASan/UBSan branches cannot execute on this Windows host.

New macOS coverage compiles the actual DeviceInfo parser/numeric core/model helper, bridge and entry against controlled UIDevice/uname objects and the existing controlled Screen class. The production header supplies the numeric core's forward declaration. Frozen bridge/task/core fragments provide the old oracle. It compares complete wire/metadata results, provider order, license counts and monitoring effects; NaN metadata is compared with an explicit NaN equivalence while all other fields and wire remain exact. No real device identity or battery state is accessed by the new fixture.

Coverage includes 160 ordinary cases; ignored/malformed-extra JS arguments; missing device and fields; real UUID description; Unicode, numeric, delimiter, newline, NUL and invalid-encoding fields/model bytes; signed state boundaries; float percentages, signed zero, unknown/over-range levels, infinities and NaN; exact/short output; ordinary license/owner denial; pre-cancel/expiry and gate-time stop; stop/deadline during opaque work; NS/C++ faults before/after monitoring; RAW screen/30/31/unknown parsing; invalid typed selectors; and NSError/result pool lifetime. Existing app/list/frontmost/path fixtures retain shared formatter regression coverage.

## Acceptance and remaining work

The user reported this checkpoint built successfully before C02b38. Its working source is based on HEAD `aed36da` with C02b37 changes; no C02b37 commit was present when C02b38 began. The next source checkpoint is IMPLEMENTATION-C02B38.md; the build report does not replace UIDevice/monitoring/device/performance qualification.

The user reported corrected C02b36 build success at baseline `aed36da`; that report does not qualify the new task-25 paths. Build rootfull/roothide variants and compare typed/helper info and batteryInfo with RAW task 25 selectors 30/31 across ordinary/unknown battery states, charging transitions and available identity fields. Verify exact raw/parts and numeric metadata, unchanged monitoring behavior, license denial/revocation, input-independent calls, output caps and caller stop/deadline. Recheck RAW screen/unknown-selector behavior after numeric-core extraction. Measure bridge overhead separately from UIDevice/uname/provider work and qualify monitoring behavior on device. Continue other P0-13 adapters, metadata codecs, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
