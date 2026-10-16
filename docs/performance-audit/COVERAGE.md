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
| VPN/accessibility/other shared | `shared/TLinkVPNDiagnostics.*`, `TLinkVPNManager.*`, `TLinkVPNPrivateRequest.*`, `TLinkAccessibilityTree.*`, broker edges | DONE (S009 rootfull + S010 TrollStore passes) | Rootfull Task-59/AX audited in S009; TrollStore private polling/helper lifecycle and 6015/6016 broker paths audited in S010 |
| appdelegate subproject | `appdelegate/*` | DONE (S010 first pass) | UIKit-wide keyboard observer lifecycle + global dyld compatibility hook audited |
| TrollStore PoC | `poc-trollstore/*` + `TunnelExtension/*` | DONE (S010 first pass) | Separate CI artifact; silent-audio residency, 1 Hz file heartbeat, 5 ms TCP idle polling/HOL and diagnostic timers audited |
| TrollStore production service lifecycle | `stream-app/app/StreamSupervisor.mm`, `TLinkVPNForegroundBroker.mm`, `vpnagent/*`, `privhelper/*`, shared private VPN helper edge | DONE (S010 first pass) | Unbounded helper waits, private VPN polling, broker concurrency and static preflight amplification audited |
| StreamControl license lifecycle | `stream-app/app/LicenseManager.mm`, `LicenseLifecycleCoordinator.mm`, `BackgroundServiceScheduler.mm` license edge | DONE (S011 first pass) | Repeated lease/status verification, late single-flight, BGTask abandoned work and diagnostics RMW amplification audited |
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
