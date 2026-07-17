# Ke Hoach Hoan Thien License TrollStore

## Trang thai trien khai

- Phase 0: **da trien khai**. Contract v1, task/component inventory explicit,
  fail-closed policy va CI checker nam trong `license-task-policy.json`,
  `docs/license-task-policy.md` va `scripts/check-license-task-policy.mjs`.
- Phase 1: **da trien khai**. Worker co validation, challenge one-time,
  deactivate/reactivate, reset coherent, admin update, stable JSON errors va
  test lifecycle doc lap. Con device smoke test tren Worker da deploy truoc khi
  chuyen sang Phase 2.
- Phase 2-6: chua trien khai trong dot nay.

## 1. Muc tieu

Hoan thien license cho `StreamControl.app` va toan bo runtime TrollStore den
muc co the bat enforcement mac dinh, van khoi phuc duoc khi license/network co
su co, va co regression test day du truoc khi bat dau port license sang
rootfull.

Thu tu bat buoc:

1. Hoan thien va on dinh TrollStore.
2. Chay device soak test va dong bang protocol license.
3. Chi sau khi dat release gate moi lap ke hoach/implement rootfull.

## 2. Pham vi tam hoan

Nhung hang muc sau van duoc ghi trong threat model nhung **khong chan ban
TrollStore license MVP nay**:

- Hardening rui ro lo Worker signing private key hoac `ADMIN_TOKEN` ngoai cac
  bien phap secret co ban dang co.
- Pairing/xac thuc client rieng cho port `6000` va `7001-7006`.
- Tich hop license vao backend rootfull.
- OLLVM, anti-debug, anti-hook va binary integrity hardening.

Khong xoa cac gate hoac secret hygiene hien co. Chi tam hoan phan hardening mo
rong de tranh tron pham vi trong luc lifecycle TrollStore chua on dinh.

## 3. Baseline da co

- Worker co challenge, activation, device limit, signed lease, refresh, revoke
  va reset devices.
- App tao P-256 device key, uu tien Secure Enclave va co Keychain fallback.
- Shared verifier kiem tra Worker signature, `key_id`, product/version,
  device-key hash, private-key possession va lease dates.
- Compile-time enforcement co the ep bang
  `TLINK_LICENSE_FORCE_ENFORCEMENT=1`.
- Task server, legacy touch, H264 accept, clipboardd, app-side bridge va
  privhelper da co gate.
- Task `75/76`, task `60/97` va Settings > License da co chan doan co ban.
- App update co service version/path recovery de thay `streamd` cu.

## 4. Definition of Done

License TrollStore duoc coi la hoan thanh khi:

- Fresh install khong license chi cho phep UI kich hoat va task chan doan.
- Activation hop le mo dung feature ma khong can restart `streamd` thu cong.
- Lease tu refresh khi app foreground va thu refresh bang BGTask best effort.
- Network failure khong xoa lease dang con offline grace.
- Lease het grace, sai device, sai chu ky, revoke hoac thieu feature deu chan
  dung app/task/stream/helper.
- Moi process nhan thay lease generation moi trong vai giay, khong phu thuoc
  restart app.
- H264 session va script dang chay dung trong thoi gian gioi han khi license
  mat quyen.
- Deactivate thiet bi giai phong device slot va cho phep kich hoat lai hop le.
- Worker co automated tests cho lifecycle va race/coherence quan trong.
- Device regression matrix chay dat sau reboot, reinstall va 72 gio soak test.
- Build release bao `enforcement_enabled=true` va khong co duong observe mode
  do plist.

## 5. Phase 0 - Dong bang contract va inventory

### Cong viec

- Lap bang duy nhat cho tat ca task TrollStore:
  `task id -> feature -> exempt/non-exempt -> component`.
- Chot feature hien tai: `automation`, `stream`, `script`, `admin`, `shell`.
- Chot state/error contract:
  `not_configured`, `not_activated`, `valid`, `offline_grace`,
  `not_yet_valid`, `expired`, `device_mismatch`, `invalid`.
- Chot response deny:
  `-1;;license_required component/task feature state error`.
- Ghi ro task exempt chi gom `60`, `75`, `76`, `96`, `97`, `99`.
- Them `license_contract_version=1` vao task `60/75/97` va Worker lease.

### Acceptance

- Khong con task/bridge nao khong co policy ro rang.
- CI fail neu them task dispatch moi ma khong cap nhat policy inventory.
- Protocol task cu khong thay doi response thanh cong.

## 6. Phase 1 - Worker lifecycle correctness

