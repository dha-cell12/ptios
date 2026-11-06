# C05x — Recheck captured caller after base64 and final wire construction

Date: 2026-11-06 (Asia/Bangkok). Baseline: `a93a47b9`; user reported C05w build passed and requested continued implementation. Continues C05/P1-59/P1-60 in four rootfull/roothide/production TrollStore UI result/capability codecs. TouchPOC excluded.

## Publication gates

Capture the native caller budget before JSON serialization. Keep the existing JSON stop/quota/failure handling and pre-base64 exact-wire/output gate. After base64 finishes, consult the captured caller again before building the final success representation. Check it once more after the root UTF-8 pointer or TrollStore NSData has been produced, before notify/return. A cancelled/expired caller selects `ui_cancelled_or_timed_out`; native output overflow selects `ui_response_too_large`. An output allowance consumed by another producer is re-evaluated against the original success-wire projection, including parent response bytes.

The shared C++11 gate checks existing stop first, then hard wire size and remaining output, then stop again. It neither reserves nor appends response bytes. Existing sticky OutputLimit, parent, cleanup and zero-as-unlimited native semantics remain. Holding the captured pointer prevents a nested TLS scope from replacing the caller being checked. Root retains its response NSString with `objc_precise_lifetime` until the borrowed UTF-8 pointer has been used by synchronous notify.

Ordinary JSON/base64/framing bytes, nil-base64 fallbacks, JSON/error priority, NS/C++ propagation, public signatures/protocol limits and the rest of each handler remain unchanged. The complete preceding task/server source is restored and hashed. All query/action/license/foreground/tap ordering stays outside the changed codec regions. A committed action is not rolled back or replayed when delivery is refused.

## Limits and cost

This prevents an observed late success and can skip final formatting after an encoder-time stop. It does not interrupt Foundation base64/formatting, create missing socket/session budget bindings, make stop/publication or output reservation atomic, cancel a transport write already accepted, bound legacy error lines or prove delivery. A stop or competing output producer can still arrive after the last check. Device/end-to-end cancellation and memory/performance qualification remain open. Two additional budget checks/mutex acquisitions and captured ownership add ordinary-path work; no measured latency/RSS/throughput gain is claimed. C05/P1-59/P1-60 remain partial.

## Verification

Freeze both complete C05w response and handler regions for root/TrollStore. Reverse only capture, the two success-stage gates and the root precise-lifetime response variable before the existing C05w task/server and AX restoration chains. The JSON writer and buffer sources are unchanged. Reuse the same90 workflow runners.

Portable100k cases use actual native budgets: exact admission, parent/prefix accounting, cancellation or output consumed after earlier admission, sticky overflow/no reservation, expired/cleanup/unlimited callers, captured-pointer isolation from nested TLS, hard-size extremes and exact error wires.

Extend the existing Foundation/CoreFoundation/ARC/ASan/UBSan wire executable with complete actual/C05w codec comparisons. Use real JSON/base64/formatting and inject effects after encoding or after final UTF-8/NSData creation. Cover cancellation, real deadline expiry, parent output consumption, overflow/cancellation priority, captured caller versus live/stopped nested TLS, NS/C++ faults, weak-budget retirement and128 cancelled/successful recovery cycles across all four routes. Require skipped final construction for encoder-time rejection and no current success publication after either observed stop. Deadline tests permit safe refusal before an effect hook on a loaded host. Existing ordinary Unicode/full-graph/boundary/nil/fault regressions remain. Notify is a controlled observer; no real CF stream/socket/UI/tap effects or transport delivery are qualified.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, frozen source identities/restoration, native fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Apple/iOS compilation and Foundation/ARC/ASan/UBSan execution require macOS CI.
