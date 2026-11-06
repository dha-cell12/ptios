# C05aa — Refuse stopped Task 77 before capability/foreground work

Date: 2026-11-07 (Asia/Bangkok). Baseline: `657b9ab8`; user reported C05z build passed and requested continued implementation. Continues C05/P1-59 for rootfull/roothide and production TrollStore Task77. TouchPOC excluded.

## Provider admission

Capture the native caller at Task77 branch entry and consult its existing stop classification before invoking the capability provider. Check it again after capability retrieval/copy. TrollStore also checks after its separate foreground lookup, before duration/metadata/JSON assembly. An already stopped caller therefore skips capability, separate foreground and JSON work. A stop observed after the capability provider prevents TrollStore's following foreground lookup.

Use the existing `ui_cancelled_or_timed_out` wire for cancellation/deadline and `ui_response_too_large` for an already-latched native OutputLimit. No new budget, timer or output reservation is introduced. This preflight classifies existing stop; a small remaining output allowance that has not latched overflow still reaches the existing JSON/wire admission policy. Stop-first classification avoids poisoning an already-cancelled tiny-budget caller with a new output-limit reason.

The captured caller cannot be replaced by a nested TLS scope entered during a provider. Later JSON/final-wire gates remain in place. Direct cleanup budgets keep their existing deadline/cancellation exemption; ordinary children retain their existing inherited deadline behavior. Unbound/live callers still read fresh capability/foreground values, with the same Task77 schema, diagnostics, metadata, JSON/framing, license policy and provider order. No value/token cache is added.

The direct shared capability API and all non-Task77 task/response/query/action/foreground safety source remain unchanged. A reached provider's NS/C++ exception still propagates, even if it also stops the caller. A pre-stopped entry no longer invokes that provider or its faults. Provider work already entered remains opaque; preflight does not interrupt it or roll back initialization/effects.

## Limits and cost

This avoids known-stopped work at handler boundaries. It neither supplies missing caller bindings nor bounds an accepted private probe/foreground crossing, makes stop/publication atomic, removes a live foreground verification, memoizes mutable state or changes diagnostic authority. Normal calls incur two root or three TrollStore stop classifications; no measured device latency/throughput/RSS gain is claimed. C05/P1-59 and provider/device qualification remain partial.

## Verification

Freeze both complete preceding C05z task handlers. Require only the moved caller capture and Task77 preflight/post-provider gates before full task/server hashes and all earlier AX/codec restoration chains. Result codecs, shared AX runtime, JSON writer/buffer/gates and SocketResponder remain unchanged. Reuse the same90 workflow runners and existing Foundation/CoreFoundation/ARC/ASan/UBSan wire executable.

Native actual/C05z handler expectations use counted capability/foreground provider seams, real native budgets and real JSON/base64/formatting. Already cancelled, expired or overflowed entries require zero current provider/JSON calls versus the preceding one capability/JSON call and TrollStore's additional foreground call. Test cancelled tiny-budget priority, after-capability/after-foreground cancellation/deadline/overflow, captured caller versus a nested live TLS scope, direct cleanup/ordinary-child semantics, reached NS/C++ provider faults and weak-budget retirement. Deadline cases permit safe earlier refusal when a loaded host expires before the hook.

Compare128 complete decoded Unicode/nested capability graphs per runtime against C05z and256 stopped/recovered cycles. Update the existing C05u codec regression's producer-count expectation only for the newly short-circuited current Task77 path; ordinary result/legacy expectations remain. All prior wire/quota/phase-pool/fault/stop/output regressions remain enabled. Private AX/Security/foreground providers and notify are controlled; no real UI/tap/private-service/transport delivery is qualified.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete frozen task/server/AX restoration, unchanged codec/shared-runtime/transport identities, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Existing portable suites pass. New Apple/iOS compilation and Foundation/ARC/ASan/UBSan execution require macOS CI; device performance qualification remains pending.

The initial full Windows run passed89 runners and hit LNK1104 opening the reused temporary TrollStore touch-test executable. A focused rerun of the unchanged touch runner passed both production variants without source changes. The90-run result combines those checks; it is not a claim that the first full run had no failures.
