# C02b25 — direct hardwareKey and press cleanup

Date: 2026-10-27 (Asia/Bangkok). Baseline: `66bb60c`; the user reported C02b24 built successfully.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, task-30 hardware-key adapter**. Other adapters and performance qualification remain open.

## Result and compatibility

The rootfull/roothide hardwareKey bridge calls TLinkExecuteNativeHardwareKey with normalized numeric action/key values. A shared sendHardwareKeyEvent core handles HID mapping, cached client creation and keyboard event dispatch. This removes the typed call's RAW request formatting/encoding, parser, processTaskWithContext dispatch, compatibility CF stream and response-vector accumulation/copy. Successful replies use the existing direct reply formatter; error replies retain compatibility parsing.

Keep Foundation intValue normalization, bridge validation, ok/raw/parts, backend error strings and the Home/Volume Up/Volume Down/Lock usage mapping. Only action 1 emits DOWN; other accepted actions emit UP as before. Only canonical action 0 is exempt cleanup, matching the RAW 0;; prefix. Positive actions other than 1 still require the ordinary license gate even though their physical event is UP. Unknown positive key types retain the backend error. The direct entry rejects negative actions and nonpositive key types before any gate or event creation.

The RAW task-30 body is unchanged and checked against frozen source. Its parser retains missing-field errors, Foundation field conversion and ignored suffix fields, then delegates to the numeric core. Client caching, synchronous caller-thread execution and normal event ownership remain. Dispatch now releases the owned event in @finally, including NS/C++ exception unwind. This does not add synchronization to the existing cached client.

Production TrollStore and TouchPOC execution sources are unchanged; both build workflows run the shared safety suites. No measured CPU, allocation, latency, RSS or hardware behavior improvement is claimed.

## Authority, side effects and lifetime

Ordinary calls inherit the child context, owner fields, caller deadline and output settings with response capture disabled. Stop checks surround exactly one task-30 license gate. Owner automation authorization does not bypass that gate. Action-zero UP uses the existing cleanup context: it remains callable after parent cancellation/expiry and license denial. No C01 timeout, compute admission or automatic retry is added.

Preserve post-effect output admission: DOWN can commit immediately before cancellation or an output error is reported. The unchanged pressHardwareKey body always attempts UP in @finally, including failed DOWN results, wait timeout, output rejection and exceptions. That is best-effort release; a backend failure during UP cannot guarantee a physical release. A caller issuing hardwareKey DOWN directly retains responsibility for its matching UP, as before.

Each typed call drains temporary objects in an autorelease pool while a strong result outside the pool keeps the reply alive. NS/C++ exceptions normalize to native_exception. Cleanup does not extend the ordinary call's authority or replay its effect. Provider execution remains cooperative and synchronous; opaque HID work is not preempted.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled.

New macOS coverage compiles the actual hardware bridge, task entry, RAW parser, usage mapping and numeric core against counted CF objects at controlled IOKit boundaries. Independent frozen baseline fragments provide the old bridge/parser/task oracle. Coverage compares physical event fields and replies across five actions, four keys and three output caps, then exercises normalized/invalid arguments, missing and extra RAW fields, unknown keys, one-gate authority, action-zero cleanup, pre/gate cancellation/expiry and zero typed RAW dispatch/response-vector capacity.

The actual press body is exercised for committed DOWN cancellation, wait expiry, tiny output caps, success metadata merge and NS/C++ dispatch faults before/after commit. Counted events must balance on every path; test-owned cached clients are explicitly drained at fixture teardown. Host fixture calls do not inject hardware events. These new Foundation/ARC/ASan/UBSan branches cannot execute on this Windows host and await macOS CI; private HID behavior and physical key cleanup require device qualification.

## Acceptance and remaining work

Build rootfull/roothide variants and compare typed/helper hardwareKey with RAW task 30 for supported keys/actions and error replies. On device, verify press DOWN/UP order under cancellation, deadline, license denial/revocation and output rejection, including recovery after HID failures. Measure bridge overhead separately from unchanged HID work. Continue other P0-13 adapters, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
