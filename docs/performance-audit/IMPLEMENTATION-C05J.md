# C05j — Carry the caller budget through AX hit-test and retire CF owners on unwind

Date: 2026-11-05 (Asia/Bangkok). Baseline: `89299859`; user reported C05i build passed and requested continued implementation. Shared rootfull/roothide and production TrollStore AX hit-test helper; TouchPOC excluded. Continues C05/P1-59/P2-22.

## Hit-test lifetime and caller deadline

TLinkAXElementAtPoint previously set the root messaging timeout to500ms regardless of the caller's remaining native budget. It also released root/hit on normal and NS-error branches, while a C++ exception after acquiring either raw owner could bypass those releases.

Keep invalid PID/nonfinite-point validation first. Refuse already-stopped work before dispatch; check the caller again after lock/prepare, screen validation, root creation, timeout setup, hit-test/root release, serialization/hit release and return from dispatch. A stopped caller receives ui_cancelled_or_timed_out with the existing error envelope and PID. This also covers work skipped by the existing native dispatch wrapper after queue residence, and refuses late success. A stopped request can supersede an error obtained after work began.

The root timeout becomes min(500ms, caller remainder), sampled after root creation. Creation/setup consume the same caller deadline; it is never renewed. Check again after the setter before starting hit-test. A missing setter still follows the same caller gates. Serialization retains the preceding actual attribute/geometry behavior and its existing parent checks; the final hit-test check prevents a late serialized row from becoming a success.

Place remaining raw root/hit ownership in finally. Keep prompt normal releases and clear their slots before proceeding. An error with an owned hit now retires that hit in finally; NS errors retain their existing ui_ax_exception mapping, and C++ exceptions still propagate after raw CF cleanup. A serializer NS fault retains its existing nil-element/found=false behavior unless the caller stopped. Existing attribute out-value finally cleanup remains enabled.

With no caller budget, the original per-RPC500ms root and100ms serializer limits remain. This does not add an implicit500ms total hit-test deadline, preempt opaque AX/setup/decoder calls, interrupt dispatch_sync while another owner runs, add admission/coalescing or change foreground validation. No schema, public option, successful field, ordinary invalid/lock/availability/error result, coordinate interpretation or Task action/authority policy changes. C05/P1-59/P2-22 remain partial; device timing is unqualified.

## Verification

Freeze the complete preceding hit-test helper. Reverse only the caller gates, root timeout and finally ownership, then validate the complete C05i AX hash and continue the existing C05i/h/g/f/e/d/c/b/a restoration chain. Reuse the snapshot safety runner/workflows; runner count remains90.

Extend its existing attribute Foundation/CF/CoreGraphics/ARC/ASan/UBSan executable with the complete current/frozen public hit-test helpers and the actual current attribute/serializer. AX, screen, dispatch admission and parent clock are controlled; CF references, value objects and CG geometry are real. Shared fixture changes default to the preceding behavior, retaining all existing240 serializer parity and snapshot/cancellation tests.

New native expectations cover128 full dictionary/sorted-JSON/provider-order/owner cases, original invalid PID/nonfinite/out-of-bounds/lock/symbol/root/hit/error/nil-row replies and missing dispatch. A20ms parent with5ms creation must leave15ms for the root timeout; a long parent still clamps to500ms. Eleven controlled expiry locations cover queue, lock/prepare, create/setup, hit return, root/hit cleanup, attribute serialization, screen and post-dispatch. Explicit cancellation and missing-setter cases must skip later work and retire owners without extending the deadline. A standalone slow provider keeps the preceding no-total-window behavior.

NS/C++ faults before create ownership, in root setup, after hit out-value assignment and in the actual attribute provider verify error mapping/propagation, raw root/hit retirement and recovery. Value-object destruction is asserted only after normal enclosing pool exit, preserving Clang's exception-pool semantics. Another128 cycles require retained result labels with balanced owners and zero live value boxes. Raw-owner diagnostics report mismatches. No real AX/UIKit/foreground/tap effect occurs; these are controlled expectations rather than device measurements. Dispatch is modeled here; this does not qualify real queue/IPC behavior or opaque-call cancellation.

Windows validation: all **90 workflow runners** (36 source,54 safety), **521 existing source checks**, complete staged AX/header restoration, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass; sixteen artifact-only checks skipped. Existing portable100k window cases pass. Extended Apple/iOS compilation and Foundation/ARC/sanitizer execution require macOS CI. Device qualification remains pending.
