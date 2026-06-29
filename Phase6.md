Phase 6 Goal Đưa helper runtime từ opt-in advanced path thành runtime ứng viên production: ổn định policy, có regression tests, có migration path rõ, và chuẩn bị quyết định có cho helper làm default hay không.

Nguyên Tắc

Không bật helper làm default ngay đầu Phase 6.
Không silent fallback khi manifest yêu cầu helper.
Không mở rộng API mới nếu lifecycle/test chưa ổn.
Ưu tiên reliability, diagnostics, automated validation.
Phase 6 Plan

Fix Phase 5 Leftovers
Thêm CLI:
--client-stop <sessionId>
Sửa docs lệch:
bỏ marker gate cũ /enable_js_helper_execution
ghi đúng config.json
cập nhật storage/frame/image/OCR đã hỗ trợ helper.
Verify install không overwrite user config.
Build A Runtime Test Harness
Thêm script/test bundle runner qua helper CLI:
direct: --run-script
daemon: --client-run
UI helper path: qua app/script player.
Chuẩn hóa expected output:
exit code
final state
log contains marker
no duplicate daemon
no stale session.
Test targets:
Helper Storage Demo
Helper Frame Color Demo
Helper OCR Demo
Helper Full Safe Smoke Demo
Helper UI RPC Demo.
Add Session/Handle Leak Verification
Sau mỗi helper run, verify:
ownedFrameCount == 0
ownedImageCount == 0
autoReleasedFrameCount hợp lý khi script throw/timeout
no stale active session.
Add helper status/debug command if needed:
--client-status --verbose
hoặc status payload expose handle counters.
Repeated-run test:
frame demo 20 lần
OCR demo 10 lần
stop mid-run
timeout mid-run.
Strengthen Failure Paths
Test and harden:
JS exception
infinite loop timeout
helper daemon killed during run
SpringBoard polling error
RPC timeout
duplicate RPC replay
admin RPC blocked.
Expected behavior:
UI không treo
script returns clear error
helper status becomes failed/cancelled/crashed
owned handles released.
Runtime Policy Finalization
Config keys:
{
  "javascript_helper_runtime_enabled": false,
  "javascript_helper_runtime_default": false,
  "javascript_helper_allow_admin_rpc": false
}
Phase 6 behavior:
runtimeLocation: "helper" + enabled true -> helper.
runtimeLocation: "helper" + enabled false -> fail clear.
no runtimeLocation -> in-process.
javascript_helper_runtime_default only experimental, not on by default.
Add docs for policy matrix.
Admin RPC Safety
Keep admin RPC disabled by default.
Confirm blocked methods:
rawTask
runShell
killApp
connectivity setters
hardware keys
scheduler/autolaunch setters if exposed.
Add negative demo/test:
Helper Admin Blocked Demo
should log helper RPC method blocked by policy.
Performance Baseline
Measure rough timing in logs:
helper startup
script eval time
RPC roundtrip count/time
frame capture + color read
OCR time.
Add summary fields if missing:
rpcAvgMs
rpcMaxMs
evalDurationMs
Goal is observability, not micro-optimization yet.
Documentation Cleanup
Update docs/tlinkauto-js-runtime.md:
runtime selection
config
supported helper APIs
unsupported/experimental APIs
admin RPC safety
troubleshooting.
Add device test checklist:
launchd helper
config on/off
run demos
read logs
cleanup config.
Release Criteria For Helper Default Decision
Required before considering default:
all safe demos pass 20 repeated runs
no duplicate helper daemon
no UI freeze on exception/timeout/stop
no frame/image handle leak
admin RPC blocked by default
config upgrade preserves user setting.
Recommendation:
End Phase 6 with helper still opt-in.
If stable, Phase 7 can introduce helper default behind javascript_helper_runtime_default.
Suggested Implementation Order

Phase 5 leftovers: docs + --client-stop.
Test harness/CLI validation.
Failure-path hardening.
Handle leak diagnostics/repeated-run tests.
Admin RPC negative tests.
Performance summary metrics.
Docs and release checklist.
Decide Phase 7 default strategy.
Deliverables

--client-stop <sessionId>
updated runtime docs
helper test checklist
safe regression demos passing
failure-mode tests passing
handle leak diagnostics in logs/status
recommendation document: keep opt-in or move to Phase 7 default experiment.
