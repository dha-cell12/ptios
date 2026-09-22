# Deploy TLinkauto License Worker lên Cloudflare bằng API token

Tài liệu này dành cho PowerShell trên Windows và đúng với Worker nằm trong
`license-worker/` của repository này. Kết quả cuối cùng gồm:

- Worker `tlinkauto-license` chạy trên `workers.dev`;
- D1 database `tlinkauto-license` được bind vào biến `DB`;
- ba secret `LICENSE_SIGNING_PRIVATE_JWK`, `ADMIN_TOKEN` và
  `DEVICE_ID_PEPPER`;
- schema và toàn bộ D1 migration được áp dụng;
- endpoint, public signing key và trang quản trị được kiểm tra sau deploy.

Không đưa API token, private JWK, admin token hoặc device pepper vào Git,
`wrangler.jsonc`, ảnh chụp màn hình hay command history.

## 1. Điều kiện ban đầu

Chuẩn bị:

- tài khoản Cloudflare có quyền quản lý Workers và D1;
- Windows 11 và Node.js 20 hoặc 22;
- repository đã được tải về máy;
- một password manager để giữ các secret;
- quyền sửa `stream-app/app/LicenseConfig.plist` trước khi build ứng dụng.

Mở PowerShell tại root của repository:

```powershell
Set-Location 'C:\Users\admin\OneDrive\Documents\GitHub\ptios'
node --version
npm --version
```

Cloudflare khuyến nghị cài Wrangler trong project thay vì cài global. Project
này đã khai báo Wrangler trong `devDependencies`, vì vậy chỉ cần:

```powershell
Set-Location '.\license-worker'
npm install
npx wrangler --version
```

