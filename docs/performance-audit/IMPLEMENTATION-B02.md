# B02 — frame/image store ownership, deadlines and payload budgets

Date: 2026-10-17. Findings: **P0-07, P0-09, P1-20, P1-21, P1-24, P1-26**.

Scope: production **pccontrol/rootfull/roothide** Image.xm. Production TrollStore has a separate image implementation; this group does not claim to change it. Prototype TouchPOC remains excluded. B01's corrected build at `07c1b84` was reported passed by the user before this group; its device qualification remains separate.

## Ownership and queue behavior

Frames and image objects are constructed once behind shared ownership and published as shared_ptr<const payload>. Payload copy construction/assignment is deleted. Frame insertion captures a shared pointer and emplaces that reference; it no longer copies the full BGRA vector into an intermediate object and then the map. Image gray matrices move into the owned object. Legacy template matching also retains the complete owned object, including its memory charge, rather than copying a Mat header without its accounting lifetime.

The serial store queue only admits/snapshots references, reserves charges, publishes objects, manages handles/owners and erases expired/released objects. Matching, color scanning, batch parsing/computation and OCR ROI clone/cvtColor execute on the caller outside that queue. A batch snapshots its frame and at most 64 distinct referenced templates atomically; parsing and unique-ID collection happen before entering the queue. Missing templates still produce an error. Releases keep their existing optional session/run/runtime filters, including unscoped release-all semantics.

Once a request has obtained a snapshot, release, count eviction or TTL expiry removes the public handle but does not invalidate that admitted reader. Subsequent requests cannot look up an erased handle. The last snapshot releases pixels before its RAII charge is returned. IDs remain positive signed-32-bit values for legacy int parsers and are never reused after wrap/exhaustion; exhaustion fails publication explicitly.

## Published limits

| Resource | Limit/policy |
| --- | --- |
| Stored frame handles | 3; oldest monotonic capture time, then lowest ID, evicted to admit another capture |
| Stored image handles | 64; explicit release; no silent image eviction/TTL |
| Owned frame payload | 96 MiB |
| Owned image payload | 64 MiB |
| Combined owned payload | 128 MiB |
| Decoded frame/image | 16,777,216 pixels; each dimension at most 8192 |
| Encoded disk image | 32 MiB; bounded read requests only one byte beyond this cap |
| Concurrent heavy image operations | 2; extra calls return image_compute_busy without waiting |
| Frame TTL | Default 1000 ms, maximum 5000 ms, as before |

Payload reservations happen **before** allocating retained BGRA/gray pixels or decoding an image. Pending construction and active readers after erase count against the same ledger; clearing the maps cannot bypass the limit. Count slots are rechecked at publication after concurrent preparation. Admission failures, pixel/encoded limits and failed publication return errors rather than a zero handle reported as success. Frame admission expires/evicts old handles before reserving bytes; a later preparation failure may therefore leave an old handle evicted. Active readers of that handle remain safe.

These are retained/application payload limits, **not an RSS ceiling**. Screen capture CGImages, encoded NSData, gray-only frame conversion's temporary BGRA, screenshot conversion RGBA, OpenCV resize/decoder scratch, ImageIO internals, OCR output clones, allocator overhead, metadata and stacks are additional. The two-operation admission bound limits simultaneous image entry points but does not bound allocations in opaque codecs or other subsystems. File reads, capture, vendor calls and scheduler residence still have the A06 cooperative-cancellation limitations. Release/metadata operations bypass compute admission.

Disk open reads one bounded immutable NSData, checks ImageIO metadata without requesting a decoded image, reserves gray bytes, then passes **those same bytes** to OpenCV IMREAD_GRAYSCALE. No path reopen race exists between preflight and decode. The decoded dimensions must match the encoded dimensions or their transpose (EXIF rotation); other results fail. Formats whose metadata ImageIO cannot inspect are now rejected even if an OpenCV codec could read them. This new restriction and the caps need qualification with actual user image sets; PNG/JPEG/EXIF/TIFF/BMP fixtures are part of device acceptance. ImageIO preflight is not a proof of bounded internal codec work on malformed inputs.

