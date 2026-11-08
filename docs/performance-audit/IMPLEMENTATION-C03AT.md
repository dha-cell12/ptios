# C03at — Direct owned reads for history index, recovery and event journal

Date: 2026-11-09 (Asia/Bangkok). Baseline: `d92471b9`; user reported C03as build passed and requested a larger batch. Scope: P1-48/P1-51/P1-54, shared production rootfull/roothide/TrollStore persisted reads. TouchPOC is excluded.

## Three producer paths

- History index and event journal retain their regular-file/no-follow/nonblocking open, fstat, negative-size and 32-MiB/4-MiB preallocation admission. Reserve exactly the admitted length without an explicit zero-fill, keep one stable raw pointer, read in the same <=64-KiB requests, and commit only successful returned bytes. The existing EOF growth probe runs before publication.
- Recovery retains C03ar's exact-byte shortcut and lazy semantic fallback. On a mismatch, reserve the authoritative encoded length without zeroing; its existing comparison engine reconstructs the verified prefix and fills the remainder. Commit the full length only after that engine reports a completed different file, then parse the immutable result. Recovery still uses the authoritative encoded length rather than adding a new 32-MiB artifact cap.
- A private TLinkOwnedReadBuffer exposes read staging, not NSData. Incomplete/overflowed commits cannot publish. Completion seals/moves the raw allocation into the existing immutable NSData owner factory; empty input produces an actual empty NSData, preserving invalid-empty-schema behavior at the original parser. Allocation/factory refusal produces the existing read-failure envelope. NS/C++ exceptions still unwind through the original descriptor/lock cleanup.

No input file is cached or skipped. Locks, schema/identity checks, recovery decisions, writer/permissions/markers/ACK/notification policy remain in the frozen source outside the small reader substitutions. The additional over-return guard rejects an impossible POSIX provider count instead of committing unproduced bytes. New internal publication failure points remain fail-closed.

## Storage and build integration

Extend the existing raw storage with reserve/writable/commit methods; append, move, seal and release retain their exact C03as source. Implement the read staging class in the already linked TLinkPersistenceJSON.mm, with a separate declaration-only header. Event and socket native runners link that module; history includes its complete generated module. All four production targets already compile it, so there is no new .mm/framework/link dependency. Before/after complete helper/core hashes and structural removal of only the additions recover the full C03as code.

This removes explicit NSMutableData length initialization before overwriting and hands off the completed allocation without an explicit payload copy. It does not eliminate OS page zeroing or guarantee Foundation's internal no-copy choice. The extra staging object/control block and small-file overhead, allocator rounding, parser memory, concurrent/held outputs, synchronous IO and full index/journal rewrites remain unmeasured. This is not an overall RSS or time bound. Callers must validate the limit and commit only bytes they actually produced; the staging API is not exposed to scripts.

## Verification

All 90 workflow runners (36 source / 54 safety portable subsets), 521 workflow source assertions, eleven-file assertion macro preprocessing, JavaScript syntax and diff whitespace checks pass on Windows; 16 artifact-only source checks are skipped. New portable coverage executes 100k poisoned-memory direct-fill/content/commit oracles, empty and exact 64-KiB/4-MiB/32-MiB reservations, partial/overflow commit, move/seal/release, allocation refusal and provider unwind. Existing C03as storage/owner and earlier history/event suites remain active.

The existing macOS sanitizer executables add 132 complete old/current history/event reader comparisons: empty/binary/three-chunk bytes, identical read and buffer-factory counts, EINTR/short/EOF/EIO/NS/C++/growth, stat/size/open fences, missing files and no writer/marker/notification effects. Full C03as history source and the entire old event reader are compiled as independent oracles. Existing C03ar recovery parity still exercises the new fallback storage. Private staging tests cover poisoned reserves, incomplete/overflowed publication refusal, real/copy/nil/short/NS/C++ data factories, detached output across caller pools and balanced allocations.

Native tests are CI expectations, not Windows results. Foundation/ARC/ASan/UBSan compilation/execution and device performance need macOS/iOS qualification. The native include/source/dependency paths are explicit, and all older source guards remain composed through exact reversal.
