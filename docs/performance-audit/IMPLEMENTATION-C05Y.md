# C05y — Drain temporary objects between success-wire phases

Date: 2026-11-06 (Asia/Bangkok). Baseline: `b68c3eb0`; user reported C05x build passed and requested continued implementation. Continues C05/P1-60 in four rootfull/roothide/production TrollStore UI result/capability codecs. TouchPOC excluded.

## Phase pools

Put base64 encoding in its own autorelease pool, assigning the resulting NSString to a strong variable outside the pool. Put final success representation construction in a second pool: root preserves a precise-lifetime NSString, while TrollStore preserves its NSData. Ordinary pool exit retires pending temporary autoreleases from that phase before continuing.

The C05x captured stop/output checks stay after each phase, now after pool drain. They can therefore refuse a stop or output shortage observed during normal temporary destruction. Root obtains the borrowed UTF-8 pointer after the formatting pool, then checks and uses it synchronously while the precise-lifetime response owner is still alive. The pointer is not obtained inside a pool that drains before its use.

Keep JSON writing, hard limits, caller/parent/cleanup semantics, nil-base64 fallback, ordinary graph/base64/framing bytes, error priorities, NS/C++ propagation and all handler/query/action/foreground/license/tap source. No new queue, retry, deadline, transport admission or protocol field is introduced. Pool destruction cannot roll back a previously committed action.

## Limits and cost

This narrows normal temporary-retention intervals. It does not eliminate the explicit JSON/base64/final response owners, bound provider/root/metadata graphs, guarantee particular Foundation internal allocations or make output publication/reservation atomic. Root UTF-8 conversion happens outside the formatting pool; any implementation-specific UTF-8 temporaries and transport storage remain outside these phase pools. Additional push/pop and destructor work can change timing; device RSS/latency/throughput benefit is not measured. Foundation class-cluster storage and ARC return-value optimizations can change the actual gain. C05/P1-60 remain partial.

Exceptions retain Clang's existing pool/unwind behavior. Do not assume an exception-exited pool drains; tests assert final ownership balance after a normally exiting enclosing caller pool. Exceptions are not converted into success or replayed.

## Verification

Freeze complete preceding C05x response/handler regions for root/TrollStore. Reverse only the pool scopes and outside strong result declarations/assignments before requiring complete task/server hashes and the existing C05x/earlier restoration chains. The JSON writer, C05x gates and root UTF-8/notify sequence are unchanged.

Reuse the existing Foundation/CoreFoundation/ARC/ASan/UBSan wire executable and link the existing test-only MRC owner helper. Its void C function explicitly schedules a pending autorelease, avoiding ARC return-value elision or assumptions about Foundation object classes. Observe those witnesses through real JSON/base64/formatting delegation in all four current/frozen routes.

For128 consecutive calls in one caller pool per route, two phase witnesses per call give a current peak of one and zero pending witnesses at each return, versus256 pending witnesses before the preceding caller pool drains. These are controlled sentinel counts, not measured Foundation allocation/RSS counts. Compare128 complete decoded Unicode/nested graphs per route against C05x and retain the final response/decoded graph after caller pool exit.

At either phase drain, controlled owner destruction cancels the captured caller or consumes parent output. Current gates refuse the late success, including skipping final construction after an encoder-phase refusal; preceding codecs publish before their witnesses drain. Check sticky reasons, weak budget retirement and zero final owners. Cover NS/C++ phase faults with balance after normal enclosing drain. All prior graph/boundary/nil/stop/output/fault regressions remain. No real UI/private/tap/transport effects are performed.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete frozen identities/task/server/AX restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Existing portable suites pass. New Apple/iOS compilation and Foundation/ARC/ASan/UBSan execution require macOS CI; device memory/performance qualification remains pending.
