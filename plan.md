Tlinkauto là 1 tweak hoạt động ở môi trường rootfull tôi đang muốn cho nó hoạt động trên môi trường trollstore tôi đã làm xong thử nghiệm cơ bản ơ thư mục stream-app chức năng click và stream màn hình hoạt động ở thiết bị trollstore. Tôi muốn bạn lên kế hoạch chuyển đổi đầy đủ chức năng của tlinkauto hỗ trợ môi trường trollstore.








Mình đề xuất hướng chuyển đổi như sau: giữ compatibility với protocol/task cũ của TLinkauto, nhưng đổi runtime từ “SpringBoard tweak + rootfull daemon” sang “TrollStore app + bundled daemon + optional privhelper”.

**Mục tiêu bổ sung quan trọng**: Giữ giao diện người dùng **tương đương** (UI Parity) để người dùng dễ sử dụng và chuyển đổi mượt mà. Không chỉ port backend mà còn port/adapt app TLinkauto gốc (tab Scripts + Settings, script management, visual feedback...) thành StreamControl.app.
Kiến Trúc Đích
StreamControl.app
UI quản lý đầy đủ (sẽ được nâng cấp thành giao diện TLinkauto tương đương).
- Bật/tắt service, log, self-test, status, probe.
- Tab Scripts: danh sách script/folder, play, add, more options (giống ScriptListViewController).
- Tab Settings: cấu hình Touch Indicator, Play settings, remote... (giống SettingsPageViewController).
- Các màn hình hỗ trợ: LogViewController, ScriptEditor, ImageViewer, popovers.
- Giao tiếp với streamd qua localhost:6000 (tái sử dụng/adapt Socket.m từ TLinkauto).
- Giữ phong cách light mode, assets (play-icon, script-icon, gearshape...), Localizable.
- Web server (GCDWebServer + http/index.html) được cân nhắc giữ cho remote listing.
Spawn/watchdog streamd giống phần đã có ở stream-app/app/StreamSupervisor.*.
Sau cài đặt người dùng mở app một lần để đăng ký service và background recovery. Sau reboot, `BGTaskScheduler` có thể đánh thức app để phục hồi `streamd` qua supervisor/privhelper, nhưng đây là best-effort và không bảo đảm thời điểm như LaunchDaemon.

streamd
Daemon non-root trong bundle app.
Giữ port 6000 cho protocol task cũ.
Giữ port 7001-7006 cho H264 stream.
Mở rộng từ POCSocketServer thành TLinkTaskServer, xử lý toàn bộ task map trong pccontrol/Task.h.
Dùng lại phần đã chứng minh: TouchInjector, HIDInjectCore, CaptureCore, H264Stream.

privhelper
Chỉ dùng cho việc thật sự cần quyền cao: clear app data, keychain, thao tác filesystem ngoài quyền mobile, kill/process mạnh.
Không đưa click/stream vào helper này để tránh làm MVP nặng và khó debug.

Giao diện người dùng (UI Parity & User Experience)
Mục tiêu cốt lõi: Giữ **giao diện và trải nghiệm sử dụng tương đương** TLinkauto gốc để người dùng cũ dễ dàng chuyển đổi, không cảm thấy "mất app" và vẫn thao tác quen thuộc.

StreamControl.app sẽ được phát triển thành app TLinkauto TrollStore đầy đủ chức năng (không chỉ là control panel daemon đơn giản).

Cấu trúc chính (giống gốc):
- UITabBarController với 2 tab chính:
  - **Scripts** (list.dash): ScriptListViewController + ScriptListTableCell. Hỗ trợ folder, file .tl, nút Play trực tiếp, Add (popover), More options (gear), Log button, refresh. Dùng path `/var/mobile/Library/TLinkauto/scripts/`.
  - **Settings** (gear): SettingsPageViewController + custom cells (switch, slider, entry). Liên kết đến TouchIndicatorConfiguration, PlaySettings, Activator (nếu khả thi).
