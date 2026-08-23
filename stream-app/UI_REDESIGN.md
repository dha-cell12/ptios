# StreamControl — UI Refresh (ui-refresh)

Đợt làm lại giao diện toàn diện (Phương án B) cho app điều khiển tweak iOS
`StreamControl`. Mục tiêu: đẹp hơn, nhất quán hơn, dễ bảo trì hơn — trong khi
**không đụng** tới lớp dịch vụ (streamd/clipboardd/vpnagent/privhelper), socket,
hay logic license.

> Branch: `ui-refresh` (tách từ `newjs`).
> Target: TrollStore / iOS 15.8.8, Theos, `TARGET = iphone:clang:latest:14.0`,
> `ARCHS = arm64 arm64e`, `APPLICATION_NAME = StreamControl`.

## Trạng thái tích hợp

Đã port trạng thái cuối `e597f3e6af7d6d0f1679e37ea8912394b153c2dc` của nhánh
`rogi747/lios:ui-refresh` vào nhánh hiện tại ngày 2026-08-23. Quá trình tích hợp
giữ nguyên các thay đổi mới hơn sau common base `2d2f91b`, bao gồm Compatibility
Tests 09–10, Event Channel và Adaptive Streaming. Sanity contract cục bộ:

```sh
node scripts/check-trollstore-ui-refresh.mjs
```

---

## 1. Kiến trúc mới (design system)

### `TLinkTheme` — nguồn token tập trung
Toàn bộ màu / font / khoảng cách được đọc từ một nơi thay vì hardcode rải rác.

- **Màu**: `accentColor`, `statusRunningColor`, `statusDegradedColor`,
  `statusStoppedColor`, `cardBackgroundColor`, `subtleTextColor`.
- **Typography (Dynamic Type)**: `titleFont`, `headlineFont`, `bodyFont`,
  `captionFont`, `logFont`.
- **Metrics**: `cardCornerRadius`, `controlCornerRadius`, `cardPadding`.
- **Factories**: `buttonWithTitle:symbol:style:target:action:` (4 kiểu nút:
  Primary / Secondary / Tinted / Destructive), `cardContainerView`,
  `statusDotViewWithDiameter:`, `verticalStackWithSpacing:`.
- **Chế độ giao diện (Appearance)**: System / Light / Dark, lưu trong
  `NSUserDefaults` (khóa `TLinkAppearanceStyle`).
  - `+currentAppearanceStyle`, `+setCurrentAppearanceStyle:`,
    `+displayNameForAppearanceStyle:`, `+applyCurrentAppearanceStyleToWindow:`.

### `TLinkLogStore` — ring buffer log dùng chung
Singleton lưu tối đa 500 dòng gần nhất (cấu hình qua `maximumLineCount`),
phát `TLinkLogStoreDidAppendNotification` khi có dòng mới.

- API: `sharedStore`, `appendLine:`, `allLines`, `recentLines:`, `clear`.

---

## 2. Thay đổi theo từng màn hình

| Màn hình | Thay đổi chính |
|---|---|
| **Overview (Dashboard)** | Tab mới, đặt đầu tiên. Thẻ trạng thái dịch vụ + nút thao tác dùng `TLinkTheme`. |
| **Scripts** | Thêm `UISearchController` + large titles, lọc theo tên (không phân biệt hoa/thường), empty-state rõ ràng. |
| **Settings** | Thêm mục **Appearance** (System/Light/Dark) qua action sheet, hiển thị chế độ hiện tại. |
| **Service Log** | Màn hình xem log gắn với `TLinkLogStore`, tự cập nhật realtime. |
| **Script Editor** | Thanh công cụ bàn phím + **tô sáng cú pháp JS nhẹ**. |
| **License** | Giữ nguyên — đã dùng màu ngữ nghĩa thích ứng (tự đúng ở Light/Dark). |

### Appearance (Settings)
Mục "Appearance" nằm trong section "Service" (dựa trên điều phối theo tiêu đề sẵn
có, **không** thêm section mới để tránh phá vỡ chỉ số section index-based đang chia
sẻ giữa chế độ thường và debug). Chạm để mở action sheet, chọn xong sẽ:
1. `setCurrentAppearanceStyle:` → lưu NSUserDefaults.
2. `applyCurrentAppearanceStyleToWindow:` → áp dụng ngay cho cửa sổ.
3. `reloadData` → cập nhật dòng detail.

