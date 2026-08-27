# Hướng dẫn quản trị License Worker trên site

Tài liệu này dành cho người vận hành dashboard quản lý license tại:

```text
https://YOUR-WORKER/admin
```

Dashboard quản lý license dùng chung cho bản rootfull và TrollStore. Thao tác
trên site thay đổi quyền ở Worker; thiết bị nhận trạng thái mới qua activation
hoặc refresh lease.

## 1. Đăng nhập

1. Mở đúng hostname Worker bằng HTTPS.
2. Nhập secret `ADMIN_TOKEN` đã cấu hình bằng `wrangler secret put` hoặc workflow
   deploy.
3. Nhấn **Connect**.
4. Khi kết thúc, nhấn **Lock** rồi đóng tab.

Token chỉ được giữ trong bộ nhớ của tab. Dashboard không lưu token vào cookie,
`localStorage` hoặc `sessionStorage`. Không đưa token vào repository, app, log,
ảnh chụp màn hình hoặc tin nhắn. Nếu token từng bị lộ, rotate ngay:

```bash
cd license-worker
npx wrangler secret put ADMIN_TOKEN
npm run deploy
```

## 2. Đọc màn hình tổng quan

| Chỉ số | Ý nghĩa |
| --- | --- |
| Total licenses | Tổng số license trong D1. |
| Active | License có status `active` và chưa hết hạn. |
| Revoked | License bị thu hồi thủ công. |
| Expired | License có status `active` nhưng đã qua hạn cố định. |
| Active devices | Tổng binding thiết bị đang chiếm slot. |

Ô tìm kiếm dùng **License ID**, không dùng clear license key. Danh sách hiển thị
tối đa 50 bản ghi mỗi trang. Bộ lọc status trên site tính trạng thái hiệu lực:
license đã qua ngày hết hạn được hiển thị là Expired dù status lưu trong D1 vẫn
là `active`.

## 3. Tạo license

Nhấn **New License** và điền:

- **License key**: nên dùng nút Generate. Key phải được lưu ngay sau khi tạo.
- **Maximum devices**: từ 1 đến 1000, là số binding active đồng thời.
- **License expiration**: hạn quyền cố định. Để trống nghĩa là vĩnh viễn.
- **Features**: phải chọn ít nhất một quyền.

Nhấn **Create License**, sau đó sao chép clear key ở khung kết quả. Worker chỉ
lưu SHA-256 hash của key; không thể khôi phục hoặc xem lại clear key từ D1 hay
dashboard. Nếu mất key, tạo license mới và revoke license cũ.

### Feature

| Feature | Phạm vi chính |
| --- | --- |
| `automation` | Touch, app/process, OCR, clipboard, VPN và automation thông thường. |
| `stream` | H264 ports 7001–7006 và Adaptive Streaming feedback. |
| `script` | Chạy/dừng script, scheduler, runtime và script log. |
| `admin` | Kill app, clear app data, respring và tác vụ quản trị nhạy cảm. |
| `shell` | Shell tasks; còn phải bật `shell.enabled` ở local config. |

Các feature độc lập. Ví dụ `automation` không tự cấp `admin` hay `shell`.

## 4. Quản lý license

Nhấn **Manage** ở dòng tương ứng.

### Save Changes

Có thể cập nhật:

- status `Active` hoặc `Revoked`;
- giới hạn thiết bị;
- hạn license;
- danh sách feature.

Thay đổi feature hoặc ngày hết hạn được đưa vào signed lease mới ở lần refresh
tiếp theo. Để kiểm tra ngay, mở **Settings > License > Refresh Lease** trên thiết
bị hoặc đợi lifecycle tự refresh.

Giảm `Maximum devices` xuống thấp hơn số binding đang active không tự revoke
thiết bị cũ. Giới hạn mới chặn activation tiếp theo; hãy revoke các binding
không còn dùng nếu cần đưa số active về đúng giới hạn.

### Revoke một thiết bị

Trong **Bound devices**, nhấn **Revoke** ở thiết bị cần thu hồi. Thao tác này:

- đổi binding sang `revoked`;
- giải phóng một active slot;
- làm refresh của lease thiết bị đó trả `device_revoked`.

Đây không phải blacklist vĩnh viễn. Nếu người dùng còn license key và còn slot,
thiết bị có thể thực hiện activation lại.

### Reset Device Slots

Dùng khi restore iOS, đổi máy, mất device private key hoặc không xác định được
binding cũ. Thao tác này revoke toàn bộ binding active và xóa activation
challenge đang dở. Sau đó người dùng phải activation lại bằng license key.

