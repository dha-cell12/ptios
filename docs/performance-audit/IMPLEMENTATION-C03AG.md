# C03ag — Shared FileHandle construction and lifecycle package

Date: 2026-11-07 (Asia/Bangkok). Baseline: `fc750fb9`; user reported C03af built successfully and requested larger batches. Scope: shared FileHandle used by rootfull/roothide, helper and production TrollStore. TouchPOC excluded. Extends P1-43/P1-44 lifecycle/temporary work without changing the complete text/base64 contract.

## Changes delivered together

- Share normalized-mode set membership with Open. A recognized normalized mode is validated directly and its already-computed plus/prefix state supplies flags; ordinary valid Open goes from three normalizer calls to one. Preserve twelve accepted modes, three aliases, lowercase/whitespace rules, public ModeWrites behavior for invalid strings, default nil mode, flags and invalid-mode priority. Unknown normalized values keep the preceding validation/writing fallback. Public signatures and frontend path/authority/count logic stay unchanged.
- Scope private mode normalization temporaries to a normal pool while retaining the resulting string through return. This benefits Open and the existing public mode helpers. It does not cache mutable values across operations or assert an allocation/RSS improvement.
- Give each successful kernel open an explicit pending descriptor owner immediately before the construction try/finally region. Metadata repair, append positioning, object creation, capability probing and property setup run while that scope owns the descriptor. Transfer to the handle only after all preparation succeeds. Finally retires an untransferred descriptor once, clearing its ownership state before close. A failed/throwing close is never retried by this owner.
- Handle a nil allocation/initializer with the existing file-open error shape and ENOMEM diagnostic instead of dereferencing nil. NS/C++ exceptions still propagate after descriptor retirement. Required metadata/append/readability probes retain their order and ordinary fallback behavior. Creation/truncation/metadata changes performed before a later failure are not rolled back or replayed.
- Initialize a plain unopened handle with fd=-1, closed=YES and nonnil empty path/default mode. The previous zero-initialized fd could target descriptor0 during direct-object deallocation; partial initialized objects now cannot own the pending descriptor. Successful Open publishes the original ready state and transfers its actual fd, including fd0.
- Use direct comparisons for canonical set/start/cur/current/end seek values; tell's canonical cur route avoids lowercase/trim. Other inputs retain the preceding Foundation normalization, aliases/error ordering and lseek behavior. Negative/extreme offsets, errors, returned positions and synchronization remain unchanged.
- Scope seek/flush/close to normal per-operation pools. Locks exit before normal pool retirement; returned path/error/result graphs remain owned. Keep read-only flush, fsync, close-before-error ownership retirement, alreadyClosed and exact error envelopes. Existing read/write/line/payload algorithms and JS bindings remain unchanged.

The safety changes cover the period after open returns and before a ready handle owns the fd. Blocking POSIX calls, caller cancellation, queue residence and existing atomicity/durability choices remain outside this package. Foundation allocation failure timing and arbitrary custom normalization/initializer/setter side effects are not promised identical to the unsafe preceding path.

## Verification

Windows passes all **90 workflow runners** (36 source,54 safety), **521 source assertions** (16 artifact-only checks skipped), a final focused FileHandle/core/extraction rerun, JavaScript syntax,11-file expanded assertion argument checks and git diff --check. Apple native branches are skipped on this host.

Five frozen regions and the new include reverse to the exact complete preceding C03ac FileHandle. Existing payload/line/full-class guards continue against that source. The complete descriptor helper is guarded. Public header, line/IO/UTF8 cores, JS binding and all three frontend implementations remain unchanged. The existing runner checks current/frozen native extraction on Windows too.

The actual portable owner executes100,000 descriptor-zero/reuse/pending/transfer/retire lifecycles, with copy prohibition, repeated retirement, close reentry and after-close exception. A transferred descriptor is closed by its new owner only; all synthetic live sets finish empty. Existing10k payload and10k line oracle/fault/boundary tests remain.

Extend the existing Foundation/CoreFoundation/POSIX/JSCore/ARC/ASan/UBSan executable; no new workflow runner or executable. Native expectations include:

- Complete ordinary mode/alias/uppercase/whitespace/Unicode/NUL/invalid/default comparisons with frozen flags, file contents, replies and open/close counts. Public ModeValid/ModeWrites checks remain paired too.
- Explicit normalizer-entry probes measure three versus one for canonical valid Open and zero versus one for canonical seek. Fallback whence/default/empty/error and negative/zero/extreme offsets retain full reply/position parity. These are fixture function-entry counts, not Foundation allocation measurements.
- 27 construction cases spanning ten post-open stage pairs (parent stat/owner/mode, append seek, capability stat/seek, path/mode/id/closed setters), nil/NS/C++ factory outcomes, nil/throwing initializers and ordinary append failure. A late setter may mutate closed before throwing; descriptor ownership still remains with the pending scope. Check one open/one close, no live fd and the intended error/propagation.
- Direct unopened construction without opening/closing descriptor0; normal caller-pool drainage while a replacement handle remains usable;64 repeated fault/recovery cycles.
- Explicit MRC normalizer and seek/flush/close success/error witnesses, held result graphs and no pending owners after normal pools. The close-failure provider closes first and then reports EIO, verifying no replay of a potentially reused descriptor.

Native extraction adapts only one construction call to a factory seam plus normalizer/seek-normalizer entry probes; ordinary construction still invokes the real class alloc/init. Subclasses provide initializer/property faults. Frozen code gets matching entry probes. The factory seam can change temporary object retirement timing, so descriptor ownership is tested independently of immediate partial-object deallocation. Existing full-class file/pipe/external-edit/short-IO/JSCore suites compile the complete current implementation.

**New Apple compilation and Foundation/ARC/sanitizer execution require macOS CI.** No device throughput, IO latency, RSS, Foundation allocation or opaque initializer cleanup gain is measured. Existing dual replies, storage JSON conversions, blocking IO, broader handle admission and device qualification remain open.
