# C06ad — Initial private VPN verification snapshot lifetime

Date: 2026-11-04 (Asia/Bangkok). Baseline: `a872f54a`; user reported C06ac build passed and requested continued implementation. Production TrollStore private legacy VPN creation in the shared manager; TouchPOC excluded.

## Retain the identifiers and count

The pre-create configuration snapshot was retained across creation and verification because its count was read after create and again in the verification-failure reply. This kept the initial array, dictionaries, names and raw identifiers reachable through up to fifty verification attempts/five seconds, although verification only needs the identifier set and initial count.

Build the same identifier set inside a local autorelease pool, capture the initial record count there and let the initial array/record graph drain before name/options preparation and the create call. Keep the set strongly owned outside the pool; identifiers retain their original aliases and membership semantics. Use the scalar for observed-count initialization and the existing profiles_before field. The collector returns a fresh locally owned list, so the initial count remains the same snapshot count rather than a later read of that list.

This removes only this function's surplus snapshot ownership. Identifiers in the set, the old marker, objects retained by the private store and later verification snapshots/selected records remain owned as before. It does not impose a process memory cap or prove lower device RSS. No extra provider call, record cache, polling/backoff change, cancellation, deadline, profile/credential/authority change or public NEVPNManager change is introduced. Create/selection/marker calls remain opaque. Full private enumeration and device qualification remain open; C06/P1-67 stay partial.

## Verification

Freeze the complete preceding C06ac configure function. The new reversal permits exactly the initial pool/scalar substitution and validates the entire preceding manager hash before C06ac/C06s/C06n/C06m/C06l restoration. Existing private-polling runner/workflow wiring is reused; runner count remains 88.

Extend its Foundation/ARC/ASan/UBSan fixture with the complete preceding function alongside current and older verification baselines. Controlled initial snapshots contain a weakly observed array, raw owner and mutable identifier. Compare current/preceding replies, options, read/selection/marker/deletion counts for both store generations and eight success/failure shapes. The old array/raw owner must be alive at create; current must release them before create and every verification read while retaining the identifier alias. Failure cases also verify unchanged initial/observed profile counts.

Other cases cover NS/C++ failures during initial snapshot construction and create, returned result ownership and 128 repeated timed-out verification lifecycles. Clocks/private store/profile effects are controlled; no real VPN configuration is created or removed. Native ownership assertions are CI expectations, not measured device gains.

Windows validation: all **88 workflow runners** (36 source, 52 safety), **521 existing source checks**, complete staged manager hashes, fixture extraction, JavaScript syntax, expanded assert preprocessing and `git diff --check` pass. Existing portable 100k polling-window cases pass. Sixteen artifact-only checks skipped. New Foundation/ARC/sanitizer compilation/execution and iOS builds require macOS CI.
