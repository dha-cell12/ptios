# C06n — continuous private VPN cleanup disconnect window

Date: 2026-11-02 (Asia/Bangkok). Baseline: `b1c7621d`; user reported the build passed, including C06m and recent fixture corrections. This checkpoint addresses another bounded part of **P1-67** for production TrollStore private-profile migration cleanup. TouchPOC excluded.

The cleanup disconnect phase used a wall-clock deadline starting after the disconnect action. It inspected status before expiry and could proceed to profile/marker deletion when disconnected was first observed after its nominal window. Action time was outside the deadline and interrupted or early-returning waits could issue probes early.

Use the shared continuous-clock policy with one five-second disconnect window starting before the action. Count action/probe/pool/wait time; keep 100 ms polling and main-thread run-loop publication support. Early main returns/EINTR finish only the remainder of the interval, with the last wait capped to remaining time. Scope probe/date temporaries. An invalid/regressed/overflow clock, failed sleep or expiry stops the phase with the existing cleanup-disconnect-timeout envelope. A separate timely-confirmation flag prevents even a late disconnected status from authorizing deletion.

Preserve all marker/store/record/selector preflight, already-disconnected/invalid handling and response fields. The complete deletion, marker-removal/error and post-delete publication tail remains byte-for-byte unchanged under the source guard. Timeout/error before timely confirmation makes no profile delete or marker remove call. No action rollback or automatic retry is introduced; disconnect may have committed or may complete later. Timeout metadata reports the last observed state, which can itself be disconnected when the probe returned late.

The new budget covers only the disconnect phase, after existing selection/status preflight. Opaque private calls/run-loop pauses cannot be preempted. Profile deletion, marker IO, queue residence and the original post-delete publication pause are outside this window. Main pauses still use short NSDate arguments; continuous-clock enforcement resumes when the API returns. Already-disconnected/invalid/missing-record paths retain their original policy. Public NEVPNManager source, C06l transition and C06m creation-verification behavior remain unchanged.

## Verification and limits

Extend the existing runner/creation fixture using actual current/frozen cleanup functions, the actual status formatter and controlled connection/store/files/clock/run-loop adapters. No real profile, marker, VPN or installed state is modified. C++14, strict warnings, ARC and sanitizers remain enabled. A new staged reversal verifies the complete preceding manager hash, explicitly compares cleanup preflight and deletion/publication tails, then runs the preceding C06m/C06l/public-transition guards. Existing portable window/wait boundary tests remain in place.

New native cases cover both main/off-main routes; ordinary/preflight/already-target/invalid/missing-record/delete/marker-error/timeout reply and side-effect parity; late action/probe/target refusal with zero deletion calls; invalid/regressed clocks, wall jumps, expensive probes, early main returns/EINTR/fatal sleeps, NS/C++ unwind and cross-pool result ownership. They also verify the unchanged separate post-delete pause. These Foundation/Objective-C++ assertions require macOS CI execution; they are not device measurements.

Windows validation passes all **76 workflow runners** (36 source, 40 safety), **521 existing workflow source checks**, staged full-manager hashes, JavaScript syntax, fixture extraction, expanded assert preprocessing and `git diff --check`. Sixteen artifact-only checks are skipped. The new Apple runtime cases were not compiled or executed on this host.

P1-67/C06 remain partial. Polling cadence/full configuration enumeration, fully asynchronous ownership, caller cancellation, opaque-call bounds and device CPU/IO/RSS/power/latency qualification remain open. No measured performance improvement or whole-cleanup deadline is claimed.
