# TLinkauto JavaScriptCore Runtime

## Runtime selection policy

JavaScriptCore scripts run in-process by default.

Helper runtime is opt-in and requires both:

- manifest requests helper execution with `runtimeLocation: "helper"` or `helperRuntimeEnabled: true`; and
- `/var/mobile/Library/TLinkauto/config.json` enables `javascript_helper_runtime_enabled`.

Supported runtimeLocation values:

- `"in-process"`: force in-process execution.
- `"helper"`: request helper execution. If config disables helper runtime, execution fails clearly.
- omitted/default: in-process.

Phase 5 does not make helper runtime the default. `javascript_helper_runtime_default` is reserved/report-only for now.

## Config

```json
{
  "javascript_helper_runtime_enabled": false,
  "javascript_helper_runtime_default": false,
  "javascript_helper_allow_admin_rpc": false
}
```

`javascript_helper_allow_admin_rpc` gates privileged helper-originated RPC. It is false by default.

## runtimeInfo

`device.runtimeInfo()` reports manifest metadata, helper requested/allowed/effective state, config path/error, helper daemon reachability, helper capabilities, and helper counters.

Capability flags include `nativeRPC`, `storageLocal`, `frameHandleRPC`, `imageHandleRPC`, `ocrRPC`, and `autoReleaseHandles`.

## Support matrix

| Feature | In-process runtime | Helper runtime |
| --- | --- | --- |
| Pure JavaScript / console / require / include | Yes | Yes |
| Native RPC through SpringBoard | Direct native bridge | Yes, via helper RPC bridge |
| Bundle-local storage APIs | Yes | Yes, helper-local and bundle-relative |
| Frame handle APIs | Yes | Yes, via session-owned RPC handles |
| Image handle APIs | Yes | Yes, via session-owned RPC handles |
| OCR APIs | Yes | Yes, via RPC wrappers |
| Admin/destructive APIs | Available to in-process scripts | Blocked by default; requires `javascript_helper_allow_admin_rpc` where allowed |

## Helper native RPC policy

Helper scripts can call safe RPC APIs through SpringBoard. Raw task execution is blocked from the helper production path. Privileged/admin RPC is blocked unless `javascript_helper_allow_admin_rpc` is true.

Blocked RPC returns `{ ok: false, error: "helper RPC method blocked by policy", reason: ... }`.

## Helper-local storage

Helper-local storage is bundle-relative and path-safe:

- `device.readText(path)`
- `device.writeText(path, text)`
- `device.readJSON(path)`
- `device.writeJSON(path, value)`
- `device.fileExists(path)`
- `device.deleteFile(path)`

Paths must remain inside the current script bundle. Bundle metadata/source files are protected from modification.

## Frame, image, and OCR RPC

Helper runtime supports frame/image/OCR wrappers:

- `captureFrame`, `releaseFrame`, `releaseAllFrames`
- `framePickColor`, `framePickColors`, `frameFindColor`, `frameIsColors`, `frameFindMultiColor`
- `openImage`, `captureImage`, `releaseImage`, `findImageInFrame`
- `ocrLanguages`, `ocrFrame`, `ocr`

Frame and image handles include owner metadata. Helper cleanup is session-scoped and does not globally release unrelated in-process handles.

## Helper client CLI

`tlinkauto-jsd` supports small client commands for test/diagnostics:

```sh
/usr/libexec/tlinkauto-jsd --client-handshake
/usr/libexec/tlinkauto-jsd --client-status
/usr/libexec/tlinkauto-jsd --client-run <scriptPath> <bundlePath> [manifestPath]
/usr/libexec/tlinkauto-jsd --client-stop <sessionId>
```

`--client-stop <sessionId>` sends `kTLinkJSHelperCmdStop` to the helper daemon, prints the JSON response, and exits `0` when the request succeeds or `2` on failure.

## Logs and observability

Helper logs are written under the bundle `_logs` directory:

- `_logs/<runId>-helper.log`
- `_logs/latest-helper.log`

Phase 5 appends a structured summary at the end of helper runs with state, exit reason, duration, RPC counts, blocked RPC counts, and storage operation counts.

## Safe demos

Safe demos intended for repeated validation:

- Helper Storage Demo
- Helper Frame Color Demo
- Helper OCR Demo
- Helper Full Safe Smoke Demo