Tài liệu chính thức: [Install/Update Wrangler](https://developers.cloudflare.com/workers/wrangler/install-and-update/).

## 2. Tạo Cloudflare API token

### 2.1 Lấy Account ID

Trong Cloudflare Dashboard:

1. Chọn account cần deploy.
2. Mở trang **Workers & Pages** hoặc trang tổng quan account.
3. Sao chép **Account ID** ở phần account details.

Account ID là chuỗi định danh account, không phải API token và không phải D1
database ID.

### 2.2 Tạo token trong Dashboard

Vào **My Profile → API Tokens → Create Token → Create Custom Token**. Nếu sử
dụng Account API Token, vào **Manage Account → API Tokens**.

Đặt tên dễ nhận biết, ví dụ `tlinkauto-license-wrangler-production`.

Cho lần tạo mới hoàn toàn, token cần các quyền sau trên đúng account:

| Phạm vi | Quyền | Lý do |
|---|---|---|
| Account/Workers | Workers Admin, hoặc nhãn cũ `Workers Scripts: Edit` | Tạo và deploy Worker mới |
| Account/D1 | `D1: Write` hoặc nhãn cũ `D1: Edit` | Tạo database, chạy schema và migration |
| Account | `Account Settings: Read` | Để Wrangler nhận diện account |
| User | `User Details: Read`, `Memberships: Read` nếu giao diện token yêu cầu | Hỗ trợ nhận diện account của user token |

Nếu Worker đã tồn tại, các lần deploy sau chỉ cần Workers Editor trên Worker
đó. Tạo Worker mới cần quyền Workers Admin ở product scope. Vì cấu hình hiện
dùng `workers_dev: true`, không cần quyền Zone/Workers Routes. Chỉ thêm
`Zone → Workers Routes: Write` khi bạn tự cấu hình route hoặc custom domain.

Ở **Account Resources**, chọn đúng một account thay vì tất cả account. Có thể
thêm giới hạn IP và thời hạn token nếu máy deploy có IP ổn định.

Chọn **Continue to summary → Create Token**, sau đó sao chép token ngay. Secret
của token chỉ hiển thị một lần. Xem thêm:

- [Create API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
- [Workers roles and permissions](https://developers.cloudflare.com/workers/authorization/)
- [API token permissions](https://developers.cloudflare.com/fundamentals/api/reference/permissions/)

## 3. Nạp API token vào phiên PowerShell

Không ghi token trực tiếp trong câu lệnh. Dùng prompt ẩn:

```powershell
$cfTokenSecure = Read-Host 'Cloudflare API token' -AsSecureString
$env:CLOUDFLARE_API_TOKEN = [System.Net.NetworkCredential]::new('', $cfTokenSecure).Password
$env:CLOUDFLARE_ACCOUNT_ID = Read-Host 'Cloudflare Account ID'
```

Xác minh token và account:

```powershell
npx wrangler whoami
$verifyHeaders = @{ Authorization = "Bearer $env:CLOUDFLARE_API_TOKEN" }
Invoke-RestMethod 'https://api.cloudflare.com/client/v4/user/tokens/verify' -Headers $verifyHeaders
```

Kết quả API phải có `success: true` và `status: active`. Với một số Account API
Token, `wrangler whoami` là phép kiểm tra đáng tin cậy hơn endpoint user token.

Nếu Wrangler báo nhiều account, giữ nguyên
`CLOUDFLARE_ACCOUNT_ID` để ép mọi thao tác vào đúng account.

## 4. Kiểm tra source trước khi deploy

Chạy từ thư mục `license-worker`:

```powershell
npm run check
npm test
npx wrangler deploy --dry-run --outdir .wrangler-dry-run
```

Phải đạt toàn bộ test và dry-run. Không tiếp tục nếu Worker không nhận binding
`env.DB` hoặc dry-run báo lỗi cấu hình.

Sau khi kiểm tra, có thể xóa đúng thư mục output tạm:

```powershell
$dryRunPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) '.wrangler-dry-run'))
if ((Split-Path -Leaf $dryRunPath) -eq '.wrangler-dry-run' -and (Test-Path -LiteralPath $dryRunPath)) {
    Remove-Item -LiteralPath $dryRunPath -Recurse -Force
}
```

## 5. Tạo hoặc xác nhận D1 database

### 5.1 Kiểm tra database hiện có

Repository hiện cấu hình:

- binding: `DB`;
- database name: `tlinkauto-license`;
- database ID nằm trong `license-worker/wrangler.jsonc`.

Không mặc định rằng ID đang có thuộc account của bạn. Kiểm tra:

```powershell
npx wrangler d1 list
npx wrangler d1 info tlinkauto-license
```

Nếu lệnh `info` thành công và ID trùng `wrangler.jsonc`, chuyển sang mục 5.3.

### 5.2 Tạo database mới

Nếu database chưa tồn tại:

```powershell
npx wrangler d1 create tlinkauto-license --location apac
```

Wrangler sẽ in `database_id`. Mở `license-worker/wrangler.jsonc`, giữ nguyên
`binding: "DB"` và `database_name: "tlinkauto-license"`, rồi thay
`database_id` bằng ID vừa nhận.

Kiểm tra lại:

```powershell
npx wrangler d1 info tlinkauto-license
```

Tài liệu chính thức: [D1 create/info/list](https://developers.cloudflare.com/workers/wrangler/commands/d1/).

### 5.3 Khởi tạo schema và chạy migrations

`schema.sql` là baseline. Các thay đổi tăng dần nằm trong `migrations/`. Chạy
theo đúng thứ tự:

```powershell
npm run db:init:remote
npx wrangler d1 migrations list tlinkauto-license --remote
npx wrangler d1 migrations apply tlinkauto-license --remote
```

Khi Wrangler hỏi xác nhận migration, đọc đúng tên database và chọn `Yes`.
Cloudflare tạo backup khi áp migration; nếu một migration lỗi, migration đó
được rollback còn các migration thành công trước đó vẫn được giữ lại.

Kiểm tra các bảng quan trọng:

```powershell
npx wrangler d1 execute tlinkauto-license --remote --command "SELECT name FROM sqlite_schema WHERE type='table' ORDER BY name;"
npx wrangler d1 execute tlinkauto-license --remote --command "PRAGMA table_info(devices);"
npx wrangler d1 execute tlinkauto-license --remote --command "PRAGMA table_info(physical_devices);"
```

Phải thấy ít nhất `licenses`, `devices`, `activation_challenges`,
`physical_devices` và `license_device_events`. Xem thêm
[D1 migration commands](https://developers.cloudflare.com/d1/wrangler-commands/).

Nếu database cũ đã có cột của migration nhưng Wrangler vẫn coi migration là
chưa chạy, dừng lại và sao lưu/đối chiếu schema. Không tự sửa bảng migration
của Cloudflare và không xóa database production để “làm lại”.

## 6. Tạo signing key và cấu hình public key cho ứng dụng

Chạy:

```powershell
npm run keys
```

Lệnh in ra:

- private JWK dùng làm Worker secret `LICENSE_SIGNING_PRIVATE_JWK`;
- `LicensePublicKeyX`;
- `LicensePublicKeyY`.

Lưu private JWK trong password manager. Không commit private JWK. Điền hai giá
trị public `x`, `y` vào cả hai tệp:

```text
stream-app/app/LicenseConfig.plist
TLinkauto/TLinkauto/LicenseConfig.plist
```

Đảm bảo `LicenseKeyID` trong plist bằng `LICENSE_KEY_ID` trong
`license-worker/wrangler.jsonc`. Hiện cả hai nên dùng cùng một ID.

Không rotate signing key riêng lẻ trên Worker: ứng dụng chỉ chấp nhận lease
được ký bằng public key đã đóng gói trong app. Muốn rotate phải phát hành app
chứa public key mới theo một kế hoạch chuyển tiếp.

## 7. Tạo ADMIN_TOKEN và DEVICE_ID_PEPPER

Tạo hai chuỗi ngẫu nhiên khác nhau. Pepper phải được giữ cố định; rotate pepper
sẽ làm toàn bộ hardware fingerprint cũ không còn match.

```powershell
function New-Base64UrlSecret([int]$ByteCount = 48) {
    $bytes = [byte[]]::new($ByteCount)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

$adminToken = New-Base64UrlSecret 48
$devicePepper = New-Base64UrlSecret 64
```

Lưu cả hai vào password manager:

- `$adminToken` là mật khẩu truy cập `/admin` và Bearer token cho Admin API;
- `$devicePepper` chỉ dùng làm Worker secret, không đưa vào app/client.

Có thể chuyển từng giá trị qua clipboard rồi xóa clipboard ngay sau khi lưu:

```powershell
Set-Clipboard -Value $adminToken
# Paste vào password manager, sau đó tiếp tục:
Set-Clipboard -Value $devicePepper
# Paste vào password manager, sau đó xóa clipboard:
Set-Clipboard -Value ''
```

## 8. Chọn policy rollout trước deploy

Trong `license-worker/wrangler.jsonc`:

```json
"HARDWARE_POLICY_MODE": "observe",
"HARDWARE_POLICY_VERSION": "1",
"ALLOW_LEGACY_DEVICE_PROOF": "false"
```

Khuyến nghị lần đầu:

- giữ `HARDWARE_POLICY_MODE=observe` để ghi nhận risk mà chưa chặn nhầm;
- nếu đang có app rootfull/TrollStore phiên bản cũ ngoài thực tế, tạm đổi
  `ALLOW_LEGACY_DEVICE_PROOF=true`;
- nếu chưa có client cũ, giữ legacy là `false`.

Sau khi client mới đã được phát hành hết, đổi legacy về `false` và deploy lại.
Chỉ chuyển hardware policy sang `enforce` sau khi đã xem dữ liệu thực tế trên
các phiên bản iOS hỗ trợ.

## 9. Deploy lần đầu cùng ba secret

Để không tạo một deployment trung gian thiếu secret, dùng
`wrangler deploy --secrets-file` với file JSON tạm nằm ngoài repository.

Đầu tiên, copy private JWK từ password manager vào biến bằng prompt. Vì JWK là
JSON một dòng, `Read-Host` phù hợp:

```powershell
$privateJwkSecure = Read-Host 'Paste LICENSE_SIGNING_PRIVATE_JWK (one-line JSON)' -AsSecureString
$privateJwk = [System.Net.NetworkCredential]::new('', $privateJwkSecure).Password
```

Tạo file tạm, deploy và luôn xóa file trong `finally`:

```powershell
$secretPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tlinkauto-worker-secrets-" + [guid]::NewGuid().ToString('N') + '.json')
$secretPayload = @{
    LICENSE_SIGNING_PRIVATE_JWK = $privateJwk
    ADMIN_TOKEN = $adminToken
    DEVICE_ID_PEPPER = $devicePepper
} | ConvertTo-Json -Compress

[System.IO.File]::WriteAllText(
    $secretPath,
    $secretPayload,
    [System.Text.UTF8Encoding]::new($false)
)

try {
    npx wrangler deploy --secrets-file $secretPath
    if ($LASTEXITCODE -ne 0) { throw "wrangler_deploy_failed exit=$LASTEXITCODE" }
}
finally {
    if (Test-Path -LiteralPath $secretPath) {
        Remove-Item -LiteralPath $secretPath -Force
    }
    $secretPayload = $null
    $privateJwk = $null
    $privateJwkSecure = $null
    $devicePepper = $null
}
```

Wrangler sẽ in URL dạng:

```text
https://tlinkauto-license.<workers-subdomain>.workers.dev
```

Ghi lại URL đó. Cloudflare lưu secret ở dạng không thể đọc ngược qua Dashboard
hoặc Wrangler. Tài liệu:
[Workers secrets](https://developers.cloudflare.com/workers/configuration/secrets/).

### Cập nhật secret sau khi Worker đã tồn tại

Sau lần đầu, có thể cập nhật từng secret bằng prompt ẩn của Wrangler:

```powershell
npx wrangler secret put ADMIN_TOKEN
npx wrangler secret put DEVICE_ID_PEPPER
npx wrangler secret put LICENSE_SIGNING_PRIVATE_JWK
```

Mỗi `secret put` tạo và deploy một Worker version mới. Không rotate signing key
hoặc pepper chỉ để thử lệnh.

## 10. Smoke test deployment

Đặt URL Worker, không có dấu `/` cuối:

```powershell
$licenseBase = 'https://tlinkauto-license.YOUR-SUBDOMAIN.workers.dev'
```

Kiểm tra health, public key và trang admin:

```powershell
$health = Invoke-RestMethod "$licenseBase/v1/health"
$publicKey = Invoke-RestMethod "$licenseBase/v1/public-key"
$adminPage = Invoke-WebRequest "$licenseBase/admin"

$health | ConvertTo-Json -Depth 10
$publicKey | ConvertTo-Json -Depth 10
$adminPage.StatusCode
```

Kết quả mong đợi:

- health có `ok=true`, `service=tlinkauto-license`;
- public key có đúng `key_id`, `x`, `y` đã đưa vào app;
- trang admin trả HTTP 200.

Kiểm tra Admin API bằng token đang còn trong `$adminToken`:

```powershell
$adminHeaders = @{
    Authorization = "Bearer $adminToken"
    'Content-Type' = 'application/json'
}

$list = Invoke-RestMethod "$licenseBase/v1/admin/licenses?limit=10&offset=0" -Headers $adminHeaders
$list | ConvertTo-Json -Depth 10
```

Tạo một license test:

```powershell
$testBody = @{
    license_key = 'TLINK-SMOKE-0001'
    max_devices = 1
    features = @('automation', 'stream', 'script', 'admin', 'shell')
} | ConvertTo-Json

$created = Invoke-RestMethod "$licenseBase/v1/admin/licenses" `
    -Method Post `
    -Headers $adminHeaders `
    -Body $testBody

$created | ConvertTo-Json -Depth 10
```

License key rõ chỉ nên được lưu ở hệ thống bán hàng/password manager. D1 chỉ
lưu hash nên không thể lấy lại clear key sau đó.

Xem log request theo thời gian thực:

```powershell
npx wrangler tail tlinkauto-license --format pretty
```

`Ctrl+C` để thoát. Xem thêm
[Real-time logs](https://developers.cloudflare.com/workers/observability/logs/real-time-logs/).

## 11. Cấu hình endpoint cho rootfull và TrollStore

Trong cả `stream-app/app/LicenseConfig.plist` (TrollStore) và
`TLinkauto/TLinkauto/LicenseConfig.plist` (rootfull), đặt:

```xml
<key>LicenseEndpoint</key>
<string>https://tlinkauto-license.YOUR-SUBDOMAIN.workers.dev</string>
<key>LicenseKeyID</key>
<string>tlinkauto-test-2026-01</string>
<key>LicensePublicKeyX</key>
<string>PUBLIC_JWK_X</string>
<key>LicensePublicKeyY</key>
<string>PUBLIC_JWK_Y</string>
```

Rootfull và TrollStore cùng dùng `LicenseManager.mm` và hardware collector dùng
chung. Sau khi đổi endpoint/public key phải build và ký lại cả hai artifact.
Nếu build bằng GitHub Actions, cập nhật thêm các repository variables
`TLINK_LICENSE_ENDPOINT`, `TLINK_LICENSE_KEY_ID`, `TLINK_LICENSE_PUBLIC_KEY_X`
và `TLINK_LICENSE_PUBLIC_KEY_Y`. Workflow sẽ đối chiếu các giá trị này trực
tiếp với `/v1/public-key` và dừng build nếu có khóa cũ.
Giữ `LicenseEnforcementEnabled=false` trong lượt smoke test thiết bị đầu tiên;
chỉ bật khi activation, refresh, offline grace và recovery đều đạt.

## 12. Quy trình deploy các lần cập nhật

Secret đang có được giữ nguyên khi chạy `wrangler deploy` thông thường. Mỗi lần
cập nhật:

```powershell
Set-Location 'C:\Users\admin\OneDrive\Documents\GitHub\ptios\license-worker'
npm install
npm run check
npm test
npx wrangler d1 migrations list tlinkauto-license --remote
npx wrangler d1 migrations apply tlinkauto-license --remote
npx wrangler deploy
```

Sau đó chạy lại health/public-key/admin smoke test ở mục 10.

## 13. Deploy bằng GitHub Actions

Workflow `.github/workflows/license-worker.yml` đã chạy validation, áp baseline
schema + migrations, cập nhật secret và deploy.

Tại GitHub repository, mở **Settings → Secrets and variables → Actions** và tạo
các repository/environment secret:

| Tên | Giá trị |
|---|---|
| `CLOUDFLARE_API_TOKEN` | API token tạo ở mục 2 |
| `CLOUDFLARE_ACCOUNT_ID` | Account ID |
| `LICENSE_SIGNING_PRIVATE_JWK` | Private P-256 JWK một dòng |
| `TLINK_LICENSE_ADMIN_TOKEN` | Admin token |
| `TLINK_LICENSE_DEVICE_ID_PEPPER` | Pepper cố định |

Tạo Actions variable:

| Tên | Giá trị |
|---|---|
| `TLINK_LICENSE_ENDPOINT` | URL Worker đầy đủ, không có `/` cuối |

Workflow dùng environment `tlinkauto-license`; nếu repository bật environment
protection, đặt các secret trong đúng environment hoặc bảo đảm chúng được phép
truy cập từ environment đó.

Chạy **Actions → Validate or Deploy License Worker → Run workflow**:

- `deploy=true`;
- `apply_schema=true`.

Lần đầu nên chạy thủ công bằng Wrangler để bạn nhìn rõ Account ID, D1 ID,
public key và URL. Sau đó dùng Actions cho các bản cập nhật lặp lại.

## 14. Rollback và sự cố

### Rollback Worker code

Liệt kê deployment/version rồi rollback:

```powershell
npx wrangler deployments list
npx wrangler versions list
npx wrangler rollback
```

Hoặc chỉ định version ID:

```powershell
npx wrangler rollback VERSION_ID --message 'rollback license worker after failed release'
```

Rollback Worker không rollback D1. Storage và schema thay đổi độc lập với Worker
version. Migration `0003` của dự án là additive nên Worker cũ có thể bỏ qua các
bảng/cột mới, nhưng không được tự động chạy SQL phá hủy để “khớp” code cũ.
Cloudflare lưu tối đa 100 version gần nhất cho rollback. Xem
[Workers rollbacks](https://developers.cloudflare.com/workers/versions-and-deployments/rollbacks/).

### Lỗi thường gặp

| Lỗi | Nguyên nhân thường gặp | Xử lý |
|---|---|---|
| `Authentication error` / `code 10000` | Token sai, hết hạn hoặc chưa nạp env | Nạp lại token bằng prompt, chạy `wrangler whoami` |
| `not authorized` khi deploy | Token thiếu Workers Editor/Admin | Bổ sung đúng quyền và scope account |
| Không tạo/chạy được D1 | Thiếu `D1: Write` hoặc sai Account ID | Kiểm tra token policy và `CLOUDFLARE_ACCOUNT_ID` |
| `d1_binding_missing` | Binding không tên `DB` hoặc D1 ID sai | Sửa `wrangler.jsonc`, chạy `d1 info` |
| `device_id_pepper_missing` | Chưa cấu hình `DEVICE_ID_PEPPER` | Dùng `wrangler secret put DEVICE_ID_PEPPER` |
| `/v1/public-key` trả `internal_error` | Private JWK thiếu/sai JSON | Cập nhật `LICENSE_SIGNING_PRIVATE_JWK` đúng một dòng |
| Admin trả `401 unauthorized` | Bearer token khác `ADMIN_TOKEN` | Dùng lại secret đúng, không dùng Cloudflare API token |
| App báo signature/key mismatch | Public X/Y hoặc key ID trong plist không khớp Worker | So sánh `/v1/public-key` với plist rồi build lại app |
| Migration báo duplicate column | Schema cũ đã sửa tay hoặc migration tracking lệch | Dừng deploy, backup và đối chiếu schema; không xóa production DB |
| Reset cùng máy bị review | Evidence nguồn thiếu/mâu thuẫn hoặc policy enforce quá sớm | Chuyển về `observe`, kiểm tra dashboard/log và test đúng model/iOS |

## 15. Kết thúc phiên deploy an toàn

Xóa secret khỏi biến PowerShell hiện tại:

```powershell
$adminToken = $null
$cfTokenSecure = $null
$verifyHeaders = $null
$adminHeaders = $null
Remove-Item Env:CLOUDFLARE_API_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:CLOUDFLARE_ACCOUNT_ID -ErrorAction SilentlyContinue
```

Cuối cùng kiểm tra:

- file tạm secrets đã bị xóa;
- không có `.env`, `.dev.vars`, file JSON hoặc log chứa secret trong repo;
- `git status` không liệt kê file chứa credential;
- API token được giữ trong password manager và có phạm vi/thời hạn phù hợp;
- `DEVICE_ID_PEPPER` có bản sao lưu an toàn và không bị rotate ngoài kế hoạch.
