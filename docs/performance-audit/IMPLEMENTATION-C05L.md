# C05l — Retire snapshot acquisition CF owners through finally

Date: 2026-11-05 (Asia/Bangkok). Baseline: `f8e1fea6`; user reported C05k build passed and requested continued implementation. Shared rootfull/roothide and production TrollStore AX snapshot acquisition; TouchPOC excluded. Continues C05 ownership work.

## Root and out-array ownership

The snapshot acquisition region previously cleaned up root/rawElements in its NS catch and explicit error branches. A C++ exception from timeout setup or after the query assigned its retained out-array could bypass those releases. This is an exceptional provider/unwind path, not evidence of a steady-state leak in the ordinary audited path.

Give the remaining raw root/payload references one finally boundary. Keep prompt normal root releases and their null assignments. For rejected payloads, leave the raw slot owned until finally instead of releasing it in an individual error branch. Preserve the existing NS-to-ui_ax_exception mapping; C++ faults still propagate after cleanup.

Declare the strong elements array before acquisition. After successful type/error validation, transfer rawElements to ARC inside the protected region and immediately clear its raw slot. Finally then leaves that array alone; the same strong owner supports the unchanged traversal and is released normally or on subsequent node unwind. No additional array copy or materialization is introduced.

The exact query/timeout/caller/local-window sequence, scan/filter/output accounting, counts/metadata, selector, capability, foreground and Task action/authority source retain their preceding text. Existing early-timeout root release/null operations remain valid and cannot be repeated by finally. This changes cleanup scope, not deadline or error priority. Full root materialization, retained source size, selector fusion, string/output memory, queue/admission and opaque preemption remain open. C05 remains partial; no ordinary latency/RSS/device gain is claimed.

## Verification

Freeze the complete preceding snapshot helper. Reverse only the protected ARC transfer and raw-owner finally changes, validate the complete C05k AX hash, then continue the existing C05k/j/i/h/g/f/e/d/c/b/a restoration chain. Reuse the existing snapshot runner/workflows; runner count remains90.

Extend its complete current/frozen Foundation/CF/CoreGraphics/ARC/ASan/UBSan snapshot executable with the exact C05k helper. AX/serializer/clock providers are controlled; CF ownership and mutable array lifetimes are real. Existing fixtures default to the preceding behavior. New counters record retained out-payloads and raw releases; successful ARC transfer is checked through array lifetime rather than expecting a manual raw release.

Native expectations cover256 full dictionary/sorted-JSON/count/query/release comparisons, including normal/empty/filtered/invalid-node output, query errors, wrong-type/missing payload, root/prepare/lock failures and unchanged timing. Four acquisition fault sites cover create before ownership, root timeout setup, query before out assignment and query after retained out assignment. NS outputs/releases compare against the complete preceding helper. C++ fault cases execute only the corrected path and must propagate with root/raw payload already retired; no old intentional leak is executed as an oracle.

Also verify recovery, NS/C++ node exceptions after successful ARC transfer, and128 alternating after-out failure lifecycles. Raw CF balance is asserted immediately with diagnostics; weak array destruction is asserted only after the normally exiting outer pool, respecting exception-exited inner pools. Existing attribute/hit-test/scan/node-pool/selector cases remain enabled. This does not reclaim allocations retained solely inside a throwing provider before it returns or assigns them to the caller.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete staged AX/header restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Existing portable100k window cases pass. Extended Apple/iOS compilation and Foundation/ARC/sanitizer execution require macOS CI. No real AX/UIKit/foreground/tap effect occurs; device qualification remains pending.