## Phase 5 test matrix

1. config off + helper manifest -> fail clear.
2. config on + helper manifest -> helper run.
3. JavaScript exception -> helper finishes failed and cleanup runs.
4. timeout/user stop -> helper finishes cancelled/failed and cleanup runs.
5. duplicate native RPC request id -> cached replay, no duplicate side effect.
6. same request id with different payload -> collision error.
7. admin RPC while admin gate false -> blocked by policy.
8. admin RPC while admin gate true -> allowed.
9. repeated frame/image/OCR demos -> no growing handle leak.
10. daemon restart/poll failure during run -> SpringBoard fails cleanly.

## Native regression harness

The helper regression harness is built into `tlinkauto-jsd` so the iOS package does not depend on Python:

```sh
/usr/libexec/tlinkauto-jsd --client-run-regression <safe|phase7|all|test-list> [--repeat N] [--json]
```

Run safe repeated regression:

```sh
/usr/libexec/tlinkauto-jsd --client-run-regression safe --repeat 20 --json
```

Run admin blocked regression while `javascript_helper_allow_admin_rpc` is false:

```sh
/usr/libexec/tlinkauto-jsd --client-run-regression admin-blocked --repeat 5 --json
```

Run failure-path regression:

```sh
/usr/libexec/tlinkauto-jsd --client-run-regression exception,timeout --repeat 3 --json
```

See `docs/helper-runtime-test-checklist.md` for the full device checklist, including the manual stop-mid-run flow using `--client-status` and `--client-stop <sessionId>`.

## Phase 7 default experiment

Phase 7 makes `javascript_helper_runtime_default` functional as a controlled experiment. The package default remains false and rollback is config-only.

Default experiment config for controlled deployments:

```json
{
  "javascript_helper_runtime_enabled": true,
  "javascript_helper_runtime_default": true,
  "javascript_helper_allow_admin_rpc": false
}
```

Rollback without reinstall:

```json
{
  "javascript_helper_runtime_default": false
}
```

Runtime selection matrix:

| Manifest/config | Result |
| --- | --- |
| `runtimeLocation: "helper"` + helper enabled false | Fail clear |
| `runtimeLocation: "helper"` + helper enabled true | Helper runtime |
| `runtimeLocation: "in-process"` | In-process runtime |
| omitted runtime + default false | In-process runtime |
| omitted runtime + default true + helper enabled true | Helper runtime |
| omitted runtime + default true + helper enabled false | In-process fallback |
| omitted runtime + default true + helper start/busy failure | In-process fallback with warning |
| explicit helper + helper start/busy failure | Fail clear, no fallback |

Use `runtimeLocation: "in-process"` for legacy scripts that depend on in-process-only behavior. Use `runtimeLocation: "helper"` for scripts that must fail rather than silently run in-process when helper is disabled. Omit `runtimeLocation` only for scripts that are safe under the default experiment.

`device.runtimeInfo()` reports Phase 7 fields: `helperExplicitRequested`, `helperDefaultRequested`, `helperDefaultFallback`, and `helperDefaultFallbackReason`.

Admin RPC remains disabled by default and raw task execution remains blocked from the helper production path.

The default experiment compatibility demo is:

```text
Helper Default Experiment Demo.bdl
```

CLI note: `--client-run` invokes the helper daemon directly, so it validates helper compatibility and timing but does not exercise SpringBoard runtime selection. Test the actual default-selection path from the app/script player.

Run Phase 7 helper compatibility baseline:

```sh
/usr/libexec/tlinkauto-jsd --client-run-regression phase7 --repeat 20 --json
```

## Python runtime removal

The iOS package/runtime is JavaScriptCore-first. Python playback has been removed from the iOS runtime and package payload.

- `.py` entries and manifests with `runtime: "python"` fail immediately with a migration message.
- Existing user `.py` scripts are preserved on upgrade, but they are no longer runnable.
- New scripts created in the app use `main.js` plus `manifest.json`.
- The iOS package no longer includes `/usr/lib/python3.7`, `/bin/python3*`, bundled `.py` examples, or the old Python helper test harness.

Python-based PC/dev tooling may remain in the source tree as legacy tooling, but it is not part of the iOS runtime path.
