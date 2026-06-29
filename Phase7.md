Mục Tiêu Phase 7

Chốt helper runtime là production-ready candidate.
Thử nghiệm javascript_helper_runtime_default theo rollout an toàn.
Không mở admin RPC mặc định.
Không mở rawTask.
Không thêm API mới trừ bugfix/diagnostics nhỏ.
Kết thúc bằng quyết định rõ:
giữ opt-in, hoặc
bật helper default theo config/experiment.
Phase 7 Plan

Baseline Verification
Chạy lại Phase 6 harness trên device thật:
safe x20
admin-blocked x5
exception/timeout x3
manual stop mid-run
Xác nhận:
no duplicate helper daemon
no stale active session
pendingNativeRPC == false
no frame/image leak qua runtimeInfo()
logs có summary metrics.
Production Default Experiment
Dùng config:
{
  "javascript_helper_runtime_enabled": true,
  "javascript_helper_runtime_default": true,
  "javascript_helper_allow_admin_rpc": false
}
Chỉ áp dụng cho scripts JavaScriptCore không force runtimeLocation: "in-process".
Không thay đổi behavior của .raw/.py.
Manifest có runtimeLocation: "in-process" vẫn phải chạy in-process.
Manifest có runtimeLocation: "helper" vẫn fail rõ nếu helper disabled.
Runtime Selection Hardening
Kiểm tra logic cuối:
runtimeLocation: "helper" + enabled false → fail clear.
runtimeLocation: "helper" + enabled true → helper.
runtimeLocation: "in-process" → in-process.
omitted + javascript_helper_runtime_default: false → in-process.
omitted + javascript_helper_runtime_default: true + helper enabled → helper.
omitted + default true + helper disabled → nên in-process hoặc fail?
Khuyến nghị: in-process, vì default experiment không phải explicit request.
Ghi rõ distinction:
explicit helper request thì fail nếu disabled.
default helper experiment thì fallback in-process nếu helper disabled/unavailable.
Rollback Safety
Đảm bảo chỉ cần sửa config để rollback:
{
  "javascript_helper_runtime_default": false
}
Không cần reinstall.
Nếu helper daemon unreachable trong default mode:
log warning rõ.
fallback in-process nếu script không explicit helper.
Nếu explicit helper thì vẫn fail clear.
Compatibility Pass
Chạy demo cũ/in-process:
JavaScriptCore API Demo
helper demos
existing record/playback flows
Kiểm tra app/UI không bị ảnh hưởng.
Kiểm tra webtango/bridge route không liên quan bị đổi.
Performance Decision
Thu summary từ harness:
durationMs
rpcCount
rpcAvgMs
rpcMaxMs
evalDurationMs
So sánh:
helper startup overhead
frame/color demo
full safe smoke
OCR path
Không tối ưu sâu, chỉ dùng để quyết định default có chấp nhận được không.
Failure Rollout Criteria
Helper default chỉ được coi là ổn nếu:
safe x20 pass
frame x20 no leak
OCR x10 pass hoặc unavailable rõ
admin blocked
exception/timeout/stop không treo UI
config rollback hoạt động
no duplicate daemon
no stale session.
Docs Finalization
Cập nhật docs:
Phase 7 default experiment
config matrix
rollback command/config
khi nào dùng runtimeLocation: "in-process"
khi nào dùng runtimeLocation: "helper"
helper default vẫn không bật admin RPC
Thêm release note:
helper runtime production candidate
default controlled by javascript_helper_runtime_default.
Final Decision
Nếu pass ổn định:
Kết thúc Phase 7 với recommendation: có thể bật helper default cho controlled deployments.
Nếu còn lỗi leak/timeout/stale session:
Kết thúc Phase 7 với helper vẫn opt-in.
Không kéo dài thêm feature phase.
Không Làm Trong Phase 7

Không thêm API mới.
Không mở admin RPC mặc định.
Không mở rawTask.
Không auto-enable helper default trong package config mặc định nếu chưa có đủ test.
Không hard fallback silent cho explicit helper request.
Không sửa lớn architecture helper/router.
