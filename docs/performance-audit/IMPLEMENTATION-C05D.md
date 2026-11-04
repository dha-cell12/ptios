# C05d — Independent AX scanned-node limit

Date: 2026-11-05 (Asia/Bangkok). Baseline: `1a9d6145`; user reported the preceding build passed, including C05c and the VPN fixture corrections. Shared rootfull/roothide and production TrollStore AX backend; TouchPOC excluded. Addresses the scanned-work part of P0-20/C05.

## Bound attempts independently of returned rows

Snapshot max_elements still limits rows surviving visibility/clickability/serialization filtering. It did not limit the number of attempted node serializations, so a mostly filtered tree could visit its entire source list within the time window. Add max_scanned_elements / maxScannedElements with a default of 4,096, minimum one and hard maximum 16,384. These are explicit safety limits, not device-tuned performance targets. Reuse the existing integerValue/default/clamp policy and snake-case precedence.

Check scanned admission before starting another node. Each attempted node counts once, including failed serialization and filtered nodes. The first bound reached among returned rows, attempted nodes, local time and caller stop ends traversal. Keep the previous scanned_count, source_count, row count, failure count and partial/truncated fields; no new snapshot schema is introduced. If source nodes remain when the scan limit is reached, the result is incomplete. Fully consuming a source exactly equal to the limit can remain complete.

Forward the option through the actual find/tap selector entry and publish default_max_scanned_elements/hard_max_scanned_elements as additive Task-77 capability fields. Direct snapshot options and find/tap/Smart Wait selector objects support both aliases. Smart Wait's separate options object is unchanged. Update the UI Tree v1 manifest, source checks and user-facing limits/example.

For example, a 20,000-node all-hidden source previously could return complete absence after 20,000 attempts; the new default stops at 4,096 and reports partial/truncated absence. Read-only callers can inspect the partial result, Task 81 retains its existing incomplete-result refusal, and wait-gone remains inconclusive. Dense filtered trees may now return fewer rows than requested; callers can explicitly raise the scan limit within its hard ceiling.

## Preserved behavior and remaining work

Keep row max/defaults, numeric serializer/attribute order, CF cleanup, parent/local deadlines, cancellation priority, match_count/index semantics and foreground/action/authority guards. Ordinary sources below the new bound retain their preceding replies. There is no added worker, retry, cache, private API or deadline renewal.

The root AX array still materializes the full source before traversal and remains owned during the operation. This does not cap that array or arbitrary attribute string sizes/process RSS, preempt opaque AX calls, combine selector matching into traversal or remove the matches array. P0-20/C05 remain partial; root allocation, per-string/output limits, selector optimization and device qualification stay open.

## Verification

Freeze the entire preceding C05c snapshot function. Exact reversal permits only scan option normalization/admission plus the constants, capability keys and selector forwarding; validate the complete preceding AX hash before the C05c/C05b/C05a chain. Existing snapshot runner wiring is reused; workflow runner count stays 90.

Extend the native Foundation/CF/CoreGraphics/ARC/ASan/UBSan fixture with complete current/preceding snapshot loops and the actual text matcher/find formatter/public selector entry. Dispatch/AX/serializer/screen/clock providers are controlled; arrays, output graphs and CF ownership are real. Cases cover default/hard/minimum/fraction/string/NSNull policy, both aliases/precedence, all-hidden/unclickable/invalid nodes, exact source exhaustion, returned-row independence, 20k old versus 4,096 new attempts, selector propagation, incomplete found/absent results and cancellation at the scan boundary. Existing ordinary reply/deadline/attribute/CF cases remain. No real UI lookup, private AX call or tap is performed; native counts are CI expectations, not device measurements.

Windows validation: all **90 workflow runners** (36 source, 54 safety), **521 existing source checks**, complete staged AX hashes, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Existing portable 100k window cases pass; sixteen artifact-only checks skipped. New native Apple/iOS compilation and Foundation/sanitizer execution require macOS CI. Real AX/framework/device qualification remains pending.
