# stream-app

Khung chuẩn hợp nhất **click + stream** cho Tlinkauto trên TrollStore (iOS 15.8.8).

## Kiến trúc

```
[App TrollStore: StreamControl]  ← UI (mở 1 lần sau cài đặt; background recovery best-effort sau reboot)
   └─ StreamSupervisor: spawn + watchdog (KHÔNG root)
        └─ [streamd]  ← daemon hợp nhất
             ├─ click/    HID injection (task 10, cổng 6000)
             ├─ stream/   capture + H.264 (cổng 7001-7006)
             └─ transport/ socket servers (tách cổng)
```

Root helper (`privhelper/`) để dành cho clear keychain / app data — thêm sau,
spawn qua `spawnRoot` + `persona-mgmt`, KHÔNG ảnh hưởng `streamd`.

## Phạm vi đợt khung chuẩn

- Click (task 10) + stream (capture→H264→client) chạy được.
- UI đồng bộ phong cách Tlinkauto ở mức bố cục (navigation + light mode).
- Self-test tap trong UI.
- CHƯA tối ưu latency (pipelining/low-latency rate control để đợt sau).
- CHƯA đồng bộ phần quản lý/play script.

## Thành phần và nguồn

| Thành phần | Nguồn |
|-----------|-------|
| click/TouchInjector, HIDInjectCore, WireProtocolParser | `poc-trollstore` (đã pass) |
| stream/CaptureCore | `poc-stream` (đã pass entitlement capture) |
| stream/H264Stream | `pccontrol/H264Stream.xm` |
| transport/SocketServer | `poc-trollstore/POCSocketServer.mm` + tách cổng stream |

## Cổng

| Cổng | Dùng cho |
|------|----------|
| 6000 | Click (task 10, wire-protocol legacy) |
| 7001-7006 | Stream H.264 (6 profile, giữ tương thích client PC) |

## Build

```
make            # build cả app (.tipa) lẫn streamd
```

`streamd` được đóng gói vào bundle app (`StreamControl.app/streamd`) để app
spawn bằng đường dẫn tương đối.

The aggregate build runs `make swift-support` before the WidgetKit target and
disables parallel compilation for that Swift bundle. This prevents Theos from
requesting `generate-output-file-map` before its host-side Swift tools exist.
If building outside CI, clone Theos recursively so `vendor/swift-support` and
its `Package.swift` are present.

## Widget-assisted Boot Script

The TrollStore package embeds `PlugIns/TLinkBootWidget.appex`. To enable the
reboot path:

1. Open **Settings -> Boot Script**, choose a JavaScript or script bundle, and
   enable **Boot Script**.
2. Add **TLinkauto Boot Wake** to the iOS Home Screen.
3. Reboot. When WidgetKit schedules the widget, it launches StreamControl if
   task port `6000` is absent. StreamControl starts `streamd`, and the selected
   `00-boot-script` autolaunch entry runs through the normal licensed script
   runtime.

The extension requests a new timeline every five minutes, but iOS may throttle
or defer it. This is a TrollStore/private-API, best-effort wake path rather than
a LaunchDaemon. Wake diagnostics are written to
`/var/mobile/Library/TLinkauto/runtime/widget_boot_wake.plist`.

## Remote Bridge MVP

Service v23 keeps the LAN ports above and can also make an outbound WSS
connection to `bridge-rs-new`. Configure `Settings -> Remote Bridge` with the
public `wss://` hostname and the bridge `TLINK_REMOTE_TOKEN`. Control and H264
use separate WebSockets; task dispatch still uses the same port-6000 parser.

Full setup and 5G validation are documented in
`bridge-rs-new/docs/remote-ios-mvp.md`.

## Entitlements

`streamd/entitlements.plist` HỢP NHẤT hai nhóm đã chứng minh riêng rẽ:
- Nhóm HID (click): `com.apple.private.hid.client.event-dispatch` + IOKit HID user-clients.
- Nhóm capture (stream): `com.apple.QuartzCore.global-capture`, IOSurface, v.v.

Bước 1 kiểm chứng ký hợp nhất trước khi bê toàn bộ code.
