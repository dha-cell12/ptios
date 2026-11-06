# C05t — Bound the UI JSON writer's accepted bytes

Date: 2026-11-06 (Asia/Bangkok). Baseline: `a4e6ba0a`; user reported C05s build passed and requested continued implementation. Rootfull/roothide and production TrollStore ordinary UI result/capability codecs; TouchPOC excluded. Continues C05/P1-60.

## Bounded synchronous writer

Replace the four explicit `dataWithJSONObject` calls with a shared synchronous `NSJSONSerialization writeJSONObject:toStream:options:error:` helper using options 0. Its internal NSOutputStream subclass checks a C++11 quota before appending each complete chunk to its NSMutableData buffer. Accepted bytes never exceed 786,426, the maximum JSON length compatible with the C05s success-wire ceiling. A refused chunk is not appended, refusal is terminal, and no partial prefix is returned as a success. Task 77 adds `hard_max_json_bytes=786426`.

The stream is opened before serialization and closed in finally, including NS/C++ unwind. A positive writer count, no error, open status, buffer length and accepted-byte count must agree before the helper copies an immutable NSData result. A normal inner autorelease-pool drain retires temporary stream/prefix ownership before returning; the retained result survives that pool. Exception-exited pools retain Clang's normal outer-drain semantics. No legacy unbounded serialization fallback is attempted.

This follows Apple's documented [JSON stream writer](https://developer.apple.com/documentation/foundation/jsonserialization/writejsonobject(_:to:options:error:)?language=objc) and [NSOutputStream subclass contract](https://developer.apple.com/documentation/foundation/outputstream). The helper supplies synchronous write/space/status/error/open/close behavior; it schedules no asynchronous work.

On quota refusal, codecs select the existing `ui_response_too_large` before base64. Other nil/zero/error/coherence failures retain each route's existing JSON-failed code. Thrown exceptions continue to propagate after close. Keep C05s final exact wire admission and native output-limit handling; request parsing, query/admission/deadline/foreground/authority/tap order and failed-operation error lines remain unchanged. Output failure does not roll back or replay committed effects.

Use the same options and decoded graphs/base64/framing; dictionary member order remains Foundation-defined. Bounded early rejection can take precedence over an invalid graph condition encountered later during serialization. Foundation's invalid-graph diagnostics are not promoted to a new compatibility guarantee.

## Scope and tradeoff

The bound covers the application buffer's logical accepted bytes and the successful returned JSON NSData. NSMutableData capacity/allocator overhead, Foundation's internal encoder temporaries, initial object graphs/provider/root text and legacy error lines are not a whole-process memory bound. Returning an immutable copy can overlap the stream buffer with one bounded result, and stream/pool operations add overhead for small replies. No universal heap/RSS/latency improvement is claimed. C05/P1-60 remain partial; device profiling and serializer-internal allocation qualification remain open.

Link the new Objective-C++ helper into pccontrol and streamd. The daemon's direct shared-core capability uses only the quota constant and needs no stream implementation linkage.

## Verification

Freeze all four complete C05s codec/handler regions. Reverse only the serializer/include/explicit size-error additions and require the full preceding root-task/TrollStore-server hashes before the existing restoration chains. Reverse the additive AX capability field/include and require the complete C05s AX hash. Update build-source checks, header/docs and contract fixture; runner count remains 90.

Add 100,000 portable chunk/oracle lifecycles for the actual quota, exact 786426/786427 boundary, sticky refusal, independent counters and size_t extremes. Existing wire/output/window/admission tests remain enabled.

Extend the existing Foundation/CoreFoundation/ARC/ASan/UBSan wire executable with the actual stream/helper implementation and real Foundation writer. Compare 128 decoded graphs per route against complete C05s codecs. Check real boundary/oversize JSON, no base64 on refusal, immutable result after input/helper pool drain and 128 actual large-rejection/recovery cycles. Existing C05s native budget/error/fallback/fault and four-route tests remain enabled.

A private writer callback seam exercises exact writes, zero/wrong counts, explicit NSError, premature close, quota failure even with a lying success count, NS/C++ faults and final close. Held/weak stream owners verify retirement after a normal caller pool. Direct primitive tests cover unopened/closed writes, zero-length handling, exact-limit admission, overflow and terminal reopen behavior. No mock class-cluster assumptions or real AX/UI/tap/transport effects.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete source restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Native Apple/iOS compilation and Foundation/ARC/ASan/UBSan execution require macOS CI. Subclass/serializer behavior, memory and throughput still require device qualification.
