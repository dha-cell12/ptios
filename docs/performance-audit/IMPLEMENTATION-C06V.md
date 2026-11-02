# C06v — coalesced license daemon reloads

Date: 2026-11-03 (Asia/Bangkok). Baseline: `47b24f7c`; user reported C06u build passed and requested continued implementation. Shared rootfull/roothide and production StreamControl coordinator; TouchPOC excluded.

## Admission and pending changes

Previously each `publishLicenseChange:` queued its own daemon reload on a global queue and, on failure, another independent one-second retry. Overlapping publications could run redundant reloads concurrently and retain many retry blocks.

Admit one reload flight under the coordinator monitor before enqueueing its first attempt. A dedicated serial queue executes it. Further publications set one pending bit instead of retaining a reason, callback or queued job. Changes arriving before an attempt starts are covered by that attempt. Changes arriving during transport cause one immediate fresh follow-up after it returns. The monitor is not held during transport or diagnostics IO.

Each unchanged state gets the preceding single retry after one second. If a publication arrives during that delay, the scheduled wake becomes a fresh primary attempt for the latest state; a failure there may receive its own single retry. Without another publication, a failed retry retires the flight. The same identity spans this chain and stale retired identities cannot perform work or clear a newer owner. There is at most one running attempt and one scheduled continuation per coordinator; continuous new publications can still keep work active.

Keep every publication's cache invalidation, UI snapshot refresh, generation read, change diagnostics and main notification unchanged. Only daemon reload work is coalesced. Reload is an invalidation hint that reads current persisted license state; it is not a per-publication transaction or signed artifact. Root transport/command/deadline and the production TrollStore route remain. No HTTP, lease persistence, authority or task gate policy changes.

## Completion, errors and diagnostics

For an isolated publication, preserve primary/retry reply classification, one-second retry delay and all diagnostic field names/timestamps/defaults. Diagnostics now describe actual serialized attempts; intermediate publications do not each get their own daemon response entry. During a pending-state follow-up, primary fields describe the new attempt and retry fields describe its retry if needed.

Transport or response-processing NS/C++ exceptions become `daemon_reload_exception` and follow the ordinary one-retry policy. A fault while writing the attempt diagnostics is contained so it cannot strand admission or replay an already successful reload. Other diagnostics, including the unchanged publication preamble, retain their preceding policy. A flight retires after success or its final failure when no change is pending.

This is process-local/per-instance coalescing, not a cross-process lease. It adds no caller cancellation or whole-flight deadline and does not preempt an opaque transport call. The unchanged TrollStore socket client still uses per-syscall timeouts; trickled input can occupy this flight beyond its nominal two seconds. C06p's continuous transport window is root-only. A retained delayed continuation can hold the coordinator until its wake; only one such continuation exists per flight. There is no idle timer or permanent cache. Reload may commit before a timeout and its existing retry remains at-least-once. Other lifecycle diagnostics IO, shared HTTP cancellation, durability and device qualification remain open; P1-77/C06 stay partial.

## Verification

Freeze the complete preceding `publishLicenseChange:`. A staged restoration removes only the new reload properties/queue/methods and restores its worker block, then verifies the full prior coordinator SHA256 before the existing C06p/C06o/C06g/C06f chain. An exact prefix check preserves all per-publication effects. Both root and production TrollStore workflows include the new runner, and extraction runs on Windows.

The native Foundation/GCD/ARC/ASan/UBSan fixture compiles complete current methods and the frozen publication method. It compares isolated success/failure/nil/Unicode primary/retry diagnostics; checks 1,000 pre-start publications use one reload and 1,001 diagnostics writes versus 1,000 reloads/2,000 writes in the frozen fixture; retains all publication effects; and checks in-flight pending changes, retry-delay promotion, new retry budgets, NS/C++ provider/diagnostics faults and stale identities. Thirty-two real serial-GCD lifecycles hold an active provider while eight threads publish 256 changes, then require exactly one fresh follow-up. A separate real delayed retry checks recovery/retirement. Network/UI/persistence providers are controlled; the real-GCD delayed adapter is shortened to one millisecond. These are fixture expectations, not device IO measurements.

Windows validation: all **81 workflow runners** (36 source, 45 safety), **521 existing workflow source checks**, staged full-coordinator/earlier checkpoint hashes, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Sixteen artifact-only checks skipped. New native execution and iOS builds require macOS CI; no real daemon, signed license, network endpoint or installed service is touched by the fixture.
