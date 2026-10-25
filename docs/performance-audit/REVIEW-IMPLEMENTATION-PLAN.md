# Đối chiếu performance audit và backlog triển khai

Ngày: 16/10/2026 (Asia/Bangkok). Commit đối chiếu: `18e6e67c7250e172da02df3e2ea558aa6ffc0242`.

## Kết luận

Phần lớn nhận xét có cơ sở ở mã nguồn hiện tại và dùng được để lập backlog. Tuy nhiên, không nên chuyển nguyên thứ tự P0/P1 của STATE thành thứ tự phát hành: audit trộn lỗi tính đúng đắn, cơ hội tối ưu chưa đo và các phạm vi rootfull, StreamControl/TrollStore, TouchPOC.

Đã đối chiếu 130 mã nhận xét trong FINDINGS (24 P0, 78 P1, 28 P2), các luồng gọi và cấu hình build liên quan. Đây là kiểm tra tĩnh; chưa chạy build iOS, Instruments hoặc tái hiện trên thiết bị. BENCHMARK-S002 đến BENCHMARK-S011 là kế hoạch đo, không phải kết quả đo. Chưa có cơ sở cam kết tỷ lệ giảm CPU/pin/RAM.

Cập nhật triển khai C02b20 (25/10/2026): người dùng báo build C02b19 pass (`adf0a93`). openImage chuyển sang entry task 48 trực tiếp, dùng chung core path/file/ImageIO/decode/store với RAW; giữ cách chuyển đổi path/owner và response cũ. Cuối lời gọi dọn đúng ID vừa publish nếu chưa commit do cancel/deadline/output/lỗi, kể cả owner bị dịch bởi delimiter trong path. 36 kiểm tra nguồn, 20 runner native, 521 lệnh kiểm tra nguồn workflow và tiền xử lý assert pass trên Windows; fixture Foundation mới chờ macOS CI. Chi tiết: IMPLEMENTATION-C02B20.md. Còn captureImage/response/các adapter P0-13 khác và helper transport/config/dedupe; C01/C02 chưa nghiệm thu hiệu năng/thiết bị.

## Phạm vi triển khai đã chốt

Theo yêu cầu người dùng ngày 16/10/2026, loại các mục chỉ thuộc `poc-trollstore`/TouchPOC khỏi backlog. Bảng bên dưới giữ dấu vết 130 nhận xét gốc; bốn mã P0-21, P1-65, P1-66, P2-25 chỉ được lưu để tham khảo, không triển khai. Rootfull/roothide và StreamControl/TrollStore tiếp tục thuộc phạm vi.

## Các điểm cần hiệu chỉnh

1. **P2-02 lỗi thời về số lượng:** code hiện có sáu listener H264, không phải hai; gộp P2-05. Blocking accept không đồng nghĩa busy loop. P2-06 là nhánh accept lỗi liên tục, khác với trạng thái idle bình thường.
2. **Không coi mọi P0 là lỗi chặn phát hành:** P0-08 cần prototype capture backend; P0-21 chỉ thuộc TouchPOC. Ngược lại P1-06/P1-07/P1-09/P1-19/P1-46 nên sửa sớm vì có lỗi bounds/lifetime/ownership/input rõ.
3. **Các con số là mô hình:** 600–1330 send/s lấy từ bitrate cấu hình, không phải mức syscall tối thiểu đã đo; bitrate thực tế có thể khác. 10/80 poll/s, 200 vòng ngủ/s, 33N và 13/23 byte/pixel cũng không phải CPU/RSS/wakeups thực đo. Pixel volume không bằng DRAM bandwidth. Ước tính frame không bao gồm mọi temporary hoặc copy C++ khi capture vào block.
4. **P1-20 là giữ payload quá hạn trong store có giới hạn**, không chứng minh RAM tăng vô hạn; P1-21 giới hạn số image nhưng chưa giới hạn byte. P1-03 mới là nghi ngờ autorelease tích lũy, cần Allocations.
5. **P1-69 xác nhận remove sai notification**, chưa chứng minh double delivery/zombie observer. P1-30 xác nhận thiếu guard candidate rỗng, chưa chứng minh Vision thực sự trả candidate rỗng trên thiết bị cụ thể.
6. **P0-14 cần nhiều hơn truyền context:** shell có hỗ trợ context; gesture/OCR/template/AX phải chủ động kiểm tra cancellation/deadline. Khi dừng touch phải cleanup các ngón đang down trước khi báo hoàn tất.
7. **License fast path phải giữ trust contract:** không bỏ enforcement ở ranh giới daemon/SpringBoard; giữ expiry, revocation, invalidation, anti-rollback và fail-closed khi snapshot quá hạn. Cache artifact xác minh theo generation; không tái sử dụng signed response gắn nonce của request khác. Giữ cơ chế phục hồi khi mất notification.
8. **P1-74 không được thay bằng hai atomic-write rồi gọi là transaction atomic:** cần commit/recovery cho cặp lease/checkpoint và kiểm tra crash giữa bước. Không bỏ candidate validation hoặc rollback recovery để giảm số lần verify.
9. **AX early exit có ràng buộc:** Task81 hiện yêu cầu snapshot không partial và kiểm tra foreground trước/sau. Tối ưu phải giữ match index/match count/partial và guard tương đương, hoặc đưa vào API/mode mới.
10. **Event persistence và protocol phải được giữ:** notification chỉ đánh thức, journal/cursor quyết định replay; kiểm tra lại generation khi đăng ký chờ để không mất wakeup. Không batch durability rồi vẫn hứa hợp đồng cũ. Typed encoder/bridge phải giữ adapter legacy và các trường text/base64 client đang dùng.
11. **Timer persistence và rootfull auto-launch là câu hỏi hợp đồng:** P2-14/P2-15 chưa đủ cơ sở để khẳng định feature toàn hệ thống hỏng. Có consumer auto-launch trong streamd; cần kiểm tra component thực sự cài ở deployment rootfull.

