# C03bb — Root console publication and drain ownership

Date: 2026-11-09 (Asia/Bangkok). Baseline: `05851c52`; user reported C03ba built successfully and requested larger packages. Scope: P1-42 root/roothide production console queue. TouchPOC is excluded. Helper/TrollStore backends remain unchanged.

## Enqueue is a transaction

The root logger previously pushed an entry, counted it accepted and set its scheduled flag before dispatch_async returned. An exception after publication could leave pending payloads and permits without a drain job. A discarded copied job had no retirement owner. Finish used a queue barrier for totals but did not explicitly consume that stranded pending array.

Bundle a pure token planner, a private owned drain ticket and publication rollback. Under the existing unfair lock, prepare a ticket lease, allocate the ticket for a newly scheduled job, publish the entry and submit that ticket. Count acceptance only after submission succeeds. Every uncommitted exit removes only the newly inserted entry and rolls back only a schedule that this publication started. Preserve an existing consumer when a joining publication fails. Allocation failure before push, enqueue NS/C++ unwind before/after block copy and an immediately discarded block all retain a recovery path.

The publisher keeps its own entry and ticket references until after the publication finally unlocks. Rollback can remove vector ownership while those references prevent payload/ticket destructors from reentering the held unfair lock. This is important for both Objective-C and C++ unwind; simply resetting a scheduled flag in the outer catch is insufficient.

## Job tokens and abandoned work

Each scheduled job receives a monotonically increasing64-bit token, independent of the run generation. A consumer checks its token before taking any batch; a ticket's last-reference destructor retires only its own still-current token. Abandonment swaps pending entries out under lock, then counts drops and releases payloads outside the lock. A stale copied block can neither consume nor discard a later job in the same run or another run.

Joining an existing job keeps its token. UINT64_MAX is usable once; future scheduling refuses instead of wrapping into an old identity. The ticket keeps the logger alive until execution or discard settles its ownership, matching the existing queued-owner lifetime. One shared ticket still represents the committed drain; there is no dispatch block per record and no retry/replay of uncertain writes.

Move the admission permit before all payload fields in the actual entry declaration. C++/ARC destruction now retires the managed payload references before reopening the permit on rollback/discard paths. The existing normal drain still explicitly moves the permit out, resets its entry and finishes the permit in that order. Foundation/provider-retained references remain outside a hard RSS guarantee.

## Terminal close

After closing admission, the existing serial queue barrier explicitly drains the current token before writing lifetime totals. This settles pending work even if an enqueue provider retained its copied block without running it. A later execution/destruction of that block is stale. Existing run-generation checks still refuse producers that were formatting when a run closed or changed.

Keep ordinary formatted/file/system output,64-record admission, vector grouping/rotation, independent sinks, summary totals and completion-proof ordering. The previous full runtime is reconstructed exactly by reversing these ownership changes before all older guards. Script/task/license authority, cancellation, module/prelude, public headers, file APIs and build targets are unchanged.

Accepted remains publication, not confirmed delivery. A record admitted before its job is subsequently abandoned can count in both accepted and dropped; refused publication counts dropped. Logging remains best effort. The finish barrier and opaque sink IO are still synchronous; this package adds no barrier-failure fallback, IO deadline, durability or general sink-reentrant finish guarantee.

## Validation

Portable actual-planner coverage passes100000 prepare/join/rollback/retire/stale transactions, UINT64_MAX exhaustion including rollback and80000 concurrent exactly-once publications under the same externally serialized contract as production. The predecessor's formatter/queue/vector/retention/producer checks remain active.

Extend the existing macOS Foundation/GCD/JSCore/ARC/ASan/UBSan executable with the actual current entry and methods. The fixture replaces only the vector-allocation/enqueue provider seams: first/joining bad_alloc, NS/C++ exceptions before/after block copy, discarded/retained jobs, abandoned eight-record batch cleanup, same-run and cross-run stale callbacks, explicit finish drain and no replay after completion. A controlled ARC witness in the actual entry verifies128 payload-before-permit retirements with zero remaining charges. Existing real files, partial-write faults and normal output comparisons remain. These are controlled lifetimes, not measured Foundation allocations or device memory.

Source validation checks complete preceding runtime restoration, constructor/field coherence, unlock-before-retirement, enqueue rollback, stale-token checks, terminal drain and native extraction of current entry fields. Windows validation passes90 workflow runner results (36 source/54 safety portable subsets),521 source assertions (16 artifact-only checks skipped), JavaScript syntax, six-file assertion macro preprocessing and diff whitespace. Native Apple compilation/execution and device performance require macOS CI; they are not claimed from Windows results.
