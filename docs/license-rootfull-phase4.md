# License Rootfull - Phase 4

Phase 4 mo rong gate Phase 3 tu request ngan sang cac phien chay dai. Muc
tieu la revoke/expire license co hieu luc ma khong can doi task tiep theo.

## Coverage

- H264 `7001-7006`:
  - Recheck feature `stream` truoc khi chiem single-viewer slot.
  - Recheck moi 5 giay khi stream dang chay.
  - Neu bi deny, shutdown socket va tang `h264_revoked_client_count`.
- Script runtime:
  - Heartbeat feature `script` moi 1 giay.
  - Khi revoke, cancel session, goi `requestStop`, danh thuc `sleep` va ghi
    `license_revoked_during_execution`.
  - Raw runtime thoat loop va dong `FILE *`.
  - JavaScript runtime tu release frame/image/file handles trong cleanup.
- Scheduler:
  - Timer recheck license ngay truoc `playScript`.
  - Autolaunch hien tai chi luu cau hinh; moi launcher sau nay phai goi
    `TLinkSchedulerScriptLaunchAllowed`.
- `tlinkauto-jsd`:
  - Link shared signed-lease verifier va policy.
  - Gate ca direct start va socket start.
  - Heartbeat 1 giay tu cancel JavaScriptCore watchdog, danh thuc sleep/RPC
    wait va dong file handles trong `finally`.

Observe build van di qua cung code path nhung verifier cho phep. Enforced
build fail closed khi lease/feature khong hop le.

## Diagnostics

- Task `97`: `license_phase=4`, `gateScope=task_and_long_running_component`.
- Task `75`: trang thai daemon va co bat cac component gate.
- Task `60`: them counter H264, heartbeat script va scheduler diagnostics.
- Log marker:
  - `active client closed by license`
  - `license_revoked_during_execution`
  - `scheduler launch blocked by license`

## Smoke test

```powershell
.\scripts\Test-TLinkRootfullLicensePhase4.ps1 `
  -HostIP "192.168.1.244" `
  -ExpectedMode enforced `
  -ExpectedState valid `
  -ExpectedAccess allowed
```

Test H264 khi khong co viewer khac:

```powershell
.\scripts\Test-TLinkRootfullLicensePhase4.ps1 `
  -HostIP "192.168.1.244" `
  -ExpectedMode enforced `
  -ExpectedState valid `
  -ExpectedAccess allowed `
  -ProbeH264
```

Test heartbeat bang script co `sleep(30000)`:

```powershell
.\scripts\Test-TLinkRootfullLicensePhase4.ps1 `
  -HostIP "192.168.1.244" `
  -ExpectedMode enforced `
  -ExpectedState valid `
  -ExpectedAccess allowed `
  -LongRunningScriptBundlePath "/var/mobile/Library/TLinkauto/scripts/License Heartbeat.tl"
```

## Test revoke dang chay

1. Chay script `sleep(30000)` va mo mot H264 viewer.
2. Deactivate license trong app hoac revoke tren Worker, sau do Refresh Lease.
3. Script phai dung trong khoang 1 giay; task `60` co
   `revoked_current_run=true` va last error chua
   `license_revoked_during_execution`.
4. H264 socket phai dong trong toi da 5 giay; task `60` tang
   `h264_revoked_client_count`.
5. Timer fire sau revoke khong duoc goi `playScript`; diagnostics scheduler
   tang `denied_count`.

Neu chi sua file lease bang shell, goi task `76reload` de cac process bo cache.

## Phase 5

Phase 5 da them visibility/UX theo feature, memory snapshot va latency metrics.
Backend Phase 4 van la authority va khong phu thuoc UI. Xem
`docs/license-rootfull-phase5.md`.