## Danh sách triển khai theo đợt

Cỡ S/M/L là độ phức tạp tương đối, chưa phải cam kết thời gian. Mỗi nhóm lớn cần tách PR nhỏ và chạy probe tương ứng sau thay đổi.

### Đợt 1: lỗi tính đúng đắn

| Nhóm | Mã chính | Công việc | Cỡ | Nghiệm thu |
|---|---|---|---|---|
| A01 | P0-04, P1-06 | Cân bằng child CF ownership; parser có length; truyền độ dài hợp lệ từ mọi caller. | S/M | Payload ngắn/sai count bị từ chối trước injection; 100k touch không tăng live child ownership tuyến tính; kiểm tra retain-after-append trên thiết bị. |
| A02 | P1-07, P1-09, P1-10 | **Đã triển khai; chờ build/device.** Chuẩn hóa finger 0–19; owner/state machine indicator; bỏ NSError** qua async; cleanup client trên owner. | M | Finger 0/19 đúng, index ngoài miền bị chặn; start/stop nhanh không nhân đôi client hoặc lỗi lifetime. |
| A03 | P1-19 | Sửa borrowed color-space release và các Create failure/NULL path của capture. | S/M | Capture iPhone/iPad hai orientation đúng; fault path không dùng NULL/over-release. |
| A04 | P0-15, P0-16, P1-52 | Một owner scheduler, generation theo tên, ack sau commit; reject busy sớm; minimum interval theo chính sách; khóa auto-launch RMW. | M | Sau remove-ack không fire generation cũ; set thay thế chỉ một timer; cập nhật đồng thời không mất key; không đọc config liên tục khi busy. |
| A05 | P0-03, P1-02 | RAW session/state machine; stopping đến khi worker cleanup xong; bỏ nested run loop cho repeat. | M | Stop/start liên tục không injection generation cũ sau khi run mới bắt đầu; không giữ worker repeat vô hạn. |
| A06 | P0-14, P1-45, P1-46 | **Đã triển khai source; giới hạn hợp tác/xác minh còn lại: IMPLEMENTATION-A06.md.** Truyền context/length; reject input dài thay truncate; output budget khi sinh; cancellation/deadline vào handler dài. | M/L | Input dài không thực thi một phần; không materialize response quá cap rồi mới reject; native work dừng theo budget công bố, cleanup vẫn chạy. |

Có thể kéo P1-35 (ColorPicker release lỗi), P1-69 (notification mismatch), P2-06 (accept errno), P2-17 (history lock failure) thành PR nhỏ trong đợt này.

### Đợt 2: hot path và tài nguyên

