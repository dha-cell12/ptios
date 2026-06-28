Phase 5 Plan Mục tiêu: chuyển helper runtime từ “feature-complete prototype” sang “production-ready runtime path” có policy rõ, observability tốt, test coverage thực tế, và chuẩn bị quyết định default runtime.

0. Pre-Phase Cleanup

Sửa docs Phase 4 còn lệch:
Thay marker gate cũ bằng config.json.
Cập nhật storage/frame/image/OCR support statu ở docs/tlinkauto-js-runtime.md
Chạy lại smoke demos sau cleanup:
Helper Storage Demo
Helper Frame Color Demo
Helper RPC Smoke Demo
Helper UI RPC Demo
1. Runtime Policy Hardening

Chuẩn hóa runtime selection:
runtimeLocation: "in-process": ép in-process.
runtimeLocation: "helper": yêu cầu helper, fail nếu config tắt.
omitted/default: in-process.
Config:
/var/mobile/Library/TLinkauto/config.json
javascript_helper_runtime_enabled
optional later: javascript_helper_runtime_default
Không silent fallback khi manifest request helper.
runtimeInfo() cần thể hiện:
helper requested?
helper allowed?
effective runtime location
config path
config error nếu parse fail.
2. Helper Session Lifecycle

Làm rõ state machine:
idle
starting
running
stopping
completed
failed
cancelled
crashed
Đảm bảo session cleanup chạy cho mọi đường:
normal complete
JS exception
timeout
user stop
helper daemon restart
SpringBoard polling failure
Thêm sessionEnd/cleanup internal path rõ hơn thay vì cleanup rải rác.
Status nên trả thêm:
startedAtMs
endedAtMs
durationMs
exitReason
3. Native RPC Robustness

Idempotency hiện đã có, Phase 5 nên harden:
Cache theo session giới hạn 256.
Không cache request không có requestId.
Log duplicate replay rõ.
Thêm method allowlist cho helper RPC trong SpringBoard:
Chỉ execute method đã cho phép.
Chặn rawTask từ helper production path.
Phân loại side-effect methods:
safe read
input
UI
destructive/admin
Config optional:
javascript_helper_allow_admin_rpc
default false cho runShell, connectivity setters, kill app, hardware keys nếu muốn production-safe.
4. Observability

Chuẩn hóa log files:
_logs/<runId>-helper.log
_logs/latest-helper.log
maybe _logs/<runId>-rpc.log
Thêm structured summary cuối run:
state
duration
rpc count
duplicate rpc count
handles created/released
storage ops count
CLI commands:
--client-handshake
--client-status
--client-run
thêm --client-stop <sessionId> nếu chưa có.
runtimeInfo() nên expose:
nativeRPC: true
storageLocal: true
frameHandleRPC: true
imageHandleRPC: true
ocrRPC: true
autoReleaseHandles: true
5. Handle Ownership Validation

Kiểm tra kỹ frame/image ownership:
helper chỉ release handle thuộc session/run hiện tại.
releaseAllFrames/future releaseAllImages scoped, không global.
cleanup on completed/failed/cancelled/timeout.
Thêm counters:
ownedFrameCount
ownedImageCount
autoReleasedFrameCount
autoReleasedImageCount
Nếu có thể, thêm debug RPC/status để verify no leaks after session.
6. Demos & Test Matrix

Demos safe:
Helper Storage Demo
Helper Frame Color Demo
Helper OCR Demo
Helper Full Safe Smoke Demo
Demos destructive/admin để riêng, không auto-run:
Shell/Admin RPC Demo
Connectivity Setter Demo
Hardware Key Demo
Test matrix:
config off + helper manifest -> fail clear
config on + helper manifest -> helper run
JS exception -> cleanup
timeout -> cleanup
user stop -> cleanup
duplicate RPC -> no duplicate side effect
daemon restart during run -> SpringBoard fails cleanly
repeated runs -> no growing handle leak
7. Packaging/Install

Ensure config.json installed with safe default:
javascript_helper_runtime_enabled: false
Ensure install scripts preserve user config if already exists, or only seed default when missing.
Ensure helper LaunchDaemon:
single instance
no restart spam
pid/socket cleanup on reinstall.
Avoid overwriting user toggles during package upgrade if possible.
8. Decision Gate For Default

Criteria before making helper default:
All safe demos pass repeatedly.
No UI freeze after failures/timeouts/stops.
No duplicate helper daemon.
No handle leak after repeated frame/image/OCR demos.
Clear config docs.
My recommendation:
Do not make helper default in Phase 5.
Keep helper enabled only when manifest requests helper and config enables it.
Consider default switch in Phase 6 after longer device testing.
Suggested Phase 5 Implementation Order

Fix docs/config packaging mismatch from Phase 4.
Preserve/seed config.json safely in install scripts.
Add RPC allowlist and admin RPC gate.
Improve helper session status/summary logging.
Add cleanup counters and handle leak diagnostics.
Add --client-stop and maybe session debug status.
Add/verify safe demos and test matrix.
Decide whether helper can remain opt-in or move toward default in Phase 6.
Recommendation Start Phase 5 with config/install/docs hardening first. It’s low-risk and prevents test confusion. Then add RPC allowlist/admin gating before expanding more behavior.

