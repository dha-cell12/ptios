# A05 — P0-03 / P1-02

Date: 2026-10-17. Base: `0dea340` (A04 build reported passed by the user).
Status: source implemented; portable native and source-contract checks passed. New macOS host integration, iOS builds and device qualification pending.

## Session ownership (P0-03)

Rootfull/roothide ScriptPlayer gives each RAW/JS launch its own cancellation token, settings/paths/manifest, history ID, console path, wake semaphore and successfully injected RAW touch state. Play.xm submits the complete settings tuple in one call; idle-only legacy setters remain for compatibility.

`shared/TLinkPlaybackState.h` is the production lifecycle: Idle -> Preparing -> Scheduled -> Running -> Waiting, or Stopping, then Finishing -> Idle. A short player lock protects lifecycle, current session/runtime and timer ownership. File/task/history work runs outside that lock. Reserve Preparing before setup to reject concurrent launchers before the worker is queued; generations are never reused or wrapped.

- Stop ACK means **cancellation requested**, not worker completion. isPlaying stays true and scheduler admission stays false through Stopping/Finishing. Start returns busy until old work and cleanup finish.
- Stop during preparation leaves cleanup ownership with the preparing caller, including repeated stop requests.
- RAW/JS iterations share a serial playback queue. Stop wakes a RAW delay, cancels repeat/heartbeat sources, requests JS runtime cancellation if present, and queues cleanup behind an active iteration. An executing task can still return normally; a new generation cannot overlap it.
- Completion validates session identity/generation and is idempotent. Close the RAW file, release tracked touches, finish that session's history and queue UI teardown before publishing Idle. Old finalizers cannot finish a new record, stop its heartbeat or clear its model fields.
- JS shares the boundary because its previous deferred legacy cleanup could erase a newly admitted RAW session. JS context, console logging, repeat and final-outcome behavior remain supported.
- UI work stays on main. Show/color validates current session; hide checks the window's generation and modifies no playback model fields. Error notifications are dispatched to main and suppressed when a newer session owns the player.

## Repeat/wait handling (P1-02; P1-03 mitigation)

Each repeat uses one cancellable dispatch source on the playback queue. The existing **gap after iteration completion** uses monotonic dispatch time. There is no NSTimer, nested CFRunLoopRun/Stop, recursive playback stack or global worker parked for the repeat gap. This remains gap-based scheduling, not a fixed-rate schedule or missed-tick replay.

Count 0 means one execution; positive N means N additional iterations. Preserve RAW negative-count indefinite repeat without decrement overflow; JS negative counts still do not repeat. Zero gaps are queued rather than recursively executed. Settings/manifest edits apply to the next session; the RAW entry file is reopened for each iteration.

`shared/TLinkRawPlayback.h` executes Task-18 waits with a wake semaphore, applying speed and preserving whole-microsecond truncation. Keep the Task-18 license gate. Other records use the real task dispatcher, its license checks, explicit byte length and the session context (including existing shell cancellation support).

No NSString is constructed for speed-adjusted waits. Wait/task callbacks use per-record autorelease pools. P1-03 is mitigated in source; no RSS improvement has been measured.

RAW input policy: at most 255 bytes per record, including newline, matching the old buffer capacity; accept a final line without newline. Reject overlong lines and embedded NUL before executing a fragment; skip blank LF/CRLF lines. Delays must be nonnegative signed-int microseconds, with scaled delay fitting the signed dispatch offset. Reject invalid/negative/nonfinite repeat gaps; nonpositive/nonfinite speed falls back to normal speed.

## Touch/history cleanup

An optional synchronous context observer runs only **after successful** task10/task61 injection. RAW uses it to track accepted DOWN/MOVE/UP frames. Cleanup emits UP-only frames for remaining fingers through the bounded injector, including after license cancellation; it authorizes no new DOWN/MOVE. Denied/invalid/failed injections are never observed.

Successful release is idempotent and precedes idle. Allocation/private-API failure can still make an UP attempt fail: record failure/last error and perform no delayed retry against a newer session. Native gesture handlers retain their existing cleanup. A06 still owns cancellation/deadlines inside long native operations. External clients sharing finger IDs do not gain separate HID namespaces here.

History belongs to the session and finishes once across repeats, after file/task cleanup. Failed runs still attempt screenshot evidence; JS preserves its console path. Cleanup exceptions record last error and release model ownership in finally. Persistence/durability errors remain C03/P1-53.

## Verification completed on Windows

`node scripts/check-raw-playback-safety.mjs` compiles actual production lifecycle/reader/touch tracking with C++14, MSVC `/W4 /WX`:

- 100,000 streamed records across read-buffer boundaries; speed adjustment, cancel before next record/after waits, EOF without newline, malformed/overlong/NUL records and overflow checks;
- finger 0/19, DOWN/MOVE/UP tracking, release at last accepted coordinates, failed release state and idempotent successful release;
- phase transitions, non-reused generations and stale entry/completion rejection;
- blocked native task followed by blocked cleanup: reservation fails after stop and throughout cleanup; next generation starts after finish;
- 8 test clients x 10,000 lifecycle cycles under an owner mutex matching the production lock contract.

Source checks cover complete launch-tuple wiring, file closure, context/length transport, delay license gate, successful-injection observer placement, UI guards and absence of old global playing/force-stop flags, NSTimer and nested run loop. A04 admission and run-history assertions now follow the new session implementation.

All 36 existing source-contract checks across both workflows pass. Native regressions: A01 passes both production injectors (100k frames each); A02 passes 10k indicator lifecycles; A03 passes 22 fault/success paths and 20k frames; A04 passes 8 x 10k registry cycles. git diff --check passes.

## Added macOS CI integration — pending runtime results

The rootfull/roothide workflow compiles the actual Objective-C++ session body and actual context classes with Foundation/dispatch and ASan/UBSan. `test/playback-runtime-test.mm` substitutes controlled UI/task/license/history/JS doubles. It covers stop during task/preparation/history/wait, repeat cancellation/count, touch release, JS/RAW isolation, prepare failure, license denial and recovery.

This suite was not run on Windows. It does not execute real UIKit, IOHID/private APIs, JS/helper teardown or persistence.

## Remaining build/device checks

1. Run the macOS host suite and build new rootfull/roothide artifacts plus affected context consumers. The latest user-reported build predates A05.
2. Repeatedly start dense RAW, stop and immediately start RAW/JS from multiple clients. Reject starts while stopping/finishing; after admission of a new session no older generation may inject, alter history/settings or hide its indicator.
3. Stop during long Task-18 delay, repeat gap, before worker entry, foreground switching and a long native task. Waiting repeats cancel without their deadline; non-cooperative native work may delay completion. A06 owns full native deadlines/cancellation, so no maximum stop latency is claimed here.
4. Verify RAW speed, task/license behavior, count 0/positive/negative, zero/nonzero gaps, finger release at stop/EOF, JS cancellation/repeat and failure evidence. Include allocation pressure and external finger-ID contention on the private injector.
5. Use Instruments to compare workers/run loops/timers and allocations during repeated start/stop, long gaps and speed-adjust playback. Measure RSS and UI timing before claiming quantitative gains.

Next: A06 (P0-14/P1-45/P1-46), JS/native context, cancellation and input/output budgets.
