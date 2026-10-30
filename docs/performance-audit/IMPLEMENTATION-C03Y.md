# C03y — conditional history permission updates

Date: 2026-10-30 (Asia/Bangkok). Baseline: `0b7887e2`, C03x build passed according to the user. Complete normalized `shared/TLinkRunHistory.mm` SHA-256: `b9aaf589f7a7748775b88df8f81f4d6c96eb25b005e38203ff5913560fe662f3`.
Status: **user reported build `adaf252c` passed before C03z; device metadata/IO qualification pending**.
Finding: **P2-18 repeated directory/permission metadata**, partial improvement.

## Change

Every history entry previously issued chmod/lchown for root/runs/evidence and fchmod/fchown for history.lock even when mode, UID and GID already matched. Repeated status reads could therefore make eight unnecessary permission-update syscalls in addition to the existing validation/IO.

Retain the three directory stat results from the existing complete parent-first preflight in a fixed local array. After all direct directories validate, call chmod only when the full 07777 mode bits differ from 0750; call lchown only when UID or GID differs from 501. No added stat calls, heap cache or persistent permission flag. Creation and directory refusal behavior remain unchanged.

For the regular single-link stable lock, use the pathname metadata already validated after flock against the open descriptor. Call fchmod only for a 0640 mode mismatch and fchown only for UID/GID mismatch. Preserve descriptor targeting, validation-before-permission ordering and best-effort error handling. Failed repairs remain visible as mismatches on later fresh stats and are retried; there is no cached success or new admission requirement. Both shared status and exclusive mutations use the same rules.

This changes only directory/lock permission-update selection. Artifact/screenshot permissions, required writes, marker/recovery, checked reads, events, schema, error fields and SDK behavior remain unchanged. Shared rootfull/roothide and production TrollStore are covered; TouchPOC is excluded.

## Verification

Reverse only the saved directory stat results and four mode/owner predicates, then hash the entire source against the user-passed C03x baseline. Keep all earlier full-source checks. The runtime adapter compiles the actual changed source, preserving real filesystem type/inode/flock checks and controlling only observed mode/UID/GID plus the permission syscalls, as prior fixtures already controlled permission operations.

New Foundation cases cover all 256 mode/owner combinations across three directories and the lock, including set-ID/sticky bits, UID-only/GID-only drift and shared/exclusive acquisition. Require exact repair order and no further calls after controlled successful repair. Change lock metadata immediately after flock to verify selection uses the post-wait observation. Inject failures in directory-mode, directory-owner, descriptor-mode and descriptor-owner updates; preserve admission and retry only still-mismatched operations until success. Compare original public status's eight controlled permission calls with updated status's zero when all metadata is correct; 128 updated snapshots still read persistence. Normal begin/failed finish must retain ACKs without unnecessary admission-permission calls.

The prior 128 stable-inode cases now expect the exact mismatch-derived descriptor call count, retaining identity/resource checks. Existing invalid-directory/link/path-replacement tests still reject before permissions/index IO.

Windows validation passed: all 65 workflow runners (36 source, 29 native), 521 workflow source checks, focused full-source/history guards/contracts, expanded assert preprocessing including the new fixture and `git diff --check`. Sixteen artifact-only checks were skipped. New Foundation/POSIX/ARC/sanitizer execution requires macOS CI.

## Limits and remaining work

The eight-to-zero comparison is an expected controlled syscall count, pending runtime CI; it is not a measured device filesystem/CPU/latency improvement. Fresh stat/identity checks, directory creation probes and full index reads remain. Concurrent actors can still repeat repairs from the same stale observation; arbitrary metadata changes after observation are not made atomic. Permission failures remain best effort as before. Artifact metadata, status caching, log retention, broader recovery/durability and remaining C03/device qualification stay open.
