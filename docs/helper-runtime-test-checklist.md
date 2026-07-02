# Helper Runtime Phase 6 Test Checklist

## Preconditions

1. Build and install the package on device.
2. Confirm helper daemon is loaded.
3. Enable helper runtime in `/var/mobile/Library/TLinkauto/config.json`:

```json
{
  "javascript_helper_runtime_enabled": true,
  "javascript_helper_runtime_default": false,
  "javascript_helper_allow_admin_rpc": false
}
```

Do not enable admin RPC for the default safe regression run.

## Basic CLI checks

```sh
/usr/libexec/tlinkauto-jsd --client-handshake
/usr/libexec/tlinkauto-jsd --client-status
```

Expected: JSON output, daemon reachable, one active session at most.

## Safe regression

```sh
/usr/libexec/tlinkauto-jsd --client-run-regression safe --repeat 20 --json
```

Expected:

- Helper Storage Demo passes.
- Helper Frame Color Demo passes.
- Helper OCR Demo passes or logs that OCR path executed.
- Helper Full Safe Smoke Demo passes.
- `blockedRpcCount == 0` for safe demos.
- `pendingNativeRPC == false` at final status.
- Logs contain `[HELPER_TEST_PASS]` marker.

## Admin blocked regression

With `javascript_helper_allow_admin_rpc` still false:

```sh
/usr/libexec/tlinkauto-jsd --client-run-regression admin-blocked --repeat 5 --json
```

Expected:

- Final state is `completed`.
- Log contains `[HELPER_TEST_PASS] Helper Admin Blocked Demo`.
- `blockedRpcCount >= 1`.

## Failure regression

```sh
/usr/libexec/tlinkauto-jsd --client-run-regression exception,timeout --repeat 3 --json
```

Expected:

- Exception demo finishes `failed` with clear lastError.
- Timeout demo in CLI harness is a controlled failure simulation and should finish `failed` with clear lastError. Real SpringBoard/UI timeout should be tested separately with a long-running script and manifest `helperTimeoutMs`.
- UI does not freeze.
- Final status has `pendingNativeRPC == false`.

## Stop mid-run manual test

Start long-running helper demo in one shell:

```sh
/usr/libexec/tlinkauto-jsd --client-run \
  "/var/mobile/Library/TLinkauto/scripts/examples/Helper Stop Mid Run Demo.tl/main.js" \
  "/var/mobile/Library/TLinkauto/scripts/examples/Helper Stop Mid Run Demo.tl" \
  "/var/mobile/Library/TLinkauto/scripts/examples/Helper Stop Mid Run Demo.tl/manifest.json"
```

In another shell, get the session and stop it:

```sh
/usr/libexec/tlinkauto-jsd --client-status
/usr/libexec/tlinkauto-jsd --client-stop <activeSessionId>
/usr/libexec/tlinkauto-jsd --client-status
```

Expected:

- State becomes `stopping`, then `cancelled` or another terminal failure state.
- No stale `pendingNativeRPC`.
- UI remains responsive.

## Leak diagnostics

After repeated safe/failure tests, check `device.runtimeInfo()` from a normal JS script or inspect SpringBoard logs.

Expected:

- `ownedFrameCount == 0` after helper run cleanup.
- `ownedImageCount == 0` after helper run cleanup.
- `helperAutoReleasedFrameCount`/`helperAutoReleasedImageCount` are reasonable for exception/timeout paths.
- No stale active session in `--client-status`.

## Timing baseline

Inspect final helper summary in `_logs/latest-helper.log`.

Expected fields:

- `durationMs`
- `rpcCount`
- `rpcAvgMs`
- `rpcMaxMs`
- `evalDurationMs`
- `blockedRpcCount`
- `storageOpsCount`

Use these for baseline observation only; Phase 6 does not require micro-optimization.

## Release criteria before Phase 7 default experiment

- Safe demos pass 20 repeated runs.
- Admin RPC is blocked by default.
- Exception/timeout/stop paths do not freeze UI.
- No frame/image handle leak.
- Config upgrade preserves user setting.
- No duplicate helper daemon/session.

Recommendation: keep helper opt-in at the end of Phase 6. Use Phase 7 for any `javascript_helper_runtime_default` experiment.


# Phase 7 default experiment checklist

## Controlled default config

Only use this after Phase 6 baseline passes:

```json
{
  "javascript_helper_runtime_enabled": true,
  "javascript_helper_runtime_default": true,
  "javascript_helper_allow_admin_rpc": false
}
```

Package defaults must remain false. Rollback is config-only by setting `javascript_helper_runtime_default` to false.

## CLI helper compatibility baseline

```sh
/usr/libexec/tlinkauto-jsd --client-run-regression phase7 --repeat 20 --json
```

This validates the safe helper demos, `Helper Default Experiment Demo.tl`, admin-blocked behavior, and controlled failure demos under the helper daemon. It does not test SpringBoard runtime selection because the native runner invokes the daemon directly.

## JS-only runtime cleanup checks

- `.py` scripts and `runtime: "python"` fail immediately with a migration message.
- No runtime path calls `/bin/python3`, `PYTHONPATH=/usr/lib/python3.7`, or `killall python3`.
- The package does not contain `/usr/lib/python3.7`, `/bin/python3*`, bundled `.py` examples, or `/var/mobile/Library/TLinkauto/tools/run-helper-tests.py`.
- Existing user `.py` scripts are preserved on upgrade but are no longer runnable.
- New script creation generates `main.js` and `manifest.json`.

## Actual runtime-selection tests from app/script player

Use `Helper Default Experiment Demo.tl`, whose manifest intentionally omits `runtimeLocation` and `helperRuntimeEnabled`.

Expected matrix:

1. default false -> demo runs in-process.
2. default true + helper enabled true -> demo runs in helper.
3. default true + helper enabled false -> demo falls back in-process.
4. `runtimeLocation: "in-process"` -> always in-process.
5. `runtimeLocation: "helper"` + helper disabled -> fail clear.
6. default true + helper daemon start/busy failure -> fallback in-process with `helperDefaultFallbackReason`.
7. explicit helper + helper daemon start/busy failure -> fail clear, no fallback.

Inspect `device.runtimeInfo()` for:

- `helperExplicitRequested`
- `helperDefaultRequested`
- `helperDefaultFallback`
- `helperDefaultFallbackReason`
- `effectiveRuntimeLocation`

## Compatibility manifest audit

`JavaScriptCore API Demo.tl` is pinned to `runtimeLocation: "in-process"` because it exercises legacy/in-process API behavior. New scripts should explicitly choose:

- `runtimeLocation: "in-process"` for in-process-only behavior.
- `runtimeLocation: "helper"` when helper is required and failure is preferred over fallback.
- omitted runtime only when safe under default experiment.

## Phase 7 decision criteria

Helper default can be recommended only when:

- Phase 6 safe x20 still passes.
- Phase 7 default compatibility x20 passes.
- Admin RPC remains blocked by default.
- rawTask remains blocked from helper production path.
- Exception/timeout/stop paths do not freeze UI.
- Config rollback works without reinstall.
- No duplicate daemon, stale session, pending RPC, or frame/image leak.

Recommendation remains controlled deployment only; package config should not auto-enable helper default.
