# Audit Coverage

Legend: DONE = first-pass audited; PARTIAL = opened/scanned but more work required; TODO = not audited for this performance project.

| Area | Files | Status | Notes |
|---|---|---:|---|
| Recording | `pccontrol/Record.xm/.h` | DONE (S001 first pass) | P0 per-event I/O/allocation; lifecycle issues found |
| RAW/JS playback controller | `pccontrol/ScriptPlayer.xm`, `Play.xm` | DONE (S001 first pass) | RAW hot-path + state race + repeat scheduling found |
| Touch injection | `pccontrol/Touch.xm/.h` | DONE (S002 first pass) | Per-child CF ownership leak confirmed; parser bounds + internal typed API findings |
| Task dispatch | `pccontrol/Task.xm` | DONE (S002 touch/gesture + S009 VPN/UI-tree passes) | Native string round-trip + relative-sleep drift + touch bounds; Task 59 timeout chain and tasks 77–81 AX execution audited |
| License hot path / control plane | `shared/TLinkRootfullLicensePolicy.mm`, `TLinkLicenseVerifier.mm`, `TLinkLicenseAuthorityClient.mm`, `license-authority/*` | DONE (S001/S011) | Per-command gates covered earlier; S011 audited 5 s authority refresh, 250 ms generation polling, signed-proof amplification and authority admission |
| Tweak/bootstrap HID callbacks | `pccontrol/Tweak.xm` | DONE (S002 first pass) | Permanent popup HID callback retained as P2 measurement item; off-main UIScreen access flagged |
| Touch indicator | `pccontrol/TouchIndicator/*` | DONE (S002 first pass) | finger-0 OOB, async NSError** lifetime, client leak, per-move main-queue churn confirmed |
| Scheduler | `pccontrol/Scheduler.xm`, `Play.xm` launch edge | DONE (S007 first pass) | timer ownership race, ghost timers, unbounded repeat frequency, main-thread launch preparation audited |
| H264 streaming | `pccontrol/H264Stream.xm` | DONE (S003 first pass) | TS tiny-send hot path, blocking backpressure, adaptive disk I/O, pacing and six idle listeners audited |
| IPC/socket | `pccontrol/IPCMessagePort.xm`, `SocketResponder.xm`, `tlinkauto-binary/SocketServer.mm` | DONE (S003 first pass) | hot-path logging/response allocation, global queue HOL blocking, response copies/writes audited |
| Screen/capture | `pccontrol/Screen.xm` | DONE (S004 first pass) | native-resolution capture, iPad ownership/failure paths, keep/screenshot encoding boundaries audited |
| Frame/image store | `pccontrol/Image.xm/.h`, task 66–70 paths | DONE (S004 first pass) | frame deep copies, byte retention, TTL, global queue HOL blocking, image-store lifetime audited |
| OCR/template matching | `TesseractOCRTask.mm`, `TextRecognization/*`, `ColorPicker.xm`, `TemplateMatch.xm` | DONE (S005 first pass) | engine/cache memory, OCR deadlines, Vision capture path, color/template complexity/cancellation audited |
| JS runtime internals | `TLinkautoJSRuntime.mm`, `jsruntime/*`, `shared/TLinkJSFileHandle.*`, helper RPC edge | DONE (S006 first pass) | helper polling transport, typed/raw bridge churn, cancellation-context loss, logging/file hot paths audited |
| Run history / persistence | `shared/TLinkRunHistory.*`, run-history event publish edge | DONE (S007 first pass) | index write amplification, lock critical section, status rereads, log retention and persistence failure semantics audited |
| Event channel | `shared/TLinkEventChannel.*`, task 95 ingress/consumer edge | DONE (S008 first pass) | 100 ms file polling, disconnect cancellation gap, journal rewrite/lock contention, response encoding/writes audited |
| VPN/accessibility/other shared | `shared/TLinkVPNDiagnostics.*`, `TLinkVPNManager.*`, `TLinkVPNPrivateRequest.*`, `TLinkAccessibilityTree.*`, broker edges | DONE (S009 rootfull + S010 TrollStore passes) | Rootfull Task-59/AX audited in S009; TrollStore polling/helper/broker paths in S010. C05a/g/i reuse symbols, C05b/c/j/k add timing gates, C05l/m cover owners/stop, C05n bounds query admission and C05p gates stopped snapshot preflight/acquisition; C05d/e bound scans/remove matches array, C05f/o drain node/matcher pools, C05q/r bound snapshot/hit text, C05s/t cap success wire/JSON sink and C05u gates caller stop and C05v checks captured remaining output before JSON append/publication, C05w caps raw requested storage and transfers immutable ownership, C05x rechecks captured stop/output after base64/final wire, C05y drains base64/final-format phase pools, C05z scopes root UTF8/synchronous notify, C05aa gates stopped Task77 providers, C05ab gates full UI/retry/tap and matcher/enqueue stages, C05ac bounds/scopes process fallback and propagates main budgets, C05ad gates captured probe/capability/foreground stages with notify/CF cleanup and per-key pools, C05ae adds lazy immutable selector plans/pre-enqueue field admission/find-operation pools, and C05h shares capability tasks. C06l–n/s bound VPN phases/completion; C06ac/ad reduce merge work/snapshot retention. AX root/selector fusion/metadata/Foundation temporary JSON/error-wire bounds/notify/value/opaque queue waits and VPN polling/full enumeration/cancellation/device qualification remain open. |
| appdelegate subproject | `appdelegate/*` | DONE (S010 first pass) | UIKit-wide keyboard observer lifecycle + global dyld compatibility hook audited |
| TrollStore PoC | `poc-trollstore/*` + `TunnelExtension/*` | DONE (S010 first pass) | Separate CI artifact; silent-audio residency, 1 Hz file heartbeat, 5 ms TCP idle polling/HOL and diagnostic timers audited |
| TrollStore production service lifecycle | `stream-app/app/StreamSupervisor.mm`, `TLinkVPNForegroundBroker.mm`, `vpnagent/*`, `privhelper/*`, shared private VPN helper edge | DONE (S010 first pass) | Unbounded helper waits, private VPN polling, broker concurrency and static preflight amplification audited. C06q/r bound helpers; C06t/u bound IO/share hello; C06x/y/z fix watcher timing/respawn/callback ownership; C06aa bounds ensure queue admission. Queue residence/whole-operation budgets/active cancellation/coalescing/kernel identity/external adoption/device qualification remain open. |
| StreamControl license lifecycle | `stream-app/app/LicenseManager.mm`, `LicenseLifecycleCoordinator.mm`, `BackgroundServiceScheduler.mm` license edge | DONE (S011 first pass) | Repeated verification, late single-flight, BGTask abandoned work and diagnostics amplification audited. C06o merges reads; C06p/v/w bound/coalesce reload; C06ab fixes UI worker failure recovery/latest-pending handoff. Writer IO/lock/durability/cancellation/device qualification remain open. |
| StreamControl app task client | `stream-app/app/TLinkSocketClient.mm` | DONE (C06w scoped follow-up) | Blocking connect, per-syscall timeout renewal, unchecked writes and partial-prefix acceptance replaced with a shared continuous window/exact writes/scoped descriptor. Public codec and ordinary replies preserved; caller/global admission/cancellation/device qualification remain open. |
| Vendor/decompiled/reference trees | frameworks, third_party, xxtouch decompile | EXCLUDED initially | only inspect when a call path requires it |


