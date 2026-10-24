# C02b8 — structured frame point-color comparison

Date: 2026-10-25 (Asia/Bangkok). Baseline: `d6147de`; the user reported the C02b7 build passed before this slice.
Status: **corrected build reported passed by the user before C02b9 (`fc1b96a`); device qualification pending**.
Finding: **P0-13, frameIsColors portion**. frameFindMultiColor and other typed methods/helper transport remain open.

## Result and scope

Root JS frameIsColors decodes its dictionary points into a bounded numeric plan, calls one licensed task-69 entry and compares against one immutable BGRA frame snapshot. It avoids per-point Foundation strings, joined request tables, aggregate UTF-8 request buffers, RAW/CF dispatch, captured response vectors and successful reply parsing. The RAW is_colors reader shares the same pixel comparison helper.

One small Foundation %.4f scalar string remains deliberately: it preserves the exact tolerance rounding, signed-zero/nonfinite spelling and input length of the old encoder. The coord token still receives actual UTF-8/NUL validation. Compatibility output strings remain. The existing frameFindMultiColor branch retains its old adapter after the two method branches are separated. Production TrollStore and TouchPOC source are unchanged.

## Compatibility and limits

- Preserve upfront JS table shape/count (1..512 dictionary rows), original coordinate finite checks, defaults and RGB long-key/short-key fallback, including respondsToSelector behavior. Preserve full validation before effects; a late malformed row still rejects even if encoded input is already oversized.
- Coordinates follow %.0f then strict signed integer parsing, including INT_MIN/INT_MAX and signed zero. Cache invalid integer/RGB status in the plan while continuing JS shape validation. Do not clamp invalid values into the image.
- The point count saturates at 513, stored rows at 512 and encoded table length at 32769. The JS producer rejects counts above 512 up front as before; backend table/count/error handling remains after frame/TTL for numeric callers.
- Preserve the equivalent 8192 UTF-16-unit aggregate input cap with exact coordinate/decimal integer lengths, double-comma/pipe separators, is_colors mode/separators and the actual scalar/coord units. Checked subtraction rejects overflow. Size precedes UTF-8/NUL rejection, and ingress precedes task authorization. Other fields are ASCII, keeping the old 32 KiB UTF-8 bound satisfied.
- Tolerance still rounds through the Foundation four-decimal representation before mode validation. mode 0 uses similarity 0..1; mode 1 uses per-channel tolerance 0..255 with the old integer truncation. Nonfinite or out-of-range rounded values fail in the backend after licensing, rather than becoming a new JS validation error.
- The shared request prelude may reject a stopped caller before method validation. Entry/core order remains caller stop/license, color admission, frame/mode/tolerance parameters, image admission, snapshot/BGRA/geometry, TTL, full-table integer/RGB validity, then ordered pixel comparisons and final cooperative stop checks. An invalid later row still wins over an earlier color mismatch or out-of-bounds point. A missing/stale frame wins over invalid point contents.
- A valid table point that is outside the image or cannot be converted at the stored point scale yields matched=false, preserving RAW behavior. No display recapture occurs.

## Authority, budgets and output

The typed task installs the existing three-second C01 child budget before a single task-69 license gate and checks stop before/after authorization. It inherits the parent owner/token/output limit without shortening the caller deadline. Existing two color/two image admissions and one shared frame reader unwind on failure. Per-point work accounting and the final request stop check retain the old cooperative cancellation policy.

Success preserves matched and value booleans, raw/parts, ageMs, the two historical three-decimal time columns and totalMs rounded through that same text. A color mismatch is still a successful response with false booleans. Final raw byte length is checked against the caller output cap. Authorization denial, local C01 expiry, parent cancellation/deadline, native exceptions and output overflow retain their mappings.

No measured allocation/latency/RSS reduction or hard completion deadline is claimed. Opaque license/store/framework waits and device accuracy/performance still require qualification.

## Validation

- Windows: 36 source-contract runners, 20 native runners and 521 direct workflow source-grep commands pass (16 artifact-only commands require CI package outputs).
- Portable modern-image tests add 10,000 comparisons against a frozen pre-C02b8 evaluator for both modes, scale, stride and exact wire limits. Additional cases cover strict signed integers/RGB, 512/513 points, saturated table bytes, invalid mode/tolerance and deterministic work/cancel bounds. Prior search/multi-point/scalar and 3000 matcher golden cases pass.
- The Foundation bridge fixture compiles the actual JS decoder, bridge and task entry with YES/NO undefined. The frozen C02b7 JS branch, actual bounded RAW bridge and a controlled frame backend compare 160 cases plus defaults/aliases, malformed/oversized lists, full-table error precedence, mode/tolerance rounding and nonfinite values, Unicode/NUL and exact ingress caps across ten scalar spellings. It checks exact result fields/output caps, one task-69 gate, C01/caller isolation, delayed authorization, cancellation, exceptions and no typed RAW dispatch.
- The actual Image adapter fixture adds 220 RAW/numeric cases plus full-table versus early mismatch/frame/TTL error order, strict integer/RGB limits, 512/513 counts, admissions, held snapshot after erase, cancellation and released slots. It checks no display capture.
- Native-budget dependency extraction places the finite-number helper before both point-color encoders/decoders. Standards-conforming assert preprocessing passes all three runtime fixtures with a rejecting negative control.
- **Foundation/macOS execution, ASan/UBSan, iOS builds and device measurements were not run on this Windows host.** Both production workflows already invoke the expanded fixtures; their new branches await CI/device qualification.

## CI fixture correction (2026-10-25)

Root macOS CI reported an unknown TLinkNativeFrameColorsRequest type in ColorEncoderUnderTest.inc. The ColorPicker runner extracted the legacy encoder through the next OCR helper; C02b8 inserted the numeric frame decoder inside that interval. Its unrelated type/member references therefore entered the standalone C++11 color fixture.

The runner now extracts only the complete legacy encoder function and asserts on every host that the result contains one function and no frame decoder/type dependency. The actual frame decoder remains exercised by the native-budget bridge fixture, where its header and declaration order are present. Production behavior, C++11 color-fixture settings, strict warnings and sanitizers are unchanged.

After the correction, the color runner passes 100k predicate comparisons, 5000 scan golden cases, 80k admission/byte lifecycles and the new fixture-isolation assertions on Windows. The native-budget portable/dependency runner also passes. The user subsequently reported the corrected build passed (`fc1b96a`) before C02b9. macOS/iOS execution was not independently performed on this host; device qualification remains pending.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare JS/RAW frameIsColors on the same frame for integer rounding, RGB aliases, both modes, four-decimal boundaries/nonfinite values, duplicate and out-of-bounds points, complete-table error precedence, TTL, exact reply fields, authorization/cancellation/output caps and recovery. Verify no recapture, retained reader or admission. Measure allocation rate and latency independently of frame creation.

Continue frameFindMultiColor and other measured P0-13 methods, then P0-12 event-driven helper RPC, P1-40 config snapshots and P1-41 byte-bounded dedupe. C01/C02 device acceptance remains open.