| Nhóm | Mã chính | Công việc | Cỡ | Nghiệm thu |
|---|---|---|---|---|
| B01 | P0-01, P1-01, P2-04 | **Đã triển khai; người dùng báo build pass; chờ device: IMPLEMENTATION-B01.md.** Owner recorder; timestamp trước I/O; buffer bounded, writer batch, flush/close khi stop. | M | Chuỗi touch tương đương; timing không phụ thuộc write duration; không mất record khi stop; giảm write/event và callback p95/p99. |
| B02 | P0-07, P0-09, P1-20, P1-21, P1-24, P1-26 | **Đã triển khai; người dùng báo build pass; chờ device: IMPLEMENTATION-B02.md.** Move buffer; immutable/ref-counted snapshot; compute ngoài store queue; byte budget; expiry cleanup theo một deadline; monotonic clock. | M/L | Không copy BGRA đầy khung khi insert; release/lookup không chờ cả CV scan; giải phóng payload quá hạn có giới hạn; snapshot sống an toàn sau erase. |
| B03 | P0-05, P1-14, P1-16, P1-17 | **Đã triển khai source phần IPC/socket; người dùng báo build pass; chờ device: IMPLEMENTATION-B03.md.** Bỏ per-touch log; response sink theo nhu cầu; output bounded theo client; tách heavy work/liveness với ordering rõ. | M/L | Task10 không còn ba NSLog/request; slow writer không cắt response âm thầm hoặc chặn mọi client; giữ ACK/error. |
| B04 | P1-12, P0-06, P1-13, P1-18 | **Đã triển khai source; người dùng báo build pass; chờ device: IMPLEMENTATION-B04.md.** H264 no-progress deadline và trả active slot; batch TS; adaptive snapshot ngoài frame loop; absolute pacing. | M | Stalled receiver được ngắt có giới hạn; TS decode đúng; giảm send theo bytes thực gửi; không đọc JSON đồng bộ trong frame loop. |
| B05 | P0-24, P0-02, P1-15, P1-71, P1-72, P1-73, P1-78 | **B05a/B05b đã triển khai; người dùng báo build pass; chờ device: IMPLEMENTATION-B05.md.** License refresh single-flight ngoài hot queue; verified snapshot; RAW session authorization; bounded authority admission; generation/artifact cache. | L | Feature-check còn snapshot hợp lệ không I/O/crypto; authority chậm không giữ hot queue; expiry/revoke/outage vẫn fail-closed đúng hợp đồng. |
| B06 | P0-17, P0-18, P1-55, P1-57, P2-19, P2-20, P2-21 | **Đã triển khai; người dùng báo build pass; chờ device: IMPLEMENTATION-B06.md.** Event-driven wait; client cancellation; trả poll capacity; monotonic timeout; cursor/filter đúng. | M/L | Quiet subscriber không đọc journal 10 lần/s; tám client disconnect không chiếm capacity tới 25s; không mất wakeup/event; replay/gap đúng. |

### Đợt 3: compute, JS, persistence và luồng chuyên biệt

| Nhóm | Mã chính | Công việc và giới hạn |
|---|---|---|
| C01 | P0-10, P0-11, P1-25, P1-27, P1-28, P1-29, P1-30, P1-31, P1-32, P1-33, P1-34, P1-35, P1-36, P1-37, P1-38, P1-39 | **C01a–C01d3 build pass theo người dùng; còn engine/device qualification và retention bảo thủ với dữ liệu không đủ bằng chứng: IMPLEMENTATION-C01D3.md.** OCR/template/color: cache/pixel/scale/tries budget; deadline gồm queue/preprocess/compute; dọn lỗi Vision/ColorPicker; frame reuse; cấu hình OpenCV một lần nếu phù hợp. Không tăng OCR parallelism trước memory budget. |
| C02 | P0-12, P0-13, P1-04, P1-05, P1-40, P1-41 | **C02a–C02b19 build pass theo người dùng. C02b20 input openImage đã triển khai source, chờ CI/device: IMPLEMENTATION-C02B20.md.** RAW/mixed giữ adapter cũ; còn các lệnh P0-13 khác, P0-12 helper transport theo event, P1-40 config snapshot, P1-41 dedupe có byte cap. Giữ ordering, reconnect/dedupe và không lặp side effect. |
| C03 | P1-42, P1-43, P1-44, P1-47, P1-48, P1-49, P1-50, P1-51, P1-53, P1-54, P1-56, P1-58 | Logger bounded/batch; buffered readLine giữ seek/EOF; compact history/lock ngắn/log retention; status snapshot; xử lý commit lỗi/journal recovery; encoder theo protocol. Chốt durability trước thay journal format. |
| C04 | P0-19, P1-62, P1-63 | VPN rootfull khỏi IPC callback đồng bộ dài; deadline bao các bước; admission/coalescing; cache capability bất biến. Không chỉ kéo outer timeout lên 30s rồi giữ nguyên HOL. |
| C05 | P0-20, P1-59, P1-60, P1-61, P1-64 | AX scanned-work budget, cancellation, string/output ceiling; selector scan hợp đồng rõ; cache symbol/capability; giữ foreground safety guard. |
| C06 | P0-22, P0-23, P1-67, P1-68, P1-69, P1-70, P1-74, P1-75, P1-76, P1-77 | StreamControl/TrollStore: helper deadline/terminate/reap; lifecycle queue không chờ vô hạn; BGTask cancel xuống HTTP và chặn late ensure; coalesce decision trước localStatus; broker/poll/preflight; observer cleanup. Transaction lease/checkpoint cần crash recovery riêng. |

