# A01 — P0-04 / P1-06

Date: 2026-10-16. Base: `18e6e67c7250e172da02df3e2ea558aa6ffc0242`.
Status: source implemented; native host regression passed; iOS build/device validation pending.

## Scope

Rootfull/roothide (`pccontrol`) and production TrollStore (`stream-app/streamd`). The same ownership/parser defects were also found on the live streamd call path while implementing A01, so both production runtimes use the fix. No files under the prototype `poc-trollstore` tree were changed. Its performance backlog is excluded by user instruction.

## Changes

- Both injectors keep each created child in a local reference, append, then release the caller's Create-rule reference. Parent ownership still ends after dispatch.
- Shared `shared/TLinkTouchPayload.h` parses a bounded payload on the stack, with no Foundation/heap allocation. All records are validated before any HID allocation or active-finger mutation.
- Preserve the existing one-digit count (1–9), finger IDs 0–19 and integer-pixel truncation of the five-digit fixed-point coordinates. Preserve valid down/move/up, unchanged active fingers, and RAW LF/CR/CRLF suffixes.
- Reject short/count-mismatched frames, non-digit fields, unsupported types/finger IDs, embedded NULs inside the supplied touch bytes and non-line-ending suffixes. The explicit length excludes the terminating NUL. Malformed frames are rejected as a whole; the old partial/zero-coordinate interpretation is not preserved.
- Handle parent/child allocation failure without NULL dereferences, leaked temporary ownership or a partial active-finger state commit.
- All production direct callers pass actual byte lengths. Rootfull IPC/JS ingress uses `processTaskWithContext` with a finite length. The legacy task adapter remains for trusted, complete NUL-terminated callers such as RAW playback; it computes strlen rather than forwarding SIZE_MAX.
- Validate the two-byte rootfull task prefix before access. Task61 searches only inside the supplied body, preserves the input buffer, rejects missing/empty ACK sequences or malformed touch data, and no longer returns success for rejected frames. Valid ACK response format is unchanged.
- Native batch rejects its malformed task10 command; earlier commands in a sequential batch are not rolled back. Legacy task10 socket dispatch remains fire-and-forget. Script/ACK paths expose the existing error response format.
- No license enforcement boundary was removed. JS cancellation-context propagation, input truncation policy, scheduler/player lifecycle and high-level gesture validation remain separate backlog work.

## Verification

`node scripts/check-touch-safety.mjs` compiles the actual production construction/append/injection function bodies with C++14 and a retain-counted HID test double, then runs both runtime variants. It does not reimplement the injector. Source contract checks cover the length-aware IPC/JS/task10/task61 routes. Added to rootfull/roothide and StreamControl CI workflows; macOS CI uses AddressSanitizer and UndefinedBehaviorSanitizer.

Host execution on Windows used MSVC 19.29, `/W4 /WX`, and real VirtualAlloc/VirtualProtect guard pages. Results passed for both runtime variants:

- every truncated prefix for counts 1–9, placed immediately before an unreadable page;
- complete valid inputs without a NUL terminator at that page boundary;
- invalid bytes at every record position, count/type/finger errors, extra records and invalid suffixes;
- valid finger 0/19, nine-finger frames, down/move/up, coordinate compatibility and unchanged active-finger replay;
- failures creating the parent, first/later children and an unchanged active child, with state rollback;
- 100,000 move frames per runtime: zero remaining test-double event ownership after every dispatch.

All 29 existing source-contract checks listed in the rootfull build workflow passed (the new native harness is counted separately). The Zoom P0 check now verifies the shared 13-byte record, one-digit count/9-touch and 20-finger constants instead of requiring duplicated parser literals. The separate TrollStore toast check also passed. These are source-contract regressions, not device execution.

Run on Windows from a Visual Studio x64 Developer Command Prompt with `set CXX=cl`, or on macOS with clang++ available. The harness creates and cleans its own OS temporary build directory.

## Remaining target validation

1. Let both CI workflows compile the real iOS artifacts; local Windows has no Xcode/iOS SDK, and this session has not run hosted CI.
2. On representative rootfull/roothide and TrollStore devices, verify private IOHID append retention and down/move/up/zoom behavior. The HID test double models retain-on-append; it cannot establish private-API behavior on a particular iOS version.
3. Run the matching S002 ownership probe with 100k frames and Instruments Allocations/VM Tracker. Check live IOHID object counts/RSS slope, not a promised byte saving. Check finger-up cleanup at the end.
4. Exercise malformed task10/task61/batch requests and valid ACK compatibility on a test screen. Verify rejected frames do not inject partial events and the following valid frame still behaves correctly.

Do not label A01 device-validated until those checks have actual results.