## Checkpoint notes

- S001: recording + RAW playback controller.
- S002: touch injection, native gesture path, bootstrap/indicator idle/event path, benchmark probe design.
- Benchmark details: `BENCHMARK-S002.md`.


- S003: IPC/daemon socket ingress + active/idle H264 streaming + adaptive streaming cross-process state.
- Benchmark details: `BENCHMARK-S003.md`.


- S004: native screen capture + frame/image object store + task 66–70 + TemplateMatch/ScreenMatch lifetime boundaries.
- Benchmark details: `BENCHMARK-S004.md`.


- S005: deep Tesseract/Vision OCR + ColorPicker + TemplateMatch compute audit. Recovered from fallback after connector outage.
- Benchmark details: `BENCHMARK-S005.md`.
- S006: JavaScript runtime/native bridge + helper RPC + JS file-handle live call paths.
- Benchmark details: `BENCHMARK-S006.md`.
- S007: scheduler timer lifecycle + auto-launch persistence + shared run-history persistence/status edge.
- Benchmark details: `BENCHMARK-S007.md`.
- S008: shared event-channel Task 95 long-poll, rootfull daemon deferred response path, and subscription cadence.
- Benchmark details: `BENCHMARK-S008.md`.
- S009: shared VPN diagnostics/manager rootfull broker path + Accessibility tasks 77–81 and SpringBoard IPC edge.
- Benchmark details: `BENCHMARK-S009.md`.
- S010: appdelegate + standalone TouchPOC/TunnelExtension + live StreamControl TrollStore private VPN/helper/supervisor compatibility edges.
- Benchmark details: `BENCHMARK-S010.md`.
- S011: license verifier generation/cache control plane + signed rootfull authority + StreamControl activation/refresh/background lifecycle.
- Benchmark details: `BENCHMARK-S011.md`.