### Cong viec

- Tach validation schema cho body cua challenge, activate, refresh va admin.
- Validate allowlist feature, `max_devices`, `expires_at`, key/JWK length va
  kieu du lieu truoc D1.
- Lam activation challenge thanh one-time consume an toan; don challenge het
  han.
- Sua semantics `reset-devices`:
  - Device cu bi revoke phai giai phong active slot.
  - Cung device key co the re-activate sau reset khi proof hop le.
- Them `/v1/deactivate`:
  - Can signed lease va device signature.
  - Revoke dung device hien tai va giai phong slot.
- Them admin update toi thieu cho `status`, `expires_at`, `max_devices` va
  `features`; khong can sua D1 thu cong khi test.
- Chuan hoa HTTP/error JSON de app phan biet network, invalid key,
  device-limit, revoked va expired.
- Bao dam refresh khong cap lease neu license/device D1 khong con active.

### Automated tests

- Them test runner Worker voi D1 local/Miniflare hoac Workers test pool.
- Test create -> challenge -> activate -> refresh.
- Test challenge het han, reused challenge va signature sai.
- Test device limit voi hai key.
- Test revoke license va revoke/reset/deactivate device.
- Test re-activate cung key sau reset.
- Test update features/expiry duoc phan anh trong lease refresh moi.

### Acceptance

- `npm test` chay doc lap, khong can Worker production.
- Moi endpoint lifecycle co positive va negative tests.
- Migration D1 idempotent va duoc kiem tra trong GitHub Actions.

## 7. Phase 2 - App license lifecycle tu dong

### Cong viec

- Tao `LicenseLifecycleCoordinator` thuoc AppDelegate, khong dat logic network
  trong view controller.
- Foreground policy:
  - Khong lease: khong request ngam; UI hien Activate.
  - `valid` va con duoi 6 gio: refresh async.
  - `offline_grace`: thu refresh ngay.
  - `expired/invalid/device_mismatch`: khong lap request vo han; hien action
    phu hop.
- Them single-flight lock de launch/active/BGTask khong refresh trung lap.
- Them exponential backoff co gioi han va jitter; reset backoff khi thanh cong.
- Persist diagnostics:
  `last_attempt`, `last_success`, `next_attempt`, HTTP/error va trigger.
- BGTask refresh license neu can, sau do moi ensure service; khong coi BGTask la
  lich chinh xac vi iOS co the khong chay.
- Khong xoa/ghi de lease hop le khi request network that bai.
- Sau activation/refresh/deactivate/remove, phat global license-change signal.

### UI

- Hien state, feature, expire, offline grace countdown va last refresh.
- Disable action trung lap khi request dang chay.
- Doi `Remove Local Lease` thanh action ky thuat ro rang; them
  `Deactivate This Device` rieng co confirmation.
- Khi enforcement deny, nut Play va cac lenh chinh hien ly do, nhung backend
  van la diem enforcement cuoi cung.
- Khong bat nguoi dung restart `streamd` sau activation/refresh.

### Acceptance

- Activation tren fresh install mo task trong toi da 5 giay.
- Foreground refresh va BGTask refresh khong tao duplicate request.
- Airplane mode van su dung duoc lease den `offline_until`.
- Reconnect network refresh thanh cong ma khong can mo License screen.

## 8. Phase 3 - Dong bo cache va state giua process

### Cong viec

- Tao file generation atomically, vi du
  `/var/mobile/Library/TLinkauto/license/generation`.
- Moi lan save/remove/deactivate lease:
  - Tang generation.
  - Invalidate cache app.
  - Gui Darwin notification best effort.
- Shared verifier luu generation kem cache; neu generation doi thi bo cache
  ngay, khong doi TTL 5 giay.
- `streamd`, clipboardd va app bridge lang nghe notification hoac kiem tra
  generation tai diem request.
- `privhelper` la process ngan nen luon doc state moi cho moi invocation.
- Task `76` tang/nap lai generation va tra generation cua `streamd`.
- Task `60/75` tra `license_generation`, `last_checked_at` va source.

### Acceptance

- Activate/remove lease trong app lam task 6000 doi state ma khong restart.
- Clipboard/H264/helper thay state moi trong toi da 2 giay.
- Sua lease file truc tiep khong duoc cache che qua thoi gian quy dinh.

## 9. Phase 4 - Enforcement coverage va long-running work

### Task server

