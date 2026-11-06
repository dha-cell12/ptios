# C05u — Stop JSON work using its captured caller budget

Date: 2026-11-06 (Asia/Bangkok). Baseline: `f93d6bb9`; user reported C05t build passed and requested continued implementation. Shared JSON helper and four rootfull/roothide/production TrollStore UI codecs; TouchPOC excluded. Continues C05/P1-59/P1-60.

## Cooperative stop gates

Capture the current native budget for the stream's lifetime. Refuse an already stopped caller before allocating/opening the stream or invoking the writer. Check the captured budget before quota admission, before/after append, in space availability, after writer return, after immutable copy and after normal helper-pool drain. Never return a JSON prefix or result once stop is observed at these gates. Keep finally close and exception propagation.

Read the captured budget rather than whichever TLS scope happens to be active inside a reentrant writer/input callback. Result NSData does not retain that budget after the stream/helper retires. The old two-argument JSON API remains as a forwarding wrapper; new codecs use the stop-aware API.

Classify the actual native reason: OutputLimit maps to `tooLarge`, while cancellation/deadline maps to `stopped`. Four codecs select `ui_cancelled_or_timed_out` for the latter before JSON-failed handling, and retain `ui_response_too_large` for size/output-limit refusal. Existing native parent/cleanup/overflow precedence is read, not changed. A newly observed caller stop takes precedence over a local quota/JSON error at the post-writer gate; exceptions still propagate after close.

Unbound calls retain C05t behavior. This does not create a missing budget binding, connect TrollStore socket/session cancellation to TLS, or add a disconnect monitor. Opaque Foundation work between callbacks and an in-progress copy cannot be interrupted; stop/publication is not atomic. Query/action/authority/tap order, quota/wire limits, successful graph/framing, budget deadlines and final native output handling remain unchanged. No retry or rollback of committed effects. C05/P1-59/P1-60 remain partial.

Budget references and repeated reason checks add ordinary-path work. No device throughput/RSS gain, preemptive cancellation or whole-operation memory bound is claimed.

## Verification

Freeze the complete C05t JSON implementation and four codec/handler regions. Derive the new writer from explicit stop/binding/wrapper changes and require the full preceding writer hash. Reverse only new codec calls/cancellation branches and require full root-task/TrollStore-server hashes before all existing restoration chains. No new workflow runner; count remains 90.

Add 100,000 portable classifications using real native budgets: cancellation, expired deadline, sticky output limit, parent propagation and cleanup semantics. Verify a regular child can still stop despite its cleanup parent, overflow precedence and captured-budget isolation from nested TLS scopes. Classification does not mutate native budget state.

Extend the Foundation/CoreFoundation/ARC/ASan/UBSan wire executable with complete current/C05t writer classes and codecs. Test pre-stopped writer refusal, cancellation before/between/after writes, local-quota versus caller-stop priority, parent budgets, nested stopped/live TLS scopes, in-flight deadline and NS/C++ unwind with closed streams. The deadline test permits the safe pre-entry refusal if CI scheduling consumes its short window. Controlled callback work exercises gates; normal codecs still delegate to real Foundation.

Compare all four ordinary decoded codec graphs against C05t, and require no base64 on cancellation. Output-limit paths retain the native reason and error classification. Held/weak owners verify budget retirement; 128 real successful results outlive their caller budget, followed by cancelled old-API refusal/recovery. Existing quota/count/coherence/boundary/Unicode/error/close tests remain enabled. No class-cluster assumptions, real UI/private-service/tap/network effects or claims of opaque encoder preemption.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete writer/root/TrollStore/AX restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Apple/iOS compilation and Foundation/ARC/ASan/UBSan execution require macOS CI. End-to-end caller binding, transport cancellation and device memory/latency qualification remain open.
