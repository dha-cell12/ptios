# C02b14 — structured input for OCR in a stored frame

Date: 2026-10-25 (Asia/Bangkok). Baseline: `4a3b0d4`; the user reported the C02b13 build passed before this slice.
Status: **build and OCR-success correction reported passed by the user before C02b15 (`2475200`); device qualification pending**.
Finding: **P0-13, ocrFrame input portion**. OCR response parsing, other remaining image/OCR adapters and helper transport remain open.

## Result and scope

Root JS ocrFrame prepares a structured request and calls one licensed task-91 entry. It avoids the aggregate request string/UTF-8 transport buffer, RAW task dispatch, CF response stream and captured response vector. The RAW parser and typed input share the same owner-queue frame copy, preprocessing, engine/cache and recognition implementation. No screen recapture is introduced.

This slice preserves the existing six-field OCR body, Base64 text/error encoding, public decoded fields, raw/parts and response parsing. Four bounded Foundation scalar strings deliberately remain to preserve %.0f followed by intValue, including very large finite ROI values. Whitelist normalization deliberately retains its Base64 encode/decode behavior. There is no measured allocation, latency or RSS claim.

Production TrollStore and TouchPOC source are unchanged. Both workflows run the expanded shared fixtures.

## Compatibility and error order

- Keep positive frame-ID validation, finite ROI JS checks, option conversion/defaults and lang/coord delimiter checks before dispatch. ROI conversion retains Foundation intValue rather than introducing strict signed-int rejection or a new clamp.
- OEM/PSM defaults remain 1/7, scaleUp 2 and thresholdMode 0. Empty language/coord normalize to vie/pixel in the shared backend. maxAgeMs <= 0 normalizes to 1000; the original signed option value still determines ingress length.
- Preserve equivalent 8192 UTF-16-unit ingress: two task-prefix characters, twelve separators, six signed integer fields, four actual ROI strings, language, encoded whitelist and coord. Checked subtraction rejects overflow. Size rejection precedes UTF-8/NUL rejection, and ingress checks precede license authorization.
- Actual dataUsingEncoding conversion checks language/coord for unencodable strings and embedded NUL. Other request fields are ASCII after scalar/Base64 conversion; the accepted UTF-16 cap remains within the existing 32 KiB UTF-8 transport ceiling. Whitelist retains its old Unicode, delimiter, NUL and invalid-UTF16 normalization through Base64 rather than becoming an unencoded protocol token.
- RAW task 91 retains check_langs, disabled handling, two-request admission before field parsing, its request budget beginning before parsing, permissive Foundation parsing and the existing error mappings. The typed backend uses the same two-request admission and request-budget implementation before its owner-queue hop.
- The common queue implementation keeps pressure epochs/cache purge, cancellation checks, frame/gray ROI copy, scaled pixel preflight, existing preprocessing/OCR work, NS/std exceptions, engine image/delegate cleanup and final timeout/error ordering. It copies request fields into local values before dispatch; no request reference escapes into the block.
- Preserve text, confidence, ageMs, ocrMs, preprocessMs, totalMs, raw/parts, decoded error code/message and disabled/busy/image/init/timeout errors. Response formatting/parsing is still compatibility work and is not counted as removed.

## Authority, budgets and resources

The typed entry installs the existing task-91 three-second C01 child scope before exactly one license gate and rechecks stop after the gate. It inherits caller cancellation/owner/output limits without modifying the parent deadline. The OCR request inherits that scope; queue wait and engine/preprocessing work do not receive a fresh outer allowance. Two admitted requests, the two-entry LRU, pixel/gray limits and pressure cleanup remain shared with RAW.

The entry checks the final response through the existing bounded reply helper. Denial, parent cancellation/deadline, local C01 expiry, output overflow and NS/C++ faults retain their mappings. Opaque license, queue, CV and engine operations remain cooperative/nonpreemptible; no hard completion deadline or engine/device performance result is claimed.

## Validation

- Portable ingress coverage adds 10,000 frozen wire-length plans, signed option values, huge finite ROI, exact 8192/8193 boundaries and saturated size counters. Existing 100k OCR scale/buffer, 100k LRU and 80k admission/deadline cases remain.
- The Foundation bridge fixture compares 100 cases with the frozen 4a3b0d4 JS branch, the actual bounded RAW bridge and a controlled OCR backend. Additional cases cover defaults, large Foundation integer conversion, Unicode/NUL/invalid UTF16, encoded whitelist, exact ingress limits, successful/error decoding, one task-91 gate, three-second C01-before-license and caller isolation, denial, cancellation/deadline, NS/C++ faults and exact output caps.
- The actual OCR fixture adds 12 RAW/typed queue/cache/preprocessing/engine-adapter comparisons, plus scaled preflight, busy admission, NS/C++ faults, cold-init expiry/cancellation and released resources. It compares text/confidence/age and body shape; real elapsed-time columns are not asserted equal. CV/engine behavior is controlled; Foundation/CoreGraphics/provider and production orchestration are exercised on macOS.
- All-host fixture extraction checks cover the new bridge/entry dependencies, Base64/error helpers and macro-independent task entry. Standards-conforming assert preprocessing passes all three existing runtime fixtures with a rejecting negative control.
- All 56 workflow runners pass on Windows: 36 source-contract and 20 native runners. All 521 direct workflow source-grep commands pass; 16 package-artifact checks require CI outputs.
- **Foundation/macOS execution, ASan/UBSan, iOS builds, real OpenCV/Tesseract and device measurements were not run on this Windows host.** The expanded Foundation branches await macOS CI through the existing runners in both workflows.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare JS ocrFrame with RAW task 91 on the same retained frame: pixel/point ROI, language/whitelist, OEM/PSM, scale/threshold, age/TTL, empty/default and large scalar conversions. Check missing frame/gray, disabled engine, busy/preflight/init errors, license delay/denial, cancellation, output caps and pressure/resource recovery. Confirm no display capture; measure bridge allocations/latency separately from recognition and accuracy.

Continue remaining measured P0-13 image/OCR adapters and response work, P0-12 event-driven helper RPC, P1-40 config snapshots and P1-41 byte-bounded dedupe. C01/C02 performance/device acceptance remains open.

## CI correction — OCR success status

Root macOS CI aborted in the native bridge fixture after the frame-image cases. The typed OCR entry reused zx_typedTouchReply, whose sole success shape is exactly `0\r\n`; it marked a valid `0;;<OCR body>\r\n` as failed. The OCR reply adapter now derives ok from the first compatibility column while retaining the same raw/parts, output/cancellation checks and error mappings. Touch reply handling is unchanged.

The actual bridge fixture explicitly requires the default OCR call to succeed with seven reply parts and decoded text/confidence/age before the frozen comparison cases. All-host extraction guards require the OCR-specific adapter. Windows native-budget/OCR and assert-preprocessor checks pass; corrected Foundation/macOS and iOS execution remain pending on CI. No strict warning or sanitizer setting is disabled.

The user reported the corrected C02b14 build at `2475200` passed before C02b15. Structured OCR result publication is tracked in `IMPLEMENTATION-C02B15.md`. This records the user report; no independent macOS/device execution was performed on this host.
