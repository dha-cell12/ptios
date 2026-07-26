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

### Tao license test

Khong dat `ADMIN_TOKEN` vao source, workflow variable hoac command history. Tao
key test 7 ngay, mot thiet bi bang PowerShell:

```powershell
$adminToken = Read-Host "Worker ADMIN_TOKEN" -AsSecureString

.\scripts\New-TLinkRootfullTestLicense.ps1 `
  -Endpoint "https://tlinkauto-license.tlinkauto.workers.dev" `
  -AdminToken $adminToken
```

Neu Windows bao `running scripts is disabled`, khong can doi policy toan he
thong. Mo mot process PowerShell tam thoi:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass
```

Sau do chay lai hai lenh tren trong cua so moi.

Script tu sinh key dang `TLINK-ROOTFULL-TEST-*`, bat tat ca feature va in key
mot lan de kich hoat. Co the tao key co ten co dinh:

```powershell
.\scripts\New-TLinkRootfullTestLicense.ps1 `
  -AdminToken $adminToken `
  -LicenseKey "TLINK-ROOTFULL-DEVICE01" `
  -ValidDays 7 `
  -MaxDevices 1
```

Neu Worker tra `license_exists`, doi key moi. Neu can dung lai key cu, vao
dashboard `/admin`, mo license va chon `Reset devices`; khong xoa/sua file
device key tren iPhone de tai su dung slot.

### Kich hoat va probe

1. Cai `.deb`, mo TLinkauto.
2. Vao `Settings -> License`, nhap key vua tao va bam `Activate`.
3. Doi `State` thanh `valid`.
4. Khong restart daemon, chay:

```powershell
.\scripts\Test-TLinkRootfullLicensePhase2.ps1 `
  -HostIP "192.168.1.244" `
  -ExpectedMode enforced `
  -ExpectedState valid
```

Probe so sanh state task `75` va `60`, kiem tra `76reload`, va bao loi neu
runtime gate bi bat som truoc Phase 3.

## Play script trong app rootfull

Task `19` la fire-and-forget. UI chi enqueue script va khong cho `recv`, vi
daemon khong bat buoc gui response cho task nay. Socket UI co timeout 2 giay de
daemon loi khong lam treo giao dien.

Trong `Settings -> Script`:

- Bat `Enable JS Helper Execution` neu `manifest.json` cua script co
  `runtimeLocation: "helper"` hoac `helperRuntimeEnabled: true`.
- Thay doi JS Helper co hieu luc o lan Play tiep theo, khong can respring.
- `Switch App Before Playing` chi quyet dinh co chuyen sang `FrontApp` hay
  khong; day khong phai option bat JavaScript runtime.

JS Helper option duoc luu tai:
`/var/mobile/Library/TLinkauto/config.json`, key
`javascript_helper_runtime_enabled`. Runtime van doc alias cu
`enable_js_helper_execution`, nhung Settings se chuyen sang key canonical khi
luu.

Switch FrontApp duoc luu tai:
`/var/mobile/Library/TLinkauto/config/tweak/config.plist`, key
`switch_app_before_run_script`. App tu tao thu muc config neu chua ton tai.

## Acceptance con lai tren thiet bi

- Fresh activation doi task `75/60` sang `valid` trong toi da 5 giay.
- Airplane mode giu lease den `offline_until`.
- Foreground refresh khong tao duplicate request.
- Network failure khong xoa lease hop le.
- Deactivate giai phong server slot va task `75/60` cung doi state.
