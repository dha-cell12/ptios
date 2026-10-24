# C02b5 — structured single-pixel frame color

Date: 2026-10-24 (Asia/Bangkok). Baseline: `5080765`; the user reported the corrected C02b4 build passed before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.
Finding: **P0-13, framePickColor portion**. Multi-point frame color and other typed methods/helper transport remain open.

## Result and scope

Root JS `framePickColor` now sends a numeric request through a licensed task-69 entry. It avoids aggregate request strings, UTF-8 request buffers, compatibility CF streams, raw task dispatch, captured response vectors and successful reply splitting. Compatibility raw/parts and RGB/ageMs/totalMs fields remain. Small output strings and a bounded scalar metadata conversion remain necessary for the old reply contract.

The numeric reader and RAW task-69 pick branch share BGRA/geometry validation and the pixel conversion/bounds/work/read helper. RAW parsing and all five color modes remain available. The reader holds the same immutable frame snapshot and never falls back to display capture. Production TrollStore and TouchPOC are unchanged.

This slice covers the single-pixel method. `framePickColors` needs its own table-count/byte limits and lazy parse/error precedence; it remains on the compatibility path for the next slice.

## Compatibility and admission

- Preserve JS frame-id/finite validation, missing coordinate defaults, option conversion, delimiter rejection and case-insensitive pixel/point selection. Coordinates still follow `%.0f` then strict double conversion. Parameter admission retains the signed `INT_MAX-1` magnitude guard, allowing negative values to reach the old point-out-of-bounds decision after frame/TTL checks.
- Preserve the equivalent 8192 UTF-16-unit aggregate request cap by counting numeric ASCII lengths, task/mode/separators, frame-id, max-age and coord-token units. Checked subtraction rejects overflow. All remaining fields are ASCII; a well-formed token within that unit cap also satisfies the old 32 KiB UTF-8 cap. Embedded NUL or lossless-UTF-8 conversion failure returns invalid_payload before authorization, after the old size decision.
- Preserve error precedence: color compute admission, parameter validation, image compute admission, snapshot existence, BGRA, geometry, TTL/max-age, pixel coordinates and work/stop checks. Zero max-age still selects the default 1000 ms; values outside 0..5000 remain invalid. No invalid coordinate is clamped into the frame.
- Snapshot acquisition and release retain the existing store boundary. Reading uses the stored scale and padded BGRA stride. Readers can finish after store erasure, and errors release both admissions and the held reference.

## Authority, budgets and results

The entry applies the existing three-second C01 child budget before the task-69 license gate and checks stop before/after authorization. Parent owner/token/output defaults and deadline are inherited without shortening the caller's budget. Local C01 expiry keeps the RAW task's control error; caller cancellation/deadline/output overflow keeps the existing typed mapping.

The numeric reader uses the existing two color and two image compute admissions and cooperative work policy. It records frame age and processing time at the same stages as RAW pick. Public totalMs is rounded to the same three-decimal compatibility text before conversion to the numeric metadata field; raw/parts retain both historical time columns. Pixel RGB values come directly from the common read, without reparsing a success response.

Opaque license calls and store/framework waits remain cooperative rather than preemptible. No measured performance gain, hard completion deadline or process-RSS guarantee is claimed.

## Validation

- Windows: all 36 source-contract runners, 20 native runners and 528 TrollStore source grep assertions pass (16 artifact-only assertions require CI outputs). Added 100,000 legacy decimal/double/encoded-length comparisons, half/signed-zero/extreme boundaries, signed coordinate admission and exact/saturating input-cap cases. Existing matcher/touch/batch/cancellation regressions remain.
- Every host extracts actual frame bridge/entry/core dependencies. Source checks require C01 budgeting before task-69 authorization and prohibit aggregate/raw/CF dispatch and success-response splitting. The fixture compiles the entry with YES/NO undefined and uses production option helpers in declaration order.
- Expanded Foundation bridge/entry tests compare 100 preparation/RGB/age/three-decimal-time/raw/parts cases with the legacy formatter, exact 8192/8193-unit inputs, delimiter/NUL/invalid-UTF-16 cases, invalid options, denial, cancellation/pre-expiry, real local C01 expiry during authorization while the caller stays live, backend faults/exceptions and output-cap boundaries. The backend is controlled in this bridge fixture.
- The actual Image handler fixture compares 120 RAW/numeric replies with a controlled metadata clock and padded-stride BGRA frames, including point scaling, negative/fractional/extreme coordinates, default/max-age/TTL, missing BGRA/geometry/frame errors, busy precedence, snapshot erasure and cancellation before/after acquisition. It checks that no display capture occurs.
- A one-off MSVC standards-conforming preprocessor check accepts assert argument boundaries in the native-bridge, color and frame-color runtime fixtures; its negative control rejects the original top-level Objective-C comma. This checks macro syntax, not Foundation compilation.
- **New Foundation/macOS cases and iOS builds were not run on this Windows host.** Real frame coordinates, snapshot lifetime under device concurrency, allocation counts and latency require CI/device qualification.

## Acceptance and next slice

Build rootfull/roothide in observe/enforced modes. Compare JS and RAW task-69 single-pixel reads from the same frame for point/pixel coordinates, fractional/negative/boundary values, age/TTL, exact reply fields, authorization/cancellation/output limits and recovery after failure. Verify no recapture and no retained reader/admission after return. Measure allocation/call latency against C02b4 independently of frame creation.

Continue framePickColors and other measured P0-13 methods, then P0-12 event-driven helper RPC, P1-40 config snapshots and P1-41 byte-bounded dedupe. C01/C02 device acceptance remains open.
