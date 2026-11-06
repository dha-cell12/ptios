# A02b — Complete indicator presentation package

Date: 2026-11-07 (Asia/Bangkok). Baseline: `e6354650`; user reported D01b built successfully and requested larger implementation batches. Finding: P1-08. Scope: rootfull/roothide global indicator. Production TrollStore uses a different foreground overlay and does not instantiate this class; TouchPOC remains excluded.

## One checkpoint for the presentation path

1. Replace immediate layout on every accepted MOVE with a fixed 20-slot numeric mailbox. Each active finger retains only its latest point/radius. DOWN still creates its visible views immediately; UP removes them and cancels pending movement immediately. New DOWN, hide and stop retire preceding tickets. No IOHID event, parent array, per-move block or unbounded queue is retained.
2. Flush at display cadence with one lazily created CADisplayLink on the main run loop in common modes. Visit each slot once per callback. Pause when no movement remains; reuse the paused link on subsequent movement. Hide invalidates/releases it and clears all pending slots. No display link is created for an idle newly shown window. The existing main-owned HID client/generation and synchronous task26 start/stop/reload remain unchanged.
3. Use a weak window target proxy. The link retains its proxy without retaining the window. Destruction invalidates the link; a late tick also checks the link identity and window visibility. A stopped window or an old link cannot update a replacement session.
4. Cache the font attribute dictionary per window and the displayed integer coordinates/label width per finger. Subpixel or radius-only movement updates geometry while reusing the label. An identical final point/radius skips all UI writes; a burst returning to the already displayed point cancels its intermediate pending layout. Preserve the preceding integer truncation, text, measurement, frame and radius expressions for valid input.
5. Validate finite coordinates/radius/scale and representable label products before integer conversion; reject negative radius and nonfinite layout extents. This deliberately refuses malformed direct/HID values that could previously overflow an int or produce invalid CGRects. It does not clamp ordinary offscreen coordinates.
6. Display scheduling is optional. Nil target/link creation and reached NS/C++ factory/registration failures invalidate any partially registered link, then flush immediately. Later movement can retry scheduling. This preserves visual feedback when the optimization is unavailable.
7. Mark a reached UI write as uncommitted before applying it. Only a matching completed ticket can clear work and establish a known rendered point. A partial/throwing render remains retryable, including movement back to the last successfully displayed point. Reentrant MOVE, UP or DOWN changes the version so an old completion cannot clear new work.
8. Hold the reached views locally during each apply. Reentrant UP/DOWN cannot redirect remaining old writes to replacement views; label-cache publication also checks the reached view identities. Invalidate the label cache before changing text/frame so a partially failed label update is repaired on retry. Add a normal per-flush pool for temporary formatting objects. Explicitly link QuartzCore in the root tweak target.

Only visual MOVE telemetry is coalesced. Injection, recorder input, gesture timing, authority, task replies and task26 actions remain at the baseline. This introduces intentional display-cadence visual sampling and does not promise a latency bound when main is blocked.

## Verification

Freeze the complete preceding window implementation. Reversing only the class/proxy region and two includes reproduces the full baseline source, including unchanged HID callback/lifecycle/configuration/public wrappers. Guard the complete current source/core and the exact QuartzCore-only Makefile change. Keep the public header, touch/task/JS and TrollStore production sources unchanged.

Windows passes all **90 workflow runners** (36 source, 54 safety), **521 source checks** (16 artifact-only checks skipped), focused indicator rerun, JavaScript syntax, expanded assertion preprocessing, source/frozen/core/Makefile identities, two actual/frozen class/weak-target extraction checks and git diff --check. The existing portable indicator suite now executes:

- 100,000 moves retained as 20 latest slots and at most 20 completions per modeled flush.
- Stale/reentrant tickets, return-to-original cancellation, failed-write retry and hide/clear behavior.
- 200,000 lifecycle/flush actions against an independent active/latest/rendered oracle.
- 100,000 preceding coordinate-label conversions plus finite, signed-zero, negative-radius, integer and extent boundaries.
- The preceding 10,000 balanced HID-client lifecycles and slot/generation/failure tests.

Add one executable inside the existing indicator runner's macOS branch with ARC/ASan/UBSan. Compile both complete actual/frozen window classes with controlled UIKit views, text measurement and display scheduler; Foundation objects, weak ownership and pools are real. Native expectations cover 128 twenty-finger graph comparisons, 1000 MOVE calls without layout before one tick, one final label/three frame writes versus per-move work, subpixel label reuse, synchronous UP, stale ticks after hide/re-show, factory/partial-registration nil/NS/C++ recovery, partial render followed by a requested return to the prior point, reentrant MOVE and UP/DOWN, and 128 weak-owner lifecycles without explicit hide.

**New Apple compilation and native execution require macOS CI.** These native counts are fixture expectations, not Windows or device measurements. Real CADisplayLink/UIKit/HID delivery, tracking/low-power/60–120 Hz behavior, stop under touch activity, real window retention and main-thread CPU/frame latency require device qualification. Paused-link/proxy/slot bookkeeping adds bounded per-window overhead. P1-08 presentation source is implemented; device performance acceptance remains open.
