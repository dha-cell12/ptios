# License Phase 6 Release Gate

Phase 6 separates source/build validation from device evidence. A green GitHub
Actions build is necessary, but it is not sufficient to publish a TrollStore
release candidate.

## CI Artifacts

The StreamControl workflow builds two independent artifacts:

- `StreamControl-tipa-observe`: diagnostics only. Never distribute this build
  as a licensed release.
- `StreamControl-tipa-enforced`: release-candidate input.

Each artifact includes a `license-build-<mode>.json` evidence file. Before
upload, CI checks the bundled `LicenseConfig.plist`, endpoint, key id, P-256
public key coordinates, compile-time mode in all four executables, service v23,
and scans the app for private signing/admin secret markers. The manifest records
SHA-256 hashes for the TIPA, config, app, streamd, clipboardd, and privhelper.

The Worker signing private JWK and admin token belong only to the protected
`tlinkauto-license` deploy environment. They must never be variables, inputs,
logs, or artifacts of the StreamControl build workflow.

## Device Regression

Install the enforced artifact and open StreamControl once. Run:

```powershell
./scripts/Test-TLinkLicensePhase6.ps1 `
  -HostIP "192.168.1.244" `
  -ExpectedMode enforced `
  -ExpectedState valid `
  -RunSafeFeatureProbes
```

The script checks service v23, contract v1, the enforced compile marker, task
`60/75`, task `76reload`, generation stability, and safe policy probes for
automation, script, admin, and shell. It does not respring, clear data, tap the
screen, expose a license key, or call Worker admin endpoints.

For each probe, `allowed` means the request passed the license feature gate;
`operation_success` separately reports whether the safe backend command itself
returned `0;;`. The admin probe intentionally omits a bundle id, so it can prove
the gate without killing an application and normally has
`operation_success=false`.

Repeat the regression for these states and retain the console JSON:

1. Valid lease with all release features.
2. Missing lease: diagnostic tasks work and feature probes are denied.
3. Corrupt/tampered lease: fail closed, quarantine diagnostics exist, port 6000
   stays alive.
4. Device mismatch: repair action is offered; repair restores the same device
   identity without creating another Worker slot.
5. Feature-restricted lease: each absent feature is denied independently.
6. Activate, refresh, deactivate, and re-activate without restarting streamd.

Also test H264, clipboardd/app bridge, a running script, and legacy task 10.
Remove/revoke permission while H264 and a script are active; H264 must close in
about five seconds and the script must stop on its one-second heartbeat.

## Soak Evidence

Run a 24-hour online soak with normal refresh:

```powershell
./scripts/Start-TLinkLicenseSoak.ps1 `
  -HostIP "192.168.1.244" `
  -DurationHours 24 `
  -ExpectedMode enforced `
  -ExpectedState valid
```

Run a 72-hour offline-grace soak using a test lease whose server timings make
the boundary observable during the test:

```powershell
./scripts/Start-TLinkLicenseSoak.ps1 `
  -HostIP "192.168.1.244" `
  -DurationHours 72 `
  -ExpectedMode enforced
```

The JSONL evidence contains timestamps, process id, installed executable path,
service/build versions, state, generation, expiry boundaries, lifecycle state,
and failures. It intentionally excludes license keys, admin tokens, lease
payloads, device public keys, and signatures.

During both windows, cover foreground/background, lock/unlock, network loss,
reboot, and one reinstall/update. Record crash reports, unexpected streamd PID
churn, CPU/battery observations, and Worker request counts beside the JSONL.

## Release Decision

All items below must be true:

- Worker tests, task policy, recovery policy, and release-readiness checks pass.
- Enforced artifact manifest passes and its hashes match the tested TIPA.
- Every process reports `enforced_compile_time_v1`; task 60 reports service 22.
- Device regression passes in valid and fail-closed states.
- 24-hour and 72-hour soak evidence has no unexplained outage or state split.
- No restart streamd workaround is needed after install, activation, repair,
  refresh, deactivate, or reinstall.
- Active script/H264 work stops within the documented enforcement interval.
- Endpoint contract and `license_contract_version=1` are frozen for the RC.

**ROOTFULL BLOCKED:** do not begin the rootfull license implementation until
all device evidence above has been reviewed and the enforced TrollStore release
candidate is accepted.
