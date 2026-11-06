# C05s — Admit UI-tree success wire size before base64

Date: 2026-11-06 (Asia/Bangkok). Baseline: `e5ffb1e0`; user reported C05r build passed and requested continued implementation. Rootfull/roothide `Task.xm` and production TrollStore `streamd` UI-tree response codecs; TouchPOC excluded. Continues C05/P1-60.

## Success response cap

After successful JSON serialization and before base64, calculate the complete success wire size: `5 + 4 * ceil(jsonBytes / 3)` for `0;;` + unwrapped base64 + CRLF. Check the number of base64 groups before multiplication. Refuse a success response larger than 1,048,576 bytes and, when a native budget is bound, check its remaining output allowance. Both ordinary result and capability Task 77 codecs use this admission on both runtimes. Task 77 adds `hard_max_success_wire_bytes=1048576`.

The largest admitted JSON length is 786,426 bytes, producing 1,048,573 wire bytes. The next JSON byte would produce1,048,577 bytes and is refused before allocating base64/final success wire. An unbound or zero/unlimited caller budget still receives the hard 1-MiB cap; a bound smaller/partially used budget can refuse earlier. The codec selects the existing `ui_response_too_large` error. Native output-budget overflow retains its sticky OutputLimit reason and existing outer transport/error handling; the controlled notify test does not claim error delivery through an exhausted real sink.

Keep JSON failure priority, successful graph/JSON options/base64/framing, legacy failure codes, nil-encoding fallbacks and NS/C++ propagation. Capability state/foreground metadata, task request parsing, authority, queries, action guards and tap order remain unchanged. No retry or side-effect replay. Task 81 effects can already be committed before formatting; output refusal does not roll back a tap. This is a response cap, not a new pre-action permission gate.

Initial Foundation JSON allocation and provider/root/metadata graphs remain unbounded by this check. Failed-operation legacy error lines are outside this success-wire cap. Direct structured core results are also outside this codec layer. Final success copies become bounded; no whole-operation peak-memory/latency or device performance gain is claimed. C05/P1-60 remain partial.

## Verification

Freeze both complete UI result helpers and task handlers. Reverse only four pre-base64 admission sites and the new includes; require full preceding root-task and TrollStore-server hashes. Continue the existing TrollStore helper/authority restoration chain. Reverse the additive AX capability field/include and require the complete preceding C05r AX hash before all prior stages. Public docs/header and contract fixture describe the success-only scope.

Reuse the snapshot runner/workflows, retaining 90 runners. Add 100,000 direct portable plans comparing exact ordinary formulas, base64 remainder/prefix/CRLF, the 786426/786427-byte JSON boundary, size_t extremes and unchanged output size on refusal. Existing snapshot/attribute/hit/admission tests remain enabled.

Add a Foundation/CoreFoundation/ARC/ASan/UBSan executable with actual current/frozen root/TrollStore result helpers and capability blocks, plus the actual TrollStore response formatter. Only JSON/base64 call seams, AX/frontmost providers, wall time and root notify sink are controlled. The ordinary seams delegate to real Foundation. Compare 128 full decoded graphs per route, exact emitted JSON/base64/framing and byte counts, including Unicode/escaped input and unavailable capability output. JSON dictionary key order is not promoted to a new protocol guarantee.

Real boundary-sized JSON demonstrates old encoding of 1,048,577 wire bytes versus zero new base64 calls on refusal. A refusal-only NSObject size probe covers impossible size_t payloads without allocating them; it is not a Foundation data subclass and never reaches encoding. Real native budgets test exact fit, one-byte shortage, unlimited-zero, parent sharing, prior captured bytes and sticky output-limit state. Verify original JSON errors, failure-code fallbacks, nil-base64 replies, NS/C++ serialization/encoding faults, invalid TrollStore result and 128 refusal/recovery cycles. No real UI queries, private services, taps or transport writes occur.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete AX/root/TrollStore source restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. New portable wire plans pass. Apple/iOS compilation and Foundation/ARC/ASan/UBSan execution require macOS CI. Final transport/device timing and memory qualification remain pending.
