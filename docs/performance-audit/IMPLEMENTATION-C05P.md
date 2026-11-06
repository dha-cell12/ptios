# C05p — Stop snapshot preflight when its caller expires

Date: 2026-11-05 (Asia/Bangkok). Baseline: `f904d07b`; user reported C05o build passed and requested continued implementation. Shared rootfull/roothide and production TrollStore AX snapshot/find backend; TouchPOC excluded. Continues C05/P1-59/P2-22.

## Caller gates

Check the existing caller stop before lock state, after lock state, after AX preparation and before root creation. A caller cancelled or expired during preflight no longer proceeds through the remaining stages into root acquisition. Keep internal invalid-PID validation first. An observed stop after lock/preparation returns the existing early cancellation envelope before reporting a stale lock/unavailable error; public snapshot/find already canonicalize stopped results on return.

After root query, retain the existing query-error/missing-value/type checks first. If a valid array arrives after caller stop, return the existing partial cancellation error before ARC transfer/screen work; the acquisition finally releases the raw out-array exactly once. Also check after screen bounds before allocating rows. Successful ARC transfer and all remaining root/CF cleanup stay unchanged, including NS/C++ unwind and ordinary query-error precedence.

These are caller gates. The existing local snapshot window still begins after preflight/options normalization and consumes root/query/screen/scan work as before. Local-only expiry still returns read-only partial/truncated data with action refusal. No deadline renewal, local preflight timeout, opaque-call preemption, transport cancellation, retry, slot-count or schema/field/authority/foreground/action change. String/output bounds, full root materialization and whole-operation/device qualification remain open. C05/P1-59/P2-22 remain partial.

## Verification

Freeze the complete preceding snapshot helper. Reverse only these six gates and the preparation-result split, validate the full preceding C05o AX hash and continue all existing staged restorations. Reuse the existing snapshot runner/workflows; runner count remains90.

Extend the Foundation/CF/CoreGraphics/ARC/ASan/UBSan snapshot fixture with controlled lock/prepare/screen costs, explicit stop stages, an optional non-extending parent end time and a method-based option normalization seam. Existing parent tests retain their original behavior when no end is configured. These are controlled providers, not Foundation number subclasses or real AX timing measurements.

Compare128 complete current/C05o graphs, sorted JSON and provider/owner/work counts. Exercise six explicit/parent-deadline stop stages with empty and nonempty arrays: initial entry, lock, prepare, option normalization, query and screen. Require skipped downstream lock/prepare/options/root/screen calls, cancellation-envelope parity and balanced root owners. A stopped valid query releases its raw out-array in finally instead of transferring it to ARC. Weak array destruction is checked after a normally draining caller pool.

Retain invalid-PID and query-error/type/missing-value priority, check stop versus lock/prepare failures, local-only late-empty partial/action refusal, NS/C++ after-out-value faults and128 stopped-query/recovery lifecycles. Existing acquisition/attribute/hit/admission/pool tests remain enabled. No real private AX/UIKit/foreground/tap operation occurs.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete staged AX/header restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Existing portable window/admission cases pass. Extended Apple/iOS compilation and Foundation/ARC/sanitizer execution require macOS CI; provider/work counts do not qualify device latency or memory gains.
