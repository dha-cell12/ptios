# C05q — Bound accepted snapshot strings and check output arithmetic

Date: 2026-11-06 (Asia/Bangkok). Baseline: `ce912eaa`; user reported C05p build passed and requested continued implementation. Shared rootfull/roothide and production TrollStore AX snapshots/find/tap; TouchPOC excluded. Continues C05/P1-60.

## Accepted row text

Limit label, value, identifier and role to 65,536 UTF-8 bytes each before appending an accepted snapshot row. Check UTF-16 length first: a well-formed string cannot encode to fewer UTF-8 bytes than its UTF-16 code units, so an obviously oversized string needs no full encoding-size scan. Then check actual UTF-8 bytes and the existing caller output budget. Oversize returns the existing `ui_response_too_large`/`partial=true` error; no text is silently truncated and no incomplete result can authorize an action. Malformed strings longer than the UTF-16 preflight limit are also refused; shorter malformed strings retain Foundation's prior encoding/error behavior.

Keep visibility/clickability filtering before output admission, so excluded rows retain their previous behavior. Keep all normal metadata/fields/query/cancellation/deadline/CF/order/action/license behavior. For well-formed fields within the new cap, ordinary graph/JSON and the conservative output estimate remain unchanged. Task 77 advertises the additive `max_snapshot_string_utf8_bytes=65536`; update the public header, UI-tree documentation and contract fixture.

## Checked estimate

Use one small C++11 helper for the existing `768 + 6 * textBytes` row estimate and `32768 + 4 * ceil(totalJSONBytes / 3)` wire estimate. Check string multiplication/row addition, accumulated JSON addition and base64 expansion before committing output counters. Unrepresentable values fail closed through the same error. Existing caller output caps can reject smaller results; this does not increase them or claim exact measurement of all response representations.

The cap bounds text in accepted snapshot rows and avoids encoding-size work for obviously oversized UTF-16 input. It does not limit the opaque provider's initial allocation, the root array, arbitrary result metadata/selector input, formatter normalization, the standalone task 80 hit-test serializer or final Foundation JSON/base64/wire copies. No truncation/schema replacement or measured device speed/RSS gain. 64 KiB is a design bound, not a measured device optimum. P1-60/C05 remain partial.

## Verification

Freeze the complete preceding snapshot helper. Reverse only the output block, helper include and additive capability field; verify the full C05p AX hash and all preceding staged restorations. Reuse the existing snapshot runner/workflows, retaining 90 runners. Add 100,000 portable comparisons with the preceding representable formulas, exact string boundaries, size_t row/aggregate/base64 overflow, maximum wire fit and unchanged output arguments on refusal. Both production helpers are directly exercised.

Extend the existing Foundation/CF/CoreGraphics/ARC/ASan/UBSan snapshot executable with current/C05p helpers. Real strings cover four row fields, exact ASCII/multibyte/emoji limits, NUL, quotes and backslashes. A refusal-only NSObject method seam proves that UTF-16 admission skips the encoding-size call; it is not a Foundation string subclass and never reaches JSON. Add 128 full aggregate graph/sorted-JSON/work-count comparisons, exact caller wire cap, filtering precedence, returned-text pool ownership and 128 oversize/refusal/recovery lifecycles with balanced root/out-array lifetimes. Capability golden comparisons add only the new field. Existing preflight/attribute/query/admission/pool cases remain enabled.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete source restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. New portable output tests pass. Apple/iOS compilation and Foundation/ARC/ASan/UBSan execution require macOS CI. No real AX/UIKit/foreground/tap effect or device workload qualified.
