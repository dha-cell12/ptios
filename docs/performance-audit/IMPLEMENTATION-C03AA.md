# C03aa — retained UTF8 views for readJSON

Date: 2026-10-30 (Asia/Bangkok). Baseline: `54991dd3`, C03z build passed according to the user.
Status: **user reported build `e1f20e22` passed before C03ab; device allocation/latency qualification pending**.
Finding: **P1-47 storage codec conversions**, partial improvement.

## Change

Root in-process and helper readJSON previously always UTF8-encoded the string returned by readText into another owned byte buffer before parsing. Add TLinkUTF8DataFromString: copy to an immutable snapshot and ask Core Foundation for already available internal UTF8 storage. If no pointer is available, retain the previous dataUsingEncoding conversion. Availability is representation/platform dependent and is never assumed.

When direct storage exists, wrap it in an immutable NSData with a custom deallocator block that retains the string owner. The block releases ownership with the data and never frees or mutates the string's buffer. This keeps the data valid beyond the source/caller autorelease pool; a mutable input is snapshotted before borrowing. Compute the complete encoded length, including embedded NUL; do not use strlen or UTF8String's temporary C buffer. Non-string inputs retain the old encoding message/exception behavior instead of entering Core Foundation with an invalid type. The string does not reference the newly created data view, so this ownership chain introduces no back-reference cycle.

The only reader changes are the conversion call and header include. Keep recursive root readText dispatch/context/error forwarding, helper readText/storage operation counts, UTF8 validation/fallback, JSON parser options/error messages, response fields, path/authority policy and byte limits. Explicitly link CoreFoundation in the two root build targets. Production TrollStore already parses its file NSData directly; its source remains at the user-passed C03z state. TouchPOC remains excluded.

API references: Apple's [CFStringGetCStringPtr](https://developer.apple.com/documentation/corefoundation/cfstringgetcstringptr(_:_:)?language=objc) and [NSData custom-deallocator initializer](https://developer.apple.com/documentation/foundation/nsdata/init(bytesnocopy:length:deallocator:)?language=objc). The fast path uses existing immutable storage; the custom block retains its owner without retaining the data view.

## Verification

Freeze both readJSON implementations from the user-passed baseline. Reverse just the include/conversion and hash each complete production source against that baseline:

- Root bridge: `0cbea81bce778d20f580f34730c41a81d6e111ccb752ff6dbf561e1d66a4397e`.
- Helper server: `6432c8f1b7d0e1b032c13b6f864d5a37e5d1ea6339a8c8a9a1cdc6c513035af3`.

Keep the earlier C03z complete-source/writeText guards by reversing this independent change first. The FileHandle runner still executes the original native reader and writer suites; its macOS branch additionally compiles the actual root readJSON branch and helper method alongside frozen implementations, the real native request/response classes and new header. Child readText is controlled to test exact forwarding/results without opening user files or executing full services/path resolvers.

New cases retain a 64-KiB borrowed buffer beyond the source's pool, release the view and require balanced owner destruction, force the ordinary encoding fallback and verify independent byte ownership, preserve parsed graph access after source/view pools drain, and mutate/drain a mutable source while the snapshot stays unchanged. Ordinary probes delegate to actual CF; a controlled pointer provider covers the borrowed-owner path independently of OS representation choices. Test nil/non-string behavior, Unicode/BOM/NUL/invalid UTF16, empty/scalar/malformed JSON, missing text/read failures, child transport/error/context and helper count parity. Compare 1,000 generated JSON replies with frozen implementations. Earlier C03z real-file writer cases remain unchanged.

Windows validation passed: all 65 workflow runners (36 source, 29 native), 521 workflow source checks, focused complete-source/FileHandle/storage guards, expanded assert preprocessing including the JSON fixture and `git diff --check`. Sixteen artifact-only checks were skipped. New Foundation/CoreFoundation/ARC/sanitizer execution requires macOS CI.

## Limits and remaining work

Only an available internal UTF8 buffer avoids the extra payload encoding/copy. Immutable copying, the data object/block and Foundation's fallback/parser can still allocate. There is no measured device hit rate, RSS, CPU or latency claim. Snapshot copying is not atomic against arbitrary concurrent mutation of the same mutable string. Existing full file reads/size races, other writeJSON conversions, FileHandle dual text/base64 replies, log retention and broader C03/durability work remain open.