Không dùng Reset Device Slots chỉ để sửa lỗi mạng hoặc lỗi refresh tạm thời.

### Revoke License

Thu hồi toàn bộ license và chặn activation/refresh sau đó. Lease đã ký đang nằm
trên thiết bị không bị sửa từ xa; thiết bị phát hiện revoke ở lần refresh kế
tiếp và các lease mới sẽ không được cấp.

Có thể đổi status lại thành Active bằng **Save Changes**, nhưng các device
binding đã revoke/reset vẫn cần activation lại.

## 5. Phân biệt ba mốc thời gian

- **License expiration / `license_expires_at`**: hạn quyền cố định do admin đặt.
- **Lease Valid Until / `expires_at`**: hạn ngắn của signed lease, được refresh.
- **Offline Until / `offline_until`**: hạn cuối được chạy trong offline grace.

Worker luôn clamp hai hạn lease vào hạn license. Refresh không thể kéo quyền sử
dụng vượt qua License expiration.

## 6. Quy trình vận hành thường dùng

### Cấp license mới

1. Tạo license với một thiết bị và các feature tối thiểu cần dùng.
2. Lưu clear key vào kho bí mật phù hợp.
3. Activation trên thiết bị.
4. Refresh Lease và kiểm tra task 75.

### Khách đổi thiết bị hoặc restore

1. Mở Manage và xem Bound devices.
2. Revoke binding cũ; nếu không xác định được binding, Reset Device Slots.
3. Activation trên thiết bị mới bằng clear key.
4. Kiểm tra device count trở về đúng giới hạn.

### Nâng hoặc hạ gói tính năng

1. Chọn/bỏ feature và Save Changes.
2. Refresh Lease trên thiết bị.
3. Kiểm tra task thuộc feature vừa thay đổi.

### Ngừng quyền truy cập

1. Revoke License.
2. Yêu cầu hoặc đợi thiết bị refresh.
3. Kiểm tra task 75 và các component gate không còn `effective_access=true`.

## 7. Kiểm tra trên thiết bị

```powershell
$raw = Invoke-TLinkTask -HostIP $iphoneIP -Task "75"
$b64 = ($raw -replace '^0;;', '').Trim()
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) |
  ConvertFrom-Json |
  Format-List
```

License hoạt động bình thường thường có:

- `state`: `valid` hoặc `offline_grace`;
- `licensed`: `True`;
- `effective_access`: `True`;
- `device_key_proof`: `True`;
- `features`: đúng với site.

Gọi task `76reload` nếu cần buộc daemon bỏ verifier cache sau khi thay file lease
trong quá trình test. Việc thay đổi Worker bình thường nên dùng **Refresh Lease**.

## 8. Lỗi thường gặp

| Lỗi | Nguyên nhân và xử lý |
| --- | --- |
| `Unauthorized` | `ADMIN_TOKEN` không khớp. Kiểm tra Worker secret hoặc rotate token. |
| `license_exists` | Clear key đã tồn tại. Tạo key khác. |
| `device_limit_reached` | Đã đủ slot. Revoke binding cũ hoặc Reset Device Slots. |
| `device_revoked` | Binding hiện tại bị revoke. Activation lại; reset slot nếu device key đã đổi. |
| `license_revoked_or_expired` | License bị revoke hoặc qua hạn. Kiểm tra Status và License expiration. |
| `device_mismatch` | Lease/public key không thuộc private key trên máy. Không copy lease giữa máy; reset và activation lại. |
| `license_device_private_key_unavailable` | Private key bị mất sau restore/cài đặt. Reset slot, xóa lease recovery nếu cần rồi activation lại. |
| `invalid_features` | Không chọn feature hoặc gửi feature ngoài danh sách contract. |
| `internal_error` | Kiểm tra Worker logs, D1 binding `DB`, schema và signing secret. |

## 9. Nguyên tắc an toàn

- Chỉ mở `/admin` qua HTTPS.
- Không lưu `ADMIN_TOKEN`, signing private JWK hoặc clear license key trong source.
- Dùng feature tối thiểu, đặc biệt với `admin` và `shell`.
- Xác nhận đúng License ID trước khi reset hoặc revoke.
- Backup D1 theo chính sách vận hành Cloudflare trước thay đổi hàng loạt.
- Dashboard hiện chưa có audit log riêng; ghi lại người thao tác, License ID, lý
  do và thời điểm trong hệ thống vận hành bên ngoài.

