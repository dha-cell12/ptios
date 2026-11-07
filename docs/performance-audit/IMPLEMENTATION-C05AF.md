# C05af — Selector immutability and shared mode preparation

Date: 2026-11-07 (Asia/Bangkok). Baseline: `a923709a`; user reported the corrected build passed and requested larger batches. Shared rootfull/roothide/production TrollStore AX. Advances P0-20/P1-59/P1-60; TouchPOC excluded.

## One matcher package

The preceding CI showed legal Foundation eligibility refusals and compatibility counts. It did not establish why a given concrete class was refused or prove that the optimization is available on every SDK. Keep the existing exact whitelist derived from Foundation-created immutable samples. Unknown/custom classes still return false before any copy probe; no private class name or superclass-wide admission is introduced.

For a known class reporting NSMutableString ancestry, try an instance-level copy-identity witness. Only a successful copy returning the same object qualifies; a different copy, nil or reached NS/C++ failure keeps compatibility. Discard a nonidentical snapshot immediately; never replace a mutable expected value with a frozen copy. The probe catches inside its own normal pool, so reached temporary owners retire on success and handled failure. The previous route for known classes without mutable ancestry remains.

This is an inference under Foundation's copying contract: NSCopying requires a functionally independent value, and permits retaining the original for immutable objects. Combining identity with the exact Foundation-class gate avoids treating an arbitrary custom copy-returning-self object as immutable. It is not a universal mutability detector. See Apple's [NSCopying contract](https://developer.apple.com/documentation/foundation/nscopying). Mutable copies with independent identities remain unqualified; unsupported representations can still refuse the fast path.

Introduce a per-find Mode shared by identifier and text, plus a separate exact Mode for role. Reuse each mode's eligibility and normalized contains/exact/prefix decision. Both classification and decode remain lazy; skipped fields/rows do not prepare a mode. Publish a decision only after its provider returns; thrown classification/decode remains retryable, and a refusal is conservative for that operation only. A new find creates fresh state. No selector, AX result or foreground value is cached across requests.

Text retains its original three-argument constructor with an owned mode. The shared-mode overload borrows a noncopyable Mode; the formatter declares both modes before all Text plans so their lifetimes enclose every use. Sharing never freezes mutable/custom mode contents: an unqualified plan passes the same live value to the complete compatibility matcher. Candidate normalization, label-then-value evaluation, reached stop/fault checks, full match count/index/selected row and result graph remain.

No input ceiling, queue/admission, schema, authority, foreground/completeness/action, snapshot, transport or deadline change. Copy probing may add a bounded public-field copy/pool cost even when it ultimately refuses qualification; the existing public field cap remains 64 KiB. Private/internal callers and opaque Foundation allocations are not a process RSS bound. A handled copy-probe failure can keep all fields on compatibility until that find ends; the next operation retries. Existing cold class discovery and its conservative partial result policy remain.

## Verification

Freeze the complete preceding plan header and matcher/public-wrapper region. Undo only the four mode declarations/constructions to reproduce the complete baseline shared AX source, then retain every preceding restoration. Guard the current plan, frozen preceding header, mode core and input policy. The task/server/native budget/dispatch code remains at baseline.

Windows passes all **90 workflow runners** (36 source, 54 safety), **521 source checks** (16 artifact-only skipped), focused AX source/portable tests, JavaScript syntax, expanded assert preprocessing, complete source/header/frozen identities and native extraction/alias checks. The actual portable mode core executes 100,000 eligibility/refusal/contains/exact/prefix/shared plans plus failed-provider retry, lazy decode and no partial publication. An independent sharing oracle confirms five versus six classification calls and three versus five mode comparisons for the controlled all-immutable identifier/role/text matrix.

Extend the existing Foundation/CoreFoundation/CoreGraphics/ARC/ASan/UBSan snapshot executable, with no new runner. Compile actual current plans/formatter plus the frozen unshared formatter using the compatible constructor, retaining the older complete compatibility oracle. Native expectations include:

- Controlled same/different/NS/C++ copy outcomes, nil refusal and explicit MRC probe retirement before return, while unknown custom classes never enter the probe.
- Actual mutable-string refusal and existing mutable/custom expected-value mutation tests.
- 1000 complete frozen graphs/count/index/row identities with unchanged 3/4003 folds; mode sharing reduces controlled eligibility calls 6 to 5 and comparisons 5 to 3.
- Actual Foundation eligibility-dependent counts plus the preceding independent forced-fast/compatibility routes; no universal SDK fast-path assumption.
- Shared prefix decode NS/C++ failure/retry and reuse without a second decode.
- Mutable and custom mode freshness, including a mixed route with eligible immutable expected fields and the actual mode classifier, with zero cached mode comparisons on refusal.

**New Apple compilation and native execution require macOS CI.** Native counts above are pending fixture expectations, not Windows/device measurements. Real SDK eligibility, copy cost, allocation/RSS, query latency and sustained CPU remain unqualified. Full AX root/snapshot materialization, opaque RPC/queue/transport and device acceptance remain open. C05/P0-20/P1-59/P1-60 stay partial.
