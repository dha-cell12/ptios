# C03ba — Shared bounded console producer for root and helper

Date: 2026-11-09 (Asia/Bangkok). Baseline: `5915bc37`; user reported C03az built successfully and requested larger packages. Scope: P1-42/P1-50 in the production root/roothide runtime core and JavaScript helper. TouchPOC is excluded; production TrollStore's separate log path is unchanged.

## Work removed before native submission

Both console preludes previously used Array.prototype.map plus join for every call. Native logging retained only4096 UTF16 units, but JavaScript still retained an array of every converted argument and built the complete joined string before crossing that boundary. A full native queue also learned about a refused call only after this work.

Replace both copies with one private shared prelude. The normal serializer path keeps an assembled prefix of at most4097 UTF16 units and does not create an argument-result array or join the complete output. The extra unit is deliberate: the unchanged native4096-unit boundary needs lookahead to avoid splitting a surrogate pair and to recognize truncation. Native output limits, byte encoding, queue permits, files, rotation and terminal drain remain final and unchanged.

Keep ordinary defaults, spaces, JSON/string conversion, empty/undefined/null fields, Unicode/NUL/CR, four levels and undefined console return values. For admitted calls, convert every argument in order even after the output prefix is full. Late toJSON/toString effects and exceptions still occur; truncation is not permission to skip those effects. When an overridden JSON.stringify returns a non-string/non-null value, use a compatibility suffix array/join so coercion still follows all remaining argument conversions as before. This exceptional path can retain/build a complete suffix.

Empty calls and one string of at most4097 units submit directly to the existing native callback, with one native crossing and no admission-query crossing. More expensive object/multi-argument/large-string calls query a new private advisory gate before formatting. Root checks its accepting state and existing64-record budget; helper checks owner closure, its run budget and the C03az process-wide budget. Full queues account one per-run drop and skip formatting. Closed/expired helper owners account their existing drop; root preserves its existing closed-owner refusal policy. Missing helper asynchronous ownership keeps the bounded synchronous fallback.

Preflight reserves nothing and can race. A positive answer does not promise delivery: the original submit still acquires permits and checks closure/generation. Direct calls to the private raw log hook still use that same native gate. An absent advisory hook uses the bounded formatter and original callback, supporting the fallback fixture/embedding path.

## Compatibility and limits

Argument expressions execute before console is called. On a full/closed owner, the expensive path now skips toJSON/toString conversion entirely; this intentional best-effort logging policy is observable if those conversions have side effects. Admitted conversions retain their preceding behavior, including throwing suffixes and exotic serializer coercion order. Console no longer depends on Array.prototype.map or join in the normal path and captures its slice implementation when installed; deliberate later replacements of those intrinsics are not a console customization contract.

The4097-unit limit describes the normal assembled transfer string, not total JavaScript allocation or RSS. JSON.stringify can still traverse/serialize one arbitrarily large or expensive object; every admitted argument conversion still runs, and VM ropes/backing storage/GC are opaque. Exotic overridden serializers retain the compatibility suffix fallback. An advisory query adds a native crossing on the expensive path; short-string/empty calls avoid it. CPU/allocation/latency gains on real devices remain unmeasured.

No public runtimeInfo/status schema, helper transport, task/license authority, module loader, file backend, structured summary/error fields, cancellation or terminal lifecycle changes. The new header is inline/private and adds no framework, implementation target or link dependency.

## Evidence

Freeze the exact two preceding preludes and reverse the complete root core, helper server and helper async owner to baseline hashes before prior guards run. Native fixtures extract the actual gate methods and installed JavaScriptCore blocks; no production backend is replaced by a permissive gate.

Node executes the actual decoded shared prelude against both frozen sources:10000 ordinary four-level scalar/object/Unicode/NUL/date/cyclic/BigInt/fallback comparisons;4095/4096/4097 boundaries and surrogate lookahead; an8-MiB joined workload reduced to4097 transferred units; admitted suffix conversion/throw behavior; custom serializer coercion ordering;1000 preflight refusals with zero conversions; recovery, absent gate and empty/short-string fast paths. Counts are controlled semantic/operation observations, not device memory measurements.

Add macOS JavaScriptCore/Foundation/ARC/ASan/UBSan coverage for the actual root/helper advisory blocks, real root permits and helper queue/files,1000 refusals per frontend without formatting, global helper saturation from another owner, Unicode lookahead, recovery, closed/weak owners, synchronous-construction fallback and zero final permits. Native execution requires macOS CI.

Windows validation:90 workflow runner results (36 source/54 safety portable subsets),521 source assertions (16 artifact-only checks skipped), complete predecessor restoration, five-file assertion macro preprocessing, JavaScript syntax and diff whitespace. The new check is a child of the existing console workflow runner, so workflow count remains90. Apple native compilation/execution and device performance remain pending.
