# License Rootfull - Phase 2

Phase 2 dua signed-license lifecycle vao app rootfull ma chua bat runtime
enforcement. Muc tieu la xac minh activation, renewal va device binding on dinh
tren rootfull truoc khi task gate duoc bat o Phase 3.

## Da trien khai

- App rootfull link cung cac module voi TrollStore:
  - `LicenseManager.mm`.
  - `LicenseLifecycleCoordinator.mm`.
  - `LicenseViewController.mm`.
  - `TLinkLicenseVerifier.mm`.
- Settings co muc `License` de:
  - Activate license key.
  - Refresh signed lease.
  - Xem refresh history va device binding.
  - Deactivate this device.
  - Repair public key hoac remove local lease cho recovery.
- App launch va foreground goi lifecycle coordinator.
- Auto refresh chi chay khi:
  - Lease `valid` con duoi 6 gio.
  - State la `offline_grace`.
- Refresh co single-flight, exponential backoff, jitter va diagnostics tai:
  `/var/mobile/Library/TLinkauto/runtime/license_lifecycle.plist`.
- Sau activate/refresh/deactivate/remove/repair:
  - Generation duoc cap nhat atomically.
  - Shared verifier cache bi invalidate.
  - App gui task `76reload` den `tlinkautod`, retry mot lan neu can.

## Enforcement

Phase 2 van co chu dich:

- `runtime_gate_active=false`.
- `enforcement_scope=activation_lifecycle_observe_no_runtime_gate`.
- Build `enforced` xac minh lease va hien `effective_access`, nhung port `6000`,
  H264, script runtime va helper chua bi chan.
- Task-server gate bat dau o Phase 3 theo `license-rootfull-policy.json`.

Khong dung rieng `effective_access=false` de ket luan automation da bi chan.
Can doc them `runtime_gate_active`.

## Build validation

```sh
node scripts/check-rootfull-license-phase0.mjs
node scripts/check-rootfull-license-phase1.mjs
node scripts/check-rootfull-license-phase2.mjs
node --check scripts/validate-rootfull-license-phase2-artifact.mjs
```

Artifact validator Phase 2 xac nhan app binary co:

- Rootfull compile marker dung mode.
- Shared verifier marker.
- Activation/refresh/deactivate endpoints.
- License UI/lifecycle evidence.
- Khong co private signing key hoac admin token.

## Device validation

1. Cai `.deb`, mo TLinkauto.
2. Vao `Settings -> License`.
3. Activate key va doi state thanh `valid`.
4. Khong restart daemon, chay:

```powershell
.\scripts\Test-TLinkRootfullLicensePhase2.ps1 `
  -HostIP "192.168.1.244" `
  -ExpectedMode enforced `
  -ExpectedState valid
```

Probe so sanh state task `75` va `60`, kiem tra `76reload`, va bao loi neu
runtime gate bi bat som truoc Phase 3.

## Acceptance con lai tren thiet bi

- Fresh activation doi task `75/60` sang `valid` trong toi da 5 giay.
- Airplane mode giu lease den `offline_until`.
- Foreground refresh khong tao duplicate request.
- Network failure khong xoa lease hop le.
- Deactivate giai phong server slot va task `75/60` cung doi state.
