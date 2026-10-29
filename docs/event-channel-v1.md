# Event Channel bất đồng bộ v1

Trạng thái: đã triển khai cho rootfull và TrollStore; chờ xác nhận trên thiết bị.

Event Channel bổ sung task `95` theo giao thức `task95_long_poll_v1`. Nó không
thay đổi response của task cũ và không mở thêm cổng. Client gửi cursor cuối đã
xử lý, server chờ tối đa 25 giây rồi trả một batch Base64 JSON.

```text
95<cursor>;;<timeout_ms>;;<max_events>;;<topic_csv>
```

Response thành công là `0;;<base64-json>`. Schema `event_channel_v1` gồm
`next_cursor`, `oldest_cursor`, `latest_cursor`, `gap`, `has_more`,
`timed_out`, và `events`. Mỗi event dùng `tlink_event_v1` với sequence toàn
cục, UUID, timestamp, runtime, topic, type và payload.

## Bảo đảm và giới hạn

- Journal dùng chung rootfull/TrollStore, cập nhật nguyên tử với `flock`.
- Giữ 256 event gần nhất; mỗi poll tối đa 32 event.
- Tối đa 8 long-poll đồng thời cho mỗi runtime process.
- Payload event tối đa 4 KiB; payload lớn được thay bằng metadata truncated.
- Delivery là at-least-once: client chỉ lưu cursor sau khi xử lý batch.
- Nếu cursor cũ hơn retention, `gap=true` cùng `oldest_cursor` được trả rõ ràng.
- Topic filter là exact match hoặc `*`; topic v1 đầu tiên là `script.run`.
- Long-poll chạy ngoài socket serial queue nên không chặn touch/task khác.
- WebTango subscription dùng WebSocket riêng để không trộn response với control.
- Task `95` tuân theo license feature `automation`; nhánh deferred vẫn kiểm tra
  gate trước khi bắt đầu long-poll.

Run History phát `script.run` với các type `started`, `finished`, `failed`,
`cancelled`, và `license_revoked`. Adaptive Streaming phát `stream.health`
cho lifecycle, downgrade/recovery và self-healing.

## Capability task 97

```text
eventChannelState=implemented
eventChannelVersion=1
eventChannelSchema=event_channel_v1
eventChannelTransport=task95_long_poll_v1
eventChannelResume=cursor_v1
eventChannelJournalMaxEvents=256
eventChannelPollMaxEvents=32
eventChannelPollTimeoutMaxMs=25000
eventChannelDeviceValidated=0
```

WebTango cung cấp `device.pollEvents()` và `device.subscribeEvents()`. Hàm
subscribe trả về callback `unsubscribe()`, reconnect với exponential backoff,
và tiếp tục cursor trên kết nối event chuyên dụng mới.

## B06: chờ và hủy theo transport

Task 95 của TCP/root JSON và remote bridge dùng đăng ký bất đồng bộ. Sau khi
ghi journal thành công, publisher phát Darwin notification; journal/cursor vẫn
quyết định replay. Một timer chung chỉ kiểm tra metadata mỗi giây khi có poll,
để bù thông báo bị mất. File không đổi không bị đọc/parse lại; hết poll thì timer
dừng. Reader dùng shared lock; owner không chờ file lock đang bị giữ.

TCP cleanup hủy token và trả poll capacity ngay khi xử lý disconnect. Remote
bridge hủy khi control WebSocket của thiết bị ngắt, đồng thời chặn response của
kết nối cũ. Browser ngắt riêng ở phía relay cần relay truyền cancellation;
thiết bị không suy đoán việc đó. Authorization có admission riêng tối đa 8,
timeout chờ 5 giây; timeout poll 0–25 giây bắt đầu sau authorization. Deadline
dùng monotonic clock, timestamp event vẫn dùng wall clock.

`next_cursor` có thể đi qua các event không khớp topic đã quét, kể cả phần đuôi;
không đi qua matching event bị giữ lại cho trang tiếp theo. Base64/schema và
hợp đồng at-least-once giữ nguyên.

Probe tám disconnect trên thiết bị yên lặng: thêm `-RunCancellationStress` vào
`scripts/Test-TLinkEventChannelV1.ps1`. Build/device và kiểm thử Foundation mới
cần được xác nhận; chi tiết giới hạn và kế hoạch đo ở
[IMPLEMENTATION-B06.md](performance-audit/IMPLEMENTATION-B06.md).

## C03n: bảo vệ journal khi publish

Publisher chỉ khởi tạo sequence 1 khi reader nhận lỗi Cocoa xác nhận file chưa
tồn tại. File trống, JSON/schema hỏng, lỗi đọc hoặc NSError không xác định trả
`state=error` và giữ journal; không ghi đè bằng journal rỗng hay phát notification.
Lỗi trả về qua API publish nội bộ gồm `event_journal_read_failed`,
`event_journal_invalid`, `event_journal_sequence_exhausted` và
`event_journal_exception`; lỗi lock/write hiện có giữ nguyên tên.