### Đợt 4: đo trước hoặc theo phạm vi

- **D01 — P0-08/P1-22/P1-23:** benchmark target-resolution/reusable capture trước đổi private backend. Kiểm tra orientation, keep-screen, màu, iPhone/iPad. Cache device class là bước nhỏ tách được; không cache mù dimensions/orientation.
- **Loại khỏi kế hoạch theo yêu cầu người dùng:** P0-21/P1-65/P1-66/P2-25 thuộc TouchPOC sơ khai. Không phát triển hoặc tối ưu artifact này. Các file còn tên POC trong `stream-app/streamd` là code production TrollStore, vẫn thuộc phạm vi.
- **D03 — các mục đo/điều kiện P2:** theo bảng dưới; không đổi listener/VM/hook lớn trước profile.

## Bảng đối chiếu toàn bộ nhận xét

**Sửa** = lỗi/bounds/lifecycle có căn cứ source; **Tối ưu** = công việc dư/điểm nghẽn có thật, độ lợi chưa đo; **Đo** = chưa đủ cơ sở ưu tiên thay kiến trúc; **Điều kiện** = phụ thuộc artifact/hợp đồng; **Gộp** = không tạo ticket trùng; **Không lỗi** = không phải vấn đề cần sửa. Các nhãn không khẳng định đã tái hiện trên thiết bị.

Nguồn viết theo đường dẫn:dòng tại commit đánh giá. Trong các bảng, đường dẫn rút gọn có gốc pccontrol/, trừ khi đã ghi shared/, stream-app/, appdelegate/, tlinkauto-binary/, license-authority/, vpn-broker/ hoặc poc-trollstore/.

### P0

| ID | Kết luận | Bằng chứng / xử lý |
|---|---|---|
| P0-01 | Tối ưu + sửa timing | Record.xm:137 callback format/encode/write rồi cập nhật baseline. B01. |
| P0-02 | Tối ưu | ScriptPlayer.xm:417 → Task.xm:831 → shared/TLinkLicenseVerifier.mm:1333: mỗi RAW line qua gate/cache queue. B05. |
| P0-03 | Sửa | ScriptPlayer.xm:584 force-stop gọi clear/idle trước worker RAW thoát. A05. |
| P0-04 | Sửa | Touch.xm:208 Create child rồi append không release ownership; HIDInjectCore sibling có release sau append. A01, xác minh private API trên máy. |
| P0-05 | Tối ưu | IPCMessagePort.xm:26 NSString/log/stream cả với task touch không có response body. B03. |
| P0-06 | Tối ưu | H264Stream.xm:431 sendAll từng 188 byte; TCP_NODELAY ở dòng 270. Chỉ nhánh TS. B04. |
| P0-07 | Tối ưu | Image.xm:1036 copy frame→stored→map; vector deep-copy. B02. |
| P0-08 | Đo | H264Stream.xm:719, Screen.xm:127 capture native rồi scale; backend target-size chưa chứng minh chạy đúng. D01. |
| P0-09 | Tối ưu | Image.xm:551,620,804 compute matching/scanning trong image queue. B02. |
| P0-10 | Tối ưu | TesseractOCRTask.mm:181 key chứa PSM/whitelist, cache không trần; third_party/TesseractOCR/TesseractOCR/G8Tesseract.h:112 image strong. C01. |
| P0-11 | Tối ưu | TesseractOCRTask.mm:157 scale tới 4x mỗi chiều rồi copy NSData, thiếu post-scale budget. 33N là mô hình buffer. C01. |
| P0-12 | Tối ưu | TLinkautoJSRuntime.mm:1027,1099 status poll rồi sleep 0.2s; helper client mở socket từng call. Chỉ helper mode. C02. |
| P0-13 | Tối ưu | jsruntime/TLinkInProcessNativeBridge.mm:190 typed method→legacy payload→stream→text parts. C02. |
| P0-14 | Sửa | Bridge dòng 212 gọi processTask; Task.xm:679 truyền context nil. A06. |
| P0-15 | Sửa | Scheduler.xm:169 đọc registry ở caller, insert timer async main, remove không cùng owner. A04. |
| P0-16 | Sửa + chính sách | Scheduler chỉ kiểm tra interval<=0, timer main gọi playScript trước reject busy. Không bảo đảm NSTimer fire ở mọi interval yêu cầu. A04. |
| P0-17 | Tối ưu | shared/TLinkEventChannel.mm:298 read batch + sleep 100000; mỗi read lock/read/parse. Chỉ có tải khi subscribe. B06. |
| P0-18 | Sửa | tlinkauto-binary/SocketServer.mm:87 cleanup không truyền token vào shared poll, slot chỉ trả khi loop xong. B06. |
| P0-19 | Sửa | tlinkauto-binary/SocketServer.mm:482 IPC timeout 5s; Connectivity.xm:81 socket 30s; VPN broker chờ 8/24s. C04. |
| P0-20 | Tối ưu có ràng buộc | shared/TLinkAccessibilityTree.mm:656,740 cap theo rows, find dựa snapshot và matches; giữ completeness/foreground contract. C05. |
| P0-21 | Loại khỏi kế hoạch | poc-trollstore/TunnelExtension/ProviderTCPServer.mm:93,109 client loop cùng accept queue, EAGAIN ngủ 5ms. Không triển khai TouchPOC. |
| P0-22 | Sửa | shared/TLinkVPNPrivateRequest.mm:214 waitpid flags=0, không cancellation/deadline sau spawn. C06. |
| P0-23 | Sửa | stream-app/app/StreamSupervisor.mm:372,422 helper wait vô hạn trên lifecycle serial queue; wait child streamd ở concurrent queue là nhánh khác. C06. |
| P0-24 | Tối ưu quan trọng | shared/TLinkLicenseVerifier.mm:1333–1353 refresh TTL 5s trong dispatch_sync; pccontrol/Makefile bật authority client. B05. |

