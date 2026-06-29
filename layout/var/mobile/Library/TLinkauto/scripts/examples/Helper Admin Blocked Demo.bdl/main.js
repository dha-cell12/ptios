console.log("[HELPER_TEST_START] Helper Admin Blocked Demo");
var r = device.runShell("echo phase6-admin-test", 2);
console.log("admin result", r);
if (r && r.ok) throw new Error("admin RPC unexpectedly allowed");
var text = String((r && (r.error || r.reason)) || "");
if (text.indexOf("blocked") < 0 && text.indexOf("policy") < 0) throw new Error("admin RPC failed without policy block");
console.log("[HELPER_TEST_PASS] Helper Admin Blocked Demo");