- Chuyen `TLinkLicenseFeatureForTask` sang policy table explicit.
- Task khong co policy phai fail CI/build test, khong ngam map automation.
- Giu task diagnostic exempt nhung dam bao khong cho phep automation.
- Task `10` van fire-and-forget; log counter `license_drop_count` de chan doan.

### H264

- Gate luc accept nhu hien tai.
- Recheck `stream` feature dinh ky trong stream loop, vi du moi 5 giay.
- Dong active client ro rang khi lease het grace/mat feature.

### Script va scheduler

- Gate truoc khi start script.
- Recheck theo heartbeat trong script runtime.
- Khi mat `script`/effective access: set stopRequested, dong file handles va log
  `license_revoked_during_execution`.
- Scheduler khong auto-start script khi license khong hop le.

### Helper va bridge

- Kiem tra tung command privhelper tai diem dispatch nhay cam.
- Clipboardd va app OCR/clipboard bridge recheck generation truoc xu ly.
- Respring, clear data, kill app can `admin`; shell can ca feature `shell` va
  local setting.

### Acceptance

- Khong co component nao chi dua vao UI gate.
- Remove/revoke lease dung script va H264 active trong thoi gian gioi han.
- Feature matrix test chung minh automation license khong mo admin/shell.

## 10. Phase 5 - Recovery, reinstall va device lifecycle

### Cong viec

- Fresh install: service chay, diagnostics mo, core task deny cho toi activation.
- App update: giu Keychain private key va lease; thay daemon cu theo service
  version/path; verifier nap config bundle moi.
- Reboot: neu service khoi dong lai, enforcement co hieu luc truoc task dau
  tien; khong co cua so allow trong luc config chua nap.
- Erase/restore/new device key: UI bao device limit va huong dan reset/deactivate,
  khong tu dong xoa device server.
- Public-key file mat nhung private key con: activation co the tai tao public
  file va re-enroll an toan.
- Lease hong: quarantine/ghi diagnostic, khong crash process.
- Clock edge cases: not-before lech nho, expires, offline grace boundary.
  Clock rollback hardening nang cao van de backlog theo pham vi tam hoan.

### Acceptance

- Khong can bam Restart streamd sau install/update/activation.
- Reinstall TIPA khong ton tai dong thoi daemon/config cu.
- Device reset flow co cach phuc hoi duoc kiem thu.

## 11. Phase 6 - CI, device test va rollout

### CI

- Worker unit/integration tests.
- Static policy coverage cho task/component.
- Build hai bien the:
  - Observe chi dung cho diagnostic branch.
  - Enforced dung cho release candidate.
- Sanity check artifact:
  `LicenseConfig.plist`, public key, endpoint, `key_id`, compile force flag va
  service version dong bo.
- Khong upload private signing key/admin token vao artifact/log.

### PowerShell regression

- Decode task `60/75`, force task `76`.
- Test valid, missing lease, tampered signature, device mismatch.
- Test tung feature: automation, stream, script, admin, shell.
- Test app bridge, clipboardd, H264, privhelper va legacy touch.
- Test activate -> refresh -> deactivate -> re-activate.

### Device soak

- 24 gio online voi auto refresh.
- 72 gio offline-grace test voi lease test co thoi gian rut gon neu can.
- Foreground/background, lock screen, reboot va reinstall.
- Script dai + H264 active trong luc remove/revoke/expire lease.
- Theo doi crash, pin, CPU, battery va request count.

### Rollout

1. Internal build enforced, mot test license/mot device.
2. Mo rong 3-5 thiet bi va nhieu iOS version.
3. Dong bang lease contract version 1.
4. Tao release candidate TrollStore.
5. Chi khi tat ca release gate dat moi tao branch/plan rootfull.

## 12. Release gate truoc rootfull

Khong bat dau implementation rootfull neu con bat ky muc nao:

- Can restart streamd de license co hieu luc.
- Auto refresh chua on dinh hoac co duplicate storm.
- App va backend bao state khac nhau.
- H264/script dang chay khong dung khi mat quyen.
- Deactivate/reset device khong phuc hoi duoc.
- Enforced artifact van co process bao `enforcement_enabled=false`.
- Worker lifecycle tests hoac device regression con fail.
- Protocol/error contract con thay doi.

Sau release gate, phase rootfull se tai su dung:

- Shared verifier va lease format v1.
- Worker endpoints va device lifecycle da dong bang.
- Task-feature policy va regression vectors cua TrollStore.
- Response `license_required` giong nhau giua hai runtime.

Rootfull va OLLVM se co ke hoach rieng; khong chen vao cac phase tren.