## Time and expiry

TTL and age use steady_clock. Timing measurements also use monotonic seconds. Task capture's existing createdAtMs response position still contains its old CFAbsoluteTime wall timestamp for wire compatibility; it is stored separately and never participates in expiry decisions. Existing response shapes, color/SAD math, coordinate conversions, max-age policy and successful batch auto-release remain unchanged.

One dispatch timer on the store queue targets the earliest current frame deadline. It has a **one-shot interval**, is set to DISPATCH_TIME_FOREVER when empty, and is rearmed on publication, expiry, snapshots and release. A first timer-creation failure rejects frame admission/publication. Idle frames no longer require another image request to be reclaimed. Lazy admission checks remain in place, so a late timer cannot admit an already-expired handle. Timer delivery/queue scheduling is not a hard reclamation SLA; an admitted reader may retain a charged expired payload until its work finishes. Explicit-lifetime image objects do not gain a surprise TTL.

## Verification

`node scripts/check-image-storage-safety.mjs` extracts the **actual production payload types, store globals, owner predicates and store core**, and compiles them with C++14 and MSVC /W4 /WX on Windows. A minimal Mat ownership double is used; OpenCV pixel math is not simulated as a performance measurement.

Passed locally:

- pointer identity through frame/image publication, compile-time prevention of payload copies;
- safe readers and charged bytes after erase, exact-deadline expiry and deterministic count eviction;
- frame/image/combined byte limits, image count rejection, no implicit image expiry, geometry/overflow and signed-handle exhaustion;
- owner predicates, timer-admission failure, two-operation compute admission and recovery;
- 20,000 frame lifecycles, plus 8 clients × 10,000 concurrent ledger reservations; no live charges at completion;
- source assertions forbid CV/matching/color/ROI work inside store dispatch blocks and require preflight before decode;
- all **36 existing source-contract checks** and all **7 prior native regression suites A01–B01**, including A06's extracted actual production SAD loops, pass on Windows.

Rootfull/roothide CI now includes the new runner. On macOS it also compiles the **actual queue, store, snapshot/reservation/timer adapter, scoped frame release and bounded decoder wrapper** with Foundation/dispatch/ImageIO and ASan/UBSan. Fixtures cover idle expiry without another image API, release while a worker retains a snapshot, release with both compute slots busy, stale cleanup, PNG metadata/encoded limits, rotated dimensions, memory denial and decoder dimension mismatch. Only the OpenCV decoding call/Mat pixel storage is doubled there; Foundation file reads, metadata preflight and dispatch are real. This macOS branch cannot run on the Windows host. Final iOS/OpenCV artifact builds and device behavior remain pending.

## Build/device acceptance

1. Run rootfull/roothide CI and build both artifacts. Compare task capture/find/color/batch/OCR response fields and results to B01 on iPhone/iPad and both orientations, including BGRA-only/gray-only frames and point coordinates.
2. Release one/all/scoped handles concurrently with slow matching/OCR. Admitted work must finish safely; new lookups must fail after release. Exercise compute-busy and payload-budget errors and recovery after the last reader finishes.
3. Capture and then stop making image requests. Check store entries expire around the configured deadline, idle timer wakeups stop, and retained payload bytes return after readers finish. Separate store payload bytes, allocations and RSS; do not interpret an allocator cache as a retained handle leak.
4. Open the actual supported PNG/JPEG/EXIF/TIFF/BMP image sets. Verify normal gray pixels/results, transpose handling, >32 MiB files, >16M-pixel images, malformed input and metadata/codec disagreement. Qualify any format rejected by ImageIO.
5. Compare BGRA allocation/copy counts, store queue wait and release p50/p95/p99, peak live payload/RSS, CPU and energy against B01. Include three large iPad frames, near-full image storage, background/suspend/resume and simultaneous consumers. Report measured tradeoffs before claiming a speedup or changing the published limits.

Next planned group: **B03 — OCR cache/pixel budgets**. Build reports do not replace device acceptance.
