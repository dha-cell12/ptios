# Rootfull License Phase 6

Phase 6 is the release-hardening and rollout-evidence phase. It keeps all Phase
3-5 backend gates and adds package/runtime coherence plus a device-signed local
anti-rollback checkpoint.

## Release integrity

Every rootfull process already embeds its compile-time mode. Phase 6 also checks
`/Applications/TLinkauto.app/RootfullLicenseBuild.plist` at runtime:

- phase is `6`
- contract is `1`
- metadata mode matches the binary compile marker
- `LicenseConfig.plist` enforcement matches the compile marker
- enforcement behavior is `task_and_long_running_component_gate`
- release integrity version and anti-rollback policy are recognized

An enforced build fails closed with `license_release_integrity_failed` when this
metadata is missing or incoherent. Observe builds report the problem but keep the
existing observe behavior.

This catches an incomplete update where the app, daemon, SpringBoard tweak or
public config comes from a different release. It is not a cryptographic code
signature replacement and can still be patched by an attacker with full root
control.

## Signed anti-rollback checkpoint

After a signed lease passes server signature, device binding and time checks,
the verifier maintains:

`/var/mobile/Library/TLinkauto/license/trust_checkpoint.plist`

The checkpoint contains the highest accepted `issued_at`, last observed wall
time and system uptime. Its payload is signed with the existing device P-256
private key. Every verifier process validates the signature with
`device_public_key.bin` before trusting it.

Phase 6 rejects:

- a signed lease whose `issued_at` is older than the accepted floor
- a large wall-clock rollback
- a same-boot wall-clock rollback inconsistent with monotonic uptime
- a malformed or modified checkpoint signature

The wall-clock rollback tolerance is 300 seconds. The checkpoint is written on
first use, for a newer lease, after about 60 seconds, or after a reboot. A file
lock serializes updates across the app, daemon, helper and SpringBoard.

A successful online activation or refresh may replace the checkpoint so a
legitimate clock correction can recover. The app first verifies the newly
received signed lease and recreates the checkpoint; if verification fails, it
restores both the previous lease and previous checkpoint. There is no task on
port `6000` that resets the checkpoint directly.

The checkpoint adds no network request. Its verification happens on the
existing local verifier cache-miss path. UI feature checks still use the Phase 5
memory snapshot. The first accepted lease performs one device signature and one
atomic write; later writes are rate-limited.

## Known limit

The signed file detects modification but cannot absolutely prevent a root
attacker from deleting the checkpoint and all related local evidence. Deletion
recreates the floor from the next valid lease. Closing that gap requires a
server-side monotonic lease epoch or additional protected state; it is tracked
for Phase 7.

## Device regression

```powershell
.\scripts\Test-TLinkRootfullLicensePhase6.ps1 `
  -HostIP "192.168.1.244" `
  -ExpectedMode enforced `
  -ExpectedState valid `
  -ExpectedAccess allowed `
  -RunSafeFeatureProbes `
  -PerformanceProbeCount 100 `
  -EnforcePerformanceBudget
```

The test checks daemon/SpringBoard phase and build-mode coherence, release
integrity, anti-rollback state, feature gates and Phase 5 latency budgets.

## Manual rollback test

Use a test device and retain both lease versions:

1. Save the current `lease.json` as lease A.
2. Refresh the lease and save the newer file as lease B.
3. Restore lease A and call task `76reload`.
4. Task `75` must report `anti_rollback_failed` with
   `license_lease_rollback_detected`.
5. Restore lease B and call task `76reload`; state must return to `valid`.

Do not delete `trust_checkpoint.plist` during this test because that intentionally
resets the local floor.

## Soak evidence

Run a 24-hour online soak:

```powershell
.\scripts\Start-TLinkRootfullLicensePhase6Soak.ps1 `
  -HostIP "192.168.1.244" `
  -DurationHours 24 `
  -ExpectedMode enforced `
  -ExpectedState valid
```

Run a 72-hour offline-grace soak with a suitable test lease:

```powershell
.\scripts\Start-TLinkRootfullLicensePhase6Soak.ps1 `
  -HostIP "192.168.1.244" `
  -DurationHours 72 `
  -ExpectedMode enforced `
  -ExpectedState offline_grace
```

The JSONL evidence records cross-process state, generation, build markers,
release integrity, anti-rollback and verifier latency. Five consecutive failures
abort the run by default.

## Release criteria

- Both observe and enforced artifacts pass the Phase 6 artifact validator.
- The enforced package is the package used for device regression and soak.
- Valid, missing, expired, tampered, device-mismatch and feature-restricted
  states are tested.
- Active H264 and scripts still stop within their Phase 4 heartbeat windows.
- Phase 5 performance budgets remain acceptable after checkpoint verification.
- The 24-hour and 72-hour JSONL evidence has no unexplained state split.

## Deferred hardening

Selective OLLVM is not enabled in Phase 6. It should be applied only after this
release baseline is stable, beginning with the verifier and execution-point
gates while excluding Objective-C runtime selectors.

Port `6000` and H264 client authentication are also deferred. License verifies
the server device, not the remote controller. Phase 7 should add pairing,
session keys, nonce/counter replay protection and an HMAC-authenticated request
envelope before public-network exposure.
