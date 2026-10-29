# C03m — compact run-history index encoding

Date: 2026-10-29 (Asia/Bangkok). Baseline: C03l working source, build passed according to the user. HEAD is still `0c5de74d`; no separate C03k/C03l commit is inferred. Normalized complete history source SHA-256 before this stage: `76ef6fa6e9d4fa9f1a8ac983a6ed69a58f56c425ae2e7c2506b01bb1232355a3`.
Status: **build passed according to the user before C03n (`87aae836`); independent device qualification pending**.
Finding: **P1-48 index encoding/write volume**, a partial optimization without a persistence-schema migration.

## Change

Every begin/finish rewrites the index with up to 50 records and embedded failure evidence. The existing encoder also inserted pretty-print indentation and line breaks. Index bytes are parsed by JSON readers; neither its whitespace nor key ordering is an exposed contract.

The private JSON writer now accepts Foundation writing options, with its original pretty default. Only WriteIndex passes option 0 for compact JSON. Record/evidence writes and recovery serialization retain their pretty format and existing size/comparison rules. Keep JSON validation/serialization, checked atomic NSData write, permissions and ownership in the same helper. No new queue, dependency, cache, output file or API is introduced.

Keep every existing envelope/record/evidence field, timestamp sampling, extension-field handling, failure/diagnostic policy, index commit point, pending marker, finally release, post-commit retirement and event order. Both permissive snapshot and checked mutation readers accept the old pretty and compact encodings. Snapshot never migrates the file. The next successful normal mutation writes compact JSON after the same admission/recovery gates, without a separate rewrite pass. Format compatibility does not permit older writers to ignore C03k's required marker protocol.

Shared rootfull/roothide and production TrollStore use this implementation. TouchPOC remains excluded. The index still embeds evidence and is still fully encoded and rewritten on each mutation; no P1-48 closure or measured device speedup is claimed.

## Verification

The source guard reverses exactly the private options argument, the encoder options selection and the index caller's option 0, then hashes the entire source against the user-passed C03l working baseline. Existing C03l/k/j/i/h hash/frozen-source comparisons remain unchanged. This isolates formatting from the previous commit/recovery/retention implementation.

New actual-source macOS cases compare compact writes with the frozen pretty encoder on the same private root and the same input graphs at 0/1/20/50 runs. Inputs include bounded evidence/error strings, Unicode, escaping, NUL, empty/nested extension values, large integers and fractional numbers. Require equal decoded graphs/status, fewer bytes and no formatting LF in the compact index, unchanged pretty record/evidence artifacts, and both readers consuming the opposite encoding. The current snapshot must not rewrite a pretty index. Finally a cold public begin loads a pretty index, repairs retained artifacts and commits compact JSON, then a warm finish retains the no-rescan fast path, events, clean marker and balanced FDs/flock. The fixture prints encoded byte totals when actually run on macOS; these are fixture data sizes, not device IO measurements.

Existing 75-transaction frozen full-field/status/evidence/retention comparisons and all writer/read/cleanup/recovery/marker fault cases remain. All 65 workflow runners (36 source-contract, 29 native), 521 direct source-grep assertions, expanded standards-conforming assert preprocessing, focused history guards/contracts and git diff --check pass on Windows. Sixteen artifact-only checks require CI outputs. New Foundation/POSIX/ARC/ASan/UBSan execution requires macOS CI.

## Remaining work

Measure first/steady-state CPU, IO, lock hold time, latency and RSS on real rootfull/roothide and TrollStore devices. Removing encoded whitespace does not establish a filesystem write-amplification or latency percentage. Separating index metadata from evidence needs an explicit compatibility/recovery design. Compact history does not add log `_logs` retention, orphan retries, event journal recovery, index reconstruction or fsync/power-loss durability. Other C03/outstanding C02 work remains open.
