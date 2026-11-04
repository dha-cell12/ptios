# C05h — Reuse one task within an AX capability probe

Date: 2026-11-05 (Asia/Bangkok). Baseline: `412688b5`; user reported C05g build passed and requested continued implementation. Shared rootfull/roothide and production TrollStore AX capability diagnostics; TouchPOC excluded. Continues C05/P1-61.

## Per-probe task owner

TLinkAXCapabilitySnapshot previously created and released a SecTask for each of its three entitlement keys. Give the capability loop a local CF task owner and pass its address to the internal entitlement helper. The first successful creation supplies the task for the remaining keys, and the capability finally block releases it before building the result graph. Nothing retains that task between capability calls.

If creation returns null, the next key still tries to create a task. Preserve the preceding per-key false result and later-key recovery rather than turning a transient creation failure into three false results. Library/symbol lookup remains under the existing retryable cache. All entitlement values are copied/read again on every probe; no value, error or negative result is memoized. The optional owner is private to this implementation. Calls without it keep their independent create/read/release lifetime.

The helper now transfers a returned value to ARC and uses finally for task/error/out-value cleanup. A shared task belongs to the capability finally block; a one-off task belongs to the helper finally block. A provider that populates CFError and then throws no longer leaves that task/error unreleased. NS/C++ exceptions still propagate; a failure during BOOL normalization also releases the capability's task. Keep the existing rule that a returned value is normalized even when the provider also reports an error.

Preserve all three names/order, BOOL conversion, capability schema/fields, live prepare/lock/foreground calls, flags and foreground/PID/action/authority behavior. The complete code outside this helper and the loop ownership is checked against C05g. This is diagnostic allocation reuse within one bounded probe, not process-lifetime entitlement caching or a new authorization decision. The existing VPN diagnostics also uses one SecTask for multiple entitlement reads; that subsystem is unchanged.

Normally this reduces three task creations/releases to one while preserving three value reads. Failure paths can still attempt creation for all three keys. It does not address notification registration, missing-secondary foreground symbol lookups, process/plist fallback, AX root/selector/string-output memory, admission or opaque RPC preemption. C05/P1-61 remain partial; device performance is unqualified.

## Verification

Freeze the complete preceding helper and capability function. Reverse only the optional owner/forwarding and finally changes, validate the complete C05g AX hash, then run the existing C05g/f/e/d/c/b/a restoration chain. Reuse the existing symbol safety runner and both workflows; runner count remains 90. Existing symbol-cache portable and one-off Foundation cases remain enabled.

Add a complete current/frozen helper/capability Foundation/CF/ARC/ASan/UBSan executable to that runner. Security loader/providers, live prepare/lock/foreground state and failures are controlled. Fake tasks are real uniquely numbered CFData owners, errors are real CFError objects, and capability dictionaries/JSON/BOOL conversion are real Foundation. Track task identity, release and error balance without redefining the SDK's SecTaskRef or assuming concrete Foundation classes.

Native expectations cover 512 full dictionary/sorted-JSON comparisons across fields, value types/errors, unavailable symbols/library and zero/one/two/three creation failures. Successful reads share one task identity in the current loop and use distinct identities in the preceding loop. Ten thousand ordinary probes expect 10k current versus30k preceding task creations/releases with unchanged30k value reads and fresh results. Verify transient creation recovery within and across probes, missing-symbol recovery and unchanged one-off ownership.

Current-only fault cases cover NS/C++ creation, each of three copy positions after assigning an error, BOOL normalization, one-off reads and symbol lookup. Every catch must observe retired raw CF owners, followed by recovery; no old exception leak is executed as an oracle. Eight threads run8k probes/24k reads with independent local owners and balanced releases. A custom value must die after normal input-pool exit while the boxed result survives, and128 repeated probes must leave zero live task/error owners. These are controlled native expectations, not device allocation/time measurements; no real Security/AX/foreground/service effect occurs.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete staged source/header restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. The new Apple/iOS compilation and Foundation/ARC/sanitizer execution require macOS CI. Device qualification remains pending.
