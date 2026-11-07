# C03ai — Complete storage operation and JSON preparation lifetime package

Date: 2026-11-07 (Asia/Bangkok). Baseline: `71a486da`; user reported C03ah build passed and requested larger batches. Scope: four Text/JSON operations across the rootfull/roothide in-process bridge, helper server and production TrollStore, plus the shared UTF8 view helper. TouchPOC excluded. P1-47 remains partial.

## Delivered together

- Scope root readText/writeText preparation, metadata, encoding and file-provider temporaries to normal operation pools. Returned response graphs retain their text/path/error values.
- Scope the root readJSON parse phase after its readText child returns. Keep the child call and its caller-provided NSError out parameter outside the new pool. Preserve the original outer child failure, nested read error and JSON parser error priority.
- Scope root writeJSON validation/encoding/request preparation separately. Retain the ready subrequest outside that phase, drain preparation temporaries, then call the original writeText child with the original context/error pointer. Keep the exact same child method, arguments and error handling; do not place an autoreleasing caller error assignment in the preparation pool.
- Scope all four helper methods. writeJSON additionally retains its ready text across a separate encoding pool, then calls the original writeText method. Preserve storageOpsCount including the existing two increments for JSON delegated through Text, all path/permission/size checks and early returns.
- Scope all four production TrollStore Text/JSON blocks. Keep its existing direct NSData JSON path, pretty-writing flag, different size policy and failure strings. Do not impose root/helper limits on TrollStore or change JSValue conversion order.
- Scope immutable UTF8 snapshot/view preparation inside the shared helper. The NSData deallocator still retains the immutable NSString backing owner after the local pool returns; unavailable direct CF storage still uses the original encoder fallback. No bytes or ownership escape through a temporary UTF8String pointer.

These are normal temporary-lifetime changes. Foundation may already release some objects early under ARC; this does not claim a particular allocation count, eliminated copy or device RSS gain. Returned graphs and retained inputs continue to live as long as their owners require. Exceptions keep their original propagation policy; an exceptional pool exit is not claimed to retire independently. There is no new retry, cancellation, quota, cache, serialization format, path policy or durability choice.

The root/helper JSON NSData-to-NSString-to-writeText path remains for compatibility. Removing that conversion and changing the underlying writer are separate work; this package does not claim to finish P1-47.

## Validation

All **90 workflow runners** (36 source,54 safety) have passing Windows results: the full run found one AX preceding-source guard affected by the new storage scopes; after composing the exact storage reversal, the affected AX runner passed again. **521 source assertions** pass with16 artifact-only checks skipped. Final focused FileHandle/storage extraction, JavaScript syntax,19-file assertion macro preprocessing and git diff --check pass. Apple native branches are skipped on this host.

Freeze all12 complete storage regions and the original UTF8 header from HEAD. The runner restores the complete root/helper/TrollStore files to their exact preceding hashes before applying historical checks. Current regions, rather than restored ones, feed all native tests. Both new/current and frozen route extractions are generated and validated on Windows too. The existing AX and VPN historical restoration chains compose the scoped storage reversal; production AX/VPN code stays unchanged.

Extend the existing storage-json Foundation/CoreFoundation/ARC/ASan/UBSan executable, linking the existing explicit MRC owner fixture. No new workflow runner or executable is added. Native expectations include:

- 252 complete current/frozen comparisons across twelve routes: reply envelopes, real file bytes, path/create/write traces, helper operation counts, NSError domain/code and propagated type errors. Cover Unicode/NUL, empty/invalid UTF16/JSON, BOM, scalar/array/dictionary/null input, path denial/missing resolved path and boundaries around512 KiB. Seed once per call to compare committed and refused effects. Preserve each backend's own contract.
- 32 repeated calls per route/implementation within one caller pool. The preceding implementation accumulates at least32 explicit provider owners; the new scopes leave zero pending owners after each normal return and at most4 controlled owners at peak. Assert root/helper JSON preparation owners have retired before entering the child path provider. These measure fixture witnesses, not Foundation allocations or bytes.
-A parsed result retained after its caller pool drains, the existing borrowed-string owner/fallback/mutable-input/parsed-graph lifetime suite, and additional direct/fallback UTF8 provider retirement with bytes retained after return.
-Original NS/C++ path-provider fault propagation, outer caller-pool cleanup and balanced owners. Existing writeText real IO/fault and root/helper readJSON child/context/NSError comparisons compile the new current regions as well.

The JSON wrapper delegates to actual Foundation serialization/parsing; it only adds controlled entry witnesses. The native JSValue adapter models conversion without accessing a real script context. Existing FileHandle JSCore tests remain; no JS bindings changed in production. **New Apple compilation and native execution require macOS CI.** Blocking IO, opaque Foundation allocations, larger JSON conversion changes and real device memory/latency qualification remain open. One checkpoint covers the complete package.