- Các ViewController khác cần port/adapt:
  - LogViewController (xib)
  - ScriptEditorViewController
  - ImageViewerViewController
  - AdderPopOverViewController, MoreOptionsPopOverTableViewController
  - PlaySettingsViewController, SettingsPage...
- Giao tiếp backend: Tái sử dụng hoặc port `Socket.m` (TCP client đơn giản) → connect localhost:6000, gửi task theo wire format cũ, nhận response 0;; / -1;;.
- Config & dữ liệu: Giữ nguyên các path từ Config.h:
  - Scripts: /var/mobile/Library/TLinkauto/scripts/
  - Config: /var/mobile/Library/TLinkauto/config/...
- Web component: Giữ GCDWebServer + http/index.html (template file list) nếu có nhu cầu remote listing.
- Phong cách & tài nguyên: Giữ light mode (overrideUserInterfaceStyle), Assets.xcassets (icons play/script/folder/gear), Localizable.strings (en + zh-Hans).
- Onboarding & UX: Giữ các alert lần đầu, refresh control, popover presentation.

Visual feedback (overlay) - cần thiết kế lại:
- Toast (12,22), AlertBox/Dialog (42,43), TouchIndicator (26): Trước đây là SpringBoard/tweak overlay.
  - Giải pháp TrollStore: Chạy trong process của app (UIWindow + custom view overlay khi app foreground).
  - Fallback: Local notification, banner, hoặc minimal alert.
  - Touch indicator có thể vẽ trực tiếp hoặc dùng accessibility overlay.
- Text input (24): Kết hợp pasteboard + HID keyboard event (cần port UIKeyboard logic).

Hạn chế cần ghi nhận:
- Siri Shortcuts (shortcutext): Hỗ trợ hạn chế hoặc bỏ (khó port trên TrollStore thuần).
- Activator: Phụ thuộc libactivator + SpringBoard, có thể thay thế bằng volume button/hotkey khác hoặc ghi là "limited".
- Một số notification/activator listener từ pccontrol/Activator sẽ cần redesign.

Chiến lược triển khai UI:
- Bắt đầu sau khi Phase 2 (core automation) ổn định: app có thể gửi task 10/18/25/29... qua socket.
- Port UI code từ TLinkauto/TLinkauto/ + layout/ (hoặc rebuild tương đương).
- App mới vẫn bundle streamd + spawn qua StreamSupervisor.
- Đảm bảo script list tự động refresh từ thư mục chuẩn.
- Thêm vào UI: capability probe, task support matrix, export log/diagnostics (mở rộng Phase 6).

Ma Trận Chức Năng
Nhóm đã có nền tảng, ưu tiên port trước:
Touch task 10, 61-65: thay pccontrol/Touch.xm bằng HID path trong stream-app/streamd/TouchInjector.*.
Screenshot/stream/frame tasks 29, 47-49, 66-70: dùng CaptureCore thay Screen.xm, giữ API trả về tương thích.
H264 stream: giữ 7001-7006, gom profile tương thích client hiện tại.
Device info 25, hello/status 60, sleep 18.

Nhóm port trực tiếp nhưng cần kiểm thử entitlement:
Template/image/color: 21, 23, 28, 48-49, 68-70, port Image.xm, ScreenMatch.xm, TemplateMatch.xm sang streamd.
OCR: 27 Vision OCR, 91 Tesseract OCR. Ưu tiên Vision trước, Tesseract sau vì kéo theo static libs lớn.
Touch recording 14-15: có thể thử bằng HID monitor entitlement đã có.
Hardware key 30: chuyển sang HID key event nếu khả thi.