### Script Editor — tô sáng cú pháp JS
- Cài đặt qua `applySyntaxHighlighting`, thao tác trực tiếp trên `textStorage`
  (chỉ đổi thuộc tính, **không** thay text) nên **giữ nguyên con trỏ & undo**.
- Bảo vệ IME: bỏ qua khi đang soạn (`markedTextRange`).
- Giới hạn hiệu năng: file > 60.000 ký tự chỉ set font/màu nền, bỏ tô token.
- Màu: keyword = accent theme, số = cam, chuỗi = xanh lá, comment = xám.
  Chuỗi/comment xử lý trong một lượt regex để tránh xung đột chồng lấn.
- Gọi lại sau: mở file, mỗi lần `textViewDidChange`, và khi đổi cỡ chữ.
- Giữ nguyên các tính năng sẵn có: toolbar Undo/Redo/Tab/`{}`/`()`/`""`/Done,
  find/replace, go-to-line, phím tắt ⌘S / ⌘F / ⌘G.

---

## 3. Danh sách file

**Mới thêm** (trong `stream-app/app/`):
- `TLinkTheme.h` / `TLinkTheme.mm`
- `TLinkLogStore.h` / `TLinkLogStore.mm`
- `DashboardViewController.h` / `DashboardViewController.mm`
- `ServiceLogViewController.h` / `ServiceLogViewController.mm`

**Đã xoá** (orphan cũ):
- `ViewController.h` / `ViewController.mm`

**Đã sửa**: `AppDelegate.mm` (thêm tab Overview + áp dụng appearance, bỏ ép light
mode), `ScriptsViewController.mm`, `SettingsViewController.mm`,
`ScriptEditorViewController.mm`, `Makefile`.

**Makefile** — `StreamControl_FILES` đã bổ sung:
`TLinkTheme.mm TLinkLogStore.mm DashboardViewController.mm ServiceLogViewController.mm`.

---

## 4. Build

> Yêu cầu môi trường macOS/Linux có Theos (không build được trên Windows PowerShell).

```sh
cd stream-app
make            # biên dịch
make package    # đóng gói .deb / .tipa cho TrollStore
```

- `StreamControl_CFLAGS = -fobjc-arc ...` (ARC bật).
- `StreamControl_CCFLAGS = -std=c++14`.
- Frameworks: UIKit, Vision, CoreML, NetworkExtension, v.v.

---

## 5. Checklist QA (chạy trên thiết bị iOS 15.8.8)

- [ ] Chuyển Appearance System/Light/Dark → áp dụng ngay, giữ sau khi khởi động lại.
- [ ] Xoay ngang/dọc trên các màn hình chính.
- [ ] Dynamic Type (cỡ chữ hệ thống lớn/nhỏ).
- [ ] Màn hình nhỏ (SE) và lớn (Max) — layout không tràn.
- [ ] Editor: tô sáng đúng, gõ mượt, con trỏ/undo không nhảy, IME tiếng Việt/Trung ổn.
- [ ] Editor: mở file lớn (>60KB) không giật.
- [ ] Scripts: tìm kiếm lọc đúng, empty-state hiển thị đúng.
- [ ] Service Log: cập nhật realtime, không rò rỉ bộ nhớ khi log nhiều.

---

## 6. Không đụng tới (ngoài phạm vi)

- `streamd/`, `clipboardd/`, `vpnagent/`, `privhelper/`.
- Logic socket (port click/task 6000, stream 7001-7006, OCR 6011, clipboard 6013)
  và toàn bộ logic license.

## 7. Việc tùy chọn còn lại

- Tách `AppDelegate` (rút `TLinkAppUIBuilder` cho window/tabs + coordinator cho
  OCR/clipboard/visual feedback). **Chưa làm** vì là refactor lớn, rủi ro cao khi
  không thể build/kiểm thử trên host hiện tại — nên thực hiện trên máy có Theos và
  chạy full QA ngay sau đó.