### P1

| ID | Kết luận | Bằng chứng / xử lý |
|---|---|---|
| P1-01 | Sửa | Record.xm:127,221 schedule/unschedule khác run-loop, thiếu release và owner state. B01. |
| P1-02 | Sửa | ScriptPlayer.xm:541 NSTimer + CFRunLoopRun giữ RAW repeat worker. A05. |
| P1-03 | Đo | ScriptPlayer speed-adjust tạo string trong block dài; cần Allocations trước kết luận memory growth. Kèm A05. |
| P1-04, P1-05 | Tối ưu | Task.xm:126 typed touch→string→parser; dòng 191,327,383 relative sleeps cộng work/oversleep. C02. |
| P1-06 | Sửa | Touch.xm:230 pointer-only, đọc fixed offset theo count. A01. |
| P1-07 | Sửa | TouchIndicator/TouchIndicatorWindow.xm:304 check>=20 nhưng truy cập index-1 với finger 0. A02. |
| P1-08 | Tối ưu | Indicator dòng 388 async main mỗi move, format/font/layout mỗi lần. Coalesce sau khi sửa lifecycle A02. |
| P1-09, P1-10 | Sửa | Indicator dòng 136 capture NSError** async, isShowing set muộn; dòng 120 cleanup rồi NULL không CFRelease. A02. |
| P1-11 | Đo / chỉnh thread | Tweak.xm:308 đọc UIScreen trên global queue; đưa UIKit-derived state về main. Chưa có bằng chứng crash cụ thể. |
| P1-12 | Sửa | H264Stream.xm:195,268 blocking send không no-progress deadline, giữ active slot. B04. |
| P1-13 | Tối ưu | H264Stream.xm:705 và shared/TLinkAdaptiveStreaming.mm lock/read/parse trong frame loop. B04. |
| P1-14 | Tối ưu kiến trúc | IPCMessagePort.xm:64 task sync; daemon serial socket/ipc queues. B03/C04. Task95 đã deferred, không coi thời gian chờ poll là chặn socketQueue. |
| P1-15 | Tối ưu | Gate daemon và SpringBoard đều có thật; giữ cả hai ranh giới, làm lookup rẻ hơn. B05. |
| P1-16 | Sửa | tlinkauto-binary/SocketServer.mm:668 wrote<=0 thì break không remainder/error. B03. |
| P1-17, P1-18 | Tối ưu | IPC response logging/copy; H264Stream.xm:748,899 relative pacing và pool-unavailable sleep sau capture. B03/B04. |
| P1-19 | Sửa | Screen.xm:189–219 release Get-rule colorSpace và Create failure chưa kiểm tra. A03. |
| P1-20, P1-21 | Tối ưu | Image.xm:999 lazy expiry; dòng 73,982 giới hạn 64 image nhưng không byte cap/TTL cleanup. Không gọi là unbounded frame leak. B02. |
| P1-22 | Tối ưu / đo pool | Screen.xm:127 uname/regex/properties/surface mỗi capture. Cache invariant trước, thử surface pool sau. D01. |
| P1-23 | Đo | Image.xm:441 gray-only vẫn tạo BGRA để convert; direct-gray cần kiểm tra tốc độ/chất lượng. D01. |
| P1-24 | Gộp | Image.xm:923–961 ROI clone/cvtColor trong store queue, cùng P0-09/B02. |
| P1-25 | Tối ưu | TemplateMatch.xm:115–185,407 cache count-bounded, scale vector không byte cap. C01. |
| P1-26 | Sửa kèm subsystem | Image.xm:81,999 wall-clock/unsigned age cho TTL. B02. |
| P1-27 | Sửa deadline | Tesseract recognitionTime=3s không bao queue/preprocessing. C01. |
| P1-28, P1-29 | Tối ưu + deadline | TextRecognization/TextRecognizer.xm full capture rồi crop; VKOcrManager.xm:122 synchronous performRequests không app deadline/cancel. C01. |
| P1-30 | Sửa phòng lỗi | VKOcrManager.xm:135,236 topCandidates[0] thiếu guard empty. Tần suất xảy ra chưa đo. C01. |
| P1-31 | Sửa nhỏ | VKOcrManager.xm:124 error return trước reset inProgress; caller hiện tạo instance mới nên tác động hạn chế. C01. |
| P1-32, P1-33, P1-34 | Tối ưu + budget | ColorPicker full capture cho pixel/ROI; nested loop NSValue getValue; thiếu compute deadline/work cap. C01. |
| P1-35 | Sửa | ColorPicker.xm:179–211 validation return sau capture không release screen. PR nhỏ đợt 1 hoặc C01. |
| P1-36, P1-37 | Sửa deadline/budget | TemplateMatch.xm:407–429 resize trước timer; dòng 434 chỉ check timeout giữa scale, không trong SAD scan. C01. |
| P1-38 | Tối ưu nhỏ / đo | TemplateMatch.xm:368 setNumThreads(1) mỗi match; chuyển init nếu không xung đột consumer khác. C01. |
| P1-39 | Gộp | Capture/conversion trùng P1-28/P1-32/P2-07; chung frame adapter C01. |
| P1-40, P1-41 | Tối ưu | TLinkautoJSRuntime.mm:1061 đọc config mỗi RPC mới; cache 256 entry không byte cap. 256MiB là giả định payload, không RSS đo. C02. |
| P1-42 | Tối ưu | jsruntime/TLinkJSRuntimeCore.mm:213–259 hai log path, I/O từng line, queue không trần; console có NSLog sync. C03. |
| P1-43 | Tối ưu | shared/TLinkJSFileHandle.mm:200 read một byte/vòng trong readLine; buffered reader phải giữ seek/read mix semantics. C03. |
| P1-44 | Tối ưu có contract | FileHandle dòng 49 luôn tạo cả text/base64; không bỏ trường cũ âm thầm. C03. |
| P1-45, P1-46 | Đã sửa source | A06: P1-45 là response sink cap khi ghi; P1-46 là reject input quá 8192 UTF-16 units trước dispatch. Giới hạn producer/RSS còn ghi rõ tại IMPLEMENTATION-A06.md. |
| P1-47 | Tối ưu | Bridge storage handlers có chuyển đổi text/data/JSON lặp. C03. |
| P1-48, P1-49 | Tối ưu | shared/TLinkRunHistory.mm begin/finish rewrite index chứa evidence; redact/tail/evidence sau khi lấy flock. C03. |
| P1-50 | Sửa retention | Logger tạo _logs/runId.log; history prune chỉ xóa dưới run-history root, không giới hạn số run logs. C03. |
| P1-51 | Tối ưu | Task.xm:1502 gọi RunHistorySnapshot/EventChannelStatus đọc persistence mỗi status. Cadence thực tế cần đo. C03. |
| P1-52 | Sửa concurrency | Scheduler.xm:95 load→mutate→atomic save không khóa RMW; kiểm tra writers cùng deployment. A04. |
| P1-53 | Sửa | shared/TLinkRunHistory.mm bỏ qua BOOL write, vẫn publish event. C03. |
| P1-54 | Tối ưu có durability | shared/TLinkEventChannel.mm:167–186 read/parse/rewrite journal mỗi publish; sau B06 và đo cadence publisher. C03. |
| P1-55, P1-57 | Gộp | Poll global worker ngủ 100ms; reader dùng LOCK_EX. Chung P0-17/B06; đổi LOCK_SH đơn lẻ không hết polling. |
| P1-56 | Tối ưu có protocol | Task95 JSON/base64/legacy rồi JSON frame; output về serial socketQueue. B03/C03, giữ wire contract. |
| P1-58 | Sửa recovery | EventChannel dòng 105–120 read lỗi→next_sequence=1, không epoch/error rõ. C03. |
| P1-59, P1-60 | Sửa cancellation/bounds | shared/TLinkAccessibilityTree.mm:699,782,805 serial dispatch_sync không token; string/output không byte cap. C05/A06. |
| P1-61 | Tối ưu | AX lock/capability lặp notify/dlopen/dlsym/SecTask; initializer AX chính đã dispatch_once. C05. |
| P1-62, P1-63 | Tối ưu + admission | shared/TLinkVPNDiagnostics.mm mười entitlement query/snapshot; vpn-broker accept→global worker→semaphore, không cap active client. C04. |
| P1-64 | Đo | Task.xm lấy foreground trước/sau; SpringBoard context sync main. Giữ safety guard, đo trước đổi. C05. |
| P1-65, P1-66 | Loại khỏi kế hoạch | poc-trollstore/AppDelegate.mm silent audio; TunnelExtension/PacketTunnelProvider.mm heartbeat/file-state/log 1Hz kể cả command không đổi. Không triển khai TouchPOC. |
| P1-67 | Tối ưu riêng TrollStore | shared/TLinkVPNManager.mm private backend polling 100ms/50 verify attempts; rootfull public NEVPN path không phải loop này. C06. |
| P1-68 | Sửa admission/queue | stream-app/app foreground broker handle sync trong accept; stream-app/vpnagent dùng global workers không cap. C06. |
| P1-69 | Sửa nhỏ | appdelegate/UIKeyboard.xm:54,65,73 add keyboardcontrol/remove textinput. Duplicate delivery chỉ là rủi ro cần đo. |
| P1-70 | Gộp theo runtime | Foreground broker/vpnagent full static preflight, mở rộng P1-62; mutable VPN state vẫn phải fresh. C06. |
| P1-71 | Tối ưu | Verifier dòng 1337 generation poll 0.25s theo feature call, không phải timer idle. B05. |
| P1-72 | Sửa admission | license-authority/main.mm:175 accept→global worker; listen backlog=16 không phải active worker cap. B05. |
| P1-73 | Tối ưu có trust contract | Authority client/local verifier lặp lease/key/proof; cache artifact nhưng vẫn ký nonce/freshness đúng. B05. |
| P1-74 | Tối ưu rủi ro cao | stream-app/app/LicenseManager.mm:321 save lease nhiều pass/checkpoint reset; giữ validation và rollback recovery. C06. |
| P1-75 | Tối ưu | stream-app/app/LicenseLifecycleCoordinator.mm refreshForTrigger gọi localStatus trước beginOperation. C06. |
| P1-76 | Sửa | stream-app/app/BackgroundServiceScheduler.mm:178–200 expire/watchdog finish không cancel HTTP/token; late ensure vẫn chạy. C06. |
| P1-77 | Tối ưu | stream-app/app/LicenseLifecycleCoordinator.mm:237,255 diagnostics plist RMW nhiều lần/operation. C06. |
| P1-78 | Tối ưu | tlinkauto-binary/SocketServer.mm:825–891 diagnostic tasks gọi full status trực tiếp. B05, API freshness rõ. |