Reader dành riêng cho publish kiểm tra schema, tối đa 256 event, các trường
chuẩn đúng kiểu và sequence nguyên dương, liên tiếp, kết thúc tại
`next_sequence - 1`. Boolean, chuỗi, phân số, số âm và số vượt uint64 không được
chấp nhận làm sequence. Journal rỗng có next_sequence hợp lệ khác 1 vẫn được
giữ cursor đó; không tự reset. Khi next_sequence bằng UINT64_MAX, publisher
dừng thay vì cộng tràn hoặc dùng lại sequence.

Ngoại lệ NS/C++ trong phần đọc/kiểm tra/dựng/ghi dưới khóa trả lỗi cố định;
`finally` nhả khóa. Chỉ sau ghi thành công và unlock mới phát Darwin notification.
Lỗi báo sau khi atomic write đã có hiệu lực có thể để lại event đã commit trên
đĩa nhưng chưa phát hint; lần publish sau đọc journal thực tế, không tự phát lại
publication lỗi. Poll vẫn có reconciliation để bù hint bị mất.

C03n chỉ bảo vệ publisher; C03o bên dưới mở rộng reader kiểm tra sang poll/status. Không phục hồi file hỏng, tái dựng epoch khi file bị mất,
replay event lỗi hay thêm fsync/power-loss guarantee. History và event journal
vẫn là hai giao dịch riêng; script lifecycle giữ chính sách phát event best effort.
Schema, task 95, payload/retention, wire và các trường thành công không đổi.
Đọc/parse/rewrite journal toàn phần và đo chi phí validation trên thiết bị còn
trong backlog C03/P1-54/P1-58; fixture Foundation mới chờ CI macOS.

## C03o: báo lỗi đọc ở poll/status và bỏ snapshot cũ

Publisher, poll và status dùng chung reader kiểm tra schema/shape/cursor của
C03n. Journal hỏng trả `event_journal_invalid`; lỗi đọc trả
`event_journal_read_failed`; NS/C++ exception trả `event_journal_exception`.
Loader bắt ngoại lệ và nhả shared flock/descriptor bằng finally. Không sửa hoặc
ghi lại journal khi đọc lỗi.

Poll đã được authorization gặp lỗi dữ liệu/đọc/exception kết thúc ngay với
error và không có batch. Adapter legacy/TrollStore/remote trả đường lỗi hiện có,
root JSON trả ok=false; client giữ cursor đã commit và có thể retry sau khi
storage được sửa. Authorization denial vẫn đi trước việc đọc dữ liệu. Không
biến lỗi đọc thành batch ready rỗng, gap hay next_cursor=0.

Mỗi lần tải snapshot thất bại đều bỏ snapshot và fingerprint đã cache, kể cả
khi còn poll khác đang chờ authorization. Nếu lấy khóa nonblocking thất bại,
owner vẫn giữ poll tới timeout và báo `event_journal_unavailable`; nó không
phục vụ snapshot cũ trong lúc đó. Hủy vẫn trả capacity ngay; lần yêu cầu hoặc
reconciliation kế tiếp có thể đọc lại sau khi lỗi hết.

Status khỏe mạnh giữ state=implemented và các trường cũ. Khi tải thất bại,
status trả state=error cùng error cố định; latest_cursor=0 lúc lỗi là giá trị
chưa biết, không phải xác nhận journal đã reset. Consumer phải kiểm tra state
và không cập nhật cursor từ status lỗi.

File thực sự chưa tồn tại vẫn được đọc như journal rỗng, không tạo journal JSON
mới. Journal next_sequence=UINT64_MAX vẫn đọc được cursor cuối, dù publisher
không thể cấp sequence mới. Thay đổi không bổ sung epoch khi mất file, sửa file
hỏng, replay hay fsync/power-loss durability. Cache vẫn dựa vào fingerprint và
reconciliation cũ; thay đổi ngoài giao thức không có bảo đảm phát hiện tức thì.
Fixture Foundation/POSIX/transport mới và đo thiết bị còn chờ CI/nghiệm thu.

## C03p: kiểm tra root và inode khóa

Root trực tiếp phải là directory thực; nếu chưa có thì tạo như trước. Từ chối
root là symlink/file trước khi áp dụng quyền hoặc mở khóa. Ancestor của đường
dẫn cố định vẫn theo bố trí filesystem hiện có.

Mở journal.lock với O_NOFOLLOW và O_NONBLOCK, kiểm tra fstat phải là file thường
có đúng một hardlink trước flock. Sau khi lấy khóa, lstat đường dẫn phải khớp
device/inode đã mở, vẫn là file thường một link và root trực tiếp vẫn là directory.
Nếu đường dẫn bị thay/mất/thêm hardlink trong lúc chờ, nhả khóa và đóng descriptor
trước khi đọc journal. Chỉ sau xác thực mới fchmod/fchown descriptor khóa; không
sửa quyền pathname thay thế. Kết quả lỗi dùng nhãn hiện có:
publisher event_journal_lock_failed; status/poll event_journal_unavailable.
Poll vẫn giữ chính sách timeout khi không lấy được khóa.

