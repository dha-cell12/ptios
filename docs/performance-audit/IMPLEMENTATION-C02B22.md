# C02b22 — structured captureImage entry, safe crop bounds and owned resources

Date: 2026-10-25 (Asia/Bangkok). Baseline: `5ffc503`; the user reported C02b21 built successfully before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.
Finding: **P0-13, captureImage adapter**. Other native adapters and helper transport/config/dedupe remain open.

## Result and scope

Root captureImage prepares a numeric crop/owner request and calls one task-48 entry directly. RAW action 1 and typed callers share screen capture, crop planning, CGImage crop/conversion, charge/owner assignment and immutable image publication. The typed entry reuses C02b21's numeric image result and final compatibility dictionary. JS tracks the returned ID and returns that dictionary.

This method no longer builds a complete task request, dispatches through RAW, creates a CF reply stream/response vector or splits/reparses the successful reply. Four small Foundation scalar format/conversion operations remain to preserve the precise historical %.0f -> intValue behavior, especially half ties, signed zero and large finite values. A bounded owner suffix formatter/parser also remains to preserve its UTF-8/NUL, delimiter, truncation/default and whitespace semantics.

Keep ID/width/height and the exact raw/parts fields through the shared formatter. RAW keeps its three-field body. Production TrollStore and TouchPOC source are unchanged. No measured allocation, latency, CPU or RSS benefit is claimed.

## Input and crop policy

- Keep the four optional argument defaults and reject nonfinite coordinates before dispatch. Use the actual Foundation scalar conversions rather than assuming C library overflow or rounding behavior. Preserve one input-length check before encoded-byte/NUL admission, then task policy.
- Envelope accounting reserves eleven ASCII units/bytes: 481;; plus the three numeric field delimiters. Shared checks use bounded subtraction for the 8192-unit and 32-KiB limits, including saturated size inputs. Under finite-double and existing 96-unit owner caps, real typed requests fit below those ceilings; exact/saturated boundaries are policy-helper tests, not reachable giant-owner JS cases.
- Preserve negative origins clamped to zero, origins beyond the screen clamped to the last pixel, and nonpositive/oversized extents expanded/clamped to the remaining screen area. Compare an extent against screenWidth-x/screenHeight-y, avoiding the old signed x+width/y+height overflow. Defined legacy cases retain their crop; formerly overflowing positive extents now safely clamp. Invalid/oversized backend screen geometry fails with image_capture_geometry_invalid before integer narrowing/cropping.
- RAW retains its Foundation %s/field parser and compute admission before its missing-field check. Both routes use the same two-request compute gate, pixel/count/byte ledger, grayscale conversion, image store, explicit lifetime and charged held readers. No additional screenshot or image lookup is introduced.

## Ownership, authority and commit

The common core releases the screen in finally around planning/crop, and releases the cropped image in finally around pixel/charge/conversion work. This covers normal returns and NS/C++ exceptions. Both CGImage handles are released before store publication; gray data and its reservation continue through their existing owned lifetimes. The unused production NSArray-owner helper is removed; frozen old-handler oracles retain a separate archived copy.

The typed function clears numeric output and publication ID before admission. It reports the newly assigned store ID before copying result metadata. Keep the ordinary caller child budget, no response sink, pre-stop and 1024-byte creation-response floor before exactly one task-48 license gate, another stop check, then final output/stop checks after building the result. Task 48 adds no C01-local duration.

Until commit, failures after publication attempt direct cleanup of only this call's new ID in the exempt context. This covers backend/result NS/C++ faults, false-without-error fallback image_capture_failed, late cancellation/deadline and defensive output overflow. An unrelated image remains untouched. Cleanup remains best-effort; images have explicit lifetime and no frame TTL fallback. Opaque screen/CV/license/owner operations remain cooperative/nonpreemptible; no hard completion deadline is claimed.

## Validation

- All 56 workflow runners pass on Windows: 36 source-contract and 20 native runners. All 521 direct workflow source-grep commands pass; 16 artifact-only checks require CI outputs. Standards-conforming assert preprocessing passes the existing and new fixtures with a rejecting negative control. git diff --check passes. The final legacy-helper extraction cleanup passes the affected storage/native-budget runners and all 521 source greps. One rerun hit host EPERM deleting an already-passed temporary native executable; a subsequent rerun succeeds without changing cleanup policy.
- Portable tests add 100k defined legacy crop comparisons and 5625 combinations against an independent wide-integer boundary oracle, covering INT_MIN/INT_MAX origins/extents, 1/8/INT_MAX screen dimensions, invalid geometry and exact/saturated input budgets. Existing storage/release/reader/ledger lifecycle suites remain.
- The actual Foundation bridge/entry fixture adds 240 frozen JS/RAW comparisons across half-decimal/large finite scalar conversions, owner sanitation/encoding/defaults, exact result/tracking and one task-48 gate. Add missing/nonfinite argument cases, errors, gate-time cancellation/expiry, caller/output policy, pre/post-publication and formatter faults, late stop/deadline, false result and isolated rollback. Final output overflow is injected at the formatter boundary; the normal three-integer reply fits below the retained floor.
- The actual capture/store fixture adds 96 frozen old/RAW/direct comparisons in the defined arithmetic domain. It uses real CGImage screen/provider/crop ownership with a controlled conversion. Additional cases cover formerly overflowing extents, stale-output clearing on busy admission, failed screen/geometry/crop/pixel/byte/count/conversion/publication and NS/C++ exceptions at crop/conversion, ending with zero image charges/CG providers. It does not qualify real display capture or OpenCV pixel conversion.
- All-host guards cover direct entry dependencies, floor/gate/commit/finally order, shared RAW body, protected CGImage releases and fixture order after publishImage and the legacy owner helper. No warning or sanitizer setting is relaxed.
- **Actual Foundation/macOS execution, ASan/UBSan, iOS builds, real screen/OpenCV and device measurements were not run on this Windows host.** New Foundation branches await macOS CI/device qualification.

## Acceptance and next slice

Build rootfull/roothide observe/enforced variants. Compare captureImage with RAW task 48 action 1 for default/negative/outside origins, fractional inputs, extent limits, owner variants and exact reply metadata. Confirm oversized positive extents clamp without overflow, real crop/conversion quality is unchanged, and failures release CGImages and only the newly owned store ID. Exercise caller stop/deadline and memory/count pressure while held readers remain valid. Measure bridge cost separately from capture/conversion and ledger pressure.

Continue remaining P0-13 adapters, P0-12 event-driven helper RPC, P1-40 policy snapshots and P1-41 byte-bounded dedupe. C01/C02 performance/device acceptance remains open.
