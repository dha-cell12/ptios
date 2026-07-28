# Rootfull License Phase 5

Phase 5 adds feature-aware application UI and latency diagnostics. The backend
task and long-running component gates from Phase 4 remain authoritative.

## UI policy

The app keeps an immutable license snapshot in memory. Scripts and Settings use
that snapshot for display and immediate interaction decisions:

- Script Play and Add require `script`.
- Stream settings require `stream`.
- Automation settings require `automation`.
- Script runtime settings require `script`.
- License activation and diagnostics remain available in every state.

The snapshot refresh runs on a serial background queue at app launch, foreground
entry, license changes, and when Scripts or Settings are opened. Signature
verification and lease file reads do not run on the main UI thread.

The UI snapshot is not a security boundary. A stale UI can only display a control
for a short time; the daemon, SpringBoard dispatcher, H264 server, scheduler and
script helper check the license again before executing protected work.

## Latency model

There are three different costs:

1. UI feature lookup is an in-memory dictionary read. It has no file, signature,
   keychain or network operation.
2. Backend feature checks normally hit the verifier cache. The cache TTL is 5
   seconds. The generation file is polled at most once every 250 ms; a Darwin
   notification invalidates the cache immediately when license state changes.
3. A cache miss loads and verifies the signed lease locally. Network access only
   occurs during activation or lease refresh, never for tap, stream frame, script
   RPC or another protected action.

Long-running components amortize checks:

- H264 session heartbeat: 5000 ms.
- Script runtime and helper heartbeat: 1000 ms.
- Scheduler: one check at launch time.

The verifier reports:

- `feature_check_count`
- `cache_hit_count` and `cache_miss_count`
- `generation_poll_interval_ms`
- `generation_poll_count`
- `feature_check_average_us` and `feature_check_max_us`
- `status_refresh_average_ms` and `status_refresh_max_ms`

The application dashboard also reports UI snapshot refresh average and maximum
milliseconds.

## Initial budgets

These are conservative test budgets, not protocol guarantees:

- Average backend feature check: at most 5000 microseconds.
- Average local lease status refresh: at most 150 milliseconds.
- UI control response: no synchronous lease verification on the main thread.

Use measured device results before tightening them. Slow storage, first-run
keychain work, debugging builds and device thermal pressure can raise the maximum
without affecting the normal cache-hit path.

## Device test

Report metrics without failing on budget:

```powershell
.\scripts\Test-TLinkRootfullLicensePhase5.ps1 `
  -HostIP "192.168.1.244" `
  -ExpectedMode enforced `
  -ExpectedState valid `
  -ExpectedAccess allowed
```

Enforce the initial budgets:

```powershell
.\scripts\Test-TLinkRootfullLicensePhase5.ps1 `
  -HostIP "192.168.1.244" `
  -ExpectedMode enforced `
  -ExpectedState valid `
  -ExpectedAccess allowed `
  -ProbeCount 100 `
  -EnforcePerformanceBudget
```

The probe uses task `250`, which passes through the automation gate without
performing a destructive action. The response itself may report an unsupported
device-info subtype; the test is concerned with the license gate and timing.

## Artifact verification

CI validates both `observe` and `enforced` packages. The Phase 5 manifest checks
compile-time mode markers, public verifier configuration, UI snapshot evidence,
performance diagnostics, Phase 4 long-running gates and absence of private
signing material.

## Residual risk

- UI snapshot state can briefly lag a generation change. Backend gates prevent
  authorization bypass.
- Metrics are process-local and reset when a process restarts.
- Average values include generation-marker reads and lock contention, but do not
  include network lease refresh.
- Runtime instrumentation is diagnostic, not anti-tamper protection. Phase 6
  now covers release coherence, signed anti-rollback state and rollout evidence;
  see `docs/license-rootfull-phase6.md`.