All intentionally in-scope first-pass rows are now DONE. Vendor/decompiled/reference trees remain explicitly excluded unless a live call path requires them.

D01a implementation follow-up (2026-11-07): pccontrol Screen/Common and production StreamCaptureSource now share bounded capture preparation/ownership helpers. Cache hardware decision/immutable property tuples only; geometry remains live and fresh surfaces remain per capture. Source/portable checks pass; new Foundation/native/device qualification pending. See IMPLEMENTATION-D01A.md.

D01b implementation follow-up (2026-11-07): root Image and production CaptureCore/StreamCaptureSource share successful immutable RGB preparation and scoped bitmap/frame/provider/byte/CV/CPU-lock ownership. Seven connected changes, frozen full-source reversals and portable memo/byte regressions pass. Fresh source surfaces and rendering algorithms remain; Apple/native/device qualification pending. See IMPLEMENTATION-D01B.md.

A02b implementation follow-up (2026-11-07): rootfull/roothide indicator P1-08 presentation source now uses bounded per-finger display coalescing, label/duplicate caches and weak/stale/reentrant/fault-safe owners. Full source reversal and portable numeric/oracle/lifecycle checks pass. Actual/frozen class Foundation/ARC execution and UIKit/HID/device cadence/CPU qualification pending. See IMPLEMENTATION-A02B.md.

C03ac implementation follow-up (2026-11-07): shared FileHandle read/write payload paths across root/helper/production TrollStore now use direct mutable read storage, checked progress, retained UTF8 write views and four normal operation pools. Full-class prior restoration, portable oracle/fault/boundary and macro integration checks pass; dual reply fields and path/authority/descriptor/JS policy remain. New Foundation/ARC/device qualification pending. See IMPLEMENTATION-C03AC.md.

C05af implementation follow-up (2026-11-07): shared root/TrollStore AX keeps its exact Foundation-class whitelist, adds an instance copy-identity witness for known mutable ancestry and reuses per-find mode classification/decode. Portable mode/fault plans and complete prior source/header restoration pass. Native full graph/sharing/copy ownership/mutation coverage and SDK/device performance await qualification. See IMPLEMENTATION-C05AF.md.

C03ad implementation follow-up (2026-11-07): shared event/history uses bounded ASCII token/name preparation, single-pass checked journal integers, bounded batch capacity and normal publish/status pools. Six scoped reversals reproduce the complete preceding sources; portable UTF16/uint64 oracles and all90/521 Windows checks pass. Foundation Unicode/errno/batch/real POSIX/MRC ownership coverage awaits macOS CI; complete index/journal rewrite and device gains remain open. See IMPLEMENTATION-C03AD.md.

C03ae implementation follow-up (2026-11-07): shared history now plans only the last50 console components, scopes console/JSON/public operations and regex/line/status-row/prune temporaries, and selects status rows directly from its owned graph. Seven full preceding-source reversals and100k portable complete-split oracles pass with all90/521 Windows checks. Complete current/preceding Foundation/POSIX transaction, tail and explicit MRC ownership additions await macOS CI; rewrite amplification/durability/device gains remain open. See IMPLEMENTATION-C03AE.md.

C03af implementation follow-up (2026-11-07): shared event channel uses typed seven-field/errno identity, conditional validated permission repair, direct bounded ASCII topic checks and record/write/waiter/BeginPoll pools. Five complete preceding-source reversals and100k portable identity/topic/permission cases pass with all90/521 Windows checks. Actual/frozen metadata/permissions/parser and journal/held-queue/eight-waiter MRC additions await macOS CI; full journal rewrite/epoch/durability/device performance remain open. See IMPLEMENTATION-C03AF.md.