Nhóm cần thiết kế lại:
Toast/alert/dialog/touch indicator 12, 22, 26, 42, 43: Xem chi tiết trong phần "Giao diện người dùng (UI Parity)". Foreground dùng overlay window của app-process. Background toast/alert/dialog dùng CFUserNotification system alert; toast background hiện cố định ở giữa màn hình.
Text input 24: ưu tiên pasteboard + HID keyboard event; nếu app đích chặn paste thì cần fallback riêng.
App management 11, 31-35, 50-54: thử private APIs từ unsandboxed platform app; nếu không ổn, đưa phần kill/data vào privhelper.
Connectivity 55-59: nhiều khả năng cần private framework/entitlement riêng; xếp phase sau.

Nhóm script/runtime:
Bundle tlinkauto-jsd vào app thay vì /usr/libexec.
Giữ JavaScriptCore-first như tài liệu docs/tlinkauto-js-runtime.md.
Script gọi task qua localhost 6000; raw/admin task vẫn gate bằng capability/config.

Roadmap
Phase 1: chuẩn hóa stream-app thành nền chính
Đổi tên POCSocketServer thành task server thật.
Giữ task 10, 97, 98, 99.
Thêm response chuẩn 0;;... / -1;;....
Thêm capability report: touch, capture, h264, hidMonitor.

Phase 2: port core automation
Port Task.h và router tối thiểu.
Implement 18, 25, 29, 60, 61-65.
Dùng lại protocol client cũ để PC/web không phải đổi.

Phase 3: port vision/image pipeline
Port Image.xm, ColorPicker.xm, ScreenMatch.xm.
Dùng CaptureCore làm frame provider chung.
Hoàn thiện 66-70 vì đây là đường hiệu năng tốt nhất cho bot.

Phase 4: script runtime
Bundle JS examples/config vào /var/mobile/Library/TLinkauto.
Chạy script bằng bundled tlinkauto-jsd hoặc tích hợp JS runtime vào streamd.
Test helper safe demos: frame color, OCR, storage, stop/timeout.

Phase 5: app/process/admin
Port app info/frontmost/open URL trước.
Thử kill/clear data/keychain qua privhelper.
Mọi task không hỗ trợ phải trả lỗi rõ: unsupported_on_trollstore, không silent fail.

Phase 6: UI/UX hoàn thiện + UI Parity
- Nâng cấp StreamControl.app thành giao diện TLinkauto đầy đủ (tab Scripts + Settings).
- Port/adapt các ViewController chính: ScriptListViewController, SettingsPageViewController, LogViewController, ScriptEditor, popovers.
- Tích hợp Socket client để gửi task thực tế (play script, screenshot, image match...).
- Hoàn thiện visual feedback: Toast/Alert/TouchIndicator chạy trong app-process (UIWindow overlay) + notification fallback.
- Thêm tính năng UI:
  - Service status, port status, capability probe, entitlement snapshot.
  - Log viewer nâng cao (từ streamd + script runtime).
  - Restart button, self-test nhiều loại task.
  - Export diagnostics / log bundle.
  - Image viewer cho kết quả match.
- Giữ web server component nếu khả thi.
- Test toàn bộ flow: mở app → thấy script list → play → thấy toast/indicator → xem log → config settings.
- Đảm bảo sau cài đặt chỉ cần mở app 1 lần để đăng ký background recovery; sau reboot iOS có thể phục hồi service bằng BGTaskScheduler, còn mở app thủ công vẫn là fallback chắc chắn.

