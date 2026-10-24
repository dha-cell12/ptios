# C02b4 — structured live color pick

Date: 2026-10-24 (Asia/Bangkok). Baseline: `9d18c75`; the user reported the corrected C02b3 build passed before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.
Finding: **P0-13, live pickColor portion**. Frame color methods and other typed methods/helper transport remain open.

## Result and scope

Root JS `pickColor` now constructs a numeric request and calls a licensed task-23 entry. The entry returns RGB values and compatibility `{ok, raw, parts}` fields directly. It avoids whole request formatting, UTF-8 request buffers, compatibility CF streams, raw task dispatch, captured response vectors and successful reply splitting. Small success text/part strings remain because callers already receive them.

The numeric and RAW ColorPicker adapters share `zx_colorPickScreen` inside the existing `zx_colorRun` admission/error/cancellation/resource policy. RAW parsing is retained. Full display capture, RGBA conversion, crop semantics and source/ROI/memory limits remain; this slice does not replace the capture backend or claim a measured allocation/latency gain. Production TrollStore and TouchPOC are unchanged.

## Numeric and error compatibility

- Preserve the bridge's early finite check and missing-coordinate defaults. Numeric conversion uses the old `%.0f` formatting followed by strict integer/range validation, including half ties, signed zero, finite overflow and the `[0,8192)` input domain. Invalid values become an invalid-coordinate sentinel; they are rejected after authorization and compute admission, retaining busy/error precedence rather than being clamped to a pixel.
- The existing immutable C-locale formatter is moved from the touch-specific header to `TLinkNativeNumber.h`, shared by touch and color requests. Formatting/parsing behavior and locale reuse remain; touch's existing scalar/batch/input-cap regressions still run.
- Finite double-coordinate strings can never reach the existing 8192-character/32 KiB request caps, so the numeric path does not introduce a smaller argument limit. Image dimensions and ROI validation still occur in the common core.
- Success includes the same decimal `raw`, string `parts` and integer red/green/blue fields. Denial/error paths reuse the existing compatibility reply helper, and output bytes are checked before returning success. Strict warnings, macro-independent booleans and ASan/UBSan remain enabled.

## Authority, deadline and ownership

The structured entry creates the same noncapturing child call context and applies the existing task-23 C01 three-second budget **before the license gate**. It checks stop before and after authorization, then calls `getRGBAtPosition`. Capture and RGBA work keep the existing two-compute admission, three-second cooperative request, 32 MiB private RGBA accounting and scope-owned image/context/buffer cleanup.

Keep the C01 child budget separate from the caller/reply budget. Local expiry retains the RAW task's `native_cancelled_or_timed_out` or color error; parent cancellation/deadline/output overflow maps through the caller's existing AbortError/TimeoutError/response-too-large handling. Do not shorten the caller deadline or replace a task-local timeout with an unrelated parent failure. Opaque capture/graphics/license calls remain cooperative/nonpreemptible, and no hard completion deadline or RSS guarantee is claimed.

## Validation

- Windows: all 36 source-contract runners, 20 native runners and 528 TrollStore source grep assertions pass (16 artifact-only assertions require CI outputs). The native budget runner adds 100,000 comparisons against the old decimal-plus-strict-integer coordinate path and explicit half/signed-zero/8192/int/huge/nonfinite boundaries. The existing 100k touch scalar, gesture timing, batch-size, budget/cancellation and color golden/admission/resource tests remain.
- Every host extracts the actual production color bridge/entry and checks that it uses the C01 budget before the task-23 gate, skips raw dispatch/CF streams, and compiles the entry without YES/NO macros. Both existing workflows already run these tests.
- Expanded macOS Foundation bridge/entry coverage checks 200 coordinate/reply/parts/RGB cases against the legacy NSString formatter plus strict parser, task-23 denial and pre/post-gate stop, inherited deadlines, a real local C01 expiry during authorization without cancelling the caller, backend faults/NS/C++ exceptions, output limits and absence of raw dispatch/response-vector allocation. The backend is controlled in this bridge fixture.
- The separate actual ColorPicker/CoreGraphics fixture compares 65 numeric/RAW combinations and repeats allocation/crop/color-space/context/draw/expiry/capture faults through the numeric adapter, including NSError lifetime and busy-before-invalid-input precedence. Existing real provider/buffer/reservation cleanup checks remain.
- **New Foundation/macOS cases and iOS builds were not run on this Windows host.** Real capture coordinates, device resources and performance require CI/device qualification.

## Acceptance and next slice

Build rootfull/roothide in observe/enforced modes. Compare JS `pickColor` and RAW task 23 for fractional/negative/boundary coordinates, identical RGB and errors, capture failures, license expiry/cancellation and recovery. Measure per-call allocations and latency independently from fresh display capture. Continue frame color/other measured P0-13 methods and P0-12 helper transport, then P1-40 config snapshots and P1-41 byte-bounded dedupe. C01/C02 device acceptance remains open.

## CI correction - assert macro argument boundary

macOS Clang rejected the fault-reply assertion because the comma in an Objective-C stringWithFormat message appeared at the assert macro's top parenthesis level. Prepare the expected string before assert, preserving the exact reply and failure-status checks. Other assertions with formatted strings in the two affected fixtures are protected by ordinary C/C++ function-call parentheses. Production behavior, strict warnings and sanitizers are unchanged; corrected macOS/iOS CI remains pending.

Validation after the correction: Windows native-budget portable checks and production fixture extraction pass. MSVC standards-conforming preprocessing rejects a negative control with the original comma and accepts all assert argument boundaries in both native-bridge and color runtime fixtures after stripping unavailable framework includes. This checks macro syntax only; Foundation compilation/execution still requires macOS CI.
