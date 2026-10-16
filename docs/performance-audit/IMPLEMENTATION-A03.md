# A03 — P1-19

Date: 2026-10-16. Base: `8a67002` (A02 build reported passed by the user).
Status: source implemented; native host and source-contract checks passed. New iOS build and device validation pending.

## Scope and changes

This group fixes `pccontrol/Screen.xm`, shared by the rootfull/roothide tweak. The production TrollStore capture implementation was inspected and does not contain the same borrowed-color-space release. Prototype TouchPOC remains excluded.

- Check IOSurface creation before Lock or rendering. A failed lock releases the owned surface and returns NULL without rendering or unlocking an unacquired lock.
- Check image creation before reading dimensions. Reject empty images. Check bitmap-context creation before transforms/draw; handle failed rotated-image creation with complete cleanup.
- Treat `CGImageGetColorSpace` as borrowed. Keep the source image alive through drawing, image creation and context release; never release the borrowed color-space reference directly.
- Release the source after the rotation helper returns. Unlock each successfully locked surface once and release the Create-rule surface reference on both success and failure. If Unlock reports failure, discard the image and return NULL.
- Derive the rotated bitmap stride from its destination width (source height), aligned to 32 bytes, instead of reusing the source stride. Preserve the existing -90-degree transform and iPad model/orientation convention.
- Validate finite positive bounds/scale, representable pixel dimensions, aligned-row arithmetic and allocation multiplication before allocating. Preserve native resolution, BGRA surface format and existing integer truncation of valid scaled bounds. Rotation expects 8-bit components for the requested 32-bit surface and fails cleanly for an unexpected component depth or missing color space.
- Document the public capture result as owned (+1), or NULL on failure. Existing screenshot, keep-screen, image and H264 consumers already handle a NULL result. Keep-screen retained-image behavior remains intact.

This group does not add target-resolution capture or pools (D01), cache device classification, change UIScreen thread access, or change keep-screen concurrency semantics.

## Verification completed

`node scripts/check-capture-safety.mjs` extracts and compiles the actual production geometry/rotation/surface ownership functions with C++14 against retain-counted API doubles. Windows execution used MSVC `/W4 /WX`.

- 22 success/fault paths cover both orientation branches: failed surface creation, lock, image creation, zero image dimensions, missing color space, unexpected component depth, failed context creation, failed rotated-image creation and unlock error.
- Geometry tests cover portrait/landscape normalization, scale/truncation, NaN/infinity/nonpositive/subpixel inputs, out-of-range dimensions and row-size overflow guards.
- Check destination dimensions, 32-byte stride alignment, the existing rotation transforms, source/color lifetime during context use, one unlock per acquired lock and owned result lifetime after local cleanup.
- 10,000 captures per branch (20,000 total), including asymmetric non-aligned dimensions, leave zero live test surfaces/images/contexts/color spaces after caller release.
- Source checks cover the Objective-C property mapping, ownership helper wiring, keep-screen retain and absence of a borrowed-color-space release. The runner is included in the rootfull/roothide CI workflow with ASan/UBSan on macOS.

A01 native tests passed again for both production touch implementations (100k-frame runs each), A02 passed 10k indicator lifecycles, and all 29 existing source-contract checks passed. `git diff --check` passed.

## Remaining build/device checks

1. Build rootfull and roothide with the new Screen.xm; the user's latest successful build predates A03. Windows host tests do not compile UIKit/Logos or the real private APIs.
2. On iPhone and iPad8+ in both orientations, verify screenshot dimensions, orientation, colors, crop coordinates, image/OCR consumers and H264 output against the previous artifact. Exercise keep/unkeep and release returned snapshots.
3. Run repeated capture under Instruments (S004 Probe H), including memory pressure and diagnostic allocation/lock failures. Check live CGImage, CGContext and IOSurface counts after caller release and compare RSS/latency; no measured performance gain is claimed yet.
4. Verify real `UICreateCGImageFromIOSurface` provider lifetime after unlocking/releasing the local surface reference. The native double models a provider retaining the surface, matching the existing caller assumption; it cannot establish private API behavior. The render API returns void, so this change cannot detect a render-server failure that still yields an image.

Do not mark A03 device-validated until target results are available. Next planned group: A04 scheduler ownership/admission and auto-launch read-modify-write (P0-15/P0-16/P1-52).