Ghi chú kỹ thuật bổ sung cho toàn bộ project:
- Đổi tên nhất quán: POCSocketServer → TLinkTaskServer, POC* → TLink* (tránh confusion).
- Response chuẩn: Luôn dùng "0;;<data>\r\n" cho success, "-1;;<error>\r\n" cho lỗi (khớp client cũ).
- Capability report (task 97): Mở rộng thành chuỗi chi tiết (touch, capture, h264, image, ocr, appMgmt, script, hidMonitor...).
- Build: streamd/Makefile phải link opencv2.framework (cho Phase 3 image) và xử lý third_party/Tesseract nếu dùng. Thêm vào FILES/FRAMEWORKS.
- Touch path: Consolidate TouchInjector và HIDInjectCore (chọn 1 làm canonical hoặc wrapper chung).
- Privhelper: Thiết kế protocol (local socket hoặc Mach service). Impl skeleton sớm (dùng persona-mgmt + spawnRoot). Cập nhật Info.plist (TSRootBinaries) và entitlements khi có.
- Error rõ ràng: Mọi task không port được phải trả "unsupported_on_trollstore" hoặc lý do cụ thể.
- SenderID & screen: Xử lý orientation thay đổi, cache bền vững.
- Logging: streamd printf/NSLog + file log; supervisor forward đầy đủ về UI.

Tiêu Chí Hoàn Thành
Client cũ (PC, WebTango, Python) vẫn connect ip:6000 và chạy được touch/screenshot/image/color/OCR/script.
WebTango/iOS stream vẫn dùng 7001-7006.
Có bảng capability rõ ràng để script biết task nào chạy được trên TrollStore.
App TLinkauto TrollStore có giao diện tương đương gốc:
  - Tab Scripts: xem danh sách, play script, quản lý folder.
  - Tab Settings + config Touch Indicator, play settings.
  - Log viewer, toast/alert/touch indicator hoạt động (app-process overlay).
  - Socket client nội bộ gửi task thành công.
Không còn phụ thuộc Substrate/SpringBoard injection cho core automation.
Các task không thể port được có fallback hoặc lỗi rõ ràng (unsupported_on_trollstore).
Script storage và config giữ nguyên path cũ (/var/mobile/Library/TLinkauto/...).

Script file parity: rootfull in-process `pccontrol`, rootfull `tlinkauto-jsd`,
and TrollStore `streamd` share the same `device.openFile` implementation.
Handles support read/write/append,
text/base64, seek/tell/flush/close, are bundle-relative, and are automatically
closed at the end of every script evaluation.

Known unresolved issues / deferred investigation:
- Smart Wait v1 is implemented across rootfull JavaScriptCore, TrollStore
  JavaScriptCore, and WebTango with one shared result schema, bounded timeout,
  cancellation, consecutive stable matches, and deterministic image/frame
  cleanup. Task `60/97`, packaged smoke scripts, a behavioral Node checker and
  the WebTango IDE expose the feature. Device validation of real image and OCR
  locators remains pending; see `docs/smart-wait-visual-locator-v1.md`.
- VPN P0 now freezes legacy task `59` as contract v1, reserves action `2` for
  future base64-JSON diagnostics, and reports the current rootfull `stub` and
  TrollStore `interface_probe` states through task `60/97`. No entitlement or
  production backend is enabled in P0. Configuration stays in foreground UI,
  secrets stay in Keychain, and credentials are forbidden on port `6000`;
  see `docs/vpn-p0-baseline.md`.
- VPN P1 now implements the reserved task `592` response with a shared
  base64-JSON schema for rootfull and TrollStore. The probe reads only the
  current process entitlements and checks NetworkExtension framework/class
  availability without saving, starting, or stopping a profile. Production
  VPN entitlements and action `1` remain disabled pending device evidence;
  see `docs/vpn-p1-diagnostics.md`.
- VPN P2 now adds the rootfull TLink-owned IKEv2 path: the foreground app
  creates the profile and stores its password as a ThisDeviceOnly Keychain
  reference, while the mobile `tlinkauto-vpnd` LaunchDaemon performs
  license-gated query/connect/disconnect over loopback port `6014`. Task
  `591` waits for terminal `NEVPNStatus`, on-demand stays disabled, and the
  broker refuses foreign profiles. Live IKEv2 control was validated on device
  on 2026-08-01; see `docs/vpn-p2-rootfull-broker.md`.
