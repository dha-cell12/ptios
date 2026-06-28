Phase 4 Plan — Updated

Mục tiêu: productionize helper runtime và hoàn thiện nhóm API còn thiếu theo thứ tự an toàn, tránh duplicate RPC, tránh silent fallback, và tránh leak frame/image handles.

Trạng thái Phase 3 đã xác nhận:

- Helper daemon single-instance ổn.
- --run-script direct helper execution ổn.
- --client-run daemon socket path ổn.
- UI playback qua helper gate ổn.
- Native RPC toast, tap, swipe, smoke read APIs đã chạy ổn sau fix getScreenSize.ok.
- Code hiện có broad native RPC wrappers cho non-handle APIs.

Caveat còn nên test thêm:

- JavaScriptCore Helper UI RPC Demo mới nhất: clipboard RPC.
- Một số API có side effect mạnh đã expose nhưng chưa nên demo mặc định: killApp, openUrl, connectivity setters, hardware keys, runShell.

1. RPC Idempotency + Concise Logs

- SpringBoard cache result theo sessionId + nativeRequestId.
- Nếu poll thấy lại cùng request:
  - không execute lại.
  - gửi lại cached result.
- Cache giới hạn 256 request gần nhất mỗi helper run/session.
- Log ngắn:
  - helper request method/requestId.
  - SpringBoard handled method/requestId ok/error.
  - helper response accepted requestId.

2. Helper-Local Storage APIs

Implement trong helper process, không qua SpringBoard:

- readText
- writeText
- readJSON
- writeJSON
- fileExists
- deleteFile

Sandbox rules:

- Chặn absolute path.
- Chặn path escape khỏi bundle.
- Chặn manifest.json.
- Chặn info.plist.
- Chặn write .js source files.
- Create parent khi write.
- Max file size 512 KiB.

Lý do: storage thuộc bundle path helper đã biết, không cần native RPC.

3. Config Gate + Fail-Clear Behavior

Thay marker file bằng config:

- /var/mobile/Library/TLinkauto/config.json
- key: javascript_helper_runtime_enabled

Behavior:

- Manifest không request helper: chạy in-process.
- Manifest request helper + config bật: chạy helper.
- Manifest request helper + config tắt/missing/invalid: fail rõ helper runtime requested but disabled.
- Không silent fallback khi manifest đã request helper.

4. Frame Handle RPC + Session Ownership

Không truyền raw pointer/object. Helper chỉ nhận opaque numeric handles qua RPC response.

SpringBoard handle tracking phải gắn ownership:

- ownerSessionId
- ownerRunId
- ownerRuntime = helper
- createdAtMs
- ttlMs
- released

RPC frame group:

- captureFrame
- releaseFrame
- releaseAllFrames
- framePickColor
- framePickColors
- frameFindColor
- frameIsColors
- frameFindMultiColor

Rules:

- releaseAllFrames chỉ release handles của session hiện tại.
- Auto-release handles khi helper session completed/failed/cancelled/timeout/stop.

5. Image Handle RPC

Sau frame stable, thêm:

- openImage
- captureImage
- releaseImage
- findImageInFrame

Dùng cùng owner/session cleanup model với frame.

6. OCR RPC

Sau image/frame stable, thêm:

- ocrLanguages
- ocrFrame
- ocr

Với ocr(): SpringBoard bridge auto capture/release để helper không leak handle.

7. Safe Demos

- Helper Storage Demo
- Helper Frame Color Demo
- Helper Image Demo
- Helper OCR Demo
- Helper Full Safe Smoke Demo

Không demo destructive APIs mặc định.

8. Default / Runtime Policy Decision

Sau khi tests ổn:

- Quyết định runtimeLocation: helper có chạy production path hay vẫn gate bằng config.
- Chưa đặt helper làm default cho mọi .js.

Verification

CLI:

- --client-handshake
- --client-status
- --client-run

UI:

- config bật/tắt helper.
- run demos.
- confirm _logs/latest-helper.log.
- confirm no duplicate helper process.
- confirm duplicate nativeRPC requestId không execute lại.
- confirm no stale handles after completed/failed/cancelled/timeout/stop.

Thứ tự triển khai Phase 4:

1. RPC idempotency + logs.
2. Helper-local storage APIs.
3. Config gate + fail-clear behavior.
4. Frame handle RPC + auto-release.
5. Image handle RPC.
6. OCR RPC.
7. Safe demos.
8. Default/runtime policy decision.
