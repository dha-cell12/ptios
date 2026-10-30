# C03z — writeText byte counting without a temporary NSData

Date: 2026-10-30 (Asia/Bangkok). Baseline: `adaf252c`, C03y build passed according to the user.
Status: **user reported build `54991dd3` passed before C03aa; device allocation/latency qualification pending**.
Finding: **P1-47 storage codec conversions**, partial improvement.

## Change

The root in-process bridge and root helper encoded writeText into an NSData only to check its length and report bytes, then used NSString's atomic UTF8 writer to perform the actual write. That explicit counting buffer remained available for the post-write reply. Production TrollStore also made an NSData just to count bytes after its string writer returned.

Use NSString lengthOfBytesUsingEncoding:NSUTF8StringEncoding for counting. Retain the same NSString normalization, path resolver, parent-directory handling, atomic string writer, NSError/fallback messages and response fields. Rootfull/roothide and helper retain the 512-KiB pre-write byte check; TrollStore retains its existing post-write counting position and policy. writeJSON's call through writeText benefits from the latter's counting change, while its other encoding steps remain. TouchPOC is excluded.

This removes the handlers' explicit counting NSData and its encoded payload. Foundation's byte-length query and string writer can still allocate/scan/encode internally. No zero-allocation, one-pass encoding, peak RSS reduction or measured device latency claim is made. Native request/context/authority handling and helper policy remain unchanged.

## Verification

Freeze all three changed writeText branches/methods from the user-passed baseline. Reverse only the byte-count expression, limit comparison and bytes result, then compare each complete production source file with its baseline SHA-256:

- Root bridge: `1c64feba57b0f3c09981c7c483b8b0355b6b8c9998429ae3d7b404326f3ad9cc`.
- Helper server: `fef72ddec3d5eac5ba56453432b46683f8df4fe40f36a2c1314ab8dc1b6ddeb6`.
- TrollStore socket: `e024f141e29eaa6cd08d28804595a86e537e8e15cd3c964409309d641b66f1d4`.

The existing check-file-handle-safety runner performs these guards on every host and retains its native line-reader suite. On macOS it additionally compiles the extracted actual root branch, complete helper method and TrollStore block alongside the frozen versions. Use the real native response class and real Foundation UTF8/atomic file writer, with controlled path resolution in private temporary files. The full-source guards protect the surrounding entry/policy/context code; the new runtime fixture does not execute those complete services or their real path resolvers.

Compare full response/transport-error fields, file bytes, resolution arguments/order and helper storage-operation counts for empty/missing/default and description inputs; Unicode/emoji/NUL/repeated BOMs; unpaired surrogates including an over-limit UTF16 string; exact 512-KiB ASCII/Unicode boundaries; denied/missing/directory paths; NSError and nil-error failures; NS/C++ write exceptions. A forwarding NSString test double counts explicit conversion/size/write calls while its backing NSString performs real encoding/IO. Preserve TrollStore's absence of post-write conversion after a throwing writer. Also compare UTF8 byte-length queries with NSData lengths across 1,000 deterministic UTF16 cases.

Event Channel's earlier full-file TrollStore guard now first reverses this independently guarded storage expression before reversing its own wire encoder; the historical digest stays unchanged. Warnings, assertions, sanitizers and all earlier FileHandle tests remain enabled.

Windows validation passed: all 65 workflow runners (36 source, 29 native) after focused Color/Event reruns, 521 source checks, focused storage/FileHandle guards, expanded assert preprocessing and `git diff --check`. Color's first assertions passed before a temporary exe-unlink EPERM; Event's initial failure was the baseline comparison updated above. Sixteen artifact-only checks were skipped. The new Foundation runtime requires macOS CI.

## Remaining work

readJSON/writeJSON still have other data/text/object conversions; FileHandle still returns its established text and base64 fields. Storage read-size races, helper policy/path qualification, filesystem durability, log retention and the wider C03/device work remain separate. The frozen comparisons assume Foundation string behavior; custom native subclasses with inconsistent encoding methods are not a script API extension.