- VPN P3 adds an experimental TrollStore foreground-app candidate. Streamd
  keeps task `59` on port `6000` and forwards fixed commands to StreamControl
  on loopback port `6015`; only the app carries `allow-vpn`, configuration and
  credentials remain local UI/Keychain, and query retains the historical
  interface fallback. Control fails closed when the app is not active or the
  entitlement is stripped. Live IKEv2 control was validated on device on
  2026-08-01; see `docs/vpn-p3-trollstore-foreground.md`.
- VPN P4 promotes rootfull to `full_control` and TrollStore to
  `app_side_control`, and adds local-UI-only `NEOnDemandRuleConnect`
  auto-reconnect for the owned profile. Explicit task `591;;0` disables
  on-demand before stopping so the terminal disconnect remains deterministic.
  Task `59` stays contract v1 and never accepts credentials or on-demand
  configuration; see `docs/vpn-p4-on-demand.md`.
- VPN P5 adds a TrollStore-only background `vpnagent` on port 6016.
  Privhelper spawns it as mobile UID/GID 501; streamd routes fixed task 59
  query/connect/disconnect/diagnostics commands to it first and retains the
  foreground app broker on 6015 as fallback. The agent shares the app identity,
  `allow-vpn` entitlement, and Keychain group but cannot receive credentials or
  configuration. Live device evidence promoted it to `background_control`:
  agent v2 ran under mobile identity and background connect/query succeeded.
  First-run Save Profile and the iOS approval prompt remain local bootstrap; see
  `docs/vpn-p5-background-agent.md`.
