# License Rootfull - Phase 1

## Trang thai

Phase 1 tich hop shared verifier vao runtime rootfull o che do quan sat.
Verifier doc va xac minh signed lease that, nhung dispatcher chua goi
`TLinkLicenseFeatureAllowed()`. Vi vay:

- `runtime_gate_active=0`.
- Automation, H264, script va shell van hoat dong nhu ban rootfull cu.
- Build `enforced` co verifier enforcement state that trong diagnostics, nhung
  chua duoc coi la ban license-enforced cho den cac phase gate.

## Thanh phan da tich hop

- `tlinkautod` va `tlinkautob` link `shared/TLinkLicenseVerifier.mm`.
- `pccontrol.dylib` link verifier de task `60` doc cung signed lease.
- Verifier ho tro ca:
  - `com.tlinkauto.tlinkauto` / `/Applications/TLinkauto.app`.
  - `com.tlinkauto.streamcontrol` / `StreamControl.app`.
- Rootfull package chua public `LicenseConfig.plist` vao `TLinkauto.app`.
- Workflow build van tach `observe` va `enforced`, validate public config,
  compile marker, verifier evidence va secret leakage.

## Diagnostics

- `60`: JSON base64 cu, them full verifier status trong object `license`.
- `75`: JSON base64 cua shared verifier, them phase, generation va gate status.
- `76reload`: invalidate cache trong `tlinkautod`.
- `76`: tang generation va invalidate cache.
- `97`: capability summary co state/config/generation/build mode.

Task `75` co the decode tren PowerShell:

```powershell
$raw = Invoke-TLinkTask -HostIP $iphoneIP -Task "75"
$b64 = ($raw -split ";;", 2)[1].Trim()
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) |
  ConvertFrom-Json
```

Ket qua fresh install Phase 1 du kien:

- `configured=true`.
- `state=not_activated` neu chua co lease.
- `rootfull_license_phase=1`.
- `runtime_gate_active=false`.
- `enforcement_scope=observe_verifier_no_runtime_gate`.

## Gioi han co chu dich

- App rootfull chua co activation/refresh/deactivate UI; muc nay thuoc Phase 2.
- Task-feature gate, H264 gate, JS helper gate va UI preflight chua bat.
- Khong dung diagnostics `effective_access` de ket luan automation da bi chan;
  phai doc them `runtime_gate_active`.
- Client authentication cho port `6000/7001-7006` va OLLVM van de sau.

## Kiem tra

```sh
node scripts/check-rootfull-license-phase0.mjs
node scripts/check-rootfull-license-phase1.mjs
node --check scripts/validate-rootfull-license-phase1-artifact.mjs
```

Inventory Phase 1 nam tai `license-rootfull-integration.json`.

Sau khi cai goi rootfull len thiet bi, chay device probe:

```powershell
.\scripts\Test-TLinkRootfullLicensePhase1.ps1 `
  -HostIP "192.168.1.244" `
  -ExpectedMode observe `
  -ExpectedState not_activated
```

Probe kiem tra task `97`, giai ma task `75`, xac nhan runtime gate van tat,
sau do kiem tra ca generation advance va cache reload cua task `76`.
