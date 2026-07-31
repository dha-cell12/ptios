# VPN P4 On-Demand Auto-Reconnect

## Outcome

VPN P4 promotes the proven IKEv2 paths on both rootfull and TrollStore and
adds opt-in auto-reconnect with `NEOnDemandRuleConnect`. The legacy task `59`
wire contract remains version 1. Profile configuration, credentials, and the
on-demand switch remain local to the foreground settings UI.

The active paths are:

```text
rootfull:   task 59 -> tlinkautod -> 127.0.0.1:6014 -> tlinkauto-vpnd
TrollStore: task 59 -> streamd   -> 127.0.0.1:6015 -> StreamControl app
```

Both use the same TLink-owned `NEVPNManager` IKEv2 profile and shared manager.
No Packet Tunnel Provider is added.

## Policy and safety

- Auto-Reconnect defaults to off whenever a profile is newly saved.
- The user enables it in `Settings -> Managed VPN -> Auto-Reconnect`.
- Enabling creates one `NEOnDemandRuleConnect` rule for all networks, enables
  the owned profile, saves preferences, reloads them, and verifies that iOS
  persisted both the flag and at least one rule.
- Disabling clears all TLink-owned on-demand rules.
- An explicit task `591;;0` first disables on-demand and then stops the tunnel.
  This prevents iOS from reconnecting while task `59` is waiting for the
  terminal disconnected state.
- Foreign VPN profiles are never modified.
- Server, username, password, certificates, and on-demand control are not
  accepted over task `59`, port `6000`, `6014`, or `6015`.

The disconnect behavior is intentional: after an explicit remote disconnect,
Auto-Reconnect is off until the user enables it again in the local UI.

## Diagnostics and capability contract

Task `97` reports:

```text
vpnPhase=4
vpnOnDemand=local_ui_connect_all_networks
vpnDisconnectPolicy=explicit_disconnect_disables_on_demand
```

Rootfull additionally reports `vpnState=full_control`. TrollStore reports
`vpnState=app_side_control`; its connect/disconnect broker remains
foreground-only, while an already-enabled iOS on-demand policy can reconnect
without a new task request.

Task `592` remains base64 JSON contract v1 and adds:

```text
on_demand_policy=local_ui_connect_all_networks_explicit_disconnect_disables
manager_status.on_demand_enabled
manager_status.on_demand_rule_count
manager_status.on_demand_mode
```

`diagnostics_source` identifies `rootfull_broker`,
`foreground_app_broker`, or `streamd_interface_fallback`. TrollStore task
`592` always makes one bounded five-second broker attempt before returning the
fallback snapshot. A fallback snapshot does not claim that on-demand is off;
it reports `broker_last_error` and `foreground_heartbeat_fresh` because only
the app process can read authoritative `NEVPNManager` state.

These are additive fields. Existing task `590`, `591;;0`, `591;;1`, and `592`
request and response formats do not change.

## Device validation

First save a real profile, connect successfully, and enable Auto-Reconnect in
the local Managed VPN screen. Then run:

```powershell
.\scripts\Test-TLinkVPNPhase4.ps1 `
  -HostIP $iphoneIP `
  -Runtime rootfull `
  -ExpectOnDemand
```

For TrollStore, keep StreamControl foreground while collecting diagnostics:

```powershell
.\scripts\Test-TLinkVPNPhase4.ps1 `
  -HostIP $iphoneIP `
  -Runtime trollstore `
  -ExpectOnDemand
```

Validate reconnection separately by changing the active network or briefly
interrupting reachability, then confirm task `590` returns `0;;1` and verify
real egress IP/DNS through the VPN.

The destructive policy check deliberately disconnects the VPN and verifies
that on-demand was cleared:

```powershell
.\scripts\Test-TLinkVPNPhase4.ps1 `
  -HostIP $iphoneIP `
  -Runtime trollstore `
  -ExpectOnDemand `
  -RunDisconnect
```

Re-enable Auto-Reconnect in the local UI after this check if desired.

## Promotion evidence

On 2026-08-01, live IKEv2 connect/query/disconnect was reported working on
both rootfull and TrollStore. P4 therefore promotes the implementation state,
but on-demand reconnection still requires its own device evidence: persisted
rule, network interruption, reconnect, and real traffic/DNS verification.
