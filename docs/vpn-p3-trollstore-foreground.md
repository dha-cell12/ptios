# VPN P3 TrollStore Foreground Candidate

## Outcome

VPN P3 adds the first real `NEVPNManager` candidate to StreamControl on
TrollStore. It deliberately remains an experimental, foreground-only path
until device evidence proves that the target TrollStore/iOS combination
honors the injected personal-VPN entitlement.

The path is:

```text
PC task 59 -> streamd :6000 -> 127.0.0.1:6015
  -> foreground StreamControl app (allow-vpn)
  -> NEVPNManager -> TLink-owned IKEv2 profile
```

The frozen P3 capability baseline was:

```text
vpnState=foreground_candidate
vpnQuery=app_broker_6015_with_interface_fallback
vpnControl=app_broker_6015_foreground_only
vpnBackend=nevpnmanager_ikev2_candidate
vpnBroker=StreamControl_app_6015
vpnPhase=3
vpnDiagnostics=task59_action2_base64_json_v1
vpnEntitlementProbe=foreground_app_process_via_592
vpnProfileIdentifier=tlinkauto-managed-v1
```

Live IKEv2 connect/query/disconnect was reported working on TrollStore on
2026-08-01. VPN P4 therefore promotes this path to `app_side_control` and
adds opt-in on-demand behavior. The broker remains foreground-only for new
task requests.

The legacy bytes and terminal-state semantics remain contract v1. Server and
credential fields are never accepted on port `6000` or `6015`.

## Entitlement and process boundary

Only `StreamControl` receives:

```xml
<key>com.apple.developer.networking.vpn.api</key>
<array>
    <string>allow-vpn</string>
</array>
```

`streamd` receives neither personal-VPN nor packet-tunnel entitlements. The
foreground broker probes its own signed entitlement and `NEVPNManager` class
before any query/connect/disconnect operation. A missing or stripped
entitlement returns `vpn_trollstore_entitlement_unavailable`.

The broker accepts commands only while `UIApplicationStateActive`; otherwise
it returns `vpn_foreground_app_required`. This is an honest limitation, not a
successful background-connect result. Streamd also checks the existing
short-lived foreground heartbeat before opening the broker socket, so a
suspended app fails promptly instead of consuming the transition timeout.

## Configuration

Open StreamControl, then:

```text
Settings -> Managed VPN
```

The shared IKEv2 form and Keychain code are the same as rootfull, but the
TrollStore build selects the exact access group
`StreamCtl.com.tlinkauto.streamcontrol`. Password persistent references use
`AfterFirstUnlockThisDeviceOnly`. Loopback VPN destinations are rejected.

P3 keeps on-demand disabled. Auto-reconnect is a later phase after manual
foreground connect is proven against a real IKEv2 endpoint.

## Task behavior

- `590`: asks the app broker first; if unavailable, retains the historical
  VPN-interface boolean fallback.
- `591;;1` and `591;;0`: require StreamControl in the foreground and return
  success only after `Connected` or `Disconnected` is observed.
- `592`: returns the foreground app's entitlement/manager evidence when the
  broker is reachable; otherwise it returns an explicit streamd fallback
  snapshot with `broker_ready=0`.

Task `97` reports `foreground_candidate`, not production-ready. Promotion
requires device evidence from task `592`, a saved profile, terminal-state
tests, and real traffic/DNS verification.

## Device validation

1. Install the new TIPA and open StreamControl in the foreground.
2. Open Settings -> Managed VPN, enter a real IKEv2 endpoint, save the
   profile, and approve the iOS VPN prompt.
3. Decode diagnostics:

```powershell
$raw = Invoke-TLinkTask -HostIP $iphoneIP -Task "592"
$b64 = ($raw -replace '^0;;', '').Trim()
$vpn = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($b64)
) | ConvertFrom-Json
$vpn | Format-List
$vpn.entitlements | Format-List
$vpn.manager_status | Format-List
```

Candidate-ready evidence is:

- `phase=3`
- `entitlement_probe_scope=foreground_app_process`
- `app_active=1`
- `allow_vpn=1`
- `api_exercised=1`
- `control_preflight=foreground_manager_ready`
- `profile_state=configured`

4. With StreamControl still foreground, run connect/query/disconnect:

```powershell
Invoke-TLinkTask -HostIP $iphoneIP -Task "591;;1"
Invoke-TLinkTask -HostIP $iphoneIP -Task "590"
Invoke-TLinkTask -HostIP $iphoneIP -Task "591;;0"
Invoke-TLinkTask -HostIP $iphoneIP -Task "590"
```

Expected terminal sequence is `1`, `1`, `0`, `0`. Verify egress IP and DNS
separately.

5. Background StreamControl and verify control fails with
`vpn_foreground_app_required` while `590` still returns the interface-probe
boolean.

The same checks can be collected without transitions:

```powershell
.\scripts\Test-TLinkVPNPhase3.ps1 -HostIP $iphoneIP -ExpectReady
```

After a real profile is configured and the endpoint is reachable, explicitly
enable the state-changing sequence:

```powershell
.\scripts\Test-TLinkVPNPhase3.ps1 `
  -HostIP $iphoneIP `
  -ExpectReady `
  -RunTransitions
```

If TrollStore refuses installation or task `592` reports `allow_vpn=0`, keep
the device on the previous query-only TIPA. Do not describe the candidate as
working on that device; preserve the diagnostics for the later Settings/manual
fallback track.
