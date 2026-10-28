# C03j — re-enable retained metadata recovery after mutation write failures

Date: 2026-10-29 (Asia/Bangkok). Baseline: `7f212b05` (C03i), build passed according to the user.
Status: **source implemented; new macOS Foundation/POSIX/ARC/sanitizer execution and device qualification pending**.
Finding: **P1-53 retained metadata coherence after local write failures in a running process**.

## Result

C03i completed recovery only once per process. A later failed mutation could leave record/evidence ahead of the index until restart. The existing persistence-failure handler now unsets the completion flag for begin/finish failures at evidence, record or index stages. This includes required writer NO results and contained NS/C++ exceptions, even when replacement already occurred. Invalidate before updating diagnostics, so saturation does not disable recovery. Serialization/pre-write failures at the same stages conservatively invalidate too.

The next mutation reads the current checked index under the monitor/flock and runs C03i's unchanged bounded repair pass before its own work. Old index authority restores old retained metadata; an index that committed before a reported failure remains authoritative. No index rollback or automatic replay/retry of the failed mutation/event occurs. A different subsequent operation can trigger repair. A failed repair keeps the flag unset and blocks that operation; the next call can retry repair. Successful repair restores the existing fast path for later normal updates.

Lock/read/preparation failures and post-commit pruning diagnostics do not change the flag. Status remains read-only. Successful record/evidence/index/event payloads, diagnostics shape, SDK types and script best-effort lifecycle remain unchanged. No new scan/timer/queue/marker on the normal success path. Shared rootfull/roothide and production TrollStore source is covered; TouchPOC is excluded.

## Verification

The source guard removes only the six-line invalidation addition and hashes the complete source against C03i at 7f212b05. Earlier complete inverse/hash comparisons remain. The actual changed source is compiled in the macOS runtime fixture.

Thirty new cases start from a warm process and inject failures at begin record/index and finish evidence/record/index: NO, NS or C++ before writing, plus NO, NS or C++ after actual replacement. Require no false event, an unset gate, correct bounded diagnostics and old/new index authority. Status must not scan artifacts or clear the flag. A different public operation must repair all authoritative retained JSON without restart or failure-event replay, preserve orphan/screenshot bytes, release descriptors/flock and restore the clean fast path. A damaged separate retained anchor makes every case require a real repair without masking the failed target's old/new versions.

Additional checks cover failed recovery/retry and a saturated failure counter. Existing public writer-fault tests now require invalidation/recovery; read/lock tests preserve the previous flag; committed cleanup faults preserve the clean flag. The restart fixture performs both failed mutations before damaging files/launching its child, retaining its exact four-repair expectation without bypassing the new local recovery behavior.

All 65 workflow runners (36 source-contract, 29 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing, focused history source/contract checks and git diff --check pass on Windows. Sixteen artifact-only checks need CI outputs. The new Foundation/POSIX/ARC/ASan/UBSan cases do not run on Windows and remain pending macOS CI; device qualification is separate. No SDK or unrelated TypeScript changes were made.

## Remaining work

Invalidation is process-local. Another already-warm owner is not notified of this failure, and external filesystem damage does not automatically reset its flag. Cross-process dirty-state coordination, missing/corrupt index reconstruction, orphan ownership/retention, screenshot availability, event delivery/replay and real device disk-full/permissions/stop/restart/latency/RSS qualification remain open. Separate atomic writes and their power-loss limits remain; no complete P1-53 closure is claimed.