- Foreground dependency reduction uses the proven clipboard UIDaemon pattern. `clipboardd` v12 keeps direct background Pasteboard access, handles best-effort keep-awake requests, sends background toast/alert/dialog through CFUserNotification, and applies the same signed-license gate as streamd. StreamControl writes a short-lived foreground heartbeat so foreground and background feedback are not duplicated.
- Device validation of v10 proved that a UIDaemon `UIWindow` could report visible in memory while the compositor did not place it above the active app. v11 removes that false-success path. Foreground toast still supports `0` top, `1` center, `2` bottom; background toast is visible through CFUserNotification but fixed at center and reports `limited_on_trollstore`. True positioned background toast remains deferred until a proven SpringBoard/BackBoard window-hosting path exists. Dialog button results are not yet bridged back to the original task.
- A global touch indicator still requires SpringBoard/BackBoard window ownership or injection and remains foreground-only. The daemon cannot safely make a normal app UIWindow appear over arbitrary foreground apps.
- StreamControl now registers `BGAppRefreshTask` and `BGProcessingTask` as a best-effort recovery path after first launch. Each handler reschedules itself and completes only after the supervisor verifies task port 6000. Diagnostics live at `/var/mobile/Library/TLinkauto/runtime/background_service_scheduler.plist`. Immediate boot startup remains unresolved because iOS controls background launch timing and TrollStore cannot install a normal platformized LaunchDaemon.
- License Phase 4 now uses an explicit fail-closed task policy table, records denied legacy task `10` drops, rechecks active H264 sessions every 5 seconds, and rechecks running scripts every second. Revoked scripts close their file handles and stop cooperatively; scheduler and autolaunch cannot bypass the script gate.
- License Phase 5 adds corrupt-lease quarantine with cross-process generation notification, Keychain-backed public-key repair, device-limit recovery guidance, explicit clock tolerance diagnostics, and service replacement so an update cannot keep an older daemon/config active. Phase 6 uses service v22 and a compile-time build-mode marker for artifact verification.
- License Phase 6 code/CI builds separate observe and enforced artifacts, validates packaged public config and compile markers in all processes, scans for private/admin secret markers, and provides PowerShell regression plus 24/72-hour JSONL soak evidence. Rootfull license work remains blocked until the enforced device release gate passes.
- Rootfull License Phase 6 now adds enforced package/runtime coherence and a device-P256-signed anti-rollback checkpoint for lease `issued_at` plus wall-clock/uptime anomalies. Task `60/75/97`, the License dashboard, dual-mode artifact validator, PowerShell regression and rootfull JSONL soak expose the state. Selective OLLVM and authenticated clients for port `6000`/H264 remain Phase 7 hardening.
- Rootfull license authority hotfix moves device-private-key possession checks into the mobile `tlinkauto-licensed` LaunchDaemon. Rootfull daemon, SpringBoard tweak, script helper, and VPN broker consume a nonce-bound P-256-signed status over a local Unix socket and fail closed if that proof is absent or expired. This resolves the split state where the app reported `valid` while task `75` reported `license_device_private_key_unavailable`; see `docs/license-rootfull-authority-hotfix.md`.
- Script folder management now exposes a visible ellipsis action menu for Rename Folder, Duplicate, and Delete Folder instead of relying only on swipe actions. The Logs view has a confirmed Clear Log button backed by task 73; clearing removes the current in-memory session log lines, while a running script may continue appending new lines.
- Respring is now available through Settings and task `74confirm`. It uses a dedicated `privhelper --respring` command rather than the gated shell, requires UID 0, validates the SpringBoard process name/path, and records the signal result in `/var/mobile/Library/TLinkauto/privhelper.log`.
- Main UI navigation is reduced to Scripts and Settings. The former service-control tab is removed; Settings keeps Restart streamd, Respring Device, and Runtime Settings visible, while all diagnostics and compatibility controls live in the DEBUG child screen.
- Keep-awake through the UIKit UIDaemon is best-effort. A guaranteed global display/power assertion remains deferred until a proven private IOKit/SpringBoard path is available.
- Vision OCR is currently deferred on TrollStore. Headless streamd Vision OCR previously crashed the worker during `vision_perform_requests` with signal 11; app-side Vision bridge avoided the streamd crash but failed on the test device with `Could not create buffer with format '420f' (-6662)`, even after RGB/accurate retry attempts.
- Current stable OCR path is task 91 using true static Tesseract libraries plus `/var/mobile/Library/TLinkauto/tessdata/*.traineddata`.
- Task 91 now reports Tesseract init source so tests can distinguish normal path init from memory fallback: response suffix `tesseract_init_source=path:...` or `tesseract_init_source=memory:...`; task 60 also exposes `tesseractInitSource`, `tesseractInitAttempts`, and `tesseractInitAtMs`.
- Revisit Vision later with a dedicated sample app/device matrix, pixel buffer format investigation, and possibly a pure CGImage/VNImageRequestHandler path that avoids the failing `420f` conversion.
- Vision OCR recovery P0 is now frozen in `docs/ocr-p0-baseline.md`: legacy task `27/91` fixtures are enforced in CI, task `97` additively reports the deferred Vision route and Tesseract default, and `scripts/Collect-TLinkOCRBaseline.ps1` collects reproducible device evidence. P0 does not enable Vision CPU-only or change the OCR wire format.
- Vision OCR recovery P1 implements a CPU-only TrollStore canary: legacy task `27` defaults to `app_cpu`, optional ninth-field profile `worker_cpu` enables the isolated direct path, iOS 14-16 uses `usesCPUOnly`, and iOS 17+ assigns an `MLCPUComputeDevice` to every Vision compute stage. Task `91` remains the stable/default engine, task `27` response bytes are unchanged, and device promotion evidence is still required; see `docs/ocr-p1-cpu-only.md`.
- Vision OCR P1 device validation is deferred after the A9/iOS 15.8.8 matrix failed: `worker_cpu` crashed with signal 11 during `vision_perform_requests`, and a fresh-launch Fast `app_cpu` request remained blocked through the 20-second watchdog while port `6000` survived. Keep task `91` as the production/default OCR path and revisit the preserved CPU-only canary on stronger hardware using `docs/ocr-p1-device-findings.md`.
- Zoom P0 freezes `task64_additive_zoom_v1` for two- and three-finger
  pinch/spread on rootfull and TrollStore. Both task `10` backends already
  support multiple finger children in one parent HID frame, while the reserved
  syntax and limits remain the historical baseline. Legacy task `10/64` is
  unchanged; see `docs/zoom-p0-baseline.md`.
