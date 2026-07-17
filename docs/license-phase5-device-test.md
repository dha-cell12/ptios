# License Phase 5 Device Test

Run these checks with an enforced build. Keep one valid test license available
and decode task `60/75` Base64 JSON with the existing PowerShell helper.

## Fresh Install

1. Install the TIPA without activating a license and open StreamControl once.
2. Task `97`, `75`, `76`, and `99` must respond. Task `97` must report
   `serviceVersion=22`, `licenseState=not_activated`, and denied access.
3. A core request such as task `25` must return `license_required`, not execute.
4. Activate in `Settings > License`; the same task must work without Restart
   streamd.

## App Update

1. Start with a valid lease and an older `serviceVersion=21` build.
2. Install the v22 TIPA over it and open StreamControl.
3. Task `97` must change to v22. Task `60` must resolve the current installed
   bundle path while retaining the same license/device identity.

## Public-Key Repair

With shell enabled and a valid license:

```powershell
$pub = "/var/mobile/Library/TLinkauto/license/device_public_key.bin"
Invoke-TLinkTask -HostIP $iphoneIP -Task "13printf 'damaged-public-key' > '$pub'"
Invoke-TLinkTask -HostIP $iphoneIP -Task "76"
```

1. Task `75` should report `device_mismatch` and an unavailable device proof.
   The License screen must report the private key as present and recovery action
   `repair_device_public_key`.
2. Open `Settings > License > Repair Device Binding`.
3. Task `75` must become valid again without activation, a new Worker device,
   or restarting streamd.

## Corrupt-Lease Quarantine

With shell enabled and a valid license:

```powershell
$lease = "/var/mobile/Library/TLinkauto/license/lease.json"
Invoke-TLinkTask -HostIP $iphoneIP -Task "13printf '{broken' > '$lease'"
Invoke-TLinkTask -HostIP $iphoneIP -Task "75"
```

1. Task `75` must return a controlled invalid/not-activated result and port
   `6000` must remain alive.
2. `recovery.state` must be `quarantined`; `quarantine_path` must point below
   `/var/mobile/Library/TLinkauto/license/quarantine/`.
3. Reactivate from Settings. The recovery diagnostic clears and access returns
   without Restart streamd.

## Device Limit And Reset

1. Activate a one-device license on device A.
2. Activate the same key on device B. The error must include
   `device_limit_reached`, `active=1`, `max=1`, and recovery guidance.
3. Deactivate A normally, then activate B. It must succeed.
4. Repeat using Worker admin `reset-devices`; B must recover by activation and
   no client may silently delete a server device record.

## Reboot And Boundaries

1. Reboot with a valid lease. Whenever streamd becomes available, its first
   core task must already be gated; there must be no observe-mode startup gap.
2. Reboot with no lease and confirm only diagnostic/exempt tasks work.
3. Test a lease at `expires_at` and `offline_until`: exact boundary remains
   valid, after the boundary follows `offline_grace` then `expired`.
4. A `not_before` difference up to 60 seconds is tolerated and reported as
   `clock_skew_tolerance_seconds=60`; larger future skew is denied.

Immediate pre-unlock/boot startup remains best-effort under TrollStore. This
test validates fail-closed behavior once the service process exists.