O_NONBLOCK bảo vệ bước open file đặc biệt; flock của publisher/status vẫn có
chính sách blocking hiện tại, owner poll vẫn nonblocking. Reader giữ LOCK_SH,
writer LOCK_EX. Lỗi open/stat/type/identity không đọc/ghi journal hoặc phát hint;
không tự xóa, thay hay sửa file khóa bị từ chối.

Mọi writer/reader/maintenance cùng deployment phải giữ một inode khóa ổn định:
không replace, unlink hoặc alias nó khi còn operation có thể hoạt động. Các kiểm
tra này phát hiện đường dẫn không hợp lệ ở thời điểm admission; không tạo bảo
đảm chống mọi race do actor ngoài giao thức. Chính sách best effort khi syscall
áp dụng permission báo lỗi vẫn giữ nguyên. Không thêm epoch, fsync hoặc cam kết
durability. Chi phí metadata/lock và hành vi filesystem trên thiết bị còn cần đo.

## C03q: giới hạn byte và kiểu file journal trước parse

Reader dùng chung mở journal.json bằng O_RDONLY|O_NOFOLLOW|O_NONBLOCK dưới flock
hiện có. Chỉ nhận file thường, size không âm và tối đa 4 MiB trước khi cấp buffer
hoặc parse JSON. Chỉ errno ENOENT từ open mới xác nhận journal chưa tồn tại;
không còn dựa vào NSError của NSData để bootstrap. Symlink (kể cả dangling),
FIFO, directory và lỗi open/stat trả event_journal_read_failed, không bị đọc như
journal rỗng. Không sửa/xóa file bị từ chối.

File lớn hơn 4 MiB trả event_journal_too_large qua publisher, poll và status;
poll giữ cursor và trả lỗi theo adapter sẵn có. Đọc đúng size đã kiểm tra, mỗi
syscall tối đa 64 KiB, thử lại EINTR và xử lý short reads. EOF sớm/lỗi đọc trả
read_failed; một probe thêm tối đa một byte kiểm tra tăng size. Growth ở ranh
4 MiB trả too_large; growth trong file nhỏ hơn trả read_failed. Descriptor được
nhả trong finally, kể cả NS/C++ exception; reconciliation/explicit retry có thể
đọc lại sau khi storage được sửa.

Writer cũng từ chối dữ liệu JSON đã mã hóa vượt 4 MiB trước atomic write, dùng
lỗi event_journal_write_failed hiện có, không phát hint hoặc thay file cũ. Journal
đúng ngưỡng vẫn được reader nhận. 256 event với payload 4096 byte và metadata
chuẩn còn cách xa ngưỡng này; extension data bên ngoài quá lớn cần được giảm
hoặc khôi phục bằng thao tác bảo trì rõ ràng, không tự truncate.

Giới hạn này áp dụng cho byte file/buffer đọc và byte đầu ra journal. Nó không
là trần RSS/JSON graph, thời gian I/O hoặc bước mã hóa payload đầu vào. Writer
vẫn encode trước kiểm tra output; journal vẫn được read/parse/rewrite toàn phần.
Schema/wire/retention/cursor và giao thức inode không đổi. Không thêm epoch,
fsync, phục hồi file hỏng hoặc bảo đảm cho actor sửa file ngoài giao thức atomic
write/flock. Build C03q đã pass theo người dùng; số đo và nghiệm thu thiết bị còn mở.

## C03r: envelope JSON-v1 trực tiếp cho Task 95 trên root

Phản hồi Task 95 bất đồng bộ dùng JSON-v1 trên rootfull/roothide tạo envelope
thành công trực tiếp từ JSON batch và base64, bỏ bước dựng chuỗi legacy rồi
chuyển UTF8/tách lại. Hợp đồng giữ nguyên: `id` theo request (mặc định 0),
`ok=true`, `data=["<base64 JSON batch>"]`, `error=null`. Không chuyển `data`
thành object batch; client/SDK không cần đổi. Bộ đóng frame ZXTP, giới hạn body
1 MiB và lỗi response_too_large/response_encode_failed giữ nguyên.

Lỗi vẫn qua encoder/parser legacy hiện có để giữ cách xử lý denial đã định dạng,
delimiter, newline, NUL và lỗi event_channel_json_failed. Serialization exception
giữ cách truyền lỗi trước đây. Nhánh legacy root, TrollStore và remote không đổi;
authorization, cancellation, request identity và output owner cũng giữ nguyên.

Đối chiếu fixture với encoder frozen ở build `0340a8e3` kiểm tra envelope/base64,
ID/lỗi, ngưỡng frame và vòng đời qua autorelease pool. Các ca Foundation/ARC mới
chờ CI macOS; chưa có số đo allocation/RSS/latency trên thiết bị. Base64 và toàn
bộ JSON serialization vẫn còn, nên P1-56 chưa được đóng toàn bộ.