- Zoom P1 implements the reserved `64zoom...` syntax on rootfull and TrollStore
  with strict numeric/bounds preflight, linear radial interpolation, one parent
  HID frame containing all two or three fingers at every step, and best-effort
  all-fingers-up cleanup on dispatch exception. Capability state remains
  `experimental` with `zoomDeviceValidated=0` until both builds pass the device
  matrix in `docs/zoom-p1-multitouch.md`.
- Zoom P2 adds `zoom_runtime_diagnostics_v1` to task `60`, including lifecycle
  counters, exact parent-frame counts, last direction/finger/step/duration and
  in-flight state. WebTango SDK/Automation IDE now exposes timeout-aware
  `device.zoom()` and pinch/spread snippets. Runtime state stays `experimental`
  and `zoomDeviceValidated=0`; see
  `docs/zoom-p2-observability-webtango.md`.
- Clear app data now has a TrollStore extension task: `72<bundle.id>`. It runs through privhelper, refuses protected bundles, and only clears safe app data containers under `/var/mobile/Containers/Data/Application/`. Keychain clearing remains deferred.

## License MVP

- Added a Cloudflare Worker + D1 license service under `license-worker/`.
- StreamControl now has a License screen that creates a Secure Enclave P-256
  device key (with a `ThisDeviceOnly` Keychain fallback), activates a license,
  refreshes its signed lease, and exposes local status.
- The signed lease is verified independently by the app, `streamd`, H264
  accept path, and `privhelper`. Local verification checks the server
  signature, dates, features, device public-key hash, and proof that the
  matching private key still exists on this device.
- Task `75` returns license diagnostics and task `76` invalidates the verifier
  cache before checking again. Task `60/97` also report license mode/state.
- Enforcement is observe-only by default. Release builds can set
  `TLINK_LICENSE_ENFORCEMENT=true`; the GitHub build then also compiles forced
  enforcement into all three native components.
- Worker lease refresh requires a device signature. Admin reset of registered
  devices is available for erase/restore or device replacement.
- Certificate pinning and rootfull runtime enforcement remain deferred
  hardening work; see `docs/license-cloudflare-worker.md`.
- Screenshot task 29 now supports action 1 file capture plus action 2 save-to-album and action 3 clear-album using the `TLinkauto` Photos album. Socket tasks must not trigger Photos permission UI; StreamControl Settings has `Photo Access` for foreground authorization. Clear album removes assets from the `TLinkauto` album only, not from the whole photo library, to avoid iOS delete-confirmation popups.
- Secure Pairing P0 freezes the rootfull/TrollStore plaintext exposure baseline,
  threat model, and additive `ZXSP` wire contract v1. It specifies a local-UI
  256-bit QR bootstrap, mutual P-256 identity plus ephemeral ECDH, HKDF-SHA256,
  AES-256-GCM sessions, strict replay/downgrade rules, pairing scopes, and
  revocation. P0 is capability-only (`contract_only`, `observe_only`) and does
  not alter legacy task/H264 behavior; see `docs/secure-pairing-p0-baseline.md`.

Nói gọn: nên biến stream-app thành “TLinkauto TrollStore runtime” chính thức, rồi kéo từng module từ pccontrol sang theo thứ tự: touch/capture trước, image/OCR tiếp, script runtime sau, cuối cùng mới đến admin/process/connectivity.
**UI Parity là tiêu chí bắt buộc** để người dùng dễ sử dụng và chuyển đổi mượt mà.
