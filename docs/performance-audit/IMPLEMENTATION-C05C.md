# C05c — AX attribute deadline gates and returned-value ownership

Date: 2026-11-05 (Asia/Bangkok). Baseline: `a5e639b7`; user reported C05b build passed and requested continued implementation. Shared rootfull/roothide and production TrollStore AX backend; TouchPOC excluded. Continues P2-22 and the cooperative cancellation part of P1-59/C05.

## Check each snapshot attribute

C05b checked the local window around each serialized node, but a node could still execute all six attribute queries after its local time was consumed. The serializer set the node messaging timeout only once, using the caller's budget rather than the shrinking local snapshot window.

Pass the existing snapshot window by borrowed pointer into the serializer/attribute helper. Before each snapshot attribute, compute min(100ms, caller remainder, local snapshot remainder), apply it through the existing optional timeout setter and recheck stop/deadline after that setup call. Skip the query when no time remains. After the query, reject a returned value if the local/caller stop is observed; subsequent helpers cannot issue more RPCs after they observe expiry. Recheck before building the row. No new window is created per attribute and the caller's deadline is not extended or changed.

Also close the root-query setup gap: after its timeout setter returns, recheck the existing local/caller gates before invoking the root query, releasing the root through the existing error path on expiry. C05b's partial/truncated snapshot policy, late-row discard, action-completeness refusal and cancellation envelopes remain in place.

The serializer's default three-argument path still sets its original timeout once. Hit-test continues to use that path without a local snapshot window; its root hit RPC and deadline behavior are not changed here. Ordinary string/number normalization, attribute order, numeric traits, geometry/activation fallback and row fields retain their preceding source.

## CF value cleanup

Wrap each attribute's owned out-value in an @try/@finally scope. Transfer a successful value to ARC and clear the raw slot; every other return or NS/C++ unwind releases a populated slot exactly once. This covers AX errors, late values and a provider that fills the out-value before throwing. The cleanup also applies to the default path. Successful aliases, errorOut values, NS serializer catch behavior and C++ exception propagation remain unchanged.

This is cooperative admission/late-result cleanup, not RPC preemption. A missing/ignored timeout setter, an opaque loader/decoder/AX call or scheduling between a check and the call can still overshoot. The applied timeout reflects the observation before setup; it is not continually renewed. Queue/preflight, root materialization, scanned work, selector/output/string limits, hit-test root timing and device qualification remain open. C05/P1-59/P2-22 stay partial; no measured device improvement is claimed.

## Verification

Freeze the complete preceding attribute/string/role/serializer block. Exact reversal permits only the optional local window, per-attribute gates, owner scope and final row gate, plus the snapshot window argument/root setup recheck. Verify the complete preceding C05b AX hash, then the existing C05b/C05a restoration chain. Extend the existing snapshot safety runner; both workflows already invoke it and the runner count stays 90.

The new macOS Foundation/CF/CoreGraphics/ARC/ASan/UBSan fixture compiles complete current/frozen helpers and snapshot loops with the actual error/normalizer/action-completeness helpers. Controlled AX providers return owned CF references and tracked frame/point owners; CoreGraphics geometry and Foundation rows/arrays are real. It compares 240 ordinary row/key-order cases across frozen/default/local serializers, including missing/error attributes and activation fallback, while preserving the default path's one timeout setup versus per-attribute setups for snapshots.

A controlled 30ms-per-query case expects four queries/120ms rather than six/180ms under a 100ms local window, with the same incomplete-action refusal. Other cases cover parent remainder without renewal, expiry during timeout setup/decoding/query, missing setter, cancellation at each attribute, direct errorOut, root setup expiry, NS/C++ exceptions after frame/point out-value publication on both paths and 128 partial snapshot/pool lifecycles. No real private AX call, UIKit, foreground query or tap is performed. These counts and ownership assertions are native CI expectations, not device measurements.

Windows validation: all **90 workflow runners** (36 source, 54 safety), **521 existing source checks**, complete staged AX hashes, extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Existing portable 100k window cases pass; sixteen artifact-only checks skipped. New Foundation/CF/ARC/sanitizer execution and iOS compilation require macOS CI; real timeout/AX/device qualification remains pending.
