# C03be — Mixed-limit history projections and shared CI validation

Date: 2026-11-10 (Asia/Bangkok). Baseline: `adbe6b16`; user reported the latest build passed and requested larger implementation batches with less build waiting. Scope: shared rootfull/roothide/production TrollStore history status (P1-48/P1-51) and the two packaging workflows. TouchPOC remains excluded.

## Runtime changes

Reuse an exact-content history memo whenever its newest-first rows completely cover the requested limit. A cached 50-row projection can answer 1/20/50-row requests; a complete three-record history cached by a 20-row request also answers a 50-row request. A partial projection never presents a larger request as complete: that request follows the existing fresh-read/decode/validation/projection path and can replace the memo with a wider prefix.

Select the requested prefix before deep copying. Unrequested rows are not traversed or copied, while every returned array/dictionary remains independently mutable. Retain one bounded frozen graph and byte key, with unchanged 2-MiB/4096-node/128-Ki UTF16/depth-32 eligibility limits. Reject auxiliary offers with inconsistent row/total/limit/failure counts. Allocation, nil and NS/C++ copy faults still clear auxiliary state and follow the preceding uncached path.

Every request still performs the complete checked fresh file read under the existing shared file lock. Full byte equality remains necessary; no path/mtime/inode-only hit or stale fallback is introduced. Root metadata and persistence diagnostics stay fresh. History transactions, recovery, retention, authority, public fields and all existing failure envelopes are unchanged. Frozen number/string semantics and detached ownership remain as in C03bd.

This targets mixed callers alternating common status limits. It does not remove IO, the O(encoded-byte) comparison, deep copies of requested rows or cold preparation. A cold larger request still costs a decode, and graph eligibility may prevent caching. Wider cached rows remain retained through smaller requests until replacement/clear, within the same eligibility limits. No device CPU/RSS/latency gain has been measured.

## CI changes

Both workflows now run their complete existing source/native safety block in a dedicated non-matrix `validate` job. Their packaging jobs require its success through `needs: validate`.

The root block retains all 83 direct Node checks; the TrollStore block retains all 75, all source assertions and their original order. These checks do not read matrix-specific TLINK environment variables. With all matrix combinations, shared-check invocations change from `4*83 + 2*75 = 482` to `83 + 75 = 158`, removing 324 repeated invocations (about 67%). This counts direct invocations, not elapsed time, nested test executables or unique suites.

Keep all four rootfull/roothide × observe/enforced builds and both TrollStore license builds. Each variant still configures and verifies its public license inputs, compiles/packages, validates its own artifact and uploads its own output. Theos/SDK setup stays in packaging jobs. TrollStore's moved sanity block requires source files and the host Xcode toolchain, not the downloaded Theos SDK. A validation failure skips every dependent package; the build checks are not optional or cached across runs.

The extra validation-job dispatch can add scheduling overhead, particularly during macOS runner shortages. This change reduces duplicate work and runner consumption; it does not guarantee a particular wall-clock reduction or repair GitHub service errors. Changes to the actual production targets still receive all matrix compile/artifact checks.

## Verification

The focused history runner passes on Windows, including the existing read/storage/recovery/quota/elapsed tests, 100000 node/text/depth oracles and 51510 mixed-limit prefix-selection cases. Selection tests cover complete/partial/empty histories, zero and oversized requests, inconsistent counts and SIZE_MAX without addition overflow. Source reversal retains the complete original history implementation and authority/transaction guards.

The existing macOS Foundation/POSIX/ARC/sanitizer fixture gains 160 mixed-limit comparisons against the complete pre-memo snapshot, expects 320 fresh reads for current plus oracle calls with no additional current decodes, measures smaller deep-copy traversal for a one-row request, and checks partial-to-wider misses, complete small-history reuse, empty histories and inconsistent auxiliary offers. Existing mutation isolation, fresh diagnostics, read/lock/type/corruption faults, copy exceptions and exact uint64/negative-zero/UTF16 lifetime coverage remain. New Apple execution and device qualification require macOS CI.

Compare the complete preceding and current workflow validation blocks and every direct Node command: nothing is removed or reordered inside either block. Compare the entire old packaging job after removing that block with the new packaging job after removing its `needs` gate: all matrix inputs and variant-specific build/artifact steps remain exactly intact. Both workflows pass official actionlint (shellcheck/pyflakes unavailable on this host). All90 local workflow runners have passing results; the initial FileHandle executable-cleanup EPERM required one complete passing rerun without a source change. All521 source assertions, changed-file assertion preprocessing, JavaScript syntax and whitespace checks pass;16 artifact-only checks await CI. Full local regression results are recorded in `STATE.md`.
