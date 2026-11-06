# AX JSON ownership fixture lifetime and failure diagnostics

Date: 2026-11-07 (Asia/Bangkok). Baseline: `bf9c4c2e`. User reported a macOS `wire` SIGABRT after the JSON ownership banner. The initial excerpt omitted its assertion. The later full log confirms `storageLifetimeCases`, line40: `weak.expired()&&trace.live==0&&trace.releases==1&&trace.maximum<=MaxJSONBytes`. This is precisely the premature retirement observation corrected here. The log is from the preceding fixture: it uses the old assert/line and lacks the new phase diagnostics. It is not evidence of a failure after this patch.

## Lifetime boundary

The old test read `held.bytes` after its producer pool had drained, cleared held in a separate empty pool, then immediately required the shared buffer owner to expire. Reads returning an interior pointer can legally extend their receiver's lifetime with a retain/autorelease in the pool active at the read. Draining a pool pushed later does not retire autoreleases already pending in an enclosing pool. See [Clang ARC interior-pointer rules](https://clang.llvm.org/docs/AutomaticReferenceCounting.html#interior-pointers).

Put producer, cross-inner-pool byte reads, final reference release and any resulting NSData/block retirement inside a normally drained caller pool. Keep trace/weak counters outside it and make the zero-live/one-free/expired-owner assertions only afterward. Preserve exact byte checks, sealed-stream rejection, all factory fault modes and all resource assertions.

An explicit test-only MRC retain/autorelease of held data models the permitted pool-held receiver lifetime even if a compiler optimizes its own extension away. It is a void C helper linked through the existing owner object, not a change to production ownership or a Foundation class-cluster assumption. Production JSON writer, deallocator, raw allocator and UI handlers are unchanged.

## Diagnostics

Ownership checks now report phase, iteration, factory mode, source line and condition before aborting. Factory retirement failures also report which stream/storage/budget owner remains. Phase progress goes to stderr.

The confirmed storage-retirement site additionally reports expired/live/free/maximum/limit values, so a remaining failure identifies the particular conjunct rather than only the compound condition.

The runner embeds the last12000 stderr characters in its thrown failure, including the signal. This retains the original assertion/ASan message even when CI output only shows the Node failure. A controlled SIGABRT result passed through the actual run formatter verifies both original-assertion retention and tail truncation.

## Validation

Windows: all90 workflow runners and521 source checks, focused AX source/portable checks, JavaScript syntax, expanded diagnostic-macro preprocessing, runner failure-format injection, complete production HEAD identities, unique MRC declaration/definition and diff/UTF8/LF checks pass. Native Foundation/ARC/ASan/UBSan execution is unavailable on Windows and must be confirmed by macOS CI. The full log confirms the failure site; it supplies no individual counter values and does not itself prove the precise retained owner or a native pass after this fix.
