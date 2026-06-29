#!/usr/bin/env python3
import argparse, json, subprocess, sys
from pathlib import Path

DEFAULT_BIN = "/usr/libexec/tlinkauto-jsd"
DEFAULT_ROOT = "/var/mobile/Library/TLinkauto/scripts/examples"
PASS = "[HELPER_TEST_PASS]"
FAIL = "[HELPER_TEST_FAIL]"
TESTS = {
  "storage": ("Helper Storage Demo.bdl", "completed", "Helper Storage Demo", 0),
  "frame": ("Helper Frame Color Demo.bdl", "completed", "Helper Frame Color Demo", 0),
  "ocr": ("Helper OCR Demo.bdl", "completed", "Helper OCR Demo", 0),
  "full": ("Helper Full Safe Smoke Demo.bdl", "completed", "Helper Full Safe Smoke Demo", 0),
  "default-compat": ("Helper Default Experiment Demo.bdl", "completed", "Helper Default Experiment Demo", 0),
  "admin-blocked": ("Helper Admin Blocked Demo.bdl", "completed", "Helper Admin Blocked Demo", 1),
  "exception": ("Helper JS Exception Demo.bdl", "failed", "", 0),
  "timeout": ("Helper Timeout Demo.bdl", "failed", "", 0),
}
SAFE = ["storage", "frame", "ocr", "full"]
PHASE7 = ["default-compat"]

def run(cmd, timeout=90):
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout)
    out = (p.stdout or "").strip()
    data = {}
    if out:
        try: data = json.loads(out.splitlines()[-1])
        except Exception: data = {}
    return p.returncode, out, (p.stderr or "").strip(), data

def payload(data):
    if isinstance(data.get("response"), dict) and isinstance(data["response"].get("payload"), dict):
        return data["response"]["payload"]
    return data if isinstance(data, dict) else {}

def read_log(p):
    path = p.get("consoleLatestLogPath") or p.get("consoleLogPath") or ""
    if not path: return "", ""
    try: return path, Path(path).read_text(errors="replace")
    except Exception as e: return path, "log read failed: %s" % e

def run_one(bin_path, root, name):
    b, expect, marker, min_blocked = TESTS[name]
    bundle = Path(root) / b
    cmd = [bin_path, "--client-run", str(bundle / "main.js"), str(bundle), str(bundle / "manifest.json")]
    code, out, err, data = run(cmd)
    p = payload(data)
    log_path, log_text = read_log(p)
    checks = {
      "state": p.get("state") == expect or (name == "timeout" and p.get("state") in ("failed", "cancelled", "timeout")),
      "marker": (not marker) or (PASS in log_text and marker in log_text),
      "noFailMarker": FAIL not in log_text,
      "blockedRpcCount": int(p.get("blockedRpcCount", 0) or 0) >= min_blocked,
      "noPendingNativeRPC": not bool(p.get("pendingNativeRPC", False)),
    }
    return {"ok": all(checks.values()), "test": name, "state": p.get("state"), "exitReason": p.get("exitReason"), "durationMs": p.get("durationMs"), "rpcCount": p.get("rpcCount"), "blockedRpcCount": p.get("blockedRpcCount"), "rpcAvgMs": p.get("rpcAvgMs"), "rpcMaxMs": p.get("rpcMaxMs"), "evalDurationMs": p.get("evalDurationMs"), "checks": checks, "logPath": log_path, "returnCode": code, "stderr": err}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--daemon-bin", default=DEFAULT_BIN)
    ap.add_argument("--examples-root", default=DEFAULT_ROOT)
    ap.add_argument("--only", default="safe")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    names = SAFE if a.only == "safe" else (PHASE7 if a.only == "phase7" else (list(TESTS) if a.only == "all" else [x.strip() for x in a.only.split(",") if x.strip()]))
    results = []
    for i in range(a.repeat):
        for name in names:
            r = run_one(a.daemon_bin, a.examples_root, name)
            r["iteration"] = i + 1
            results.append(r)
            if not a.json: print(("PASS" if r["ok"] else "FAIL"), name, "iter", i + 1, r["checks"])
    summary = {}
    for r in results:
        name = r.get("test", "unknown")
        bucket = summary.setdefault(name, {"runs": 0, "ok": 0, "durationMs": [], "rpcAvgMs": [], "rpcMaxMs": [], "evalDurationMs": []})
        bucket["runs"] += 1
        if r.get("ok"): bucket["ok"] += 1
        for key in ("durationMs", "rpcAvgMs", "rpcMaxMs", "evalDurationMs"):
            v = r.get(key)
            if isinstance(v, (int, float)): bucket[key].append(v)
    for bucket in summary.values():
        for key in ("durationMs", "rpcAvgMs", "rpcMaxMs", "evalDurationMs"):
            vals = bucket.pop(key)
            bucket[key + "Avg"] = (sum(vals) / len(vals)) if vals else 0
            bucket[key + "Max"] = max(vals) if vals else 0
    report = {"ok": all(r["ok"] for r in results), "summary": summary, "results": results}
    if a.json: print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["ok"] else 2
if __name__ == "__main__": sys.exit(main())
