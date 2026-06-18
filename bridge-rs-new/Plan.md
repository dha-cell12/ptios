Plan triển khai iOS vào bridge-rs (Discovery + Device Manager + MPEG-TS Stream Web)
Mục tiêu

Bridge-rs tự động quét LAN để tìm iPhone service.

Hợp nhất danh sách thiết bị Android (ADB) + iOS (LAN) trong một registry.

Expose API để UI/web đọc device list + trạng thái.

Expose endpoint stream iOS: TCP MPEG-TS → WebSocket.

Web UI phát video bằng mpegts.js + MSE.

Phase 0 — Chuẩn bị & kiểm tra hiện trạng
0.1. Xác định các thành phần sẵn có trong bridge-rs

Framework server đang dùng (axum/warp/actix/hyper)

Cơ chế device list Android hiện tại (đang có endpoint nào? ws nào?)

Cơ chế stream Android: đang dùng ws relay hay http? endpoint path?

Deliverable: ghi ra các endpoint Android hiện tại để giữ consistency.

0.2. Xác định subnet LAN của desktop

Desktop IP ví dụ: 192.168.1.X ⇒ subnet /24 prefix 192.168.1

Nếu nhiều NIC/Wi-Fi + LAN: chọn interface đúng.

Deliverable: hàm lấy prefix subnet, hoặc config bắt buộc.

Phase 1 — iOS Discovery Provider (LAN scan)
1.1. Data model parse JSON /deviceinfo

Dựa trên JSON bạn đưa:

ApiResp<T> { code, message, data }

IosDeviceInfo { devsn, zeversion, sysversion, devname, devmac, deviceid, devtype, wifi_ip, ipaddr }

Deliverable: struct serde + unit test parse JSON mẫu.

1.2. Scanner logic (polling + concurrency)
Behavior

Scan range 2..=255 với prefix 192.168.1:

GET http://<ip>/ping (timeout 200–400ms)

nếu 200 ⇒ GET http://<ip>/deviceinfo (timeout 500–800ms)

nếu code==0 ⇒ nhận thiết bị online

Performance rules

concurrency limit: 64 (tùy máy)

dùng reqwest Client reuse connection pool

per-IP backoff nếu fail liên tục (optional nhưng tốt)

Deliverable: module ios_lan_scanner.rs trả Vec<IosDeviceInfo + ip>.

1.3. State store + diff

Tạo IosDeviceState chuẩn hoá:

id: ios:<udid> (udid = deviceid)

ip: từ host scan hoặc wifi_ip

name, model, sys_version, mac, ze_version

status: online/offline

stream: tcp://<ip>:7001 (port fixed hoặc config)

Diff rule:

nếu device mới xuất hiện ⇒ DeviceAdded

nếu mất ⇒ DeviceOffline

nếu info đổi ⇒ DeviceUpdated

Deliverable: DeviceRegistry hoặc IosRegistry riêng emit event channel.

Phase 2 — Unified Device API (Android + iOS)
2.1. Unified types

DeviceDescriptor (để API trả):

id

platform: android | ios

status

display_name

ip (nếu có)

capabilities: ["stream_mpegts_ws", "status"] cho iOS

meta: map/json full info

Android giữ nguyên, chỉ cần map sang cùng schema.

Deliverable: GET /devices trả list unified.

2.2. Event stream (optional nhưng rất hữu ích)

WS /events push JSON events để UI realtime.

Deliverable: UI không cần polling liên tục.

Phase 3 — iOS Stream: TCP MPEG-TS → WebSocket relay
3.1. Server endpoint

Tạo endpoint:

GET /ios/{id}/stream (WebSocket upgrade)

Flow:

lookup device by id trong registry

connect TCP đến <ip>:7001 (timeout 1–2s)

loop:

read TCP bytes (chunk 16–64KB)

send WS binary frame

nếu WS đóng ⇒ close TCP

Deliverable: stable relay + backpressure handling.

Multi-client policy

Chọn 1 trong 2:

V1 (nhanh): 1 client = 1 TCP connect (OK nếu ít user)

V2 (xịn): 1 TCP upstream/device + fan-out nhiều WS clients (nên làm nếu nhiều viewer)

Khuyến nghị: làm V1 trước, thiết kế để nâng cấp V2.

Phase 4 — Web Client playback (mpegts.js)
4.1. Page/Component xem stream

<video> + mpegts.js

connect URL: ws(s)://<host>/ios/<id>/stream

config live low latency:

enableWorker: true

liveBufferLatencyChasing: true

tune latency (0.6s–1.5s)

4.2. UI hiển thị list thiết bị

gọi GET /devices

filter platform ios/android

hiển thị status + nút “View stream” nếu iOS online

Deliverable: xem iPhone stream trên web.

Phase 5 — Hardening & Ops
5.1. Config

enable/disable iOS scan

subnet prefix (auto hoặc manual)

ports (default 80 cho http, 7001 cho stream)

poll intervals

concurrency limit

5.2. Logging/metrics

log ip scan errors

log connect stream failures

count online devices

stream sessions active

5.3. Security (LAN vẫn nên có)

nếu endpoint iPhone có token: add header Authorization

bridge-rs hạn chế bind public interface nếu không cần

optional allowlist subnet

Checklist nghiệm thu (Acceptance Criteria)

Desktop quét subnet 192.168.1.2-255 và tìm thấy đúng 10 iPhone.

GET /devices trả iPhone với id=ios:<udid>, status online/offline đúng.

Khi iPhone tắt service, status chuyển offline trong ≤ 2 chu kỳ poll.

ws://server/ios/<id>/stream relay được MPEG-TS (test bằng tool):

websocat ws://... | ffplay -i - (nếu muốn debug)

Web UI xem live stream ổn định, latency thấp.
