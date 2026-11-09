# C03az — Bounded asynchronous helper console batches

Date: 2026-11-09 (Asia/Bangkok). Baseline: `4e5d0862`; user reported C03ay built successfully and requested larger packages. Scope: P1-42/P1-50, production root/roothide JavaScript helper. TouchPOC is excluded.

## Producer, admission and queued ownership

Move ordinary helper `_tlinkautoLog` system and disk sinks off the JS caller onto one process serial queue. Each run owns a fixed pending array and one outstanding drain ticket. Reserve both a per-run permit and a process-wide permit before metadata/UTF8 preparation. The shared process limit is64 retained records across preparing, pending and consuming work; full or closed owners refuse before formatting.

Keep C03ay immutable4096-unit message/64-unit metadata prefixes, surrogate boundaries, producer timestamp and one nonempty UTF8 line of at most16KiB shared by both paths. Each admitted record can retain up to16KiB of logical UTF16 metadata plus16KiB of encoded data: at most2MiB across64 producer records. This excludes backing/allocator/Foundation objects, caller inputs, paths, queue/control objects and the bounded atomic-creation copy. It is not a process RSS limit. JS argument conversion and arbitrary description/provider work remain opaque.

Publication and scheduling form one mutex transaction. Enqueue failure rolls back the entry; a copied-but-abandoned ticket retires its pending records and admission permits. Ticket generations refuse stale callbacks without wrapping. Keep payloads alive until their sinks finish, then release payloads before their permits. A stalled consumer can hold64 records; further logs drop rather than grow the queue.

If queue/owner construction fails, retain the preceding bounded synchronous emitter. Admission refusal, closure and sink failures do not switch to synchronous retry. No extra implementation object, framework, public helper header or build target is introduced.

## Batched disk and independent system sinks

Reuse the complete root console append/vector/group policy with narrowly adapted record types and the existing helper512-KiB threshold. Existing files use retained NSData spans, host-clipped writev and checked partial/EINTR progress. Missing-file creation retains bounded joined-data atomic replacement. Include the record crossing the threshold, then reset before the next record, matching preceding sequential bytes in ordinary execution.

Run and latest paths have independent failure masks; uncertain prefixes are never replayed. System logging has its own exception boundary and per-record pool. A file codec failure can still deliver prepared metadata to the system sink. A system failure does not suppress either file. Accepted records keep FIFO order within their owner; normal completed per-file bytes and system records retain the frozen formats.

System output is now deferred. Within a batch system records precede the file groups, so intermediate interleaving/file observation changes. Full queues can drop records, and failed file groups conservatively count every affected record. Logging remains best effort, not a durability or delivery guarantee.

## Terminal close and observability

Close admission and drain accepted published work before all three terminal summary paths. A scope owner also closes on NS/C++ unwind before the C03ax completion proof runs. The serial queue barrier waits for in-flight sinks. If barrier submission throws, a consumer mutex serializes a direct drain; delayed queued tickets then become stale. Sink reentry only requests closure, avoiding recursive waits. If scope close cannot settle, cancel the retention proof so incomplete work is not marked complete.

An opaque producer still formatting when close starts is not waited on: its eventual publication is refused and its permits retire after preparation returns. It cannot append after terminal summary or completion marking. Terminal waits can still block on opaque filesystem/system IO; there is no hard delivery deadline or active IO cancellation. Structured summary/exception reporting retains its previous writer and size policy.

`device.runtimeInfo().consoleLog` adds mode `async_bounded_batch_v1` and per-run `accepted`, `dropped`, `truncated`, `writeFailures`, `systemFailures`, `pending`, `peakPending`. Accepted means publication, not delivery ACK. Dropped includes refused logs and pending work retired after abandoned scheduling. Pending includes preparing/consuming payloads. Failed construction reports only `sync_bounded_fallback_v1`; no asynchronous counters are fabricated. Closed run callbacks refuse before formatting.

## Validation and remaining qualification

Freeze and restore the complete preceding helper and metadata implementation before older source guards run. Check all three terminal closes, scope/proof ordering, single transactional scheduling seam and the complete adapted root writer bodies. Keep prior C03ay native comparisons independent through exact metadata restoration.

Portable coverage passes100000 FIFO/close/stale/held-payload transactions, UINT64_MAX fencing,10000 registration rollback/reentry cases and80000 concurrent exactly-once publications with zero final charges. Native CI adds12 complete64-record actual JSCore/file/system comparisons, controlled128-to2 ordinary descriptor open/close expectations, host vector limits, process-wide admission, discard/copied enqueue failures, stale callbacks, independent sink/seek/close/vector faults, blocked drain, late producer refusal, reentry and NS/C++ unwind before real completion proof. Existing80 synchronous helper comparisons and retention tests remain; cancelled proofs are explicitly tested.

Windows validation: all90 workflow runners (36 source and54 safety portable subsets),521 workflow source assertions (16 artifact-only checks require built outputs), nine-file assertion macro preprocessing, JavaScript syntax, complete source reversals and diff whitespace. Apple Foundation/GCD/JSCore/POSIX/ARC/ASan/UBSan execution is wired into the existing console runner but requires macOS CI. Descriptor counts are controlled fixture expectations, not device measurements. Device latency, allocation/RSS, real syslog workload, summary/error bounds, legacy/orphan migration and overall disk/time bounds remain open.
