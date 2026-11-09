# C03bc — Exact-content Event status cursor memo

Date: 2026-11-10 (Asia/Bangkok). Baseline: `33adcbea`; user reported C03bb built successfully and requested larger packages. Scope: P1-51/P1-54 Event Channel status shared by rootfull/roothide and production TrollStore. TouchPOC is excluded.

## Delivered together

- Factor the complete preceding JSON/schema/sequence/event validator into one decoder. Publication and long-poll still call that same decoder on their existing read paths. Preserve every original validation rule and error string; no schema or authority shortcut is added there.
- Add a process-local exact-content memo for status only. Every request still acquires the existing shared file lock and performs the complete bounded, no-follow/nonblocking regular-file read with EOF validation. Compare those fresh bytes with a previously validated immutable byte copy; an exact match reuses only its uint64 latest cursor. No path, inode, timestamp or hash match can authorize a hit by itself.
- Keep one byte copy of at most2MiB plus the cursor. Do not retain a parsed journal graph or a public status dictionary. Mutex serialization prevents partial publication and cross-client key/value mixing. Copy/allocate while holding the memo mutex after retiring the preceding copy, with no second retained memo entry. Allocation refusal/throw clears the entry and leaves the already validated status successful; subsequent calls decode normally.
- Build status directly from that scalar instead of allocating a pagination batch, topic set, selected-event array and unused batch metadata. A local loader pool releases cold decoded graphs/read temporaries before constructing the outward status graph. Public status fields, errors and journal-read counters remain; counters still count each actual read.

Missing-file bootstrap remains implemented at cursor0 and is never memoized. Read, lock, schema or decode failure clears the memo before returning the existing failure envelope. Journals larger than2MiB still use the unchanged4-MiB reader/validator boundary; they are valid but uncached. A different byte sequence always needs validation even when its size/metadata match. Identical bytes after atomic replacement can hit only after the replacement has passed a new checked read. The memo owns its bytes independently of the read buffer.

Concurrent requests can replace each other's memo entries, causing extra misses. They cannot return another key's cursor: lookup compares complete length/content under the same mutex as publication. A late older decode can replace the single entry, but the next request must still match its freshly read bytes; no generation assumption is needed for correctness.

## Cost and limits

This removes repeated JSON parsing, schema scans and unused batch construction for unchanged status content. It does not remove filesystem reads, shared-lock admission, kernel copies, writer journal rewrites or long-poll reconciliation. Warm lookup still compares O(encoded bytes). A cold valid small journal adds one byte allocation/copy; changing/high-traffic journals may receive no benefit. The2-MiB limit is requested retained content, not total process RSS, allocator overhead, IO time or a bound on concurrent caller buffers/decoder graphs. Device CPU/allocation/latency gains require measurement.

The memo is private auxiliary state, not persisted recovery or an event epoch. It neither repairs a damaged journal nor fabricates a success from old data. Existing missing-file sequence/epoch recovery, arbitrary noncooperating filesystem races and durability remain open. No public schema, task/license gate, transport, history implementation, poll snapshot cache, build target, framework or implementation link dependency changes.

## Validation

Restore the complete preceding Event source before all historical guards. Verify that the decoder body is exactly the previous validator, the status lookup follows the fresh read, publication/poll/read/lock bodies are preserved and failure clears the memo. Retain both fresh-read fixture seams and isolate the historical standalone integer extractor from the newly factored decoder, preventing an accidental native dependency expansion. Review all three direct native Event builders; their existing shared include paths resolve the new header without another linked implementation.

Portable production-cache coverage passes100000 exact-byte/mutation/clear oracles,300000 allocation-free hits, zero/UINT64_MAX/SIZE_MAX and exact2-MiB boundaries, owned caller-byte snapshots, null/throwing allocation recovery and80000 concurrent stores/lookups without false-key hits.

Allocation counters here cover owned memo-byte allocations, not opaque mutex, kernel or runtime allocations.

Extend the existing Foundation/POSIX/GCD/ARC/ASan/UBSan runtime with an exact frozen status adapter. Native expectations include129 checked fresh reads with one decode; ordinary/zero/UINT64_MAX cursor and complete status graph comparisons; identical atomic replacement, changed content, missing/corrupt journal, primed-cache read faults, NS/C++ decoder faults, unsafe root/directory/FIFO refusal, allocation-failure uncached success, large valid uncached journals and balanced real descriptors/locks. Native counts are controlled fixture expectations, not device measurements; Apple execution remains pending macOS CI.

Windows validation has passing results for all90 workflow runners (36 source/54 safety portable subsets) and521 source assertions, with16 artifact-only checks skipped. The new child check initially had an overly broad source regex matching existing `max_events` fields; after narrowing it, the complete Event runner passed again alongside the other89 results. JavaScript syntax, five-file assertion macro preprocessing, complete predecessor restoration and diff whitespace pass. No Apple native execution is claimed on Windows.
