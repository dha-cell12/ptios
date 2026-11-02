# C06s — synchronized IKEv2 helper completion

Date: 2026-11-02 (Asia/Bangkok). Baseline: `6f415413`; user reported C06r build passed and requested continued implementation. TouchPOC excluded.

## Completion ownership

The shared synchronous IKEv2 configuration wrapper previously read a `__block NSDictionary *` while an asynchronous provider could write it on another thread. Duplicate callbacks could replace the result, and a retained callback could retain a result after the caller had timed out. The production TrollStore root helper invokes this wrapper; the shared manager also compiles for root builds.

Reuse the existing mutex/semaphore completion owner. Its new locked `ready()` query lets the main caller continue driving the run loop without reading an unsynchronized result. Accept the first callback only, close the owner before returning, and discard duplicate or late results. A nil callback is terminal and returns the existing timeout envelope immediately. The scope guard closes the owner on NS/C++ unwind; exception propagation remains unchanged. A provider retaining the callback retains only the closed state after return, with no result retained there.

Preserve the root-UID gate, successful/error result dictionary, executor UID/GID/process decoration and approval-path policy. No credential, provider, profile or authority logic changes. The callback does not add a deep immutable copy of provider-owned mutable data; the existing ownership contract still applies.

## Waiting and deadlines

Start one 30-second continuous-clock window before completion allocation and provider invocation. Setup and synchronous starter time consume it. Check the window while waiting and again under the result mutex before publication, so completion at or after expiry cannot become success. Clock setup failure and completion-source allocation failure return the existing timeout without starting configuration.

On main, retain the default-mode run-loop pump in slices of at most 100 ms. If the mode has no source and returns immediately, wait on the semaphore for a bounded slice instead of spinning. Off main, wait on the semaphore and leave the main run loop to its owner thread. Wall time is used only for the short run-loop API argument; it no longer decides overall result acceptance.

Opaque configuration calls and run-loop calls cannot be preempted. This is a result-acceptance deadline, not a guarantee that every native call returns within 30 seconds. There is no new cancellation, global admission cap, profile rollback or replay. Underlying configuration may still commit after timeout. Device/run-loop/NetworkExtension qualification, remaining private polling/full enumeration, supervisor cancellation and other C06 work remain open.

## Verification

Freeze the complete preceding synchronous function. The restoration guard reverses this change and verifies the entire prior manager hash, then participates in the existing cleanup/verification/transition baseline chain. A separate equality guard preserves the complete timeout/result-decoration suffix. Add the safety runner to both root and production TrollStore workflows.

The portable runner retains the existing 100k broker-window/write policy cases. The new macOS fixture compiles complete current/frozen wrappers and the actual completion class under C++14, ARC and ASan/UBSan. Identity, configuration provider, run-loop adapter and most clock steps are controlled; no real VPN, Keychain or root identity is changed. Cases cover frozen healthy/error/root-denial metadata, nil/duplicate/late callbacks, starter-time consumption, exact deadline, empty-mode fallback, off-main waiting, wall-clock jumps, invalid clock/setup, result lifetime across pools and NS/C++ unwind, 64 rounds of eight concurrent publishers, and a real background caller/semaphore/GCD callback. The run-loop adapter is controlled; real main-loop and NetworkExtension behavior still require device qualification.

Windows validation: all **78 workflow runners** (36 source, 42 safety), **521 existing workflow source checks**, staged source hashes, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Sixteen artifact-only checks skipped. New Apple compilation, native fixture execution and iOS builds require macOS CI; Windows source/portable passes do not substitute for those checks. C06 and P0-22 stay partial.
