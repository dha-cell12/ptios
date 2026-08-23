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
