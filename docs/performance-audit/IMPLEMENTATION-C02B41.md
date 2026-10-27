# C02b41 — direct clipboard text adapters

Date: 2026-10-28 (Asia/Bangkok). Baseline: `b6f5dae`, containing C02b40; the user reported C02b40 built successfully.
Status: **source implemented; new macOS/Foundation/ARC/sanitizer CI and device qualification pending**.
Finding: **P0-13, keyboard task-24 kinds 6/7**. Other keyboard kinds, other adapters, metadata codecs/copies and performance qualification remain open.

## Result and compatibility

The rootfull/roothide keyboard JS adapter routes kind 6 (read clipboard text) and kind 7 (write clipboard text) through TLinkExecuteNativeClipboardText. Shared TLinkReadClipboardText/TLinkWriteClipboardText primitives preserve the UIPasteboard operations used by the RAW backend. Other keyboard kinds, including clipboard images and appdelegate notifications, retain RAW dispatch. The RAW task handler is unchanged; the RAW backend is checked against a frozen complete implementation after accounting for the two extracted primitives.

The direct path removes full task-string formatting/encoding, the full RAW keyboard parser, processTaskWithContext, compatibility CF stream and response-vector accumulation/copy for text reads/writes. It still formats an optional content object's %@ description for compatibility. The complete original content is validated before truncation or ignoring it: prefix-inclusive 8192 UTF-16 code units, UTF-8 encoding/byte limits and embedded-NUL rejection remain. Oversized ignored GET content and ignored SET suffixes therefore still fail. No new protocol-token restriction rejects newlines or delimiters.

Preserve missing versus empty SET content, the exact missing-content error, first-field truncation at ;; and the exact empty SET reply (0;; followed by CRLF). GET still tests the first pasteboard.string value for nil and rereads it when nonnil; it does not cache or merge the two getters. Missing pasteboard/nil first string stays empty success, and a nil second read keeps the old (null) formatting. The shared bounded reply formatter preserves newline trimming, delimiter splitting, NUL truncation and Unicode behavior. JS text augmentation continues to select parts[1], with its existing result copy. No paste success verification, retry, rollback or cache is introduced.

Production TrollStore and TouchPOC execution sources are unchanged; both workflows run the shared safety suites. No CPU, allocation, latency or RSS improvement has been measured.

## Authority, effects and lifetime

Each read/write retains one ordinary task-24 license gate; owner automation authorization does not bypass it. Unsupported direct kinds fail before authority/provider work. The child context inherits owner fields, deadline, cancellation and output settings, with response capture disabled. Task 24 adds no C01-local deadline. Stop is checked after input conversion, before/after the gate and after provider/reply work.

Opaque pasteboard work remains synchronous. Once accepted, a SET can commit before caller stop/deadline, output rejection or an escaping exception is reported. The primitives have no new internal stop checks, retries or rollback. NS/C++ exceptions escaping the direct entry normalize to native_exception. Input formatting creates a snapshot before provider work; scoped budgets restore TLS and the per-call pool retains the result through teardown. Actual UIPasteboard thread requirements, permissions and cross-app effects still require device qualification.

## Verification

All 62 workflow runners (36 source-contract, 26 native), 521 direct workflow source-grep assertions, expanded standards-conforming assert preprocessing and git diff --check pass on Windows. The assert checker retains its rejecting negative control. Sixteen artifact-only checks require CI outputs. No warning or sanitizer checks were disabled. Windows cannot execute the new macOS/Foundation/ARC/sanitizer branches.

New macOS coverage compiles the actual clipboard primitives and full RAW parser, direct entry, shared reply formatter and JS adapter. Frozen JS/task/backend fragments from b6f5dae provide the old oracle. A controlled pasteboard records lookup/get/set/committed order and values; notification delivery is intercepted. Tests do not change the real clipboard or send real keyboard notifications.

Coverage includes 160 ordinary cases; nil/missing pasteboard and getter rereads; missing/empty/NSNull SET content; Unicode, delimiter, newline and NUL inputs/results; numeric kind normalization and non-string content descriptions; exact/over-limit ASCII/Unicode ingress and exact/short output; complete admission of ignored inputs/suffixes; ordinary authority/owner denial and initial/gate/provider stop/deadline; faults before/after fake SET effects; conversion-time cancellation, mutable input snapshots and retained results; RAW image-validation/notification fallbacks and full RAW parser compatibility after primitive extraction. Image file loading remains outside this checkpoint.

## Acceptance and remaining work

The user reported C02b40 build success at b6f5dae; that does not qualify the new text clipboard paths. Build rootfull/roothide and compare typed/helper keyboard 6/7 with RAW task 24 for empty/nonempty clipboard, Unicode/delimiters/newlines, missing/empty SET content, exact limits, ordinary license denial/revocation and caller stop/output failures. Qualify UIPasteboard thread/privacy behavior and actual cross-app read/write effects. Recheck keyboard notifications and clipboard image RAW routes. Measure bridge overhead separately from pasteboard access. Continue other P0-13 adapters and metadata codecs/copies, P1-40 invalidation and P0-12 qualification/unknown-start cases; C02 remains partial.
