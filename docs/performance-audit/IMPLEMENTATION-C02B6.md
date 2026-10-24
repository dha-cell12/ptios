# C02b6 — structured multi-point frame color

Date: 2026-10-24 (Asia/Bangkok). Baseline: `1d710aa`; the user reported the corrected C02b5 build passed before this slice.
Status: **build reported passed by the user at `650a4f4`; device qualification pending**.
Finding: **P0-13, framePickColors portion**. Other typed methods/helper transport remain open.

## Result and scope

Root JS framePickColors prepares a bounded numeric point plan and calls one licensed task-69 entry. It reads all requested pixels from one immutable frame snapshot. The bridge no longer formats/joins a point table, creates an aggregate UTF-8 request, dispatches through the RAW task/CF stream, captures a response vector or reparses a successful response. Compatibility output strings remain necessary; the bounded coord token is converted to UTF-8 for exact RAW ingress parity.

The numeric and RAW pick_many readers share point conversion, bounds, work accounting and BGRA reading. RAW still accepts its existing wire syntax and retains its lazy per-point parsing. Production TrollStore and TouchPOC source are unchanged; both production CI workflows already run the shared root fixtures.

## Compatibility and limits

- Preserve complete JS array/object/finite validation before options and side effects, including a malformed point beyond the storage/count/input limit. Extra array fields remain ignored and missing object x/y retain the old zero default.
- Coordinates still follow JS %.0f formatting then strict double conversion. Point scale, signed zero, negative/fractional/extreme values and first-failure order follow the legacy reader; invalid points are never clamped into the frame.
- Store at most 512 numeric points. Count saturates at 513; table length saturates at 32769. Stop extra numeric formatting once both counters saturate while continuing JS validation. The point count/table limit remains a backend decision after frame/geometry/TTL checks.
- Calculate the equivalent aggregate 8192 UTF-16-unit request cap using numeric ASCII lengths, commas/pipes, frame/age digits, mode/separators and coord-token length. Checked subtraction rejects overflow. Size rejection precedes actual UTF-8 conversion/NUL rejection, which precedes authorization. Remaining fields are ASCII, so the old 32 KiB encoded cap is satisfied after these checks.
- Preserve error order: JS validation, ingress size/encoding, caller stop/task authorization, color admission, frame options, image admission, snapshot/BGRA/geometry, TTL, table/count, then ordered point conversion/bounds/work/read. In particular a missing or expired frame still wins over a 513-point table or an invalid coordinate. Zero maxAgeMs still selects the default TTL.

## Authority, budgets and output

The typed task entry installs the existing three-second C01 child budget before its single task-69 license gate, rechecks stop after authorization and shares the parent owner/token/output limit without shortening the caller deadline. Denial, parent cancellation/deadline, local C01 expiry, exceptions and output overflow keep the existing response mappings.

The core uses the existing two color and two image admissions and holds one shared immutable frame reference through the loop. It never recaptures the display. Failed/expired work returns no public partial colors and releases its reader/admissions. Formatting checks cooperative cancellation and builds raw/parts and numeric colors directly from the result vector. Success preserves x/y/RGB, order/duplicates, ageMs, the two historical three-decimal time columns and totalMs rounded through that same text. The final compatibility raw byte length is checked against the caller output limit.

No measured latency/allocation/RSS gain or hard completion deadline is claimed. Opaque authorization/store/framework waits remain cooperative.

## Validation

- Windows: 36 existing source-contract runners and 20 native runners pass. The portable modern-image runner adds 10,000 plans checked against the frozen decimal wire lengths, exact 8192/8193 caps, 512/513 count/storage and 100,000-point saturation. Existing 100k scalar cases, 3000 matcher oracle cases and native-budget/touch/batch regressions pass.
- All 521 direct source-grep commands from the production TrollStore workflow pass; 16 artifact-only commands need CI package outputs.
- The expanded Foundation bridge fixture compiles the actual bridge and task entry, including with YES/NO undefined. A frozen C02b5 JS branch plus the actual bounded RAW bridge provides the compatibility oracle with a controlled physical-frame backend. It compares 120 list cases plus mixed/default/invalid shapes, 512/513, validation beyond oversized input, Unicode/NUL, exact ingress limits, one license gate, C01/caller budget isolation, authorization delay, faults/cancellation and exact output caps. Typed calls must make no RAW dispatch.
- The actual Image adapter fixture adds 120 RAW/numeric list cases with a controlled metadata clock and real Foundation containers, padded BGRA stride/point scale, count/coordinate versus snapshot/geometry/TTL precedence, busy gates, held snapshot after erase, cancellation and released admissions. It verifies no display recapture.
- Standards-conforming preprocessing passes assert argument boundaries for native-bridge/color/frame-color fixtures with a rejecting negative control.
- **Foundation/macOS execution, ASan/UBSan, iOS builds and physical-device measurements were not run on this Windows host.** Both workflows already invoke the expanded runners; their new branches await CI/device qualification.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare JS/RAW multi-point reads on the same frame for point/pixel scaling, default/mixed input shapes, duplicate and boundary points, 512/513 counts, expired/missing frames, error ordering, exact colors/raw/parts/age/time, authorization/cancellation/output limits and recovery. Verify no recapture, no retained frame reader/admission, and measure allocations and latency independently of frame creation.

Continue other measured P0-13 methods, then P0-12 event-driven helper RPC, P1-40 config snapshots and P1-41 byte-bounded dedupe. C01/C02 device acceptance remains open.