### P2

| ID | Kết luận | Xử lý |
|---|---|---|
| P2-01 | Đo | Popup HID callback có chi phí, chưa biết đáng kể không; đo count/CPU trước thay registration. |
| P2-02 | Gộp / sửa tài liệu | Hai listener là mô tả cũ; gộp P2-05 sáu listener. |
| P2-03 | Không lỗi | Scan cố định 20 slot bounded, không ưu tiên tối ưu. |
| P2-04 | Gộp | Clock/baseline recorder và field range dư, chung B01. |
| P2-05 | Đo | Sáu blocking accept worker có footprint; không kết luận high CPU khi idle. |
| P2-06 | Sửa nhỏ | Accept failure không phân loại errno; tách transient/fatal, kèm B04 hoặc PR nhỏ đợt 1. |
| P2-07 | Tối ưu có semantics | Capture-once/use-many cho workflow high-rate; frame reuse không thay ngầm yêu cầu fresh image. C01. |
| P2-08 | Sửa edge case | Template key mtime giây+size có thể stale khi rewrite cùng giây/cùng size. C01. |
| P2-09 | Đo | check_langs quét tessdata mỗi call; chỉ cache khi cadence đáng kể và có invalidation. |
| P2-10 | Không lỗi | Serial Tesseract không tự nó là performance bug; không tăng parallelism trước memory budget. |
| P2-11, P2-12 | Sửa kèm subsystem | JS NSDate deadline và hardware key sleep 50ms không interruptible; ưu tiên sau native context. A06/C02. |
| P2-13 | Đo | VM/context/prelude mới mỗi run là startup cost; không pool trước đo và kiểm tra isolation. |
| P2-14, P2-15 | Điều kiện | Timer process-lifetime; chưa thấy auto-launch consumer trong pccontrol nhưng streamd có. Chốt yêu cầu restart/component deployment trước sửa. |
| P2-16, P2-17, P2-18 | Sửa/tối ưu kèm subsystem | History duration dùng wall time; snapshot thiếu lockFd<0 guard; directory/permission metadata lặp. C03. |
| P2-19 | Sửa | Event timeout unsigned wall-clock elapsed có thể underflow. B06. |
| P2-20, P2-21 | Tối ưu nhỏ | Regex compile mỗi request, không mỗi poll iteration; cursor có thể advance qua trailing unmatched đã quét, giữ pagination đúng. B06. |
| P2-22, P2-23 | Sửa budget / đo fallback | AX wall deadline, remote attribute có thể overshoot; PID fallback scan process/plist không phải đường thường khi PID sẵn có. C05. |
| P2-24 | Đo | dyld hook có strlen/strcmp, nhưng suffix constant có thể được compiler fold; cần call-volume/CPU profile trước ưu tiên. |
| P2-25 | Loại khỏi kế hoạch | Timer UI 1Hz chỉ TouchPOC; không khẳng định app suspended vẫn fire 1Hz. Không triển khai TouchPOC. |
| P2-26 | Sửa kèm subsystem | Private VPN NSDate deadline; dùng monotonic elapsed budget. C06. |
| P2-27 | Tối ưu có invalidation | Cache build/config bất biến; lease/revocation/expiry vẫn fresh theo chính sách. B05. |
| P2-28 | Sửa kèm subsystem | Monotonic retry/backoff trong process; persisted epoch vẫn cần cho restart/license expiry. C06. |

