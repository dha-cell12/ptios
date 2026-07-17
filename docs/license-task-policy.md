# License Task Policy v1

`license-task-policy.json` la inventory duy nhat cho license TrollStore. CI doc
file nay, parse backend Objective-C++ va fail neu dispatch, feature map, exempt
list hoac component gate khong con khop nhau.

## Feature

| Feature | Task |
| --- | --- |
| `automation` | `10-12`, `14-18`, `21-30`, `32-35`, `40`, `42-59`, `61-70`, `90`, `91`, `98` (tru cac task duoc liet ke o feature khac) |
| `script` | `19`, `20`, `36-39`, `41`, `73` |
| `admin` | `31`, `72`, `74` |
| `shell` | `13`, `71` |
| `stream` | H264 accept/stream loop tren `7001-7006`, khong co line task rieng |

Task `10` la legacy fire-and-forget nen co gate rieng trong `POCHandleLine`.
Danh sach chinh xac theo tung ID nam trong `license-task-policy.json`, khong nen
suy dien tu cac range rut gon trong bang nay.

## Exempt

Chi cac task sau khong can lease: `60`, `75`, `76`, `96`, `97`, `99`.
Chung chi phuc vu diagnostics, status, cache invalidation, path/status discovery
va ping. Them task exempt moi la thay doi contract va phai review rieng.

## Component

- `clipboardd`, app OCR bridge va app clipboard bridge can `automation`.
- H264 can `stream`.
- Privhelper open app/URL can `automation`.
- Privhelper kill app, clear data va respring can `admin`.
- Shell task can `shell` va van bi local setting `shell.enabled` gate them.

## Error Contract

- License deny:
  `-1;;license_required task=<id> feature=<feature> state=<state> error=<error>`.
- Component deny:
  `-1;;license_required component=<name> feature=<feature> state=<state> error=<error>`.
- Task co dispatch nhung chua co inventory:
  `-1;;license_policy_missing task=<id>`.
- State v1:
  `not_configured`, `not_activated`, `valid`, `offline_grace`,
  `not_yet_valid`, `expired`, `device_mismatch`, `invalid`.

Success response cua legacy task khong thay doi. Task `60`, `75`, `97` va lease
Worker cong bo `license_contract_version=1`.

Chay policy check thu cong:

```bash
node scripts/check-license-task-policy.mjs
```
