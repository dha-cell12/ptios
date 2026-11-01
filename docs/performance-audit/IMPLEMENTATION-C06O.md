# C06o — one diagnostics read for refresh failure backoff

Date: 2026-11-02 (Asia/Bangkok). Baseline: `ddfa1bc3`; user reported C06n build passed and requested continued implementation. This checkpoint addresses another bounded part of **P1-77** for the shared rootfull/roothide and production TrollStore license coordinator. TouchPOC excluded.

Failure handling previously read the diagnostics plist to obtain consecutive_failures, computed backoff under the coordinator monitor, then called the diagnostics/history writer which read the same plist again. Move the unchanged calculation into an inline state-mutation callback executed under that writer's existing monitor after its sole read. The existing two-argument diagnostics API forwards with a nil mutation. The callback is synchronous and never retained for later execution.

Keep failure-count/exponent/delay caps, jitter sampling, defaults, trigger/error fields, history order/20-entry limit, mode/updated timestamp, atomic-write API and normal completion/publication behavior. There is still one write transaction per failure; this removes one explicit application plist read. The next-attempt timestamp is now sampled after that transaction's read. Other diagnostic reads, trigger/UI/reload persistence, authority/HTTP/lease/checkpoint storage and signed trust behavior are unchanged.

The monitor only serializes this coordinator instance. Cross-process/other-instance writers, failed-read reset and unchecked directory/write behavior retain their previous policy. This does not introduce a diagnostics cache, durability guarantee, IO deadline, write batching or HTTP cancellation. P1-77/C06 remain partial, and no device performance gain is claimed.

## Verification

A frozen fixture keeps only the prior diagnostics writer/failure method. A staged reversal reconstructs the complete preceding coordinator hash, explicitly preserves every failure-math/jitter/field line, then runs the existing subscriber/C06f guards. Existing complete current/frozen native coordinator fixtures continue to exercise authority, decision/coalescing, errors, history and cancellation.

The native fixture instruments only extracted coordinator plist reads, retaining real Foundation plist IO. New cases compare failure output against the frozen previous coordinator for prior counts -1/0/1/15/16/99, defaults and caps, and assert two reads before versus one after. Thirty-two concurrent failure/history transactions on one coordinator check one read each, the failure cap, twenty unique retained history IDs and unrelated-field preservation. Transaction instrumentation moves to the shared writer entry, keeping the existing three-per-attempt/one-per-skip checks intact. Providers, clocks and jitter are controlled; only private temporary plists are modified.

New Foundation/GCD/ARC/ASan/UBSan assertions require macOS CI compilation/execution and are not measured device IO results. Remaining diagnostics persistence/cross-process/durability and device qualification stay open.

Windows validation passes all **76 workflow runners** (36 source, 40 safety), **521 existing workflow source checks**, staged complete-coordinator/subscriber/C06f hashes, JavaScript syntax, fixture extraction, expanded assert preprocessing and `git diff --check`. Sixteen artifact-only checks are skipped. New native read-count/frozen-output/concurrency assertions were not compiled or executed on this host.