## Kế hoạch đo và kiểm tra

1. Baseline riêng từng runtime: rootfull SpringBoard/daemon và StreamControl/TrollStore; không đo TouchPOC. Ghi commit/build flags, thiết bị/iOS, physical resolution, profile/bitrate, thermal state và workload.
2. A01–A06: repro và correctness regression trước, theo S002/S004/S006/S007. Tách PR ownership/bounds nhỏ khỏi PR thay transport/ownership lớn.
3. B01–B06: cùng trace trước/sau; thu CPU time, allocations/live bytes/RSS, syscall/file I/O, queue wait, p50/p95/p99 latency, dropped event/frame, wakeups và Energy Log. Dùng aggregate counters/signpost sampling, không thêm per-event production log để đo.
4. S008: idle subscription/disconnect/cursor; S009: VPN timeout/AX; S010: helper/lifecycle và POC; S011: license cache miss/generation/BGTask. Thử authority chậm/down, revoke/expiry/mất notification, stalled socket, cancel giữa native call, disk full, crash giữa commit.
5. Phân biệt nghiệm thu chức năng và hiệu năng: lỗi ownership/bounds có thể cần sửa dù chưa đo CPU; thay capture backend/transport/cache lớn chỉ nhận khi có số trước/sau và không giảm bảo đảm hiện tại.

Điểm bắt đầu đề xuất: **A01 → A02 → A03 → A04 → A05 → A06**, rồi **B01/B02/B03/B04**. B05 và B06 có giá trị lớn nhưng cần thiết kế snapshot/invalidation/cancellation trước triển khai. Các nhóm C được ưu tiên lại theo workload thực và kết quả benchmark, không theo số lượng nhãn P0 trong audit.