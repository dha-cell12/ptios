# Adaptive Streaming & Self-Healing v1

Trạng thái: đã triển khai cho rootfull, TrollStore và WebTango; chưa xác nhận trên thiết bị.

V1 giữ nguyên sáu port `7001-7006`, profile hiện hữu và header frame `ZXH2`.
Thay đổi chất lượng chỉ áp dụng động lên FPS và bitrate, không đổi kích thước encoder
giữa phiên nên decoder cũ tiếp tục tương thích.

WebTango gửi tối đa một feedback mỗi giây qua task `94`:

```text
94<base64(stream_feedback_v1 JSON)>
```

Feedback gồm `port`, `fps`, `kbps`, `decode_queue`, `dropped`,
`total_approx_ms` và `stalled`. Task `94` thuộc license feature `stream`.
Payload tối đa 16 KiB và chỉ chứa số liệu bounded. Server chỉ ghi nhận tối đa
một feedback cho mỗi port trong 750 ms để tránh write amplification.

## Policy điều chỉnh

- Ba mức: `high`, `balanced`, `survival`.
- Hai mẫu degraded liên tiếp hạ một mức; severe/stall hạ ngay một mức.
- Bốn mẫu tốt liên tiếp mới nâng một mức.
- Mỗi lần đổi mức có cooldown 5 giây để tránh dao động.
- Feedback mới có hiệu lực trong 5 giây; feedback mất lâu dùng `balanced` fail-safe.
- Target adaptive không vượt trần FPS/bitrate do thermal controller quyết định.
- `balanced`: khoảng 70% FPS và 65% bitrate gốc.
- `survival`: khoảng 45% FPS và 35% bitrate gốc, vẫn tôn trọng min FPS và bitrate 200 Kbps.

## Self-healing

- Native encoder tự tạo lại tối đa ba lần khi submit hoặc callback timeout.
- Encoder cũ được invalidate/drain trước khi trả frame context về pool.
- WebTango worker phát hiện không có frame trong 3 giây, socket close và decoder error.
- Client reconnect tối đa sáu lần với exponential backoff từ 250 ms đến 5 giây.
- Metrics, adaptation, recovery và failure được lưu trong task `60` tại
  `adaptive_streaming` và phát topic Event Channel `stream.health`.

Capability task `97`:

```text
adaptiveStreamingState=implemented
adaptiveStreamingVersion=1
adaptiveStreamingSchema=adaptive_streaming_v1
adaptiveStreamingFeedback=task94_base64_json_v1
adaptiveStreamingLevels=high,balanced,survival
adaptiveStreamingSelfHealing=encoder_restart_3_client_reconnect_6
adaptiveStreamingDeviceValidated=0
```

## Test thiết bị

```powershell
./scripts/Test-TLinkAdaptiveStreamingV1.ps1 `
  -HostIP "192.168.1.244" `
  -Runtime trollstore
```

Dùng `-RunFeedbackSmoke` để gửi hai mẫu degraded, chờ cooldown, rồi xác nhận
task `60` cho thấy level đã hạ. Test stall/reconnect cần mở WebTango và tạm ngắt
mạng hoặc restart runtime trong khi stream đang hiển thị.
