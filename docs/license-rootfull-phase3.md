# License Rootfull - Phase 3

Phase 3 bat runtime gate cho task protocol rootfull. App activation/lifecycle
cua Phase 2 duoc giu nguyen; backend moi la diem quyet dinh cuoi cung.

## Coverage

- `tlinkautod` gate request truoc local dispatch hoac IPC sang SpringBoard.
- `pccontrol` gate lai truoc moi task de chan duong IPC/direct call bo qua
  daemon.
- Nut Play trong app preflight feature `script` de hien loi license thay vi
  im lang; backend gate van la authority cuoi cung.
- Bang policy duy nhat nam tai `shared/TLinkRootfullLicensePolicy.mm`; CI doi
  chieu voi `license-rootfull-policy.json`.
- Feature:
  - `automation`: touch, capture, image, OCR, app info va connectivity.
  - `script`: play/stop, scheduler va autolaunch.
  - `admin`: kill app va clear data.
  - `shell`: task `13/71`.
- Task exempt chi gom `60`, `75`, `76`, `96`, `97`, `99`.
- Task co dispatch nhung thieu policy fail closed:
  `-1;;license_policy_missing task=<id>`.

Task `10` la fire-and-forget. Khi bi deny no khong gui response, tang
`task10_license_drop_count` trong task `75/97`. Task khac tra:

```text
-1;;license_required task=<id> feature=<feature> state=<state> error=<error>
```

## Observe va enforced

- Build `observe`: request van di qua bang policy, verifier cho phep de test
  regression khong lam mat chuc nang.
- Build `enforced`: fresh install chua license chi dung duoc diagnostics va
  activation UI. Task thuong bi deny.
- License `valid` chi mo feature co trong signed lease. `automation` khong tu
  mo `admin` hoac `shell`.
- `runtime_gate_active=true` nghia la code gate da duoc lap; xem them
  `enforcement_enabled` de biet build co thuc su deny hay khong.

## Device test

Build enforced chua kich hoat:

```powershell
.\scripts\Test-TLinkRootfullLicensePhase3.ps1 `
  -HostIP "192.168.1.244" `
  -ExpectedMode enforced `
  -ExpectedState not_activated `
  -ExpectedAccess denied
```

Sau khi activate license du feature:

```powershell
.\scripts\Test-TLinkRootfullLicensePhase3.ps1 `
  -HostIP "192.168.1.244" `
  -ExpectedMode enforced `
  -ExpectedState valid `
  -ExpectedAccess allowed
```

Test feature hep, vi du lease khong co `admin` va `shell`:

```powershell
.\scripts\Test-TLinkRootfullLicensePhase3.ps1 `
  -HostIP "192.168.1.244" `
  -ExpectedMode enforced `
  -ExpectedState valid `
  -ExpectedDeniedFeatures admin,shell
```

## Da duoc hoan thanh trong Phase 4

- Gate H264 port `7001-7006` va recheck active stream.
- Script/helper heartbeat de dung session dang chay khi revoke/expire.
- Scheduler/autolaunch launcher recheck.
- Gate helper va cac component privileged ngoai task dispatch.

Chi tiet va huong dan test nam tai `docs/license-rootfull-phase4.md`.
