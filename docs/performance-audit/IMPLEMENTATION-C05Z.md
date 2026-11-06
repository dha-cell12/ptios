# C05z — Scope root UTF-8 conversion and synchronous publication

Date: 2026-11-07 (Asia/Bangkok). Baseline: `79c96a85`; user reported C05y build passed and requested continued implementation. Continues C05/P1-60 for rootfull/roothide UI result/capability success codecs. Production TrollStore retains C05y unchanged; TouchPOC excluded.

## Publication pool

Add one autorelease pool around each root codec's existing UTF-8 conversion, captured stop/output gate and synchronous notify. Conversion and pointer use occur in the same pool. Keep the precise-lifetime response NSString outside that pool; no borrowed pointer escapes it. Normal success or final-gate refusal drains pending autoreleases from conversion/notify before the codec returns.

The existing `pccontrol/SocketResponder.xm` notify implementation consumes the message synchronously: it either appends to a native response sink or loops through CFWriteStreamWrite before returning. This source is unchanged. The new pool neither changes its write policy nor makes it nonblocking/cancellable. Base64/final-format phase pools, exact bytes, nil fallback, error priority, stop/output checks, parent/cleanup semantics, NS/C++ propagation and all task/query/action/foreground/license/tap order remain unchanged.

The final gate is still before notify. Pool destruction after notify has already accepted bytes can stop the caller or consume output, but cannot retract/replace those bytes or trigger replay. This is temporary-lifetime control, not atomic stop/publication, output reservation, rollback or proof of transport delivery. Early JSON/error paths outside the prepared-success publication block are not given a new pool.

## Limits and cost

Conversion/notify temporaries can retire before a long-lived surrounding request pool drains. Actual Foundation UTF-8 backing/cache allocations, ARC optimizations and retained owners determine the benefit; the full JSON/base64/response owners and transport/provider/root/metadata representations remain outside a whole-operation memory bound. Pool duration includes a blocking notify, so this does not bound transport time or memory during the write. One additional pool push/pop/destruction phase adds work. No device RSS/latency/throughput gain is claimed. C05/P1-60 remain partial.

Do not assume exception-exited Clang pools drain. NS/C++ errors retain propagation; native tests check final balance after a normally exiting enclosing caller pool.

## Verification

Freeze the two complete preceding C05y root response/handler regions. Reverse only the UTF-8/check/notify pool and indentation, require the complete preceding root task hash and continue all C05y/earlier restoration chains. Require an unchanged complete TrollStore server and unchanged JSON writer/buffer/gates/SocketResponder/MRC helper sources. Reuse the same90 workflow runners and existing Foundation/CoreFoundation/ARC/ASan/UBSan wire executable.

Extend the explicit test-only MRC witness helper seams to UTF-8/notify. For128 consecutive calls in one caller pool per root route, current expectations peak at two pending witnesses and zero at return, versus256 pending before the preceding caller pool drains. These are controlled sentinel counts, not Foundation allocation or RSS measurements. Compare128 complete Unicode/nested decoded graphs per route against C05y, exact wire bytes/size and held results after pool exit. A notify observer copies real UTF-8 bytes and verifies them again after nested allocation/pool churn, while the borrowed pointer is still in its valid scope.

Cover the existing post-UTF8 cancellation/parent-output refusal, witness retirement on its normal early return, weak budget cleanup and NS/C++ faults at UTF-8/notify with final enclosing-pool balance. Also trigger caller cancellation or parent output consumption at normal publication-pool drain after the observer has accepted a success: require exactly one unchanged success copy and no replay/replacement. Notify remains controlled; no actual CF stream/socket/private/UI/tap effect or end-to-end delivery is qualified.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, frozen identities/full task/server/AX restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Existing portable suites pass. New Apple/iOS compilation and Foundation/ARC/ASan/UBSan execution require macOS CI; device memory/performance qualification remains pending.
