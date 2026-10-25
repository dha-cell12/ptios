# C02c1 — metadata-backed immutable helper configuration snapshot

Date: 2026-10-25 (Asia/Bangkok). Baseline: `2259bc0`; the user reported C02b22 built successfully before this slice.
Status: **source implemented; new macOS/iOS CI and device qualification pending**.
Finding: **P1-40, bounded first slice**. Metadata syscalls/serialization remain synchronous; event-driven helper transport, dedupe and other native adapters remain open.

## Result and scope

The root JavaScript runtime keeps one process-local configuration cache behind the existing TLinkautoJSHelperConfigSnapshot function. Script runtime selection, per-new-RPC helper policy and runtimeInfo continue calling that function. An unchanged file identity returns the same immutable normalized dictionary without opening/reading the config file or parsing JSON again.

This is a metadata-backed cache, not a purely memory-only or asynchronous policy read. Every lookup still performs stat under a cache mutex. A miss serializes open/read/parse/publication, and slow filesystem work can block concurrent lookups. No notification watcher, timer, pinned per-session policy or fixed refresh interval is added. P1-40 is therefore partial; removing synchronous metadata work requires a separate invalidation/authority design and qualification.

Only the normalized path/valid/enabled/default/admin/error fields are retained, not the whole input JSON. Temporary data/parser objects drain in a local autorelease pool. Callers retain their immutable dictionaries independently of later replacements and cache lifetime. Production TrollStore and TouchPOC source are unchanged; both build workflows run the new shared test runner. No measured device latency/CPU/RSS improvement is claimed.

## Identity and stable publication

The cache key includes device, inode, size, nanosecond mtime and ctime, mode, uid and gid. Changes invalidate a previous view even for same-size in-place writes with restored mtime, atomic rename replacement, permission changes or deletion/recreation. Access time is excluded so ordinary reads do not invalidate the cache. This is filesystem metadata coherence, not a cryptographic content generation or a guarantee against metadata-forging writers.

On a miss, check the path identity, open and fstat the descriptor, read bounded bytes, then compare descriptor and path identities again before accepting the data. A replacement or in-place write observed during reading rejects that candidate. No mixed or obviously stale candidate replaces the cache. Writes after the final check can be observed by the next lookup, as with the prior synchronous read; no instantaneous cross-process revocation guarantee is introduced.

Only regular files are accepted. Open with CLOEXEC and NONBLOCK so a regular-file-to-FIFO race cannot turn the loader into a blocking FIFO reader. Read at most 1 MiB plus one detection byte, handle partial reads and up to 32 EINTR interruptions, and close on normal/error/NS/C++ paths. The new 1-MiB config ceiling is an intentional bound: larger configs disable helper flags with config_size_limit. Existing ordinary config files and booleans keep their prior meanings; direct symlink resolution remains supported.

## Policy compatibility and failures

Preserve the primary javascript_helper_runtime_enabled key and legacy enable_js_helper_execution fallback exactly, plus runtimeDefault and allowAdminRPC boolValue handling. Keep configPath/configValid/error and the same missing/empty or JSON parse error semantics for ordinary supported files. Return immutable dictionaries instead of the previously mutable temporary snapshot; all production call sites read these values.

Missing/unreadable/changing/oversized/nonregular files or loader exceptions replace a previously permissive view with all helper flags false. I/O/identity failures invalidate the memo so the same metadata can recover on the next lookup. Stable malformed or empty files can cache their denied view until metadata changes. Never retain an old admin-true snapshot merely because a reload failed.

The helper RPC allowlist/admin classification, task license enforcement and replay branches are unchanged. In particular, enabled/default flags still control runtime selection, while the existing per-new-RPC policy consumes allowAdminRPC; this slice does not invent a new stop-on-disable rule for active sessions or reexecute cached requests. The existing 200-ms helper polling/fresh socket transport and 256-entry dedupe design remain for P0-12/P1-41.

## Validation

- Windows: all 57 workflow runners pass (36 source-contract, 21 native), plus 521 direct workflow source-grep checks; 16 artifact-only checks need CI outputs. The existing phase-2 alias source contract now checks the runtime's header integration and the actual normalizer expression in its new location, without relaxing license assertions. The previously failing alias check passes after that update.
- Portable tests add 100k identity/memo cycles, mutate every one of the ten identity fields and exercise 8 x 10k serialized publication/invalidation cycles. The metadata cache's Foundation/POSIX implementation is compiled on macOS, not on Windows.
- The new macOS fixture compiles the actual cache, runtime wrapper and allowlist/admin policy. It adds 121 frozen normalization cases plus alias/missing/empty/invalid JSON, 10k unchanged reads with no additional open/read/parse, retained immutable views, same-inode/size/restored-mtime ctime invalidation, atomic replacement, permission changes and deletion/recreation.
- Real-file fault boundaries cover stat/open/fstat/read/close failures, partial reads, EINTR limits, NS/C++ read exceptions, in-place/replacement races and subsequent recovery. File bounds cover oversized, exactly 1-MiB valid JSON and FIFO rejection. Eight threads issue 8000 reads with one parse and 7999 cache hits; tracked descriptors end empty. These are fixtures awaiting macOS execution, not device results.
- Source guards verify the unchanged per-RPC wrapper call, metadata hit before open, final descriptor/path checks before decode/publication, mutex ownership and both workflow runner entries. Standards-conforming assert preprocessing and git diff --check pass.
- **Actual Foundation/macOS/sanitizer execution, iOS builds and device measurements were not run on this Windows host.** The new macOS branch and real filesystem/runtime integration await CI/device qualification.

## Acceptance and next slice

Build rootfull/roothide, run helper and default/fallback modes, compare flags/runtimeInfo and new-RPC admin policy while changing config by atomic replacement and in-place writes. Verify parse/open counts stay flat under unchanged RPC traffic, policy changes are detected, invalid reads never reuse admin permission, and retained snapshots survive refresh. Measure cache-hit metadata/lock cost and reload stalls separately from the existing transport polling delay.

Continue P0-12 event-driven helper RPC with reconnect/session/request identity and no repeated side effects, P1-41 byte-bounded replay/dedupe, remaining P0-13 adapters and the rest of P1-40 invalidation work. C01/C02 performance/device acceptance remains open.
